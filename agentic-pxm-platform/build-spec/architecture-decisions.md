# Architecture Decisions — Agentic PXM Platform

> Audience: a coding agent that might be tempted to deviate. These are distilled from the source's design trail (`aidlc-docs/`) plus kit-level packaging decisions. Don't reverse them without checking with your build lead.

## AD1 — Custom IaC (AWS CDK), not a managed harness
**Decision:** Deliver the agent as six AWS CDK stacks (Data, Auth, Agent, Api, Frontend, Observability) you own end-to-end, deployed via `cdk deploy --all`.
**Why:** The use case is a regulated, multi-tenant catalog workflow with a durable human-in-the-loop gate, RAG over a vector store, and pool-based tenancy — it needs orchestration, persistence, auth, and a vector index, not just a prompt + tools. A managed harness can't express the Step Functions saga + `waitForTaskToken` gate, and the compliance/tenancy posture demands an auditable, you own stack.
**What this means for the build:** Keep the stack split; deviating to a managed build level must be recorded here and cleared with your build lead.

## AD2 — Step Functions saga, not a single Lambda
**Decision:** Orchestrate the run as a Step Functions state machine: `Enrich → ReviewChoice → (AutoApprove | ReviewGate → PostReviewChoice → Publish) → Done`, each task with exponential-backoff retries.
**Why:** A multi-stage agentic run that can pause for days needs durable orchestration, retries, and a visible run history — a single Lambda can't pause for a human or survive throttling cleanly.
**What this means for the build:** Keep the saga shape and the retry policy (`States.TaskFailed`/`States.Timeout`, 2s interval, 3 attempts, 2.0 backoff). The per-stage decomposition can expand without changing the contract.

## AD3 — Human-in-the-loop gate via `waitForTaskToken`
**Decision:** Realize the review gate with the Step Functions `waitForTaskToken` integration (task timeout 3 days); the operator decision resumes via `SendTaskSuccess`. Locally, `LocalOrchestrator` mirrors this with a PAUSED_REVIEW state.
**Why:** High-impact actions (compliance blockers, channel publish) must stay under operator control. A durable token-based pause lets a run wait for a real human without holding compute.
**What this means for the build:** Never wire a blocker straight to publish. The gate is the product's safety guarantee.

## AD4 — Deterministic, cited compliance check (model enriches, code decides)
**Decision:** The compliance verdict is rule-based substring matching against each applicable `Regulation`'s `restricted_substances` and `prohibited_claims`; every finding cites the `reg_id` + `citation_url`. The LLM is used for attribute suggestion, classification, and copy — never for the blocker decision.
**Why:** A compliance verdict must be reproducible and defensible. An LLM-owned verdict is neither, and it can hallucinate. Determinism makes the gate trustworthy and the audit trail real.
**What this means for the build:** Keep the blocker decision in code. Re-tune the rules per deployment, but never hand the verdict to the model.

## AD5 — Pluggable `LLMProvider` (Bedrock / AgentCore / fake)
**Decision:** All model access goes through an `LLMProvider` protocol with three implementations: `FakeProvider` (deterministic/offline), `BedrockProvider` (Claude 3.5 Sonnet `InvokeModel` + Titan embeddings), `AgentCoreProvider` (Bedrock AgentCore runtime). Selected by `PXM_PROVIDER`.
**Why:** The fake provider lets the entire platform run offline for the demo, CI, and property-based tests with zero credentials; the Bedrock/AgentCore split lets you pick latency/cost/managed-tooling tradeoffs without touching agent code.
**What this means for the build:** Don't bypass the provider with direct boto3 calls in agent logic. New providers implement the protocol.

## AD6 — RAG over OpenSearch Serverless with an in-memory fallback
**Decision:** RAG retrieval uses a `VectorIndex` protocol with two backends: `OpenSearchVectorIndex` (k-NN, index `pxm-rag`) when `PXM_OPENSEARCH_ENDPOINT` is set, else `InMemoryVectorIndex` (cosine) for local/tests. Sources are tagged `taxonomy` / `brand` / `regulations_text`.
**Why:** Classification and copy must be grounded in your taxonomy and brand guidelines; OpenSearch Serverless gives a managed vector store in AWS, while the in-memory index keeps local runs AWS-free.
**What this means for the build:** OpenSearch Serverless carries a **minimum always-on cost** — flag it in ROI and size it to volume. Keep the backend-agnostic protocol.

## AD7 — DynamoDB single-table with tenant-prefixed keys + GSI1
**Decision:** All entities (products, suppliers, regulations, runs, reviews) live in one DynamoDB table with `PK/SK` keys prefixed by tenant (`T#<tenant>`) and a `GSI1` for status/queue queries. On-demand billing, AWS-managed encryption, point-in-time recovery.
**Why:** Single-table design keeps tenant isolation, status queries, and the review queue in one place with predictable access patterns; the GSI serves list-by-status without scans.
**What this means for the build:** Never drop the tenant prefix from a key. Serialization is shared across in-memory and DynamoDB backends so the round-trip property holds identically (property-tested).

## AD8 — Validated lifecycle state machine as the single source of truth
**Decision:** Product status transitions are defined as an explicit `(status, event) → status` table in `shared/lifecycle.py`; any undefined transition raises `InvalidTransition`. All writes go through `MasterDataService` (one validated write path), and immutable fields can never change.
**Why:** A product moving from draft → enriching → (needs_review | approved) → published/rejected must be tamper-proof and auditable. Centralizing transitions prevents illegal states; the single write path prevents drift.
**What this means for the build:** Route every status change through the lifecycle; it is hardened with stateful property-based tests — keep them green.

## AD9 — Pool-based multi-tenancy with Cognito + role authZ
**Decision:** One deployment serves many brands. A Cognito user pool carries a `custom:tenant_id` claim and admin/operator/viewer groups; the BFF maps JWT claims to a `TenantContext` and enforces an action→roles matrix (write_product → admin; start_run / review_decision / publish → admin+operator; reads / chat_query → all).
**Why:** Catalog-ops teams run multiple brands/business units and need isolation + role separation without a deployment per brand.
**What this means for the build:** Enforce tenant + role on every operation. Highest-privilege group wins when resolving a role.

## AD10 — Offline-first, property-tested, CI without AWS
**Decision:** The platform runs end-to-end locally (fake provider + in-memory repo + in-memory vector index + `LocalOrchestrator`); the backend ships a `pytest` + Hypothesis suite and the frontend a Vitest + fast-check suite; CI runs lint + tests + `cdk synth` with no AWS credentials and no deploy.
**Why:** A demoable, testable, reproducible build is the fastest path to stakeholder confidence and a safe customization loop. Property tests pin the invariants (lifecycle, serialization round-trip, idempotent normalization) that customization must preserve.
**What this means for the build:** Keep the fake provider and in-memory backends working as customization happens; don't make AWS a hard dependency of the unit tests.

## Model

- **Provider:** Bedrock (`anthropic.claude-3-5-sonnet-20240620-v1:0`) + Titan Embeddings v2 (`amazon.titan-embed-text-v2:0`); AgentCore optional.
- **Why this model:** Claude 3.5 Sonnet balances enrichment/copy quality against per-SKU cost and latency; Titan v2 is a low-cost in-region embedding model for RAG. Both are configurable via `PXM_BEDROCK_TEXT_MODEL` / `PXM_BEDROCK_EMBED_MODEL` per your latency/cost needs.

## Open architecture questions (review before deciding)

- **Production hardening:** dev stacks use `RemovalPolicy.DESTROY` and the OpenSearch network policy is `AllowFromPublic` — both must be hardened (retention, VPC/private access, alarms) for production.
- **Agent stage decomposition in AWS:** the reference bundles the four stages into one `EnrichmentFn`; splitting into per-stage Lambdas (matching the local ASL) is your choice with cost/observability tradeoffs.
- **AgentCore IAM scope:** the `bedrock-agentcore:InvokeAgentRuntime` permission is currently `*` — tighten to the specific runtime ARN once deployed.
