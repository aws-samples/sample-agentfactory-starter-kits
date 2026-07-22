# Architecture Decisions — Field Technician Dispatch Agent

> Audience: a coding agent that might be tempted to deviate. These are the major design choices behind the reference implementation plus kit-level packaging decisions. Don't reverse them without a deliberate review.

## AD1 — One ReAct agent, not multiple cooperating agents
**Decision:** Use a single Strands Agents ReAct agent (`backend/app/agent.py`) with seven registered tools, rather than a pipeline of specialist agents.
**Why:** Dispatch is one reasoning task — match a job to a technician using facts the tools fetch. The capability lives in the system prompt + the tools, so a single agent that reasons, calls a tool, observes, and continues is the simplest correct shape.
**What this means for the build:** Don't split the dispatch flow into sub-agents. Add capability by adding or refining tools and the prompt, not by adding agents.

## AD2 — Capability lives in the system prompt + tools
**Decision:** Encode the 7-step process, priority logic, and tie-break/no-match rules in `SYSTEM_PROMPT`; give the agent seven small `@tool` functions.
**Why:** Keeping the policy in the prompt makes it auditable and editable by you, and keeping each tool single-purpose makes it independently testable and repointable.
**What this means for the build:** Tune behavior by editing the prompt and tools. Keep tools small and side-effect-free except `dispatch_technician`.

## AD3 — Required skill + certification is a hard filter
**Decision:** `search_technicians` returns only technicians matching **every** required skill and certification before any other factor is weighed.
**Why:** A technician without the required certification (EPA 608, gas-fitter, master electrician, BICSI, etc.) is not a valid dispatch regardless of proximity or availability. Safety and compliance come first.
**What this means for the build:** Never let proximity or availability override the skill/cert filter. Keep it as a pre-filter, not a soft score.

## AD4 — Explicit priority logic in the prompt
**Decision:** CRITICAL → closest available qualified tech (speed first); HIGH → balance speed and qualification; MEDIUM/LOW → best overall fit. Ties break by rating → experience → cost.
**Why:** Urgent jobs are SLA-bound; speed dominates. Routine jobs can optimize for the best overall match. Making this explicit means the same logic applies on every order, not just when the best dispatcher is on shift.
**What this means for the build:** Re-tune the tiers and trade-offs for your operation, but keep the priority logic explicit and in the prompt where it's auditable.

## AD5 — Stream the reasoning over SSE
**Decision:** Stream the agent's reasoning, tool calls, and final response as Server-Sent Events from `POST /api/dispatch`, via a `callback_handler` that maps Strands callback events to SSE messages (`reasoning`, `text`, `tool_call`, `final_response`, `done`).
**Why:** The product value is *visible, auditable* logic — the dispatcher watches the agent think and can override. A single opaque answer would lose the trust and the override point.
**What this means for the build:** Keep the callback-to-SSE bridge. The frontend reads the stream and renders a card per tool call; don't collapse to a single response.

## AD6 — SSE over POST (background thread + queue)
**Decision:** Stream from a POST endpoint by running the agent on a background thread that pushes events to a queue the SSE generator drains, rather than using `EventSource` (GET-only).
**Why:** The dispatch request needs a JSON body (`{"message": ...}`) *and* a streamed response; `EventSource` only supports GET with no body. A `POST /api/dispatch/sync` is also provided for non-streaming callers.
**What this means for the build:** Keep the POST + manual stream pattern; don't refactor to `EventSource`.

## AD7 — `calculate_travel_time` is a Haversine + fixed-speed stub
**Decision:** Estimate travel time as straight-line Haversine distance ÷ a fixed 35 mph, in `_haversine_miles` / `calculate_travel_time`.
**Why:** It demonstrates proximity-aware dispatch with zero external dependencies and no API key, which is right for a reference. It is explicitly *not* production-accurate.
**What this means for the build:** Treat this as an integration point. For production, replace it with a real routing/traffic API; the agent's reasoning is unchanged, only the ETA source.

## AD8 — `dispatch_technician` returns a mock confirmation
**Decision:** The dispatch tool validates the technician and work order and returns a structured assignment confirmation (technician, work-order title, reason, notification text) — it does not call a real notification or assignment system.
**Why:** The reference is a working demo with no real external systems to call. The decision and its rationale are real; the side effect is mocked.
**What this means for the build:** Wire this to your SMS/push/FSM assignment during customization. Keep it the *only* tool with a side effect, and keep a human confirming before it fires in production.

## AD9 — Mock JSON data layer
**Decision:** The seven tools read from `backend/data/*.json` (8 technicians, 5 work orders in the DFW metro, schedules) loaded per call.
**Why:** Zero infra for the demo; deterministic, reproducible scenarios across five trades and four urgency levels.
**What this means for the build:** **Production must repoint each tool to your real systems** (FSM, skills DB, scheduling, inventory). Match the data shapes or adapt the tool parsing. Nothing is persisted in the reference.

## AD10 — Custom stack, not Bedrock Agents / KB / Guardrails
**Decision:** Despite the `custom-iac` build level, implement as a custom stack — Strands Agents + FastAPI + React + Bedrock — with no managed Bedrock Agent, no Knowledge Base, and no Bedrock Guardrail.
**Why:** The agent reasons from its system prompt and tool results; there's no document corpus to retrieve (so no KB) and the tool/prompt logic carries the constraints. Strands gives native Bedrock integration, the `@tool` decorator, and streaming callbacks with minimal ceremony.
**What this means for the build:** Don't introduce a KB or Guardrail to "complete" the stack. Add them only if a specific requirement of yours (e.g. PII redaction, a knowledge corpus) calls for it.

## AD11 — Decision-support, not autonomous dispatch
**Decision:** Output is a recommendation streamed to a human dispatcher; no automated assignment without confirmation.
**Why:** SLAs, safety-critical certifications, and customer trust require an accountable human at the point of assignment.
**What this means for the build:** Never wire the recommendation to an automatic assignment that skips the dispatcher.
