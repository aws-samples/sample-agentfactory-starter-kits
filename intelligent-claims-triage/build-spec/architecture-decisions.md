# Architecture Decisions — Intelligent Claims Triage

Decisions made up front so the coding agent doesn't re-litigate them mid-build.

## AD1: Build level = `custom-iac`

**Decision:** A full CDK (TypeScript → CloudFormation) stack, with the agent runtime deployed separately on Bedrock AgentCore.

**Why.** The kit's value is the whole pipeline: intake API, async invocation, storage, document extraction, policy RAG, decisioning, and human-review routing. A managed harness covers the agent runtime but not the API Gateway / Lambda / DynamoDB / S3 / SQS / SNS that make this a deployable claims system. We need explicit IaC anyway, so `custom-iac` is the honest level — even though the agent itself rides on AgentCore Runtime.

**What this means for the build.** Treat the CDK stack and the AgentCore agent as two deploy units. Don't try to fold the agent into the CDK stack, and don't drop the CDK stack in favor of "just the agent."

## AD2: Agent on AgentCore Runtime, not a Lambda-hosted loop

**Decision:** The Strands agent runs on Bedrock AgentCore Runtime, invoked via `bedrock-agentcore:InvokeAgentRuntime`.

**Why.** The agent makes several tool calls and LLM turns per claim (extract, lookup, assess, write/notify) that can run for tens of seconds. AgentCore gives a purpose-built agent runtime with the right execution model and observability, instead of stretching a Lambda to host an agent loop.

**Alternatives considered.** Agent loop inside a Lambda (timeout and packaging friction), Bedrock Managed Agents (less control over the Strands tool orchestration and the prompt).

## AD3: Asynchronous triage (202 + worker)

**Decision:** `POST /claims/{id}/triage` is an orchestrator Lambda that returns 202 and asynchronously invokes a worker Lambda (5-minute timeout) that calls AgentCore.

**Why.** Full triage can exceed API Gateway's hard 29-second integration limit. Returning 202 immediately and polling `GET /claims/{id}` keeps the client responsive and lets the agent take the time it needs. The worker marks `AGENT_ERROR` on failure so claims don't get stuck silently.

**What this means for the build.** Don't make triage a synchronous request/response. The UI polls for the terminal status.

## AD4: Model = Claude Haiku 4.5 via inference profile

**Decision:** `us.anthropic.claude-haiku-4-5-20251001-v1:0` (region-prefixed inference profile) as default.

**Why.** Triage is a structured, tool-driven workflow over a bounded amount of claim text — Haiku is fast and cheap enough to make per-claim economics work at volume while handling the multi-tool reasoning. The inference profile (not the raw model ID) is required; on-demand throughput on the bare model ID fails.

**When to change.** Move to a Sonnet-class profile if your claims need heavier reasoning over long, messy narratives; keep Haiku for high-volume, well-structured intake. Always use the region-matched profile prefix (`us.` / `eu.` / `ap.`).

## AD5: Policy lookup via RAG, with a demo fallback

**Decision:** `lookup_policy` queries a Bedrock Knowledge Base over your policy documents. If `KNOWLEDGE_BASE_ID` is unset or returns nothing, it falls back to demo/default policy data tagged with its `source`.

**Why.** Coverage decisions must be grounded in your actual policy language, and RAG reads what they have without forcing a clean schema. The fallback exists only so the kit runs end-to-end before a KB is wired (demo policy `ACM-2024-07821`).

**What this means for the build.** The fallback is a smoke-test convenience, not the design. Production must wire a real Knowledge Base; don't ship demo policy data as the answer source.

## AD6: Decision logic — auto-approve below 0.7, escalate at/above, never auto-deny

**Decision:** Risk < 0.7 → auto-approve with a bounded payout; risk ≥ 0.7 → escalate to a human. There is no auto-deny path.

**Why.** Straight-through processing earns its keep on the low-risk majority; anything risky goes to a human with assembled context. Denying a claim carries legal and customer-impact weight that belongs with a person, not the agent. The threshold is a single, tunable value in the system prompt.

**What this means for the build.** Keep the threshold configurable. Don't add an auto-deny branch. Keep the payout bounded: `min(max(amount − deductible, 0), coverageLimit)`.

## AD7: Risk score is a capped, documented rubric

**Decision:** The risk score is a sum of named factors (amount vs. limit, total loss, disputed liability, fraud indicators, peril not covered), capped at 1.0.

**Why.** A documented, additive rubric is explainable and tunable — a claims-compliance reviewer can read it. A free-form "model picks a number" is neither. The cap prevents factor stacking from producing nonsense scores.

**What this means for the build.** The rubric lives in the system prompt and is your main tuning surface. Keep `min(sum, 1.0)`.

## AD8: Extraction has a fallback chain

**Decision:** `extract_document` tries Textract FORMS/TABLES, then Textract text detection, then raw-PDF text scraping, then returns "use claim metadata."

**Why.** Real claim documents are messy — scans, odd PDFs, photos. Triage must degrade gracefully rather than hard-fail on a document Textract can't parse. Worst case, the agent proceeds on the submitted claim fields.

**What this means for the build.** Preserve the fallback chain. The returned `source` field tells you which path produced the data — surface it for tuning.

## AD9: API is authenticated by default

**Decision:** Every API Gateway method requires an API key tied to a usage plan (throttle 50 rps / 100 burst, 10k/day quota).

**Why.** The endpoints submit claims, trigger agent invocations, and read claim data — none should be open to the internet. The usage plan also caps cost/abuse during a demo or pilot.

**When to change.** For production, swap the API key for your identity provider / a Lambda authorizer. Don't remove auth entirely.

## AD10: Single-tenant deployment

**Decision:** One stack per organization; one trust boundary.

**Why.** Claims data is regulated and specific to your organization. A shared multi-tenant deployment would mix one insurer's claims and policies with another's — unacceptable. Each deployment gets its own account-scoped resources (`claims-triage-*`).

## AD11: Audit trail is first-class

**Decision:** Every decision persists its full basis (score, factors, reasoning, extracted data, policy context) on the claim, and the agent's tool calls + reasoning stream to CloudWatch.

**Why.** "Why was this claim approved?" must have a concrete, replayable answer for a claims-compliance or audit review. The cross-reference (`extractedData` + `policyContext`) is what lets a human see exactly what the agent saw.

**What this means for the build.** `update_claim` must always receive `extracted_data` and `policy_context`. Don't drop them to save a few tokens — the UI and the audit story both depend on them.
