# Requirements — Agentic Insurance Advisor

> Audience: a coding agent implementing or customizing the kit.

## Functional requirements

**FR1 — Supervisor-orchestrated multi-agent advisory.** The system shall, given a client profile and advisory type, run a Bedrock supervisor agent (`agentCollaboration: SUPERVISOR_ROUTER`) that delegates to three specialists **in sequence** — Product Retrieval → Suitability Analysis → Recommendation Letter — passing full client context to each and returning your output verbatim in one consolidated package. *Maps to: T1, T2.*

**FR2 — Grounded product retrieval.** The Product Retrieval agent shall use RAG over a Bedrock Knowledge Base of carrier product documents and return 3–5 ranked products with carrier/product name, coverage type, premium, key features, eligibility, a match rationale, and **source citations**. It shall recommend only products present in the indexed catalog whose eligibility the client meets. *Maps to: T3.*

**FR3 — Rule-based suitability scoring.** The Suitability agent shall load the rules via the `load_suitability_rules` action and evaluate **every** retrieved product against all eight rules (SUIT-01…SUIT-08), returning a per-rule pass/fail with reasoning and the cited rule ID, plus an overall verdict. *Maps to: T4, T5.*

**FR4 — Deterministic verdict logic.** The overall verdict shall follow fixed logic: if **any** rule returns UNSUITABLE → **UNSUITABLE**; if all rules pass → **SUITABLE**; if some return CONDITIONAL and none UNSUITABLE → **CONDITIONAL**. *Maps to: T5.*

**FR5 — Externalized suitability rules.** The eight rules, your criteria, and `verdict_if_violated` shall live in `data/rules/suitability-rules.yaml` in S3 and be loaded at runtime by the action-group Lambda — you shall be able to change a rule or threshold (e.g. the 10%-of-income affordability ceiling) without a code change. *Maps to: T6.*

**FR6 — Compliant recommendation letter.** The Recommendation agent shall generate a markdown letter written to the client containing: header, client summary, products considered, recommendation + rationale, suitability justification, the **mandatory disclosure block**, and next steps. The disclosure block shall appear on every letter. *Maps to: T7, T8.*

**FR7 — Async job API.** The REST API shall create an advisory job and return **`202 + jobId`** immediately, run the supervisor asynchronously (self-invoke via `InvocationType=Event` → `invoke_agent`), and expose job status and the consolidated result via separate endpoints. *Maps to: T9, T10.*

**FR8 — Job progress tracking.** The action-group Lambda shall write job status transitions (`retrieval_complete` → `analysis_complete` → `complete`) and partial results to the `advisory-jobs` DynamoDB row as each stage finishes. *Maps to: T10, T11.*

**FR9 — Partial-results on failure.** If a sub-agent fails or times out, the supervisor shall report the failure and return whatever partial results are available rather than failing the whole package. *Maps to: T12.*

**FR10 — Producer UI.** The React SPA shall let a producer select a client, pick an advisory type, track progress, view results across Products / Suitability / Letter / Full Package tabs, and export the letter as markdown. *Maps to: T13.*

## Non-functional requirements

**NFR1 — Latency / async UX.** A full four-agent advisory takes ~1–3 minutes; the API shall be async so the producer is never blocked. The SPA polls job status. Model mix (Sonnet 4.5 reasoning vs. Nova 2 Lite/Nova Pro) is the latency lever. *Maps to: T9, T14.*

**NFR2 — Auditability.** Every suitability verdict shall be decomposable into per-rule pass/fail with cited rule IDs; the job row shall retain retrieved products (with citations), the suitability assessment, and the letter. *Maps to: T5, T11.*

**NFR3 — Security / least privilege.** The system shall be single-tenant in your account. The Bedrock agent role shall scope `bedrock:InvokeModel` to the specific model ARNs in use; the KB role to the product bucket + OpenSearch collection; the action role to the rules bucket (read) and jobs table (update). Production deployments shall place authentication in front of the API. *Maps to: T15.*

**NFR4 — Cost predictability.** Cost shall scale with advisory volume (Bedrock tokens) plus the fixed OpenSearch Serverless OCU floor; the floor dominates at low volume and must be validated per deployment. *Maps to: T16.*

**NFR5 — Grounding.** Product recommendations shall be grounded in the Knowledge Base with citations; the agent shall not invent products or eligibility. *Maps to: T3.*

**NFR6 — Single-tenancy.** One deployment per organization in your own account/region; no shared multi-tenant store. *Maps to: T15.*

## Out of scope

- Autonomous, bind-able recommendations (the output is a producer-reviewed draft).
- Authentication/authorization layer (reference API Gateway is open; must be added for production).
- CRM / policy-admin integration (client profiles are seeded into DynamoDB).
- Live rate-quoting / illustration engine (premiums come from indexed documents).
- Model fine-tuning or custom inference hosting (use Bedrock via inference profiles).
- Fully CloudFormation-managed agent creation (multi-agent collaboration setup is script/console-assisted).

## Dependencies

- Bedrock model access in the target region (`us-east-1` default), via inference profiles: Claude Sonnet 4.5, Nova 2 Lite, Nova Pro, Titan Text v2 (embeddings).
- Bedrock multi-agent collaboration available in the account/region.
- AWS account with permissions to create S3, DynamoDB, OpenSearch Serverless, Lambda, API Gateway, CloudFront, IAM, and Bedrock Agents/Knowledge Bases.
- AWS CLI v2 configured; Node.js 18+ and Python 3.12+ for the frontend build and Lambda packaging.
- A structured client-profile dataset and an indexable carrier product catalog.
