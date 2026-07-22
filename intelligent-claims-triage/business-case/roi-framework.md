# ROI Framework — Intelligent Claims Triage

This is a scaffold. Replace `[X]` placeholders with your own numbers. The worked example below is illustrative, not a number to quote.

## What problem this solves

Every claim starts with clerical work. An adjuster opens a first-notice-of-loss claim, reads the repair estimate or police report, keys the amounts and incident details into the claims system, then pulls the policy to confirm coverage, deductible, and limits. Only then does adjudication begin. On a queue of thousands of claims a month, that front-end work is hours per adjuster per day — and it's the same work whether the claim is a clean $1,200 fender-bender or a disputed total loss.

This agent does the front-end work and the easy decisions. It extracts the document fields with Textract, cross-references coverage against the policy corpus in a Knowledge Base, scores the claim, and auto-approves the low-risk ones with a calculated payout and a policy-cited rationale. The risky claims escalate to a human with all of that context already assembled. Adjusters stop keying PDFs and stop triaging the obvious claims; they spend their time where judgment actually matters.

## ROI math (template)

You fill these in during discovery. Use your actual numbers; don't pad.

### Inputs to gather

| Input | How to get it | Your value |
|---|---|---|
| Monthly claim volume (document-bearing) | Claims system | [X] claims/month |
| Share of claims that are low-risk / straightforward | Adjuster estimate or historical triage data | [X]% |
| Manual front-end time per claim today (extract + policy lookup) | Sample 1 week of adjuster time-tracking | [X] minutes |
| Adjuster time per straightforward adjudication today | Same sample | [X] minutes |
| Loaded hourly cost of an adjuster | Finance + benefits + overhead | $[X]/hour |
| Expected auto-approval rate you will accept | Risk appetite conversation | [X]% |
| Expected front-end time reduction (extraction + lookup) | Benchmark range: 60–90% | [X]% |
| Average cycle time per claim today | Claims system | [X] days |

### Output formulas

```
Annual front-end clerical hours (today) =
  monthly_claim_volume
  × front_end_minutes_per_claim / 60
  × 12 months

Annual clerical cost (today) = annual_front_end_hours × loaded_hourly_cost

Annual savings from extraction + lookup automation =
  annual_clerical_cost × front_end_time_reduction

Annual savings from straight-through auto-approval =
  monthly_claim_volume × auto_approval_rate
  × adjudication_minutes_per_claim / 60
  × 12 × loaded_hourly_cost

Total annual benefit = extraction_savings + auto_approval_savings
                       (+ cycle-time / CSAT gains — qualitative unless you quantify)

ROI multiple = total_annual_benefit / (kit_build_cost + annual_run_cost)
```

### Worked example (illustrative, NOT a guarantee)

Mid-size auto insurer, 5,000 document-bearing claims/month, adjuster loaded cost $65/hour:

```
Front-end clerical automation:
  5,000 × 15 min/claim / 60 = 1,250 hours/month
  × 12 = 15,000 hours/year
  × $65/hour = $975K/year of clerical time
  × 80% reduction = ~$780K/year

Straight-through auto-approval (40% of claims auto-approved, 12 min adjudication each):
  5,000 × 40% × 12 min / 60 = 400 hours/month
  × 12 = 4,800 hours/year
  × $65/hour = ~$312K/year

Annual benefit (illustrative): ~$1.09M

Build cost: 16–24 hrs × $200/hr = ~$4K
Annual run cost: ~$25–60K (Bedrock Haiku invocations, Textract pages, Lambda/API/DynamoDB)

ROI multiple: ~18–40x first year (if the numbers above hold)
```

**Use as a template, NOT as a number to quote.** Your real numbers will differ; measure them before relying on the math.

## Cost drivers

| Cost | Typical range | Notes |
|---|---|---|
| Bedrock invocations (Claude Haiku 4.5) | $0.002–0.02 per claim triaged | Haiku is cheap; multi-tool reasoning over a claim is a few thousand tokens |
| Amazon Textract | $1.50 per 1,000 pages (DetectText) to $50+ per 1,000 (FORMS/TABLES) | Forms/Tables analysis is the bulk of per-claim cost; tune feature types |
| Bedrock Knowledge Base | OpenSearch Serverless ~$345/month floor + embedding/query costs | The OCU minimum dominates at low volume; shared across the org |
| Lambda | <$0.20 per 1,000 claims | 8 short-lived functions; negligible |
| API Gateway | $3.50 per million requests | Negligible at claims volume |
| DynamoDB (on-demand) | <$0.10 per 1,000 claims | PAY_PER_REQUEST; small items |
| S3 | $0.023/GB/month | Claim + policy document storage |
| SQS + SNS | Pennies | Escalation volume only |
| CloudWatch | $0.50/GB ingested + storage | Agent reasoning logs can be chatty; set retention |

**Plan range:** the Knowledge Base (OpenSearch Serverless) floor (~$345/month) plus Textract usage are the two cost drivers that matter; everything else scales near-linearly and cheaply with claim volume. At 5,000 claims/month, expect roughly $2–5K/month all-in depending on Textract feature usage.

## Common objections + responses

| Objection | Response |
|---|---|
| "We can't let AI approve claims without oversight." | It only auto-approves **low-risk** claims below a threshold you set, with the payout math and a policy-cited rationale persisted on every one. Anything risky escalates to a human. You tune the threshold — start conservative and raise it as you trust the system. |
| "How do we audit why a claim was approved?" | Every claim stores its risk score, risk factors, reasoning, the extracted document data, and the exact policy context the decision used. The agent's tool calls and reasoning are in CloudWatch. You can reconstruct any decision after the fact. |
| "Our policy documents are messy / non-standard." | The policy lookup is RAG over your actual documents in a Bedrock Knowledge Base — it reads what you have rather than requiring a clean schema. The extraction tool also has fallbacks for documents Textract can't parse cleanly. |
| "Textract won't read our adjusters' weird PDFs." | The extraction tool tries Textract FORMS/TABLES, then text detection, then raw-PDF text scraping, and finally falls back to the submitted claim metadata so triage never hard-fails. Field patterns are tunable to your formats. |
| "What happens when the model is wrong?" | On low confidence the rubric pushes risk up and the claim escalates rather than auto-approving. The agent never auto-denies, and a tool/model failure marks the claim `AGENT_ERROR` for human pickup — it doesn't silently resolve. |
| "We already have a claims system / a vendor IDP tool." | This kit complements them. It sits at intake to triage and auto-decide; it writes decisions back via its tools, which you can repoint at your core claims system. The value is the agentic extract → validate → score → route loop, not another system of record. |

## Time-to-value benchmarks

| Milestone | Target |
|---|---|
| Reference stack deployed in your account | 2–3 days |
| Policy corpus ingested into a Knowledge Base | 3–5 days |
| Risk rubric + extraction tuned to your claims | 5–7 days |
| First batch of real claims triaged end-to-end | 7–10 days |
| Measurable cycle-time / auto-approval rate | 30 days (need volume) |
| Full ROI realization | 90 days |

## Differentiation vs. competitors

- **vs. standalone IDP tools (Textract-only, ABBYY, Hyperscience).** Those extract fields; they don't reason about coverage or make a triage decision. This kit uses extraction as step one of an agentic loop that also cross-references policy, scores risk, and decides — with the audit trail to back it.
- **vs. incumbent claims platforms (Guidewire, Duck Creek) with add-on AI.** Those are systems of record. This kit is a lightweight triage layer that runs in your own AWS account, integrates via its tools, and isn't a multi-year platform commitment. It can feed decisions back into the platform.
- **vs. building it yourself.** A team can wire Textract + a KB + an LLM in a few weeks. The kit gives a working reference — the async triage pattern, the risk-rubric prompt, the escalation plumbing, and the auditability already worked out — so your team spends its time on the policy corpus and risk appetite, not the orchestration.
- **vs. a pure-LLM "read the claim and decide" approach.** No grounding, no bounded payout, no audit trail, no human-in-the-loop. This kit grounds coverage in retrieved policy text, bounds the payout math deterministically, and escalates anything risky — which is what gets it past a claims-compliance review.
