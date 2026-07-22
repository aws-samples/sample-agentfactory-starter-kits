# TriageAI — Patient Intake & Clinical Triage

> **Status:** Draft · Spec-only kit — a blueprint of a working implementation · Build level: Custom IaC

A patient-intake and clinical-triage agent. A patient — or a triage nurse on the patient's behalf — describes symptoms in a structured form. A single Bedrock (Claude 3.5 Haiku) call classifies **urgency** (`low` / `medium` / `high` / `critical`), recommends a **department** (ER / Primary Care / Mental Health / Specialist Referral), surfaces **red-flag warnings** and **clarifying follow-up questions**, and routes the case into a **clinical staff queue** ordered by urgency. When the model is unavailable, a deterministic **safe-default fallback** applies — the case still routes (Primary Care, medium urgency) and is tagged so staff know to review it manually.

## Why this exists

Patient triage at the front door — an ED, urgent-care line, telehealth intake — is usually a nurse reading a symptom description and deciding, case by case, how urgent it is and where it should go. That's a bottleneck, it varies nurse to nurse, and under load it delays the one thing that matters most: surfacing the genuinely critical patient fast. TriageAI's thesis is that a structured intake form plus a constrained LLM call can produce a consistent, **explainable** first-pass urgency-and-routing recommendation in seconds — with the reasoning, red flags, and follow-up questions a clinician needs to confirm or override it. It is a fast, transparent second opinion that pushes critical cases to the top of the queue, not a replacement for the clinician's judgement.

## How to use this kit

This kit is a blueprint, not a codebase: it contains the architecture, the build contract, and acceptance tests — but not the application's source code. Read [`AGENTS.md`](AGENTS.md) + [`build-spec/`](build-spec/) and have a coding agent (Kiro / Claude Code / Cursor / Codex) implement the pattern in your own AWS account, against your own intake schema and clinical taxonomy.

**What the spec targets:** a locally-runnable application (FastAPI backend + React/Vite SPA over TLS) whose only AWS dependency is a Bedrock `InvokeModel` permission. With no Bedrock access, the deterministic fallback still exercises the full intake → queue flow.

## What this kit gives you

| File | What's in it |
|---|---|
| [`kit.json`](kit.json) | Kit manifest — services, model, outcomes, ideal customer, ROI scaffolding |
| [`architecture/architecture.md`](architecture/architecture.md) | The stack, a component diagram, data flow (happy + fallback paths), audit trail |
| [`business-case/roi-framework.md`](business-case/roi-framework.md) | ROI math template, cost drivers, objection handling, competitive framing |
| [`AGENTS.md`](AGENTS.md) | Build contract for a coding agent re-implementing or customizing the kit |
| [`build-spec/`](build-spec/) | Requirements, architecture decisions, deployment spec, acceptance tests |

## Shared responsibility

This is an accelerator and a working reference, not a managed service and not a medical device. You own the deployed application, the triage prompt and taxonomy, the intake data, and the AWS infrastructure in your account. Every triage output is decision-support for a human clinician — you own the clinical decision and are responsible for clinical validation, regulatory posture, and PHI handling in production. The reference is a local, in-memory prototype; you and your engineering team add persistence, authentication hardening, and any EHR integration. Prompts and scripts are provided as-is.

## Vertical applicability

The intake-classify-route pattern generalizes within healthcare and beyond:

- **Hospital ED / urgent care** — the reference use case: symptom intake → urgency + department → nurse queue.
- **Telehealth front door** — classify inbound patient messages to the right care pathway before a clinician picks them up.
- **Payer / nurse-line triage** — route member symptom calls to self-care, appointment, or escalation.
- **Beyond clinical** — any structured-intake-then-route workflow (benefits intake, IT/HR help desks) where a human owns the final decision and explainability matters.
