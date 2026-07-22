# AGENTS.md — Clinical Trial Site Lookup

> Coding-agent contract for `clinical-trial-site-lookup`. Read this file first if you are a coding agent (Kiro, Claude Code, Codex, Cursor, or similar) being asked to build this kit.

## What this kit does

A site-selection assistant for pharma sponsors and CROs running multi-site clinical trials. Given a query like *"find me active phase-3 sites for non-small-cell lung cancer within 100 miles of Boston that have enrolled at least 5 patients in the last 12 months,"* the agent returns a ranked list of candidate sites with PI name, site status, recent enrollment trend, capacity signal, and a short rationale per site, every claim cited to a source.

**Vertical:** Healthcare (pharma sponsors + CROs)
**Build level:** AgentCore Managed Harness
**Build status:** Not yet built — implement against this spec

## Build-level guidance

This kit is `managed-harness`. AWS manages the agent loop, compute (microVM per session), sandbox, memory, identity, observability, and VPC networking. You own the harness configuration, the system prompt, the tool list, and the Knowledge Base content.

This is the right level for this kit because the value is entirely in: (1) the prompt, (2) the tools the agent calls (ClinicalTrials.gov MCP server + your CRO database MCP server + KB retrieval), and (3) the Guardrails. There is no custom orchestration logic. Do not promote this kit to `custom-iac` unless you need an audited CFN stack — that's a different kit, not a different build of this kit.

## What you (the coding agent) should do

This is a **Path B kit** — spec-first, no source code yet. Build the agent in your AWS account against this spec.

Read in order: `build-spec/requirements.md` (functional spec) → `build-spec/architecture-decisions.md` (build-level rationale + tools/KB/guardrails) → `build-spec/deployment-spec.md` (resources to create) → `build-spec/acceptance-tests.md` (how we know it works).

Do not commit code into the kit folder. The kit folder is catalog metadata, not the agent's source. When the build is done, record where your implementation lives.

## Required behavior

The agent must:

- Accept a natural-language query containing therapeutic area, trial phase, geography, and optional ranking criteria (enrollment performance, capacity, language, time zone)
- Resolve the therapeutic area against your taxonomy (synonyms, parent/child relationships)
- Search ClinicalTrials.gov via the public API for active trials matching the criteria
- Cross-reference candidate sites against your internal CRO database (recent enrollment performance, prior trial history, current activation status)
- Rank sites using configurable weights (enrollment speed, capacity, PI track record, geographic distance)
- Return the top N results (default 10, max 50) with PI name, site status, enrollment trend, capacity signal, and a one-sentence rationale per site
- **Cite the source for every claim.** No claim about a site goes out without a citation back to ClinicalTrials.gov or your CRO database, with a retrievable identifier
- Refuse queries that contain PHI (patient identifiers, MRN, DOB) — this is a site-selection tool, not a patient-matching tool
- Refuse to make diagnostic, dosing, or treatment-recommendation claims

## Tools the agent needs

| Tool | Type | Source | Purpose |
|---|---|---|---|
| `ctgov_search` | MCP server | Public ClinicalTrials.gov API | Search active trials by condition, phase, location, status |
| `ctgov_site_detail` | MCP server | Public ClinicalTrials.gov API | Fetch site details for a given NCT ID + facility ID |
| `cro_db_search` | MCP server (you build) | Your CRO database | Search internal site records by PI, geography, therapeutic area |
| `cro_db_enrollment_history` | MCP server (you build) | Your CRO database | Fetch a site's enrollment history across past trials |
| `kb_retrieve` | AgentCore Knowledge Base | Therapeutic-area taxonomy + site profile docs | RAG retrieval for synonyms, site notes |

The two `cro_db_*` MCP servers are kit-your own. You point the agent at your CTMS / data warehouse / proprietary store. The kit ships pattern code + an MCP server template; your coding agent fills in your connection details.

The two `ctgov_*` MCP servers can be a published public MCP wrapper around ClinicalTrials.gov. If one doesn't exist at build time, your coding agent builds a thin one — the API is REST + JSON, no auth, low complexity.

## System prompt

The agent's system prompt should establish:

```
ROLE
You are a clinical trial site-selection assistant for [your CRO/sponsor name].
You help site selectors find research sites for active trials.

WHEN A USER ASKS YOU SOMETHING
1. If the query contains PHI (patient identifiers, MRN, DOB, etc.), refuse and explain
   that this tool is for site selection only.
2. If the query asks for diagnostic, dosing, or treatment recommendations, refuse.
3. Otherwise: parse the query into therapeutic-area, phase, geography, and ranking criteria.
4. Resolve the therapeutic area using kb_retrieve to expand synonyms.
5. Search ClinicalTrials.gov via ctgov_search.
6. For each candidate, fetch site details via ctgov_site_detail and enrich with
   cro_db_enrollment_history.
7. Rank using the configured weights.
8. Return the top N results in structured form: site_name, PI, status, enrollment_trend,
   capacity_signal, rationale, citations.

ALWAYS
- Cite every factual claim. Format: "[Source: ClinicalTrials.gov NCT12345678]" or
  "[Source: CRO_DB site_id=XYZ trial_history_2024]"
- Respect the configured max-results limit.
- If you cannot find data, say so. Do not invent enrollment numbers, PI names, or capacity claims.
- If a site appears in your blocked list, exclude it and note exclusion in the
  audit log (do not show to the user as a result).

NEVER
- Make diagnostic claims, treatment recommendations, or dosing guidance.
- Process or retain patient identifiers.
- Speculate about PI quality, site reputation, or other unverifiable attributes.
- Substitute your judgment for your site-selection criteria — return ranked
  candidates and rationale, not "this site is best."
```

The full prompt with your specific CRO name + therapeutic area defaults goes in `harness.json` once your coding agent fills it out.

## Conventions

- **AWS region:** Configurable per deployment; pharma organizations in the US default to `us-east-1`, EU deployments to `eu-west-1` for residency.
- **Logging:** Every query, tool call, and response goes to CloudWatch with structured logs. Log levels: INFO for normal flow, WARN for guardrail triggers (PHI, off-topic), ERROR for tool failures.
- **Guardrails:** Bedrock Guardrails enforce: PHI redaction (never logged or stored, refusal triggered), topic deny-list (no diagnostic / dosing / treatment claims), grounding check (refuse if no source available), content filters (HIGH on sexual/violence/hate).
- **Citation requirement:** Every output goes through a post-check that confirms each factual claim has a citation. Outputs without citations are blocked at the harness layer.
- **Cost target:** ~$0.10–0.30 per query at managed-harness baseline (Bedrock invocation + KB retrieve + 2–3 MCP tool calls).
- **You customize** (don't hardcode these — make them configurable):
  - Internal CRO database connection (BigQuery / Postgres / Snowflake / proprietary CTMS)
  - Therapeutic-area taxonomy and synonyms specific to the sponsor
  - Site-ranking weights (enrollment speed vs. capacity vs. PI track record)
  - Site shortlists (preferred / blocked) per program
  - Geographic constraints and time-zone preferences

## Acceptance — how we know it works

Before bumping `kit.json.status` from `draft` / `in-build` to `published`:

1. All acceptance tests in `build-spec/acceptance-tests.md` pass against your data
2. Guardrails fire correctly on synthetic PHI inputs and out-of-scope queries
3. Citation rate ≥ 99% — measured as queries where every factual claim has a verifiable citation
4. CloudWatch dashboard shows expected metrics (queries/day, citation rate, source mix, p95 latency)
5. You and your site-selection lead have reviewed at least 30 real production-shaped queries against your data and confirmed the rankings match (or are explainable improvements over) human expert judgment
6. Blocked-list and PHI refusal both demonstrated end-to-end

## Repository convention

This kit folder (`clinical-trial-site-lookup/`) is **catalog metadata**, not the agent's source code. When your coding agent finishes building, the source lives in your repository — the implementation is built from this spec.

Do NOT add agent code under this kit folder.

## When you finish a build

Record where your implementation lives, then bump `kit.json.status` from `draft` to `published` once you have reviewed the build against the acceptance tests.
