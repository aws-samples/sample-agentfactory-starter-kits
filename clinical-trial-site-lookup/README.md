# Clinical Trial Site Lookup — Starter Kit

> **Vertical:** Healthcare · **Sub-segment:** pharma sponsors + CROs
> **Build Level:** AgentCore Managed Harness
> **Deploy Time:** 5–7 days
> **Services:** Bedrock · AgentCore Managed Harness · AgentCore Gateway · Knowledge Bases · Guardrails · CloudWatch
> **Model:** Anthropic Claude 3.5 Sonnet (via Amazon Bedrock)

## What this solves

Site selectors at pharma sponsors and CROs spend hours per day in ClinicalTrials.gov and your internal CRO database trying to assemble a candidate-site shortlist for a new trial. Sites are missed, time-to-first-patient slips, and trial leads can't reproduce the rationale behind a shortlist 90 days later.

This kit deploys an AgentCore-hosted assistant that takes a natural-language query (therapeutic area, phase, geography, ranking criteria), searches both data sources, ranks candidates, and returns a fully-cited shortlist. Read-only — no PHI in scope.

## Outcomes

- **[X%] reduction** in site-identification cycle time per trial
- **[N hours/week] saved** per site selector on manual database queries
- **Auditable answer trail** with cited sources for every site recommendation
- **Faster trial start-up** with fewer activation delays from site mismatches

## ROI summary

| | |
|---|---|
| Annual savings | Not yet modeled — depends on your trial portfolio and selector headcount |
| Annual AWS cost | Primarily Bedrock invocations + Knowledge Base queries |
| Return on AWS spend | Model it with your own numbers using the framework below |

Full ROI model in [`business-case/roi-framework.md`](business-case/roi-framework.md).

## What's pre-built vs. what you customize

| Pre-built (in this kit) | You customize |
|---|---|
| AgentCore Managed Harness with the trial-site-lookup system prompt | Internal CRO database connection (CTMS / data warehouse) |
| ClinicalTrials.gov MCP server (read-only public API) | Therapeutic-area taxonomy + synonyms |
| Knowledge Base structure for taxonomy + site profiles | Site-ranking weights (enrollment / capacity / PI / geography) |
| Guardrails template (refuse PHI, no diagnostic claims, citation requirement) | Site shortlists (preferred / blocked) per program |
| CloudWatch dashboard | Geographic + time-zone preferences |
| `AGENTS.md` + `build-spec/` for your coding agent to implement | |

## Shared responsibility

Read-only kit. You own the deployed harness configuration, the Knowledge Base content, and the connection to your CRO database. AWS does not handle PHI in this kit by design — the agent refuses inputs containing PHI patterns and the data sources (ClinicalTrials.gov + your CRO database) are non-PHI. Scripts are provided as-is. Partners can offer managed support engagements if needed.

## Ideal customer

| | |
|---|---|
| **Size** | Mid-market pharma sponsors, CROs, academic medical centers running multi-site trials |
| **Volume** | 30+ active trials at any time; site selection touches 50–500 candidate sites per trial |
| **Team** | 1–5 site selectors per therapeutic area, supported by feasibility analysts |
| **Triggers** | Trials missing FPI milestones · selectors spending hours/day in CTMS · no structured site-comparison · leadership pressure on trial start-up speed |
| **Disqualifiers** | Single-site / investigator-initiated trials · no internal CRO database · contractually-fixed site lists |

---

## How this kit ships (Path B — spec-first)

This kit is **not yet built**. It ships as:
- **Kit metadata** (`kit.json`, this README, `architecture/`, `business-case/`)
- **Coding-agent contract** ([`AGENTS.md`](AGENTS.md) + [`build-spec/`](build-spec/))

You and your engineering team build the agent in your AWS account using the contract above and a coding agent of your choice (Kiro / Claude Code / Codex / Cursor). When the build is certified against [`build-spec/acceptance-tests.md`](build-spec/acceptance-tests.md), record where your implementation lives and bump `status` to `published`.

## Quick start

```bash
# 1. Open the kit in your coding agent of choice
cd clinical-trial-site-lookup

# 2. Read AGENTS.md — the build contract
# 3. Read build-spec/requirements.md — what the agent must do
# 4. Read build-spec/architecture-decisions.md — why these choices
# 5. Read build-spec/deployment-spec.md — what to create in your AWS account
# 6. Read build-spec/acceptance-tests.md — how to verify the build

# 7. Build in your AWS account against the spec
# 8. Run the acceptance tests (T1–T16)
# 9. Record where your implementation lives
# 10. Bump kit.json.status from "draft" to "published"
```

## Architecture (one-paragraph version)

A natural-language query goes to an AgentCore Managed Harness running Claude 3.5 Sonnet. The agent calls (1) a public ClinicalTrials.gov MCP server to find active trials matching therapeutic area / phase / geography, (2) your internal CRO database via two MCP servers behind AgentCore Gateway to enrich each candidate site with recent enrollment history, and (3) a Bedrock Knowledge Base for therapeutic-area synonyms and your own site profile notes. The agent ranks candidates using your configured weights, applies guardrails (refuse PHI inputs, no diagnostic claims, every claim must be cited), and returns a structured ranked shortlist with PI, status, enrollment trend, capacity, and rationale per site. Every query, tool call, and response is logged to CloudWatch with a 7-year retention policy for compliance audit.

Full diagram and component breakdown in [`architecture/architecture.md`](architecture/architecture.md).

---

**AgentFactory** · Vertical: Healthcare · Kit v0.1.0
