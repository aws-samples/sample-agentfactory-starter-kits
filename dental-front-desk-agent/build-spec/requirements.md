# Requirements — Dental Front-Desk Agent

> Audience: a coding agent implementing or customizing the kit, and whoever certifies the build.

## Functional requirements

**FR1 — Intent routing.** The Router agent shall classify each inbound patient message into SCHEDULING, INSURANCE, GENERAL, ESCALATE, or UNCLEAR, and either answer general practice questions directly (via `get_practice_info`) or delegate to the correct specialist (`delegate_to_scheduling` / `delegate_to_insurance`). For UNCLEAR it asks a clarifying question; it handles one topic at a time. *Maps to: T1, T2, T3.*

**FR2 — Scheduling.** The Scheduling agent shall find available slots, book, reschedule, cancel, and look up a patient's appointments via its tools against the scheduling service, tenant-scoped by `X-Tenant-ID`. It shall present 2–3 options, ask one question at a time, and obtain explicit patient confirmation (date / time / provider / procedure) **before** calling `book_appointment`, never claiming success without tool confirmation. *Maps to: T4, T5.*

**FR3 — Insurance.** The Insurance agent shall check plan eligibility, coverage for a procedure, and list accepted plans via its tools. Every coverage response shall include the disclaimer *"This is general information. Please verify with your insurance provider for exact coverage details."* and shall never state coverage or dollar amounts without a tool confirmation. Unrecognized plans trigger a re-ask, then an accepted-plans offer, then escalation. *Maps to: T6, T7.*

**FR4 — HIPAA-safe language.** All three agents shall use general terms ("your appointment", not the procedure name unless the patient raised it), shall not volunteer clinical detail, and shall not read back sensitive information unprompted. *Maps to: T8.*

**FR5 — Escalation.** The Router shall call `escalate_to_human` on explicit request, after two failed clarification attempts, or for out-of-scope requests (medical advice, billing disputes, complaints), returning a hand-off message and logging the escalation. *Maps to: T9.*

**FR6 — Guardrail enforcement.** A Bedrock Guardrail shall be applied to agent turns (`bedrock:ApplyGuardrail`) for grounding / hallucination checks; flagged events shall be recorded with the action taken (BLOCKED / WARNED). *Maps to: T10.*

**FR7 — Observability.** Every interaction shall emit OTEL traces (tool calls, latency, tokens, reasoning steps, model id) processed into `DentalFrontDesk-Traces`, with hourly latency (P50/P95/P99) and token aggregation into `DentalFrontDesk-Metrics`, all partitioned by `tenant_id`. *Maps to: T11.*

**FR8 — Evaluation + alerting.** An LLM-as-a-judge pipeline shall score every interaction on four rubrics — accuracy, HIPAA-safe language, empathy, policy adherence (25% weight each) — compute a weighted composite into `DentalFrontDesk-Evaluations`, and raise an alert into `DentalFrontDesk-Alerts` when a rubric's rolling-window average breaches its threshold. *Maps to: T12, T13.*

**FR9 — Practice-manager dashboard.** An AppSync GraphQL API + React dashboard shall expose real-time metrics, paginated interactions with transcripts, evaluation scores, trends, and alert acknowledge/resolve, scoped per tenant. *Maps to: T14.*

**FR10 — Multi-tenancy.** Practice data and all telemetry shall be isolated by `tenant_id` partition key; no cross-tenant reads shall be possible at the DynamoDB level. The reference ships 5 seeded demo practices. *Maps to: T15.*

## Non-functional requirements

**NFR1 — Latency.** A typical single-turn front-desk response shall complete in a timeframe acceptable for interactive patient conversation on Claude Sonnet 4.5; multi-turn bookings accrue per-turn latency. Latency percentiles are aggregated hourly and visible per practice.

**NFR2 — Safety.** Clinical advice, diagnoses, treatment guarantees, and out-of-scope requests shall always be refused and escalated. HIPAA-safe language and the insurance disclaimer are enforced in prompts; the Guardrail is the second line.

**NFR3 — Security.** Single-tenant in your AWS account/region. The `DentalFrontDeskAgentCoreRuntime` role shall grant only `bedrock:InvokeModel`, `InvokeModelWithResponseStream`, and `ApplyGuardrail`. Production deployments shall add authentication in front of the dashboard and agent endpoints and complete encryption/retention/HIPAA review.

**NFR4 — Cost predictability.** Bedrock cost scales with conversation volume × turns plus the per-interaction Haiku evaluation pass; the evaluation sampling rate is tunable to control spend.

**NFR5 — Auditability.** Per-turn provenance (agent used, tools, latency, tokens, model) and per-rubric evaluation evidence shall be retained so any quality score or verdict can be decomposed.

**NFR6 — Multi-tenant isolation.** One deployment serves many practices; isolation is enforced by partition key, not application logic alone.

## Out of scope

- Clinical/medical advice, diagnoses, prescriptions, or treatment-outcome guarantees.
- Autonomous handling of billing disputes, complaints, or escalations without a human.
- Real PMS / insurance / EHR integrations (the reference ships mock services as stand-ins).
- Production authentication/authorization, encryption-at-rest review, retention/BAA, and formal HIPAA certification (must be added before production PHI).
- Voice/telephony transport (the reference operates on text messages; voice front-ends are your integration).
- Model fine-tuning or custom inference hosting (uses Bedrock-hosted Claude).

## Dependencies

- Bedrock model access enabled in your region (`us-east-1` default) for Claude Sonnet 4.5 (agents) and Claude Haiku (evaluation judge).
- Bedrock AgentCore Runtime available in the region, plus a Bedrock Guardrail configured with your denied topics and grounding source.
- AWS account with permissions to create DynamoDB, Lambda, API Gateway, AppSync, S3, CloudFront, EventBridge, CloudWatch, and IAM roles via CloudFormation.
- Structured practice data (providers, schedules, accepted plans, policies) to seed the foundation tables, or real scheduling/insurance APIs to repoint the specialist tools to.
- Python 3.12 + AWS CLI v2; Node for the dashboard build (React/Vite).
