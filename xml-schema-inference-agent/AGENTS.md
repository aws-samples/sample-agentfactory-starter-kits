# AGENTS.md — XML Schema Inference Agent

> **Audience: a coding agent** (Kiro / Claude Code / etc.) re-implementing or customizing this kit for your organization.

## What this is

- A **single Bedrock Agent** (Claude Sonnet 4) that onboards an undocumented data source by reasoning over example traces and calling three deterministic Lambda tools.
- **One Lambda action group, three tools** (`src/lambda/schema_agent.py`): `analyze_traces` (flatten JSON, infer types, detect arrays → field inventory), `generate_mapping` (match discovered paths to standard logical field names with confidence), `generate_sql` (emit Redshift SUPER/PartiQL SELECT + view + sample analytics from the mappings).
- A **separate XML→JSON parser Lambda** (`lambda/xml_parser.py`) that turns the platform's raw XML into the JSON the agent consumes — handling deeply nested elements, repeating tags, and the `ArrayElementObject`/`ArrayElementString` array convention. Triggered by S3 PutObject or Kinesis.
- The **logical-field catalog and type-inference rules live in two places that must agree**: the agent system prompt (`hackathon/agent_prompt.md`) and the `STANDARD_FIELDS`/`infer_type` logic in the tool Lambda. The tools are the source of truth for what actually gets mapped; the prompt shapes how the agent orchestrates them.
- Delivery surface for the demo: a **Streamlit UI** (`src/ui/app.py`) with a no-AWS Local mode and a Bedrock Agent mode that streams the reasoning trace.

## The target implementation, file by file

No source code ships in this kit — you build the implementation from this contract. The paths below describe the target layout and where each piece of key logic lives:

1. `README.md` and `hackathon/aidlc_usecase.md` — the problem (per-source XML, no XSD, 2–3 day onboarding), the before/after, and the demo arc.
2. `hackathon/agent_prompt.md` — the agent's system prompt, the standard-field catalog, the string→type inference rules, and the expected tool contracts. This *is* the capability definition.
3. `src/lambda/schema_agent.py` — the three tools. `STANDARD_FIELDS`, `PATH_PATTERNS`, `flatten_json`, `infer_type`, `generate_mapping` confidence logic, and the PartiQL path construction in `generate_sql`.
4. `lambda/xml_parser.py` — how raw XML becomes JSON: attribute handling, repeating-element → array conversion, `ArrayElementObject`/`String` conventions, `infer_type`.
5. `src/lambda/api_schema.json` — the OpenAPI action-group schema the Bedrock agent uses (note: `bedrock_api_schema*.json` are alternate shapes; `api_schema.json` is the request-body version the handler parses).
6. `src/cdk/stack.py` + `src/cdk/app.py` — the deployable stack: S3 bucket, tools Lambda, Lambda role, Bedrock agent role with a scoped `bedrock:InvokeModel` policy.
7. `hackathon/trace_customer_A_parsed.json` and `trace_customer_C_parsed.json` — two structurally different sources that must resolve to the same logical fields.

## Re-deploying for another tenant

1. **Replace the logical-field dictionary** — edit `STANDARD_FIELDS` in `src/lambda/schema_agent.py` (and the matching catalog in `hackathon/agent_prompt.md`) to your domain fields and your matching keywords/context/path hints.
2. **Tune the path patterns** — update `PATH_PATTERNS` for nested fields that name-matching alone can't resolve in your traces.
3. **Adapt the parser** — adjust `lambda/xml_parser.py` for the source's array idioms and any non-standard type rules (`infer_type`).
4. **Point `generate_sql` at the real target** — set the table name, view-naming convention, and confirm the PartiQL path construction matches your Redshift SUPER table.
5. **Deploy** via CDK (`cd src/cdk && cdk deploy`), then create the Bedrock Agent (console or IaC), paste the system prompt, and attach the action group Lambda with `src/lambda/api_schema.json`.

## What you're NOT building

- **Not an autonomous pipeline.** The agent proposes mappings with confidence and generates SQL; a data engineer reviews before anything is promoted. Do not wire generated SQL to auto-run against production tables.
- **Not a generic XML library.** The value is the *logical-field mapping* and confidence scoring, not raw XML-to-JSON — that part is a thin parser.
- **Not a new model.** Use Bedrock-hosted Claude Sonnet 4; do not fine-tune or stand up custom inference.
- **Not a copy of any source into the kit folder.** The kit holds metadata + specs only; the implementation is built from this contract and lives in your own repository.

## Non-negotiables

- **Tools are deterministic; the model orchestrates.** Type inference, array detection, mapping confidence, and SQL generation are computed in Python in `schema_agent.py`. The model decides *which* tool to call and *interprets* results — it never invents a mapping the tool didn't return.
- **Confidence and unmapped fields are first-class output.** `generate_mapping` returns a confidence per mapping plus `unmapped_fields` and surfaces ambiguity. Never collapse to a bare path list — the review step depends on this.
- **The standard-field catalog in the prompt and the `STANDARD_FIELDS` dict must stay in sync.** Drift between them is the most common source of bad mappings.
- **Everything is a string in the source XML.** Type inference happens from value patterns (leading-zero numerics stay strings, `Y`/`N`/`PASS`/`FAIL` → boolean, ISO dates → date). Don't assume JSON types from the raw feed.
- **Repeating elements are arrays even when a trace shows one element.** Array detection must be schema-level across a batch of traces, not per-trace — this is the exact failure that broke the Snowflake/Databricks POCs.
- **IAM is least-privilege:** the Bedrock agent role grants only `bedrock:InvokeModel` on the specific Claude model; the Lambda role gets `AWSLambdaBasicExecutionRole` + S3 read on the traces bucket only.

## Defaults

- **Model:** `anthropic.claude-sonnet-4-20250514-v1:0` (provider: bedrock). The deployed reference agent ran in `us-east-1`; the CDK app currently targets `us-west-2` — pick one and make both consistent before deploying.
- **Tools Lambda:** `schema-inference-agent-tools`, Python 3.12, 512 MB, 60 s timeout.
- **Naming:** S3 traces bucket `schema-agent-traces-<account>-<region>`; rename per deployment.

## Things to confirm before customizing

- What are your standard/logical business fields, and how do they refer to them today?
- How many distinct source schemas, and can you get 3–10 real example traces per source?
- Where does the mapped data need to land — Redshift SUPER, a mapping registry, or just an export?
- What are the source's array/repeating-element conventions and any odd type encodings (zero-padded IDs, custom booleans)?
- Is PII present in the traces, and how is it masked before parsing?

## When to flag back mid-build

- You expect mappings to go straight to production with no human review (out of scope — escalate).
- Sources already share a stable XSD/schema — the agent adds little; reconsider fit.
- Traces are unavailable or too few per source to detect arrays reliably.
- Bedrock model access for Claude Sonnet 4 isn't enabled in your account/region.
- You need a persisted, versioned mapping registry (the reference outputs mappings; persistence is a customization — see architecture notes).

## Done definition

- Agent runs `analyze_traces` → `generate_mapping` → `generate_sql` end-to-end on a batch of your traces.
- Two structurally different sources resolve to the same logical fields; cross-source unification is demonstrable.
- Mappings carry confidence; ambiguous and unmapped fields are reported, not dropped.
- Generated Redshift SUPER/PartiQL SELECT + view are syntactically valid against your target table.
- Acceptance tests in [`build-spec/acceptance-tests.md`](build-spec/acceptance-tests.md) pass.
- Deployed to your account via CDK with a least-privilege Bedrock agent role.
