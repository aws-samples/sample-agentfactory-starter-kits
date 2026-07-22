# Payment Fraud Detector

> **Status: Draft.** This kit is a spec-only blueprint: it contains the kit metadata, the build contract (`AGENTS.md` + `build-spec/`), and the docs pack — but not the agent's source code. The implementation is built from the spec.

A working AI agent that combines a deterministic rules engine with a Bedrock-powered LLM analyst layer to surface fraudulent payment patterns. The reference demo is a pharmacy payment fraud detector, but the same architecture drops into FSI transaction monitoring, AML triage, healthcare claims FWA, or any payment integrity use case with only the rules and data schemas changing.

## Why this exists

Fraud-ops teams running rules-only detection drown in false positives. Pure ML approaches don't pass model risk review. This kit is the hybrid pattern: keep your auditable rules engine as the spine, add a Bedrock-powered analyst layer on top that explains *why* rules fired and what to dig into next. Analysts triage faster, more confidently, with auditable rationale at every step.

## How to use this kit

This kit is a blueprint, not a codebase: it contains the architecture, the build contract, and acceptance tests — but not the agent's source code. Open [`AGENTS.md`](AGENTS.md) + [`build-spec/`](build-spec/) in your coding agent (Kiro / Claude Code / Codex / Cursor) and have it implement the agent in your AWS account against the spec — customizing the rules engine and data schemas for your vertical along the way.

**What the spec targets:** a fully-working stack — master CFN + 5 child stacks, an MCP server (FastAPI on ECS Fargate), a Bedrock Agent with action groups, and a Streamlit analyst UI. The architectural choices (ECS+ALB, Streamlit UI, multi-stack CFN) are the spec's defaults; if you want different ones (custom React UI instead of Streamlit, EKS instead of Fargate, a different container layout), the build contract tells you where deviation is safe.

The kit's `kit.json` describes the agent; the architecture, business case, and build spec are the contract you build against.

## What this kit gives you

| File | What it tells you |
|---|---|
| [`kit.json`](kit.json) | Kit metadata — name, services, model, outcomes |
| [`AGENTS.md`](AGENTS.md) | Build contract for a coding agent customizing or rebuilding the kit |
| [`architecture/architecture.md`](architecture/architecture.md) | Reference architecture diagram + components + data flow |
| [`business-case/roi-framework.md`](business-case/roi-framework.md) | ROI scaffolding you fill in for your deployment |
| [`build-spec/requirements.md`](build-spec/requirements.md) | What the agent must do |
| [`build-spec/architecture-decisions.md`](build-spec/architecture-decisions.md) | Why custom-iac, why ECS+ALB, why Streamlit, why Sonnet |
| [`build-spec/deployment-spec.md`](build-spec/deployment-spec.md) | What gets deployed in your account |
| [`build-spec/acceptance-tests.md`](build-spec/acceptance-tests.md) | Tests the build must pass before it's production-ready |

## What's NOT in this kit folder

- **Source code** — not included; built from the spec
- **CloudFormation templates** — not included; built from the spec
- **Sample data** — not included; you generate synthetic data per the spec
- **Streamlit UI components** — not included; built from the spec

This is by design. The kit folder is the blueprint; the implementation is built from the spec and lives wherever you put it.

## Shared responsibility

This kit is an **accelerator and a blueprint, not a managed service**. You own the deployed agent, the rules engine, the data, the AWS infrastructure, and the analyst workflow. The implementation you build from the spec is yours — you and your engineering team customize the rules + schemas to your payment domain. Partners can offer managed support engagements if needed.

## Vertical applicability

The spec targets data and rules for:

- **Pharmacy payment integrity** (default demo — clinical-trial pharmacy claims)
- **Generic payment fraud** (transaction monitoring patterns)

The architecture extends naturally to:

- **FSI AML / sanctions** — replace pharmacy rules with structuring detection, sanctions screening, beneficial-ownership lookups
- **Healthcare claims FWA** — replace with upcoding patterns, unbundling, billing anomalies
- **Insurance fraud** — replace with claim staging, ghost employees, duplicate claims
- **Generic payment integrity** — chargeback abuse, merchant fraud, card-not-present patterns
