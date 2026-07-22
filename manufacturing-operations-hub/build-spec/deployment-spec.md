# Deployment spec — Manufacturing Operations Hub

What "done" looks like. The coding agent reads this to know when to stop; you read it to verify before bumping `kit.json.status` to `published`.

## Deployment context

- **AWS account:** your account, deployed via your IAM role.
- **Region:** your primary region with Bedrock + the chosen model available (the reference reads `AWS_REGION` / `AWS_PROFILE` from `.env`).
- **Trust boundary:** single-tenant — one deployment points at one your operational data store.
- **Source code location:** the public AWS sample at `https://github.com/aws-samples/industrial-data-store-simulation-chatbot` (MIT). Clone + customize; the kit folder is metadata, not source.
- **Data store:** your MES / historian / data warehouse, reached over TLS via a **read-only** account — ideally a read replica or reporting store, not the live OLTP system.

## Deployment tiers

This is a `managed-harness` kit. Pick the tier that matches your stage:

| Tier | Host | Use when |
|---|---|---|
| **Pilot / demo** | Local workstation or SageMaker JupyterLab running Streamlit (`make start-dashboard`) | Discovery, demos, first connection to your data |
| **Managed (recommended for rollout)** | Strands agent hosted on **Bedrock AgentCore Runtime**; channel = your portal or a hosted UI; **CloudWatch** for logs/metrics | Plant-wide, multi-user, needs per-session isolation + observability |

The agent code (prompt + tools + data layer) is identical across tiers; only the host changes.

## Resources to create

**AI / agent**
- The Strands agent configured with the MES system prompt, the three tools (`run_sqlite_query`, `get_database_schema`, `create_intelligent_visualization`), and the Production Meeting orchestrator + four sub-agents.
- Bedrock model access enabled for `us.anthropic.claude-haiku-4-5-20251001-v1:0` (or the chosen alternative).
- *(Managed tier)* a Bedrock AgentCore Runtime hosting the agent.

**Identity**
- An IAM execution role for the agent host (see IAM below).
- A **read-only database account** for the agent's connection to your operational store (created on your database, not an AWS resource).

**Compute / runtime**
- *(Pilot)* the Streamlit process (local / SageMaker JupyterLab), Python via `uv`.
- *(Managed)* AgentCore Runtime; no servers for you to manage.

**Storage**
- *(Pilot)* the bundled SQLite `mes.db` (demo only) or a direct connection to your store.
- No S3/object storage is required by the core kit (no KB, no document corpus).

**Observability**
- *(Managed)* a CloudWatch log group + a dashboard (queries/day, latency, error rate, model usage). The reference logs executed queries via the `DatabaseManager` logger.

**Networking**
- Connectivity from the agent host to your database (VPC / PrivateLink to the replica, or your standard secured path). Outbound TLS to the Bedrock endpoint.

**Explicitly NOT created**
- **0 Lambda functions** — no action groups; tool logic runs in the agent's own code.
- **0 Knowledge Bases / OpenSearch** — no RAG in the default build.
- **0 write paths** to the operational store.

## IAM permissions

The agent host's execution role needs **only** Bedrock model-invocation permissions:

```
bedrock:InvokeModel                    → on the chosen model / inference-profile ARN
bedrock:InvokeModelWithResponseStream  → on the chosen model / inference-profile ARN
bedrock:ListFoundationModels           → for the model picker in the UI
bedrock:GetFoundationModel             → for model metadata in the UI
```

*(Managed tier additionally)*

```
cloudwatch:PutMetricData                 → on the kit's metric namespace
logs:CreateLogStream + logs:PutLogEvents → on the kit's log group
bedrock-agentcore:*                      → scoped to the kit's AgentCore Runtime resource
```

Scope every `Resource` to the specific model/inference-profile and log/runtime ARNs — no wildcards in production. **No AWS data-plane permissions are required** — the operational database is your and is reached with the read-only DB account, not an IAM grant.

## What you configure during the build

| Config item | Format | Source |
|---|---|---|
| Database connection | SQLAlchemy URL (e.g. `postgresql+psycopg://...`) | Your DBA — read-only account, replica/reporting store |
| AWS region + profile | `.env` (`AWS_REGION`, `AWS_PROFILE`) or role on the host | Your cloud team |
| Model id | `config.py` `default_model` | You, per latency/cost/quality |
| System prompts | `mes_analysis_agent.py` + the 4 sub-agent prompts | You, from your schema + vocabulary |
| Dashboards / KPIs | `production_meeting/dashboards/*` + canned queries in `database.py` | You, from your meeting cadence |
| Daily-analysis schedule | scheduler config (`scripts/` / `daily_analysis_scheduler.py`) | Your ops team |

## What's pre-built (ships in the reference)

- Both agent packages (MES Insight Chat + Production Meeting orchestrator + 4 sub-agents)
- The three tools incl. the SELECT-only guard and intelligent error analyzer
- The DB-agnostic SQLAlchemy data layer + canned dashboard queries
- The Streamlit UI (chat + dashboard, action tracker, meeting notes, reports)
- The synthetic MES data generator + educational text-to-SQL notebook
- The daily-analysis scheduler + cache manager
- `Makefile` targets (`setup`, `setup-db`, `start-dashboard`, `run-analysis`, `test`)

## Cost expectations

| Driver | Typical range |
|---|---|
| Bedrock invocations (Haiku 4.5 default) | ~$0.01–0.10 per query |
| Agent/UI compute (pilot small host or SageMaker; managed = AgentCore Runtime) | ~$50–400/mo |
| CloudWatch (managed tier) | ~$10–80/mo |
| Daily pre-compute batch | ~$1–5 per run |
| **All-in (single plant, typical)** | **~$3K–12K/year**, Bedrock-dominated |

## Pre-deployment checklist

- [ ] Bedrock access confirmed in-region; chosen model enabled
- [ ] Your operational store identified; **read replica / reporting store** available
- [ ] **Read-only** DB account provisioned for the agent
- [ ] Network path from the agent host to the database confirmed
- [ ] IAM execution role created, scoped to the model (and log/runtime ARNs for managed)
- [ ] Secrets handling agreed (secret store for production, not `.env`)

## Post-deployment validation

- [ ] `get_database_schema` returns your real schema
- [ ] Read-only guard rejects a write statement before execution (T5)
- [ ] Representative questions across priority domains return correct, schema-grounded answers with visible SQL (T1–T4)
- [ ] Daily briefing runs end-to-end on your data
- [ ] Acceptance tests in [`acceptance-tests.md`](acceptance-tests.md) pass
- [ ] (Managed) CloudWatch dashboard renders with non-zero metrics from the smoke test

## Day-2 operations (yours to run)

- Maintain the read-only DB account + the replica/reporting store the agent reads
- Tune prompts/dashboards as the schema or meeting cadence evolves
- Monitor Bedrock spend + query latency; adjust model choice if needed
- Rotate DB credentials per your policy
- Extend to additional plants/domains, or promote from the pilot host to AgentCore Runtime
