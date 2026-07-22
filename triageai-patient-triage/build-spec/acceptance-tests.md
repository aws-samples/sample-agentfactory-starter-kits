# Acceptance Tests — TriageAI Patient Triage

> Audience: you and your engineering lead during sign-off. Each test maps to requirements in [`requirements.md`](requirements.md).

## Functional

**T1 — Intake validation rejects bad input.**
- *Setup:* an intake with an empty name, age `999`, pain level `15`, and a malformed email.
- *Action:* submit via the SPA, then directly to `POST /api/triage`.
- *Expected:* the SPA blocks with inline field errors; a direct API call returns a 422 with no model call made.
- *Maps to:* FR1.

**T2 — Patient and nurse-on-behalf submission.**
- *Setup:* the intake form.
- *Action:* submit once as "Patient (self)" and once as "Nurse on patient's behalf."
- *Expected:* both succeed; `submitted_by` is recorded correctly and both cases appear in the staff queue.
- *Maps to:* FR1, FR7.

**T3 — Low-urgency classification + routing.**
- *Setup:* a mild, non-urgent symptom description (e.g. "mild headache for two days").
- *Action:* submit and inspect the result.
- *Expected:* `low` or `medium` urgency, Primary Care (or equivalent), plain-language next steps, no red flags.
- *Maps to:* FR2.

**T4 — Critical-case escalation.**
- *Setup:* a life-threatening description (e.g. "severe chest pain radiating to left arm with shortness of breath, started 30 minutes ago"), pain `9`, duration `< 1 hour`.
- *Action:* submit and inspect the result and queue.
- *Expected:* `critical` urgency, ER routing, prominent cardiac red flags; the case sorts to the top of the staff queue.
- *Maps to:* FR2, FR5.

**T5 — Output is schema-valid and within taxonomy.**
- *Setup:* any intake.
- *Action:* inspect the `TriageResult`.
- *Expected:* `urgency` ∈ {low, medium, high, critical}; `department` ∈ {ER, Primary Care, Mental Health, Specialist Referral}; `next_steps`, `reasoning`, `estimated_wait` present; `red_flags` ≤ 10; `follow_up_questions` ≤ 3.
- *Maps to:* FR3.

**T6 — Retry on schema-invalid model output.**
- *Setup:* force the model to return malformed/out-of-schema JSON once (test harness or stub).
- *Action:* run a triage.
- *Expected:* the engine retries once; if the retry validates, the case is `TRIAGED` normally (not fallback).
- *Maps to:* FR3.

**T7 — Deterministic fallback on Bedrock failure.**
- *Setup:* set `BEDROCK_MODEL_ID=anthropic.invalid-model` (or remove creds).
- *Action:* submit an intake.
- *Expected:* the result is medium urgency / Primary Care / `model_id="fallback"`; the case is tagged `ai_fallback`; the result page shows the "AI temporarily unavailable" banner; no hard failure.
- *Maps to:* FR4, NFR2.

**T8 — Fallback on timeout.**
- *Setup:* a forced slow/timed-out Converse call (test harness) beyond `BEDROCK_TIMEOUT_SECONDS`.
- *Action:* submit an intake.
- *Expected:* the engine returns the safe-default without retrying the timed-out call; the case routes and is tagged `ai_fallback`.
- *Maps to:* FR4, NFR1.

**T9 — Case lifecycle.**
- *Setup:* a fresh submission.
- *Action:* submit, then read the case detail.
- *Expected:* the case is created `PENDING`, transitions to `TRIAGED` with `triaged_at` set and a result attached; invariants hold (PENDING has no result; TRIAGED has both).
- *Maps to:* FR5.

**T10 — Queue ordering.**
- *Setup:* several cases across urgency tiers submitted at different times.
- *Action:* `GET /api/staff/cases` with a valid token.
- *Expected:* ordered urgency-descending then submitted-at-ascending — critical first, ties broken by earliest submission.
- *Maps to:* FR5.

**T11 — Staff auth required.**
- *Setup:* the staff routes.
- *Action:* call `/api/staff/cases` with no token, an expired token, and a tampered token.
- *Expected:* each returns 401 with no case data; only a valid Bearer token from `POST /api/staff/login` succeeds.
- *Maps to:* FR6.

**T12 — Fail-fast on missing secrets.**
- *Setup:* unset `STAFF_PASSCODE` (or `STAFF_SESSION_SECRET`).
- *Action:* start the app.
- *Expected:* startup fails with a clear ConfigError; the app does not serve.
- *Maps to:* FR6, NFR3.

## Non-functional

**T13 — PHI never reaches the prompt or logs.**
- *Setup:* an intake with a distinctive name and email.
- *Action:* run a triage with prompt/log capture (the `test_logging_redaction` suite covers this).
- *Expected:* the name and email appear in neither the built prompt nor any log line; disallowed log fields are redacted.
- *Maps to:* NFR4.

**T14 — Security headers + transport.**
- *Action:* `curl -k -I https://localhost:8443/healthz`.
- *Expected:* all 5 headers present (CSP, HSTS, X-Content-Type-Options, X-Frame-Options, Referrer-Policy); the service is HTTPS-only.
- *Maps to:* NFR3.

**T15 — Rate limiting + body-size limit.**
- *Action:* exceed 10 triage requests/min (and 5 logins/min) from one client; send a body > 64 KB.
- *Expected:* excess requests are rate-limited (429); oversized bodies are rejected (413).
- *Maps to:* NFR3.

**T16 — Least-privilege Bedrock grant.**
- *Action:* inspect the IAM policy attached to the runtime principal.
- *Expected:* only `bedrock:InvokeModel` on the Claude family (plus `bedrock:ListFoundationModels` if preflight is used). No broader grants.
- *Maps to:* NFR3, NFR6.

## Operational

**T17 — Health endpoint.**
- *Action:* `GET /healthz`.
- *Expected:* returns ok.
- *Maps to:* operational readiness.

**T18 — In-memory scrub on shutdown.**
- *Setup:* submit cases, then stop the app.
- *Action:* restart and read the queue.
- *Expected:* the queue is empty — cases do not survive a restart (prototype PHI hygiene).
- *Maps to:* NFR4.

**T19 — Test suite passes.**
- *Action:* `make test-fast` in `backend/` and `npm test` in `frontend/`.
- *Expected:* all tests pass (reference: 65 backend + 26 frontend, 12 property-based invariants incl. queue ordering, case-state transitions, validator idempotence, and no-PHI-in-logs).
- *Maps to:* FR2, FR5, NFR4.

## Sign-off

| Role | Name | Date |
|---|---|---|
| Reviewer | __________ | ______ |
| Your clinical / engineering lead | __________ | ______ |
