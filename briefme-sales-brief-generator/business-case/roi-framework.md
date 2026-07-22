# ROI Framework — BriefMe Sales Brief Generator

> The numbers here are **templates and illustrative examples** — real figures come from your own discovery, not from this doc.

## What problem this solves

Pre-meeting account research is recurring, manual, and uneven. A rep preparing for a discovery or expansion call typically skims the company's website, hunts for recent news and funding/earnings, tries to identify the right stakeholders, and assembles a point of view — every time, from scratch. Multiply that by every rep and every meeting and it's a large, invisible time sink. The output is also inconsistent (every rep researches differently) and unverifiable (you can't tell where a claim came from).

BriefMe converts that task into a one-click, **cited** brief. A single agent runs the same structured research every time — overview, products, recent news, talking points, stakeholders — with Nova Web Grounding returning real source URLs the rep can check. The benefit is two-sided: **time saved** per brief, and **consistency + trust** (every rep gets the same brief structure, with sources). It runs inside your own AWS account, which matters for teams who won't put account data into a third-party SaaS.

## ROI math (template)

**Inputs (illustrative, research-backed — not a guarantee):**

| Input | Symbol | Value | Basis |
|---|---|---|---|
| Reps using BriefMe | `R` | 50 | Illustrative team size — validate with your own numbers |
| Briefs generated / rep / week | `b` | 5 | Illustrative; reps prep for several net-new/expansion calls weekly |
| Manual research minutes replaced per brief | `m` | 40 min | Conservative vs. the 1–2 hrs/call reps report (Salesmotion) and 5–6 hrs/wk on account research |
| Fraction of that research time actually saved | `s` | 60% | Conservative — rep still reviews/verifies the cited brief |
| Fully-loaded rep cost / hour | `c` | $70 | Glassdoor AE total pay ~$117K/yr ÷ ~1,840 productive hrs ≈ $64/hr, lightly loaded → $70/hr (conservative) |
| Working weeks / year | `w` | 46 | Net of PTO/holidays |

**Output formulas:**

```
Briefs / year             = R × b × w
Research hours saved / yr  = (R × b × w) × (m / 60) × s
Annual time-savings ($)    = research hours saved × c
Annual AWS cost            = (R × b × w) × cost-per-brief   (see cost drivers)
Net annual benefit         = annual time-savings − annual AWS cost
```

**Worked example (Illustrative, research-backed — not a guarantee):**

```
Briefs / year        = 50 × 5 × 46                 = 11,500 briefs/yr
Research hrs saved   = 11,500 × (40/60) × 0.60     = 4,600 hrs/yr
Annual time-savings  = 4,600 × $70                 ≈ $322,000/yr   → ~$320K/yr
```

**Annual AWS cost (computed from Bedrock pricing):**

```
Per-brief model tokens (research-heavy):
  input  ~150,000 tokens × $2.50 / 1M  = $0.375
  output  ~20,000 tokens × $12.50 / 1M = $0.250
  Nova Premier per brief               ≈ $0.625
Per-brief infra (Lambda + DynamoDB on-demand + API GW + S3 + CloudFront + Cognito)
                                       ≈ <$0.02 (negligible)
Per-brief total                        ≈ $0.65

Annual model cost    = 11,500 × $0.625              ≈ $7,190/yr
Annual infra add-on  (Lambda compute, DDB, API GW, CloudWatch, AgentCore Runtime)
                                                    ≈ <$150/yr
Annual AWS cost                                     ≈ $7,600/yr
```

> **No vector store / OpenSearch in this kit.** BriefMe grounds on the *live public web* via Nova Web Grounding, not a Knowledge Base — so there is **no OpenSearch OCU floor** (the usual dominant fixed cost in RAG kits). Cost scales almost linearly with briefs × per-brief tokens.

```
Net annual benefit   ≈ $322,000 − $7,600           ≈ $314,000/yr
Cost multiple        = $322,000 / $7,600           ≈ 42×  (sensible range ~30–45×)
```

**On the multiple:** ~40× is large because AWS cost per brief is tiny relative to loaded rep labor. Be honest in the room: this is a **capacity-reclamation** play — the dollar figure is *recovered selling time*, which only becomes revenue if reps redeploy those hours into selling. Lead with hours-back-per-rep and consistency/trust; treat the multiple as a directional "the infra is rounding error vs. the labor."

**Sensitivity:** the two biggest levers are `m × s` (how much research time a brief really replaces — validate by observing reps) and per-brief token size (Web Grounding depth × synthesis verbosity — meter it in your own runs). Double the token estimate and annual cost is still only ~$15K/yr against six-figure time-savings.

Run the same formulas with your real inputs. The time-savings line is the credible one to lead with; treat per-brief cost as a model output (token sizes × Web Grounding calls × volume), not a fixed number.

## Cost drivers

| Driver | Notes | Typical range |
|---|---|---|
| Bedrock — Nova Premier | Orchestration + ~4 Web Grounding research calls per brief, plus synthesis tokens. The dominant cost; scales with briefs/month and brief depth | Model from token sizes × calls × volume |
| Lambda | `generate_brief` (512 MB, runs while the agent works) + `get_briefs` (256 MB). Pay-per-invoke | Low at sales-team volume |
| DynamoDB | On-demand; one small item per brief + GSI lookups | Negligible–low |
| S3 | One HTML file per brief (private bucket) | Negligible |
| CloudFront | Serves the static SPA | Low |
| Cognito | User pool for the sales team | Free tier covers most teams |
| CloudWatch | Lambda + runtime logs | Low |

Cost scales almost entirely with **Nova Premier usage per brief** (the research + synthesis calls). The biggest lever is brief depth — how many research topics and how verbose the synthesis. AgentCore Runtime, Lambda, and the storage/edge layer are minor at sales-team volume.

## Common objections + responses

- **"We already have ZoomInfo / a research SaaS."** Those are great data sources; BriefMe is in-account, cited, and produces a *meeting-ready brief* in your format, not a data dump. They can be complementary — point the agent at your preferred sources over time.
- **"How do we know the LLM isn't making things up?"** Every research pass uses Nova **Web Grounding**, which returns real source URLs; the brief renders a Sources slide. Reps verify claims against citations — that's the core design choice.
- **"Will reps trust it?"** It's a first draft, not the final word. The cited, structured format makes it fast to verify and edit — that's what drives adoption over a black-box summary.
- **"Where does our data go?"** It runs entirely in your own AWS account and region. The only external calls are Nova Web Grounding's in-region web research; no account data goes to a third-party SaaS.
- **"Can it pull from our CRM / internal docs?"** Not in this kit — it researches the public web. Private-data grounding (RAG over internal content) is a larger, separate build; scope it as a follow-on.
- **"What if a company has little public footprint?"** The brief returns empty/short sections rather than fabricating, and the prompt instructs factual restraint. Coverage tracks public availability.
- **"How fast can we see it?"** A focused engagement (12–18 hrs over ~3–5 days) gets a customized, deployed instance running on your brief format and identity.

## Time-to-value benchmarks

| Milestone | Target |
|---|---|
| Reference deployed to a sandbox; first brief generated | Day 1–2 |
| Prompt + brief schema + slideshow tuned to your motion | Day 2–4 |
| Deployed to your account with your Cognito/auth posture | Day 4–5 |
| Acceptance tests passed + sales-team walkthrough | Day 5 |

## Differentiation vs. competitors

- **Sales-intelligence SaaS (ZoomInfo, Clearbit, LinkedIn Sales Navigator):** rich data, but external to your boundary and oriented to records, not a synthesized meeting brief. BriefMe is in-account and produces a cited narrative in your format; position as complementary.
- **Generic chatbot "research this company" prompts:** no citations, no structure, no persistence, and the data leaves the boundary. BriefMe's grounded citations + fixed schema + searchable history are the differentiators.
- **Other "AI SDR / research" point tools:** usually closed SaaS with opaque sourcing. BriefMe ships as source you own and runs, on Bedrock, with verifiable grounding.
- **When this kit is NOT the answer:** you need briefs grounded in private/internal data, needs the agent to take outbound actions, or operates only where Nova Premier + Web Grounding aren't available. Disqualify early (see `kit.json`).

## Sources

All savings figures are illustrative and research-backed — validate with your own numbers. URLs below were retrieved during research; cost figures are computed from AWS pricing, not a third-party claim.

**Savings side (public benchmarks):**
- https://www.salesforce.com/blog/small-business/state-of-sales-takeaways-for-smbs/ — Salesforce State of Sales (7th ed.): reps spend ~60% of their time on non-selling tasks "think manual data entry, lead research, and constant tool-switching." Backs the premise that account research is a large, recurring time sink.
- https://www.glassdoor.com/Salaries/account-executive-salary-SRCH_IN1_KO0,17.htm — Glassdoor: Account Executive total pay ~$117,181/yr (avg base ~$70,940), United States. Backs the loaded-cost-per-hour input (`c`).
- https://salesmotion.io/blog/sales-team-manual-account-research-time — Vendor blog (corroborating, not primary): reps spend ~5+ hrs/week on manual account research. Used only to sanity-check that the 40 min/brief × 5 briefs/wk research estimate is conservative.
- https://www.revic.ai/blog/research-time-savings — Vendor blog (corroborating, not primary): reps spend ~1–2 hrs preparing per call. Used to sanity-check the "60–80% faster prep" outcome.

**Cost side (computed from AWS pricing):**
- https://aws.amazon.com/bedrock/pricing/ — Amazon Bedrock pricing. Nova Premier ~$2.50 / 1M input tokens, ~$12.50 / 1M output tokens. Basis for the ~$0.625/brief model cost.
- Lambda, DynamoDB on-demand, API Gateway HTTP, S3, CloudFront, Cognito, AgentCore Runtime — standard AWS pricing; all negligible (<$150/yr combined) at this volume. No OpenSearch/vector store in this kit (live Web Grounding, not a KB), so no OCU fixed-cost floor.

> Vendor-blog figures (Salesmotion, Revic) are marked corroborating because they are marketing content, not primary research; the load-bearing public sources are Salesforce State of Sales and Glassdoor. Internal estimates (token sizes per brief, 60% replacement fraction) carry no citation and should be metered against your own runs.
