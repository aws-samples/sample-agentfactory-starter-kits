# Architecture Decisions — Dental Front-Desk Agent

> Audience: a coding agent that might be tempted to deviate. These distill the design choices baked into the reference implementation source plus kit-level packaging decisions. Don't reverse them without a deliberate review.

## AD1 — Router + specialist agents, not one mega-prompt
**Decision:** A Router agent classifies intent and delegates to dedicated Scheduling and Insurance agents (each its own Strands `Agent` with its own prompt and tools); the router also handles general Q&A and escalation.
**Why:** Each capability needs different tools, different rules (booking confirmation vs. the insurance disclaimer), and independent quality scoring. A single prompt can't be scoped or evaluated per capability, and it makes escalation muddy.
**What this means for the build:** Keep the three agents separate. Add new capabilities as new specialists + router intents, not by overloading one prompt.

## AD2 — Build level: Custom IaC
**Decision:** Ship as four CloudFormation stacks (foundation, agents, pipelines, dashboard) plus an AgentCore Runtime deploy script — you own the whole stack.
**Why:** The value is in the observability + evaluation pipeline and the multi-tenant dashboard, not just prompt + tools. Healthcare buyers (DSOs, platform vendors) want the full audited stack in your own account.
**Why not the others:** *managed-harness* can't carry the eval pipeline, dashboard, and multi-tenant data layer. *managed-agents-openai* is for teams who specifically want OpenAI frontier models on AWS — not the ask here; this kit standardizes on Claude on AgentCore.
**What this means for the build:** Don't collapse the stacks into a harness; the pipelines and dashboard are first-class deliverables.

## AD3 — Claude Sonnet 4.5 for agents; Claude Haiku for the judge
**Decision:** Router and both specialists run on `us.anthropic.claude-sonnet-4-5-20250514`; the evaluation pipeline scores with Claude Haiku (`anthropic.claude-3-haiku-20240307-v1:0`).
**Why:** Sonnet 4.5 balances quality and latency for interactive patient conversation. The judge runs on every interaction at 100% sampling, so a cheaper, fast Haiku model keeps evaluation cost proportionate.
**What this means for the build:** Don't put the expensive model on the judge. Re-tier per deployment latency/cost needs, but keep the judge cheaper than the agents.

## AD4 — HIPAA-safe language enforced in prompts, Guardrail as second line
**Decision:** Every agent prompt encodes HIPAA-safe-language rules (general terms, no unprompted clinical detail, no reading back sensitive info); a Bedrock Guardrail adds grounding/hallucination checks via `ApplyGuardrail`.
**Why:** Prompt rules shape behavior; the Guardrail catches what slips through and produces the hallucination signal the dashboard reports. Two independent layers are stronger than either alone.
**What this means for the build:** Never drop the prompt rules in favor of "the Guardrail will catch it," or vice versa. Both ship.

## AD5 — Mandatory insurance disclaimer + confirm-before-book
**Decision:** Coverage answers always append the verify-with-your-provider disclaimer and never state coverage without a tool call; bookings require explicit patient confirmation before `book_appointment`.
**Why:** These are the two highest-liability front-desk actions. A wrong coverage promise or an unconfirmed booking erodes trust and creates operational mess.
**What this means for the build:** Treat the disclaimer and the confirmation gate as invariants, not stylistic choices.

## AD6 — Decision-support / front-desk only, human escalation always available
**Decision:** The agent does front-desk tasks and escalates anything clinical, dispute-related, or unresolved via `escalate_to_human`.
**Why:** Patient safety and the practice's liability. The agent must never give clinical advice or settle disputes.
**What this means for the build:** Never wire the agent to give clinical answers or auto-resolve complaints. The escape hatch is non-negotiable.

## AD7 — Four equal-weight evaluation rubrics with threshold alerting
**Decision:** Score every interaction on accuracy, HIPAA-safe language, empathy, and policy adherence at 25% each; composite is the weighted mean; alerts fire when a rubric's rolling-window (default 10) average drops below its threshold (defaults: hipaa_safe 80/CRITICAL, accuracy 70/HIGH, policy 70/HIGH, empathy 60/MEDIUM).
**Why:** Front-desk quality is multi-dimensional — a booking can be accurate but cold, or empathetic but leak PHI. Equal weights give a balanced default; per-rubric thresholds let HIPAA be treated more strictly than empathy.
**What this means for the build:** Re-tune weights and thresholds per deployment, but keep HIPAA-safe language the strictest rubric.

## AD8 — Multi-tenancy by DynamoDB partition key
**Decision:** Every table (`DentalFrontDesk-*`) and every tool call is keyed by `tenant_id` (via the `X-Tenant-ID` header); the dashboard is scoped per tenant.
**Why:** One agent pattern must serve many practices for a DSO or platform vendor, with hard data isolation and per-practice config (hours, policies, accepted plans).
**What this means for the build:** Never write a query without the `tenant_id` partition key. Per-practice config is data, not code.

## AD9 — Mock services as deliberate stand-ins
**Decision:** Scheduling, insurance, reminders, practice-config, and patient services ship as Lambda + API Gateway + DynamoDB mocks seeded with synthetic data (5 demo practices).
**Why:** The full agent loop — including booking and eligibility — must demo end-to-end before any real integration exists, and the tool signatures define the integration contract.
**What this means for the build:** **Production must replace the mocks** with your real PMS / insurance APIs (repoint the specialist tools) or reseed with real data. Treat this as a required pre-production step.

## AD10 — AgentCore Runtime deploy via boto3, least-privilege role
**Decision:** Deploy the agent to Bedrock AgentCore Runtime through the `bedrock-agentcore-control` API (`scripts/deploy-agent-boto3.py`), under the `DentalFrontDeskAgentCoreRuntime` role granting only Bedrock invoke + ApplyGuardrail. Runtime contract: `POST /invocations`, health `GET /ping`.
**Why:** AgentCore Runtime provides session management and OTEL observability out of the box; the boto3 path sidesteps CLI/CDK version issues. Least-privilege limits blast radius.
**What this means for the build:** Keep the runtime entrypoint contract and the scoped role; add auth in front for production.

## AD11 — No production auth/encryption/HIPAA in the reference
**Decision:** The reference is a demo/PoC on synthetic data with no auth layer, no encryption review, and no formal HIPAA controls.
**Why:** It's an accelerator to prove the pattern fast, not a certified product.
**What this means for the build:** Before any real PHI, add authentication, encryption-at-rest review, retention/BAA, and a formal HIPAA review. Every one of these is a required pre-production step.
