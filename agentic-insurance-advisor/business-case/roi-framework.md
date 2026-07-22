# ROI Framework — Agentic Insurance Advisor

> The numbers here are **templates and clearly-labeled illustrative examples** — real figures come from your own discovery, not from this doc. Do not present the worked example as a commitment.

## What problem this solves

Insurance advisory is document-intensive and compliance-heavy. To produce one full advisory today, a producer manually cross-references carrier brochures, policy summaries, and rate sheets to find fitting products, reasons through suitability against the firm's standards, and hand-writes a recommendation letter with the required disclosures. Three costs fall out of that manual flow at once:

- **Capacity cost** — manual research caps a producer at a handful of full advisories per day, so growing advisory throughput means growing headcount.
- **Compliance cost** — suitability reasoning varies advisor-to-advisor, and hand-written letters inconsistently include the required disclosures, which turns audit prep into a manual reconstruction exercise and raises the risk of an unsuitable-recommendation or missed-disclosure incident.
- **Client-experience cost** — slow turnaround and generic recommendations erode trust.

The kit decomposes that flow into a supervisor plus three specialists: retrieval grounded in the carrier's own product documents, suitability scored against the **same eight documented rules (SUIT-01…SUIT-08) every time with the rule ID cited**, and a letter that ships with its disclosure block — collapsing an afternoon of work into a sub-2-minute, auditable workflow.

## ROI math (template)

**Inputs to gather in discovery:**

| Input | Symbol | Example (illustrative) |
|---|---|---|
| Producers in the network | `P` | 40 |
| Full advisories per producer per day today | `a` | 4 |
| Minutes per advisory today (research + suitability + letter) | `m` | 45 min |
| Time reduction from the agent workflow | `Δt` | 60% (→ ~27 min saved/advisory) |
| Fully-loaded producer cost / hour | `c` | $40/hr |
| Working days / year | `d` | 240 |
| Annual cost of a missed-disclosure / unsuitable-recommendation incident | `I` | $[I] |
| Reduction in incident exposure from consistent rules + disclosures | `Δi` | [X%] |

**Loaded-rate basis:** BLS reports a **median annual wage of $60,370 for insurance sales agents (SOC 41-3021), May 2024**. Applying a conservative ~1.4× loading for benefits, payroll taxes, and overhead gives ~$84.5K/yr ÷ 2,080 hrs ≈ **$40/hr loaded**. The time-sink is real: Cerulli/Invesco finds advisors spend only **~53% of their time client-facing and ~22% on administrative/compliance/paperwork** activities — the research-and-documentation slice this kit automates.

> ⚠️ The **45-min manual baseline** and **60% time reduction** are illustrative internal estimates (observe the real per-advisory minutes in discovery). The loaded rate and the admin-time split are sourced (see ## Sources).

**Output formulas:**

```
Producer hours saved / year   = P × a × (m/60) × Δt × d
Capacity time value / year    = producer hours saved × c
Added advisory capacity / yr  = P × Δa × d              (advisories, not $ — value per customer)
Compliance exposure avoided   = I × Δi
Annual benefit                = capacity time value + compliance exposure avoided
```

**Worked example — ILLUSTRATIVE, RESEARCH-BACKED — not a guarantee:**

```
Annual advisory volume   = 40 × 4 × 240                       = 38,400 advisories/yr
Time saved per advisory  = 45 min × 60%                       = 27 min = 0.45 hr
Producer hours saved/yr  = 38,400 × 0.45                       = 17,280 hrs/yr
Capacity time value      = 17,280 hrs × $40/hr                 = $691,200/yr  (~$0.69M)
Per producer             = 4/day × 0.45 hr × 5 days            = ~9 hrs/week returned
Compliance exposure avd  = additional upside, conservatively not counted in the headline
Annual benefit (headline)= ~$0.69M/yr  (capacity/time value only)
```

**AWS cost (computed from pricing) — ILLUSTRATIVE:**

```
Per-advisory token estimate (all on Sonnet 4.5, conservative — ignores Nova mix savings):
  input  ~40,000 tok × $3.00/1M  = $0.12
  output  ~8,000 tok × $15.00/1M = $0.12
  per advisory                    ≈ $0.24
Bedrock model / yr   = 38,400 × $0.24                          ≈ $9,200/yr
OpenSearch Serverless = 4 OCU (HA prod) × $0.24/OCU-hr × 8,760 ≈ $8,400/yr   ← dominant fixed cost
KB Retrieve (~2/advisory) + storage (~1 GB) + Titan embeds    ≈ $200/yr
Lambda + API GW + DynamoDB + S3/CloudFront + CloudWatch       ≈ $300/yr
Annual AWS cost                                                ≈ $18,000/yr (~$18K)
```

**Multiple:** $691,200 ÷ $18,000 ≈ **38×** → report conservatively as **~30–40×**.

Run the formulas with your real inputs. Treat the compliance-exposure term conservatively — it is the harder number to defend and the more variable one; lead with the capacity and time-saved math, which is directly observable. Note the OpenSearch Serverless OCU floor (~$8.4K/yr HA, or ~$4.2K/yr at the 2-OCU minimum) dominates cost at low volume; Bedrock token spend overtakes it only as advisory volume climbs.

## Cost drivers

| Driver | Notes | Typical range |
|---|---|---|
| Bedrock (Claude Sonnet 4.5) | Suitability + supervisor reasoning. Largest per-advisory token cost; scales with advisory volume | $ per advisory — model from token sizes × volume |
| Bedrock (Nova 2 Lite) | Product-retrieval RAG synthesis — cost-efficient tier | Low per advisory |
| Bedrock (Nova Pro) | Optional, for supervisor routing + letter writing when latency matters (`speed-up-models.sh`) | Low–moderate per advisory |
| Knowledge Base retrieval | `Retrieve` calls per advisory against the carrier catalog | Low; scales with volume |
| **OpenSearch Serverless** | Vector collection carries a **fixed monthly OCU floor** — dominates cost at low advisory volume | **Validate with your own numbers — the floor, not per-query, is the lever at low volume** |
| Lambda (5 API handlers + action group) | Per-invocation; advisory runs are short bursts | Negligible |
| DynamoDB (PAY_PER_REQUEST) | Client profiles + job rows (TTL'd) | Negligible |
| API Gateway HTTP API | Per-request | Negligible |
| S3 + CloudFront | Product docs, rules YAML, SPA hosting | Negligible |
| CloudWatch | Logs | Low |

The dominant cost lever at low volume is the **OpenSearch Serverless OCU floor**, not model tokens — validate it with your own numbers. At higher volume, Bedrock token spend (Sonnet 4.5 on suitability) becomes the driver; the Nova model mix for routing/retrieval/letter is a deliberate cost control.

## Common objections + responses

- **"Is the AI making the recommendation? Our producers are licensed and accountable."** No. The output is a *draft package* — retrieved products, per-rule suitability, and a letter — for a licensed producer to review, edit, and own. The agent never binds or sends anything.
- **"Compliance will ask how a suitability call was reached."** Every verdict is a per-rule pass/fail against the documented eight rules (SUIT-01…SUIT-08) with the rule ID cited and reasoning attached — far more defensible than advisor-by-advisor judgment. UNSUITABLE on any rule makes the product UNSUITABLE overall.
- **"Our suitability standard is different from yours."** The rules are externalized in `data/rules/suitability-rules.yaml`, loaded at runtime — your compliance team edits the rule set, thresholds (e.g. the 10%-of-income affordability ceiling), and verdict logic without a code change.
- **"Will it recommend products we don't carry, or invent eligibility?"** No. The retrieval agent answers only from the indexed carrier documents with source citations and checks eligibility before recommending — it can't surface a product that isn't in your catalog.
- **"Will the letters be missing disclosures like our hand-written ones?"** The mandatory disclosure block (not-FDIC-insured / not-a-deposit / not-financial-advice) lives in the recommendation agent's instruction and is on every letter by construction.
- **"How long until we see it on our own products?"** A focused engagement (16–24 hrs over ~5–8 days) gets a customized, deployed instance running on your product catalog and suitability standard.
- **"Where does our client data go?"** Single-tenant in your own AWS account and region; client profiles sit in your DynamoDB, product docs in your S3, and the only model calls are in-region Bedrock invocations within your account boundary.

## Time-to-value benchmarks

| Milestone | Target |
|---|---|
| CFN stack + seeded sample data deployed, demo running on the six sample clients | Day 1–2 |
| Your product catalog ingested into the KB; suitability YAML + disclosure tuned | Day 3–5 |
| Agents provisioned + collaboration wired in your account, end-to-end advisory passing | Day 5–7 |
| Acceptance tests passed + advisory/compliance walkthrough | Day 7–8 |

## Differentiation vs. competitors

- **Manual / template-driven advisory (status quo):** spreadsheets, brochure PDFs, and Word letter templates. No grounded retrieval, no consistent rule check, no audit trail. The kit's grounded RAG + documented rules + auto-disclosure is the leap.
- **Single general-purpose LLM "ask about this client" tools:** one prompt, no rule engine, no per-rule citations, no guarantee of disclosure language, prone to inventing products. The kit's separation into retrieval / suitability / letter with externalized rules and citations is the differentiator.
- **Standalone financial-planning / illustration software (e.g. carrier illustration tools, planning suites):** strong at quoting and projections, weak at cross-document research and documented suitability reasoning. Position the kit as the research-and-suitability layer that produces a defensible, client-ready draft, feeding into — not replacing — your quoting/illustration stack.
- **Build-from-scratch multi-agent platform:** months of work to land supervisor-router orchestration, a grounded KB, an externalized rules engine, and an async API. This kit is that pattern, working, in your account in days.
- **When this kit is NOT the answer:** you want the agent to bind/auto-issue recommendations, has no structured client-profile data, has no product catalog to index, or requires strictly on-premises deployment. Disqualify early (see `kit.json`).

## Sources

All savings inputs below are from public sources actually retrieved; cost inputs are computed from AWS published pricing. Numbers are **research-backed illustrative** — validate with your own numbers.

- **BLS — Insurance Sales Agents (SOC 41-3021), Occupational Outlook Handbook:** median annual wage **$60,370 (May 2024)**. Basis for the ~$40/hr loaded producer rate (×1.4 loading). https://www.bls.gov/ooh/sales/insurance-sales-agents.htm
- **BLS — OEWS national occupational data, May 2024:** confirming wage table for 41-3021. https://www.bls.gov/oes/current/oes413021.htm
- **Cerulli Associates via Invesco, "Maximizing time with clients" (Mar 2023):** advisors spend ~**53% of time client-facing** and ~**22% on administrative/operations/compliance/paperwork**. Basis for the "manual research/documentation is a real time sink" claim and the capacity-lift outcome. https://www.invesco.com/us/en/financial-professional/total-cx/insights/maximizing-time-with-clients.html
- **AWS Bedrock pricing** (Claude Sonnet 4.5 $3.00/1M input, $15.00/1M output; Titan Text Embeddings V2 $0.02/1M; Knowledge Bases $5/GB-mo + $1/1,000 Retrieve). Basis for the per-advisory model cost and KB cost. https://aws.amazon.com/bedrock/pricing/
- **AWS OpenSearch Serverless pricing** ($0.24/OCU-hour; ~2-OCU minimum dev, ~4-OCU HA production). Basis for the dominant ~$8.4K/yr fixed cost. https://aws.amazon.com/opensearch-service/pricing/

**Internal estimates (no public source — clearly marked):** the 45-min manual advisory baseline, the 60% time reduction, the 40-producer / 4-advisories-per-day volume, and the per-advisory token sizes (40K in / 8K out) are illustrative assumptions for the worked example. Replace each with your own observed values.
