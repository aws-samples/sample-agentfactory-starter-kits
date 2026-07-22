# Business Case — Clinical Trial Site Lookup

## Executive summary (for your leadership)

Your clinical operations team's site selectors are the bottleneck on trial start-up. They spend hours per day in ClinicalTrials.gov and your internal CRO database trying to assemble candidate-site shortlists. Sites are missed, time-to-first-patient slips, and the rationale behind each shortlist is hard to reproduce 90 days later when audit questions come up.

This kit deploys an AI agent that does the search, ranking, and shortlisting in seconds. Site selectors get a fully-cited shortlist with PI, status, recent enrollment trend, and capacity signal — every claim traceable back to ClinicalTrials.gov or your CRO database. Time-to-shortlist drops from hours to minutes, audit trails are automatic, and your selectors focus on the judgment calls that actually need a human (relationship management, risk assessment, complex negotiations).

The result: faster trial start-up, fewer first-patient-in misses, and a defensible audit trail for every site decision.

## The problem (quantified)

For a typical mid-sized CRO running 30+ active trials with 3 site selectors per therapeutic area:

| Metric | Current state (industry-typical) | With agent (kit target) |
|---|---|---|
| Time to assemble candidate-site shortlist | 4–8 hours per trial | < 30 minutes per trial |
| Site identification's share of phase-3 timeline | 15–30% | 5–10% |
| Sites considered per trial | 30–80 (limited by selector bandwidth) | 200–500 (full data sweep) |
| Reproducibility of site-decision rationale | Poor — hours of email + spreadsheet archaeology | Full audit trail in CloudWatch logs |
| First-patient-in (FPI) milestone hit rate | Industry average ~50% | Aspiration: improve to 70%+ via better selection |

These industry baselines come from CRO industry surveys and are not specific to your organization — pilot the kit with a focused 6-month trial portfolio to ground real numbers.

## ROI model

**Assumptions to validate with your pilot:**

- Mid-size CRO running 30+ active trials at any time
- Site-selection takes ~15% of phase-3 trial timeline today
- 3–5 site selectors per therapeutic area (fully-loaded cost ~$200K each)
- 30% of FPI misses are caused by site-selection issues (vs. regulatory, contracting, supply-chain)
- Each missed FPI delays the trial by ~30 days; trial-day costs vary by phase ($30K–$80K/day for phase-3)

**Annual savings (per CRO running 30+ trials):**

| Category | Calculation | Annual value |
|---|---|---|
| Selector time reclaimed | 4 selectors × 30% time on shortlists × $200K | **$240,000** |
| Faster shortlist iteration cycles | 30 trials × 6 hours saved per shortlist round × $100/hr loaded | **$18,000** |
| Reduced FPI delays from better matching | 30 trials × 30% selection-driven delay × 30 days × $50K/day × 10% improvement | **$135,000** |
| Audit / compliance time savings | Compliance team time reconstructing rationale 90 days later, ~50 trials × 4 hours × $150/hr | **$30,000** |
| **Total annual value** | | **~$423,000** |

**AWS cost to run (per CRO at 200 queries/day):**

| Component | Monthly cost |
|---|---|
| Bedrock Agent invocations (200/day × 30) | ~$300–600 |
| Knowledge Base retrievals | ~$80–150 |
| AgentCore Gateway (MCP server traffic) | ~$50–100 |
| OpenSearch Serverless (KB vector store) | ~$200–400 |
| CloudWatch + S3 (logs + KB source) | ~$30–80 |
| **Total monthly** | **~$660–1,330** |
| **Total annual** | **~$8,000–16,000** |

**ROI: ~25x–50x return on AWS spend at the assumed profile above.**

## Build-level positioning

This kit is delivered at the **AgentCore Managed Harness** level. AWS manages the agent loop, compute, sandbox, memory, identity, observability, and VPC networking. You own the harness configuration, the connection to your CRO database, and the Knowledge Base content.

Managed-harness is the right level because the value is entirely in the prompt, the tools, and the Knowledge Base — no custom orchestration. If you're in a heavily-regulated subsegment and want a CloudFormation stack your auditors can read line-by-line, a `custom-iac` variant is feasible but is a separate kit, not a configuration of this one.

## Talking points

When making the case to your leadership:

- "Your site selectors spend 4–8 hours per trial assembling shortlists. The agent does it in 30 minutes with 5x more sites considered."
- "Every site recommendation is cited back to ClinicalTrials.gov or your CTMS. When your auditor asks 'why did you pick this site?' 90 days later, the answer reconstructs in 5 minutes instead of an afternoon of email archaeology."
- "The agent refuses PHI inputs by design. This is a site-selection tool, not a patient-matching tool. The compliance posture is dramatically simpler than anything that touches patient data."
- "Deploys in your account in 5–7 days. You own the agent, the data connection, and the audit trail. The kit gives you the harness config and the spec; your team runs it."

## Competitive positioning

- vs. **Veeva Vault CTMS / Medidata Rave-CTMS feasibility modules:** These are workflow tools that present pre-curated lists. They don't search natural-language queries against the live ClinicalTrials.gov data + your internal records simultaneously. This kit augments rather than replaces.
- vs. **Generic LLM "use ChatGPT for clinical research" tooling:** No grounding, no citation discipline, no integration with your CTMS, no PHI refusal. Different posture entirely.
- vs. **Building from scratch in-house:** 6+ months of engineering. This is 5–7 days to a working pilot.
- vs. **Microsoft Foundry healthcare templates:** Microsoft's prior-authorization template is the headline reference; site selection is an unfilled gap in that template library.

## Extending the kit

- **Additional therapeutic areas:** re-deploy the kit per major program with its own KB content and preferred-site lists.
- **Adjacent feasibility tools:** the same harness + Gateway pattern extends to investigator selection and other feasibility workflows.
