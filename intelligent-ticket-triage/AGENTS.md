# AGENTS.md — Intelligent Ticket Triage

> Coding-agent contract for `intelligent-ticket-triage`. Read this file first if you are a coding agent (Kiro, Claude Code, Codex, Cursor, or similar) being asked to extend, modify, or re-deploy this kit.

## What this kit does

A Bedrock Agent that ingests support tickets from any source, classifies them by category/priority/complexity using RAG over historical ticket data, routes to the correct team, and auto-resolves common issues — all behind Bedrock Guardrails for PII and topic boundaries.

**Vertical:** Software & Internet
**Build level:** Custom IaC (Bedrock Agents + KB + Guardrails)
**Build status:** Built — full CloudFormation stack + Lambda action groups in `infrastructure/` and `src/`

## Build-level guidance

This kit is `custom-iac` — you own the full CloudFormation stack: Bedrock Agent + Knowledge Base + Guardrails + Lambda action groups + monitoring. Scripts are provided as-is.

This was the first reference kit, and unlike most kits in this repository it ships its full source code in this folder.

## What you (the coding agent) should do

This kit is **already built**. The agent's source is in this kit folder under `infrastructure/` and `src/`. Treat this AGENTS.md as **post-hoc documentation** — read it before touching the source.

If you're being asked to:

- **Re-deploy** the kit in a your account → run `infrastructure/deploy.sh`. It validates AWS creds, deploys CFN, packages Lambdas, prepares the agent, and creates a `live` alias. See the README's quick-start.
- **Extend** the kit (new tool, different model, custom routing) → modify `infrastructure/template.yaml` for AWS resources, `src/agent/tools/*.py` for tool logic, `src/agent/system-prompt.txt` for the agent's instructions. Re-run `deploy.sh` — it's idempotent.
- **Adapt** the kit for a different ticket source → most of that lives in `src/agent/tools/route-ticket.py` (routing rules) and `src/agent/tools/classify-ticket.py` (classification map). Plus the webhook URL and ticket-source-type fields in `infrastructure/config.example.yaml`.

If you're working in a engagement, fork this kit and deploy from your fork rather than modifying the upstream copy.

## Required behavior

The agent must:

- Receive incoming tickets via webhook (Zendesk / Jira / ServiceNow / custom API)
- Classify each ticket by category (`bug`, `feature_request`, `billing`, `access`), priority (`P1`–`P4`), and complexity (`auto-resolvable`, `L1`, `L2`, `engineering`) using historical ticket data via RAG
- Auto-resolve high-confidence (≥ 0.9) tickets with documented solutions by generating a KB-grounded response
- Route lower-confidence or complex tickets to the correct team queue, pre-loaded with context from the KB
- Enforce Bedrock Guardrails on every input and output: PII redaction, topic boundaries, grounding check, content filters

## Tools the agent needs

Three Lambda action groups, all defined in `infrastructure/template.yaml` and implemented in `src/agent/tools/`:

| Tool | File | Purpose |
|---|---|---|
| `classify_ticket` | `src/agent/tools/classify-ticket.py` | Returns category, priority, complexity, confidence |
| `route_ticket` | `src/agent/tools/route-ticket.py` | Maps classification to a team queue with KB context |
| `resolve_ticket` | `src/agent/tools/resolve-ticket.py` | Generates and sends an auto-resolution response |

Plus a Knowledge Base with Titan Embeddings v2 + OpenSearch Serverless, defined in the same template.

## System prompt

The agent's system prompt is in `src/agent/system-prompt.txt` and gets injected into the Bedrock Agent on deploy. Read it for the full instructions; the high-level structure is:

- Establish role (intelligent ticket triage agent)
- Define the workflow (classify → decide → route or resolve)
- List the rules (always classify first, never fabricate solutions, route to human if confidence drops)
- Define categories, priority levels, and complexity rubric

## Conventions

- **AWS region:** Configurable via `infrastructure/config.yaml` (default: `us-east-1`)
- **Logging:** CloudWatch dashboard at `${CustomerNamePrefix}-ticket-triage` shows volume, auto-resolution rate, latency, and errors
- **Guardrails:** PII redaction (email, phone, SSN, credit card) + topic deny-list + content filters (sexual/violence/hate HIGH; insults MEDIUM)
- **Cost target:** ~$0.02–0.05 per ticket (Bedrock invocations + KB queries dominate)
- **You customize:**
  - Knowledge Base content (your tickets + your product docs)
  - Guardrail rules (your PII patterns, your topic boundaries)
  - Routing logic per category/priority
  - Auto-resolution confidence threshold (default 0.9; lowered by 0.05 for enterprise tier)
  - Ticket source integration (Zendesk / Jira / ServiceNow / custom API)

## Acceptance — how we know it works

Before bumping `kit.json.status` from `review` to `published`:

1. CFN stack deploys cleanly with `./infrastructure/deploy.sh`
2. All three Lambda action groups invoke without errors against the canonical sample inputs
3. Agent's `prepare-agent` succeeds and the `live` alias is created
4. Guardrails fire on synthetic PII / off-topic inputs (no leak, refusal message returned)
5. CloudWatch dashboard shows non-zero metrics
6. You have reviewed at least 20 real production-shaped tickets and signed off

## Repository convention

This kit ships its source code **inside the kit folder** under `infrastructure/` and `src/` — the kit folder is both the documentation and the source of truth for this agent.
