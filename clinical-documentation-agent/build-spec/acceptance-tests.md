# Acceptance Tests — Clinical Documentation Agent

> Audience: your engineering lead at sign-off, with the compliance officer present for T4–T7 and T14. Tests T1–T11 can be run against the prototype (`python run.py`, `pytest -q`) and again against the deployed `BedrockAgentRunner`; T12–T16 apply to the deployed system. Automate T1–T3, T5–T7, and T9–T11 in `tests/`.

## Functional

### T1 — Happy path: CBT session produces a signable note
**Setup:** Synthetic catalog loaded (`PT-1001`, transcript `cbt-depression`, 53 min, in-person, credential LCSW).
**Action:** `POST /api/sessions` with `transcript_id=cbt-depression`, then `POST /api/sessions/{sid}/run`, then `GET /api/sessions/{sid}`.
**Expected:** Status `READY_FOR_REVIEW`; template `CBT Session`; all required sections populated; `evidence_map` non-empty; QA `overall=PASS` with no blocking failures; CPT `90837`; ICD-10 includes `F33.1`.
**Maps to:** FR1, FR3, FR4, FR5, FR7, NFR3

### T2 — Pre-session context and template selection
**Setup:** Catalog loaded.
**Action:** Run sessions for each of: (`cbt`, in-person), (`med_management`, telehealth), (`crisis`, in-person), (`intake`, in-person), (`dbt`, in-person), (`group`, in-person).
**Expected:** `PatientContext` carries treatment goals, previous-session summary, homework, PHQ-9/GAD-7 trends, diagnoses, `sessions_remaining`. Templates selected are `CBT Session`, `Med Management`, `Crisis Assessment`, `Initial Psychiatric Eval`, `DBT Individual`, `Group Therapy` respectively (matches `test_template_selection`).
**Maps to:** FR2, FR3

### T3 — Authorization alert when sessions are nearly exhausted
**Setup:** `PT-1002` with `sessions_remaining=2` (synthetic `med-management` transcript).
**Action:** Run the session; inspect context and U1 audit event.
**Expected:** `auth_alert=True`; U1 rationale contains "AUTH ALERT: fewer than 3 sessions remaining"; the UI surfaces the alert before the note.
**Maps to:** FR2, FR10

### T4 — Missing SI/HI screening blocks sign-off (the patient-safety test)
**Setup:** Copy the `cbt-depression` transcript and delete every utterance in which the clinician asks about suicidal or homicidal ideation. Compliance officer present.
**Action:** Create a session with `transcript_text` = the edited transcript; run; attempt `POST /signoff`.
**Expected:** Risk Assessment section is **empty** (no fabricated "denies SI/HI"); QA `risk_assessment=FAIL` with detail "No SI/HI screening found in transcript — note cannot be signed."; `overall=FAIL`; `POST /signoff` returns **422**; `EHRStore.charts` unchanged. Matches `test_missing_risk_screening_fails_qa` and `test_signoff_blocked_when_qa_fails`.
**Maps to:** FR5, FR7, FR8, FR9

### T5 — Credential scope blocks a non-prescriber billing E&M
**Setup:** `med-management` transcript, `provider_credential=LCSW`.
**Action:** Run the session.
**Expected:** Coding selects `99214`; `credential_scope_ok=False`; `credential_note` names the credential and the code; QA `credential=FAIL`; `overall=FAIL`; sign-off blocked. Matches `test_credential_scope_blocks_lcsw_med_management`.
**Maps to:** FR6, FR7, FR8

### T6 — CPT matches documented duration
**Setup:** `cbt` session type.
**Action:** Run with `duration_min` = 16, 30, 37, 38, 45, 52, 53, 60, 90.
**Expected:** CPT = 90832 for ≤37, 90834 for 38–52, 90837 for ≥53; QA `time_cpt=PASS` in every case. Then force a mismatch (e.g., inject `90837` with `duration_min=40`) and confirm `time_cpt=FAIL`. Matches `test_psychotherapy_cpt_thresholds`, `test_cpt_code_in_known_set`, `test_coder_and_qa_agree_on_time`.
**Maps to:** FR6, FR7

### T7 — Telehealth modifier and crisis code
**Setup:** `med-management` transcript (telehealth, 25 min); `crisis` transcript (45 min).
**Action:** Run both.
**Expected:** Med-management coding includes modifier `95`; crisis coding CPT = `90839`. Matches `test_med_management_telehealth_modifier`, `test_crisis_uses_crisis_code`.
**Maps to:** FR6

### T8 — Hallucination check flags unsupported content
**Setup:** Deployed `BedrockAgentRunner` (or a hand-edited note in the prototype).
**Action:** Inject a sentence into a note section containing clinical terms that appear nowhere in the transcript, context, or `clinical_vocab` (e.g., a medication the patient is not on).
**Expected:** QA `hallucination=FAIL` with detail listing the unsupported terms; `overall=FAIL`; sign-off blocked. Then add the terms to `clinical_vocab` and confirm the check passes — demonstrating the allowlist is the tuning surface.
**Maps to:** FR5, FR7

## Non-functional

### T9 — Determinism and backend-swap equivalence
**Setup:** Same transcript, same parameters.
**Action:** Run twice on `SimulatedAgentRunner`; then run once on `BedrockAgentRunner`.
**Expected:** Simulated runs produce identical note, coding, and QA (matches `test_determinism_same_input_same_output`). The Bedrock run produces the **same QA verdicts and the same CPT/ICD codes** for all three synthetic transcripts; prose may differ. Orchestrator, API, UI, and tests unchanged between runners.
**Maps to:** NFR2, NFR5, FR6

### T10 — Sign-off files note, superbill, AVS; sets SIGNED
**Setup:** T1 session in `READY_FOR_REVIEW` with QA PASS.
**Action:** `POST /signoff` with clinician name; `GET /api/sessions/{sid}`.
**Expected:** HTTP 200; status `SIGNED`; `EHRStore.charts[patient]` has exactly one new entry; `superbills` has one entry with ICD-10, CPT, add-ons, modifiers; after-visit summary present; `write_log` appended. Matches `test_writeback_files_note_after_signoff`. In the target, the note appears in HealthLake / the EHR.
**Maps to:** FR8, FR9, NFR8

### T11 — Out-of-order sign-off is rejected
**Setup:** A session created but not yet run.
**Action:** `POST /signoff`.
**Expected:** HTTP **409**; nothing written. Then run the T4 edited transcript and `POST /signoff` → **422**. No path writes to the EHR without `READY_FOR_REVIEW` + QA non-FAIL + explicit sign-off.
**Maps to:** FR8, FR9, NFR7, NFR8

### T12 — Input bounds and latency
**Setup:** A 20,001-character transcript; a normal transcript.
**Action:** `POST /api/sessions` with the oversized transcript; run the normal one with timing.
**Expected:** Oversized → HTTP **413**. Prototype pipeline completes in a few seconds. Deployed pipeline (hybrid): signed-ready note within 2 minutes of Connect Health output landing in S3.
**Maps to:** FR1, NFR4, NFR7

### T13 — No PHI in repo; PHI contained in the account
**Setup:** Source repository; deployed account.
**Action:** Grep the repo for real identifiers; confirm every patient/transcript in `seed_data.py` is marked synthetic. In the deployed account, confirm S3 buckets use SSE-KMS and block public access; confirm audit log entries contain stage summaries and evidence references but not full transcript text; confirm no PHI leaves the account (no third-party endpoints in the EHR adapter other than your EHR).
**Expected:** No real PHI in the repo; encryption at rest and in transit verified; audit logs PHI-minimal.
**Maps to:** NFR1, NFR7

### T14 — Audit trail is complete and replayable
**Setup:** T10 session (signed) and T4 session (blocked). Compliance officer present.
**Action:** `GET /api/sessions/{sid}/audit` for both; inspect S3/CloudWatch mirrors in the deployed system.
**Expected:** Signed session: events for U1, U2, U3, U4, U5, SIGNOFF, WRITE_BACK in order with timestamps and actors. Blocked session: U1–U5 present, QA event records the FAIL detail, no SIGNOFF/WRITE_BACK. Compliance officer can pick a sentence from the signed note and reach its supporting utterance via `evidence_map`.
**Maps to:** FR10, NFR8

## Operational

### T15 — Compliance review of QA checks and audit format
**Setup:** Final `qa_agent.py` check list (with any organization-specific severity changes) and a sample audit export.
**Action:** Walk the compliance officer through each check's FAIL/WARN status and the audit record format and retention.
**Expected:** Compliance officer confirms in writing that the check list meets the organization's documentation standard and the audit format and retention meet its policy.
**Maps to:** FR7, NFR1

### T16 — Operability and cost review
**Setup:** Deployed system after the first consented session and the pilot cohort's first week.
**Action:** Review the CloudWatch dashboard (sessions, QA FAIL by check, sign-off latency, tokens/session), test the QA FAIL-rate alarm, change one coding rule in the repo and confirm the test suite catches a regression, and compare Bedrock + Connect Health spend per session to the ROI model.
**Expected:** Dashboard populated; alarm fires on a synthetic spike; rule change gated by tests; per-session cost recorded and within the ROI model's range or the model is updated.
**Maps to:** NFR5, NFR6

## Sign-off

**Engineering lead:** _______________________
**Compliance officer (T4–T7, T14, T15):** _______________________
**Date:** _______________________

**All tests pass:** ☐ Yes ☐ No

If "No," document failing tests and remediation plan before re-running.

Once all tests pass, sign off the deployment for production cutover.
