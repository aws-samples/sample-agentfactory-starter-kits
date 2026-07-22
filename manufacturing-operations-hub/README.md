# Manufacturing Operations Hub — Starter Kit

> **Status: Draft — Path A (imported).** The reference implementation is a public AWS sample at [`github.com/aws-samples/industrial-data-store-simulation-chatbot`](https://github.com/aws-samples/industrial-data-store-simulation-chatbot). This kit folder holds the catalog metadata, the build contract (`AGENTS.md` + `build-spec/`), and the docs pack — not a copy of the source.

> **Vertical:** Manufacturing & Industrial · **Sub-segment:** discrete manufacturing, plant operations
> **Build Level:** Managed Harness (Strands Agents SDK + Streamlit)
> **Deploy Time:** 3–5 days
> **Services:** Bedrock · Bedrock AgentCore · SageMaker · CloudWatch
> **Model:** Anthropic Claude Haiku 4.5 (via Amazon Bedrock cross-region inference)

## What this is

A natural-language analytics agent for the shop floor. It lets manufacturing teams ask plain-English questions about your MES (Manufacturing Execution System) data — *"which work centers are behind schedule?"*, *"what quality issues correlate with equipment downtime?"*, *"which materials are below reorder level?"* — and get back direct answers, the right chart, and follow-up suggestions. It ships two surfaces:

- **MES Insight Chat** — a Strands Agents SDK text-to-SQL agent that learns the database schema, writes SQL from a natural-language question, runs it read-only, and returns results with an auto-selected visualization.
- **Daily Production Meeting** — a dashboard that pre-computes the KPIs a lean meeting needs (completion rates, OEE, defects, inventory alerts) and uses an orchestrator + four specialized sub-agents (production, quality, equipment, inventory) to generate a daily briefing.

It's demoed on a synthetic e-bike-factory database, but the value is the pattern, not the demo data: repoint the data layer at your MES/historian and re-tune the prompt.

## Why this exists

Two recurring manufacturing pains:

1. **The BI bottleneck.** Production, quality, and maintenance staff can't query MES data themselves. Every "why" question becomes a ticket to a small data team, and the answer comes back days later — long after the shift it was about.
2. **Daily-meeting slide prep.** Lean/standup meetings start with someone spending 30–60 minutes every morning assembling the same KPIs into slides. The meeting is half-over before anyone discusses an actual problem.

This kit collapses both. Non-technical staff get answers in seconds, and the daily meeting starts with the numbers already on the screen — so the time goes to actions and problem-solving, not data assembly.

## Two ways to use this kit

You'll either **clone the reference repo** or **build your own from the spec**. Both are valid.

### Option 1 — Clone the working agent

The reference at [`github.com/aws-samples/industrial-data-store-simulation-chatbot`](https://github.com/aws-samples/industrial-data-store-simulation-chatbot) is a fully-working app: Strands SDK agents, a Streamlit UI combining both surfaces, a DB-agnostic SQLAlchemy data layer, a synthetic-data generator, and an educational text-to-SQL notebook. Clone it, repoint the data layer at your database, re-tune the system prompt for your schema and terminology, and redeploy.

**When this is the right path:** you want something working in your account in days, are comfortable with Streamlit + a Strands agent invoking Bedrock, and has a queryable MES/operational store to point at.

### Option 2 — Build your own from the spec

The kit's [`AGENTS.md`](AGENTS.md) + [`build-spec/`](build-spec/) are the contract. Open them in your coding agent (Kiro / Claude Code / Codex / Cursor) and have it implement the agent in your account against the spec — useful if you want a different UI, a different host (e.g., hosting the Strands agent on Bedrock AgentCore Runtime instead of running Streamlit), or wants to understand every line that ships.

Either way, `kit.json` describes the agent; the architecture, business case, and build spec apply to both paths.

## What this kit gives you

| File | What it tells you |
|---|---|
| [`kit.json`](kit.json) | Kit manifest — services, model, outcomes, ideal customer, ROI scaffolding |
| [`AGENTS.md`](AGENTS.md) | Build contract for a coding agent re-deploying or customizing the kit |
| [`architecture/architecture.md`](architecture/architecture.md) | Reference architecture diagram + components + data flow |
| [`business-case/roi-framework.md`](business-case/roi-framework.md) | ROI scaffolding you fill in for your deployment |
| [`build-spec/requirements.md`](build-spec/requirements.md) | What the agent must do (functional + non-functional) |
| [`build-spec/architecture-decisions.md`](build-spec/architecture-decisions.md) | Why managed-harness, why text-to-SQL, why read-only, why Haiku |
| [`build-spec/deployment-spec.md`](build-spec/deployment-spec.md) | What gets deployed in your account |
| [`build-spec/acceptance-tests.md`](build-spec/acceptance-tests.md) | Tests the build must pass before being marked `published` |

## What's NOT in this kit folder

- **Source code** — lives at the public GitHub repo above (MIT-licensed AWS sample)
- **The synthetic MES database / generator** — same place
- **Streamlit UI + dashboards** — same place

This is by design. The kit folder documents the agent; the source lives at the public AWS sample repo, [`github.com/aws-samples/industrial-data-store-simulation-chatbot`](https://github.com/aws-samples/industrial-data-store-simulation-chatbot).

## Shared responsibility

This kit is an **accelerator and a working reference, not a managed service**. You own the deployed agent, the connection to your MES/operational database, the system prompts, and the AWS account. The kit is **read-only by design** — the agent issues SELECT queries only and never writes to or controls the MES or shop floor. Scripts are provided as-is; partners can offer managed support engagements if needed.

## Vertical applicability

The reference is built for **discrete manufacturing** (e-bike assembly) and covers four MES domains out of the box:

- **Production** — work orders, completion rates, throughput, bottlenecks, shift performance
- **Quality** — defect rates, yield, first-pass quality, root-cause patterns
- **Equipment** — OEE, machine status, downtime, maintenance scheduling
- **Inventory** — stock levels, reorder alerts, material consumption, supplier performance

The same schema-first text-to-SQL pattern extends naturally to adjacent operational data stores:

- **Process / continuous manufacturing** — point at the historian/batch records; re-tune the prompt for process KPIs (yield, throughput, energy per unit)
- **Supply chain / warehouse ops** — repoint at a WMS/ERP operational store for inventory, fulfillment, and supplier-performance questions
- **Field service / asset-heavy ops** — point at an asset/maintenance database for uptime, work-order, and reliability questions

---

**AgentFactory** · Vertical: Manufacturing & Industrial · Kit v0.1.0
