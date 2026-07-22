# AGENTS.md — Agentic Insurance Advisor

> **Audience: a coding agent** (Kiro / Claude Code / etc.) re-implementing or customizing this kit for your organization.

## What this is

- A **multi-agent insurance advisory system** built on **Amazon Bedrock multi-agent collaboration**.
- A **supervisor agent** (`agentCollaboration: SUPERVISOR_ROUTER`) orchestrates three specialists **in sequence**: Product Retrieval → Suitability Analysis → Recommendation Letter, then returns the consolidated package.
- **Product Retrieval** runs **RAG** over a **Bedrock Knowledge Base** of carrier product documents (vector store: **OpenSearch Serverless**; embeddings: **Titan Text v2**).
- **Suitability Analysis** calls an **action-group Lambda** that loads eight rules (SUIT-01…SUIT-08) from a **YAML file in S3** and writes job progress to **DynamoDB**; the agent reasons over the rules and returns a per-product verdict.
- **Recommendation Letter** is a stateless generation step producing a markdown letter with a fixed disclosure block.
- Delivery surface: an **async Lambda + API Gateway (HTTP) REST API** that creates a job, self-invokes to run the supervisor (multi-agent runs take 1–3 min), and exposes status/result; a **React + Vite SPA** on **S3 + CloudFront** is the producer UI.

## Where to read first (in your implementation)

1. `README.md` — the agent's purpose, the four-agent diagram, the demo walkthrough, the tech stack table.
2. `agents/supervisor/agent-config.json` — the orchestration instruction and the `SUPERVISOR_ROUTER` collaboration mode. This defines the workflow order.
3. `agents/{product-retrieval,suitability,recommendation}/agent-config.json` — each specialist's system prompt and its attachment (knowledge base / action group / none). The prompts *are* the capability definition.
4. `agents/setup-agents.sh` and `agents/provision-agents.sh` — how the agents, action group, aliases, and collaborator associations are actually created via the Bedrock CLI.
5. `agents/suitability/action-group/handler.py` — `load_suitability_rules` (S3 YAML) and `update_job_status` (DynamoDB) — the only tools any agent calls.
6. `data/rules/suitability-rules.yaml` — the eight suitability rules, your criteria, and verdict logic. This is the compliance core.
7. `api/src/handlers/start_advisory.py` — the async job pattern: create job → self-invoke via `InvocationType=Event` → `bedrock-agent-runtime.invoke_agent` → write result to DynamoDB.
8. `infrastructure/template.yaml` — S3, DynamoDB, API Gateway, CloudFront/OAC, and the four IAM roles (agent, action, KB, API). Note the agent role scopes `bedrock:InvokeModel` to the specific model ARNs.

## Re-deploying for another tenant

1. **Load the product catalog.** Replace the sample documents in `data/carrier-products/` with your brochures/policy summaries/rate sheets, run `data/seed-data.sh`, and re-sync the Bedrock Knowledge Base so retrieval is grounded in real products.
2. **Rewrite the suitability rules.** Edit `data/rules/suitability-rules.yaml` to your compliance standard — rule set, thresholds (e.g. the 10%-of-income affordability ceiling), and verdict logic.
3. **Tune the agent prompts.** Edit the four `agents/*/agent-config.json` instructions for your lines of business; have compliance review the recommendation agent's disclosure block.
4. **Provision the agents.** Run `infrastructure/deploy.sh`, then `agents/setup-agents.sh` + `agents/provision-agents.sh` to create the agents, attach the KB and action group, wire the collaborators, and write the supervisor agent ID/alias into the API Lambda's environment.
5. **Deploy API + UI.** Run `api/deploy-api.sh` and `frontend/deploy-frontend.sh`; map the client schema in `data/client-profiles/clients.json` to your CRM/policy-admin data.

## What you're NOT building

- **Not autonomous advice.** The output is a draft recommendation package for a licensed producer to review, edit, and own. Never wire it to bind or send a recommendation without a human.
- **Not a new model.** Use Bedrock-hosted models via inference profiles; do not fine-tune or stand up custom inference.
- **Not a single mega-prompt.** Keep the four agents separate — the supervisor routes; each specialist owns one job. That separation is what makes retrieval, suitability, and letter generation independently inspectable.
- **Not a copy of the source into the kit folder.** The kit holds metadata + specs; the implementation is built from this spec in your own repository.

## Non-negotiables

- **Suitability rules are externalized, not hardcoded.** They live in `data/rules/suitability-rules.yaml`, loaded at runtime via the action-group Lambda. You must be able to change a threshold without a code change.
- **Every suitability verdict cites its rule ID.** The agent must produce a per-rule pass/fail with reasoning and an overall SUITABLE/UNSUITABLE/CONDITIONAL verdict — not a single opaque score. UNSUITABLE on any rule makes the product UNSUITABLE overall.
- **Every letter carries the disclosure block.** The standard not-FDIC-insured / not-a-deposit / not-financial-advice disclosure is mandatory and lives in the recommendation agent's instruction.
- **Retrieval is grounded in the knowledge base.** The product-retrieval agent recommends only products found in the indexed carrier documents, with source citations — it must not invent products or eligibility.
- **The supervisor passes full client context to every sub-agent** and returns sub-agent output verbatim (do not let the supervisor summarize away the letter or the per-rule reasoning).
- **IAM is least-privilege:** the Bedrock agent role grants `InvokeModel` only on the specific model ARNs in use; the KB role is scoped to the product bucket + OpenSearch collection; the action role is scoped to the rules bucket (read) and the jobs table (update).

## Defaults

- **Models:** suitability + supervisor reasoning on `us.anthropic.claude-sonnet-4-5-20250929-v1:0`; product retrieval on `us.amazon.nova-2-lite-v1:0`; recommendation/supervisor optionally moved to `us.amazon.nova-pro-v1:0` for speed (see `agents/speed-up-models.sh`); KB embeddings on `amazon.titan-embed-text-v2:0`. Claude 4.x and Nova are served via inference profiles (`us.` prefix).
- **Region:** `us-east-1` (where the models were verified). Confirm Bedrock model access in the target region.
- **Naming:** `insurance-advisor-*` project prefix for buckets, tables, roles, Lambdas, and agents (rename per deployment).
- **Job model:** advisory runs are async — API returns `202 + jobId`, the client polls status. The jobs table has a TTL.

## Things to confirm before customizing

- What's the client-profile data shape, and where does it live (CRM, policy-admin, spreadsheet)?
- What is your suitability standard — which rules, which thresholds, which lines of business?
- Who owns and signs off the disclosure language (compliance)?
- What's the carrier product catalog, in what format, and can it be indexed into a knowledge base?
- What latency is acceptable per advisory, and what's the cost ceiling (drives the Sonnet-vs-Nova model mix)?

## When to pause and flag for review mid-build

- You want autonomous, bind-able recommendations (out of scope — escalate).
- There's no usable client-profile data or no product catalog to index.
- Compliance hasn't signed off on the suitability rules or disclosure language.
- Bedrock model access (Claude Sonnet 4.5 / Nova) or multi-agent collaboration isn't available in your account/region.
- You need PII handling, retention, or audit guarantees beyond what the reference (DynamoDB + CloudWatch) provides.

## Done definition

- CFN stack deploys; data is seeded; the knowledge base is synced over your product documents.
- All four agents are provisioned, the action group + KB are attached, and the supervisor's collaborators are wired; the supervisor alias ID is set in the API Lambda environment.
- An advisory run for a sample client returns a package with retrieved products (with citations), a per-rule suitability verdict per product, and a letter containing the disclosure block.
- The async API returns `202 + jobId`, status transitions to `complete`, and the result is retrievable; the SPA renders all tabs.
- Acceptance tests in [`build-spec/acceptance-tests.md`](build-spec/acceptance-tests.md) pass.
- IAM roles confirmed least-privilege; deployed into your own account/region.
