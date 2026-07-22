# ROI Framework — Agentic PXM Platform

> The numbers here are **templates and clearly-labeled illustrative examples** — real figures come from your own discovery, not from this doc. Do not commit to any number from this playbook.

## What problem this solves

Product onboarding is the unglamorous bottleneck in retail catalog operations. Operators hand-key attributes, rewrite marketing copy per channel, and manually check each SKU against the regulations of every market it ships to — and compliance problems are routinely caught **after** a product is already listed. That creates three costs at once: **operator time** per SKU, **time-to-market** delay before a SKU can sell, and **compliance risk** (a restricted substance like lead, or a prohibited claim like "cures cancer," slipping onto a channel).

The agent collapses onboarding into one orchestrated pass: it normalizes attributes, classifies the SKU against the taxonomy, drafts brand-consistent copy, and validates the product against each target market's regulations — citing the specific `reg_id` behind every finding. Clean, low-risk SKUs flow through and publish without a human touch. Anything with a compliance blocker pauses at a human-in-the-loop gate with the cited regulation in hand, so the high-impact decision stays with an operator instead of being caught post-publish.

## ROI math (template)

**Inputs to gather in discovery:**

| Input | Symbol | Example (illustrative, research-backed) |
|---|---|---|
| SKUs onboarded / re-enriched per month | `S` | 3,000 SKUs/month (36,000/yr) — "thousands+/mo" per `kit.json` idealCustomer |
| Operator minutes per SKU today (attributes + copy + compliance check) | `m` | 20 min/SKU — conservative low end of the 20–46 min/SKU manual benchmark (Crystallize/Envive) |
| Fully-loaded operator cost / hour | `c` | $32/hr — Catalog Specialist ~$46,958/yr ($22.58/hr, Zippia) × ~1.4 loading (benefits + overhead) |
| Share of operator effort the agent removes (auto-enriched + auto-classified + drafted copy) | `Δt` | 60% — one orchestrated pass replaces manual enrich/classify/copy; operator reviews |
| Share of SKUs that hit a compliance blocker needing review | `r` | 5–15% (market-specific) |
| Cost of a compliance incident / recall / delisting avoided | `I` | Your own — keep conservative; bad data drives ~23% of returns (Envive) |
| Compliance incidents avoided per month (caught before publish) | `n` | Your own |

**Output formulas:**

```
Operator hours today        = S × (m / 60)
Operator time saved / month = S × (m / 60) × Δt × c
Compliance loss avoided     = n × I
Gross monthly benefit       = operator time saved + compliance loss avoided
Annual benefit              = gross monthly benefit × 12
```

**Worked example (ILLUSTRATIVE, research-backed — not a guarantee):**

```
Inputs (illustrative):  S = 3,000 SKUs/mo (36,000/yr), m = 20 min/SKU, c = $32/hr,
                        Δt = 60%   (sources: Crystallize/Envive 20–46 min/SKU; Zippia
                        Catalog Specialist $46,958/yr × ~1.4 loading)

Operator hours today        = 36,000 × (20/60)              = 12,000 hrs/yr
Operator time saved / yr    = 12,000 × 60% × $32/hr         = $230,400/yr
                            (≈ 7,200 hrs/yr returned to the team)

Annual labor benefit        ≈ $0.23M/yr
```

**Cost side (computed from AWS pricing — see `kit.json` roi.cost):**

```
Bedrock (Claude 3.5 Sonnet, ~3 calls/SKU)
  per SKU ≈ 8,000 in-tok × $3/1M  + 2,500 out-tok × $15/1M = $0.024 + $0.0375 ≈ $0.062
  × 36,000 SKUs                                                          ≈ $2,200/yr
Titan Embeddings v2 (RAG query + ingest) + chat-console tokens           ≈ $800/yr
OpenSearch Serverless — ALWAYS-ON OCU FLOOR (dominant fixed cost)
  2 OCU ≈ $350/mo → $4,200/yr   (4-OCU HA ≈ $700/mo → $8,400/yr)
AgentCore + Step Functions + Lambda + DynamoDB + API GW + CloudFront     ≈ $1,000/yr
                                                                          ----------
Annual AWS cost                                          ≈ $8,200/yr (2 OCU)
                                                         to ≈ $12,400/yr (4-OCU HA)

ROI multiple = $230,400 / $8,200  ≈ 28x   (2 OCU)
             = $230,400 / $12,400 ≈ 19x   (4-OCU HA)
             → ~18–30x
```

This headline counts **operator-time savings only** — the number that is easiest to measure per SKU and hardest to dispute. On top of it sits **revenue protection** that is real but your own: ~23% of product returns trace to inaccurate product information, and poor product data can cost mid-market retailers ~15–25% of revenue (Envive/McKinsey). Size that from your own revenue and return data — don't fold an unvalidated revenue number into the headline.

Treat **compliance-loss-avoided** conservatively — it's the harder number to defend and the more variable one; lead with the operator-time savings.

## Cost drivers

| Driver | Notes | Typical range |
|---|---|---|
| Bedrock (Claude 3.5 Sonnet text) | ~3 model calls per SKU enrichment (enrich, classify, copy) + chat-console tokens. Compliance check is deterministic — no model call. Scales with SKU volume | $ per 1K SKUs — model from token sizes × volume |
| Bedrock (Titan Embeddings v2) | Embeddings for RAG ingest (one-time per corpus update) + per-query retrieval | Low; scales with corpus + query volume |
| OpenSearch Serverless | **Minimum always-on OCU cost regardless of throughput** — the dominant fixed cost. Size before committing | Always-on floor + usage |
| Lambda + Step Functions | Per-stage Lambda invocations + state transitions per run | Low; scales with SKU volume |
| DynamoDB (on-demand) | Pay-per-request reads/writes per SKU + status transitions | Low |
| API Gateway + CloudFront + S3 | Operator console traffic + SPA hosting | Negligible-to-low |
| CloudWatch + X-Ray | Logs, dashboards, traces | Low |

Cost scales primarily with **SKU volume × per-SKU model calls** plus the **OpenSearch Serverless always-on floor**. The biggest cost-control lever is recognizing that low catalog volume may not justify the always-on OpenSearch cost — disqualify early (see `kit.json`).

## Common objections + responses

- **"We already have a PIM/PXM system."** This doesn't replace it — it's an enrichment + compliance agent that sits on top of your master data. Keep the PIM as the system of record; route onboarding work through the agent and write enriched, compliant SKUs back.
- **"Will it auto-publish something non-compliant?"** No. The compliance check is deterministic rule matching against your regulation corpus, and any blocker (restricted substance, prohibited claim) pauses the run at a human-in-the-loop gate with the cited `reg_id`. Publish is gated behind operator approval by design.
- **"Is the compliance decision a black box?"** No. The blocker decision is in code, not the model — it's substring matching against `restricted_substances` and `prohibited_claims` in your regulation data, and every finding cites the regulation id and source URL. The model only drafts copy and suggests attributes.
- **"How do we trust the generated copy?"** Copy generation is grounded in your brand-guidelines corpus via RAG, and an operator reviews anything that hits the review queue. For clean SKUs the copy is a starting point you can spot-check; the brand voice is something you tune in the corpus.
- **"We run multiple brands / business units."** The platform is pool-based multi-tenant — tenant-prefixed data keys and a Cognito `custom:tenant_id` claim isolate each brand, with admin/operator/viewer roles. One deployment serves many brands.
- **"What about different rules per market?"** The compliance check runs per target market — a SKU shipping to US + EU is validated against each market's regulations independently (the seeded set covers US-CPSC-LEAD, EU-RoHS, US-FTC-CLAIMS, EU-CLP). You add your markets' regulations to the corpus.
- **"Is our data safe?"** Single deployment in your own AWS account and region; nothing leaves your boundary except in-region Bedrock model calls. DynamoDB is encrypted with point-in-time recovery enabled.

## Time-to-value benchmarks

| Milestone | Target |
|---|---|
| Local demo on your sample SKUs (fake provider, no AWS) | Day 1–2 |
| Enrichment stages + compliance rules + corpus tuned to your catalog | Day 2–5 |
| Deployed to your account (`cdk deploy --all`), seeded, Cognito user created | Day 5–6 |
| Acceptance tests passed (incl. the HITL gate) + operator walkthrough | Day 6–8 |

(Aligns with `kit.json`: ~16–24 hours of build effort over a 5–8 day deploy window.)

## Differentiation vs. alternatives

- **Standalone PIM/PXM platforms (Akeneo, Salsify, inriver, etc.):** strong at master-data management and syndication, but enrichment + compliance is largely manual or rules-bolted-on. This kit adds an autonomous enrichment pass with a deterministic, cited compliance gate — position it as additive on top of the PIM, not a rip-and-replace.
- **Generic LLM "enrich my catalog" tools / spreadsheets of prompts:** one prompt, no orchestration, no human-in-the-loop gate, no deterministic compliance, no tenancy. This kit's differentiator is the **Step Functions saga + HITL gate + deterministic cited compliance + pool-based multi-tenancy** — the things that make autonomy safe for a regulated catalog.
- **Building from scratch:** you can wire Bedrock + Step Functions + DynamoDB + OpenSearch + Cognito themselves, but this kit ships the four-stage agent, the saga with the `waitForTaskToken` gate, the validated lifecycle, the RAG service with a local fallback, the six CDK stacks, and a property-tested backend — collapsing weeks of plumbing into a 5–8 day customization.
- **When this kit is NOT the answer:** you want fully autonomous publish with no review of blockers, have no structured master data / taxonomy / regulations to feed it, requires strict on-prem deployment, or has catalog volume too low to justify the OpenSearch Serverless always-on cost. Disqualify early (see `kit.json`).

## Sources

All numbers above are **illustrative and research-backed — not guarantees**. Savings inputs come from the public sources below; cost inputs are computed from AWS list pricing. Validate every figure against your own data.

| Source (retrieved) | Backs which figure |
|---|---|
| [Envive — 32 Product Catalog Data Quality Statistics for Ecommerce](https://www.envive.ai/post/product-catalog-data-quality-statistics) | Manual entry **20–46 min/SKU**; **~23% of returns** stem from inaccurate product info; poor product data → **~15–25% revenue loss** for mid-market; accurate data lowers returns ~20%. (Envive in turn cites Crystallize's PIM statistics and McKinsey.) |
| [Zippia — Catalog Specialist Job Outlook & Growth (US)](https://www.zippia.com/catalog-specialist-jobs/trends/) | Catalog Specialist base salary **~$46,958/yr ($22.58/hr)** — anchor for the ~$32/hr fully-loaded operator rate (×~1.4 loading for benefits + overhead, a standard internal assumption). |
| [Koongo — Why Manually Managing Product Data Is Costing You More Than You Think](https://www.koongo.com/blog/why-manually-managing-product-data-is-costing-you-more-than-you-think/) | Merchants spend **~8–15 hrs/week** on manual product-data work across channels (Koongo cites BigCommerce); per-correction time ~3–5 min. |
| [AWS Bedrock pricing](https://aws.amazon.com/bedrock/pricing/) | Claude 3.5 Sonnet **$3/1M input, $15/1M output**; Titan Text Embeddings V2 **$0.02/1M** — basis for per-SKU model cost. |
| [Amazon OpenSearch Service pricing](https://aws.amazon.com/opensearch-service/pricing/) | OpenSearch Serverless **OCU** unit cost — basis for the always-on RAG floor (~$350/mo for 2 OCU, ~$700/mo for 4-OCU HA), the dominant cost driver. |

**Notes on defensibility:**
- The **~$0.23M/yr labor savings** is built from the *conservative* end of every input (20 min/SKU, not 46; 60% removed, not the 6× speed-up PIM vendors cite) so the floor is easy to defend.
- The **loading multiplier (~1.4×)** applied to the Zippia base is an internal estimate, not a single-source figure — adjust to your real fully-loaded rate.
- The **revenue-protection upside** (returns, abandonment) is deliberately kept *out* of the headline because it requires your revenue and return data to size honestly.
- **Cost** is dominated by the OpenSearch Serverless OCU floor, which is incurred regardless of SKU volume — low-volume catalogs erode the multiple fast (see the disqualifiers in `kit.json`).
