# AGENTS.md — Intelligent Claims Triage

> **Audience:** Coding agents (Kiro, Claude Code, Codex, Cursor) re-deploying or extending this kit in your AWS account.
> **Status:** Spec-only — no source code is included in this kit folder. This folder is catalog metadata + the build contract; you implement the agent from this contract in your AWS account.

## What this is

A working claims-triage agent built on four pieces:

- **Strands agent on Bedrock AgentCore Runtime** (`agent/claims_triage_agent.py`) — a single entrypoint that takes a claim payload, runs the triage workflow in order (extract → policy lookup → risk assess → decide), and writes the decision back. Lazy-loads the agent on first invocation to stay under AgentCore's cold-start budget. Model is Claude Haiku 4.5 via an inference profile.
- **Four Strands tools** (`agent/tools/`) — `extract_document` (Textract with text/PDF fallbacks), `lookup_policy` (Bedrock Knowledge Base RAG with demo-data fallback), `update_claim` (DynamoDB write), `notify_reviewer` (SQS + SNS escalation).
- **CDK stack** (`infra/claims-triage-stack.ts`) — API Gateway REST API (API key + usage plan), 8 Node.js 20 Lambdas, DynamoDB claims table (`status-index`, `policyNumber-index` GSIs), two S3 buckets (claim docs, policy docs), an SQS review queue, and an SNS topic. The agent runtime itself is deployed separately via the AgentCore CLI, not by this stack.
- **React (Vite) demo UI** (`frontend/`) — adjuster, customer, and reviewer dashboards calling the API.

The triage runs asynchronously: the `triage-claim` orchestrator Lambda returns 202 immediately and invokes the `triage-worker` Lambda, which calls AgentCore (`bedrock-agentcore:InvokeAgentRuntime`) with a 5-minute timeout.

## Where to read first

Read in this order (implementation paths refer to the code you build from this spec):

1. `README.md` (your implementation's README) — full deploy walkthrough and configuration reference
2. `agent/claims_triage_agent.py` — the system prompt is the spec for the triage workflow and the risk rubric
3. `agent/tools/*.py` — the four tools define the agent's real capability surface
4. `infra/claims-triage-stack.ts` — the deployable stack and the trust boundary
5. `architecture/architecture.md` (this kit's own) — high-level overview for catalog readers
6. `build-spec/` (this kit's own) — what to verify when re-deploying

## Re-deploying in a new environment

The spec targets a working CDK stack and an AgentCore deploy flow. The customization story for your deployment:

1. **Risk rubric** — the scoring factors, weights, and the auto-approve vs. escalate threshold live in the `SYSTEM_PROMPT` in `agent/claims_triage_agent.py`. This is the kit's decision logic; tune it to your risk appetite. Default threshold is 0.7.
2. **Policy corpus** — `policy-docs/` holds a sample auto policy. For production, ingest your policy documents into a Bedrock Knowledge Base and set `KNOWLEDGE_BASE_ID` on the agent runtime. Without a KB, `lookup_policy` falls back to hardcoded demo data — fine for a smoke test, not for production.
3. **Document extraction** — `agent/tools/extract_document.py` parses Textract FORMS/TABLES output with regex field extractors tuned to auto-claim documents. Adjust the field patterns for your document formats.
4. **Intake + UI** — `lambda/submit-claim.js` defines the claim schema; `frontend/src/views/` is the demo UI. Adapt to your intake channel (these are demo surfaces, not the core value).
5. **Escalation routing** — `agent/tools/notify_reviewer.py` sends escalated claims to SQS and notifies via SNS. Point the queue/topic at your review tooling and notification channels (`REVIEW_QUEUE_URL`, `REVIEW_TOPIC_ARN`).

The deploy order matters: deploy the agent to AgentCore first, capture the runtime ARN, then `export AGENTCORE_RUNTIME_ARN=...` before `npx cdk deploy` — it's read at synthesis time and baked into the worker Lambda's environment.

## What you're NOT building from scratch

The spec's architectural backbone is fixed — build to it, don't redesign it. Specifically:

- Don't replace AgentCore Runtime with a different agent host — the async orchestrator → worker → AgentCore pattern is the kit's backbone.
- Don't collapse the async triage into a synchronous API call. Triage can exceed API Gateway's 29-second limit; the 202 + worker pattern exists for a reason.
- Don't move policy lookup off RAG into hardcoded rules — the demo fallback is a fallback, not the design.
- Don't remove the human-review escalation path to "ship faster." It's the kit's compliance story.

## Non-negotiables

- **Cite policy terms in every decision.** The system prompt requires the agent to reference specific policy terms in its reasoning. Auto-approval and escalation both persist `reasoning`, `riskScore`, `riskFactors`, and the `policyContext` used. Don't let the agent decide without grounding.
- **Escalate, never auto-deny silently.** Risk score < 0.7 auto-approves; ≥ 0.7 escalates to a human. The agent surfaces and routes; a human owns the deny decision. No auto-deny code path.
- **Risk score is capped at 1.0.** The rubric sums factor weights; the prompt requires `min(sum, 1.0)`. Keep that cap.
- **Payout is bounded.** `payout = min(max(estimatedAmount - deductible, 0), coverageLimit)`. Never pay below zero or above the coverage limit.
- **Persist the cross-reference.** `update_claim` must always receive `extracted_data` and `policy_context` as JSON strings — the UI and the audit trail depend on them.
- **API is authenticated.** Every API Gateway method requires an API key with a usage plan (throttle + daily quota). Don't expose unauthenticated endpoints.

## Defaults

- **Model:** `us.anthropic.claude-haiku-4-5-20251001-v1:0` (region-prefixed inference profile — required; the raw model ID fails with on-demand throughput). Pick the matching `us.` / `eu.` / `ap.` profile for your region.
- **Region:** us-east-1 in the source; you can deploy to any region with Bedrock + AgentCore + Textract availability.
- **Resource names:** `claims-triage-*` (table `claims-triage-claims`, buckets `claims-triage-documents-<acct>-<region>` and `claims-triage-policies-<acct>-<region>`, queue `claims-triage-human-review-queue`, topic `claims-triage-human-review`).
- **Guardrails:** optional. Set `GUARDRAIL_ID` (+ `GUARDRAIL_VERSION`) on the agent runtime to enable PII redaction and topic boundaries on claim narratives.

## Things to confirm before customizing

- What line of business? (auto / P&C / health / warranty / lending) — drives the extraction fields and policy corpus
- Where do policy documents live today, and can they be ingested into a Bedrock Knowledge Base?
- What's your risk appetite — what should the auto-approve threshold be, and which factors matter most?
- What's the intake channel? (portal, agent upload, API from a core claims system) — drives the submit path
- Where should escalations go? (existing review queue, case management system, adjuster inbox)
- Any PII/PHI handling or guardrail requirements on claim narratives?
- Expected claim volume — drives Lambda concurrency and AgentCore runtime sizing

## When to pause and reassess

- You want the agent to **auto-deny** claims (different risk and regulatory posture; this kit only auto-approves or escalates)
- You want **no human in the loop** on high-risk claims (kit escalates by design)
- You want real-time / inline decisioning under a few seconds (kit's async triage is seconds-to-minutes)
- Real claimant PII appears in committed sample data (compliance exposure — keep sample data synthetic)
- You have no documents to extract (the Textract layer adds little; reconsider fit)

## Done definition

Re-deployment is done when:

- Agent deploys to AgentCore Runtime; the runtime ARN is captured and set as `AGENTCORE_RUNTIME_ARN`
- `npx cdk deploy` completes; API Gateway, all 8 Lambdas, DynamoDB, both S3 buckets, SQS, and SNS exist
- A claim submitted via `POST /claims` then `POST /claims/{id}/triage` returns 202 and reaches a terminal status (APPROVED or ESCALATED) in DynamoDB
- An auto-approved claim shows a bounded payout and a policy-cited rationale; an escalated claim lands on the SQS queue and fires an SNS notification
- All acceptance tests in `build-spec/acceptance-tests.md` pass
- You've recorded where your implementation lives (repo URL, ref) and who certified the build
