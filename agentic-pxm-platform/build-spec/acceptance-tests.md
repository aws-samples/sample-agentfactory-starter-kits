# Acceptance Tests — Agentic PXM Platform

> For sign-off with your engineering lead. Each test maps to requirements in [`requirements.md`](requirements.md). The reference fixtures (`data/products.json`) provide clean SKUs (`SKU-AUDIO-01`, `SKU-HOME-01`, `SKU-APPAREL-01`) and blocker SKUs (`SKU-TOY-LEAD` → lead, `SKU-BEAUTY-01` → "cures cancer" / "100% safe").

## Functional

**T1 — SKU ingestion creates a DRAFT product.**
- *Setup:* a sparse `ProductDraft` (sku, title, target_markets) and an admin `TenantContext`.
- *Action:* call `create_product`.
- *Expected:* a `Product` is created in `DRAFT` with tenant + creator stamped; an invalid SKU format is rejected.
- *Maps to:* FR1.

**T2 — Attribute normalization is idempotent.**
- *Setup:* a product with mixed-case keys and unit tokens (e.g. `"KG"`).
- *Action:* run `normalize_attributes` once, then again on its output.
- *Expected:* keys lowercased/stripped, units standardized, output sorted; running twice yields the same result (property-tested, PBT-04).
- *Maps to:* FR2.

**T3 — Classification + copy are RAG-grounded.**
- *Setup:* the seeded taxonomy + brand corpus; a product with a `category_hint`.
- *Action:* run the classify and copy stages.
- *Expected:* a taxonomy category is assigned (hint honored, else inferred from retrieved passages) and a title + short + long description are produced; the enriched fields persist via the validated write path.
- *Maps to:* FR2.

**T4 — Compliance check flags a restricted substance.**
- *Setup:* `SKU-TOY-LEAD` (lead) targeting `US`, with `US-CPSC-LEAD` in the corpus.
- *Action:* run the enrichment pass.
- *Expected:* a `BLOCKER` `Finding` is emitted citing `reg_id=US-CPSC-LEAD` and its `citation_url`; `needs_review = true`.
- *Maps to:* FR2, FR3.

**T5 — Compliance check flags a prohibited claim; clean SKU passes.**
- *Setup:* `SKU-BEAUTY-01` ("cures cancer", "100% safe") for `US` (`US-FTC-CLAIMS`); and a clean SKU (`SKU-AUDIO-01`).
- *Action:* run both.
- *Expected:* the beauty SKU produces a `BLOCKER` citing `US-FTC-CLAIMS`; the clean SKU produces only `PASS` findings and `needs_review = false`.
- *Maps to:* FR3, FR4.

**T6 — Clean SKU auto-approves.**
- *Setup:* a clean SKU (no blocker).
- *Action:* start a run.
- *Expected:* the product transitions `draft → enriching → approved` with no human action (AutoApprove path).
- *Maps to:* FR4.

**T7 — Blocker SKU pauses at the HITL gate.**
- *Setup:* a blocker SKU.
- *Action:* start a run.
- *Expected:* the product transitions `enriching → needs_review`, a `ReviewItem` (with findings, and a task token in AWS) is created, and the saga pauses (PAUSED_REVIEW locally / `waitForTaskToken` in AWS). No publish occurs.
- *Maps to:* FR4, FR5.

**T8 — Operator approve resumes to publish; reject ends in REJECTED.**
- *Setup:* a paused blocker SKU and an operator context.
- *Action:* call `approve(..., publish=True)` on one; `reject(...)` on another.
- *Expected:* approve → `needs_review → approved`, then publish to the channel; reject → `needs_review → rejected`. The review item is removed.
- *Maps to:* FR5, FR6.

**T9 — Channel publish is gated on APPROVED.**
- *Setup:* a product not in `APPROVED` status.
- *Action:* attempt `channel_publish` / `publish`.
- *Expected:* publish is refused (`ChannelPublishNotAllowed` / a `REJECTED` `PublishResult`); an `APPROVED` product publishes and returns a `MOCK-<hash>` listing id, transitioning to `published`.
- *Maps to:* FR6.

**T10 — Lifecycle rejects invalid transitions.**
- *Setup:* a product in a given status.
- *Action:* attempt a transition not in the allowed table (e.g. `draft --approve-->`).
- *Expected:* `InvalidTransition` is raised; only defined `(status, event)` pairs succeed (stateful property test, PBT-06).
- *Maps to:* FR7.

**T11 — Immutable fields cannot be patched.**
- *Setup:* an existing product.
- *Action:* submit a `ProductPatch` attempting to change `sku` / `tenant_id` / `created_at`.
- *Expected:* the write is rejected; mutable fields update through the single validated write path with `updated_at`/`updated_by` refreshed.
- *Maps to:* FR8.

**T12 — RAG retrieval works on both backends.**
- *Setup:* the seeded corpus.
- *Action:* retrieve with a source filter (`taxonomy` / `brand`) in-memory, and (if deployed) against OpenSearch Serverless.
- *Expected:* top-k passages are returned ranked by similarity, filtered by source; serialization round-trips identically across backends (PBT-02).
- *Maps to:* FR9.

**T13 — Provider abstraction runs offline and on Bedrock.**
- *Setup:* `PXM_PROVIDER=fake` (no creds), then `PXM_PROVIDER=bedrock` in the deployed account.
- *Action:* run an enrichment pass under each.
- *Expected:* the fake provider produces a full deterministic result with zero AWS calls; the Bedrock provider invokes Claude + Titan without code changes.
- *Maps to:* FR10.

**T14 — Tenant isolation.**
- *Setup:* products under tenant A and tenant B.
- *Action:* read tenant B's product with a tenant-A context.
- *Expected:* no cross-tenant read; keys are tenant-prefixed and the tenant claim is enforced.
- *Maps to:* FR11, NFR5.

**T15 — Role-based authorization.**
- *Setup:* admin, operator, viewer contexts.
- *Action:* attempt `write_product`, `start_run`, `review_decision`, `publish`, and reads with each role.
- *Expected:* write_product → admin only; start_run / review_decision / publish → admin+operator; reads / chat_query → all; a forbidden action raises `ForbiddenError`.
- *Maps to:* FR11.

**T16 — End-to-end demo + test suites pass.**
- *Action:* run `python -m services.demo.run_local_demo`; run `pytest` (backend) and `npm run test` (frontend).
- *Expected:* the demo onboards all five fixture SKUs (clean → auto-approve + publish; blockers → HITL → reject); the backend `pytest` + Hypothesis suite and the frontend Vitest + fast-check suite pass with no AWS credentials.
- *Maps to:* FR2, FR12, NFR2, NFR3, NFR7.

## Non-functional

**T17 — Saga retry/resilience.**
- *Action:* inspect the state machine task definitions.
- *Expected:* each task retries on `States.TaskFailed`/`States.Timeout` (2s interval, 3 attempts, 2.0 backoff); the review gate has a 3-day task timeout.
- *Maps to:* NFR2.

**T18 — Least-privilege IAM.**
- *Action:* inspect the agent/BFF role policies.
- *Expected:* `bedrock:InvokeModel` scoped to `anthropic.*` + `amazon.titan-embed-*`; DynamoDB scoped to the table; Step Functions start/task-response; scoped OpenSearch access. No broad grants beyond the documented AgentCore `*` (flagged to tighten).
- *Maps to:* NFR4.

## Sign-off

| Role | Name | Date |
|---|---|---|
| Build lead | __________ | ______ |
| Your engineering lead | __________ | ______ |

The kit's `kit.json.status` can be bumped from `draft` to `published` when T1–T18 pass against the customized instance, you have run the functional tests against real production-shaped SKUs, and the sign-off table above records the certifier.
