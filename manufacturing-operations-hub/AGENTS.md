# AGENTS.md — Manufacturing Operations Hub

> **Audience:** Coding agents (Kiro, Claude Code, Codex, Cursor) re-deploying or extending this kit in a your AWS account.
> **Status:** Path A — working code exists at `https://github.com/aws-samples/industrial-data-store-simulation-chatbot` (MIT-licensed AWS sample). The GitHub repo is the source of truth; this kit folder is catalog metadata, not the agent's source.

## What this is

A natural-language analytics agent over manufacturing (MES) data, built on the **Strands Agents SDK** and **Amazon Bedrock**, with a **Streamlit** UI. Two surfaces, two agent packages:

- **MES Insight Chat** (`app_factory/mes_agents/`) — a single multi-domain analysis agent using the Strands agent-as-tools pattern. System prompt makes it a manufacturing expert across production, quality, equipment, and inventory. Three tools: `run_sqlite_query`, `get_database_schema`, `create_intelligent_visualization`.
- **Daily Production Meeting** (`app_factory/production_meeting_agents/`) — an orchestrator (`production_meeting_analysis_tool`) that classifies a query and routes to four specialized sub-agents (`production_analysis_tool`, `quality_analysis_tool`, `equipment_analysis_tool`, `inventory_analysis_tool`). A "daily briefing" calls all four and synthesizes a meeting-ready summary.
- **Shared data layer** (`app_factory/shared/database.py`) — a `DatabaseManager` built on SQLAlchemy. DB-agnostic by design: SQLite (`mes.db`) today, written so you can repoint to PostgreSQL with connection changes only.

The pattern is **schema-first text-to-SQL**: the agent calls `get_database_schema` first, then writes a SQL query, runs it read-only, and returns results with an auto-selected chart and error-recovery suggestions when a query fails.

## Build-level guidance

This kit is `managed-harness`. The value is entirely in (1) the system prompt, (2) the three tools, and (3) the read-only data layer — not in custom orchestration infrastructure. The reference implementation runs the Strands agent inside a Streamlit process (locally or on SageMaker JupyterLab) that invokes Bedrock directly. For a managed, self-hosted delivery, host the **same** Strands agent on **Bedrock AgentCore Runtime** and front it with your channel of choice — the prompt + tools are unchanged.

Do not promote this to `custom-iac` unless a specific business demands an audited CloudFormation stack with Bedrock Agents + action-group Lambdas. That is a different kit, not a different build of this one — the text-to-SQL tools live more cleanly in the agent's own tool code than in Lambda action groups.

## Where to read first

Read the source in this order — it is well-documented:

1. `README.md` (source) — full setup, both surfaces, the architecture sequence diagram, AWS config
2. `app_factory/mes_agents/mes_analysis_agent.py` — the MES Insight Chat agent + its system prompt
3. `app_factory/mes_agents/tools/database_tools.py` — `run_sqlite_query` (and the `_validate_query` read-only guard) + `get_database_schema`
4. `app_factory/shared/database.py` — the SQLAlchemy `DatabaseManager`, schema introspection + caching, parameterized canned queries
5. `app_factory/production_meeting_agents/production_meeting_agent.py` — the orchestrator + four specialized sub-agents + query classifier
6. `app_factory/data_generator/sqlite-synthetic-mes-data.py` + `data_pools.json` — the synthetic schema and simulation patterns (your map of the demo data)
7. `architecture/architecture.md` (this kit) — high-level overview for catalog readers
8. `build-spec/` (this kit) — what to verify when re-deploying

## Re-deploying for another tenant

The source works as shipped. The customization story for a new deployment:

1. **Database connection** — In `app_factory/shared/database.py`, repoint `DatabaseManager` from `sqlite:///mes.db` to your operational store (e.g. `postgresql+psycopg://...`). The layer already uses SQLAlchemy `engine` + `inspect()` + parameterized `text()`, so schema introspection and the canned queries are portable. Validate date-handling helpers in `app_factory/shared/db_utils.py` against the target dialect.
2. **System prompt** — In `app_factory/mes_agents/mes_analysis_agent.py` (`_get_system_prompt`), replace the e-bike/MES framing with your domain, table names, and KPI vocabulary. Do the same for the four sub-agent prompts in `production_meeting_agent.py`.
3. **Dashboards** — `app_factory/production_meeting/dashboards/` (equipment, inventory, production, productivity, quality, root_cause, weekly) are Streamlit modules backed by the canned queries in `DatabaseManager`. Adjust the queries + tabs to your schema and meeting cadence.
4. **Model** — `app_factory/mes_agents/config.py` and `app_factory/production_meeting_agents/config.py` set `default_model`. Default is `us.anthropic.claude-haiku-4-5-20251001-v1:0`; Nova Lite/Pro and Claude Sonnet are in `SUPPORTED_MODELS`. Pick per your latency/cost/quality needs and Bedrock access.
5. **Demo data** — `app_factory/data_generator/` exists for demos and notebooks. Once the live connection is in place, it is not part of the production path.

## What you're NOT building from scratch

The whole app already works. You're repointing + re-tuning it, not rebuilding it. Specifically:

- Don't replace Strands Agents SDK with a hand-rolled agent loop
- Don't replace the SQLAlchemy data layer with raw `sqlite3` / driver-specific code — that breaks the DB-agnostic portability that makes you migration cheap
- Don't migrate Streamlit to a custom React app for v1 — Streamlit is a feature for fast internal tooling, not a bug
- Don't add an ORM-level write path or "let the agent fix the data" capability

## Non-negotiables

- **Read-only, SELECT-only.** `run_sqlite_query` runs `_validate_query`, which rejects `drop`, `delete`, `truncate`, `alter`, `create`, `insert`, and `update`. Keep this guard. The agent reads operational data; it never writes to or controls the MES or shop floor. If you repoint to a new database, connect with a **read-only database user** as defence-in-depth behind the keyword guard.
- **Schema-first.** The agent must call `get_database_schema` before writing SQL, and write queries grounded in the real schema — never invent table or column names. The system prompt and tool descriptions enforce this ordering; preserve it.
- **Show the SQL.** The generated query is surfaced to the user. Don't hide it — visible SQL is what makes an answer auditable and reproducible, and it's how a power user catches a wrong assumption.
- **Don't fabricate data.** On an empty result or an error, the agent explains why and suggests a reformulation (see `error_handling.py`). It must not invent plausible-looking numbers, machines, or work orders.
- **Parameterized queries for canned dashboard logic.** The `DatabaseManager` helper queries use bound parameters (`:start_time`, etc.). Keep that pattern for any new canned query.

## Defaults

- **Model:** `us.anthropic.claude-haiku-4-5-20251001-v1:0` (cross-region inference profile — note the `us.` prefix; it is required for the inference profile and is not optional).
- **Region:** your primary region with Bedrock + the chosen model available (source defaults to whatever `AWS_REGION` / `AWS_PROFILE` are set in `.env`).
- **Runtime:** local or SageMaker JupyterLab for the reference; Bedrock AgentCore Runtime for a managed deployment. Python managed with `uv`; common tasks in the `Makefile` (`make setup`, `make setup-db`, `make start-dashboard`, `make run-analysis`).
- **IAM:** the agent's role needs only `bedrock:InvokeModel`, `bedrock:InvokeModelWithResponseStream`, `bedrock:ListFoundationModels`, `bedrock:GetFoundationModel`. Scope `Resource` to the chosen model/inference-profile ARNs. No data-plane AWS permissions are needed — the operational database is your.

## Things to confirm before customizing

- Which operational data store? (MES vendor / historian / data warehouse — drives the connection + any SQL-dialect adjustments)
- Is a **read-only** database account available for the agent to connect with?
- Which domains matter most? (Production / quality / equipment / inventory — drives prompt + dashboard focus)
- What is the daily-meeting cadence and who attends? (Drives the briefing format and which dashboards lead)
- Where will users reach the agent? (Internal Streamlit app, an existing portal, a chat surface — drives the host/channel decision)
- Latency vs. cost vs. quality preference (drives Haiku vs. Sonnet vs. Nova)

## When to pause and reassess

- You want the agent to **write back** to the MES, adjust schedules, or take shop-floor actions (this kit is read-only analytics — that's a different threat model and a different kit)
- You have no queryable operational store (data is only in PLCs / paper / spreadsheets — a data-foundation engagement comes first)
- You need fully on-prem inference with no cloud connectivity (kit is Bedrock-native)
- The target database is large enough that ad-hoc agent-written SQL could impact the production OLTP system (recommend pointing at a read replica or reporting store, not the live transactional DB)

## Done definition

Re-deployment is done when:

- The agent connects to your database through a **read-only** account and `get_database_schema` returns your real schema
- The read-only guard is verified: a query containing `UPDATE`/`DELETE`/`DROP` is rejected before execution (acceptance test T5)
- A representative set of natural-language questions across your priority domains return correct, schema-grounded answers with visible SQL (acceptance tests T1–T4)
- The Daily Production Meeting briefing runs end-to-end and produces a meeting-ready summary from your data
- A production supervisor or analyst at you run a full session unassisted
- You've recorded the deployed source location, who certified the build, and when

## When you finish a build

Record where your implementation lives (repo URL and ref) and who certified it. Bump `kit.json.status` from `draft` to `published` once you have reviewed the build against the acceptance tests.
