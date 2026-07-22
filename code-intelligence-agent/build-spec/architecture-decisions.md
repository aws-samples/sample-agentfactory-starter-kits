# Architecture Decisions — Code Intelligence Agent

> Audience: a coding agent that might be tempted to deviate. These are distilled from the source `template.yaml`, the `src/` modules, the `README.md`, and `ROADMAP.md`. Don't reverse them without careful consideration.

## AD1 — RAG over a fine-tuned model
**Decision:** Answer questions with retrieval + Claude synthesis over indexed code, not a model trained on your code.
**Why:** Code changes constantly; embeddings + webhook re-indexing keep answers current with no retraining, and retrieval gives verifiable `file:line` citations a fine-tune can't. It also keeps the source in your account.
**What this means for the build:** Keep the ingest → chunk → embed → retrieve → synthesize pipeline; don't substitute parametric model knowledge for retrieval.

## AD2 — Citations are mandatory; code is data
**Decision:** Every `query_code` answer cites `[file_path:start_line-end_line]` from retrieved chunks, and the synthesis system prompt treats code context as data only (never follows instructions embedded in code/comments).
**Why:** Grounding is the product — non-engineers must be able to verify an answer against the actual code, and a codebase is a prime prompt-injection surface.
**What this means for the build:** Don't relax the grounding prompt or let the model answer from memory. If context can't answer, return "not in the indexed context."

## AD3 — GitHub identity pass-through, checked per user (per query)
**Decision:** The requesting user's identity is passed through; repo access is verified against the GitHub API per user, cached 5 minutes in DynamoDB, and the query is scoped to only accessible repos.
**Why:** A shared index must never become a way to read code a user can't see in GitHub. GitHub is the single source of truth for access.
**What this means for the build:** Never widen scope to "all indexed repos." Keep the access check and audit log on every query.

## AD4 — Ingest via GitHub API, no clone
**Decision:** `fetcher.py` walks the repo tree through the GitHub API rather than cloning.
**Why:** Avoids storing full working copies, works within Lambda's ephemeral filesystem, and lets ingestion be rate-limit aware (GitHub's 5000 req/hr) and incremental.
**What this means for the build:** Keep API-based fetching; for very large repos, offload (AD11) rather than reverting to clone.

## AD5 — AST-aware chunking with a line-based fallback
**Decision:** Chunk files at function/class/method boundaries via tree-sitter (`chunker.py`), falling back to ≈150-line/20-overlap windows when no grammar applies; target ≈200 tokens, max 500, merge tiny chunks.
**Why:** Semantic boundaries retrieve far better than fixed windows, and the fallback guarantees every file (configs, schemas, unknown languages) still gets indexed.
**What this means for the build:** Add languages/schema formats to the extension and boundary maps for you; never drop the line fallback.

## AD6 — Titan Embed v2 at 1024 dims, same model at index and query time
**Decision:** Use `amazon.titan-embed-text-v2:0`, 1024 dimensions, normalized, for both chunk embedding and query embedding.
**Why:** Vectors must come from the same model/space to be comparable; normalization suits cosine similarity in FAISS.
**What this means for the build:** If you change the embedding model or dimensions, you must re-index — don't mix.

## AD7 — FAISS on S3 with Lambda /tmp cache
**Decision:** Persist one FAISS index per repo to S3 (`vector_store.py`) and cache it in Lambda `/tmp` on warm invocations.
**Why:** Serverless, cheap, no vector-DB to run; `/tmp` caching avoids re-downloading the index every call.
**Alternatives considered:** A managed vector store (e.g. OpenSearch Serverless) — heavier and costlier than the POC needs; FAISS-on-S3 fits the single-tenant, low-ops goal.
**What this means for the build:** Keep per-repo index files; mind the Lambda 4 GB memory ceiling for very large indexes (AD11).

## AD8 — Claude Sonnet 4.5 via inference profile for synthesis and intent
**Decision:** Synthesis (max 2048 tokens, temp 0.2) and intent classification (max 20 tokens, temp 0.0) both use `us.anthropic.claude-sonnet-4-5-20250929-v1:0`.
**Why:** Sonnet 4.5 balances answer quality and cost; a tiny, deterministic classification call is cheap and keeps routing snappy.
**What this means for the build:** Use the inference-profile ID, not a bare foundation-model ID. Keep the intent call cheap.

## AD9 — Two guardrail layers, not one
**Decision:** Local regex input validation + output secret-redaction (`guardrails.py`) AND the Bedrock `CodeIntelGuardrail` (content filters, PII anonymization, GitHub-token/API-key regexes, profanity list).
**Why:** Local checks are instant and free for obvious injection/secret patterns; the Bedrock Guardrail catches semantic/PII cases the regexes miss. Defense in depth.
**What this means for the build:** Keep both. Tune the Guardrail policy and the regexes to your compliance posture; don't remove either layer.

## AD10 — MCP over an IAM-authenticated Function URL; API Gateway only for webhook/OAuth
**Decision:** Quick talks to the MCP function over a Function URL (`AWS_IAM`, `RESPONSE_STREAM`). API Gateway carries only `/webhook/github` and `/oauth/callback`.
**Why:** Same-account IAM auth is the simplest secure path for Quick, and `RESPONSE_STREAM` streams answers. Webhook/OAuth need public HTTPS endpoints, which API Gateway provides — but MCP traffic never goes through it.
**What this means for the build:** Don't route MCP through API Gateway; keep the Function URL IAM-auth model.

## AD11 — Decision-support, single-branch, in-Lambda indexing (with a documented scale-out)
**Decision:** The agent answers questions only (no code writes/PRs/actions), indexes the default branch, and indexes small repos in-process in the Lambda. Repos over ~1000 files need an offload.
**Why:** Keeps scope tight, the index focused, and cost predictable. The Lambda 15-min timeout and 4 GB memory bound in-process indexing.
**Alternatives considered:** Fargate offload (no timeout, up to 120 GB RAM) or a Step Functions Distributed Map — documented in `ROADMAP.md` as the large-repo pattern; the MCP server already returns a job ID and supports `get_status` polling so the UX is unchanged.
**What this means for the build:** For large repos, implement the offload rather than fighting the Lambda limits. Never wire the agent to take actions on a repo.

## AD12 — Frontier-Agent delegation is roadmap, not shipped
**Decision:** `SECURITY` and `OPERATIONS` intents are classified, but `src/delegation/` is a stub — delegation to specialized Bedrock/AgentCore agents is Phase 2.
**Why:** The Phase 1 value is cited RAG Q&A; specialized security/ops agents are a separate, larger build.
**What this means for the build:** Don't claim delegation works. Build it only if it is explicitly scoped; until then those intents fall through to the RAG path.
