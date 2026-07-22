# AGENTS.md — BriefMe Sales Brief Generator

> **Audience: a coding agent** (Kiro / Claude Code / etc.) re-implementing or customizing this kit for your organization.

## What this is

- A **single-agent company-research app** that turns a company name into a cited, structured sales brief rendered as an HTML slideshow.
- **One Strands SDK agent** on **Amazon Nova Premier** (`us.amazon.nova-premier-v1:0`), with a single `web_research` tool that wraps the Nova **Web Grounding** (`nova_grounding`) system tool via the Bedrock **Converse** API. The orchestrating agent decides which topics to research, calls the tool per topic, and synthesizes one structured JSON brief.
- The agent is deployed to **AgentCore Runtime via direct code deployment** — no Dockerfile, no ECR. The `BedrockAgentCoreApp` wrapper provides the `/invocations` + `/ping` server; CDK's `AgentRuntimeArtifact.fromCodeAsset` packages the Python and builds the arm64 environment.
- Delivery surface: a **vanilla-JS SPA** (CloudFront + S3) behind **Cognito Hosted UI**, calling two **Python Lambdas** through an **HTTP API** with a **Cognito JWT authorizer**. `generate_brief` invokes the runtime, renders HTML, and persists; `get_briefs` lists by company and fetches stored HTML.
- Persistence: **DynamoDB** (brief metadata + a `companyName-createdAt` GSI) and a private **S3** bucket (rendered HTML).
- Citations from Web Grounding are captured per brief and rendered on a Sources slide — that traceability is the point.

## Where to read first (in your implementation)

1. `README.md` — the app's purpose, the four units, the end-to-end flow.
2. `briefme-agent/agent.py` — the agent itself: `SYSTEM_PROMPT`, the `web_research` tool, citation capture, JSON extraction + fallback. **The prompt and the brief schema are the capability definition.**
3. `briefme-agent/main.py` — the `BedrockAgentCoreApp` `@app.entrypoint`; the invocation payload contract (`company_name`, `website_url`).
4. `briefme-api/generate_brief.py` — invokes the runtime (`bedrock-agentcore.invoke_agent_runtime`), renders HTML, writes S3 + DynamoDB.
5. `briefme-api/html_renderer.py` — the self-contained slideshow renderer (slides, inline CSS/JS, Sources slide).
6. `briefme-api/get_briefs.py` — list-by-company (GSI query) + fetch-HTML routes.
7. `briefme-infra/lib/briefme-stack.ts` — the whole stack: S3, CloudFront, Cognito, DynamoDB, Lambdas, HTTP API + authorizer, the AgentCore Runtime construct, and the scoped Bedrock IAM grants.
8. `aidlc-docs/construction/construction-design.md` — the consolidated design blueprint (agent grounding approach, API contracts, data model, NFRs, infra map).

## Re-deploying for another tenant

1. **Rewrite the research scope** — edit `SYSTEM_PROMPT` and the per-topic queries in `briefme-agent/agent.py` for your selling motion (what a brief should cover).
2. **Adjust the brief schema** — change the JSON contract in `SYSTEM_PROMPT` (and the matching fields in `html_renderer.py`) to add/remove sections.
3. **Rebrand the slideshow** — edit `briefme-api/html_renderer.py` (inline CSS, slide order, fields shown).
4. **Set the model + auth** — `BRIEFME_MODEL_ID` env var and the Bedrock IAM grants in `briefme-infra/lib/briefme-stack.ts`; tune Cognito (self-signup, allowed email domains, callback URLs) to your identity policy.
5. **Deploy** — `cd briefme-infra && npm install && npx cdk bootstrap && npx cdk deploy`. CDK packages the agent and Lambda code, generates `config.js` with live endpoints, and uploads the frontend. No container build.

## What you're NOT building

- **Not an action-taking agent.** It produces a brief; it does not send email, update CRM, or take any outbound action. Don't add write actions without explicit sign-off.
- **Not a private-data RAG system.** It researches the **public web** via Nova Web Grounding. Grounding the brief in your CRM/data room is a different (larger) build — flag it.
- **Not a multi-agent pipeline.** One orchestrating agent with one research tool. Don't over-decompose it.
- **Not a copy of the source into the kit folder.** The kit holds metadata + specs; the implementation is built from this spec in your own repository.

## Non-negotiables

- **Every brief must carry citations.** Web Grounding returns source URLs; capture them (`_citations`) and render the Sources slide. A brief without sources defeats the purpose — never strip citation handling.
- **The final agent output must be a single valid JSON object** matching the brief schema. Keep the `_extract_json` guard + the graceful fallback that returns a renderable brief even if parsing fails — the API must never 500 on a slightly-off model response.
- **Web Grounding is a Nova system tool on Nova Premier in US regions.** It is invoked through the Converse API `toolConfig` (`{"systemTool": {"name": "nova_grounding"}}`), only with the `us.amazon.nova-premier-v1:0` inference profile. Don't swap to a model/region that can't ground.
- **AgentCore direct code deployment, not containers.** Keep the `BedrockAgentCoreApp` entrypoint + `fromCodeAsset` path. Don't reintroduce a Dockerfile/ECR unless you specifically need it.
- **The API is authenticated.** Every route sits behind the Cognito JWT authorizer. Don't expose `generate_brief` unauthenticated.
- **IAM is least-privilege:** the agent role grants only `bedrock:InvokeModel[WithResponseStream]` on the Nova Premier model + inference profile and `bedrock:InvokeTool` on `nova_grounding`. Don't widen it.

## Defaults

- **Model:** `us.amazon.nova-premier-v1:0` (Nova Premier cross-region inference profile). **Region:** `us-east-1` (Web Grounding + Nova Premier availability).
- **Runtime:** AgentCore Runtime `briefme_agent`, Python 3.12, entrypoint `main.py`.
- **Lambdas:** `generate_brief` (512 MB, 120 s timeout — it waits on the agent), `get_briefs` (256 MB, 10 s). Python 3.12.
- **Naming:** `BriefMeStack`, `briefme-*` resources, Cognito Hosted UI prefix `briefme-<account>`. Rename per deployment.

## Things to confirm before customizing

- What does a "good brief" cover for this your motion — which sections, what tone, what talking-point style?
- What's the identity policy — open self-signup, domain-restricted, or federate to your IdP instead of standalone Cognito?
- Are Nova Premier and Web Grounding enabled in your target region/account?
- Does you need briefs grounded in private/internal data (out of scope here — escalate)?
- What retention/PII posture is needed for stored briefs (the reference keeps HTML in S3 + metadata in DynamoDB indefinitely)?

## When to pause and flag for review mid-build

- You want the agent to take actions (send outreach, write to CRM) — out of scope; escalate.
- You need private-data grounding (RAG over internal docs) rather than public-web research.
- Nova Premier / Web Grounding isn't available in your required region.
- Your identity requirements exceed standalone Cognito (e.g., must federate to corporate SSO).
- Compliance requires data-residency, retention, or PII handling beyond the reference's defaults.

## Done definition

- A signed-in user can submit a company name and receive a rendered HTML slideshow brief with overview, products, recent news, talking points, stakeholders, and a Sources slide of real citations.
- The agent runs on AgentCore Runtime (Nova Premier) and uses the `web_research` / `nova_grounding` tool for every brief.
- A malformed model response still yields a renderable brief (fallback), not a 500.
- Briefs persist to S3 + DynamoDB and are retrievable by company via `get_briefs`.
- All API routes require a valid Cognito JWT; the agent IAM role is least-privilege.
- Acceptance tests in [`build-spec/acceptance-tests.md`](build-spec/acceptance-tests.md) pass; `cdk deploy` stands up the stack in your account.
