# ROI Framework — XML Schema Inference Agent

> The numbers here are **templates and illustrative examples** — real figures come from your own discovery, not from this doc.

## What problem this solves

Teams that ingest semi-structured data from many external sources hit the same wall: every source ships its own XML/JSON shape, with no XSD and no documentation. To use the data, an engineer has to manually trace nested structures, figure out where each business field lives, write extraction logic (XPath, Spark UDFs, custom parsers), and maintain it forever. The cost shows up in two places — **onboarding latency** (days per new source before the data is usable) and **maintenance drag** (a growing pile of brittle per-source jobs that break on every schema change).

For the organization this kit was built with, this was 2–3 engineer-days to onboard each new lender's credit-decision traces, multiplied across a large customer base, plus repeated re-mapping whenever an existing source changed its structure. Prior attempts with Snowflake, Databricks, and Iceberg+Glue+Athena stalled on the nested/repeating-element parsing problem specifically. This kit replaces per-source hand-mapping with one agent that discovers the schema, maps fields to standard logical names with confidence, and generates the Redshift SQL — so the engineer reviews and approves instead of reverse-engineering from scratch.

## ROI math (template)

**Inputs to gather in discovery:**

| Input | Symbol | Example (illustrative, research-backed) | Basis |
|---|---|---|---|
| New sources / customers onboarded per year | `N` | 100 | Within kit's "tens to hundreds" ideal-customer profile; conservative mid-point |
| Engineer-days per onboarding today | `d` | 2.5 days | Baseline reported by the originating team (2–3 engineer-days/source); anecdotal, no public URL |
| Onboarding-time reduction with the agent | `Δo` | 75% | AWS Rhapsody case study: Bedrock data-integration agent cut connectivity setup 16h→4h (75%) and build-and-test ~80%; we take the more conservative 75% |
| Existing sources with schema changes per year | `C` | 150 | Discovery input; illustrative |
| Engineer-days per manual re-mapping | `r` | 0.5 day | Discovery input; illustrative |
| Re-mapping reduction with re-run + diff | `Δr` | 75% | Same Rhapsody basis (re-run + diff vs. hand-editing) |
| Fully-loaded data-engineer cost / day | `c` | ~$635 | BLS data-scientist median $112,590/yr (May 2024) × 1.3 benefits/overhead ÷ 230 working days |

**Output formulas:**

```
Onboarding days saved / yr   = N × d × Δo
Re-mapping days saved / yr   = C × r × Δr
Total engineer-days saved/yr = onboarding saved + re-mapping saved
Annual benefit ($)           = total engineer-days saved × c
```

**Worked example (Illustrative, research-backed — not a guarantee):**

```
Onboarding days saved   = 100 × 2.5 × 0.75   = 187.5 days/yr
Re-mapping days saved   = 150 × 0.5 × 0.75   = 56.25 days/yr
Total engineer-days     = ~244 days/yr   (≈ 25–30 hours/week of freed capacity)
Annual benefit          = 244 × $635          ≈ $155,000/yr
```

Sensitivity: at the high end of the ideal-customer profile (more sources, a senior-engineer ~$900 loaded day rate, or the 80% Rhapsody figure) the benefit approaches ~$285K/yr. Run the same formulas with your real numbers. Treat the onboarding-reduction percentage conservatively — the agent gets the field inventory and a confidence-scored draft mapping in minutes, but a human still reviews, so model the *review* time honestly rather than assuming zero engineer involvement.

## Cost worked example (Illustrative — computed from AWS pricing)

This is a **run-at-onboarding** tool, not a per-transaction agent — cost scales with onboardings and re-mappings, not steady-state volume.

```
Agent runs / yr         = 100 onboardings + 150 re-mappings   = 250 runs/yr
Per run (Claude Sonnet 4): ~150K input tokens × $3/1M         = $0.45
                           ~15K output tokens × $15/1M        = $0.225
                           ≈ $0.68/run  (a few tool-calling turns: analyze + map + SQL)
Bedrock / yr            = 250 × $0.68                          ≈ $170/yr
Lambda + S3 + CloudWatch (short-lived tools, low storage)     ≈ $20–50/yr
Redshift Serverless validation layer (optional, sparse use)   ≈ $300–600/yr  (≈ $0 on an existing cluster)
---------------------------------------------------------------------------
Total annual AWS cost                                         ≈ $600–$1,200/yr
```

```
Multiple = $155,000 / ~$1,000   ≈ 150×   (range >100×)
```

The multiple is large because the compute is genuinely tiny — there is no OpenSearch vector store, no Guardrails, and no high-volume inference path here. The honest takeaway is **not** "150× return" as a headline; it's that **the AWS spend is a rounding error against the engineer-time saved**, and the real constraint on value capture is human review capacity, not cost.

## Cost drivers

| Driver | Notes | Typical range |
|---|---|---|
| Bedrock (Claude Sonnet 4) | Per onboarding: a few tool-calling turns over a trace batch (analyze + map + SQL). Scales with sources onboarded and traces per batch, not with steady-state volume | $ per onboarding — model from token sizes × turns |
| AWS Lambda | Tools Lambda + XML→JSON parser invocations; short-lived, 512 MB | Negligible to low |
| Amazon S3 | Raw + parsed trace storage | Low; scales with retained traces |
| Amazon Redshift Serverless | Only if the query/validation layer is deployed; charged for RPU-hours when queries run | Optional — model per usage |
| Kinesis | Only if streaming ingestion is used instead of S3 PutObject | Optional |
| CloudWatch | Lambda + agent logs | Low |

Cost scales with **how many sources you onboard and re-map**, not with day-to-day decision volume — this is a tool you run at onboarding time and on schema changes, not on every transaction. That makes spend predictable and bursty rather than continuous.

## Common objections + responses

- **"We already have a parsing pipeline / Spark jobs."** That's exactly the maintenance cost this removes. Keep the runtime pipeline; use the agent to *generate and update* the mappings the pipeline runs, instead of hand-writing them per source.
- **"Snowflake/Databricks/Athena couldn't handle our nested XML."** This kit was built precisely because those POCs stalled on repeating-element parsing. The parser collapses repeating tags into arrays and the agent detects arrays at the schema level across a batch, not per trace.
- **"Will it map fields wrong and corrupt our data?"** Every mapping has a confidence score, ambiguous and unmapped fields are reported rather than guessed, and a data engineer approves before anything reaches production. It's a drafting accelerator, not an autonomous writer.
- **"Everything in our XML is a string — how does it know types?"** Type inference is rule-based on value patterns (zero-padded numerics stay strings, `Y`/`N`/`PASS`/`FAIL` → boolean, ISO dates → date) and runs in the tool code, not the model's imagination.
- **"How does it handle a source changing its schema?"** Re-run the agent on new traces and diff against the existing mapping; new or moved fields surface for review instead of silently breaking the pipeline.
- **"What about PII in the traces?"** The agent reasons over structure, not values; mask or tokenize PII before parsing. Everything runs single-tenant in your account.
- **"How long to prove it on our data?"** A focused engagement (12–18 engineering hours over ~3–5 days) gets the field dictionary customized and the agent running on two of your real sources.

## Time-to-value benchmarks

| Milestone | Target |
|---|---|
| Local-mode demo on your sample traces (no AWS) | Day 1 |
| Standard-field dictionary + path patterns tuned to your domain | Day 2–3 |
| CDK deployed + Bedrock Agent created with action group in your account | Day 3–4 |
| Two real sources mapped, unified, and SQL validated; acceptance tests passed | Day 4–5 |

## Differentiation vs. competitors

- **Lake-house schema tools (Snowflake, Databricks Auto Loader, Glue crawlers):** good at well-behaved or self-describing formats; they stall on deeply nested, repeating, all-string XML with no schema — the exact case this targets. Position as complementary: the agent produces the mapping these tools then consume.
- **Hand-written parsers / XPath / Spark UDFs:** the status quo. The agent doesn't replace the runtime; it removes the days of manual reverse-engineering and the per-source maintenance.
- **Generic "ask an LLM about this XML" prompting:** no deterministic field inventory, no confidence scoring, no reproducible SQL, no array detection across a batch. The tool layer is the differentiator — the model orchestrates, the tools guarantee.
- **When this kit is NOT the answer:** sources already share a stable XSD (nothing to infer), you want fully autonomous mapping into production with no review, or there are too few sources to pay back the build. Disqualify early (see `kit.json`).

## Sources

All figures are **illustrative and research-backed** — they are defensible from the sources below, not guarantees. Validate every number against your own discovery data.

- **AWS Rhapsody case study** — https://aws.amazon.com/solutions/case-studies/rhapsody-case-study/ — An Amazon Bedrock–based AI agent (Axon) for healthcare data integration cut requirements-clarification and build-and-test effort by ~80% and reduced connectivity setup from ~16 hours to 4 hours (75%). Backs the 75–80% onboarding-time-reduction (`Δo`/`Δr`) assumption for an LLM-driven schema-mapping agent.
- **U.S. Bureau of Labor Statistics, Occupational Outlook Handbook — Data Scientists** — https://www.bls.gov/ooh/math/data-scientists.htm — Median annual wage for data scientists was $112,590 in May 2024. Backs the ~$635 fully-loaded day rate (× 1.3 benefits/overhead ÷ 230 working days). (BLS SOC 15-2051; a defensible public proxy for a data/integration engineer.)
- **AWS Bedrock pricing** — https://aws.amazon.com/bedrock/pricing/ — Claude Sonnet 4 on-demand $3.00/1M input tokens, $15.00/1M output tokens. Backs the per-run Bedrock cost (~$0.68/run).
- **AWS Redshift pricing** — https://aws.amazon.com/redshift/pricing/ — Redshift Serverless RPU-hour pricing for the optional validation/query layer; billed only while queries run. Backs the optional ~$300–600/yr cost line (≈$0 on an existing cluster).
- **Data-mapping share of integration effort** (corroborating, not load-bearing) — https://unogeeks.com/oracle-integration-cloud-mapping/ — Industry write-ups commonly cite ~70% of integration effort going into data transformation/mapping rather than connectivity, supporting why removing manual mapping is the high-leverage saving. Treated as context only; the savings math relies on the Rhapsody and BLS sources above.

**Inputs that are NOT publicly sourced** (mark as you provide / internal estimates, no URL): the 2–3 engineer-days-per-onboarding baseline (reported by the originating team), sources-onboarded-per-year and schema-changes-per-year volumes (discovery inputs), and the standard-field auto-map hit rate (internal estimate — validate on your traces).
