# Acceptance Tests — Payment Fraud Detector

These tests must all pass before the kit's `status` is bumped from `draft` to `published` (or before signing off your deployment). You run them with your engineering lead.

## How to run

For each test:
1. Set up the test condition in your deployed environment
2. Run the action
3. Verify the expected behavior (functional + audit log)
4. Mark pass/fail

Tests T1–T8 should be automated (implement them as `mcp-server/test_*.py` in your build). Tests T9–T16 are manual / observational.

---

## Functional tests

### T1 — Rules engine fires on known-fraud test data
**Setup:** Bundled `data/pharmacy/transactions.json` includes seeded fraud patterns.
**Action:** Run the analyzer against the bundled data via the MCP server `/analyze` endpoint.
**Expected:** Rules engine returns expected number of fires for unregistered-receivers, threshold-avoidance, self-dealing, and excessive-frequency rules. Counts match `mcp-server/test_mcp_endpoints.py` expectations.
**Maps to:** FR1, FR2

### T2 — LLM narrative references actual rule fires
**Setup:** Run an analyst session against bundled pharmacy data.
**Action:** Inspect the LLM response.
**Expected:** Narrative references at least one rule fire by ID or description, and does not fabricate fires that didn't happen.
**Maps to:** FR3

### T3 — Decision-support only (no auto-action)
**Setup:** Inspect the kit's code paths for any auto-block / auto-quarantine / auto-action logic.
**Action:** Code review.
**Expected:** No code path takes any action on flagged transactions beyond logging and returning to the analyst.
**Maps to:** FR4

### T4 — Local Folder data source mode
**Setup:** Configure Streamlit to use Local Folder mode pointing at `data/pharmacy/`.
**Action:** Run an analysis session.
**Expected:** Same rule fire counts as the S3 mode would produce against identical data.
**Maps to:** FR5

### T5 — S3 data source mode
**Setup:** Upload `data/pharmacy/*.json` to your S3 bucket. Configure Streamlit to use S3 mode pointing at the bucket.
**Action:** Run an analysis session.
**Expected:** Same rule fire counts as Local Folder mode for identical data. Streamlit can switch between modes without restart.
**Maps to:** FR5

### T6 — Bedrock Agent uses RETURN_CONTROL action groups
**Setup:** Inspect Bedrock Agent action group config (`bedrock-agent/bedrock_config.json`).
**Action:** Verify executor type.
**Expected:** Action group executor is `RETURN_CONTROL` pointing at MCP server endpoints. No direct Lambda action groups.
**Maps to:** FR6

### T7 — Streamlit UI has all required views
**Setup:** Open Streamlit UI in a browser.
**Action:** Navigate through all tabs.
**Expected:** Dashboard, alerts, raw-data, senders, coordinators tabs all load and display data. Each tab is functional (not placeholder).
**Maps to:** FR7

### T8 — Concurrent sessions don't leak state
**Setup:** Run `mcp-server/test_concurrent_requests.py`.
**Action:** Multiple parallel sessions analyzing different data.
**Expected:** Each session sees only its own data; no rule fires bleed across sessions.
**Maps to:** FR9

---

## Non-functional tests

### T9 — Rule engine latency
**Setup:** Run `mcp-server/test_autoscaling.py` or load test directly.
**Action:** Issue 1000 sequential analysis requests against the MCP server.
**Expected:** p95 < 100 ms for pure rule engine analysis (no LLM in the path).
**Maps to:** NFR1

### T10 — End-to-end latency
**Setup:** Run 50 full analyst sessions (rules + LLM narrative).
**Action:** Measure end-to-end response time.
**Expected:** p95 < 30 s. Most latency is Bedrock token generation; ALB + MCP add <1 s.
**Maps to:** NFR2

### T11 — HTTPS-only at the ALB
**Setup:** Try HTTP request to the ALB on port 80.
**Action:** Send `curl http://<alb-dns>/`.
**Expected:** 301 redirect to HTTPS. No HTTP content served.
**Maps to:** NFR4

### T12 — TLS 1.2+ enforcement
**Setup:** Inspect ALB listener configuration.
**Action:** Verify TLS policy.
**Expected:** Listener uses ELBSecurityPolicy-TLS13-1-2-2021-06 or stricter. No TLS 1.0 / 1.1 acceptance.
**Maps to:** NFR4

### T13 — Encryption at rest
**Setup:** Inspect S3 bucket, ALB access logs, CloudWatch log groups.
**Action:** Verify encryption configuration.
**Expected:** All use customer-managed KMS keys. No SSE-S3-only buckets in production deploys.
**Maps to:** NFR4

### T14 — Audit log replay
**Setup:** Run an analyst session that flags a transaction.
**Action:** Query CloudWatch Logs for the Bedrock Agent invocation.
**Expected:** Logs contain enough detail to reconstruct: which rule fired, what data Claude saw, what narrative Claude wrote, when, and by whom.
**Maps to:** NFR6

---

## Operational tests

### T15 — Auto-scaling under load
**Setup:** Run `mcp-server/test_autoscaling.py` with sustained load above the scale-out threshold.
**Action:** Inspect ECS service desired-count over a 10-minute window.
**Expected:** ECS service scales out from 2 → 4+ tasks within 5 minutes. Scales back in to 2 within 10 minutes after load drops.
**Maps to:** NFR3

### T16 — Stack rollback on failure
**Setup:** Intentionally introduce a CFN syntax error in a child stack.
**Action:** Run `deploy.sh`.
**Expected:** Failed child stack rolls back. Master stack rolls back. No half-deployed resources left in the account.
**Maps to:** Day-2 ops

---

## Sign-off

**Reviewer name:** _______________________
**Engineering lead:** _______________________
**Date:** _______________________

**All tests pass:** ☐ Yes ☐ No

If "No," document failing tests and remediation plan before re-running.

Once all tests pass, sign off your deployment for production cutover.
