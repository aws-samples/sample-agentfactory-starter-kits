# AGENTS.md — Field Technician Dispatch Agent

> **Audience: a coding agent** (Kiro / Claude Code / Codex / Cursor / etc.) re-implementing or customizing this kit for your organization.

## What this is

- A **single-agent, tool-using dispatch assistant** for field-service work orders. A dispatcher describes a work order in plain language; the agent reasons through it and recommends a technician.
- **One Strands Agents ReAct agent** on Amazon Bedrock (Claude Sonnet 4), defined in `backend/app/agent.py`. The capability lives in the **system prompt + the seven registered tools** — not in multiple cooperating agents.
- The agent runs a **ReAct loop**: reason → call a tool → observe → repeat → decide. It streams every reasoning step, tool call, and the final dispatch over **SSE** so the dispatcher watches the logic unfold.
- **Seven `@tool` functions** in `backend/app/tools.py`: `get_work_order`, `list_pending_work_orders`, `search_technicians`, `check_availability`, `calculate_travel_time`, `check_parts_inventory`, `dispatch_technician`.
- **Priority-based decision logic** is encoded in the system prompt: CRITICAL → speed (closest available qualified tech), HIGH → balanced, MEDIUM/LOW → best overall fit. Tie-break: higher rating, then more experience, then lower cost.
- Delivery surface: **FastAPI backend** (`backend/app/main.py`) with an SSE streaming endpoint + **React/Vite SPA** (`frontend/src/`). Runs locally against **mock JSON data** in `backend/data/`.
- The output is a **recommendation for a human dispatcher**, not an autonomous assignment.

## Where to read first (in the implementation you build)

1. `README.md` — purpose, the 7-tool table, the example interaction, local run instructions.
2. `backend/app/agent.py` — the `BedrockModel` config and the `SYSTEM_PROMPT`. The prompt *is* the dispatch policy (the 7-step process, priority logic, tie-break and no-match handling).
3. `backend/app/tools.py` — the seven `@tool` functions and the `_haversine_miles` helper. The tool docstrings define the agent's contract with each tool.
4. `backend/app/main.py` — FastAPI app: the SSE `POST /api/dispatch` endpoint, the `callback_handler` that turns Strands events into SSE messages, plus `/api/dispatch/sync`, `/api/work-orders`, `/api/technicians`, `/api/health`.
5. `backend/data/*.json` — the seed dataset: `technicians.json` (8 techs with skills/certs/location/rating/rate/experience), `work_orders.json` (5 orders across five trades and four urgency levels in the DFW metro), `schedules.json` (today's jobs + `available_from` per tech).
6. `frontend/src/App.jsx` + `frontend/src/components/` — the SSE reader and the components that render reasoning, tool-call cards, the work-order side panel, and the dispatch summary.
7. `aidlc-docs/` — the design trail (inception requirements/user-stories/design, construction functional design + test plans) behind the implementation.

## Re-deploying in a new environment

1. **Rewrite the dispatch policy** — edit `SYSTEM_PROMPT` in `backend/app/agent.py` for your trade mix, urgency tiers, and the skill/proximity/rating/cost trade-offs that matter to your operation.
2. **Repoint the seven tools** in `backend/app/tools.py` from the bundled JSON files to your real systems — FSM/work-order API for `get_work_order`/`list_pending_work_orders`, HR/skills database for `search_technicians`, scheduling system for `check_availability`, and the parts/inventory system for `check_parts_inventory`.
3. **Replace the travel-time stub** — `calculate_travel_time` uses straight-line `_haversine_miles` + a fixed 35 mph. Swap in a real routing/traffic API for production ETAs.
4. **Wire `dispatch_technician` to a real action** — it currently returns a mock confirmation string ("SMS and app notification sent to ..."). Point it at your notification + work-order-assignment system.
5. **Match the data schemas** — align `technicians.json` / `work_orders.json` / `schedules.json` shapes (or the live API responses) to your field-service data.
6. **Pick the model tier and region** in `BedrockModel(...)` (`backend/app/agent.py`); confirm Bedrock access in that region.

## What you're NOT building

- **Not an autonomous dispatcher.** The output is a recommendation a human dispatcher confirms. Do not wire the agent to finalize assignments without a human in the loop.
- **Not Bedrock Agents / Knowledge Base / Guardrails.** Despite the `custom-iac` build level, this is a **custom stack** (Strands Agents + FastAPI + React + Bedrock). There is no managed Bedrock Agent, no RAG/KB, and no Bedrock Guardrail in the reference. Don't add them unless asked.
- **Not a route optimizer.** The agent matches one technician to one job by skill/availability/proximity. It is not a multi-stop VRP solver. If your core problem is route optimization, flag it (see disqualifiers in `kit.json`).
- **Not a persistent datastore.** The reference reads mock JSON on each tool call; nothing is written back. Production needs real systems of record — that's customization, not shipped.
- **Not a copy of the source into the kit folder.** The kit holds metadata + specs; you build the implementation from this contract in your own repository.

## Non-negotiables

- **Human-in-the-loop.** `dispatch_technician` produces a recommendation streamed to a dispatcher; you own the final assignment and any SLA commitment.
- **Stream the reasoning.** The value is the *visible, auditable* logic — every reasoning step and tool call streams to the UI before the assignment. Don't collapse it to a single opaque answer.
- **One ReAct agent, seven tools.** The capability is the system prompt + the tools, not a chain of sub-agents. Keep the tools small, single-purpose, and independently testable.
- **Required-skill / certification match is a hard filter.** A technician without the required skill or certification is never a valid recommendation — `search_technicians` filters on both before anything else is weighed.
- **Priority logic is explicit.** CRITICAL → speed, HIGH → balanced, MEDIUM/LOW → best fit, with the documented tie-break order. Keep it in the prompt where it's auditable.
- **The travel-time and dispatch tools are stubs by design.** Treat `calculate_travel_time` (Haversine + 35 mph) and `dispatch_technician` (mock confirmation) as integration points, not finished logic.

## Defaults

- **Model:** `us.anthropic.claude-sonnet-4-20250514-v1:0` (cross-region inference profile). Region `us-west-2`.
- **Backend:** FastAPI on port 8000; SSE endpoint `POST /api/dispatch`; health check `GET /api/health`.
- **Frontend:** React + Vite dev server on port 5173, proxied to the backend.
- **Data:** mock JSON in `backend/data/` (8 technicians, 5 work orders, schedules) — replace with your real integrations.
- **No auth, no persistence, no production host** in the reference — these are customization work.

## Things to confirm before customizing

- What systems hold technician skills, certifications, location, and live schedules, and how does the agent read them (API, DB, export)?
- What's the work-order schema, and how does a dispatch request reach the agent (FSM webhook, queue, manual entry)?
- What urgency tiers and SLAs do you use, and how should priority logic map to them?
- Should `calculate_travel_time` use a specific routing/traffic provider you already pay for?
- What does "dispatch" actually trigger — SMS, mobile-app push, an FSM assignment write-back — and which system owns it?
- Which model tier and region fit your latency, cost, and data-residency needs?

## When to pause and reassess mid-build

- You want fully autonomous dispatch with no dispatcher confirmation (out of scope — escalate).
- There's no structured technician data (skills/certs/location/schedule) to feed the tools.
- The real problem is multi-stop route optimization, not skill/availability matching (a VRP solver fits better).
- Bedrock model access for the chosen tier isn't enabled in your account/region.
- You need persistence, auth, or audit retention beyond the reference's mock-data demo.

## Done definition

- A single Strands ReAct agent runs with the seven registered tools against your data sources (or the mock JSON for a demo).
- A plain-language dispatch request streams reasoning + tool calls over SSE and ends with a dispatch recommendation naming the technician, distance, availability, and rationale.
- Required-skill / certification filtering is enforced; priority logic and tie-breaks behave as specified; the no-match path explains what's missing instead of guessing.
- `calculate_travel_time` and `dispatch_technician` are pointed at real systems (or explicitly documented as stubs for a demo).
- Acceptance tests in [`build-spec/acceptance-tests.md`](build-spec/acceptance-tests.md) pass.
- A runtime + auth are in place in your account (customization, not shipped), and `GET /api/health` returns healthy.
