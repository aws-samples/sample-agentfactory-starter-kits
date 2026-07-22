# Requirements — TriageAI Patient Triage

> Audience: a coding agent implementing or customizing the kit.

## Functional requirements

**FR1 — Structured patient intake.** The system shall accept a patient intake form (`TriageRequest`) capturing name, email, age, sex, symptom description, symptom duration (from a fixed allowed set), pain level (0–10), known conditions, and submitted-by (patient or nurse).
Input is validated server-side with Pydantic (and client-side in the SPA); malformed input is rejected before any model call. *Maps to: T1, T2.*

**FR2 — AI urgency + department classification.** The system shall classify each intake into an `urgency` (low / medium / high / critical) and a recommended `department` (ER / Primary Care / Mental Health / Specialist Referral) via a single Bedrock (Claude) Converse call.
The model may only return values from the fixed urgency and department enums. *Maps to: T3, T4.*

**FR3 — Explainable, schema-validated output.** Each triage result shall include `next_steps`, `reasoning`, `estimated_wait`, a `red_flags` list (0–10), and `follow_up_questions` (0–3), validated against `TriageResult`. The model response shall be parsed, code-fence-stripped, and schema-validated; on schema-invalid output the engine shall retry once. *Maps to: T5, T6.*

**FR4 — Deterministic safe-default fallback.** On any Bedrock failure (timeout, AWS error, or schema-invalid after the retry) the system shall return a deterministic safe-default result — medium urgency, Primary Care, `model_id="fallback"` — and tag the case `ai_fallback`. The triage flow shall never hard-fail. *Maps to: T7, T8.*

**FR5 — Case lifecycle + staff queue.** Each submission shall create a `PENDING` `Case`, transition to `TRIAGED` on completion (with `triaged_at`), and appear in a staff queue ordered urgency-descending then submitted-at-ascending so critical cases surface first. *Maps to: T9, T10.*

**FR6 — Staff access control.** Staff routes (queue list, case detail) shall require a valid Bearer session token obtained by exchanging a shared passcode; the passcode comparison shall be constant-time and tokens shall expire. *Maps to: T11, T12.*

**FR7 — Nurse-on-behalf submission.** The intake form shall support submission by a patient (self) or a nurse on the patient's behalf, recorded in `submitted_by`. *Maps to: T2.*

## Non-functional requirements

**NFR1 — Latency.** A triage call shall complete within an interactive budget; the engine enforces an 8-second timeout (`BEDROCK_TIMEOUT_SECONDS`) on the Converse call (run on a worker thread) and returns the fallback rather than blocking indefinitely.

**NFR2 — Availability / resilience.** The system shall never hard-fail on Bedrock unavailability; the deterministic fallback guarantees a routed case.

**NFR3 — Security.** Traffic shall be served over TLS. Every response shall carry the 5 security headers (CSP, HSTS, X-Content-Type-Options, X-Frame-Options, Referrer-Policy). Requests shall be rate-limited (10/min triage, 5/min login), body-size-limited (64 KB), and CORS-restricted to an explicit origin allowlist. The app shall refuse to start without `STAFF_PASSCODE` and `STAFF_SESSION_SECRET`. The Bedrock IAM grant shall be least-privilege (`bedrock:InvokeModel` on the Claude family only).

**NFR4 — PHI protection.** `patient_name` and `email` shall never appear in the model prompt (excluded by construction) or in logs (allowlist-first redacting JSON logger with a defense-in-depth PHI-marker scan). The in-memory store shall be scrubbed on shutdown.

**NFR5 — Cost predictability.** Bedrock cost shall scale linearly with intake volume — one Converse call per intake on the low-cost Haiku tier; the model id/tier is configurable.

**NFR6 — Single-tenancy.** One deployment per organization in your own account/region; the only outbound dependency is the in-region Bedrock invocation.

## Out of scope

- Autonomous clinical decisions or actions (this is clinician decision-support).
- Persistent datastore (reference is in-memory, scrubbed on shutdown; production persistence is a customization).
- A real identity provider (reference uses a shared passcode → signed session token).
- EHR / scheduling / messaging integrations.
- Multi-language support, mobile-native app, email/SMS notifications, manual case reassignment (explicit non-goals per the source's `requirements.md` §5).
- Cloud IaC (CDK/ECS/etc.) — the reference is local-only; the deployment target is built per deployment.

## Dependencies

- Bedrock model access enabled for Claude 3.5 Haiku in your region (`us-east-1` default).
- AWS credentials with `bedrock:InvokeModel` (and `bedrock:ListFoundationModels` for the preflight script).
- Compute to host the FastAPI backend + built React SPA in your account.
- Python 3.11 and Node 20.x for build/run; openssl for the local TLS cert.
- Structured intake data with symptom, duration, and pain-level signal.
