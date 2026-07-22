# ROI Framework — Sentinel Auto-Loan Fraud Detection

> The numbers here are **templates and illustrative examples** — real figures come from your own discovery, not from this doc.

## What problem this solves

Auto lenders and dealer-finance platforms screen application fraud mostly with rules engines: fixed thresholds on individual fields. Fraudsters learn the thresholds and slip past them, while legitimate applicants trip them and generate false-positive noise. The result is two costs at once — **fraud losses** from cases the rules miss, and **underwriter time** spent clearing false positives and manually chasing signals across systems.

The patterns that drive real loss are cross-dimensional: a **synthetic identity** (an SSN issued well after the applicant's stated birth year), **application stacking** (the same identity/address/phone across multiple dealers in a short window), or a **financial mismatch** (income inconsistent with occupation, thin equity on luxury collateral). No single rule sees these — they only surface when identity, velocity, and financial signals are correlated. Sentinel correlates them with four cooperating agents and explains the verdict in language an underwriter can defend, so the team catches more real fraud *and* spends less time per application.

## ROI math (template)

**Inputs to gather in discovery:**

| Input | Symbol | Example (illustrative, research-backed) | Basis |
|---|---|---|---|
| Applications screened / month | `A` | 25,000 (300K/yr) | Mid-market auto lender; kit targets "thousands+/mo" |
| Share currently sent to manual review | `r` | 12% | Internal estimate (MRC: merchants manually review 10–15% of orders) |
| Underwriter minutes per reviewed app today | `m` | 20 min | Tookitaki ~20 min/alert; roe.ai ~45 min per false positive (20 is conservative) |
| Fully-loaded underwriter cost / hour | `c` | $50 | BLS loan-officer median $74,180 × ~1.4 loading ÷ 2,080 hrs ≈ $50 |
| Review-time reduction from correlated triage + explanations | `Δt` | 30% | Conservative vs Pindrop/FNBO 35–40% faster (~11–13 min/case) |
| Fraud loss currently slipping past rules / year | `L` | $3.75M | 0.10% of ~$3.75B funded — a fraction of Point Predictive's ~1.3% industry exposure rate |
| Incremental fraud caught by multi-agent correlation | `Δf` | 10% | Internal estimate (cross-dimensional catch on the noisy middle) |

**Output formulas:**

```
Monthly review hours today      = A × r × (m / 60)
Analyst time saved / month ($)  = (A × r × (m / 60)) × Δt × c
Fraud loss avoided / year ($)   = L × Δf
Gross annual benefit            = (analyst savings/mo × 12) + fraud avoided/yr
```

**Worked example (Illustrative, research-backed — not a guarantee):**

```
LABOR SAVINGS
Review hours/month   = 25,000 × 0.12 × (20/60)   = 3,000 apps × 0.333 hr = 1,000 hrs/mo
Hours saved/month    = 1,000 × 0.30              = 300 hrs/mo
Labor saved/month    = 300 × $50                 = $15,000/mo
Labor saved/year     = $15,000 × 12              = $180,000/yr

FRAUD LOSS AVOIDED (the softer, more variable number — keep conservative)
Funded volume/year   ≈ 150,000 funded × $25,000 avg (Experian $24,297)  ≈ $3.75B
Loss escaping rules  = $3.75B × 0.10%            = $3.75M/yr
Incremental caught   = $3.75M × 10%              = $375,000/yr

TOTAL ILLUSTRATIVE ANNUAL BENEFIT = $180,000 + $375,000 ≈ $555,000/yr  (~$0.55M)
```

**Cost to run (computed from AWS pricing — worst-case all-live):**

```
BEDROCK — Claude Sonnet 4.5 ($3 / 1M input, $15 / 1M output), 4 agent calls/application
  Assume per call: ~2,000 input tokens (system prompt + app attributes + shared context), ~500 output
  Input/app  = 4 × 2,000 = 8,000 tok → 8,000/1e6 × $3   = $0.024
  Output/app = 4 × 500   = 2,000 tok → 2,000/1e6 × $15  = $0.030
  Per app    = $0.054  (≈ $0.05); + ~10% analyst-chat buffer ≈ $0.06
  Annual (all 300K apps live) = 300,000 × $0.054 ≈ $16,200  (+ chat buffer → ~$18,000)

FIXED INFRA (this kit uses NO OpenSearch Serverless / Knowledge Base / Guardrails)
  App Runner 1 vCPU / 2 GB, steady light traffic   ≈ $40/mo  → ~$500/yr
  ECR + S3 + CodeBuild + CloudWatch                ≈ $15/mo  → ~$200/yr

TOTAL ANNUAL COST ≈ $18,000 + $700 ≈ ~$19,000/yr
```

**Return multiple:** $555,000 ÷ $19,000 ≈ **~29x**. Conservative range **~20–30x**.
Labor-only floor (ignoring all fraud avoidance): $180,000 ÷ $19,000 ≈ **~9–10x** — the defensible worst case if you credit zero fraud-loss avoidance.

> **Lever:** the kit recommends running only borderline apps through live Bedrock and clearing clear-cut cases with the deterministic heuristic engine. The cost above assumes *every* app runs live (worst case); routing only the noisy middle live cuts Bedrock spend substantially and pushes the multiple higher.

Run the same formulas with your real inputs. Treat fraud-loss-avoided conservatively — it's the harder number to defend and the more variable one.

## Cost drivers

| Driver | Notes | Typical range |
|---|---|---|
| Bedrock (Claude Sonnet 4.5) | 4 agent invocations per application + optional analyst-chat tokens. Scales with application volume and how many apps you run live vs. heuristic-only | $ per 1K applications — model from token sizes × volume |
| App Runner | Single container runtime, billed for compute time; 1 vCPU / 2 GB in the reference | ~$5–25/mo idle-to-light; scales with traffic |
| ECR | Image storage | Negligible |
| CodeBuild | Per-build minutes for image builds | Negligible (build-time only) |
| S3 | Source bundle for the CodeBuild path | Negligible |
| CloudWatch | Logs | Low |

Cost scales primarily with **how many applications you run through live Bedrock**. Running borderline-only apps live (and clearing clear-cut ones with the heuristic engine) is a lever to control cost.

## Common objections + responses

- **"We already have a rules engine."** Sentinel doesn't replace it — it adds correlated, explainable reasoning on top. Keep the rules for clear-cut cases; route the noisy middle to the agents.
- **"Is this a black box? Compliance will ask why."** No. The verdict is a *deterministic* weighted score with a per-dimension contribution breakdown and a plain-language narrative citing the specific data values used. That's more explainable than most rules engines.
- **"Will it auto-decline good customers?"** It makes no autonomous decisions. It's a second opinion for a human underwriter — APPROVE / FLAG / DECLINE is a recommendation, not an action.
- **"What if Bedrock is down or slow?"** Every agent has a deterministic heuristic fallback; the pipeline degrades gracefully and never hard-fails. The score/verdict are computed in code regardless.
- **"How do we trust the LLM's numbers?"** The LLM never owns the score. It supplies narrative and risk factors; the score and recommendation are deterministic.
- **"We have strict data residency."** It's single-tenant in your own account and region; no data leaves your boundary except Bedrock model calls within-region.
- **"How long to see it on our data?"** A focused engagement (16–24 engineering hrs over ~1–1.5 weeks) gets a customized, deployed instance running on your application schema.

## Time-to-value benchmarks

| Milestone | Target |
|---|---|
| Local demo on your sample applications (mock mode) | Day 1–2 |
| Agent prompts + heuristics tuned to your product | Day 3–5 |
| Deployed to your account on App Runner (live Bedrock) | Day 5–6 |
| Acceptance tests passed + underwriter walkthrough | Day 6–8 |

## Differentiation vs. competitors

- **Legacy rules engines (FICO Falcon, SAS, in-house):** strong at deterministic rules, weak at cross-dimensional correlation and explanation. Sentinel complements them with reasoning + narrative; position as additive, not a rip-and-replace.
- **Black-box ML fraud scores:** a single opaque probability. Sentinel's per-dimension contributions + narrative win when compliance/underwriters need defensible reasons.
- **Generic LLM "ask about this application" tools:** one prompt, no deterministic verdict, no fallback. Sentinel's separation of agents + deterministic scoring + heuristic resilience is the differentiator.
- **When this kit is NOT the answer:** you want fully autonomous decisioning, have no structured application data, or need strict on-prem deployment. Disqualify early (see `kit.json`).

## Sources

All savings figures are **illustrative and research-backed** — not guarantees. Cost figures are computed from public AWS pricing. Validate every input per deployment.

| Source (real URL, retrieved 2026-06-19) | Backs which figure |
|---|---|
| https://www.bls.gov/ooh/business-and-financial/loan-officers.htm | Loan officers (incl. loan underwriters) median annual wage **$74,180** (May 2024) → loaded to ~$50/hr |
| https://pointpredictive.com/press-releases/2025-auto-lending-fraud-trends-report-9-2-billion-industry-risk/ | Auto-lending fraud-loss exposure **$9.2B** for 2024; **69%** first-party fraud; income/employment misrepresentation **43%** ($3.9B) → fraud-loss-avoided basis |
| https://pointpredictive.com/press-releases/point-predictive-releases-2024-auto-lending-fraud-trends-report-identifies-7-9-billion-industry-fraud-loss-exposure/ | Synthetic-identity attempts **+98% YoY** ($7.9B exposure in the prior 2024 report) → synthetic-identity outcome |
| https://www.tookitaki.com/compliance-hub/reducing-false-positives-transaction-monitoring | ~**20 minutes per alert** for thorough manual review → `m` (minutes/review) |
| https://www.pindrop.com/research/case-study/fraud-assist-ai-efficiency-fnbo-fraud-case-investigation/ | AI fraud-assist: **35–40% faster** investigations, **~11–13 min saved/case** at FNBO → `Δt` (review-time reduction; 30% used conservatively) |
| https://www.nofraud.com/blog/research-shows-that-manual-review-is-the-largest-expense-eating-at-fraud-budgets/ | CyberSource benchmark: **~82%** of manually reviewed transactions are legitimate (false positives) → review-time-reduction rationale |
| https://autofinancenews.net/allposts/big-wheels/originations-rise-9-6-across-top-100-auto-lenders-in-2024-big-wheels/ | Top-100 auto lenders originated **$656B** in 2024 → industry origination anchor / fraud-exposure-as-%-of-originations |
| https://www.sacbee.com/news/business/article306731196.html | Experian: average auto loan balance **$24,297** (Q3 2024) → average funded-loan size in fraud-avoided calc |
| https://aws.amazon.com/bedrock/pricing/ | Claude Sonnet 4.5 token pricing ($3/1M input, $15/1M output) → Bedrock cost |
| https://aws.amazon.com/apprunner/pricing/ | App Runner compute pricing → fixed-infra cost |

**Internal estimates (no public source — flagged as such):** the manual-review share `r` (12%), the incremental fraud-catch rate `Δf` (10%), and the share of funded volume escaping current rules (0.10%) are conservative internal assumptions, not sourced figures. The 10–15% manual-review band is loosely supported by MRC merchant-review benchmarks but is not auto-lending-specific. Replace all three with your measured numbers in discovery.
