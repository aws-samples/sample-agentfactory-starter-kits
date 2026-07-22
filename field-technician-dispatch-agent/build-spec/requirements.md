# Requirements — Field Technician Dispatch Agent

> Audience: a coding agent implementing or customizing the kit, and whoever certifies the build.

## Functional requirements

**FR1 — Work-order intake from plain language.** The system shall accept a plain-language dispatch request (e.g. *"Dispatch a technician for WO-1003 — emergency gas leak"*) via `POST /api/dispatch` and resolve the referenced work order with the `get_work_order` tool, exposing its required skills, required certifications, urgency, location, and estimated duration. The system shall also list pending work orders via `list_pending_work_orders`. *Maps to: T1, T2.*

**FR2 — Qualified-technician search with hard filter.** The `search_technicians` tool shall filter the technician pool so that only technicians matching **every** required skill **and** every required certification are returned, with an optional proximity filter (max distance from the job lat/lng). A technician missing a required skill or certification shall never be a candidate. *Maps to: T3, T4.*

**FR3 — Availability check.** The `check_availability` tool shall return a technician's schedule for the day (today's jobs, `available_from`, and an `is_available_now` flag) so the agent can prefer sooner-available technicians, especially for urgent jobs. *Maps to: T5.*

**FR4 — Travel-time estimation.** The `calculate_travel_time` tool shall compute straight-line distance (Haversine) from a technician's location to the job site and an estimated drive time at a fixed assumed speed, returning distance in miles and estimated minutes. This is an explicit integration stub for a real routing API. *Maps to: T6.*

**FR5 — Parts-inventory check.** The `check_parts_inventory` tool shall report whether common parts for the job's trade are in stock, so the agent can factor materials availability into the recommendation. *Maps to: T7.*

**FR6 — Priority-based recommendation.** The agent shall apply priority logic from the system prompt: CRITICAL → closest available qualified technician (speed first); HIGH → balance speed and qualification; MEDIUM/LOW → best overall fit. Ties shall break by higher rating, then more years of experience, then lower hourly rate. *Maps to: T8, T9.*

**FR7 — Dispatch execution (recommendation).** The `dispatch_technician` tool shall finalize a recommendation for a named technician and work order with a plain-language `reason`, returning an assignment confirmation (technician, work-order title, reason, notification text). In the reference this is a mock confirmation; in production it calls your notification/assignment system. The recommendation is for a human dispatcher to confirm. *Maps to: T10.*

**FR8 — Streamed reasoning.** The system shall stream the agent's reasoning, each tool call, and the final response over SSE from the `POST /api/dispatch` endpoint via a callback handler, so the dispatcher sees the logic step by step before the assignment. A synchronous `POST /api/dispatch/sync` shall also be available. *Maps to: T11, T12.*

**FR9 — No-match / not-found handling.** When no technician matches all requirements, the agent shall explain what's missing and suggest alternatives (widen search radius, relax a non-critical requirement, reschedule) rather than recommend an unqualified technician. Tools shall return explicit "not found" results for unknown work-order or technician IDs. *Maps to: T13, T14.*

**FR10 — Supporting read endpoints.** The system shall expose `GET /api/work-orders` and `GET /api/technicians` for the UI's work-order side panel, and `GET /api/health` for readiness. *Maps to: T15.*

## Non-functional requirements

**NFR1 — Latency.** A dispatch is one ReAct loop spanning several tool-calling turns; it shall complete in a timeframe acceptable for interactive desk use with the default tier (Claude Sonnet 4). Streaming keeps the dispatcher informed during the run.

**NFR2 — Human-in-the-loop.** The system shall never finalize an assignment autonomously; output is a recommendation a dispatcher confirms.

**NFR3 — Security.** Single-tenant in your account. The runtime's role shall grant only the Bedrock invoke permissions needed for the chosen model/inference profile. Production deployments shall place authentication in front of the API (not shipped in the reference). Data in transit over HTTPS.

**NFR4 — Cost predictability.** Bedrock cost shall scale with work-order volume × tool turns per dispatch; a tight system prompt that avoids redundant tool calls is the primary cost lever.

**NFR5 — Auditability.** Each recommendation shall be reconstructable from the streamed reasoning + tool calls and the final `dispatch_technician` payload (technician, work order, reason).

**NFR6 — Single-tenancy.** One deployment per organization in your own account/region; no shared multi-tenant store.

**NFR7 — Extensibility of tools.** Each of the seven tools shall be a small, single-purpose `@tool` function so it can be repointed from mock JSON to your real system without changing the agent or the other tools.

## Out of scope

- Autonomous dispatch with no dispatcher confirmation.
- Multi-stop route optimization / VRP (single qualified-tech matching only).
- Persistent datastore (the reference reads mock JSON; production persistence is a customization).
- Authentication/authorization layer (must be added for production).
- Real routing/traffic ETAs (`calculate_travel_time` ships as a Haversine + fixed-speed stub).
- Real notification/FSM write-back (`dispatch_technician` ships as a mock confirmation).
- Bedrock Knowledge Base, Guardrails, or fine-tuning — none are used.

## Dependencies

- Bedrock model access enabled for the chosen Claude tier in your region (`us-west-2` default for Claude Sonnet 4 via cross-region inference profile).
- A runtime in your account to host the FastAPI backend, plus a way to serve the built React SPA.
- Python 3.12+ and Node.js 18+ for local development (`strands-agents`, `strands-agents[bedrock]`, `fastapi`, `uvicorn`, `sse-starlette`, `pydantic`).
- Structured technician data (skills, certifications, location, schedule) and work-order data to repoint the tools from mock JSON to real systems.
- Optional: a routing/traffic API and a notification/FSM integration for the two stub tools.
