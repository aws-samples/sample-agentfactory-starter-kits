# Requirements — Internal Knowledge Q&A

What the agent must do. Each requirement maps to one or more acceptance tests in [`acceptance-tests.md`](acceptance-tests.md).

## Functional requirements

### FR1 — Retrieval-grounded Q&A
The agent answers natural-language questions from your connected document sources by retrieving relevant chunks from the Knowledge Base and grounding the response in those chunks.

### FR2 — Citation requirement
Every answer that is grounded in retrieved content must include at least one source citation. Citations must include the source document name and a deep link (or document URI) where your identity context can resolve it.

### FR3 — Cite-or-decline contract
When the retrieval doesn't surface relevant chunks, or when the model can't confidently ground its answer, the agent must say "I don't have a documented answer for that — try [escalation path]" instead of fabricating an answer. The system prompt enforces this.

### FR4 — PII redaction on input
Inbound user queries are scanned for PII (emails, phone numbers, SSN-like patterns, account numbers) and redacted before being sent to the model or logged. The original PII is never persisted.

### FR5 — Off-topic refusal
Questions outside the scope of internal documentation (e.g., personal advice, news commentary, current events) are refused with a clear "this isn't what I'm here for" response.

### FR6 — Denied-topics enforcement (vertical-specific)
You can configure a list of denied topics. Configurable examples:
- FinServ: investment advice, client-specific recommendations, regulatory interpretation
- Healthcare: clinical advice, PHI lookup, medication recommendations
- Manufacturing: safety override recommendations, equipment certification claims
- All: legal advice, HR decisions on individuals, decisions affecting compensation

### FR7 — Source attribution
Every response includes the source document name + URI. If multiple sources are cited, list them all. Source URIs must point to the original document in its source system (Confluence page, SharePoint file, S3 object), not a copy.

### FR8 — Audit trail
Every query and response is logged to CloudWatch Logs with: timestamp, user identity (from SSO), question (post-redaction), retrieved chunk IDs, cited document URIs, answer text, and any guardrail interventions.

### FR9 — Channel surfaces
The agent is reachable through at least one of: Slack slash command, web chat embed, Teams app, or internal portal embed. You pick; v1 ships with one surface.

### FR10 — SSO integration
User identity comes from your IdP (Okta, Azure AD, Google Workspace, Cognito). The agent does not maintain its own user accounts.

## Non-functional requirements

### NFR1 — Citation rate
≥ 90% of answers must include at least one citation in production usage. (Exception: explicit decline responses don't need citations.)

### NFR2 — Latency
Median end-to-end latency ≤ 3 seconds; p95 ≤ 8 seconds. Includes retrieval + model invocation + guardrails overhead.

### NFR3 — Availability
99.5% availability target. AgentCore Managed Harness provides the runtime; you are responsible for source-system availability (if Confluence is down, the agent can still answer from cached chunks).

### NFR4 — Security
- Documents stay in your source systems. No copies in the kit's infrastructure.
- All AWS-side data (chunks, embeddings, audit logs) encrypted at rest with customer-managed KMS keys.
- All in-transit traffic uses TLS 1.2+.
- Audit logs retained per your data retention policy.

### NFR5 — Cost predictability
You can predict costs from query volume + corpus size. CloudWatch dashboard exposes per-query cost estimates.

### NFR6 — Single-tenancy
This kit is single-tenant by design. One organization, one corpus, one trust boundary. Multi-tenant deployments are out of scope for v1.

## Out of scope

- Document authoring or editing
- Cross-tenant deployments
- Per-document access control (beyond what the source system enforces)
- Action-taking (write to source systems, send emails, create tickets)
- Voice or image input
- Cross-session memory
- Document quality grading (the agent doesn't tell you a doc is stale; it cites what's there)

## Dependencies

- You have documents in at least one supported source (Confluence, SharePoint, S3, GitHub wiki, Notion, Google Drive, or one connectable via custom connector)
- You have an IdP supporting OIDC or SAML
- Your AWS account has Bedrock model access for the chosen model (Claude 3.5 Sonnet by default)
- Your AWS account is in a region where AgentCore + Knowledge Bases are available
