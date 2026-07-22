# AGENTS.md — Code Intelligence Agent

> **Audience: a coding agent** (Kiro / Claude Code / etc.) re-implementing or customizing this kit for your organization.

## What this is

- An **MCP server** that answers natural-language questions about a GitHub codebase with **file:line citations**, invoked from **Amazon Quick** over an **IAM-authenticated Lambda Function URL** (`RESPONSE_STREAM`).
- A **RAG pipeline**, not a fine-tuned model: GitHub-API ingestion (no clone) → AST chunking (tree-sitter) → **Bedrock Titan** embeddings → **FAISS** index in **S3** → **Claude (Sonnet 4.5)** synthesis with citations.
- **GitHub identity pass-through:** each request carries the user; OAuth tokens are **KMS-encrypted**, and repo scope is checked per user so the agent only answers over repos that user can see.
- **Role-aware answers:** one agent, four personas (executive / architect / security / developer) shaped in `src/query_engine/role_filter.py`.
- **Auto re-indexing:** GitHub webhook (HMAC-verified) → **SQS FIFO** (+ DLQ) → incremental indexer Lambda.
- Deployed as **AWS SAM** (`template.yaml`): four Lambdas (MCP, webhook, OAuth callback, incremental indexer), API Gateway (webhook + OAuth only), DynamoDB single-table, S3, KMS CMK, Bedrock Guardrail, CloudWatch dashboard/alarms, X-Ray.

## Where to read first (in your implementation)

1. `README.md` — purpose, the deploy flow (`sam build` / `sam deploy --guided`), the MCP tool table, and the cost/limitations tables.
2. `template.yaml` — the whole deployable stack: the four functions, IAM scoping, DynamoDB/S3/SQS/KMS, and the `CodeIntelGuardrail` policy. This is the trust-boundary source of truth.
3. `src/mcp/server.py` + `src/mcp/tools.py` — MCP JSON-RPC routing and the tool handlers (`query_code`, `index_repo`, `get_status`, `connect_github`). The tools *are* the capability definition.
4. `src/query_engine/{intent,retrieval,synthesis,role_filter}.py` — the RAG path: how a query is classified, retrieved, synthesized with citations, and filtered by role.
5. `src/ingestion/{fetcher,chunker,embedder,incremental}.py` — the indexing path: GitHub fetch, AST chunking, Titan embedding, webhook-driven incremental re-index.
6. `src/identity/{tokens,access_check,token_budget}.py` — KMS token store, per-user repo access checks, daily token budget.
7. `src/guardrails.py` — local input validation + output secret-redaction that complements the Bedrock Guardrail.
8. `docs/THREAT_MODEL.md` + `docs/ARCHITECTURE_GUIDE.md` — the STARLORD threat analysis and the full architecture rationale.

## Re-deploying for another tenant

1. **Create a GitHub OAuth App** in your org; set its callback to the deploy's `OAuthCallbackUrl`. Capture Client ID + Secret as SAM parameters.
2. **Tune the Guardrail** (`template.yaml` → `CodeIntelGuardrail`) — PII entities, content filters, and the secret-redaction regexes — to your compliance posture.
3. **Adapt the RAG layer** — role personas in `role_filter.py`, intent categories/keywords in `intent.py`, and the AST chunker in `chunker.py` for your languages and schema formats (Avro/Protobuf/OpenAPI/SQL).
4. **Deploy** with `sam build && sam deploy --guided` (region `us-east-1` recommended for model availability); confirm Bedrock access for Claude Sonnet 4.5 and Titan Embed v2.
5. **Index + connect** — register per-repo webhooks at `GitHubWebhookUrl`, index 2–3 representative repos, and add the `McpServerFunctionUrl` as a Quick "Connect to any MCP server" target (same-account IAM auth).

## What you're NOT building

- **Not a developer IDE copilot.** This is org-wide code Q&A, not code completion or PR authoring. The agent never writes code or modifies repos.
- **Not autonomous.** It answers questions; it takes no actions on the repo or infrastructure.
- **Not the Phase 2 Frontier-Agent delegation.** `src/delegation/` is a stub (`__init__.py` only); SECURITY/OPERATIONS intents are classified but delegation to specialized Bedrock Agents is roadmap, not shipped. Don't claim it works — build it only if it's explicitly in scope.
- **Not a copy of the source into the kit folder.** The kit holds metadata + specs; the implementation is built from this spec in your own repository.

## Non-negotiables

- **Cite or it didn't happen.** Every `query_code` answer is grounded in retrieved chunks and carries file:line citations. Don't let the model answer from parametric memory.
- **Identity pass-through is mandatory.** Answer only over repos the requesting user can access; check access per user (`src/identity/access_check.py`). Never widen scope to "all indexed repos."
- **OAuth tokens stay KMS-encrypted and short-lived in memory.** Tokens are encrypted with you CMK; keep the token-callback pattern (token never outlives the API call scope). Never log tokens.
- **Two guardrail layers stay in place.** Local input validation + output secret-redaction (`src/guardrails.py`) AND the Bedrock Guardrail (`bedrock:ApplyGuardrail`). Don't drop either.
- **Least-privilege IAM per function.** Each Lambda gets only the actions it needs (the MCP function: DynamoDB CRUD on its table, S3 CRUD on its bucket, `bedrock:InvokeModel*`, `ApplyGuardrail` on the specific guardrail ARN, KMS encrypt/decrypt). Don't grant `*` resources beyond what `template.yaml` already scopes.
- **Cost controls stay on.** Per-user daily token budget and Lambda reserved concurrency are DoS/cost protections — keep them, tune the values.

## Defaults

- **Model:** `us.anthropic.claude-sonnet-4-5-20250929-v1:0` (synthesis + intent), `amazon.titan-embed-text-v2:0` (embeddings). Region `us-east-1`.
- **Stack name:** `code-intel-agent` (rename per deployment). DynamoDB single-table with GSI1; S3 bucket holds FAISS indexes.
- **Auth:** MCP via Function URL `AWS_IAM` + `RESPONSE_STREAM`; webhook/OAuth via API Gateway (`/webhook/github`, `/oauth/callback`).
- **Limits:** `USER_DAILY_TOKEN_LIMIT=100000`, `ReservedConcurrentExecutions=50`, CloudWatch log retention 90 days.

## Things to confirm before customizing

- How many repos and which languages? (Drives chunker config and whether Lambda 15-min indexing is enough or a Fargate/Step Functions offload is needed for very large repos.)
- Which roles ask questions, and what should each see? (Drives `role_filter.py`.)
- What's the compliance posture — required PII/secret handling and audit retention? (Drives the Guardrail policy and log retention.)
- GitHub OAuth App vs. GitHub App, and org-wide vs. per-repo webhooks?
- Is Quick the only surface, or also the `chat.py` CLI / direct Lambda invoke?

## When to pause and flag for review mid-build

- A repo exceeds ~1000 source files and won't index within the Lambda 15-min timeout — needs the Fargate or Step Functions offload (roadmap pattern).
- You want SECURITY/OPERATIONS delegation to Frontier Agents (Phase 2 — not built; scope as follow-on).
- You want the agent to write code, open PRs, or act on infra — out of scope.
- Bedrock access for Claude Sonnet 4.5 or Titan Embed v2 isn't enabled in your region.
- Source isn't reachable via the GitHub API, or OAuth/webhook access can't be granted.

## Done definition

- `sam build && sam deploy` succeeds; `initialize` and `tools/list` return the four tools; the MCP Function URL is connected in Quick.
- A `query_code` call returns a synthesized answer with file:line citations, scoped to the requesting user's accessible repos.
- A blocked/malicious input is refused by the guardrail; a leaked secret in output is redacted.
- A push/PR to an indexed repo fires the webhook → SQS → incremental indexer and updates the index.
- Acceptance tests in [`build-spec/acceptance-tests.md`](build-spec/acceptance-tests.md) pass; each Lambda's IAM role is least-privilege; logs retain 90 days.
