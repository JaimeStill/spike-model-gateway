// Package retry is the spike's proof that go-ai's retry policy, as infer sets it by default, rides
// out the gateway's own refusals: its 429s, with Retry-After and x-ratelimit-*, and its in-flight
// limit's 503 "request limit exceeded", with none. It is the spike's only authored Go, and imports
// go-ai read-only, at a released tag (go.mod).
//
// Each test is one case, and runs only while RETRY_CASE names it, since each needs its probes
// overlay or condition live on the gateway (gateway/agentgateway/probes/); without it the test
// skips, so `go test` in the check skips them all. scripts/clients-lib.sh's retry_case runs one
// case with the environment it needs:
//
//   - RETRY_CASE: the live case, rate-limit-agent, embedding-burst, in-flight-1, or bulk-rate-low;
//     any other value fails the run (TestMain), rather than skipping every test.
//   - RETRY_KEY_FILE: the path of the gateway key's file, .state/agentgateway/keys/<name>, read by
//     the test itself, so the key is never in a process's argv; nothing here prints it. Nor an
//     address: an error's text, which a transport failure fills with the gateway's tailnet
//     address, is printed and tabled with each IP address as <addr> (scrub).
//   - RETRY_KEY_IN: bearer, the default, sends the key as the bearer token; header sends it as
//     `x-api-key: <key>`, for the key-header overlay, as clients-lib.sh's CLIENTS_KEY_IN does.
//   - RETRY_AGENT_BASE_URL and RETRY_EMBEDDING_BASE_URL: each alias's base URL on the gateway.
//   - RETRY_TABLE: optional, a file the per-attempt table is written to, besides t.Log.
//
// A recording transport under go-ai's client keeps every attempt: when it started and its reply
// arrived, its status, the reply's headers, whether a refused reply's body holds the in-flight
// marker, and its Retry-After. A case passes only if every refused attempt carries a marker only
// the gateway gives (x-ratelimit-limit, -remaining, and -reset on a 429, which Azure doesn't
// send, rather than any x-ratelimit-* name; the body marker on a 503), the call's last attempt
// answers 200 (but bulk-rate-low's refused call), and each retry starts no sooner than the refused
// attempt's Retry-After after its reply, when it gave one. The table, with no secret in it, is
// for cross-checking each attempt against the gateway's access log.
package retry

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"maps"
	"net/http"
	"os"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/standards-lab/go-ai"
	"github.com/standards-lab/go-ai/format/completions"
	"github.com/standards-lab/go-ai/protocol"
)

// inFlightMarker is the body of agentgateway's in-flight refusal, 503 "request limit exceeded"
// (probes/in-flight-1.yaml); a row's 503 doesn't hold it.
const inFlightMarker = "request limit exceeded"

// inferDefault is infer's default retry policy at tools/infer/v0.2.0: 3 attempts, the first wait
// at most 500 ms, every wait and the longest Retry-After honored at most 30 s
// (tools/infer/README.md, "Retries").
var inferDefault = ai.RetryPolicy{MaxAttempts: 3, BaseDelay: 500 * time.Millisecond, MaxDelay: 30 * time.Second}

// attempt is one request the transport sent, and its reply.
type attempt struct {
	call       string
	n          int // the attempt's number within its call, from 1
	start      time.Time
	reply      time.Time // when the reply's header arrived, or the transport failed
	status     int       // 0 when the transport failed
	header     http.Header
	marker     bool // a refused reply's body holds inFlightMarker
	retryAfter string
	err        string // the transport's failure
}

// gatewayRateHeaders are the headers agentgateway's local rate limit adds to every reply on a
// limited route, its 429s among them: x-ratelimit-limit, x-ratelimit-remaining, and
// x-ratelimit-reset, by these exact names (the recorded tables under .state/answer/retry/). A row
// sends none. Azure OpenAI sends x-ratelimit-* too, but only names with a -requests or -tokens
// suffix (x-ratelimit-limit-requests, x-ratelimit-remaining-tokens, and the rest), and none of
// these three (learn.microsoft.com, "Manage Azure OpenAI in Microsoft Foundry Models quota",
// "Rate limit response headers", read 2026-11-19), so a prefix alone marks no reply as the
// gateway's.
var gatewayRateHeaders = []string{"X-Ratelimit-Limit", "X-Ratelimit-Remaining", "X-Ratelimit-Reset"}

// rateLimited reports whether the reply carries every one of gatewayRateHeaders, by exact name:
// the gateway's local rate limit, not a row's or Azure's.
func (a *attempt) rateLimited() bool {
	for _, name := range gatewayRateHeaders {
		if len(a.header.Values(name)) == 0 {
			return false
		}
	}
	return true
}

// attempts is the log every recorder of a case writes to, in the order the replies arrived.
type attempts struct {
	mu   sync.Mutex
	list []*attempt
}

func (l *attempts) add(a *attempt) {
	l.mu.Lock()
	defer l.mu.Unlock()
	for _, b := range l.list {
		if b.call == a.call {
			a.n++
		}
	}
	a.n++
	l.list = append(l.list, a)
}

// calls returns each call's attempts in the order they started, by call name.
func (l *attempts) calls() map[string][]*attempt {
	l.mu.Lock()
	defer l.mu.Unlock()
	m := map[string][]*attempt{}
	for _, a := range l.list {
		m[a.call] = append(m[a.call], a)
	}
	for _, as := range m {
		slices.SortFunc(as, func(x, y *attempt) int { return x.start.Compare(y.start) })
	}
	return m
}

// callKey names a request's call in its context, which go-ai passes to every attempt.
type callKey struct{}

func withCall(ctx context.Context, call string) context.Context {
	return context.WithValue(ctx, callKey{}, call)
}

// recorder is an http.RoundTripper that records every attempt in log, then calls onReply, when
// set, with it.
type recorder struct {
	base    http.RoundTripper
	log     *attempts
	onReply func(*attempt)
}

func (r *recorder) RoundTrip(req *http.Request) (*http.Response, error) {
	call, _ := req.Context().Value(callKey{}).(string)
	a := &attempt{call: call, start: time.Now()}
	resp, err := r.base.RoundTrip(req)
	a.reply = time.Now()
	if err != nil {
		a.err = scrub(err)
	} else {
		a.status = resp.StatusCode
		a.header = resp.Header.Clone()
		a.retryAfter = resp.Header.Get("Retry-After")
		// A refused reply's body is short, read whole for the marker and handed on unchanged; a
		// 2xx's, maybe a stream, is left alone.
		if resp.StatusCode/100 != 2 {
			body, rerr := io.ReadAll(resp.Body)
			resp.Body.Close()
			a.marker = bytes.Contains(body, []byte(inFlightMarker))
			resp.Body = io.NopCloser(bytes.NewReader(body))
			if rerr != nil {
				a.err = scrub(rerr)
			}
		}
	}
	r.log.add(a)
	if r.onReply != nil {
		r.onReply(a)
	}
	return resp, err
}

// address is an IPv4 address, or an IPv6 one in brackets, as a dial error names the host it
// reached: gb10-2's tailnet address, which nothing here prints.
var address = regexp.MustCompile(`\b\d{1,3}(\.\d{1,3}){3}\b|\[[0-9A-Fa-f]*:[0-9A-Fa-f:.]*(%[\w.-]+)?\]`)

// scrub is err's text with each IP address replaced by <addr>, for t.Log and the table.
func scrub(err error) string {
	return address.ReplaceAllString(err.Error(), "<addr>")
}

// cases is every live case, by RETRY_CASE's value.
var cases = []string{"rate-limit-agent", "embedding-burst", "in-flight-1", "bulk-rate-low"}

// TestMain refuses a RETRY_CASE that names no case, which would otherwise skip every test and pass.
func TestMain(m *testing.M) {
	if c := os.Getenv("RETRY_CASE"); c != "" && !slices.Contains(cases, c) {
		fmt.Fprintf(os.Stderr, "RETRY_CASE is %q, not a case: %s\n", c, strings.Join(cases, ", "))
		os.Exit(2)
	}
	os.Exit(m.Run())
}

// live skips the test unless RETRY_CASE names its case, and returns the base URL variable's value
// for alias.
func live(t *testing.T, name, alias string) string {
	t.Helper()
	if os.Getenv("RETRY_CASE") != name {
		t.Skipf("RETRY_CASE isn't %s: the case needs its overlay or condition live on the gateway", name)
	}
	v := "RETRY_" + strings.ToUpper(alias) + "_BASE_URL"
	base := os.Getenv(v)
	if base == "" {
		t.Fatalf("%s is unset", v)
	}
	return base
}

// newClient returns a Chat Completions client of baseURL under policy, sending through a recorder
// into log, with the key RETRY_KEY_FILE holds.
func newClient(t *testing.T, baseURL string, log *attempts, policy ai.RetryPolicy, onReply func(*attempt)) *ai.Client {
	t.Helper()
	path := os.Getenv("RETRY_KEY_FILE")
	if path == "" {
		t.Fatal("RETRY_KEY_FILE is unset")
	}
	raw, err := os.ReadFile(path)
	if err != nil {
		// The error names the path, never the key.
		t.Fatalf("reading the key: %v", err)
	}
	key := strings.TrimSpace(string(raw))
	if key == "" {
		t.Fatalf("%s is empty", path)
	}
	opts := ai.Options{Retry: policy}
	switch in := os.Getenv("RETRY_KEY_IN"); in {
	case "", "bearer":
		opts.Token = func(context.Context) (string, error) { return key, nil }
	case "header":
		opts.Header = http.Header{"X-Api-Key": {key}}
	default:
		t.Fatalf("RETRY_KEY_IN is %q, not bearer or header", in)
	}
	base := http.DefaultTransport.(*http.Transport).Clone()
	hc := &http.Client{Transport: &recorder{base: base, log: log, onReply: onReply}}
	c, err := ai.New(baseURL, hc, completions.New(completions.Options{}), opts)
	if err != nil {
		t.Fatalf("ai.New: %v", err)
	}
	return c
}

// chat is a short chat request to the alias.
func chat(alias, text string, maxTokens int) *protocol.Request {
	return &protocol.Request{
		Model: alias,
		Input: []protocol.Item{protocol.Message{
			Role:    protocol.RoleUser,
			Content: []protocol.ContentPart{protocol.InputText{Text: text}},
		}},
		MaxOutputTokens: maxTokens,
	}
}

// writeTable logs the per-attempt table, and writes it to RETRY_TABLE when set. It holds no
// header value but Retry-After and x-ratelimit-*, and no request, so no key.
func writeTable(t *testing.T, log *attempts) {
	t.Helper()
	var b strings.Builder
	b.WriteString("call\tattempt\tstart\treply_ms\tgap_ms\tstatus\tretry_after\tx-ratelimit-limit\tx-ratelimit-remaining\tx-ratelimit-reset\tbody_marker\terror\n")
	calls := log.calls()
	for _, name := range slices.Sorted(maps.Keys(calls)) {
		var prev *attempt
		for _, a := range calls[name] {
			gap := ""
			if prev != nil {
				gap = strconv.FormatInt(a.start.Sub(prev.reply).Milliseconds(), 10)
			}
			fmt.Fprintf(&b, "%s\t%d\t%s\t%d\t%s\t%d\t%s\t%s\t%s\t%s\t%t\t%s\n", a.call, a.n,
				a.start.Format("2006-01-02T15:04:05.000Z07:00"), a.reply.Sub(a.start).Milliseconds(), gap,
				a.status, a.retryAfter, a.header.Get("X-Ratelimit-Limit"), a.header.Get("X-Ratelimit-Remaining"),
				a.header.Get("X-Ratelimit-Reset"), a.marker, a.err)
			prev = a
		}
	}
	for line := range strings.Lines(b.String()) {
		t.Log(strings.TrimSuffix(line, "\n"))
	}
	if path := os.Getenv("RETRY_TABLE"); path != "" {
		if err := os.WriteFile(path, []byte(b.String()), 0o644); err != nil {
			t.Errorf("writing the table: %v", err)
		}
	}
}

// checkCall checks one call's attempts: each refused attempt is the gateway's own, a 429 with
// x-ratelimit-limit, -remaining, and -reset (rateLimited) or a 503 with the body marker; each
// retry waited at least the refused attempt's Retry-After from its reply; and, when answered, the
// last attempt is a 200.
func checkCall(t *testing.T, call string, as []*attempt, answered bool) {
	t.Helper()
	if len(as) == 0 {
		t.Errorf("%s: no attempt recorded", call)
		return
	}
	for i, a := range as {
		last := i == len(as)-1
		if a.status == http.StatusOK {
			if !last {
				t.Errorf("%s: attempt %d answered 200, yet another followed", call, a.n)
			}
			continue
		}
		switch {
		case a.status == http.StatusTooManyRequests && !a.rateLimited():
			t.Errorf("%s: attempt %d's 429 lacks one of %s: not the gateway's", call, a.n,
				strings.Join(gatewayRateHeaders, ", "))
		case a.status == http.StatusServiceUnavailable && !a.marker:
			t.Errorf("%s: attempt %d's 503 body lacks %q: not the gateway's", call, a.n, inFlightMarker)
		case a.status != http.StatusTooManyRequests && a.status != http.StatusServiceUnavailable:
			t.Errorf("%s: attempt %d is status %d (%s), not a gateway refusal", call, a.n, a.status, a.err)
		}
		if a.retryAfter != "" && !last {
			secs, err := strconv.Atoi(a.retryAfter)
			if err != nil {
				t.Errorf("%s: attempt %d's Retry-After %q isn't seconds", call, a.n, a.retryAfter)
			} else if gap := as[i+1].start.Sub(a.reply); gap < time.Duration(secs)*time.Second {
				t.Errorf("%s: attempt %d came %v after attempt %d's reply, under its Retry-After of %d s",
					call, as[i+1].n, gap, a.n, secs)
			}
		}
	}
	if last := as[len(as)-1]; answered && last.status != http.StatusOK {
		t.Errorf("%s: last attempt %d is status %d, not 200", call, last.n, last.status)
	}
}
