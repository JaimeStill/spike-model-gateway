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
			t.Errorf("%s: %s", call, scrub(err))
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
			t.Errorf("embed-%02d: %s", i, scrub(err))
		}
	}
	if !limited {
		t.Errorf("none of %d embeddings was refused 429 with Retry-After 1 and the gateway's x-ratelimit-* headers", n)
	}
}

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
		t.Fatalf("held: %s", scrub(err))
	}

	_, err := client.Generate(withCall(ctx, "second"), chat("agent", "Reply with the word ready.", 64))
	if err != nil {
		t.Errorf("second: %s", scrub(err))
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
			t.Errorf("%s: want the 429's APIError, got %s", call, scrub(err))
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
