# AGENTS.md — Dental Front-Desk Agent

> **Audience: a coding agent** (Kiro / Claude Code / Cursor / etc.) re-implementing or customizing this kit for your organization.

## What this is

- A **router + specialist multi-agent front-desk system** for dental practices, built on the **Strands Agents SDK** and deployed to **Amazon Bedrock AgentCore Runtime**.
- A **Router agent** (`packages/router-agent`) classifies patient intent (SCHEDULING / INSURANCE / GENERAL / ESCALATE / UNCLEAR) and either answers general practice questions itself or delegates to a specialist via tools.
- A **Scheduling agent** (`packages/scheduling-agent`) books / reschedules / cancels appointments and looks up availability.
- An **Insurance agent** (`packages/insurance-agent`) checks plan eligibility, coverage, and accepted plans — and **always appends an insurance disclaimer**.
- All three agents run on **Claude Sonnet 4.5** (`us.anthropic.claude-sonnet-4-5-20250514`) and are constrained by HIPAA-safe-language prompt rules + a **Bedrock Guardrail** (grounding / hallucination checks, applied via `bedrock:ApplyGuardrail`).
- Every interaction is **traced (OTEL)**, **scored by an LLM-as-a-judge evaluation pipeline** on four rubrics, and surfaced to practice managers in a **React + AppSync dashboard**.
- Backend is mocked: `packages/mock-services` ships scheduling, insurance, reminders, practice-config, and patient services on **Lambda + API Gateway + DynamoDB** so the full loop demos on synthetic data before any real integration.

**Vertical:** Healthcare (dental practices / DSOs / dental voice-platform vendors)
**Build level:** Custom IaC — AgentCore Runtime + Guardrails + Observability/Eval pipelines + AppSync dashboard
**Build status:** Spec-only — no source code is included in this kit folder; build the implementation from this contract.

## Where to read first (in the implementation you build)

1. `README.md` — system overview, the service table, the 4 CloudFormation stacks, the demo tenant.
2. `packages/router-agent/main.py` — the AgentCore Runtime entrypoint (`@app.entrypoint`), payload contract (`prompt`, `tenant_id`, `patient_id`, `session_history`), and how the router agent is constructed.
3. `packages/router-agent/src/prompts.py` — `ROUTER_SYSTEM_PROMPT`: intent classification, communication rules, HIPAA-safe language, frustration detection, escalation rules. The prompts *are* the capability definition.
4. `packages/router-agent/src/tools.py` — the four router tools: `delegate_to_scheduling`, `delegate_to_insurance`, `get_practice_info`, `escalate_to_human`.
5. `packages/{scheduling,insurance}-agent/src/prompts.py` + `tools.py` — specialist prompts and the tools that call the mock services over HTTP (`MOCK_SERVICES_API_URL`).
6. `packages/evaluations/src/rubrics.py` — the four rubric definitions, scoring criteria, and weights; `evaluator.py` for the composite math; `alerts.py` for the per-rubric thresholds.
7. `packages/observability/src/` — trace processor, hourly metrics aggregation (P50/P95/P99 + tokens), hallucination detector fed by Guardrails events.
8. `infrastructure/unit-{1,2,3,4}-*.yaml` — the four CloudFormation stacks and the `DentalFrontDesk-*` DynamoDB tables.
9. `scripts/deploy-agent-boto3.py` — deploys the router agent to AgentCore Runtime via the `bedrock-agentcore-control` API and creates the `DentalFrontDeskAgentCoreRuntime` execution role.

## Re-deploying for another tenant

1. **Rewrite the three system prompts** in `packages/{router,scheduling,insurance}-agent/src/prompts.py` — intent rules, HIPAA-safe phrasing, escalation triggers, the insurance disclaimer wording, and the practice's policies (cancellation window, walk-in policy, booking horizon).
2. **Repoint the specialist tools** in `packages/{scheduling,insurance}-agent/src/tools.py` from the mock services to your real scheduling/PMS and insurance-eligibility APIs (the tool signatures are the integration contract).
3. **Replace or reseed the mock services** in `packages/mock-services/` — swap in real integrations, or seed the `DentalFrontDesk-*` foundation tables with your providers, schedules, accepted plans, and policies.
4. **Seed per-practice config** (hours, policies, accepted plans, providers) into the foundation DynamoDB tables, keyed by `tenant_id`.
5. **Tune the evaluation rubrics and alert thresholds** in `packages/evaluations/src/rubrics.py` (weights + scoring criteria) and `packages/evaluations/src/alerts.py` (per-rubric thresholds / window size) to the practice's quality bar.
6. **Confirm the Guardrail** is created and attached, and that the runtime role has `bedrock:ApplyGuardrail` so grounding/hallucination checks fire.
7. **Deploy** the four stacks (`infrastructure/unit-1..4`) then run `scripts/deploy-agent-boto3.py` to push the agent to AgentCore Runtime. Re-brand the dashboard in `packages/dashboard-ui/`.

## What you're NOT building

- **Not a clinical advisor.** The agent never gives diagnoses, treatment guidance, medication advice, or outcome guarantees. The router prompt explicitly refuses these and escalates. Do not add tools or prompt language that cross this line.
- **Not an autonomous closer.** Billing disputes, complaints, and anything the agent can't resolve route to a human via `escalate_to_human`. Do not wire the agent to settle disputes or override office policy.
- **Not production-grade compliance out of the box.** The reference runs on **synthetic data with mock services** in a demo/PoC posture — no real auth, encryption-at-rest review, retention policy, or formal HIPAA sign-off. Address every one of these before any production data touches it.
- **Not a copy of the source into the kit folder.** This kit folder holds metadata + specs only; you build the implementation from this contract in your own repository.

## Non-negotiables

- **HIPAA-safe language is enforced in every prompt.** Agents use general terms ("your appointment", not "your root canal"), never volunteer clinical detail, and never read back sensitive info unprompted. Keep these rules in all three prompts.
- **The insurance disclaimer is mandatory.** Every coverage response must include *"This is general information. Please verify with your insurance provider for exact coverage details."* The agent never guarantees dollar amounts or claims a procedure is covered without a tool call.
- **Confirm before mutating.** The scheduling agent must get explicit patient confirmation (date / time / provider / procedure) before calling `book_appointment`, and never claims success without tool confirmation.
- **Escalation is always available.** The router escalates on explicit request, after two failed clarifications, or on out-of-scope requests. Never remove the escape hatch.
- **Every interaction is observable and scored.** Traces flow to the observability pipeline; the four-rubric evaluation runs at 100% sampling. Don't ship a path that bypasses tracing or evaluation.
- **Multi-tenancy is by `tenant_id` partition key.** All DynamoDB access and all tool calls are tenant-scoped (via the `X-Tenant-ID` header). Never allow cross-tenant reads.
- **IAM is least-privilege.** The `DentalFrontDeskAgentCoreRuntime` role grants only `bedrock:InvokeModel`, `InvokeModelWithResponseStream`, and `ApplyGuardrail`.

## Defaults

- **Agent model:** `us.anthropic.claude-sonnet-4-5-20250514` (router + both specialists). Region `us-east-1`.
- **Evaluation model:** Claude Haiku (`anthropic.claude-3-haiku-20240307-v1:0`) in `evaluator.py` — a cheaper judge for the per-interaction scoring pass.
- **Runtime:** Bedrock AgentCore Runtime, entrypoint `POST /invocations`, health `GET /ping`.
- **Naming:** `dental-front-desk-agent_router_agent` (agent), `dental-frontdesk-foundation` / `dental-frontdesk-pipelines` / `dental-frontdesk-dashboard` (stacks), `DentalFrontDesk-*` (DynamoDB tables). Rename per deployment.
- **Data:** DynamoDB `PAY_PER_REQUEST`, multi-tenant by `tenant_id`.

## Things to confirm before customizing

- Which real systems back scheduling/PMS and insurance eligibility, and what are your API shapes (to repoint the specialist tools)?
- What are the practice's policies — cancellation window, booking horizon, walk-in rules, accepted plans — and do they vary per location?
- What does "good" look like for HIPAA-safe language and empathy, and where should the four rubric alert thresholds sit?
- Is the Bedrock Guardrail configured with your denied topics and grounding source?
- Single practice, multi-location DSO, or a platform vendor embedding across many practices? (Drives the multi-tenant seed strategy.)
- What's the production hardening plan — auth in front of the dashboard/agent, encryption, retention, and the formal HIPAA review?

## When to pause and reassess mid-build

- You want the agent to give clinical/medical advice or guarantee treatment outcomes (out of scope — escalate).
- You expect day-one HIPAA certification (the reference is demo-posture on synthetic data — needs hardening first).
- There's no structured practice data and no willingness to integrate a real scheduling/PMS or insurance source (the kit ships mocks as stand-ins).
- You want fully autonomous handling of escalations, billing disputes, or complaints (human-in-the-loop is by design).
- Bedrock model access for Claude Sonnet 4.5 (or the Haiku judge) isn't enabled in your account/region.

## Done definition

- Router classifies intent and delegates to Scheduling / Insurance specialists or answers general questions, with a working `escalate_to_human` path.
- Specialist tools call real (or mock) scheduling/insurance services, tenant-scoped by `X-Tenant-ID`; scheduling confirms before booking; insurance always includes the disclaimer.
- The Guardrail is attached and denies clinical/PHI topics; hallucination events land in the observability pipeline.
- Every interaction is traced (OTEL → `DentalFrontDesk-Traces`), hourly metrics aggregate (`DentalFrontDesk-Metrics`), and the four-rubric evaluation scores it (`DentalFrontDesk-Evaluations`) with threshold alerts (`DentalFrontDesk-Alerts`).
- The Practice Manager dashboard renders metrics, transcripts, scores, trends, and alert acknowledge/resolve, scoped per tenant.
- Acceptance tests in [`build-spec/acceptance-tests.md`](build-spec/acceptance-tests.md) pass against the seeded demo practices.
- Deployed to your account on AgentCore Runtime with the least-privilege `DentalFrontDeskAgentCoreRuntime` role; `GET /ping` returns healthy.

## Repository convention

This kit folder is **catalog metadata and the build contract**, not the agent's source code. Do NOT add agent code under this folder — build the implementation in its own repository in your own account.
