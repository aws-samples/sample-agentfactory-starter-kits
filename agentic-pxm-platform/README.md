# Agentic PXM Platform

> **Status:** Draft · Spec derived from a working implementation · Build level: Custom IaC

An autonomous **Product Experience Management (PXM)** agent for retail catalogs. An operator ingests a sparse SKU; the agent then runs a four-stage enrichment pass — **enrich attributes → classify to taxonomy → generate brand-consistent copy → validate compliance** against the SKU's target markets (US/EU) — and either **auto-approves** a clean product or routes anything with a **compliance blocker** (restricted substance, prohibited claim) to a **human review queue** before it can publish to a channel. The whole flow is an AWS Step Functions saga with a `waitForTaskToken` human-in-the-loop gate, RAG grounding over OpenSearch Serverless, and pool-based multi-tenancy so multiple brands can share one deployment.

## Why this exists

Product onboarding is the unglamorous bottleneck in retail. Operators hand-key attributes, rewrite marketing copy per channel, and manually check each SKU against the regulations of every market it ships to — and compliance problems are routinely caught *after* a product is already listed. The agent collapses that into one orchestrated pass: it enriches and classifies the SKU, drafts the copy, and cites the specific regulation behind every compliance finding. Crucially it does **not** publish autonomously — a blocker or a publish request escalates to a human, with the cited regulation in hand. Clean, low-risk SKUs flow through without a human touch; the high-impact decisions stay with an operator.

## How to use this kit

This kit is a blueprint: it contains the architecture, the build contract, and acceptance tests — not the agent's source code. No source is included; the agent is built from the spec. Read [`AGENTS.md`](AGENTS.md) + [`build-spec/`](build-spec/) and have a coding agent (Kiro / Claude Code / Cursor / Codex) implement the pattern in your own AWS account, against your own catalog, taxonomy, and regulations.

**What the spec targets:** an implementation that runs end-to-end **locally with no AWS** (a deterministic fake model provider, in-memory data + vector index) for the demo and the full test suite, and **deploys to AWS** via `cdk deploy --all` (six stacks) plus a seed script.

## What this kit gives you

| File | What's in it |
|---|---|
| [`kit.json`](kit.json) | Kit manifest — services, model, outcomes, ideal customer, ROI scaffolding |
| [`architecture/architecture.md`](architecture/architecture.md) | The stack, a component diagram, data flow (happy + HITL paths), audit trail |
| [`business-case/roi-framework.md`](business-case/roi-framework.md) | ROI math template, cost drivers, objection handling, competitive framing |
| [`AGENTS.md`](AGENTS.md) | Build contract for a coding agent re-implementing or customizing the kit |
| [`build-spec/requirements.md`](build-spec/requirements.md) | Functional + non-functional requirements, each mapped to acceptance tests |
| [`build-spec/architecture-decisions.md`](build-spec/architecture-decisions.md) | Why custom-iac, why Step Functions HITL, why pool-based tenancy, why the provider abstraction |
| [`build-spec/deployment-spec.md`](build-spec/deployment-spec.md) | What gets deployed in your account, costs, checklists |
| [`build-spec/acceptance-tests.md`](build-spec/acceptance-tests.md) | Tests the build must pass before sign-off |

## Shared responsibility

This is an accelerator and a working reference, not a managed service. You own the deployed agent, the enrichment and compliance rules, the master data and RAG corpus, the channel adapters, and the AWS infrastructure in your account. The agent auto-approves low-risk SKUs, but channel publishing and any compliance blocker stay behind a human review gate — you own the publish decision. You and your engineering team adapt the kit to your catalog; deploy scripts are provided as-is.
