# Requirements — BriefMe Sales Brief Generator

> Audience: a coding agent implementing or customizing the kit.

## Functional requirements

**FR1 — Company-research input.** The system shall let an authenticated user submit a company name (required) and an optional website URL from the web frontend.
Input is collected by the SPA and sent to `POST /briefs` with a Cognito Bearer token. *Maps to: T1, T2.*

**FR2 — Agent-powered cited research.** On submission, a Lambda shall invoke the AgentCore-hosted Strands agent, which uses Amazon Nova Premier with the Nova Web Grounding (`nova_grounding`) system tool to research the company across overview, products/services, recent news, and key stakeholders.
The agent runs a separate grounded `web_research` call per topic and captures source citations. *Maps to: T3, T4.*

**FR3 — Structured brief synthesis.** The agent shall return a single valid JSON object with `company_name`, `overview`, `products_services[]`, `recent_news[]`, `talking_points[]`, `stakeholders[]`, and an appended `citations[]` list.
A malformed model response shall be recovered where possible and otherwise fall back to a renderable brief — the pipeline must not hard-fail. *Maps to: T4, T5.*

**FR4 — HTML slideshow output.** The backend shall render the structured brief into a single self-contained HTML slideshow (inline CSS/JS, no external deps) with one slide per section and a Sources slide built from citations, navigable via Prev/Next and arrow keys. *Maps to: T6.*

**FR5 — Brief persistence + retrieval.** Each generated brief's HTML shall be stored in a private S3 bucket and its metadata in DynamoDB (keyed by `briefId`, with a `companyName-createdAt` GSI). Users shall be able to list briefs by company (newest first) and re-open a stored brief's HTML. *Maps to: T7, T8.*

**FR6 — Authentication.** The app shall require login via Amazon Cognito; every API route shall sit behind a Cognito JWT authorizer so only authenticated users can generate or read briefs. *Maps to: T9.*

**FR7 — Static frontend hosting.** The SPA shall be hosted in a private S3 bucket served only via CloudFront (OAC), with deploy-time-generated runtime config (`config.js`) carrying the live API and Cognito endpoints. *Maps to: T10.*

## Non-functional requirements

**NFR1 — Latency.** A brief shall be generated within an interactive budget; the `generate_brief` Lambda has a 120 s timeout to cover the multi-topic agent run. The frontend loads quickly via CloudFront.

**NFR2 — Resilience.** A malformed or partial model response shall still produce a renderable brief (fallback). Agent/render/persistence failures shall return structured error responses (`502`/`500`), never silent failures.

**NFR3 — Security.** Single-tenant in your account. S3 buckets are private (no public access); the frontend is served only via CloudFront OAC. The agent IAM role shall grant only `bedrock:InvokeModel[WithResponseStream]` on the Nova Premier model + inference profile and `bedrock:InvokeTool` on `nova_grounding`. Data in transit over HTTPS.

**NFR4 — Cost predictability.** Cost scales with Nova Premier usage per brief (research + synthesis calls). DynamoDB is on-demand, Lambda is pay-per-invoke, and there is no idle compute except the managed AgentCore Runtime.

**NFR5 — Infrastructure as code.** All resources shall be provisioned by a single AWS CDK (TypeScript) stack; one `cdk deploy` stands up agent, API, frontend, auth, and storage with no separate container build.

**NFR6 — Traceability.** Every brief shall carry source citations from Web Grounding, rendered on a Sources slide, so claims are verifiable against your sources.

**NFR7 — Single-tenancy.** One deployment per organization in your own account/region; no shared multi-tenant store.

## Out of scope

- Outbound actions (sending emails, scheduling, writing to CRM) — the kit produces a brief only.
- Private-data / internal-document grounding (RAG) — research is public-web only.
- Real-time streaming of agent output to the UI (batch response only).
- PDF export, mobile app, and an admin portal for user management.
- Multi-tenancy / cross-account brief sharing.

## Dependencies

- Amazon Nova Premier and Web Grounding enabled in your region (US region; `us-east-1` default), via the `us.amazon.nova-premier-v1:0` inference profile.
- AWS account with permissions to create AgentCore Runtime, Lambda, API Gateway (HTTP API), DynamoDB, S3, CloudFront, Cognito, and IAM roles.
- Node.js 18+, npm, and AWS CDK v2; CDK bootstrap in the target account/region.
- AWS credentials configured. Docker is **not** required (AgentCore direct code deployment).
