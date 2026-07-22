# Acceptance Tests — BriefMe Sales Brief Generator

> For sign-off with your engineering lead. Each test maps to requirements in [`requirements.md`](requirements.md).

## Functional

**T1 — Brief request from the UI.**
- *Setup:* a signed-in user on the deployed SPA.
- *Action:* enter a company name and submit.
- *Expected:* the SPA sends `POST /briefs` with a Bearer token and shows a loading state.
- *Maps to:* FR1.

**T2 — Optional website URL accepted.**
- *Setup:* signed-in user.
- *Action:* submit a company name plus a website URL.
- *Expected:* the URL is passed through to the agent and used to focus research; brief still generates.
- *Maps to:* FR1.

**T3 — Agent performs grounded web research.**
- *Setup:* a well-known public company.
- *Action:* generate a brief.
- *Expected:* the agent invokes the `web_research` / `nova_grounding` tool for the research topics; the resulting brief carries non-empty `citations`.
- *Maps to:* FR2, NFR6.

**T4 — Structured brief schema returned.**
- *Setup:* any company.
- *Action:* inspect the agent's returned object.
- *Expected:* valid JSON with `company_name`, `overview`, `products_services[]`, `recent_news[]`, `talking_points[]`, `stakeholders[]`, and `citations[]`.
- *Maps to:* FR2, FR3.

**T5 — Graceful fallback on malformed model output.**
- *Setup:* force the model to return non-JSON (or simulate it).
- *Action:* generate a brief.
- *Expected:* `_extract_json` recovers an embedded object if present; otherwise a fallback brief renders (overview = raw text, empty lists). No 500 from a parse failure.
- *Maps to:* FR3, NFR2.

**T6 — HTML slideshow rendered.**
- *Setup:* a generated brief.
- *Action:* open the returned HTML.
- *Expected:* a self-contained slideshow with one slide per section plus a Sources slide; Prev/Next and arrow-key navigation work; no external asset requests.
- *Maps to:* FR4.

**T7 — Brief persisted to S3 + DynamoDB.**
- *Setup:* generate a brief.
- *Action:* inspect storage.
- *Expected:* HTML object exists at `briefs/{companySlug}/{briefId}.html` in the private bucket; a DynamoDB item exists with `briefId`, `companyName`, `companyNameLower`, `createdAt`, `s3Key`, `summary`.
- *Maps to:* FR5.

**T8 — Retrieve briefs by company + fetch stored HTML.**
- *Setup:* at least one brief for a company.
- *Action:* `GET /briefs?company={name}`, then `GET /briefs/{briefId}/html`.
- *Expected:* the list returns matching briefs newest-first (GSI query); the HTML route returns the stored slideshow as `text/html`.
- *Maps to:* FR5.

## Non-functional

**T9 — All API routes require auth.**
- *Action:* call `POST /briefs` and `GET /briefs` with no/invalid token, then with a valid Cognito JWT.
- *Expected:* unauthenticated calls are rejected by the authorizer; authenticated calls succeed.
- *Maps to:* FR6, NFR3.

**T10 — Frontend served only via CloudFront.**
- *Action:* attempt direct S3 access to the frontend bucket; load the app via the CloudFront URL.
- *Expected:* direct S3 access is blocked (OAC-only); CloudFront serves the SPA with `config.js` carrying live endpoints.
- *Maps to:* FR7, NFR3.

**T11 — Latency within interactive budget.**
- *Action:* generate a brief end-to-end.
- *Expected:* completes within the `generate_brief` 120 s budget; typical runs are well under it.
- *Maps to:* NFR1.

**T12 — Least-privilege agent role.**
- *Action:* inspect the AgentCore Runtime instance role policy.
- *Expected:* only `bedrock:InvokeModel[WithResponseStream]` on the Nova Premier model + inference profile and `bedrock:InvokeTool` on `nova_grounding`. No broader grants.
- *Maps to:* NFR3.

**T13 — Single `cdk deploy` stands up the stack.**
- *Action:* `npx cdk deploy` in a clean account/region.
- *Expected:* the full stack (agent, Lambdas, HTTP API, Cognito, DynamoDB, S3, CloudFront) deploys with no separate container build; outputs are emitted.
- *Maps to:* NFR5.

**T14 — Graceful degradation on sparse coverage.**
- *Setup:* a company with little public footprint.
- *Action:* generate a brief.
- *Expected:* sections return empty lists or brief notes rather than fabricated content; the brief still renders.
- *Maps to:* FR3, NFR2.

## Operational

**T15 — Agent invocation failure returns a clean error.**
- *Setup:* force an agent/runtime failure (e.g., model access disabled).
- *Action:* `POST /briefs`.
- *Expected:* a structured `502` error is returned (not a stack trace); the failure is logged to CloudWatch.
- *Maps to:* NFR2.

**T16 — Citations traceable on the Sources slide.**
- *Setup:* a brief for a well-covered company.
- *Action:* open the Sources slide.
- *Expected:* it lists clickable source links (domain/URL) captured from Web Grounding for the claims in the brief.
- *Maps to:* FR3, NFR6.

## Sign-off

| Role | Name | Date |
|---|---|---|
| Build lead | __________ | ______ |
| Your engineering lead | __________ | ______ |
