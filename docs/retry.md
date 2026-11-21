# The retry test

This page gives the reasoning behind the Go retry test, [`retry/`](../retry/): what each case
expects of the gateway, and why each check reads a refusal as the gateway's own. The package comment in
[`retry/record_test.go`](../retry/record_test.go) gives the environment each case runs with, and
`retry_case` in [`scripts/clients-lib.sh`](../scripts/clients-lib.sh) runs one case.

## infer's policy

`inferDefault` is infer's default retry policy, as at tools/infer/v0.3.1 (unchanged since v0.2.0,
where the cases were measured): 3 attempts, the first wait at most 500 ms, every wait and the
longest Retry-After honored at most 30 s (go-ai's tools/infer/README.md, "Retries").

## The gateway's refusals

A refused attempt counts as the gateway's only when it carries a marker no row or Azure gives:

- **A 429** carries every one of x-ratelimit-limit, x-ratelimit-remaining, and x-ratelimit-reset,
  by these exact names, which agentgateway's local rate limit adds to every reply on a limited
  route, its 429s among them (the recorded tables under .state/answer/retry/). A row sends none.
  Azure OpenAI sends x-ratelimit-* too, but only names with a -requests or -tokens suffix
  (x-ratelimit-limit-requests, x-ratelimit-remaining-tokens, and the rest), and none of these three
  (learn.microsoft.com, "Manage Azure OpenAI in Microsoft Foundry Models quota", "Rate limit
  response headers", read 2026-11-19), so a prefix alone marks no reply as the gateway's.
- **A 503** holds "request limit exceeded" in its body, agentgateway's in-flight refusal
  ([probes/in-flight-1.yaml](../gateway/agentgateway/probes/in-flight-1.yaml)); a row's 503
  doesn't hold it.

A refused reply's body is short, so the recorder reads it whole for the marker and hands it on
unchanged; a 2xx's body, maybe a stream, is left alone. A call checks out when each refused
attempt is the gateway's own, each retry waited at least the refused attempt's Retry-After from its
reply, and, when the call was answered, its last attempt is a 200.

Nothing the test prints holds a secret. The key's path is in an error, never the key. A dial error
names the host it reached, gb10-2's tailnet address, so each IPv4 address, and each IPv6 one in
brackets, is printed and tabled as `<addr>`. The per-attempt table holds no header value but
Retry-After and x-ratelimit-*, and no request. `TestMain` refuses a RETRY_CASE that names no case,
which would otherwise skip every test and pass.

## rate-limit-agent

The probe's bucket on the agent route holds 2 requests and gets 2 back every 10 s, shared by every
key, so the third chat within a window is answered 429 with a Retry-After of the seconds to the
next refill, at most 10, and x-ratelimit-*
([probes/rate-limit-agent.yaml](../gateway/agentgateway/probes/rate-limit-agent.yaml)). The test
sends chats one after another until one is refused, at most 4, since the bucket may hold fewer than
2 when it starts; infer's policy waits the Retry-After, under its 30 s cap, and the refused call's
retry ends 200.

## embedding-burst

The embedding route's global bucket holds 34 requests and gets 34 back each second
([config.yaml](../gateway/agentgateway/config.yaml), the embedding route), so of 40 embeddings sent
at once, about 6 are answered 429 with Retry-After 1 and x-ratelimit-*. Each is retried after its
second, under infer's policy, and every call ends 200.

## in-flight-1

The probe sets the gateway's in-flight limit to 1 per bind, so while one request runs, another is
refused at arrival, before any key or route, with 503 "request limit exceeded" and no Retry-After
([probes/in-flight-1.yaml](../gateway/agentgateway/probes/in-flight-1.yaml)). The test holds one
streaming agent chat open, unread past its first event, from a client of its own; a second chat is
then refused, and the recorder releases the held stream on that 503, so the second's retry, after
go-ai's backoff, is admitted and ends 200. Leaving the held stream's range closes it, freeing its
slot, and a cleanup releases it whatever happens, so the test never hangs on it.

The second call may make 5 attempts, not infer's 3: the backoff's full jitter can make a retry wait
almost nothing, and the held request's slot is freed only once the gateway sees its connection
close, so a retry may beat the release and be refused again. The base and most delays stay
infer's.

## bulk-rate-low

Run with the bulk key: the overlay lowers bulk's bucket on the agent route to 2 requests a minute,
refilled each minute ([probes/bulk-rate-low.yaml](../gateway/agentgateway/probes/bulk-rate-low.yaml)),
so bulk's third chat in a minute is answered 429 with a Retry-After of the seconds to the refill.
Past infer's 30 s cap, go-ai doesn't wait: it returns the 429 at once, its APIError.RetryAfter
holding the wait, after one attempt. Where the refill falls is the bucket's, so a refusal may come
with 30 s or less to go: that call waits, is retried, and ends 200 like any other, and the test
sends on, at most 6 chats, until one is returned refused; two answered after a refill leave nearly
the whole minute, so one is.
