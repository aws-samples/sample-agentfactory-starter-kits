# Architecture Decisions — BriefMe Sales Brief Generator

> Audience: a coding agent that might be tempted to deviate. These are distilled from the source's `aidlc-docs/` (requirements, application-design, construction-design, audit log) plus kit-level packaging decisions. Don't reverse them without checking with your build lead.

## AD1 — Single orchestrating agent, not a pipeline
**Decision:** One Strands agent with a single `web_research` tool decides which topics to research and synthesizes the brief, rather than decomposing into multiple agents.
**Why:** The task is bounded — research a handful of fixed topics about one company and synthesize them. A single agent with a grounding tool is the simplest thing that works and is the cheapest to run and reason about.
**Alternatives considered:** A multi-agent pipeline (one agent per section) — rejected as unnecessary complexity for a bounded research task.
**What this means for the build:** Keep it one agent; add topics via the prompt, not new agents.

## AD2 — Web Grounding via the Converse `systemTool` on Nova Premier
**Decision:** Web search is the Nova **Web Grounding** (`nova_grounding`) system tool, invoked through the Bedrock **Converse** API `toolConfig`, wrapped in a Strands `@tool` named `web_research`.
**Why:** Web Grounding is a Nova *systemTool* available only on Nova Premier in US regions; wrapping it as a Strands tool keeps the agent loop clean (agent picks topics → calls the tool → synthesizes) and lets citations be captured per call.
**What this means for the build:** Don't substitute a generic search API; the grounding tool is what produces verifiable citations. Keep the citation-capture in `web_research`.

## AD3 — Citations are a first-class, persisted output
**Decision:** Every source URL/domain returned by grounding is accumulated and appended to the brief as `citations[]`, then rendered on a Sources slide.
**Why:** The product's trust model is "cited, verifiable research." A brief without sources is just a summary the rep can't check.
**What this means for the build:** Never strip citation handling; reset and accumulate citations per request (`_citations`).

## AD4 — Model: Nova Premier via cross-region inference profile
**Decision:** `us.amazon.nova-premier-v1:0` (the cross-region inference profile), set via the `BRIEFME_MODEL_ID` env var on the runtime.
**Why:** Web Grounding requires Nova Premier in US regions and the inference-profile id; the model and the grounding capability are coupled.
**What this means for the build:** Don't hardcode a bare foundation-model id or pick a model/region that can't ground.

## AD5 — AgentCore direct code deployment (no container)
**Decision:** Deploy the agent to AgentCore Runtime via `AgentRuntimeArtifact.fromCodeAsset` using the `BedrockAgentCoreApp` SDK wrapper + a `main.py` `@app.entrypoint` — no Dockerfile, no ECR.
**Why:** The source started with a FastAPI + Docker build, then switched mid-build (audit log, 2026-06-12) once the CDK `aws-bedrockagentcore` construct's direct-code path was confirmed. It removes the container build/push step entirely; CDK packages the Python and AgentCore builds the arm64 environment.
**Alternatives considered:** FastAPI server in a container on ECR (the original approach) — dropped to simplify deployment to a single `cdk deploy`.
**What this means for the build:** Keep the `BedrockAgentCoreApp` entrypoint and `fromCodeAsset`; don't reintroduce Docker unless you specifically need it.

## AD6 — Deterministic JSON extraction + graceful fallback
**Decision:** The agent's text output is parsed with `_extract_json` (strip fences, then regex-extract an object); if parsing fails, return a fallback brief (raw text as overview, empty lists).
**Why:** LLMs occasionally wrap or pad JSON. The API must always return a renderable brief rather than 500 on a slightly-off response.
**What this means for the build:** Keep the extraction guard + fallback; the renderer must tolerate empty sections.

## AD7 — Two Lambdas behind an HTTP API with a Cognito JWT authorizer
**Decision:** `generate_brief` (POST /briefs) and `get_briefs` (GET /briefs, GET /briefs/{id}/html) sit behind an API Gateway **HTTP API** with a Cognito JWT authorizer.
**Why:** HTTP API is the cheap, simple serverless front door; the JWT authorizer reuses the Cognito user pool so every route is authenticated with no custom auth code.
**What this means for the build:** Keep all routes authorized; `generate_brief` runs at 512 MB / 120 s (it waits on the agent), `get_briefs` at 256 MB / 10 s.

## AD8 — Persistence split: DynamoDB metadata + S3 HTML
**Decision:** Brief metadata lives in DynamoDB (`briefId` PK + `companyName-createdAt` GSI); the rendered HTML lives in a private S3 bucket keyed `briefs/{companySlug}/{briefId}.html`.
**Why:** DynamoDB gives cheap, fast company-scoped lookups (newest-first via the GSI); S3 is the right place for the larger HTML payload. On-demand billing means no idle cost.
**What this means for the build:** Keep `companyNameLower` for case-insensitive GSI queries; don't put HTML in DynamoDB.

## AD9 — Self-contained HTML slideshow rendered server-side
**Decision:** `html_renderer.py` emits one self-contained HTML page (inline CSS + JS, no external assets) with one slide per section and a Sources slide.
**Why:** A self-contained page stores cleanly in S3, renders anywhere with no build step, and is trivial to brand. The frontend just displays it.
**What this means for the build:** Keep rendering server-side and self-contained; customize slides/branding in `html_renderer.py`.

## AD10 — Static SPA on CloudFront + S3 with OAC; config injected at deploy
**Decision:** The vanilla-JS SPA is hosted in a private S3 bucket served only via CloudFront (OAC); `config.js` (API + Cognito endpoints) is generated by the CDK stack at deploy time.
**Why:** No build pipeline, no public bucket, and the frontend always points at the freshly-deployed endpoints.
**What this means for the build:** Don't hardcode endpoints in the frontend; let the stack inject `config.js`.

## AD11 — Research only, no autonomous action
**Decision:** BriefMe produces a brief for a human to read; it sends no email, schedules nothing, and writes to no CRM.
**Why:** Keeps the trust/compliance surface small and adoption simple — it's decision-support, not automation.
**What this means for the build:** Don't wire the brief to any outbound action without explicit sign-off.

## AD12 — Single-stack, single-tenant CDK
**Decision:** The whole system is one `BriefMeStack` (TypeScript CDK), deployed once per organization into your own account/region.
**Why:** One deployable unit, one trust boundary, simplest possible operations for a demo-to-pilot accelerator.
**What this means for the build:** Keep it single-stack; rename `briefme-*` resources per deployment.
