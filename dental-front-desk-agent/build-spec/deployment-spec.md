# Deployment Spec — Dental Front-Desk Agent

> Audience: a coding agent provisioning resources in your account, and whoever verifies before bumping `kit.json.status` to `published`.

## Deployment context

- **Account:** your own AWS account (single-tenant deployment, multi-tenant by practice within it).
- **Region:** `us-east-1` by default (where AgentCore Runtime + Claude tiers were verified). Confirm Bedrock model access and AgentCore Runtime availability in the chosen region.
- **Trust boundary:** everything runs in your account; the only outbound dependency is in-region Bedrock model invocation. (Production note: the reference has no auth in front of the dashboard/agent — add it.)
- **Source code location:** built from this kit's spec in your own repository. The kit folder holds metadata + specs only; no source is included.
- **Delivery unit:** four CloudFormation stacks + an AgentCore Runtime agent.

## Deploy sequence

| Step | Artifact | What it creates |
|---|---|---|
| 1 | `infrastructure/unit-1-foundation.yaml` (`dental-frontdesk-foundation`) | Foundation DynamoDB tables, mock-service Lambdas, REST API Gateway, EventBridge daily reminder rule |
| 2 | `infrastructure/unit-2-agents.yaml` (`dental-frontdesk-agents`) | Agent gateway wiring (Lambda + API Gateway) to the mock services |
| 3 | `infrastructure/unit-3-pipelines.yaml` (`dental-frontdesk-pipelines`) | Observability + evaluation DynamoDB tables and the trace-processor / evaluator Lambdas |
| 4 | `infrastructure/unit-4-dashboard.yaml` (`dental-frontdesk-dashboard`) | AppSync GraphQL API, resolver Lambda, S3 + CloudFront for the React SPA |
| 5 | `scripts/deploy-agent-boto3.py` | Packages the router agent, creates the `DentalFrontDeskAgentCoreRuntime` role, deploys to AgentCore Runtime via `bedrock-agentcore-control` |
| 6 | `scripts/seed-observability-data.py` | Seeds demo telemetry; `run-test-conversations.py` runs scored test conversations |

## Resources to create

- **Agent runtime:** Bedrock AgentCore Runtime agent (`dental-front-desk-agent_router_agent`), entrypoint `POST /invocations`, health `GET /ping`.
- **AI/model:** Bedrock model access — Claude Sonnet 4.5 (agents) and Claude Haiku (evaluation judge); a Bedrock Guardrail (grounding/hallucination) — access must be enabled, Guardrail must be created and its `GUARDRAIL_ID` wired in.
- **Compute:** Lambda functions — mock services (scheduling, insurance, reminders, practice-config, patients), trace processor, evaluator, dashboard GraphQL resolver.
- **Data:** DynamoDB tables (`PAY_PER_REQUEST`, multi-tenant by `tenant_id`) — foundation tables plus `DentalFrontDesk-Traces`, `DentalFrontDesk-Metrics`, `DentalFrontDesk-Evaluations`, `DentalFrontDesk-Alerts`.
- **APIs:** API Gateway (REST, for mock services), AppSync (GraphQL, for the dashboard).
- **Frontend:** S3 bucket + CloudFront distribution hosting the React/Vite/Tailwind SPA.
- **Events:** EventBridge daily rule for post-procedure reminder processing.
- **Identity:** `DentalFrontDeskAgentCoreRuntime` role (Bedrock `InvokeModel` / `InvokeModelWithResponseStream` / `ApplyGuardrail` only) plus least-privilege Lambda execution roles.
- **Observability:** CloudWatch (OTEL spans via GenAI Observability, logs, metrics).

## What you configure during the build

| Config item | Format | Source |
|---|---|---|
| Agent system prompts | Python string constants | `packages/{router,scheduling,insurance}-agent/src/prompts.py` |
| Specialist tool endpoints | HTTP calls (`MOCK_SERVICES_API_URL`) | `packages/{scheduling,insurance}-agent/src/tools.py` |
| Per-practice config (hours, policies, accepted plans, providers) | DynamoDB items keyed by `tenant_id` | `infrastructure/unit-1-foundation.yaml` tables (seeded) |
| Mock services / real integrations | Python services | `packages/mock-services/` |
| Evaluation rubrics + weights | `RubricConfig` constants | `packages/evaluations/src/rubrics.py` |
| Alert thresholds + window | `AlertConfig` constants | `packages/evaluations/src/alerts.py` |
| Guardrail | `GUARDRAIL_ID` / `GUARDRAIL_VERSION` env | Bedrock Guardrails console + agent env |
| Dashboard branding / queries | React + GraphQL | `packages/dashboard-ui/`, `packages/dashboard-api/` |
| Region / account / naming | Env + script vars | `scripts/deploy-agent-boto3.py`, stack params |

## What's pre-built

- The router + Scheduling + Insurance agent pattern on Strands + AgentCore Runtime, with all tools.
- Mock scheduling / insurance / reminders / practice-config / patient services and 5 seeded demo practices.
- The four CloudFormation stacks and the AgentCore Runtime deploy script.
- The observability pipeline (OTEL processing, hourly P50/P95/P99 + token aggregation, hallucination tracking).
- The four-rubric LLM-as-a-judge evaluation pipeline with weighted composite and threshold alerting.
- The Practice Manager dashboard (React + AppSync GraphQL): metrics, transcripts, scores, trends, alert acknowledge/resolve.
- Mock-services pytest suites and the `run-test-conversations.py` scored-conversation harness.

## Cost expectations

| Driver | Scales with | Notes |
|---|---|---|
| Bedrock — Claude Sonnet 4.5 | Conversations × turns | Agent reasoning; multi-turn bookings cost more |
| Bedrock — Claude Haiku (judge) | Interactions (100% sampling, tunable) | Cheaper model by design |
| Bedrock Guardrails | Turns | `ApplyGuardrail` per turn |
| AgentCore Runtime | Active conversation minutes | Session/compute time |
| Lambda + DynamoDB (`PAY_PER_REQUEST`) | Invocation / read-write volume | Mock services, pipelines, resolvers, telemetry |
| AppSync + CloudFront + S3 | Practice-manager usage | Low (dashboard traffic) |
| CloudWatch / EventBridge | Trace volume + daily trigger | Low |

## Pre-deployment checklist

- [ ] Bedrock access enabled for Claude Sonnet 4.5 and Claude Haiku in the target region.
- [ ] AgentCore Runtime available in the region; a Bedrock Guardrail created (denied topics + grounding source).
- [ ] AWS CLI v2 configured with permissions for DynamoDB, Lambda, API Gateway, AppSync, S3, CloudFront, EventBridge, IAM.
- [ ] Agent prompts tuned to the practice; HIPAA-safe rules and the insurance disclaimer present.
- [ ] Specialist tools repointed to real PMS/insurance APIs, or mocks reseeded with your data shape.
- [ ] Per-practice config seeded per `tenant_id`; rubric weights and alert thresholds reviewed.

## Post-deployment validation

- [ ] `GET /ping` on the AgentCore Runtime agent returns healthy.
- [ ] A routine booking, a reschedule, an eligibility check, and a coverage question all complete; the coverage answer includes the disclaimer.
- [ ] An explicit "talk to a person" triggers `escalate_to_human`; an attempt to elicit clinical advice is refused.
- [ ] An interaction appears in `DentalFrontDesk-Traces`, aggregates into `DentalFrontDesk-Metrics`, and is scored into `DentalFrontDesk-Evaluations`.
- [ ] The dashboard renders metrics, transcripts, four rubric scores, trends, and alert acknowledge/resolve, scoped per tenant.
- [ ] The `DentalFrontDeskAgentCoreRuntime` role is confirmed least-privilege (Bedrock invoke + ApplyGuardrail only).
- [ ] Acceptance tests pass against the seeded demo practices.

## Day-2 operations (yours to run)

- Add authentication in front of the dashboard and agent endpoints (the reference has none).
- Complete the production hardening: encryption-at-rest review, data retention/BAA, formal HIPAA review.
- Replace remaining mock services with real PMS / insurance integrations.
- Re-tune prompts, rubrics, and alert thresholds as quality data accrues.
- Manage Bedrock spend via the evaluation sampling rate and tight specialist delegation.
- Set CloudWatch retention/alarms; review the per-practice hallucination rate and alert history.
- Onboard new practices/locations by seeding per-`tenant_id` config.
