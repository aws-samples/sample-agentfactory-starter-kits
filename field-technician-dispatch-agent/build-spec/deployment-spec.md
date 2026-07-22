# Deployment Spec — Field Technician Dispatch Agent

> Audience: a coding agent standing the agent up in your account. The reference runs locally; production hosting is a customization you choose.

## Deployment context

- **Account:** your own AWS account (single-tenant).
- **Region:** `us-west-2` by default (where Claude Sonnet 4 is invoked via cross-region inference profile). Confirm Bedrock model access in the chosen region.
- **Trust boundary:** everything runs in your account; the only outbound dependency is in-region Bedrock model invocation (plus any routing/notification APIs you wire into the stub tools).
- **Source code location:** the kit folder holds metadata + specs only; obtain the reference implementation source to deploy.
- **Delivery shape:** a FastAPI backend (`backend/`, port 8000) plus a built React/Vite SPA (`frontend/`). The reference runs the backend with `uvicorn` and the frontend with the Vite dev server; you pick the production runtime.

## Local run (reference / demo)

```bash
# Backend
cd backend && python3.12 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload --port 8000

# Frontend
cd frontend && npm install && npm run dev   # http://localhost:5173
```

Mock JSON data is loaded from `backend/data/`; AWS credentials with Bedrock access (`us-west-2`) are required for live model calls.

## Resources to create (production — you choose)

The reference ships **no IaC**. A production deployment in your account typically needs:

- **Compute / runtime:** a host for the FastAPI backend (e.g. a container service, a VM, or serverless behind an ASGI adapter) on port 8000 with health check `GET /api/health`.
- **Static hosting:** somewhere to serve the built SPA (`frontend/dist`) — co-served by the backend or a separate static host/CDN.
- **Identity:** an execution role for the runtime granting **only** the Bedrock invoke permissions for the chosen model/inference profile (`bedrock:InvokeModel` / `InvokeModelWithResponseStream` on the Anthropic model + inference profile).
- **Bedrock model access:** Claude Sonnet 4 access enabled in-region — no resource to create, but access must be turned on.
- **Authentication:** an auth layer in front of the API (the reference API is open) — required for production.
- **Observability:** structured logging around the agent run and tool calls (e.g. CloudWatch log group + metrics).
- **Integrations:** connectivity from the runtime to your FSM/work-order API, skills DB, scheduling system, parts inventory, routing API, and notification system as the tools are repointed.

## What you configure during the build

| Config item | Format | Source |
|---|---|---|
| Dispatch policy (process, priority logic, tie-breaks) | `SYSTEM_PROMPT` string | `backend/app/agent.py` |
| Model tier + region | `BedrockModel(model_id=..., region_name=...)` | `backend/app/agent.py` |
| Work-order lookup / pending list | `@tool` functions | `backend/app/tools.py` (`get_work_order`, `list_pending_work_orders`) |
| Technician search (skill/cert/proximity filter) | `@tool` function | `backend/app/tools.py` (`search_technicians`) |
| Availability check | `@tool` function | `backend/app/tools.py` (`check_availability`) |
| Travel-time source | `@tool` function + helper | `backend/app/tools.py` (`calculate_travel_time`, `_haversine_miles`) |
| Parts-inventory check | `@tool` function | `backend/app/tools.py` (`check_parts_inventory`) |
| Dispatch action (notification/assignment) | `@tool` function | `backend/app/tools.py` (`dispatch_technician`) |
| Data schemas | JSON shapes / API responses | `backend/data/*.json` |
| Frontend branding / layout | React components | `frontend/src/components/` |
| CORS allowed origins | FastAPI middleware | `backend/app/main.py` |

## What's pre-built

- The single Strands ReAct agent with the dispatch system prompt and seven registered tools.
- The seven `@tool` functions and the `_haversine_miles` helper.
- The FastAPI app with the SSE `POST /api/dispatch` endpoint, the callback-to-SSE bridge, `POST /api/dispatch/sync`, `GET /api/work-orders`, `GET /api/technicians`, and `GET /api/health`.
- The React + Vite SPA: chat panel, streamed reasoning, tool-call cards, work-order side panel, dispatch-summary card.
- The seed dataset (8 technicians, 5 work orders across five trades and four urgency levels, schedules) in the DFW metro.

## Cost expectations

| Driver | Notes | Typical range |
|---|---|---|
| Bedrock (Claude Sonnet 4) | One ReAct loop per dispatch = several model invocations (one per tool turn). Scales with work-order volume × tool turns | Model from token sizes × turns × volume |
| Compute host (FastAPI) | Runtime you choose, billed for compute time | Depends on host + traffic |
| Static hosting / CDN | Serving the built SPA | Low |
| Routing / traffic API | Only if the Haversine stub is replaced | Per-request, vendor-priced |
| Logging / observability | You add | Low |

## Pre-deployment checklist

- [ ] Bedrock access enabled for the chosen Claude tier in the target region.
- [ ] Execution role scoped to Bedrock invoke only for the chosen model/inference profile.
- [ ] System prompt tuned to your trades, urgency tiers, and trade-offs.
- [ ] Seven tools repointed from mock JSON to your real systems (or explicitly kept on mock data for a demo).
- [ ] `calculate_travel_time` decision made: Haversine stub vs. real routing API.
- [ ] `dispatch_technician` wired to your notification/assignment system (or kept mock for a demo).
- [ ] Auth layer chosen for in front of the API.
- [ ] Runtime + static hosting chosen.

## Post-deployment validation

- [ ] `GET /api/health` returns `{"status": "healthy"}`.
- [ ] A plain-language dispatch request streams reasoning + tool calls over SSE and ends with a dispatch recommendation.
- [ ] A job whose required certification no tech holds returns a no-match explanation, not an unqualified recommendation.
- [ ] CRITICAL vs. MEDIUM/LOW jobs show the expected priority behavior.
- [ ] Acceptance tests pass against the deployed instance.
- [ ] Execution role confirmed least-privilege (Bedrock invoke only).

## Day-2 operations (you own these)

- Add authentication in front of the API.
- Add persistence/logging for dispatch decisions (the reference doesn't persist).
- Re-tune the system prompt and skill/cert filters as trades, certifications, and SLAs change.
- Monitor Bedrock spend vs. work-order volume and tool turns per dispatch.
- Maintain the routing-API and notification integrations as those systems change.
- Decommission by removing the runtime, static host, and role when retiring the agent.
