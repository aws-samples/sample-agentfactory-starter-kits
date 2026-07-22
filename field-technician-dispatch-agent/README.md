# Field Technician Dispatch Agent

> **Status:** Draft · Spec-only blueprint (build it from this kit's contract) · Build level: Custom Stack

A work-order dispatch agent that picks the right field technician for a job and shows its work. A dispatcher describes a work order in plain language ("emergency gas leak at WO-1003"); a single Strands ReAct agent on Amazon Bedrock (Claude Sonnet 4) calls seven tools — work-order lookup, skill/certification/proximity search, availability check, Haversine travel-time, parts-inventory check, and dispatch execution — and streams its reasoning step by step to a chat UI before assigning a technician. The output is a dispatch recommendation with a clear, auditable rationale: which technician, how far away, available when, and why they were chosen.

## Why this exists

Field-service dispatch is a constraint-matching problem that most teams still solve by hand: a dispatcher mentally cross-references who has the right skills and certifications, who's available today, who's closest, and how urgent the job is — across an FSM system, a scheduling tool, and tribal knowledge. It's slow, it's inconsistent between dispatchers, and on urgent jobs (a gas leak, a down commercial HVAC unit) the minutes spent finding the right person are minutes against an SLA. This agent collapses that lookup into one reasoned pass and streams the reasoning so the dispatcher can trust it and override it. It's a fast, transparent second opinion for the dispatch desk — not a replacement for the dispatcher.

## How to use this kit

This kit is a blueprint: it contains the architecture, the build contract, and acceptance tests — but **not** the agent's source code. No source is included; the agent is built from the spec. Read [`AGENTS.md`](AGENTS.md) + [`build-spec/`](build-spec/) and have a coding agent (Kiro / Claude Code / Cursor / Codex) implement the pattern in your own AWS account against your work-order and technician systems.

**What the spec targets:** a locally runnable stack — FastAPI backend on `:8000`, React/Vite frontend on `:5173` — that works against bundled mock JSON data and invokes live Bedrock with AWS credentials configured for `us-west-2`. The seven tools and the dispatch system prompt are the parts you customize.

## What this kit gives you

| File | What's in it |
|---|---|
| [`kit.json`](kit.json) | Kit manifest — services, model, outcomes, who it's for, ROI scaffolding |
| [`architecture/architecture.md`](architecture/architecture.md) | The stack, a component diagram, the dispatch data flow (happy + no-match paths), audit trail |
| [`business-case/roi-framework.md`](business-case/roi-framework.md) | ROI math template, cost drivers, objection handling, competitive framing |
| [`AGENTS.md`](AGENTS.md) | Build contract for a coding agent re-implementing or customizing the kit |
| [`build-spec/`](build-spec/) | Requirements, architecture decisions, deployment spec, acceptance tests |

## Vertical applicability

The pattern is the same wherever a skilled, distributed workforce is matched to incoming jobs:

- **Skilled trades (HVAC / electrical / plumbing):** the reference scenario — emergency gas leak, leaking commercial refrigerant, EV-charger install — match by trade skill, certification (EPA 608, gas-fitter, master electrician), and proximity.
- **Telecom & network install:** dispatch BICSI/CCNA-certified techs to structured-cabling and AP-mounting jobs by skill and site location.
- **Facilities & property management:** route the nearest qualified technician to building-system tickets, balancing urgency against travel time.
- **Medical-equipment / utilities field service:** assign certified field engineers to service calls where certification match and response time both matter.

## Shared responsibility

This is an accelerator and a working reference, not a managed service. You own the deployed agent, the dispatch logic in the system prompt, the integrations that connect the seven tools to your real systems, the technician and work-order data, and the AWS infrastructure in your account. The agent's output is a recommendation streamed to a human dispatcher — you own the final assignment and any SLA commitments. The reference ships with mock data and no production host or auth; wiring those in is customization work. Code is provided as-is.
