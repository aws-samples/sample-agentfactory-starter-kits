# Acceptance Tests — Internal Knowledge Q&A

These tests must all pass before the kit's `status` is bumped from `draft` to `published`. Run them with your engineering lead.

## How to run

For each test:
1. Set up the test condition in your deployed environment
2. Run the action
3. Verify the expected behavior (functional + audit log)
4. Mark pass/fail

Tests can be automated (recommended for T1–T8) or manual (acceptable for T9–T16). Your repo should have a `tests/` directory with at least the automated subset.

---

## Functional tests

### T1 — Grounded answer with citation
**Setup:** A document in the corpus contains a known answer to a known question.
**Action:** Ask the question through the channel surface.
**Expected:** Agent returns the correct answer + at least one citation pointing to the source document.
**Maps to:** FR1, FR2, FR7

### T2 — Decline when corpus has no answer
**Setup:** The corpus does NOT contain an answer to a specific question (e.g., "What's the company's policy on Mars colonization?").
**Action:** Ask the question.
**Expected:** Agent returns a decline message ("I don't have a documented answer for that — try [escalation path]") and no fabricated answer.
**Maps to:** FR3

### T3 — PII redaction on input
**Setup:** Submit a query that contains PII (e.g., "My email is alice@example.com — what's the policy on personal email?").
**Action:** Run the query.
**Expected:** Agent processes the query (it can still answer the policy question) but the PII is redacted in the audit log. The model never sees the PII.
**Maps to:** FR4, NFR4

### T4 — Off-topic refusal
**Setup:** Submit a clearly off-topic query (e.g., "Who's going to win the World Cup?").
**Action:** Run the query.
**Expected:** Agent refuses with a clear message indicating the query is outside its scope.
**Maps to:** FR5

### T5 — Denied-topic refusal (vertical-specific)
**Setup:** Configure a vertical-specific denied topic (e.g., "investment advice" for FinServ). Submit a query that crosses that line ("Should I buy AAPL stock?").
**Action:** Run the query.
**Expected:** Agent refuses with a denied-topic message.
**Maps to:** FR6

### T6 — Citation includes source URI
**Setup:** Same as T1.
**Action:** Inspect the answer's citations.
**Expected:** Each citation includes a working source URI (Confluence page link, SharePoint file link, S3 object path, etc.) that your identity context can resolve.
**Maps to:** FR7

### T7 — Audit log is complete
**Setup:** Run a query through the agent.
**Action:** Inspect CloudWatch Logs for that query's entry.
**Expected:** Log entry contains: timestamp, user identity, question (post-redaction), retrieved chunk IDs, cited document URIs, answer text, guardrail interventions (if any).
**Maps to:** FR8

### T8 — SSO authentication
**Setup:** Try to access the agent without authenticating through your IdP.
**Action:** Attempt query.
**Expected:** Request is rejected with an authentication error. Only authenticated users from your IdP can query the agent.
**Maps to:** FR10

---

## Non-functional tests

### T9 — Citation rate threshold
**Setup:** Have 5 employees from the target audience run a total of ≥100 real queries over 2–3 days.
**Action:** Inspect CloudWatch dashboard.
**Expected:** ≥90% of non-decline answers include a citation. Decline rate is between 5–20%.
**Maps to:** NFR1

### T10 — Latency benchmark
**Setup:** Run 50 queries against the agent over 30 minutes (synthetic load).
**Action:** Inspect latency metrics.
**Expected:** Median latency ≤3 seconds, p95 ≤8 seconds.
**Maps to:** NFR2

### T11 — Encryption at rest
**Setup:** Inspect the AWS account's resources via Console or CLI.
**Action:** Verify encryption configuration.
**Expected:** Knowledge Base storage, OpenSearch Serverless collection, and CloudWatch log group all use customer-managed KMS keys.
**Maps to:** NFR4

### T12 — Encryption in transit
**Setup:** Inspect the channel surface integration.
**Action:** Verify TLS configuration.
**Expected:** All HTTP traffic uses TLS 1.2+. No HTTP fallback.
**Maps to:** NFR4

---

## Operational tests

### T13 — New source addition
**Setup:** You want to add a second document source post-deployment.
**Action:** Follow the runbook to add the source.
**Expected:** Source is added without a full rebuild. Documents from the new source become queryable within the configured refresh window.
**Maps to:** Day-2 ops

### T14 — Source refresh
**Setup:** Update a document in the source system (e.g., revise a Confluence page).
**Action:** Wait for the configured refresh cadence (or trigger a manual refresh).
**Expected:** Subsequent queries return the updated content with a citation reflecting the latest version.
**Maps to:** Day-2 ops

### T15 — Denied topics update
**Setup:** You want to add a new denied topic post-deployment.
**Action:** Update the Guardrails policy.
**Expected:** New denied topic takes effect within the policy update window. Test query that crosses the new line is refused.
**Maps to:** Day-2 ops

### T16 — Cost monitoring
**Setup:** Run 100 queries over a measured window.
**Action:** Inspect the CloudWatch dashboard.
**Expected:** Per-query cost estimate is visible and within ±20% of the actual Bedrock + KB costs in the billing console.
**Maps to:** NFR5

---

## Sign-off

**Technical reviewer name:** _______________________
**Your engineering lead:** _______________________
**Date:** _______________________

**All tests pass:** ☐ Yes ☐ No

If "No," document failing tests and remediation plan before re-running.

Once all tests pass, bump `kit.json.status` from `draft` to `published` and record where your implementation lives.
