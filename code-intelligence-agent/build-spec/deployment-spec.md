# Deployment Spec — Code Intelligence Agent

> Audience: a coding agent provisioning resources in your account.

## Deployment context

- **Account:** your own AWS account (single-tenant).
- **Region:** `us-east-1` by default (where Claude Sonnet 4.5 and Titan Embed v2 are verified). Confirm Bedrock model access in the chosen region first.
- **Trust boundary:** everything runs in your account; the only outbound dependencies are in-region Bedrock and the GitHub API.
- **Source code location:** the kit folder holds metadata and specs; build the implementation from the specs in this folder.
- **Delivery unit:** one AWS SAM stack (`template.yaml`) — `sam build && sam deploy --guided`.

## Resources to create (from `template.yaml`)

- **Compute (4 Lambdas, Python 3.12, X-Ray active):**
  - `McpServerFunction` — Function URL (`AWS_IAM`, `RESPONSE_STREAM`), 4096 MB, 900 s timeout, `ReservedConcurrentExecutions: 50`. The Quick connector target.
  - `GitHubWebhookFunction` — API Gateway `POST /webhook/github`, 256 MB, 30 s; HMAC-verifies and enqueues to SQS.
  - `IncrementalIndexerFunction` — SQS-triggered (batch size 1), 2048 MB, 300 s; re-indexes changed files.
  - `OAuthCallbackFunction` — API Gateway `GET /oauth/callback`, 256 MB, 30 s; exchanges the OAuth code and stores the token encrypted.
- **API:** `WebhookApi` (API Gateway, stage `prod`) — webhook + OAuth only, never MCP traffic.
- **Storage:** `EmbeddingsBucket` (S3, AES256 SSE — holds per-repo FAISS indexes); `MetadataTable` (DynamoDB single-table PK/SK + `GSI1`, PAY_PER_REQUEST, KMS SSE, PITR, TTL enabled).
- **Messaging:** `IndexingQueue` (SQS FIFO, content-based dedup, 360 s visibility, 1-day retention, redrive `maxReceiveCount` 3); `IndexingDLQ` (FIFO, 14-day retention).
- **Security:** `TokenEncryptionKey` (KMS CMK) + alias; `CodeIntelGuardrail` (Bedrock Guardrail) + `CodeIntelGuardrailVersion`.
- **Observability:** `AgentDashboard` (CloudWatch); `HighErrorRateAlarm` (>5 MCP errors / two 5-min periods); `DLQAlarm` (≥1 DLQ message). Log retention set to 90 days post-deploy via the CLI.

## IAM (least-privilege per function)

| Function | Permissions |
|---|---|
| `McpServerFunction` | DynamoDB CRUD on `MetadataTable`; S3 CRUD on `EmbeddingsBucket`; `bedrock:InvokeModel` + `InvokeModelWithResponseStream`; `bedrock:ApplyGuardrail` on the `CodeIntelGuardrail` ARN; KMS `Encrypt`/`Decrypt` on the CMK |
| `GitHubWebhookFunction` | DynamoDB CRUD; SQS `SendMessage` to `IndexingQueue` |
| `IncrementalIndexerFunction` | DynamoDB CRUD; S3 CRUD; `bedrock:InvokeModel`; KMS `Decrypt` |
| `OAuthCallbackFunction` | DynamoDB CRUD; KMS `Encrypt` only |

## SAM parameters (provided at deploy)

| Parameter | Purpose | Notes |
|---|---|---|
| `GitHubClientId` | GitHub OAuth App client ID | `NoEcho` |
| `GitHubClientSecret` | GitHub OAuth App secret | `NoEcho` |
| `GitHubWebhookSecret` | HMAC secret for webhook signature validation | `NoEcho` |

## What you configure during the build

| Config item | Where | Source |
|---|---|---|
| Guardrail policy (PII entities, content filters, secret regexes) | `CodeIntelGuardrail` | `template.yaml` |
| Role personas + detail per role | `role_filter.py` | `src/query_engine/` |
| Intent categories + keyword fallbacks | `intent.py` | `src/query_engine/` |
| Answer prompt + citation format | `synthesis.py` | `src/query_engine/` |
| AST chunking rules / languages / schemas | `chunker.py` | `src/ingestion/` |
| Per-user daily token budget | `USER_DAILY_TOKEN_LIMIT` (default 100000) | `template.yaml` env |
| Reserved concurrency | `ReservedConcurrentExecutions` (default 50) | `template.yaml` |
| GitHub OAuth App + per-repo webhooks | OAuth App + repo settings | GitHub |

## What's pre-built

- The MCP server (Function URL, `RESPONSE_STREAM`) with `query_code` / `index_repo` / `get_status` / `connect_github` (+ `query_dependencies`).
- The ingestion pipeline (GitHub-API fetcher, tree-sitter chunker, Titan embedder, FAISS-on-S3 with `/tmp` cache).
- The RAG query engine (intent classification, retrieval, Claude synthesis with citations, role filtering).
- The GitHub identity layer (OAuth callback, KMS token store, per-user access checks, DynamoDB TTL cache).
- Auto re-indexing (HMAC webhook → SQS FIFO + DLQ → incremental indexer).
- Security + observability in the SAM template (Bedrock Guardrail, KMS CMK, input/output sanitization, X-Ray, dashboard + alarms, 90-day logs, token metering).

## Cost expectations

| Driver | Reference (single small repo) |
|---|---|
| Bedrock (Claude Sonnet 4.5 + Titan embeddings) | ~$15–30/mo |
| Lambda | ~$3/mo |
| DynamoDB | ~$0.25/mo |
| S3 | ~$0.05/mo |
| KMS | ~$1/mo |
| **Total** | **~$20–35/mo** |

Scales with query volume and repo size; the per-user token budget and incremental (changed-files-only) re-indexing bound spend.

## Pre-deployment checklist

- [ ] Bedrock access enabled for Claude Sonnet 4.5 and Titan Embed v2 in the target region.
- [ ] AWS SAM CLI + AWS CLI v2 configured with deploy permissions (Lambda, API GW, DynamoDB, S3, SQS, KMS, Bedrock Guardrails, CloudWatch, X-Ray, IAM).
- [ ] GitHub OAuth App created in your org; Client ID + Secret captured.
- [ ] Webhook secret chosen.
- [ ] Pilot repos (2–3) identified; languages mapped against the chunker's grammar list.

## Post-deployment validation

- [ ] `initialize` and `tools/list` return the tools over the MCP Function URL.
- [ ] OAuth App callback set to `OAuthCallbackUrl`; `connect_github` authorizes successfully.
- [ ] Per-repo webhooks registered at `GitHubWebhookUrl`; a push fires webhook → SQS → incremental indexer.
- [ ] `index_repo` + `get_status` show pilot repos `complete`; a `query_code` answer returns with `file:line` citations scoped to the user.
- [ ] A malicious input is refused; a planted secret is redacted from output.
- [ ] Each Lambda's IAM role confirmed least-privilege; log retention set to 90 days.

## Day-2 operations (yours to run)

- Set CloudWatch log retention (90 days) and review the dashboard + alarms.
- Re-tune the Guardrail policy, role filters, intent routing, and chunker as the codebase and compliance needs evolve.
- Manage Bedrock spend via the per-user token budget; keep webhooks healthy (watch the DLQ alarm).
- For repos over ~1000 files, implement the Fargate / Step Functions offload (roadmap pattern).
- Tear down with `sam delete --stack-name code-intel-agent` when decommissioning.
