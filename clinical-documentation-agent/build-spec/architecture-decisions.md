# Architecture Decisions — Clinical Documentation Agent

> Audience: a coding agent that might be tempted to deviate. Each decision records why it was made so you can tell a deliberate constraint from an accident. AD1–AD6 govern the prototype build; AD7–AD11 govern the production target.

## AD1: Build level = `managed-harness` (with Connect Health as the managed transcription layer)

**Decision:** Bedrock AgentCore Managed Harness for the BH agents, with Amazon Connect Health ambient documentation as the managed transcription and base-note service. Not custom IaC.

**Why.** The kit's value is in the BH-specific rules and the QA gate, not in infrastructure. AgentCore hosts the four model-backed stages (context, note enhancement, coding, QA) and provides Memory for per-patient context; Connect Health is a managed, HIPAA-eligible service for the parts that are hard to build (dual-channel ASR, diarization, evidence mapping). There is no ECS, ALB, or VPC to author — the only component you build from scratch is the EHR adapter.

**Alternatives considered.** `custom-iac` with Transcribe Medical + Lambda + Step Functions: more control, far more surface area, and you re-implement what Connect Health already does. Rejected unless Connect Health is unavailable in your region.

**What this means for the build:** no CloudFormation stacks for compute; AgentCore agent definitions, a Connect Health subscription, S3 buckets, and IAM.

## AD2: `AgentRunner` abstraction between orchestrator and inference backend

**Decision:** Every stage is invoked through `AgentRunner.run(agent_name, payload) → AgentResult`. The shipped `SimulatedAgentRunner` is deterministic Python; `BedrockAgentRunner` is the production implementation.

**Why.** You need a first build that runs offline with no PHI and no AWS credentials, and a production path that does not rewrite the orchestrator, API, UI, or tests. One interface satisfies both (NFR2 reproducibility and NFR5 extensibility). It also makes the rules testable without a model in the loop — the test suite runs in seconds.

**Alternatives considered.** Build straight on Bedrock and mock it in tests. Rejected: mocking a model's prose is brittle, and the demo would need credentials.

**What this means for the build:** implement `BedrockAgentRunner` behind the same interface; keep `AgentResult{output, confidence, rationale, latency_ms, backend, extra}`. Do not call Bedrock from the orchestrator or agents directly.

**When to deviate:** never for the interface. The runner's internals (Strands vs. raw Converse API) are yours.

## AD3: QA is blocking, not advisory

**Decision:** `write_back` raises when `QAReport.overall == "FAIL"`. Checks for required sections, risk assessment, CPT-vs-duration, hallucination, and credential scope are FAIL-class; diagnosis-present and measurement are WARN-class by default.

**Why.** Advisory warnings get clicked through at 6 pm; a missing SI/HI screening that reaches the chart is a patient-safety and liability event, and a 90837 on a 40-minute session is a denial. The kit's compliance value depends on the gate being hard.

**Alternatives considered.** Advisory with a "sign anyway" override. Rejected: it converts a control into a suggestion, and the audit trail would have to record every override.

**What this means for the build:** `POST /signoff` returns 422 on FAIL. No override flag. If you want a check downgraded, it is a rule change with your compliance officer's recorded agreement — not a runtime bypass.

## AD4: Every note claim carries an evidence reference

**Decision:** The note agent emits `evidence_map: {claim → utterance index}` (or Connect Health evidence reference in the hybrid design), and the UI renders it next to the note.

**Why.** Clinicians will not sign what they cannot verify quickly; compliance reviewers need to trace a sentence to its source months later. The evidence map is also the input to the hallucination check — a claim with no supporting utterance is a finding, not a style issue.

**Alternatives considered.** Free-text note with a confidence score. Rejected: a score does not tell the clinician *which* sentence to doubt.

**What this means for the build:** when porting U3 to a model prompt, require structured output with per-section evidence indices. Connect Health's own evidence-mapping output can be consumed directly in the hybrid design.

## AD5: Coding is rule-based on documented duration and session type

**Decision:** `cpt_for_duration` picks 90832/90834/90837 from `duration_min`; crisis → 90839; med management → 99214. The model writes the rationale; it does not choose the code.

**Why.** Psychotherapy CPT is defined by time. Model-inferred "complexity" is how practices over-code, and an over-coding pattern is an audit finding with clawbacks. Deterministic selection is also what makes the QA `time_cpt` check meaningful — coder and QA agree by construction (verified by the Hypothesis property tests).

**Alternatives considered.** Let the model propose a code with confidence and have QA check it. Rejected: adds a failure mode with no upside; the duration is already known.

**What this means for the build:** keep `cpt_for_duration` and its tests as deterministic post-processing in `BedrockAgentRunner`'s coding stage. Payer-specific bands are a configuration change with tests, not a prompt change.

## AD6: Credential scope is enforced in code and fails QA

**Decision:** Prescriber-only codes (99213/99214/99215, 90863) billed under a credential not in {MD, DO, NP, PA, PMHNP} set `credential_scope_ok=False`, and the QA `credential` check FAILs.

**Why.** This is a licensure and billing-compliance rule with no clinical judgment component. Encoding it in code makes it testable (`test_credential_scope_blocks_lcsw_med_management`) and auditable. Leaving it to a prompt makes it probabilistic.

**Alternatives considered.** Warn only, since supervision/incident-to arrangements exist. Rejected as a default: those arrangements change who signs or how the claim is submitted — an organization-specific rule to add, not a reason to weaken the default.

**What this means for the build:** `PRESCRIBER_CREDENTIALS` and the prescriber-only set are configuration; extend them for your organization with tests.

## AD7: Hybrid Connect Health + AgentCore over all-custom or all-managed

**Decision:** Amazon Connect Health ambient documentation produces the transcript, base note, evidence map, and after-visit summary; a Bedrock AgentCore layer adds pre-session context, BH note enhancement, coding with credential scope, and the QA gate.

**Why.** The reference design evaluated Option A (Connect Health alone), Option B (fully custom AgentCore + Nova Sonic + Claude), and Option C (hybrid), and recommended C: Connect Health gives time-to-market and a HIPAA-eligible managed ASR/diarization stack with Psychiatry specialty support; the custom layer is where BH differentiation lives. Option A lacks the coding, credential, and blocking-QA logic. Option B rebuilds a transcription pipeline for no gain.

**Alternatives considered.** As above. Also: keep an incumbent third-party scribe and run only U3–U5 on its transcript — a valid variant when you already have one.

**What this means for the build:** U2 reads Connect Health outputs from S3 rather than running ASR. U3 enhances the base note rather than drafting from scratch. If Connect Health is unavailable, fall back to Option B with Transcribe Medical.

## AD8: Model = Claude Sonnet 4.5 on Bedrock, Haiku-class for the QA tier, prompt caching on

**Decision:** `anthropic.claude-sonnet-4-5-20250929-v1:0` for note enhancement, coding rationale, and QA narrative; optional Haiku-class model for the QA stage; prompt caching on the template + rules prefix.

**Why.** The reference design names Claude Sonnet 4.5 for clinical reasoning quality and models a ~73% cost reduction from caching (60–70%), tiering (40–50%), and Memory reuse (30%). Those are projections, but the levers are real and cheap to enable. Region default `us-west-2` follows Connect Health availability.

**Alternatives considered.** Claude Opus for everything — higher cost for no measured quality gain on structured BH notes. Nova models — not evaluated for this task.

**What this means for the build:** configure the model ID and region as deployment parameters; structure prompts with the static template/rules first so caching applies.

## AD9: Direct EHR API or HealthLake; no HL7/FHIR interface engine

**Decision:** `EHRStore` is replaced by a direct client to your EHR write API or to a HealthLake FHIR R4 datastore. No Mirth/Rhapsody-style interface engine is part of the kit.

**Why.** This kit assumes you control your EHR and can expose a write-back API, so an interface engine adds cost and latency with no benefit. HealthLake is the standards-based alternative when you want FHIR without building the adapter from scratch.

**Alternatives considered.** HL7 v2 ORU messages via an interface engine. Deferred: only needed if your EHR offers nothing else, in which case it is engineering work outside the kit.

**What this means for the build:** preserve the `EHRStore` method contract (`get_patient_context`, `file_note`, `attach_superbill`, `write_log`); implement it against your API.

## AD10: Clinician sign-off is the only path to write-back

**Decision:** `POST /api/sessions/{sid}/signoff` is the sole caller of `write_back`. There is no scheduled, background, or auto-approve path.

**Why.** Human-in-the-loop is a design requirement (source US-C4, FR-8), not a safety afterthought. The clinician is the licensed author of record. The pipeline's job is to make the review fast and well-informed, not to remove it.

**Alternatives considered.** Auto-file on QA PASS with a review queue. Rejected: moves the signature after filing, which most state boards and payers treat as the clinician attesting to a note they had not yet read.

**What this means for the build:** do not add an auto-file flag, even for "low-risk" templates.

## AD11: Vanilla HTML/JS clinician UI with zero build step

**Decision:** `web/index.html` is a single static page served by FastAPI, calling the `/api/sessions` routes.

**Why.** Maximum reproducibility for the first build — no Node toolchain, no bundler, one `python run.py`. For production the UI is a reference, not a deliverable: most organizations embed the review flow in their EHR.

**Alternatives considered.** React/Streamlit. Fine if you want a standalone app; not worth the build dependency in the kit.

**What this means for the build:** treat the API contract as the stable surface. Replace or embed the UI freely; do not change the routes or the `to_jsonable()` payload shapes.
