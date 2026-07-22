# Acceptance Tests — Sentinel Auto-Loan Fraud Detection

> Audience: you and your engineering lead during sign-off. Each test maps to requirements in [`requirements.md`](requirements.md).

## Functional

**T1 — Identity agent scores synthetic identity.**
- *Setup:* an application with an SSN issued after the applicant's stated birth year.
- *Action:* run the pipeline (mock or live).
- *Expected:* identity agent returns an elevated `identity_risk_score` with a finding citing the SSN-vs-age mismatch.
- *Maps to:* FR1.

**T2 — Velocity agent detects stacking.**
- *Setup:* an application sharing address/phone with recent applications.
- *Action:* run the pipeline.
- *Expected:* velocity agent returns an elevated `velocity_risk_score` with a stacking finding.
- *Maps to:* FR1.

**T3 — Financial agent flags income/occupation mismatch.**
- *Setup:* income inconsistent with occupation, or thin equity on high-value collateral.
- *Action:* run the pipeline.
- *Expected:* financial agent returns an elevated `financial_risk_score` with a corresponding finding.
- *Maps to:* FR1.

**T4 — Deterministic verdict mapping.**
- *Setup:* the three tuned sample scenarios.
- *Action:* run each.
- *Expected:* scores land in distinct tiers and map correctly — APPROVE (<35), FLAG (35–69), DECLINE (≥70). Reference samples: ~8/APPROVE, ~40/FLAG, ~74/DECLINE.
- *Maps to:* FR2.

**T5 — Verdict stable across mock and live.**
- *Setup:* same application.
- *Action:* run in mock mode and live mode.
- *Expected:* `final_score` and `recommendation` are identical (narrative may differ); the score is code-computed in both.
- *Maps to:* FR2, NFR5.

**T6 — Explainable output present.**
- *Setup:* any assessment.
- *Action:* inspect the result.
- *Expected:* per-dimension score contributions, a plain-language narrative, top risk factors, and per-agent provenance (source/model/latency) are all present.
- *Maps to:* FR3.

**T7 — Mock mode runs with no AWS creds.**
- *Setup:* `MOCK_MODE=true`, no credentials.
- *Action:* run the pipeline.
- *Expected:* a full deterministic assessment returns; no Bedrock call is made.
- *Maps to:* FR4.

**T8 — Graceful fallback on Bedrock failure.**
- *Setup:* live mode with invalid creds or a forced exception.
- *Action:* run the pipeline.
- *Expected:* affected agents fall back to heuristics; the pipeline completes; provenance badge shows `heuristic`. No hard failure.
- *Maps to:* FR4, NFR2.

**T9 — SSE progress streaming.**
- *Setup:* the streaming endpoint.
- *Action:* `POST /api/assess/stream`.
- *Expected:* ordered `agent_start`/`agent_complete` events per agent, then a final `complete` event with the assessment.
- *Maps to:* FR5.

**T10 — Grounded analyst chat streams.**
- *Setup:* a stored assessment.
- *Action:* `POST /api/chat/stream` with a question.
- *Expected:* a token-streamed answer grounded in that assessment's data.
- *Maps to:* FR5, FR6.

**T11 — Single-origin serving.**
- *Setup:* built SPA present (`frontend/dist`).
- *Action:* request the root and an API path from the same origin.
- *Expected:* SPA served and API responds from one origin; API routes take precedence.
- *Maps to:* FR7.

## Non-functional

**T12 — Latency within interactive bounds (default tier).**
- *Action:* run a 4-agent live pass on Sonnet 4.5.
- *Expected:* completes in interactive time (~10s/agent reference); Opus runs documented as batch-only.
- *Maps to:* NFR1.

**T13 — Least-privilege instance role.**
- *Action:* inspect the App Runner instance role policy.
- *Expected:* only `bedrock:InvokeModel` / `InvokeModelWithResponseStream` on Anthropic models + inference profiles. No broader grants.
- *Maps to:* NFR3.

**T14 — Single-tenant isolation.**
- *Action:* review the deployment.
- *Expected:* one deployment in your account/region; no shared multi-tenant store.
- *Maps to:* NFR6.

## Operational

**T15 — Health endpoint.**
- *Action:* `GET /api/health`.
- *Expected:* `status: ok` with mode, region, default model, and assessment count.
- *Maps to:* operational readiness.

**T16 — Unit/property test suite passes.**
- *Action:* `MOCK_MODE=true pytest -q` in `backend/`.
- *Expected:* all tests pass (reference: 16 incl. a Hypothesis property test).
- *Maps to:* FR2, NFR5.

## Sign-off

| Role | Name | Date |
|---|---|---|
| Reviewer | __________ | ______ |
| Your engineering lead | __________ | ______ |
