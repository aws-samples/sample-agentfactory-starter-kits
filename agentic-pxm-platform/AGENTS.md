# AGENTS.md — Agentic PXM Platform

> **Audience: a coding agent** (Kiro / Claude Code / Cursor / Codex / etc.) re-implementing or customizing this kit for your organization.

## What this is

- An **autonomous product onboarding & enrichment agent** for retail catalogs (PIM/PXM / catalog-operations).
- **One `EnrichmentAgent` that runs four sequential stages** over a single product: **enrich attributes → classify to taxonomy → generate brand-consistent copy → compliance check** (`services/agent/enrichment_agent.py`).
- The agent is wrapped in an **AWS Step Functions saga** with exponential-backoff retries and a `waitForTaskToken` **human-in-the-loop review gate** (`infra/stacks/agent_stack.py`, `services/agent/sfn_handlers.py`).
- **Clean products auto-approve and publish autonomously.** Anything with a **compliance blocker** (restricted substance, prohibited claim) is routed to a **review queue** and only proceeds on an operator decision. **Channel publish is always gated** behind APPROVED status.
- The LLM is reached through a **pluggable `LLMProvider`** (`shared/providers.py`): `FakeProvider` (deterministic, offline), `BedrockProvider` (Claude 3.5 Sonnet `InvokeModel` + Titan embeddings), `AgentCoreProvider` (Bedrock AgentCore runtime). Selected by `PXM_PROVIDER`.
- Delivery surface: **React + TypeScript SPA** (ingest, product list/detail, review queue, chat) on **S3 + CloudFront**, fronted by **API Gateway → BFF Lambda** with a **Cognito** authorizer. Data in **DynamoDB single-table** + **OpenSearch Serverless** (RAG k-NN).
- Tenancy: **pool-based multi-tenancy** — tenant-prefixed DynamoDB keys (`T#<tenant>`) and a Cognito `custom:tenant_id` claim, with **admin / operator / viewer** roles.

## Where to read first (in your implementation)

No source is included in this kit — the implementation is built from this spec. Structure (and read) it in this order:

1. `README.md` — purpose, the architecture-at-a-glance table, local-run + deploy instructions, the demonstrated behaviors.
2. `services/agent/enrichment_agent.py` — the four enrichment stages and the deterministic compliance check. **The stage logic is the capability.**
3. `services/agent/orchestration.py` — `build_state_machine_definition()` (the ASL saga) and `LocalOrchestrator` (the same saga in-process, incl. the HITL pause/resume).
4. `services/agent/sfn_handlers.py` — the per-state Lambda handlers (`enrich`, `auto_approve`, `review_gate` via `waitForTaskToken`, `publish`).
5. `shared/lifecycle.py` — the product status state machine (the single source of truth for valid transitions).
6. `shared/models.py` + `shared/enums.py` — `Product`, `ProductDraft`, `Regulation`, `Finding`, `ReviewItem`, `TenantContext` and the status/severity/role enums (the data contract).
7. `services/agent/rag.py` — the RAG service over OpenSearch Serverless k-NN with the in-memory fallback.
8. `shared/providers.py` — the `LLMProvider` abstraction and the three concrete providers.
9. `services/review_channel/channel.py` — the `ChannelAdapter` protocol and `MockMarketplaceAdapter` (the thing you replace).
10. `infra/app.py` + `infra/stacks/*.py` — the six CDK stacks (Data, Auth, Agent, Api, Frontend, Observability).
11. `aidlc-docs/construction/` — the design trail and per-unit code summaries.

## What you (the coding agent) should do

This kit ships spec-first: no source code is included. This `AGENTS.md` is the build contract — implement the agent from it, then verify your build against [`build-spec/acceptance-tests.md`](build-spec/acceptance-tests.md).

Read [`build-spec/requirements.md`](build-spec/requirements.md) for the functional spec, [`build-spec/architecture-decisions.md`](build-spec/architecture-decisions.md) for the rationale, and [`build-spec/deployment-spec.md`](build-spec/deployment-spec.md) for what "done" means. Build in your AWS account; do not commit agent code into this kit folder.

## Required behavior

- **Ingest a sparse SKU** (`ProductDraft`: sku, title, optional supplier_id, category_hint, target_markets, description_raw) and create a `Product` in `DRAFT`.
- **Run the four-stage enrichment** in one orchestrated pass: normalize attributes → classify against the taxonomy (RAG-grounded) → write title + short/long copy (brand-guidelines-grounded) → check the product against every target market's regulations.
- **Emit cited compliance findings.** Each `Finding` carries the `reg_id`, a `severity` (`pass`/`info`/`warning`/`blocker`), a message, and the regulation's `citation_url`. A blocker is raised when a `restricted_substance` or `prohibited_claim` appears in the product's title/description/attributes.
- **Auto-approve clean products** (no blocker) and let them publish; **route any blocker to the review queue** and pause the saga at the HITL gate until an operator approves or rejects.
- **Never publish to a channel** unless the product is in `APPROVED` status (the publish tool enforces this).
- **Enforce tenant + role boundaries** on every operation via `TenantContext` and the authZ matrix.
- **Keep every run auditable** — an `EnrichmentRun` records the stage and correlation id; the validated lifecycle records every status transition.

## Tools the agent uses (`services/agent/tools.py`)

- `product_read` / `supplier_read` — tenant-scoped master-data reads.
- `compliance_search(jurisdiction, category)` — pull the regulations that apply to a product's market + category.
- `rag_retrieve(query, k, source)` — top-k passages from the RAG corpus, filterable by `source` (`taxonomy` / `brand` / `regulations_text`).
- `product_write(patch)` — the **single validated write path** (goes through `MasterDataService.update_product`; immutable fields rejected).
- `channel_publish(product_id, channel)` — **HITL-gated**; raises `ChannelPublishNotAllowed` unless the product is `APPROVED`.

Do not invent integrations the kit doesn't need. There are no external KYC/ERP/PIM calls in the reference — master data is read from the DynamoDB single table and regulations from the seeded corpus.

## System prompt / stage prompts

There is **no single monolithic system prompt** — each stage builds its own prompt from the product + retrieved RAG context (see `enrich_attributes`, `classify`, `generate_copy` in `enrichment_agent.py`). When customizing for your environment:

- Establish the stage's role and your product domain in each stage prompt.
- Ground classification in your **taxonomy** corpus and copy in your **brand-guidelines** corpus.
- Keep the **compliance check deterministic** — it is rule-based substring matching against `Regulation.restricted_substances` / `prohibited_claims`, not an LLM judgment. The model enriches; the blocker decision stays in code.
- Draft the stage prompts from the requirements before implementing, then refine them against the acceptance tests.

## Conventions

- **AWS region:** `us-east-1` default (`AWS_REGION` / `CDK_DEFAULT_REGION`). Confirm Bedrock model access in your region.
- **Provider selection:** `PXM_PROVIDER` = `fake` (local/tests), `bedrock` (default in AWS), or `agentcore`. Backend selection is env-driven: `PXM_TABLE` → DynamoDB repo, `PXM_OPENSEARCH_ENDPOINT` → OpenSearch index, `PXM_STATE_MACHINE_ARN` → Step Functions orchestrator (otherwise the in-process `LocalOrchestrator`).
- **Logging:** structured `log_event(...)` calls (`shared/observability.py`) carry a correlation id through a run; Lambdas run with X-Ray active tracing. Logs land in CloudWatch.
- **IAM is least-privilege:** agent/BFF roles grant `bedrock:InvokeModel` scoped to `anthropic.*` + `amazon.titan-embed-*`, `bedrock-agentcore:InvokeAgentRuntime`, DynamoDB read/write on the table, Step Functions start/task-response, and scoped OpenSearch `aoss:APIAccessAll` + a data-access policy.
- **You customize** (don't hardcode — keep configurable): enrichment/compliance stage logic, the `data/` master data + RAG corpus, the channel adapters, the model IDs, and the CDK stack parameters.

## What you're NOT building

- **Not fully autonomous publish.** Compliance blockers and channel publishing stay behind the HITL gate by design. Do not wire blockers straight to publish.
- **Not an LLM-owned compliance verdict.** The blocker decision is deterministic rule matching against the regulation corpus. The model never decides compliance.
- **Not a new model.** Use Bedrock-hosted Claude + Titan embeddings (or an AgentCore runtime). Don't fine-tune or stand up custom inference.
- **Not a single-tenant store.** Tenancy is pool-based — never drop the tenant prefix from a key or the tenant check from a read.
- **Not a copy of the source into the kit folder.** The kit holds metadata + specs; the implementation is built from this spec in your own repository.

## Non-negotiables

- **The four stages are explicit and ordered.** Enrich → classify → copy → compliance. Don't collapse them into one opaque call — the per-stage structure is what makes a run auditable.
- **Compliance is deterministic and cited.** Every blocker names the `reg_id` and `citation_url`. Never ship a finding without its citation.
- **The HITL gate is real.** In AWS it is `waitForTaskToken` with a 3-day timeout; locally it is `LocalOrchestrator`'s PAUSED_REVIEW state. A blocker pauses the run; only an operator decision resumes it.
- **The lifecycle state machine is the single source of truth.** All status changes go through `shared/lifecycle.py`; invalid transitions raise `InvalidTransition`. It is property-tested — keep it that way.
- **One validated write path.** Product writes go through `MasterDataService`; immutable fields (`tenant_id`, `product_id`, `sku`, `created_at`, `created_by`) can never change.
- **Tenant isolation + role authZ on every operation** via `TenantContext` and the `_ACTION_ROLES` matrix in `services/api_bff/auth.py`.

## Defaults

- **Model:** `anthropic.claude-3-5-sonnet-20240620-v1:0` (text) + `amazon.titan-embed-text-v2:0` (embeddings). Region `us-east-1`.
- **Deploy target:** six CDK stacks via `cdk deploy --all` (or `./deploy.sh`), single dev account/region, all resources `RemovalPolicy.DESTROY` for easy teardown.
- **Naming:** `pxm` DynamoDB table, `pxm-rag` OpenSearch collection, `Pxm*` stacks (rename per deployment).

## Things to confirm before customizing

- What is your product/supplier/regulation master-data model, and where does it live today?
- Which **taxonomy** do they classify against, and what are your **brand-copy** guidelines?
- Which **target markets** and **regulations** must each SKU satisfy (the seeded set covers US-CPSC-LEAD, EU-RoHS, US-FTC-CLAIMS, EU-CLP)?
- Which **channels** do they publish to (replacing `MockMarketplaceAdapter`)?
- What are your roles/tenancy needs — how many brands share the deployment, and who can approve a blocker?
- Latency/cost posture: Bedrock `InvokeModel` vs. an AgentCore runtime?

## When to pause and flag for review mid-build

- You want fully autonomous publish with no human review of blockers (out of scope — escalate).
- There's no structured master data / taxonomy / regulation corpus to feed the agent.
- A strict on-premises-only requirement (the kit is cloud-native on Bedrock + CDK).
- Bedrock model access for Claude 3.5 Sonnet / Titan embeddings isn't enabled in the account/region.
- Catalog volume is too low to justify the build + the OpenSearch Serverless always-on cost.

## Done definition

- A sparse `ProductDraft` ingests to `DRAFT`, runs the four stages, and lands in `APPROVED` (clean) or `NEEDS_REVIEW` (blocker).
- A blocker SKU pauses the saga at the HITL gate; an operator approve resumes to publish, a reject ends in `REJECTED`.
- A clean SKU auto-approves and publishes to the channel, returning a listing id.
- Compliance findings cite `reg_id` + `citation_url`; runs and transitions are logged with a correlation id.
- The provider abstraction runs offline (`fake`) and against Bedrock (`bedrock`) without code changes.
- Acceptance tests in [`build-spec/acceptance-tests.md`](build-spec/acceptance-tests.md) pass; the backend `pytest` suite (incl. Hypothesis PBT) is green.
- Deployed to your account via `cdk deploy --all`, seeded, with a Cognito user created and least-privilege roles confirmed.

## Repository convention

This kit folder (`agentic-pxm-platform/`) is **catalog metadata**, not the agent's source code. No source is included — the agent is built from this spec in your own repository. Do **not** add agent code under this folder. To extend the agent, change your implementation and verify it against [`build-spec/acceptance-tests.md`](build-spec/acceptance-tests.md).
