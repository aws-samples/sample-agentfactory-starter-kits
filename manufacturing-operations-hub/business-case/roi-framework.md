# Business Case — Manufacturing Operations Hub

## What problem this solves

Two things slow down a plant's daily rhythm, and both are about access to data the plant already has.

**The BI bottleneck.** A plant's MES, historian, and quality systems are full of answers, but the people who need them — production supervisors, quality engineers, maintenance leads — can't get at them directly. Every "why did line 3 fall behind yesterday?" or "which supplier's parts correlate with this defect spike?" becomes a request to a small, overloaded data/BI team. The answer comes back days later, after the shift it was about, so most questions simply don't get asked.

**Daily-meeting slide prep.** Lean/standup meetings start with someone spending 30–60 minutes every morning pulling the same KPIs into the same slides. By the time the meeting starts, a third of it is gone to reading numbers aloud instead of solving the problems behind them.

This kit addresses both. The **MES Insight Chat** lets any authorized user ask in plain English and get a cited, chart-backed answer in seconds — grounded in a read-only SQL query they can see. The **Daily Production Meeting** dashboard pre-computes the KPIs and an AI briefing, so the meeting opens with the numbers already on screen and the time goes to actions.

The result: shorter, sharper daily meetings; self-service answers for the people closest to the work; and a small data team freed from a queue of one-off report requests.

## ROI math (template)

ROI here is **time reclaimed** (meeting prep + analyst/BI request handling) plus the harder-to-quantify value of faster, better-informed operational decisions. Gather the inputs below during discovery; don't ship you a number you didn't build with them.

### Inputs to gather

| Input | Where it comes from | Example placeholder |
|---|---|---|
| Daily meetings per day across plants/lines | Ops leadership | `M` meetings |
| Prep time per meeting today | The person who builds the slides | `P` minutes |
| Ad-hoc MES/BI requests per week | Data/BI team queue | `R` requests/week |
| Avg analyst time per request (incl. context-switch) | BI team | `T` minutes |
| Loaded hourly cost — supervisor / analyst | Finance | `$S` / `$A` per hour |
| Working days per year | — | ~250 |

### Output formulas

```
Annual meeting-prep time reclaimed
   = M meetings/day × P min × 250 days ÷ 60 × $S/hr × (fraction eliminated)

Annual BI-request time reclaimed
   = R requests/week × T min × 52 ÷ 60 × $A/hr × (fraction self-served)

Annual value (time)  = meeting-prep reclaimed + BI-request reclaimed
Operational-decision value = qualified separately (faster issue resolution,
   fewer repeat defects, better OEE) — capture as a pilot outcome, don't pre-claim
ROI multiple = Annual value ÷ Annual AWS cost
```

### Worked example — **illustrative only, not a guarantee**

> These are placeholder numbers to show the shape of the math. Replace every value with your real inputs from discovery before presenting anything.

Assume a mid-size plant: `M`=3 daily meetings, `P`=45 min prep each, supervisor loaded cost `$S`=$70/hr; plus `R`=40 ad-hoc BI requests/week at `T`=30 min each, analyst loaded cost `$A`=$60/hr.

- Meeting prep: 3 × 45 min × 250 ÷ 60 × $70 × 70% eliminated ≈ **$55,000/yr**
- BI requests: 40 × 30 min × 52 ÷ 60 × $60 × 60% self-served ≈ **$37,000/yr**
- Illustrative annual time value ≈ **~$92,000/yr** (before any operational-decision upside)

Against an illustrative AWS run cost of **~$3K–12K/yr** (see below), that's a rough **~8–30x** return on AWS spend on reclaimed time alone — and the bigger prize (faster issue resolution, fewer repeat defects, OEE improvement) is the pilot's job to measure. **Validate with your own numbers.**

## Cost drivers

| Component | What drives it | Typical range |
|---|---|---|
| **Bedrock invocations** | Queries/day × tokens/query × model. Claude Haiku 4.5 is the low-cost default; Claude Sonnet costs more per query for deeper reasoning. | ~$0.01–0.10 per query |
| **Agent / UI compute** | Hosting the Strands agent + Streamlit. A small always-on host (or SageMaker JupyterLab for dev); AgentCore Runtime for managed, per-session scaling. | ~$50–400/mo |
| **CloudWatch (managed delivery)** | Log + metric volume for the hosted agent. | ~$10–80/mo |
| **Daily analysis pre-compute** | The scheduler runs a batch of model calls once/day to cache insights. | ~$1–5 per run |
| **Operational database** | Your existing MES/replica — **not a new AWS cost** for this kit. | n/a (yours to run) |

Indicative all-in AWS run cost at typical single-plant volume: **~$3K–12K/year**, dominated by Bedrock invocations. There is no Knowledge Base / OpenSearch cost (no RAG) and no Lambda cost (no action groups) in this kit.

## Common objections + responses

| Objection | Response |
|---|---|
| "We don't want an AI touching our MES / shop floor." | It can't. The kit is read-only by construction — a query guard rejects INSERT/UPDATE/DELETE/DROP/ALTER/CREATE/TRUNCATE before anything reaches the database, and we connect with a read-only DB account. It reads and explains; it never writes or controls equipment. Verifiable in acceptance test T5. |
| "How do we know the SQL is right / the answer isn't hallucinated?" | Every answer shows the generated SQL and is grounded in your real schema (the agent reads the schema first). A power user can read the query; on an empty or failed result the agent says so and suggests a fix rather than inventing numbers. |
| "Our data isn't in SQLite — it's in [historian / Oracle / SQL Server / Snowflake]." | The synthetic SQLite DB is just the demo. The data layer is SQLAlchemy and DB-agnostic; repointing it is a connection change plus prompt re-tuning, not a rewrite. Confirm SQL-dialect specifics during discovery. |
| "Will ad-hoc agent queries slow down our production database?" | Point the agent at a read replica or reporting store, not the live OLTP system, and use a read-only user. We scope this in the design session. |
| "We already have Tableau / Power BI / Grafana dashboards." | Those answer the questions someone built a dashboard for. This answers the ad-hoc 'why' questions in between — and it feeds the daily meeting an auto-generated briefing instead of hand-built slides. It complements BI, it doesn't replace it. |
| "Our MES vendor has an analytics module." | Vendor modules are scoped to your product and your schema. This is a portable pattern across your operational stores, in your AWS account, that you own and tune. |
| "What does it cost to run?" | Roughly $3K–12K/year in AWS at single-plant volume, dominated by Bedrock calls. ROI on reclaimed time alone is typically high single-digit to low double-digit multiples — we'll build the number with your inputs. |

## Time-to-value benchmarks

| Milestone | Target |
|---|---|
| Demo on synthetic e-bike data in front of stakeholders | Day 0–1 |
| Connected (read-only) to your MES / replica | Day 2–3 |
| System prompt + key dashboards re-tuned to your schema | Day 3–4 |
| Acceptance tests pass against real data; first supervisor self-serves | Day 4–5 |
| First daily meeting run off the dashboard instead of slides | Week 2 |
| Captured outcome metrics (prep time saved, requests self-served) | Week 4–6 |

## Differentiation vs. competitors

- vs. **BI dashboards (Tableau / Power BI / Grafana / Looker):** Dashboards answer pre-built questions; this answers the ad-hoc ones and writes the daily briefing. Position as complementary — it often sits next to existing BI, not instead of it.
- vs. **MES-vendor analytics modules (e.g. built-in reporting in your MES):** Vendor-locked to one schema and product. This kit is a portable, you own pattern across operational stores, tunable to your vocabulary, running in your AWS account.
- vs. **Generic "ask your database" SaaS text-to-SQL tools:** Those send schema/queries to a third-party SaaS and aren't manufacturing-aware. This runs in your account on Bedrock, is read-only by construction, and ships with manufacturing-domain prompts + the four production-meeting sub-agents.
- vs. **Build-it-in-house:** Months of engineering to get to a working text-to-SQL agent with error recovery, visualization, and a meeting workflow. This is a working AWS sample you repoint in days.
- **When this kit is *not* the answer:** you have no queryable operational store (data lives in PLCs/paper/spreadsheets — they need a data-foundation engagement first), or they want write-back / shop-floor control (different threat model, different kit).

## Pipeline opportunity

- **Initial deployment:** Bedrock consumption + the hosting/compute + the build effort, per plant.
- **Expansion:** additional plants/lines; additional operational stores (quality, maintenance, supply chain); promoting from a single Streamlit app to an AgentCore-hosted, multi-user deployment.
- **Platform pull-through:** AgentCore Runtime, CloudWatch, and (if you later want tribal-knowledge context) Knowledge Bases + OpenSearch — incremental consumption per deployment.
