# Requirements — Code Intelligence Agent

> Audience: a coding agent implementing or customizing the kit, and a reviewer certifying the build.

## Functional requirements

**FR1 — Cited, code-grounded answers.** Given a natural-language question, the system shall retrieve relevant code chunks and synthesize an answer with Claude Sonnet 4.5 that includes `[file_path:start_line-end_line]` citations for every claim. If the indexed context can't answer, the system shall say so rather than speculate. Code in context is treated as data — instructions embedded in code/comments are never followed. *Maps to: T1, T2.*

**FR2 — Per-user repo scoping via GitHub identity.** The system shall pass through the requesting user's GitHub identity and answer only over repositories that user can read, verified against the GitHub API (`GET /repos/{owner}/{repo}`) with a short-TTL cache. It shall never widen scope to all indexed repos. *Maps to: T3, T4.*

**FR3 — GitHub-API ingestion with AST-aware chunking.** The system shall index a repo by fetching its file tree through the GitHub API (no clone, rate-limit aware), chunking each file AST-aware via tree-sitter with a line-based fallback (≈150 lines, 20-line overlap), embedding chunks with Titan Embed v2 (1024-dim, normalized), persisting a FAISS index to S3, and storing chunk metadata in DynamoDB. *Maps to: T5, T6.*

**FR4 — Intent classification and routing.** The system shall classify each query (architecture / search / dependency / security / operations / admin / status). `admin`/`status` shall route without an LLM call; ambiguous queries use a Claude classification call with a keyword-regex fallback so classification never hard-fails. *Maps to: T7.*

**FR5 — Role-aware responses.** The system shall tailor answer depth to the asker's role: executive (no raw code blocks, top-3 citations), architect (file-deduplicated citations), security and developer (full detail). *Maps to: T8.*

**FR6 — Auto re-indexing on push/PR.** The system shall accept GitHub `push`/`pull_request` webhooks, verify the HMAC signature, enqueue to an SQS FIFO queue, and re-index changed files via the incremental indexer. Poison messages shall land in a DLQ. *Maps to: T9.*

**FR7 — GitHub OAuth connect with CSRF protection.** The system shall provide an OAuth connect flow that stores a state token in DynamoDB (10-min TTL) for CSRF validation, exchanges the code on callback, and stores the access token KMS-encrypted. *Maps to: T10.*

**FR8 — MCP surface for Amazon Quick.** The system shall expose `query_code`, `index_repo`, `get_status`, `connect_github` (and `query_dependencies`) as MCP tools over an IAM-authenticated Lambda Function URL with `RESPONSE_STREAM`, callable from Amazon Quick. *Maps to: T11.*

**FR9 — Two-layer guardrails.** The system shall screen inputs for SQL/shell/prompt-injection and path-traversal patterns and reject over-long queries, AND redact secret-shaped strings (GitHub tokens, API keys, hardcoded credentials) from outputs — in addition to the Bedrock `CodeIntelGuardrail`. *Maps to: T12.*

**FR10 — Per-user token budget.** The system shall enforce a configurable per-user daily token budget (default 100K) and refuse over-budget queries with a clear message. *Maps to: T13.*

## Non-functional requirements

**NFR1 — Grounding / no hallucination.** Every answer shall be traceable to retrieved chunks via citations; unanswerable questions return an explicit "not in the indexed context" response. *Maps to: T1.*

**NFR2 — Least-privilege IAM per function.** Each Lambda shall hold only the permissions it needs — the MCP function: DynamoDB CRUD on its table, S3 CRUD on its bucket, `bedrock:InvokeModel*`, `ApplyGuardrail` on the specific guardrail ARN, KMS encrypt/decrypt; the OAuth function: KMS encrypt only; the webhook function: SQS send only. No `*` resource grants beyond what `template.yaml` scopes. *Maps to: T14.*

**NFR3 — Encryption.** OAuth tokens shall be encrypted with a you own KMS CMK; the DynamoDB table shall use KMS SSE; the S3 bucket shall use server-side encryption. Plaintext tokens shall not outlive the API-call scope and shall never be logged. *Maps to: T15.*

**NFR4 — Single-tenancy / residency.** One deployment per organization in your own account/region; the only outbound dependencies are in-region Bedrock and the GitHub API. *Maps to: T14.*

**NFR5 — Cost predictability.** Bedrock cost shall scale with query volume and repo size; the per-user token budget and incremental (changed-files-only) re-indexing shall bound spend. Reference: ~$20–35/mo for a single small-repo deployment. *Maps to: T13.*

**NFR6 — Observability.** X-Ray tracing shall be active; a CloudWatch dashboard shall expose query latency, token usage, errors, and queue/DLQ depth; alarms shall fire on high error rate and DLQ messages; logs shall retain 90 days. *Maps to: T16.*

**NFR7 — Resilience.** Intent classification shall fall back to keyword matching on LLM failure; per-file indexing failures shall be skipped without failing the whole index run; webhook DLQ shall capture repeated failures. *Maps to: T7, T9.*

## Out of scope

- Developer IDE code completion / copilot functionality.
- Writing code, opening PRs, or any autonomous action on a repo or infrastructure.
- SECURITY/OPERATIONS delegation to specialized Bedrock/AgentCore Frontier Agents (Phase 2 — `src/delegation/` is a stub).
- Large-repo offload to Fargate / Step Functions (documented roadmap pattern; not in the SAM stack).
- Multi-branch indexing (the default branch is indexed by design).
- Model fine-tuning or custom inference hosting.

## Dependencies

- Bedrock model access enabled for **Claude Sonnet 4.5** (`us.anthropic.claude-sonnet-4-5-20250929-v1:0`) and **Titan Embed v2** (`amazon.titan-embed-text-v2:0`) in your region (`us-east-1` default).
- A **GitHub OAuth App** in your org (Client ID + Secret) and a webhook secret.
- AWS account with permissions to deploy via SAM: Lambda, API Gateway, DynamoDB, S3, SQS, KMS, Bedrock Guardrails, CloudWatch, X-Ray, IAM.
- AWS SAM CLI, AWS CLI v2, Python 3.12+.
- `tree-sitter-languages` for AST chunking (the chunker falls back to line-based chunking if a grammar is unavailable).
- Amazon Quick configured to connect to an MCP server (the Function URL target).
