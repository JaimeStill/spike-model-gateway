# goal · experiment.hosting.spike-model-gateway

- **State:** idle
- **Task:** none
- **Branch:** none

## Tasks

1. [ ] agentgateway
2. [ ] litellm
3. [ ] priority
4. [ ] answer

## Decisions

- plan: the question is rewritten around the vLLM layout: one row per purpose, no failover.
- plan: agentgateway and LiteLLM are tried live. Agent Router stays on paper: it is
  Kubernetes-first, and `aigw run` is for local testing. vLLM's production-stack router stays on
  paper: it balances replicas of one model. Kubernetes portability is on paper too, since both live
  gateways have a Kubernetes path.
- plan: the dev gateway runs on gb10-2. It has 65 GiB of headroom against gb10-1's 2.7, it reboots
  unattended, and the capstone's compose stack runs there next.
- plan: model management is fenced only. Consumer keys reach serving routes alone, and row
  lifecycle stays with `host/` over SSH and with experiment.admin.
- plan: spike-model-engines is a rolling spike for the experiment, so it joins this spike's repos.
  The `agentgateway` task rebinds the rows behind the gateway through a `host/` pull request.
- plan: overflow to Azure AI Foundry runs live, with a capped request count. A deployment and key
  are needed before `priority`.
- plan: kind context; `mise run check`; `mise run currency`; no gate.
- plan: overhead is measured with the same GuideLLM cells sent direct and through the gateway, in
  one session.
- plan: the order is agentgateway, litellm, priority (both gateways in one session), answer.
- plan: LiteLLM's Postgres counts as known, not as a new tool. Cerebro plans a Postgres cache too.
- plan: consumers name purpose aliases (agent, vision, audio, embedding). Each alias has its own
  base URL, `/<alias>/v1`, whose `/models` lists only that alias, so go-ai's integration tier and
  the `infer` CLI's one-listed-model fallback work unchanged. Rejected: one shared `/v1` with
  `--model` required of every client.
- plan: go-ai's integration tier runs through the gateway, and go-ai stays read-only. The `infer`
  CLI is used once it is released, as a published version.
- plan: agentgateway's `host/` pull request to spike-model-engines also adds go-core's Apache-2.0
  `LICENSE` there, per the spike repository convention (standards-lab `context/README.md`,
  "Experiments"); this spike holds spike-model-engines.

## Pending edits

(none)
