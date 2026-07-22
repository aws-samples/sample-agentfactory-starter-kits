# AGENTS.md — TriageAI Patient Triage

> **Audience: a coding agent** (Kiro / Claude Code / etc.) re-implementing or customizing this kit for your organization.

## What this is

- A **patient-intake + clinical-triage** application. A symptom intake form goes in; a structured triage decision comes out and lands in a staff queue.
- **One Bedrock (Claude) invocation per intake** via the **Converse API**, not a multi-agent pipeline and not an AgentCore harness. A single PHI-aware user-turn prompt asks the model to return strict JSON.
- The model returns `urgency` (low/medium/high/critical), `department` (ER / Primary Care / Mental Health / Specialist Referral), `next_steps`, `reasoning`, `estimated_wait`, `red_flags` (0–10), and `follow_up_questions` (0–3). The response is **schema-validated with Pydantic** (`TriageResult`).
- A **deterministic safe-default fallback** applies on any failure (timeout, AWS error, schema-invalid after one retry): the case is routed to Primary Care at medium urgency, `model_id="fallback"`, and tagged `ai_fallback`. The pipeline never hard-fails.
- Delivery surface: **FastAPI backend** (`/api/triage`, staff routes, `/healthz`) + **React/Vite/TypeScript SPA** (intake form, result view, staff login, urgency-sorted queue, case detail). Reference persistence is an **in-memory store scrubbed on shutdown**.

## The target implementation, file by file

No source code ships in this kit — you build the implementation from this contract. The paths below describe the target layout and where each piece of key logic lives:

1. `TRIAGEAI.md` — what the agent does, the architecture sketch, the demo script (incl. the critical-case and fallback walkthroughs).
2. `backend/src/triageai/triage/prompt.py` — the triage prompt and JSON output contract. The prompt *is* the capability definition; note name/email are excluded by design.
3. `backend/src/triageai/triage/bedrock.py` — `BedrockTriageEngine`: the Converse call, the retry-then-fallback logic, JSON extraction, and schema validation.
4. `backend/src/triageai/domain/models.py` + `enums.py` — `TriageRequest` / `TriageResult` / `Case` schemas and the urgency/department taxonomy. This is the data contract.
5. `backend/src/triageai/triage/fallback.py` — the deterministic safe-default result.
6. `backend/src/triageai/triage/service.py` — the orchestrator: validate → create PENDING case → triage → mark TRIAGED (or fallback).
7. `backend/src/triageai/repository/memory.py` — the in-memory case store and the urgency-desc / submitted-at-asc queue ordering.
8. `backend/src/triageai/api/` — `app.py` (wiring + middleware order), `routes_triage.py`, `routes_staff.py`, `auth.py`, `middleware.py`, `limiter.py`.
9. `backend/src/triageai/logging/config.py` — the allowlist-based PHI-redacting JSON logger.
10. `aidlc-docs/` — the full design documentation (requirements, business rules `RULE-*`, NFR design) behind every decision.

## Re-deploying for another tenant

1. **Replace the intake schema** — edit `TriageRequest` in `backend/src/triageai/domain/models.py` (and `ALLOWED_DURATIONS`) to match your form, plus the React form in `frontend/src/pages/IntakeForm.tsx`.
2. **Adapt the taxonomy** — edit `Urgency` and `Department` in `backend/src/triageai/domain/enums.py` to your urgency levels and service lines.
3. **Rewrite the triage prompt** in `backend/src/triageai/triage/prompt.py` for your clinical guidance and the (now-customized) JSON contract.
4. **Re-tune the safe-default** in `backend/src/triageai/triage/fallback.py` so the fallback routing matches your lowest-risk default.
5. **Configure** model id, region, timeout, retries, and rate limits in `backend/src/triageai/config.py` / `.env` (default model `anthropic.claude-3-5-haiku-20241022-v1:0`, region `us-east-1`), and attach a least-privilege `bedrock:InvokeModel` policy (template in `backend/README.md`).

## What you're NOT building

- **Not an autonomous clinical decision system.** The output is a recommendation for a human clinician. Never wire it to auto-discharge, auto-admit, or take any clinical action.
- **Not a medical device.** It is decision-support; clinical validation and regulatory posture are your responsibility.
- **Not a persistent datastore.** The reference is in-memory by design (PHI scrubbed on shutdown). A production build needs a real, encrypted store with retention controls — flag this to your team.
- **Not a multi-turn chat or a multi-agent pipeline.** It is one constrained, schema-validated Converse call per intake.
- **Not a copy of any source into the kit folder.** The kit holds metadata + specs only; the implementation is built from this contract and lives in your own repository.

## Non-negotiables

- **A human clinician always owns the decision.** The urgency/department output is a recommendation; the staff queue is the handoff to a human.
- **Never put PHI in the prompt or the logs.** `patient_name` and `email` are excluded from the prompt by construction; the logger is allowlist-first and rejects PHI markers. Keep both invariants.
- **The model output must be schema-validated.** Parse the JSON, validate against `TriageResult`, retry once on schema-invalid, then fall back. Never trust raw model text downstream.
- **The pipeline must never hard-fail.** Any timeout/error/invalid response resolves to the deterministic safe-default, tagged `ai_fallback`.
- **Constrained taxonomy.** The model may only return the four urgency values and four departments; enforce it with enums, not free text.
- **Secure by default.** Staff routes require a signed, expiring Bearer token; security headers, body-size limits, CORS allowlist, and rate limiting stay on. The app refuses to start without `STAFF_PASSCODE` / `STAFF_SESSION_SECRET`.

## Defaults

- **Model:** `anthropic.claude-3-5-haiku-20241022-v1:0` via the Bedrock **Converse** API. Region `us-east-1`. `maxTokens` 1024, `temperature` 0.2.
- **Budget:** `BEDROCK_TIMEOUT_SECONDS=8`, `BEDROCK_MAX_RETRIES=1` (one retry, on schema-invalid only).
- **Surface:** FastAPI on `:8443` (TLS), React/Vite SPA on `:5173`, staff session TTL 3600s, rate limits 10/min triage and 5/min login.

## Things to confirm before customizing

- What are your intake form fields, and which carry triage signal?
- What is your urgency scale and department/service-line taxonomy?
- Is this decision-support only, or does you expect any automated routing action (and is that acceptable to clinical/compliance)?
- What persistence, encryption, retention, and audit does production require (the reference is in-memory)?
- Is Bedrock model access enabled in your account and region, and what is your PHI/regulatory posture for sending intake text to Bedrock?

## When to flag back mid-build

- You want autonomous clinical action (out of scope — escalate).
- Intake data is unstructured or too sparse to triage meaningfully.
- You need persistence, PHI encryption-at-rest, audit retention, or EHR integration beyond the reference's in-memory demo store.
- Bedrock model access isn't enabled in your account/region, or your compliance team hasn't approved sending intake text to Bedrock.

## Done definition

- An intake submission returns a schema-valid `TriageResult` (constrained urgency + department + reasoning + red flags + follow-ups) within the timeout budget, or the deterministic fallback applies and is tagged `ai_fallback`.
- The case lands in the staff queue ordered urgency-desc, submitted-at-asc; critical cases sort to the top.
- Name/email never appear in the prompt or logs; the PHI-redaction tests pass.
- Staff routes reject missing/expired/invalid tokens; the app refuses to start without the required secrets.
- Acceptance tests in [`build-spec/acceptance-tests.md`](build-spec/acceptance-tests.md) pass; backend + frontend test suites are green.
