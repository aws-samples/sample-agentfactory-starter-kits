# Requirements — Clinical Documentation Agent

> Audience: a coding agent implementing this kit. Each requirement names the acceptance tests in `acceptance-tests.md` that verify it.

## Functional requirements

### FR1 — Session intake
The system accepts a session with `patient_id`, `session_type` (cbt, med_management, crisis, intake, dbt, group), `modality` (in-person, telehealth), `duration_min`, `provider_credential`, and a transcript supplied either by `transcript_id` (catalog) or `transcript_text` (free text). Transcripts over 20,000 characters are rejected with HTTP 413. **Tests:** T1, T12.

### FR2 — Pre-session context (U1)
Before any drafting, the system loads the patient's treatment goals, previous-session summary, homework assigned, PHQ-9 and GAD-7 trends, active diagnoses, and remaining authorized sessions. If fewer than 3 sessions remain, the context carries an `auth_alert` surfaced in the clinician UI and audit trail. **Tests:** T2, T3.

### FR3 — Template selection
The system selects a note template from session type, modality, and provider preference: CBT Session, Med Management, Crisis Assessment, Initial Psychiatric Eval, DBT Individual, Group Therapy, SOAP, or DAP. Each template defines its required sections. **Tests:** T2.

### FR4 — Diarized transcription (U2)
The system produces timestamped utterances labeled by speaker (clinician / patient) with a per-utterance confidence. In the prototype this parses `CLINICIAN:`/`PATIENT:`-prefixed text (also THERAPIST/PROVIDER/DR/DOCTOR and CLIENT); unprefixed lines inherit the previous speaker. In production this reads Amazon Connect Health ambient-documentation transcripts from S3. **Tests:** T1.

### FR5 — Structured note with evidence map (U3)
The system fills every section of the selected template from the transcript and context only, and records an `evidence_map` linking each claim to the utterance index (or Connect Health evidence reference) that supports it. The Risk Assessment section is populated **only** from transcript evidence of an SI/HI screening; if none exists the section is left empty. The system never generates risk language that the transcript does not support. **Tests:** T1, T4, T8.

### FR6 — Coding with confidence and credential scope (U4)
The system carries forward active ICD-10 diagnoses, selects a CPT code deterministically — psychotherapy by documented duration (≤37 min → 90832, 38–52 → 90834, ≥53 → 90837), crisis → 90839, medication management → E&M 99214 — adds applicable add-ons (90785, 90863) and modifier 95 for telehealth, and attaches a confidence and rationale to each code. If any selected code is prescriber-only (99213, 99214, 99215, 90863) and `provider_credential` is not in {MD, DO, NP, PA, PMHNP}, `credential_scope_ok` is false with an explanatory `credential_note`. **Tests:** T5, T6, T7, T9.

### FR7 — Blocking QA (U5)
The system runs seven checks and reports each as PASS, WARN, or FAIL with detail: (1) required sections present, (2) risk assessment documented for mental-health templates, (3) CPT matches documented duration, (4) diagnosis present, (5) hallucination — note content grounded in transcript/context or an allowed clinical vocabulary, (6) credential scope, (7) PHQ-9/GAD-7 measurement referenced. Checks 1, 2, 3, 5, and 6 are blocking (FAIL); 4 and 7 are WARN by default. `overall` is FAIL if any blocking check fails. **Tests:** T4, T5, T6, T8.

### FR8 — Clinician review and sign-off gate
After QA the session is `READY_FOR_REVIEW`. The clinician sees the note, evidence map, codes with confidence, QA report, and audit trail. Sign-off (`POST /api/sessions/{sid}/signoff`) is rejected with 409 if the session is not ready and with 422 if QA `overall` is FAIL. **Tests:** T4, T10, T11.

### FR9 — EHR write-back (U6)
On successful sign-off the system files the note and the superbill (ICD-10, CPT, add-ons, modifiers) to the EHR, records treatment-plan progress, attaches the after-visit summary, appends to the write log, and sets status `SIGNED`. Nothing is written before sign-off. **Tests:** T10, T11.

### FR10 — Audit trail
Every pipeline stage (U1–U5), sign-off, and write-back emits an `AuditEvent{ts, stage, actor, summary, detail}`. The full list is retrievable via `GET /api/sessions/{sid}/audit` and rendered in the UI. In production the list is persisted to S3 and CloudWatch Logs. **Tests:** T14.

## Non-functional requirements

### NFR1 — Privacy and HIPAA alignment
The implementation repository must contain no PHI; all seeded patients and transcripts are synthetic. Production processing occurs only in your AWS account using HIPAA-eligible services (Amazon Connect Health, Amazon Bedrock, AgentCore, S3, HealthLake) under your BAA. Audit logs never contain full transcript text — only stage summaries and evidence references. **Tests:** T13, T15.

### NFR2 — Reproducibility
Given identical inputs, the prototype produces byte-identical note, coding, and QA output (no network, no randomness; audit timestamps pinned to a fixed base). The production pipeline must keep coding and credential decisions deterministic; model-generated prose may vary. **Tests:** T9.

### NFR3 — Portability
The prototype runs with one command (`python run.py`) on Python 3.12 with six dependencies and no AWS credentials. **Tests:** T1.

### NFR4 — Latency
The prototype pipeline completes in under a few seconds per session. Production target: a signed-ready note within 2 minutes of session end (Connect Health note generation plus the AgentCore BH layer). **Tests:** T12.

### NFR5 — Extensibility
Swapping `SimulatedAgentRunner` for `BedrockAgentRunner`, or `EHRStore` for a real EHR adapter, requires no change to the orchestrator, API routes, data model, UI, or existing tests. **Tests:** T9, T16.

### NFR6 — Cost awareness
The production design enables Bedrock prompt caching on the template-and-rules prefix and supports tiering the QA stage to a smaller model. The reference design projects ~73% Bedrock cost reduction from these; treat as a target to measure, not a guarantee. **Tests:** T16 (cost review item).

### NFR7 — Security baseline
Transcript size capped at 20,000 characters (413). Sign-off state checks (409/422) prevent out-of-order writes. Production adds authentication on the API (the prototype has none), TLS, least-privilege IAM for AgentCore → S3/HealthLake, and encryption at rest (S3 SSE, HealthLake default) and in transit. **Tests:** T12, T13.

### NFR8 — Resiliency
A stage failure logs a SYSTEM audit event and surfaces the error; it does not leave a partially filed note. Write-back is atomic from the orchestrator's perspective — note and superbill are filed together or not at all. **Tests:** T11, T14.

## Out of scope

- Audio capture and ASR inside the kit (Connect Health or Transcribe Medical provides this).
- A full payer rules engine — the coding rules are a representative BH subset.
- Autonomous filing without clinician sign-off.
- Model-inferred CPT level selection.
- Multi-tenant deployment.
- Research de-identification pipeline.
- General-medicine or surgical note templates.

## Dependencies

- An AWS account with Bedrock model access for `anthropic.claude-sonnet-4-5-20250929-v1:0` (and optionally a Haiku-class model) in the chosen region.
- Amazon Connect Health available in the region with the Psychiatry specialty (hybrid path), or an alternative transcript source (custom path).
- A patient-consent workflow for session recording (you own this).
- An EHR write-back API or a HealthLake FHIR R4 datastore, and the engineering capacity to build the adapter.
- Signed BAA with AWS covering the services above.
- Python 3.12 for the prototype; Strands Agents SDK for `BedrockAgentRunner`.

## Open extension points (post-v1)

- Promote measurement-based care (check 7) to FAIL if you require PHQ-9/GAD-7 every N sessions.
- Group-therapy and IOP/PHP per-diem coding.
- Treatment-plan progress auto-linking to goals in AgentCore Memory.
- Clinician-specific style preferences for note prose.
