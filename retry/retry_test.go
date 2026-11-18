package retry

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"sync"
	"testing"
	"time"

	"github.com/standards-lab/go-ai"
)

// TestRateLimitAgent is the rate-limit-agent case: the probe's bucket on the agent route holds 2
// requests and gets 2 back every 10 s, shared by every key, so the third chat within a window is
// answered 429 with a Retry-After of the seconds to the next refill, at most 10, and
// x-ratelimit-* (probes/rate-limit-agent.yaml). The test sends chats one after another until one
// is refused, at most 4, since the bucket may hold fewer than 2 when it starts; infer's policy
// waits the Retry-After, under its 30 s cap, and the refused call's retry ends 200.
func TestRateLimitAgent(t *testing.T) {
	base := live(t, "rate-limit-agent", "agent")
	var log attempts
	client := newClient(t, base, &log, inferDefault, nil)
	t.Cleanup(func() { writeTable(t, &log) })

	refused := false
	for i := 1; i <= 4 && !refused; i++ {
		call := fmt.Sprintf("chat-%d", i)
		ctx, cancel := context.WithTimeout(withCall(t.Context(), call), 2*time.Minute)
		_, err := client.Generate(ctx, chat("agent", "Reply with the word ready.", 64))
		cancel()
		if err != nil {
			t.Errorf("%s: %v", call, err)
		}
		as := log.calls()[call]
		checkCall(t, call, as, true)
		for _, a := range as {
			if a.status == http.StatusTooManyRequests && a.retryAfter != "" {
				refused = true
			}
		}
	}
	if !refused {
		t.Error("no chat in 4 was refused 429 with a Retry-After: is rate-limit-agent deployed?")
	}
}

// TestEmbeddingBurst is the embedding burst: the embedding route's global bucket holds 34
// requests and gets 34 back each second (gateway/agentgateway/config.yaml, the embedding route),
// so of 40 embeddings sent at once, about 6 are answered 429 with Retry-After 1 and
// x-ratelimit-*. Each is retried after its second, under infer's policy, and every call ends 200.
func TestEmbeddingBurst(t *testing.T) {
	base := live(t, "embedding-burst", "embedding")
	var log attempts
	client := newClient(t, base, &log, inferDefault, nil)
	t.Cleanup(func() { writeTable(t, &log) })

	const n = 40
	start := make(chan struct{})
	errs := make([]error, n)
	var wg sync.WaitGroup
	for i := range n {
		wg.Go(func() {
			ctx, cancel := context.WithTimeout(withCall(t.Context(), fmt.Sprintf("embed-%02d", i)), time.Minute)
			defer cancel()
			<-start
			_, errs[i] = client.Embed(ctx, &ai.EmbeddingRequest{Model: "embedding", Input: []string{"A retry probe."}})
		})
	}
	close(start)
	wg.Wait()

	limited := false
	for call, as := range log.calls() {
		checkCall(t, call, as, true)
		for _, a := range as {
			if a.status == http.StatusTooManyRequests && a.retryAfter == "1" && a.rateLimited() {
				limited = true
			}
		}
	}
	for i, err := range errs {
		if err != nil {
			t.Errorf("embed-%02d: %v", i, err)
		}
	}
	if !limited {
		t.Errorf("none of %d embeddings was refused 429 with Retry-After 1 and x-ratelimit-*", n)
	}
}

// TestInFlight1 is the in-flight-1 case: the probe sets the gateway's in-flight limit to 1 per
// bind, so while one request runs, another is refused at arrival, before any key or route, with
// 503 "request limit exceeded" and no Retry-After (probes/in-flight-1.yaml). The test holds one
// streaming agent chat open, unread past its first event, from a client of its own; a second chat
// is then refused, and the recorder releases the held stream on that 503, so the second's retry,
// after go-ai's backoff, is admitted and ends 200.
//
// The second call may make 5 attempts, not infer's 3: the backoff's full jitter can make a retry
// wait almost nothing, and the held request's slot is freed only once the gateway sees its
// connection close, so a retry may beat the release and be refused again. The base and most
// delays stay infer's.
func TestInFlight1(t *testing.T) {
	base := live(t, "in-flight-1", "agent")
	var log attempts
	t.Cleanup(func() { writeTable(t, &log) })

	release := make(chan struct{})
	var once sync.Once
	held := newClient(t, base, &log, ai.RetryPolicy{}, nil)
	client := newClient(t, base, &log, ai.RetryPolicy{MaxAttempts: 5, BaseDelay: inferDefault.BaseDelay, MaxDelay: inferDefault.MaxDelay},
		func(a *attempt) {
			if a.call == "second" && a.status == http.StatusServiceUnavailable {
				once.Do(func() { close(release) })
			}
		})
	// The held stream is released at the end whatever happens, so the test never hangs on it.
	t.Cleanup(func() { once.Do(func() { close(release) }) })

	ctx, cancel := context.WithTimeout(t.Context(), 2*time.Minute)
	defer cancel()
	admitted := make(chan error, 1)
	done := make(chan struct{})
	go func() {
		defer close(done)
		first := true
		for _, err := range held.GenerateStream(withCall(ctx, "held"),
			chat("agent", "Count upward from 1, one number a line.", 4096)) {
			if err != nil {
				if first {
					admitted <- err
				}
				return
			}
			if first {
				first = false
				admitted <- nil
			}
			// Leaving the range closes the stream, freeing its slot.
			select {
			case <-release:
			case <-ctx.Done():
			}
			return
		}
		if first {
			admitted <- errors.New("the held stream ended with no event")
		}
	}()
	if err := <-admitted; err != nil {
		t.Fatalf("held: %v", err)
	}

	_, err := client.Generate(withCall(ctx, "second"), chat("agent", "Reply with the word ready.", 64))
	if err != nil {
		t.Errorf("second: %v", err)
	}
	once.Do(func() { close(release) })
	<-done

	calls := log.calls()
	if h := calls["held"]; len(h) != 1 || h[0].status != http.StatusOK {
		t.Errorf("held: want one attempt answered 200, got %d attempts", len(h))
	}
	as := calls["second"]
	checkCall(t, "second", as, true)
	if len(as) < 2 || as[0].status != http.StatusServiceUnavailable || !as[0].marker {
		t.Error("second: want a first attempt refused 503 with the body marker, then a retry")
	} else if as[0].retryAfter != "" {
		t.Errorf("second: the in-flight 503 carries Retry-After %q; the gateway gives none", as[0].retryAfter)
	}
}

// TestBulkRateLow is the bulk-rate-low case, with the bulk key: the overlay lowers bulk's bucket
// on the agent route to 2 requests a minute, refilled each minute (probes/bulk-rate-low.yaml), so
// bulk's third chat in a minute is answered 429 with a Retry-After of the seconds to the refill.
// Past infer's 30 s cap, go-ai doesn't wait: it returns the 429 at once, its APIError.RetryAfter
// holding the wait, after one attempt. Where the refill falls is the bucket's, so a refusal may
// come with 30 s or less to go: that call waits, is retried, and ends 200 like any other, and the
// test sends on, at most 6 chats, until one is returned refused; two answered after a refill
// leave nearly the whole minute, so one is.
func TestBulkRateLow(t *testing.T) {
	base := live(t, "bulk-rate-low", "agent")
	var log attempts
	client := newClient(t, base, &log, inferDefault, nil)
	t.Cleanup(func() { writeTable(t, &log) })

	for i := 1; i <= 6; i++ {
		call := fmt.Sprintf("chat-%d", i)
		ctx, cancel := context.WithTimeout(withCall(t.Context(), call), 2*time.Minute)
		_, err := client.Generate(ctx, chat("agent", "Reply with the word ready.", 64))
		returned := time.Now()
		cancel()
		as := log.calls()[call]
		if err == nil {
			checkCall(t, call, as, true)
			continue
		}
		checkCall(t, call, as, false)
		apiErr, ok := errors.AsType[*ai.APIError](err)
		switch {
		case !ok || apiErr.Status != http.StatusTooManyRequests:
			t.Errorf("%s: want the 429's APIError, got %v", call, err)
		case apiErr.RetryAfter <= inferDefault.MaxDelay:
			t.Errorf("%s: returned with Retry-After %v, within the %v it would wait", call, apiErr.RetryAfter, inferDefault.MaxDelay)
		}
		if len(as) != 1 {
			t.Errorf("%s: %d attempts, want exactly 1", call, len(as))
		} else if wait := returned.Sub(as[0].reply); wait > time.Second {
			t.Errorf("%s: returned %v after its reply, not at once", call, wait)
		}
		return
	}
	t.Error("no chat in 6 was returned refused: is bulk-rate-low deployed, with the bulk key?")
}
