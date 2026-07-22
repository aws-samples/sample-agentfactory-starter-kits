# Architecture decisions — Manufacturing Operations Hub

Why this kit made each call, and the choices a coding agent should not undo without re-opening the decision.

## AD1 — Build level: Managed Harness (Strands Agents SDK + Streamlit)

**Decision:** Ship as `managed-harness`. The value is the system prompt + the three tools + the read-only data layer.

**Why:** There is no custom orchestration that justifies a CloudFormation stack with Bedrock Agents and action-group Lambdas. The reference implementation runs a Strands Agents SDK agent inside a Streamlit process that invokes Bedrock directly; the same prompt + tools host cleanly on Bedrock AgentCore Runtime for a managed, multi-user deployment. Either way you own the prompt, the tool list, and the database connection — exactly the managed-harness shape.

**Alternatives considered:** `custom-iac` (Bedrock Agents + action-group Lambdas) — rejected because the text-to-SQL tools live more cleanly in the agent's own tool code than in Lambdas you must audit; promote to a separate custom-iac kit only if a specific business demands an audited stack. `managed-agents-openai` — no reason; the kit runs well on Bedrock-served Claude/Nova and needs no OpenAI-specific capability.

**What this means for the build:** Don't hand-roll the agent loop or build a CFN stack. Configure prompt + tools + model; host on AgentCore Runtime when you need managed scaling.

## AD2 — Model: Claude Haiku 4.5 (cross-region inference), pluggable

**Decision:** Default to `us.anthropic.claude-haiku-4-5-20251001-v1:0`; keep Nova Lite/Pro and Claude Sonnet wired in `config.py`.

**Why:** Text-to-SQL over a known schema is mostly structured reasoning + tool use, which Haiku 4.5 handles at low latency and cost — the right default for an interactive plant tool. Deeper, multi-step "why" investigations benefit from Claude Sonnet; cost-sensitive or high-volume deployments can drop to Nova. The `us.` prefix denotes the cross-region inference profile and is **required** — not optional.

**Alternatives considered:** Sonnet-by-default — rejected on cost/latency for the common case; make it a per-deployment override instead.

**What this means for the build:** Keep model selection in `config.py`; default Haiku 4.5, document how to switch. Preserve the `us.` inference-profile prefix.

## AD3 — Schema-first text-to-SQL (no hand-built semantic layer)

**Decision:** The agent calls `get_database_schema` first and writes SQL grounded in the live schema, rather than relying on a maintained semantic model.

**Why:** It keeps the kit portable — repointing to a new database doesn't require rebuilding a semantic layer; the agent re-reads the new schema. Schema introspection is cached (5 min) so it's cheap on warm paths. The tool descriptions and system prompt enforce the "schema before query" ordering.

**Alternatives considered:** A curated semantic layer / metrics catalog — higher answer precision but high per-deployment build + maintenance cost; revisit only for very large or ambiguous schemas.

**What this means for the build:** Preserve the schema-first ordering. For very wide schemas, scope `get_database_schema` to relevant tables or summarize the schema in the prompt rather than abandoning the approach.

## AD4 — Read-only by construction

**Decision:** The agent issues SELECT only. `run_sqlite_query` runs `_validate_query`, which rejects `insert`, `update`, `delete`, `drop`, `alter`, `create`, and `truncate` before execution. Deployments also connect with a read-only database account.

**Why:** This is the kit's core safety property and its main objection-handler with manufacturing teams ("an AI is not touching our MES"). Defence in depth: the keyword guard catches it in the app; the read-only DB grant catches anything the guard misses. There is no business reason for this analytics agent to write.

**Alternatives considered:** Allowing scoped writes (e.g. logging action items back to the DB) — rejected for v1; action items live in the app layer, not via agent-issued SQL.

**What this means for the build:** Never weaken or bypass the guard. When repointing to a new DB, provision a read-only user. Any write-back feature is out of scope and changes the threat model.

## AD5 — DB-agnostic data layer (SQLAlchemy)

**Decision:** All database access goes through a SQLAlchemy `DatabaseManager` (`engine` + `inspect()` + parameterized `text()`), not driver-specific code.

**Why:** SQLite ships for the demo, but the kit's purpose is to repoint at your store. SQLAlchemy makes that a connection-string change; schema introspection and the canned dashboard queries port across dialects. Canned queries use bound parameters, which is both safe and portable.

**Alternatives considered:** Raw `sqlite3` — simpler for the demo but would force a rewrite per deployment; rejected.

**What this means for the build:** Keep new data access inside `DatabaseManager` and parameterized. Validate dialect-specific bits (date math in `db_utils.py`) against the target database; don't introduce raw driver calls.

## AD6 — Two surfaces, agent-as-tools, with a routing orchestrator

**Decision:** Keep the two packages: a single multi-domain `MES Analysis Agent` for ad-hoc chat, and a `Production Meeting` orchestrator that classifies a query and routes to four specialized sub-agents (production / quality / equipment / inventory), fanning out to all four for a daily briefing.

**Why:** Ad-hoc analysis benefits from one agent with broad context; the daily meeting benefits from focused, domain-expert sub-agents whose narrower prompts produce sharper, more consistent briefings. The agent-as-tools pattern keeps each agent independently testable and swappable.

**Alternatives considered:** One mega-agent for everything — rejected; the briefing quality and per-domain prompt tuning are better with specialization. A hard-coded query pipeline — rejected; loses the natural-language flexibility.

**What this means for the build:** Preserve the orchestrator + classifier + four sub-agents. Re-tune the per-domain prompts and routing keywords for you; don't collapse them into one prompt.

## AD7 — No RAG / knowledge base in the core path

**Decision:** Answers come from live SQL against structured data, not document retrieval. No Bedrock Knowledge Base / OpenSearch in the default build.

**Why:** The questions are quantitative and live ("yesterday's defect rate by line"), which SQL answers exactly and freshly; a vector store would add cost and a staleness/grounding problem without improving these answers. It also keeps run cost low (no OpenSearch floor).

**Alternatives considered:** Adding a KB for tribal-knowledge / SOP context — a reasonable **extension** if you want qualitative context alongside the numbers, but not core; add it as a separate tool if needed.

**What this means for the build:** Don't add a KB by default. If a you want document context, add it as an additional tool without disturbing the text-to-SQL path.

## AD8 — Host: local/SageMaker for the reference, AgentCore Runtime for managed delivery

**Decision:** Run the Strands agent + Streamlit locally or on SageMaker JupyterLab for development/demo; host the same agent on Bedrock AgentCore Runtime (+ CloudWatch) for a managed, multi-user deployment.

**Why:** The reference is optimized for fast standup and demos. A production deployment serving many concurrent plant users wants per-session isolation, managed scaling, and centralized observability — which AgentCore Runtime provides without changing the prompt or tools.

**Alternatives considered:** ECS/EKS-hosted Streamlit — viable, but more infra for you to own than AgentCore for the same outcome. Leaving it as a single Streamlit process in production — fine for a pilot, not for plant-wide rollout.

**What this means for the build:** Demo on the simple host; plan the AgentCore Runtime move when volume/concurrency justifies it. The agent code is the same.

## Open architecture questions

Decide these deliberately before building:

- **Live OLTP vs. read replica.** For anything beyond a pilot, point the agent at a replica/reporting store, not the live transactional MES DB. Confirm you have (or can stand up) one.
- **Schema scoping for wide databases.** Large MES schemas inflate the introspection payload. Decide whether to scope `get_database_schema` to relevant tables or summarize the schema in the prompt.
- **Channel surface.** Internal Streamlit app vs. embedding the agent in your existing operations portal vs. a chat surface — drives the host/integration decision.
- **Conversation memory.** The reference keeps a per-day persistent agent for follow-up context. Decide retention/scoping for multi-user deployments (per-session vs. shared).
