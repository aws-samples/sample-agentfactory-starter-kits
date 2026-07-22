# Acceptance Tests — Agentic Insurance Advisor

> For sign-off with your engineering lead. Each test maps to requirements in [`requirements.md`](requirements.md). Run against the six sample clients first, then against your real client-shaped data.

## Functional

**T1 — Supervisor orchestrates the full workflow.**
- *Setup:* a seeded client (e.g. Michael Torres — 48, married, 3 dependents, term expiring 2028) and an advisory type.
- *Action:* start an advisory and let it run to completion.
- *Expected:* the consolidated package contains all three sections — retrieved products, per-product suitability, and a letter — produced in order by the three specialists under the supervisor.
- *Maps to:* FR1.

**T2 — Supervisor passes full context and returns output verbatim.**
- *Setup:* any client.
- *Action:* inspect the package against each sub-agent's raw output.
- *Expected:* the supervisor passed the full client profile to each sub-agent and the letter + per-rule reasoning appear verbatim (not summarized away).
- *Maps to:* FR1.

**T3 — Grounded product retrieval with citations.**
- *Setup:* the KB synced over the (sample or your own) carrier catalog.
- *Action:* run retrieval for a client.
- *Expected:* 3–5 ranked products, each an actual catalog product (e.g. Guardian Shield Term Life, Summit Financial Fixed Annuity) with carrier/product/coverage/premium/eligibility/match-rationale and **source citations**; no invented products or eligibility.
- *Maps to:* FR2, NFR5.

**T4 — Suitability evaluates every product against all eight rules.**
- *Setup:* a client with retrieved products.
- *Action:* run suitability.
- *Expected:* each product has a pass/fail line for SUIT-01…SUIT-08 with reasoning and the rule ID cited, plus an overall verdict.
- *Maps to:* FR3, NFR2.

**T5 — Verdict logic precedence holds.**
- *Setup:* construct cases — (a) a product violating an UNSUITABLE rule (e.g. SUIT-02 premium > 10% income), (b) a product passing all rules, (c) a product with only CONDITIONAL flags (e.g. SUIT-04 coverage gap).
- *Action:* run suitability on each.
- *Expected:* (a) → UNSUITABLE; (b) → SUITABLE; (c) → CONDITIONAL. Any UNSUITABLE rule forces overall UNSUITABLE.
- *Maps to:* FR4, NFR2.

**T6 — Rules are externalized and editable without code change.**
- *Setup:* edit a threshold in `data/rules/suitability-rules.yaml` (e.g. the SUIT-02 affordability ceiling from 10% to 8%), re-upload to S3.
- *Action:* re-run suitability on a borderline client.
- *Expected:* the verdict reflects the new threshold; no code was changed or redeployed.
- *Maps to:* FR5.

**T7 — Recommendation letter has all required sections.**
- *Setup:* a client with at least one SUITABLE/CONDITIONAL product.
- *Action:* generate the letter.
- *Expected:* header, client summary, products considered, recommendation + rationale, suitability justification, disclosure block, and next steps — all present, in markdown.
- *Maps to:* FR6.

**T8 — Disclosure block on every letter.**
- *Setup:* run advisories for several different clients.
- *Action:* inspect each letter.
- *Expected:* the standard not-FDIC-insured / not-a-deposit / not-financial-advice disclosure appears verbatim on every letter.
- *Maps to:* FR6.

**T9 — Async job creation.**
- *Setup:* the deployed API.
- *Action:* `POST` the advisory endpoint.
- *Expected:* returns **`202` with a `jobId`** immediately; the agent work runs asynchronously (self-invoke), not on the request thread.
- *Maps to:* FR7, NFR1.

**T10 — Job status transitions and result retrieval.**
- *Setup:* a started job.
- *Action:* poll `get_job_status`, then `get_job_result` once complete.
- *Expected:* status moves through `retrieval_complete` → `analysis_complete` → `complete`; the result endpoint returns the consolidated package.
- *Maps to:* FR7, FR8.

**T11 — Partial results persisted per stage.**
- *Setup:* a job mid-run.
- *Action:* read the `advisory-jobs` row after the suitability stage.
- *Expected:* `productResults` and `suitabilityResults` are populated before `letterResult`; the row reflects progress.
- *Maps to:* FR8, NFR2.

**T12 — Graceful partial-results on sub-agent failure.**
- *Setup:* force a sub-agent (e.g. recommendation) to fail or time out.
- *Action:* run an advisory.
- *Expected:* the supervisor reports the failure and returns the available stages (products + suitability) rather than a blank package; no hard crash.
- *Maps to:* FR9.

**T13 — Producer UI renders all tabs and exports the letter.**
- *Setup:* a completed advisory in the SPA.
- *Action:* open the result; switch tabs; export the letter.
- *Expected:* Products / Suitability / Letter / Full Package tabs render; the letter exports as markdown.
- *Maps to:* FR10.

## Non-functional

**T14 — Async UX within interactive bounds.**
- *Action:* run a full advisory and observe the UI.
- *Expected:* the request returns immediately (`202`); the progress tracker advances; the full run completes in ~1–3 min on the configured model mix without blocking the producer.
- *Maps to:* NFR1.

**T15 — Least-privilege IAM and single-tenancy.**
- *Action:* inspect the four IAM roles and the deployment.
- *Expected:* the agent role scopes `InvokeModel` to the specific Sonnet/Nova ARNs; the KB role to the product bucket + OpenSearch; the action role to the rules bucket (read) + jobs table (update); one deployment in your account/region. No stray `*` on model/data actions.
- *Maps to:* NFR3, NFR6.

**T16 — Cost envelope sanity check.**
- *Action:* review the OpenSearch Serverless OCU floor and per-advisory Bedrock token math against expected volume.
- *Expected:* projected cost is within the kit's stated ROI envelope; the OCU floor is acknowledged as the low-volume driver.
- *Maps to:* NFR4.

## Operational

**T17 — Knowledge Base re-sync.**
- *Action:* add/replace a product document and re-sync the KB.
- *Expected:* the new/updated product appears in retrieval; a removed product no longer surfaces.
- *Maps to:* operational readiness (Day-2).

## Sign-off

| Role | Name | Date |
|---|---|---|
| Build lead | __________ | ______ |
| Your engineering lead | __________ | ______ |
| Your compliance reviewer (suitability rules + disclosure) | __________ | ______ |

The kit's `kit.json.status` can be bumped to `published` when T1–T13 pass on sample data, T14–T16 are verified, you have run T1–T8 against real production-shaped data, compliance has signed off the suitability rules and disclosure block, and the sign-off table above records the certifier.
