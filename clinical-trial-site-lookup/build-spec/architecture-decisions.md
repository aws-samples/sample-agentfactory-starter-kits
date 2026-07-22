# Architecture decisions — Clinical Trial Site Lookup

Why this kit picked this build level, and the design choices the coding agent should not undo without re-opening these decisions.

## Build level: AgentCore Managed Harness

This kit uses AgentCore Managed Harness because the value is entirely in (1) the prompt, (2) the tools the agent calls, and (3) the Guardrails. There is no custom orchestration logic that justifies hand-rolling the agent loop or shipping a CloudFormation stack you audit line-by-line.

### Why not the other build levels?

- **Why not `managed-agents-openai`:** This kit doesn't need OpenAI frontier models. Claude 3.5 Sonnet on Bedrock handles the natural-language parsing, tool orchestration, and citation discipline with room to spare. The OpenAI variant adds Limited Preview gating without a corresponding capability gain. If your procurement mandates OpenAI for procurement reasons, ship a separate `clinical-trial-site-lookup-openai` kit later.
- **Why not `custom-iac`:** No part of this kit needs custom Lambda action groups. Site search, enrichment, ranking — all of it is the LLM calling MCP servers. Custom IaC would mean writing Lambdas you audit, when the same logic lives more cleanly in your own MCP server code (which is already part of the build).

Organizations in heavily-regulated subsegments (e.g. trials run under FDA IND with specific data-handling SOPs) may ask for `custom-iac`. That's a kit variant, not a deviation from the default. Open a separate kit folder if needed.

## Model

- **Provider:** Amazon Bedrock
- **Model id:** `anthropic.claude-3-5-sonnet-20241022-v2:0`
- **Why this model:** Claude 3.5 Sonnet handles structured output (the JSON-shaped site list) reliably, follows citation discipline well, and refuses out-of-scope inputs without prompting workarounds. Cost per query stays within the $0.10–$0.30 envelope. Newer Claude versions (Sonnet 4.5+ via inference profiles) are interchangeable when available — bump the model id in the harness config to migrate, no other changes needed.

## Tools

| Tool | Type | Source | Rationale |
|---|---|---|---|
| `ctgov_search` | MCP server | Public ClinicalTrials.gov API | The trial-discovery primitive. Public, no auth, well-documented. |
| `ctgov_site_detail` | MCP server | Public ClinicalTrials.gov API | Per-site enrichment (PI name, location, status). Same source as `ctgov_search`. |
| `cro_db_search` | MCP server (you build) | Your CTMS / data warehouse | Your own site records. Sites won't share this data publicly, so this MCP server lives on you side. |
| `cro_db_enrollment_history` | MCP server (you build) | Your CTMS / data warehouse | Recent enrollment performance — the most important ranking signal. |
| `kb_retrieve` | AgentCore Knowledge Base | Therapeutic-area taxonomy + site profile docs | Synonyms (e.g. "NSCLC" ↔ "non-small cell lung cancer"), your own notes. |

The two `ctgov_*` MCP servers can be a single shared MCP wrapper. If a published one exists, use it. If not, your coding agent builds a thin one — REST + JSON, no auth, ~50 lines of code per endpoint.

The two `cro_db_*` MCP servers are kit-your own and cannot be shipped pre-built. The kit ships an MCP server template (FastAPI / TypeScript / whatever you prefer) with the tool schemas; your coding agent fills in the database connection.

## Knowledge Base

- **Source data:**
  - Your therapeutic-area taxonomy (synonyms, parent/child relationships)
  - You curate site profile notes (free-text "this site is good at X" notes from feasibility analysts)
  - Optional: extracted abstracts from past site qualification visits
- **Chunking strategy:** 512 tokens, 100 overlap. Therapeutic-area taxonomy is short text; site profiles are longer. The chunking handles both reasonably without per-source tuning.
- **Embedding model:** `amazon.titan-embed-text-v2:0`
- **Vector store:** OpenSearch Serverless (default for AgentCore harness KB)

The KB is **not** the primary data store — that's ClinicalTrials.gov + your CRO database. The KB enriches the agent's understanding of your vocabulary and adds qualitative context the structured databases don't capture.

## Guardrails

Layer 1 (Bedrock Guardrails — pre-LLM):
- **PHI redaction:** Block inputs containing patient identifiers, MRN, DOB, name+DOB combinations. Your own PII patterns are added to the guardrail config.
- **Topic deny-list:** Block diagnostic claims, dosing recommendations, treatment guidance, patient-matching requests.
- **Content filters:** HIGH on sexual / violence / hate (these shouldn't trigger in a trial-site context; HIGH catches anomalies).

Layer 2 (kit-specific output checks — post-LLM):
- **Citation regex:** Every output is scanned for factual claims (numbers, named entities, dates, status assertions) and confirmed each has a citation immediately following. Outputs without citations are rejected; the agent retries up to 3 times before returning "cannot answer with available data."
- **Blocked-site filter:** Sites in your blocked list are removed from results before output. The exclusion is logged for audit but not shown to the user.

Layer 3 (compliance audit — post-output):
- Every query, tool call, and response is logged to CloudWatch with structured fields: user identity, query text (PHI-redacted), tools called, sites returned, citation presence per claim. Logs are retained per your compliance policy (typically 7 years for clinical research).

## Open architecture questions

Decisions still open at the time the kit shipped. The coding agent should flag these for review before making the call:

- **MCP server hosting for `ctgov_*`:** publish a community MCP server that all users point at, or have each your coding agent build its own thin wrapper? Centralized is more efficient; per-deployment is more robust to availability shifts. Default = per-deployment until usage justifies a central one.
- **Inference profile vs. foundation-model id:** Claude Sonnet 4.5 / 4.6 are inference-profile-only. As of writing, Claude 3.5 Sonnet (foundation-model id) is the safe default. If you have access to newer Claude via inference profiles should override `harness.json.model.id` to `us.anthropic.claude-sonnet-4-5-20250929-v1:0` or similar.
- **Memory:** Should the agent remember your last few queries within a session for context (e.g., "now show me the same trial in the EU")? Default = session-scoped short-term memory enabled, no long-term memory. You can opt into long-term memory for your site-selection team's accumulated criteria, but only after the privacy review.
- **Free-text PI notes from past visits:** Organizations vary in whether they have these and whether they're appropriate to include in the KB. Default = excluded; opt-in per deployment.
