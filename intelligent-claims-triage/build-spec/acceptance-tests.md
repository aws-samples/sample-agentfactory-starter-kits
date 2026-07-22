# Acceptance Tests — Intelligent Claims Triage

These tests must all pass before the kit's `status` is bumped from `draft` to `published` (or before signing off your deployment). Run them with your engineering lead.

## How to run

For each test:
1. Set up the test condition in your deployed environment
2. Run the action
3. Verify the expected behavior (functional + persisted record + audit log)
4. Mark pass/fail

Use the bundled sample documents (`sample-docs/`) and the demo policy (`ACM-2024-07821`) for tests that don't require your data; use real (redacted) claims for the final sign-off pass.

---

## Functional tests

### T1 — End-to-end auto-approval (happy path)
**Setup:** A low-risk claim (amount well under coverage limit, covered peril, no fraud signals) with a readable document in S3.
**Action:** `POST /claims` then `POST /claims/{id}/triage`.
**Expected:** Triage returns 202; the claim reaches `APPROVED` in DynamoDB with a `payoutAmount` equal to `min(max(amount − deductible, 0), coverageLimit)`, a non-empty `reasoning`, and populated `extractedData` + `policyContext`.
**Maps to:** FR1, FR5, FR7, FR9

### T2 — End-to-end escalation
**Setup:** A high-risk claim (e.g., amount > 50% of limit + total loss + disputed liability).
**Action:** Submit and trigger triage.
**Expected:** Claim reaches `ESCALATED` with `riskScore ≥ 0.7`, an `escalationReason`, a message on the SQS review queue, and an SNS notification. No `payoutAmount`. No auto-deny.
**Maps to:** FR4, FR6, FR9

### T3 — Document extraction
**Setup:** A claim with a repair-estimate PDF (use `sample-docs/repair-estimate.pdf`).
**Action:** Run triage (or `POST /extract`).
**Expected:** Extracted fields include estimated amount and incident details; the result's `source` reflects the path used (`textract` / `pdf_raw_extraction` / etc.).
**Maps to:** FR2

### T4 — Extraction fallback on an unreadable document
**Setup:** A document Textract can't parse (e.g., an unsupported/garbled file).
**Action:** Run triage.
**Expected:** Extraction returns `source: extraction_unsupported` (or raw-PDF fallback); triage still completes using claim metadata rather than hard-failing.
**Maps to:** FR2

### T5 — Policy lookup via Knowledge Base
**Setup:** Policy documents ingested into a Bedrock KB; `KNOWLEDGE_BASE_ID` set on the agent.
**Action:** Triage a claim whose policy is in the KB.
**Expected:** `policyContext.source` is `knowledge_base` (or `knowledge_base_enriched`); coverage type, deductible, limit, perils, and exclusions reflect the document.
**Maps to:** FR3

### T6 — Policy lookup fallback (no KB)
**Setup:** `KNOWLEDGE_BASE_ID` unset.
**Action:** Triage a claim for demo policy `ACM-2024-07821`.
**Expected:** `policyContext.source` is `hardcoded_demo`; triage completes. (Acceptable for smoke test only — production must use a KB.)
**Maps to:** FR3

### T7 — Risk score is bounded
**Setup:** A claim that trips multiple risk factors at once.
**Action:** Triage and inspect `riskScore`.
**Expected:** `riskScore` is in [0.0, 1.0] and never exceeds 1.0 even when summed factors would.
**Maps to:** FR4

### T8 — Payout is bounded
**Setup:** A claim whose `estimatedAmount` exceeds the coverage limit, and another below the deductible.
**Action:** Triage both (low-risk so they auto-approve).
**Expected:** First pays exactly `coverageLimit`; second pays `0` (never negative).
**Maps to:** FR5

### T9 — Reasoning is policy-grounded
**Setup:** Any triaged claim.
**Action:** Read `reasoning`.
**Expected:** It references specific policy terms (coverage, deductible, limit, perils, or exclusions) from the retrieved `policyContext` and does not assert coverage facts absent from it.
**Maps to:** FR8

### T10 — Claim lifecycle API
**Setup:** Deployed API + valid API key.
**Action:** Exercise `POST /claims`, `GET /claims` (with `?status=` and `?policyNumber=`), `GET /claims/{id}`, `GET /claims/{id}/documents`, `POST /claims/{id}/review`, `POST /extract`.
**Expected:** Each returns the documented shape; list filters work via the GSIs; document URLs are presigned and time-limited.
**Maps to:** FR10, FR11

### T11 — Reviewer decision updates the claim
**Setup:** An `ESCALATED` claim.
**Action:** `POST /claims/{id}/review` with a reviewer decision.
**Expected:** The claim record updates to reflect the reviewer's decision.
**Maps to:** FR11

### T12 — UI end-to-end
**Setup:** Frontend configured with API URL + key.
**Action:** Submit a claim as a customer, trigger triage as an adjuster, view the decision cross-reference, work an escalation as a reviewer.
**Expected:** All three dashboards function; the decision view shows the extracted-data + policy cross-reference.
**Maps to:** FR12

---

## Non-functional tests

### T13 — Async behavior and latency
**Setup:** Submit a claim.
**Action:** Trigger triage and time the API response; then poll for terminal status.
**Expected:** `POST /triage` returns 202 in < 1 s; the claim reaches a terminal status within the worker's 5-minute budget (typically well under a minute).
**Maps to:** NFR1, FR9

### T14 — Auth enforced
**Setup:** Deployed API.
**Action:** Call any endpoint without the `x-api-key` header.
**Expected:** 403 Forbidden. With a valid key, the same call succeeds. Throttle/quota from the usage plan are in effect.
**Maps to:** NFR4

### T15 — Audit trail reconstructable
**Setup:** Any triaged claim.
**Action:** Read the DynamoDB record and the CloudWatch logs (`/aws/bedrock-agentcore/runtime/*`).
**Expected:** The record holds `riskScore`, `riskFactors`, `reasoning`, `extractedData`, `policyContext` (and `payoutAmount` / `escalationReason` as applicable); the logs show the agent's tool calls. Together they fully explain the decision.
**Maps to:** NFR6

### T16 — Agent failure is graceful
**Setup:** Force a triage failure (e.g., revoke `InvokeAgentRuntime`, or inject a tool error).
**Action:** Trigger triage.
**Expected:** The claim is marked `AGENT_ERROR` (not silently approved or left stuck); the failure is logged. No false auto-approval.
**Maps to:** FR9, NFR3

---

## Sign-off

**Technical reviewer name:** _______________________
**Engineering lead:** _______________________
**Date:** _______________________

**All tests pass:** ☐ Yes ☐ No

If "No," document failing tests and a remediation plan before re-running.

Once all tests pass, bump `kit.json.status` from `draft` to `published` (catalog) or sign off you deployment for production cutover, and record who certified the build and when.
