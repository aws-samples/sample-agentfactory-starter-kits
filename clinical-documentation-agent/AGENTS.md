# AGENTS.md — Clinical Documentation Agent

> **Audience:** a coding agent (Kiro, Claude Code, Codex, Cursor) implementing this kit in your AWS account or adapting it to your templates, payers, and EHR. Humans should start with `README.md`.
>
> **Status:** Draft, spec-only. This file is the build contract. The module and function names below are the layout the spec calls for; you create them.

## What this is

- A **five-stage behavioral-health documentation pipeline**: pre-session context (U1) → diarized transcription (U2) → structured note with evidence map (U3) → ICD-10/CPT coding with credential scope (U4) → blocking QA (U5), followed by clinician sign-off and EHR write-back (U6). An `Orchestrator.run_pipeline` runs U1→U5 in fixed order.
- Every stage is a handler behind an `AgentRunner` interface. Build a deterministic `SimulatedAgentRunner` first (pure-function Python, runs offline on synthetic data) and a `BedrockAgentRunner` second. They share the orchestrator, API, UI, and tests.
- A **FastAPI** service with routes `GET /api/catalog`, `POST /api/sessions`, `POST /api/sessions/{sid}/run`, `GET /api/sessions/{sid}`, `POST /api/sessions/{sid}/signoff`, `GET /api/sessions/{sid}/audit`, and `GET /` serving a single-page clinician review UI.
- An `EHRStore` adapter — in-memory and seeded with synthetic patients and transcripts for the prototype; your EHR API or HealthLake in production.
- A test suite (~30 tests): pipeline end-to-end, coding thresholds, credential blocking, sign-off blocking, determinism, and Hypothesis property tests on the CPT time bands.

## Where to read first

1. `build-spec/requirements.md` — FR1–FR10, NFR1–NFR8, each mapped to acceptance tests.
2. `build-spec/architecture-decisions.md` — AD3 (blocking QA), AD4 (evidence map), AD5 (deterministic coding), AD6 (credential scope), AD10 (sign-off is the only write path). These are the constraints you must not loosen.
3. `architecture/architecture.md` — the prototype and target diagrams, the component table, and the happy-path and blocked-path data flows. The blocked path is the kit's reason to exist.
4. `build-spec/acceptance-tests.md` — T4 (missing SI/HI screening blocks sign-off) and T5 (credential scope) are the tests to write first.
5. `build-spec/deployment-spec.md` — resources, configuration table, checklists.

## Module layout the spec calls for

```
healthcare_agent/
  models.py              # dataclasses: Utterance, Transcript, PatientContext, ClinicalNote,
                         #   CodeItem, Coding, QACheck, QAReport, AuditEvent, Session; to_jsonable()
  agent_runner.py        # AgentRunner ABC; SimulatedAgentRunner; BedrockAgentRunner
  orchestrator.py        # Orchestrator.run_pipeline (U1→U5, AuditEvent per stage); write_back (QA gate)
  ehr_store.py           # EHRStore: get_patient_context, file_note, attach_superbill, write_log
  seed_data.py           # synthetic patients + transcripts (CBT 53 min; telehealth med-mgmt 25 min
                         #   with sessions_remaining=2; crisis 45 min)
  api.py                 # FastAPI routes; MAX_TRANSCRIPT_CHARS = 20000 → 413; 409/422 on signoff
  agents/
    context_agent.py     # U1: load context; select_template; auth_alert when sessions_remaining < 3
    transcription_agent.py  # U2: parse CLINICIAN:/PATIENT: free text → diarized utterances
    note_agent.py        # U3: TEMPLATE_SECTIONS; evidence_map; _risk_section (empty if no SI/HI screening)
    coding_agent.py      # U4: cpt_for_duration; PRESCRIBER_CREDENTIALS; prescriber-only set; add-ons; modifier 95
    qa_agent.py          # U5: seven checks; MH_TEMPLATES; CPT_TIME_RULES; clinical_vocab allowlist
web/index.html           # clinician review UI (vanilla HTML/JS, no build step)
tests/                   # test_pipeline.py, test_coding.py, test_properties.py (Hypothesis)
run.py                   # uvicorn on 127.0.0.1:8080; --demo for a headless run
```

## Implementing for your organization

1. **Templates.** Define `TEMPLATE_SECTIONS` for CBT Session, Med Management, Crisis Assessment, Initial Psychiatric Eval, DBT Individual, Group Therapy, SOAP, DAP — then adapt to your note types. Add required sections your compliance officer names. Every mental-health template includes `Risk Assessment`.
2. **Coding rules.** Implement `cpt_for_duration` on CPT standard bands (≤37 min → 90832, 38–52 → 90834, ≥53 → 90837), crisis → 90839, medication management → 99214, add-ons 90785 and 90863, modifier 95 for telehealth. Set `PRESCRIBER_CREDENTIALS = {MD, DO, NP, PA, PMHNP}` and the prescriber-only set `{99213, 99214, 99215, 90863}`; extend both to your credential types and payer contracts.
3. **QA checks.** Implement the seven checks: `sections`, `risk_assessment`, `time_cpt`, `diagnosis`, `hallucination`, `credential`, `measurement`. The first, second, third, fifth, and sixth are FAIL-class; `diagnosis` and `measurement` are WARN by default. Seed `clinical_vocab` with accepted clinical shorthand so the hallucination check does not false-positive.
4. **Simulated runner first.** Make the whole pipeline pass its tests with deterministic handlers and synthetic data. This is your regression suite for everything that follows.
5. **Bedrock runner.** Implement `BedrockAgentRunner(AgentRunner)` using Strands `Agent` + `BedrockModel(model_id="anthropic.claude-sonnet-4-5-20250929-v1:0")`. Each handler's rules become that agent's system prompt. Keep the `AgentResult{output, confidence, rationale, latency_ms, backend, extra}` contract. The orchestrator, API, and UI must not change.
6. **Transcription.** Hybrid (recommended): Amazon Connect Health ambient documentation produces the diarized transcript, base clinical note, evidence map, and after-visit summary in S3; U2 reads those and U3 enhances rather than drafts. All-AgentCore fallback: Transcribe Medical or Nova Sonic for U2, Claude for U3.
7. **EHR adapter.** Replace the in-memory `EHRStore` with your EHR API client or HealthLake FHIR R4. Preserve `get_patient_context`, `file_note`, `attach_superbill`, and the `write_log`.
8. **Deploy.** Run the pre-deployment checklist in `build-spec/deployment-spec.md`, then `build-spec/acceptance-tests.md`.

## What you're NOT building

- Audio capture and ASR — Connect Health or Transcribe Medical supplies this. Do not write a speech pipeline.
- A payer rules engine — the coding rules are a representative behavioral-health subset; payer-specific edits are configuration with tests.
- An autonomous filing path — see Non-negotiables.
- A multi-tenant service — one deployment per organization.

## Non-negotiables

- **QA is blocking, not advisory.** `write_back` must refuse when any check is FAIL. Do not downgrade `risk_assessment`, `time_cpt`, `credential`, `sections`, or `hallucination` to WARN to make a demo pass.
- **No fabricated risk assessments.** If the transcript contains no SI/HI screening, the Risk Assessment section stays empty and QA fails the note. A model prompt that fills it with "patient denies SI/HI" when the clinician never asked is a patient-safety defect.
- **Every note claim maps to evidence.** Keep `evidence_map` (claim → utterance index or Connect Health evidence reference). The clinician UI shows it; your compliance officer relies on it.
- **Credential scope is enforced in code.** Prescriber-only codes under a non-prescriber credential set `credential_scope_ok=False` and fail QA. Do not leave this to the model.
- **Clinician signs before anything reaches the EHR.** `POST /signoff` is the only path to `file_note`/`attach_superbill`. No background auto-filing.
- **Determinism where the rules are deterministic.** Coding bands and credential checks stay rule-based after the Bedrock swap. Use the model for drafting and summarizing, not for deciding which CPT code the duration supports.
- **Synthetic data stays synthetic.** Never commit real transcripts or patient records. PHI lives only in your account under your BAA.

## Defaults

- **Model:** `anthropic.claude-sonnet-4-5-20250929-v1:0` for note drafting, coding rationale, and QA narrative. A Haiku-class model for the QA tier is a cost decision. Enable prompt caching on the template + rules prefix.
- **Region:** `us-west-2` (Connect Health availability). Confirm Connect Health and Bedrock model access in your chosen region.
- **Transcription:** Amazon Connect Health ambient documentation, Psychiatry specialty, dual-channel audio. Patient consent captured before the session starts.
- **Context store:** AgentCore Memory for treatment goals, last-session summary, homework, PHQ-9/GAD-7 trends. HealthLake (FHIR R4) if you want a standards-based clinical store.
- **Outputs and audit:** S3 (Connect Health writes transcript, note, evidence map, after-visit summary there) + CloudWatch. Retain audit per your policy — 7 years is the usual healthcare default.
- **Ports / local:** `127.0.0.1:8080`, Python 3.12, `pip install -r requirements.txt` (fastapi, uvicorn, pydantic, pytest, hypothesis, httpx). `MAX_TRANSCRIPT_CHARS = 20000`.
- **Naming:** keep the U1–U6 stage names in audit events; the UI and tests depend on them.

## Things to decide before coding

- Which session types and templates do you bill today? (Drives `TEMPLATE_SECTIONS`.)
- What credential types are on staff, and which codes is each allowed to bill under your payer contracts?
- Do you control an EHR write-back API, or is HealthLake the target? Who owns the adapter?
- Hybrid (Connect Health + AgentCore) or all-AgentCore? Is Connect Health available in your region, and do you have a consent workflow?
- Which QA checks must be FAIL vs. WARN for your organization? Measurement-based care (PHQ-9/GAD-7) in particular.
- Audit retention period, and who reviews the audit format (your compliance officer, usually).

## When to stop and escalate

- Someone asks you to auto-file notes without clinician sign-off.
- Someone asks the model to pick the CPT code "based on clinical complexity" rather than documented duration.
- Your templates have no risk-assessment section and that is intended.
- Connect Health does not support your specialty or region.
- The EHR has no write API and the only path is UI automation.
- You find real patient data in any transcript provided for testing.

## Done definition

The build is done when:
- `pytest -q` passes, including the tests you added for your rules.
- `BedrockAgentRunner` runs all five stages end to end on the three synthetic transcripts and produces the same QA verdicts the simulation does (CBT passes; LCSW med-management fails credential; no-SI/HI transcript fails risk).
- A transcript with the SI/HI screening removed is **blocked at sign-off** in the deployed UI (T4 in `acceptance-tests.md`).
- A clinician on your team can run a session end to end — create, run, review, sign — and the note, superbill, and after-visit summary appear in your EHR or HealthLake.
- The audit trail for that session is visible in the UI and persisted in S3/CloudWatch with the agreed retention.
- Your compliance officer has reviewed the QA check list and the audit format and signed `acceptance-tests.md`.
