# ROI Framework — Internal Knowledge Q&A

This is a scaffold. Replace `[X]` placeholders with your own numbers during the engagement.

## What problem this solves

Senior staff (engineers, HR partners, ops leads, compliance officers) field a steady stream of "where do I find X?" questions whose answers are already documented but hard to find. Each interruption breaks flow for 5–15 minutes. New hires take longer to ramp because they can't navigate the documentation.

The agent gives employees a self-serve, citation-grounded answer for documented questions and frees senior staff to do work only they can do.

## ROI math (template)

You fill these in during the discovery phase. Use your actual numbers; don't pad.

### Inputs to gather

| Input | How to get it | Your value |
|---|---|---|
| Headcount in the target org/team | HRIS or org chart | [X] employees |
| Avg "where do I find X" questions per senior staff member per day | Sample 5 senior staff for a week | [X] questions/day |
| Avg time per question (asking + answering + context-switch cost) | Self-report; benchmark is 8–12 minutes | [X] minutes |
| Loaded hourly cost of senior staff time | Finance / TC + benefits + overhead | $[X] / hour |
| Expected deflection rate (% of questions the agent answers) | Benchmark range: 50–70% in mature corpora | [X]% |
| Onboarding velocity baseline | Time-to-productivity for new hires | [X] weeks |

### Output formulas

```
Annual interruption cost (today) =
  senior_staff_count
  × questions_per_day
  × minutes_per_question / 60
  × loaded_hourly_cost
  × 240 working days

Annual savings =
  annual_interruption_cost × deflection_rate

Onboarding velocity gain =
  (baseline_ramp_weeks - new_ramp_weeks)
  × new_hires_per_year
  × loaded_weekly_cost_of_unproductive_ramp

Total annual benefit = annual_savings + onboarding_velocity_gain

ROI multiple = total_annual_benefit / (kit_build_cost + annual_run_cost)
```

### Worked example (illustrative, not a guarantee)

Mid-market software company, 500 engineers, 30 senior staff:

```
Annual interruption cost:
  30 senior × 8 questions/day × 10 min/q / 60 = 40 hours/day
  × $150/hour × 240 days = $1.44M/year

At 60% deflection:
  Annual savings = $864K

Onboarding velocity:
  Baseline 6 weeks → new ramp 4.5 weeks
  1.5 weeks × 50 hires/year × $150/hr × 40 hrs = $450K

Annual benefit (illustrative): ~$1.3M

Build cost: 12–18 hrs × $200/hr = $3-4K
Annual run cost: ~$40-80K (Bedrock invocations + KB queries; volume-dependent)

ROI multiple: ~15x first year (if numbers above hold)
```

**Use this as a template, NOT as a number to quote.** Every your numbers will differ. The discovery conversation is where you establish the real inputs.

## Cost drivers

You should expect these AWS costs:

- **Bedrock invocations** — per query, depends on input + output tokens. Claude 3.5 Sonnet pricing applies. Plan for 1–5K tokens per query average.
- **Knowledge Bases queries** — per retrieval. Default chunking + retrieval is cheap; custom chunking changes the math.
- **OpenSearch Serverless** — vector store. Has a baseline OCU charge whether queries are happening or not. Right-size based on corpus volume.
- **CloudWatch Logs** — query/response audit log. Retention duration drives cost.
- **AgentCore Managed Harness** — runtime. Pay-per-use; minimal idle cost.

Have your FinOps / cloud cost team review before deployment. Cost grows with corpus size and query volume, not linearly with employee count.

## Common objections + responses

| Objection | Response |
|---|---|
| "We tried a wiki search agent before and it hallucinated answers." | This kit's hard rule is **cite or decline**. The system prompt + guardrails enforce it. The acceptance tests verify it. If the corpus doesn't have the answer, the agent says so — it doesn't make one up. |
| "Our docs are out of date — won't the agent give people stale info?" | The agent tells you which document and which version it's citing. If the doc is stale, that's a documentation hygiene problem the agent makes *visible* (you can see what's getting cited and update it). It doesn't fix bad docs, but it surfaces them. |
| "What about our most sensitive documents — exec offsites, comp data, M&A docs?" | Don't put them in the KB. The agent retrieves only from the sources you connect. Sensitive docs stay out of the corpus; the audit log shows what got accessed. |
| "We already have Glean / Notion AI / Confluence Atlassian Intelligence." | Those are great horizontal tools. This kit gives you a deployment you control in your AWS account, with audit logging, identity-tied access, your own guardrails policy, and no per-seat licensing. Pick based on whether deployment-control or off-the-shelf-convenience matters more. |
| "Why not just have ChatGPT read our docs?" | Sending internal documents to a third-party model has legal, compliance, and IP implications most enterprises won't accept. This kit keeps documents in your AWS account, runs the inference on Bedrock in your account, and gives you an audit log of every query. |

## Time-to-value benchmarks

| Milestone | Target |
|---|---|
| Build complete (in your AWS account) | 5–7 days |
| First production query | 7–10 days |
| Citation rate >90% in production | 14 days (depends on corpus quality) |
| Measurable senior-staff hour reduction | 30–60 days (need usage volume) |
| Full ROI realization | 90 days |

## Differentiation vs. competitors

- **vs. Glean.** Glean is excellent at horizontal enterprise search. This kit is a deployment in *your* AWS account with *your* guardrails policy and identity tied to *your* IdP — no per-seat license, no data leaving your account.
- **vs. Notion AI / Confluence Intelligence.** Those are tied to one source. This kit aggregates across all your sources (Confluence + SharePoint + S3 + custom) into one corpus.
- **vs. ChatGPT Enterprise + custom GPTs.** Custom GPTs send your data to OpenAI's infrastructure. This kit keeps documents and inference in your AWS account.
- **vs. building it yourself.** A junior team can build a basic RAG agent in a weekend. The hard parts — guardrails, cite-or-decline enforcement, audit logging, source-of-truth integration — are what this kit gives you out of the box.
