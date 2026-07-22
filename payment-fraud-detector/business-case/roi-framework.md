# ROI Framework — Payment Fraud Detector

This is a scaffold. Replace `[X]` placeholders with your own numbers.

## What problem this solves

Fraud-ops teams running rules-based detection systems get drowned in false positives. Each false positive eats analyst time. A 5–15% false-positive rate on a 100K-transaction-per-month system means analysts triage 5,000–15,000 false alerts a month. Senior analysts burn out. New analysts take 6+ months to develop the pattern recognition needed to prioritize alerts.

The hybrid agent doesn't replace the rules engine — it makes the rules engine *useable*. Rules fire fast (~35ms each); the LLM analyst layer reads the rule fires + transaction context and writes an analyst-grade summary explaining what's actually suspicious, what's likely benign, and what to dig into next. Analysts triage faster, more confidently, with auditable rationale.

## ROI math (template)

Fill these in before you build the business case. Use your actual numbers; don't pad.

### Inputs to gather

| Input | How to get it | Your value |
|---|---|---|
| Monthly transaction volume | Your payment system | [X] transactions/month |
| Rule-fire rate (% of transactions flagged) | Your existing rules engine logs | [X]% |
| False-positive rate (% of fires that are actually benign) | Analyst triage history | [X]% |
| Average analyst triage time per alert today | Sample 1 week of analyst time-tracking | [X] minutes |
| Loaded hourly cost of a fraud analyst | Finance + benefits + overhead | $[X]/hour |
| Expected triage-time reduction with LLM context | Benchmark range: 30–50% | [X]% |
| New-analyst ramp time today | HR + manager input | [X] months |

### Output formulas

```
Annual analyst time on alerts (today) =
  monthly_transaction_volume
  × rule_fire_rate
  × triage_time_per_alert / 60
  × 12 months

Annual analyst cost (today) = annual_analyst_time × loaded_hourly_cost

Annual savings from LLM triage acceleration =
  annual_analyst_cost × triage_time_reduction

Onboarding velocity gain =
  (baseline_ramp_months - new_ramp_months)
  × new_hires_per_year
  × loaded_monthly_cost_of_unproductive_ramp

Total annual benefit = annual_savings + onboarding_velocity_gain

ROI multiple = total_annual_benefit / (kit_build_cost + annual_run_cost)
```

### Worked example (illustrative, NOT a guarantee)

Mid-market payment processor, 500K transactions/month, 12 analysts:

```
Annual analyst time on alerts (today):
  500K × 8% rule fire rate × 12 min/alert / 60 = 8,000 hours/month
  × 12 = 96,000 hours/year
  × $90/hour loaded = $8.6M/year

At 40% triage-time reduction:
  Annual savings = $3.4M

Onboarding velocity:
  Baseline 6 months → new ramp 4 months
  2 months × 4 hires/year × $20K/month unproductive cost = $160K

Annual benefit (illustrative): ~$3.6M

Build cost: 16–24 engineering hrs × $200/hr = ~$5K
Annual run cost: ~$60–120K (Bedrock invocations, ECS Fargate, ALB)

ROI multiple: ~25–40x first year (if numbers above hold)
```

**Use as a template, NOT as a number to quote.** Your real numbers will differ; validate them against your own data.

## Cost drivers

| Cost | Typical range | Notes |
|---|---|---|
| Bedrock invocations (Claude 3 Sonnet) | $0.005–0.05 per analyst session | Token-based; depends on data volume sent to Claude |
| ECS Fargate (MCP + Streamlit) | ~$30–60/month at default 2-task minimum | Auto-scales with load |
| Application Load Balancer | ~$25/month base + LCU charges | LCU charges minor unless very high volume |
| S3 (transaction data) | $0.023/GB/month | Volume-driven |
| CloudWatch (logs + dashboards) | $0.50/GB ingested + $0.03/GB stored/month | Retention-driven |
| VPC + NAT Gateway | ~$30–60/month | Standard private-subnet costs |

**Plan range:** $80–150/month base infrastructure + Bedrock token costs scaling with usage. If you process 500K transactions/month with 12 analysts running ~50 sessions/day, expect $200–500/month in Bedrock spend.

## Common objections + responses

| Objection | Response |
|---|---|
| "We tried ML-based fraud detection and the model risk team killed it." | This kit's spine is a deterministic rules engine — fully auditable, no model in the rule path. Claude only summarizes the rule output + transaction context. The model never makes a decision; it explains decisions humans review. Different threat model entirely. |
| "Our existing rules engine works fine." | Then keep it. This kit can wrap your existing rules engine — replace the MCP server's rule modules with calls to your existing system. The value is in the LLM analyst layer on top, not in the rules layer. |
| "We need real-time, transaction-time fraud scoring." | This kit isn't designed for that — it's batch-analyst-flavored. Real-time scoring is a different (and much stricter) problem. Treat it as a follow-on build once this is in production. |
| "How do we audit Claude's reasoning?" | The narrative is logged with every rule fire. Your compliance team can replay any flagged transaction's full decision trace: which rule fired, what data Claude saw, what narrative Claude wrote. Auditability is a kit requirement, not a nice-to-have. |
| "What about novel fraud patterns the rules don't catch?" | The kit ships with `scripts/claude_only_fraud.py` — a sidecar that asks Claude to find fraud in raw data with no rules. Use it as an exploration tool to identify new patterns, then encode the patterns into rules. The hybrid is the production path; Claude-only is the discovery path. |
| "We already use SAS / Actimize / Featurespace." | Those are great commercial tools. This kit is for you if you (a) want your fraud-ops in your own AWS account, (b) have an existing rules layer you want to keep, and (c) want LLM-grade analyst summarization that the commercial tools either don't offer or charge separately for. |

## Time-to-value benchmarks

| Milestone | Target |
|---|---|
| First deploy in your account | 3–5 days |
| Rules engine customized for your vertical | 5–7 days |
| First analyst session with your real data | 7–10 days |
| Measurable triage-time reduction | 30 days (need usage volume) |
| Full ROI realization | 90 days |

## Differentiation vs. competitors

- **vs. SAS / Actimize / Featurespace.** Those are turnkey commercial fraud platforms. This kit is for you if you specifically want LLM analyst summarization in your own AWS account, with your existing rules infrastructure, and don't want vendor lock-in to a fraud platform.
- **vs. building it yourself.** A team can build a rules engine + LLM wrapper in a few weeks. The kit gives you a working reference (deployed, demoed, with the rules-vs-LLM tradeoffs already worked out) so your team focuses on your rules and data, not on the orchestration plumbing.
- **vs. Bedrock Agents alone.** A Bedrock Agent calling Claude on transaction data without a rules engine produces "Claude-only fraud detection" — slow, expensive, and harder to audit. This kit's hybrid pattern is what makes it production-grade.
