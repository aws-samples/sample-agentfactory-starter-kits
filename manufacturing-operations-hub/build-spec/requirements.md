# Requirements — Manufacturing Operations Hub

The functional + non-functional specification for the agent. A coding agent reads this to build (or re-deploy) the kit; you read it to certify a build matches the spec. Requirements map to acceptance tests in [`acceptance-tests.md`](acceptance-tests.md).

## The problem

Manufacturing teams sit on rich MES data — work orders, OEE, quality control, inventory, downtime — but the people who need it can't query it. Every ad-hoc question becomes a BI ticket with days of latency, and daily production meetings start with 30–60 minutes of manual slide prep pulling the same KPIs. This kit gives the plant a natural-language interface that turns questions into read-only SQL, returns answers with charts, and auto-generates a daily-meeting briefing — grounded in the database, with the SQL shown, and unable to modify anything.

## Functional requirements

Ordered by priority. The agent must:

1. **FR1 — Accept a natural-language question** about manufacturing operations (production, quality, equipment, inventory) and respond with a direct, data-grounded answer.
   - Example: *"Which work centers are behind schedule this week, and what's driving it?"*
   - The agent decomposes multi-step questions into a sequence of database operations as needed.

2. **FR2 — Read the schema before writing SQL.** The agent calls `get_database_schema` (tables, columns, types, foreign keys, sample rows) and grounds every query in the real schema. It must not reference tables or columns that don't exist.

3. **FR3 — Generate and execute read-only SQL.** The agent writes a SELECT query and runs it via `run_sqlite_query`. The query passes through a validation guard that **rejects** any modifying keyword (`insert`, `update`, `delete`, `drop`, `alter`, `create`, `truncate`) before execution.

4. **FR4 — Show the generated SQL** alongside the answer. The query that produced a result is visible to the user so the answer is auditable and a knowledgeable user can spot a wrong assumption.

5. **FR5 — Select an appropriate visualization.** The agent calls `create_intelligent_visualization` to pick a chart suited to the result shape (trend, distribution, comparison, ranking) when a chart adds value.

6. **FR6 — Recover from errors without fabricating.** On a SQL error, the agent surfaces a root cause + recovery suggestions and reformulates or retries. On an empty result, it states that no rows matched and suggests relaxing the most-restrictive constraint. It must never invent rows, machines, work orders, or metrics.

7. **FR7 — Produce a daily production-meeting briefing.** The Production Meeting orchestrator classifies the request, routes single-domain questions to the right specialized sub-agent (production / quality / equipment / inventory), and for a daily briefing calls all four and synthesizes a meeting-ready summary structured as **Critical Issues → Key Metrics → Recommendations**.

8. **FR8 — Pre-compute and cache daily insights.** A scheduled job runs the domain analyses once per period and caches the results so the dashboard loads pre-computed insights quickly, with on-demand refresh available.

9. **FR9 — Be repointable to your operational store.** The data-access layer is DB-agnostic (SQLAlchemy); switching from the bundled SQLite database to your MES/replica is a connection + prompt change, not a rewrite.

10. **FR10 — Support model selection.** The model is configurable (default Claude Haiku 4.5; Nova Lite/Pro and Claude Sonnet also wired) so you can trade latency/cost against reasoning depth.

## Non-functional requirements

| # | Requirement | Target | Why |
|---|---|---|---|
| NFR1 | **Read-only containment** | 100% — no write statement ever reaches the database | The agent analyzes operational data; it must never modify or control the MES/shop floor. Enforced by the keyword guard **and** a read-only DB account. |
| NFR2 | Latency (typical query) | p95 < 10s end-to-end for a single-step query | Interactive feel for supervisors; multi-step analysis may take longer and shows progress. |
| NFR3 | Schema grounding | 100% of executed queries reference only real tables/columns | No hallucinated schema; the agent reads schema first. |
| NFR4 | Answer transparency | Generated SQL shown for every data-backed answer | Auditability + user trust. |
| NFR5 | Cost per query | ~$0.01–0.10 (Haiku 4.5 default) | Drives the ROI envelope. |
| NFR6 | Source-DB safety | Agent connects via a read-only account, pointed at a replica/reporting store for non-trivial volume | Protect the live OLTP system from ad-hoc query load. |
| NFR7 | Security in transit / at rest | TLS to Bedrock and the database; secrets in a secret store, not in code/`.env` for production | Standard data-handling hygiene. |
| NFR8 | Observability | Executed queries logged; for managed delivery, queries/tool-calls/responses to CloudWatch | Reproduce any answer; spot errors and abuse. |
| NFR9 | Single-tenancy | One deployment points at one your operational store | Clear trust boundary; no cross-customer data blending. |
| NFR10 | Availability | Inherits the host's availability (single process for dev; AgentCore Runtime for managed, multi-user) | Match SLA to deployment tier. |

## Inputs

- **Source:** a natural-language question (chat) about production, quality, equipment, or inventory; or a dashboard/briefing request.
- **Format:** chat through the Streamlit UI, or the AgentCore harness API for a managed deployment.
- **Volume:** tens to low-hundreds of queries/day per plant at steady state.
- **Authentication:** AWS IAM at the model/agent layer; your app/SSO authenticates the user upstream; the database connection uses a read-only account.

## Outputs

- **Destination:** rendered in the Streamlit UI (answer + chart + generated SQL + follow-up suggestions), or returned to your app for a managed deployment; the daily briefing renders in the dashboard.
- **Format:** natural-language answer + structured result table + an auto-selected visualization; the briefing is structured text (Critical Issues / Key Metrics / Recommendations).
- **Side effects:** **none on the data** — read-only. Executed queries are logged for audit; no writes to the operational store.

## Dependencies

What your account/environment must support:

- **Amazon Bedrock** access in the deployment region, with the chosen model (Claude Haiku 4.5 cross-region inference profile `us.anthropic.claude-haiku-4-5-20251001-v1:0` by default) enabled.
- **A queryable operational data store** (MES / historian / data warehouse) reachable from the host, ideally a **read replica or reporting store**, with a **read-only** database account for the agent.
- **A host for the agent + UI** — local or SageMaker JupyterLab for the reference; Bedrock AgentCore Runtime (+ CloudWatch) for a managed, multi-user deployment.
- **Python toolchain** — `uv` for dependency management; `make` for the bundled setup/run targets (reference implementation).

## Out of scope

The agent must NOT:

- Write to, update, or delete data in the operational store, or issue any DDL (read-only only).
- Control or actuate the MES, equipment, or any shop-floor system.
- Fabricate data when a query returns nothing or errors — it explains instead.
- Replace your BI/dashboard suite — it complements it with ad-hoc Q&A + the daily briefing.
- Perform document retrieval / RAG — answers come from live SQL, not a knowledge base. (A KB for tribal-knowledge context is a possible extension, not part of this kit.)
- Blend data across multiple customers/tenants.

## Success metrics

The build is working correctly when:

- 100% of executed queries are read-only and schema-grounded (no writes reach the DB; no hallucinated tables/columns)
- A representative set of your real questions across priority domains return correct answers with visible SQL
- The daily briefing runs end-to-end and you agree it reflects your meeting's reality
- Supervisors/engineers self-serve answers that previously required a BI ticket — measurable reduction in ad-hoc request volume and meeting-prep time
- Empty/error cases produce honest "no data / here's why" responses, never fabricated results
