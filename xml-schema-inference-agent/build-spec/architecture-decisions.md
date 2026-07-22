# Architecture Decisions — XML Schema Inference Agent

> Audience: a coding agent that might be tempted to deviate. These are distilled from the source (README, `hackathon/aidlc_usecase.md`, `agent_prompt.md`, `schema_agent.py`, CDK) plus kit-level packaging decisions. Don't reverse them without reviewing the tradeoffs first.

## AD1 — One agent with deterministic tools, not a free-form prompt
**Decision:** A single Bedrock Agent orchestrates three Python tools (`analyze_traces`, `generate_mapping`, `generate_sql`); the heavy lifting is in code, not the prompt.
**Why:** Schema discovery, type inference, array detection, mapping confidence, and SQL must be reproducible and reviewable. A model asked to "map this XML" free-form gives different answers each run and can't be audited.
**Alternatives considered:** A single mega-prompt (rejected — non-deterministic, no confidence scoring, no array detection across a batch).
**What this means for the build:** Keep the logic in the tools; the model decides which tool to call and interprets results, nothing more.

## AD2 — Custom IaC (CDK), not a managed harness
**Decision:** Ship as a CDK stack provisioning S3 + Lambda + IAM + the Bedrock agent role; build level `custom-iac`.
**Why:** The kit deploys real owned infrastructure — a tools Lambda, an S3 traces bucket, scoped IAM, and a separate parser Lambda. That's an audited custom stack, not a prompt-and-KB harness.
**What this means for the build:** Deploy with `cdk deploy`; you own and audits the stack.

## AD3 — Claude Sonnet 4 as the reasoning model
**Decision:** Use `anthropic.claude-sonnet-4-20250514-v1:0` (the model wired into the CDK Bedrock invoke policy).
**Why:** Schema unification across heterogeneous structures needs strong reasoning, but the per-onboarding call volume is low, so Sonnet's balance of capability and cost fits. (The source README/usecase text references "Sonnet 4.5/4.6" loosely; the deployed IAM policy pins Sonnet 4 — treat the code as authoritative.)
**What this means for the build:** Confirm model access in the target region; don't fine-tune or self-host.

## AD4 — Type inference is rule-based, run in the tools
**Decision:** `infer_type` derives types from string value patterns in code (leading-zero numerics stay strings; `Y`/`N`/`PASS`/`FAIL` → boolean; ISO dates → date).
**Why:** Source XML is entirely strings. Letting the model guess types is non-deterministic and gets zero-padded identifiers and boolean encodings wrong.
**What this means for the build:** Extend `infer_type` for your encodings; keep it in code, not the prompt.

## AD5 — Array detection at the schema level, across a batch
**Decision:** Repeating elements are recognized as arrays across the whole trace batch (parser collapses repeating tags + `ArrayElementObject/String`; `analyze_traces` records arrays with counts).
**Why:** This is the exact failure that broke your Snowflake/Databricks/Iceberg POCs — an element appearing once in one trace and many times in another. Per-trace detection misses it.
**What this means for the build:** Never infer array-ness from a single trace; analyze the batch.

## AD6 — Path-pattern matching before keyword matching
**Decision:** `generate_mapping` tries multi-part `PATH_PATTERNS` (e.g. `creditdata.score.value`) as path suffixes first, then falls back to field-name keyword + context matching.
**Why:** The same logical field hides at very different depths/names per source (`Origination.FinalScore` vs `LoanDecision.CreditData.Score.Value`). Name-only matching can't resolve the nested cases.
**What this means for the build:** Add your own nested cases to `PATH_PATTERNS`, not just keywords.

## AD7 — Confidence + unmapped reporting as first-class output
**Decision:** Every mapping carries a confidence score; unmatched fields are returned in `unmapped_fields`; the highest-confidence candidate per logical field wins.
**Why:** The product is a *reviewable draft*, not an autonomous writer. The engineer needs to see what's uncertain.
**What this means for the build:** Never drop unmapped fields silently or emit a mapping without confidence.

## AD8 — Human review before production; no autonomous writes
**Decision:** The agent proposes mappings and generates SQL; a data engineer approves before anything reaches production tables.
**Why:** A wrong mapping silently corrupts analytics. Review is the safety boundary.
**What this means for the build:** Do not wire generated SQL to auto-execute against live tables.

## AD9 — Redshift SUPER/PartiQL as the SQL target
**Decision:** `generate_sql` emits Redshift SUPER `SELECT` + `CREATE VIEW` + sample analytics, converting dot-paths to PartiQL accessors.
**Why:** SUPER lets you land semi-structured traces and query nested data directly — the destination that made the parsing effort worthwhile.
**Alternatives considered:** Flattening to relational columns up front (rejected — loses the nested structure and re-introduces per-source ETL).
**What this means for the build:** Keep SUPER/PartiQL as the target; adapt table/view names per deployment.

## AD10 — Parser supports both S3 and Kinesis ingestion
**Decision:** `xml_parser.py` handles S3 PutObject events and Kinesis stream records (base64 XML).
**Why:** Teams ingest traces both as batch files (S3) and as streams (Kinesis); supporting both avoids a rewrite per deployment.
**What this means for the build:** Keep both code paths; pick the trigger that matches your pipeline.

## AD11 — Mapping persistence is a production add-on, not shipped
**Decision:** The reference *returns* mappings; a durable, versioned mapping registry (e.g. DynamoDB, as sketched in the use-case doc) is not implemented.
**Why:** The hackathon scope proved the inference; persistence is a your own data-model decision.
**What this means for the build:** Flag this to your team; design the registry with you if reuse/diffing is required.

## AD12 — Least-privilege IAM
**Decision:** The Bedrock agent role grants only `bedrock:InvokeModel` on the one Claude model; the Lambda role gets `AWSLambdaBasicExecutionRole` + read on the traces bucket.
**Why:** The agent only needs to invoke the model; the tools only need to read traces. Anything broader is unjustified.
**What this means for the build:** Don't widen the policies for convenience.
