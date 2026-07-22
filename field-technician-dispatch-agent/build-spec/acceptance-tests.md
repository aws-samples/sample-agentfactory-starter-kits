# Acceptance Tests — Field Technician Dispatch Agent

> Audience: the engineering lead and technical reviewer during sign-off. Each test maps to requirements in [`requirements.md`](requirements.md). Run against the bundled DFW mock data for the reference, then re-run against your data before publishing. Work-order/technician IDs below reference the seed dataset.

## Functional

**T1 — Work-order resolution from plain language.**
- *Setup:* the reference dataset loaded.
- *Action:* `POST /api/dispatch` with `{"message": "Dispatch a technician for WO-1003 - emergency gas leak"}`.
- *Expected:* the agent calls `get_work_order("WO-1003")` and surfaces urgency `critical`, required skills `["plumbing", "gas fitting"]`, required cert `Gas Fitter Certification`, and the job location.
- *Maps to:* FR1.

**T2 — Pending work-order listing.**
- *Setup:* the reference dataset.
- *Action:* ask the agent to list pending work orders (or call `list_pending_work_orders`).
- *Expected:* all five seed work orders with `status: pending` are returned.
- *Maps to:* FR1.

**T3 — Skill + certification hard filter.**
- *Setup:* WO-1003 (requires gas fitting + Gas Fitter Certification).
- *Action:* run the dispatch.
- *Expected:* `search_technicians` returns only technicians holding gas-fitting skill and the Gas Fitter Certification (Marcus Williams, tech-003, in the seed data); technicians without the cert are excluded.
- *Maps to:* FR2.

**T4 — Proximity filtering.**
- *Setup:* a work order with a `max_distance_miles` constraint and the job lat/lng.
- *Action:* call `search_technicians` with the distance + `from_lat`/`from_lng`.
- *Expected:* only technicians within the radius are returned, each annotated with `distance_miles`.
- *Maps to:* FR2.

**T5 — Availability check.**
- *Setup:* any technician ID (e.g. tech-002, no jobs today vs. tech-006, booked until 15:30).
- *Action:* call `check_availability`.
- *Expected:* returns today's jobs, `available_from`, and a correct `is_available_now` flag.
- *Maps to:* FR3.

**T6 — Travel-time estimate.**
- *Setup:* a technician ID and a job lat/lng.
- *Action:* call `calculate_travel_time`.
- *Expected:* returns `distance_miles` (Haversine) and `estimated_travel_minutes` (distance ÷ 35 mph × 60), with the technician's origin city/state.
- *Maps to:* FR4.

**T7 — Parts-inventory check.**
- *Setup:* a job with required skills (e.g. `["HVAC", "refrigeration"]`).
- *Action:* call `check_parts_inventory`.
- *Expected:* returns in-stock / low-stock parts for the matching trade category (or a general fallback if no category matches).
- *Maps to:* FR5.

**T8 — Critical job prioritizes speed.**
- *Setup:* WO-1003 (CRITICAL).
- *Action:* run the dispatch.
- *Expected:* among qualified, available technicians the agent recommends the closest one and its reasoning cites speed/proximity for the critical job.
- *Maps to:* FR6.

**T9 — Routine job optimizes best fit + tie-break.**
- *Setup:* a MEDIUM/LOW job (e.g. WO-1004 EV-charger install) with more than one qualified tech.
- *Action:* run the dispatch.
- *Expected:* the agent optimizes for best overall fit and, on near-ties, prefers higher rating → more experience → lower hourly rate, citing the reason.
- *Maps to:* FR6.

**T10 — Dispatch execution payload.**
- *Setup:* a resolved work order and a chosen technician.
- *Action:* the agent calls `dispatch_technician(tech_id, work_order_id, reason)`.
- *Expected:* returns a `dispatched` confirmation with technician name, work-order title, the reason, and notification text. (Mock in the reference; real notification/assignment when wired.)
- *Maps to:* FR7.

**T11 — SSE streaming of reasoning + tool calls.**
- *Setup:* the streaming endpoint.
- *Action:* `POST /api/dispatch`.
- *Expected:* ordered SSE messages — `reasoning`/`text`, a `tool_call` per tool invocation, a `final_response`, then a `done` event. The SPA renders a card per tool call.
- *Maps to:* FR8.

**T12 — Synchronous endpoint.**
- *Setup:* same request.
- *Action:* `POST /api/dispatch/sync`.
- *Expected:* a single non-streamed JSON response containing the agent's final result.
- *Maps to:* FR8.

**T13 — No-match handling.**
- *Setup:* a work order whose required certification no technician in the pool holds.
- *Action:* run the dispatch.
- *Expected:* the agent explains what's missing and suggests alternatives (widen radius, relax a non-critical requirement, reschedule); it does **not** recommend an unqualified technician.
- *Maps to:* FR9, NFR2.

**T14 — Unknown ID handling.**
- *Setup:* a non-existent work order (e.g. `WO-9999`) or technician (`tech-999`).
- *Action:* call the relevant tool.
- *Expected:* an explicit "not found" result the agent surfaces to the dispatcher; no fabricated record.
- *Maps to:* FR9.

**T15 — Support endpoints + health.**
- *Action:* `GET /api/work-orders`, `GET /api/technicians`, `GET /api/health`.
- *Expected:* work orders and technicians return the seed data; health returns `{"status": "healthy"}`.
- *Maps to:* FR10.

## Non-functional

**T16 — Human-in-the-loop preserved.**
- *Action:* review the end-to-end flow.
- *Expected:* `dispatch_technician` produces a recommendation surfaced to the dispatcher; no path finalizes an assignment without human confirmation.
- *Maps to:* NFR2.

**T17 — Least-privilege role.**
- *Action:* inspect the runtime's execution role.
- *Expected:* only `bedrock:InvokeModel` / `InvokeModelWithResponseStream` on the chosen Anthropic model + inference profile. No broader grants.
- *Maps to:* NFR3.

**T18 — Single-tenant isolation.**
- *Action:* review the deployment.
- *Expected:* one deployment in your account/region; no shared multi-tenant store.
- *Maps to:* NFR6.

## Sign-off

| Role | Name | Date |
|---|---|---|
| Technical reviewer | __________ | ______ |
| Your engineering lead | __________ | ______ |
