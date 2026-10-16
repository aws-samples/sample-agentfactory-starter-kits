# Clinical Documentation Agent

> **Status: Draft.** This kit is a spec-only blueprint: it contains the kit metadata, the build contract (`AGENTS.md` + `build-spec/`), and the docs pack — but not the agent's source code. The implementation is built from the spec.

A five-agent pipeline for **behavioral health**: it takes a therapy or psychiatry session transcript and produces a template-structured clinical note, ICD-10 and time-based CPT codes with confidence scores, and a blocking QA report — then holds everything until a clinician reviews and signs. Only after sign-off are the note, superbill, treatment-plan progress, and after-visit summary written to the EHR, with every step in a timestamped audit trail.

The spec describes two layers: a deterministic, offline-runnable prototype (FastAPI + a vanilla-JS clinician UI, synthetic data, no AWS calls) that proves the workflow and rules, and the production target — **Amazon Connect Health ambient documentation** for transcription and base-note generation plus a **Bedrock AgentCore** layer running Claude Sonnet 4.5 for the behavioral-health-specific context, coding, and QA stages.

## Why this exists

Behavioral-health clinicians spend 15–20 minutes per session on documentation, much of it after hours. Notes miss required elements — most consequentially a documented suicidal/homicidal-ideation (SI/HI) risk screening — and the gap is found by a payer audit, not before sign-off. CPT time codes get denied when the documented duration does not support the code billed, and non-prescribers occasionally bill E&M or pharmacologic-management codes they are not credentialed for.

This kit encodes those failure modes as **blocking checks**, not advisory warnings. A note with no SI/HI screening in the transcript cannot be signed. A 90837 on a 40-minute session cannot be signed. An LCSW cannot sign a note that bills 99214. The clinician remains the decision-maker; the agent makes sure the decision is made on a complete, grounded, correctly coded draft.

## How to use this kit

This kit is a blueprint, not a codebase: it contains the architecture, the build contract, and acceptance tests — but not the agent's source code. Open [`AGENTS.md`](AGENTS.md) + [`build-spec/`](build-spec/) in your coding agent (Kiro / Claude Code / Codex / Cursor) and have it implement the pipeline in your AWS account against the spec — adapting the note templates, coding rules, and QA checks to your payer mix and clinical workflows along the way.

**What the spec targets:** a staged, gated pipeline — context → transcription → note → coding → QA — where each stage is a handler behind an `AgentRunner` interface, so you can first build it as deterministic Python (runnable offline with synthetic data, ~30 tests including property-based tests on the CPT time bands) and then swap in a Bedrock-backed runner without changing the orchestrator, API, or UI. The production shape is hybrid: Amazon Connect Health produces the diarized transcript, base note, evidence map, and after-visit summary into S3; AgentCore agents add pre-session context, BH note enhancement, time-banded CPT coding with credential scope, and the blocking QA gate. If Connect Health is not available in your region, the build contract describes the all-AgentCore fallback.

The kit's `kit.json` describes the agent; the architecture, business case, and build spec are the contract you build against.

## What this kit gives you

| File | What it tells you |
|---|---|
| [`kit.json`](kit.json) | Kit metadata — name, services, model, outcomes, what you customize vs. what the spec provides |
| [`AGENTS.md`](AGENTS.md) | Build contract for a coding agent implementing or adapting the kit — non-negotiables, defaults, done definition |
| [`architecture/architecture.md`](architecture/architecture.md) | Prototype vs. target architecture, component table, happy-path and blocked-path data flows, audit trail |
| [`business-case/roi-framework.md`](business-case/roi-framework.md) | Documentation-time ROI math, Bedrock cost model, objections, positioning vs. ambient-scribe vendors |
| [`build-spec/requirements.md`](build-spec/requirements.md) | 10 functional + 8 non-functional requirements, mapped to acceptance tests |
| [`build-spec/architecture-decisions.md`](build-spec/architecture-decisions.md) | 11 decisions with rationale: blocking QA, evidence map, deterministic coding, credential scope, hybrid Connect Health + AgentCore |
| [`build-spec/deployment-spec.md`](build-spec/deployment-spec.md) | Resources, configuration, cost drivers, pre/post-deployment checklists |
| [`build-spec/acceptance-tests.md`](build-spec/acceptance-tests.md) | 16 verifiable tests, including the blocked-risk-screening and credential-scope cases |

## What's NOT in this kit folder

- **Source code** — not included; built from the spec
- **Live Amazon Connect Health or Bedrock integration** — described in the spec; you build the `BedrockAgentRunner`
- **Audio capture** — the pipeline starts at the transcript; Connect Health (or your ASR) supplies audio-to-text
- **An EHR integration or payer rules engine** — the EHR adapter is yours to build; the coding rules are a representative behavioral-health subset you extend
- **PHI** — the spec calls for synthetic patients and transcripts only

This is by design. The kit folder is the blueprint; the implementation is built from the spec and lives wherever you put it.

## Shared responsibility

This kit is an accelerator and a working reference, not a managed service. You own the deployed pipeline, the note templates, the coding and QA rules, the EHR integration, the AWS infrastructure, and the clinical and billing decisions the agent supports. You are responsible for patient consent for session recording, your BAA with AWS, and compliance review before PHI enters the system. Everything is provided as-is.

## Vertical applicability

This kit is **behavioral-health specific** — the templates (CBT, Med Management, Crisis, DAP), the SI/HI risk check, and the time-banded psychotherapy CPT logic are not general-medicine artifacts. Within BH it applies to:

- **Outpatient therapy and psychiatry groups** — the primary target; mixed prescriber/non-prescriber credentials make the credential-scope check immediately valuable.
- **BH telehealth platforms** — high session volume, modifier 95 on everything, and a strong need to prove documented duration supports the CPT code.
- **IOP / PHP programs** — group-therapy and DBT templates are in the spec; coding rules would need per-diem and H-code additions.
- **Crisis and mobile-crisis services** — the Crisis Assessment template and 90839 path are specified; the risk-assessment check is the whole point.
