# Requirements — Agentic PXM Platform

> Audience: a coding agent implementing or customizing the kit, and the build lead certifying the build.

## Functional requirements

**FR1 — SKU ingestion.** The system shall accept a sparse `ProductDraft` (sku, title, optional supplier_id, category_hint, target_markets, description_raw, gtin) and create a `Product` in `DRAFT`, validating the SKU format and stamping tenant + creator. *Maps to: T1.*

**FR2 — Four-stage enrichment.** On a run, the `EnrichmentAgent` shall execute four ordered stages over the product: (1) normalize attributes (idempotent), (2) classify to a taxonomy category using RAG-retrieved context, (3) generate a title + short + long marketing copy grounded in brand-guideline passages, (4) check compliance per target market. The enriched fields shall be persisted via the single validated write path. *Maps to: T2, T3, T4.*

**FR3 — Deterministic, cited compliance check.** For each target market, the system shall match the product's title/description/attributes against the applicable regulations' `restricted_substances` and `prohibited_claims`. Any match shall produce a `BLOCKER` `Finding` carrying the `reg_id`, a message, and the `citation_url`; a clean market shall produce a `PASS` finding. The blocker decision shall be computed in code, not by the model. *Maps to: T4, T5.*

**FR4 — Auto-approve vs. human-in-the-loop routing.** If no blocker is found, the product shall transition `enriching → approved` autonomously (auto-approve). If any blocker is found, the product shall transition `enriching → needs_review`, a `ReviewItem` shall be created, and the run shall pause at the HITL gate until an operator decision. *Maps to: T5, T6.*

**FR5 — HITL review gate via task token.** In AWS, the review gate shall be realized with the Step Functions `waitForTaskToken` integration (task timeout 3 days); the operator decision (`approve`/`reject`) shall resume the saga via `SendTaskSuccess`. Locally, the `LocalOrchestrator` shall mirror this with a PAUSED_REVIEW state and `resume_after_review`. *Maps to: T6, T7.*

**FR6 — Gated channel publish.** A product shall be publishable to a channel only when in `APPROVED` status; the publish tool shall raise/reject otherwise. Publishing shall go through a registered `ChannelAdapter` (`map → validate → publish`) and transition `approved → published`. *Maps to: T7, T8.*

**FR7 — Validated lifecycle state machine.** All status changes shall go through `shared/lifecycle.py`; only the defined `(status, event) → status` transitions shall be permitted, and any other shall raise `InvalidTransition`. *Maps to: T9.*

**FR8 — Single validated write path + immutability.** Product writes shall go through `MasterDataService`; the immutable fields (`tenant_id`, `product_id`, `sku`, `created_at`, `created_by`) shall never be modifiable by a patch. *Maps to: T10.*

**FR9 — RAG grounding with local fallback.** Classification and copy generation shall retrieve top-k passages by embedding similarity, filterable by source (`taxonomy`, `brand`, `regulations_text`). The vector backend shall be OpenSearch Serverless k-NN when `PXM_OPENSEARCH_ENDPOINT` is set, else an in-memory cosine index. *Maps to: T11.*

**FR10 — Pluggable model provider.** The agent and RAG shall reach the model through an `LLMProvider` selected by `PXM_PROVIDER`: `fake` (deterministic/offline), `bedrock` (Claude 3.5 Sonnet `InvokeModel` + Titan embeddings), or `agentcore` (Bedrock AgentCore runtime + Bedrock embeddings). Switching providers shall require no code change. *Maps to: T12.*

**FR11 — Multi-tenancy + role-based authorization.** Every operation shall carry a `TenantContext` (tenant_id, user_id, role) derived from JWT claims; data keys shall be tenant-prefixed; the authZ matrix shall gate actions (write_product → admin; start_run / review_decision / publish → admin+operator; reads / chat_query → all roles). *Maps to: T13, T14.*

**FR12 — Operator console + chat.** A React SPA shall provide ingest, product list/detail, the review queue, and a chat console; the chat shall classify intents (query vs. command) and gate commands by role. *Maps to: T15.*

## Non-functional requirements

**NFR1 — Autonomy with safe escalation.** Low-risk SKUs complete without human action; high-impact actions (compliance blockers, channel publish) require an operator decision via the HITL gate.

**NFR2 — Resilience.** Each saga task shall retry on `States.TaskFailed` / `States.Timeout` with exponential backoff (interval 2s, 3 attempts, rate 2.0). The system shall run fully offline with the fake provider + in-memory backends.

**NFR3 — Determinism / auditability.** Compliance verdicts shall be reproducible from the regulation corpus; runs shall record a correlation id, stage, and cited findings so any decision can be decomposed.

**NFR4 — Security / least privilege.** Single deployment per deployment account/region. IAM roles shall grant only `bedrock:InvokeModel` on `anthropic.*` + `amazon.titan-embed-*`, `bedrock-agentcore:InvokeAgentRuntime`, DynamoDB read/write on the table, Step Functions start/task-response, and scoped OpenSearch access. DynamoDB shall be encrypted with point-in-time recovery; API access shall be JWT-authenticated via Cognito.

**NFR5 — Tenant isolation.** No cross-tenant reads; tenant prefix enforced on every key; tenant claim enforced from the JWT.

**NFR6 — Cost predictability.** Bedrock cost scales with SKU volume × ~3 model calls per enrichment (compliance is deterministic, no model call); OpenSearch Serverless carries a minimum always-on cost that must be sized to volume.

**NFR7 — Tested.** The backend shall ship a `pytest` + Hypothesis property-based suite (lifecycle state machine, serialization round-trip, attribute-normalization idempotence); the frontend shall ship a Vitest + fast-check suite. CI shall run lint + tests + `cdk synth` with no AWS credentials.

## Inputs

- **Source:** operator-submitted `ProductDraft` via the SPA / REST API (or a chat "enrich SKU-X" command). Master data (products, suppliers, regulations) and the RAG corpus are seeded from `data/` into DynamoDB + OpenSearch.
- **Format:** JSON `ProductDraft`; regulations as `Regulation` records (jurisdiction, applies_to_categories, restricted_substances, prohibited_claims, required_attributes, citation_url).
- **Authentication:** Cognito JWT → `TenantContext` (tenant_id, user_id, role).

## Outputs

- **Destination:** an enriched, classified, copy-written `Product` written back to DynamoDB; clean products published to a channel (listing id returned); blockers placed on the review queue.
- **Side effects:** lifecycle transitions, `EnrichmentRun` records, `Finding`s persisted on the product, structured CloudWatch logs + X-Ray traces.

## Out of scope

- Fully autonomous publish of compliance blockers (HITL gate is by design).
- Real channel/marketplace integrations (the kit ships `MockMarketplaceAdapter` only).
- A production master-data system (the kit seeds synthetic fixtures; you wire your own).
- LLM-owned compliance verdicts (the blocker decision is deterministic).
- Model fine-tuning or custom inference hosting.
- Production hardening defaults — dev resources use `RemovalPolicy.DESTROY` and the OpenSearch network policy is `AllowFromPublic`; both must be hardened for production.

## Dependencies

- Bedrock model access enabled for Claude 3.5 Sonnet (`anthropic.claude-3-5-sonnet-20240620-v1:0`) + Titan Embeddings v2 (`amazon.titan-embed-text-v2:0`) in the target region (`us-east-1` default). Optionally a deployed Bedrock AgentCore runtime for `agentcore` mode.
- AWS account with permissions to create DynamoDB, OpenSearch Serverless, S3, Lambda, Step Functions, API Gateway, Cognito, CloudFront, CloudWatch, and IAM roles.
- AWS CDK CLI ≥ 2.150; Python ≥ 3.12; Node.js ≥ 18 (for the frontend build). Docker optional (for Linux-native Lambda bundles; otherwise pip bundling).
- Structured product/supplier/regulation master data and a RAG corpus (taxonomy + brand guidelines + regulation text).
