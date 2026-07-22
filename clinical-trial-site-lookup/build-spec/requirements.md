# Requirements — Clinical Trial Site Lookup

This is the functional specification for the agent. A coding agent reads this to build the kit; you read this to certify the build matches the spec.

## The problem

Site selectors at pharma sponsors and CROs spend hours per day in ClinicalTrials.gov and your internal CRO database trying to assemble a candidate-site shortlist for a new trial. The work is repetitive: the same therapeutic-area searches, the same enrichment from internal enrollment-history records, the same filtering by geography and capacity. Sites are missed, time-to-first-patient slips, and the trial team can't reproduce or audit the rationale behind a shortlist.

This kit gives site selectors a natural-language interface that searches both data sources, ranks candidates by configurable criteria, and produces an auditable shortlist with citations.

## Functional requirements

Ordered by priority. The agent must:

1. **Accept a natural-language query** describing the trial's therapeutic area, phase, geography, and any ranking preferences.
   - Example: *"Find phase-3 NSCLC sites within 100mi of Boston with at least 5 patients enrolled in the last 12 months."*
   - The agent parses this into structured criteria using the LLM + the kit's KB-resident therapeutic-area taxonomy.

2. **Search ClinicalTrials.gov** for active trials matching the structured criteria.
   - Use the `ctgov_search` MCP tool.
   - Filter to studies with `OverallStatus IN ('Recruiting', 'Active, not recruiting')` unless the user asks otherwise.

3. **Enrich each candidate site** with your internal CRO data:
   - Recent enrollment performance (patients enrolled in the last 6 / 12 / 24 months across all trials at this site)
   - Site activation status in your CTMS
   - PI's prior trial history at this site (for the same therapeutic area and adjacent areas)

4. **Rank the candidate sites** using your configured weights. Default weighting:
   - Recent enrollment performance: 40%
   - PI prior-trial track record (same therapeutic area): 30%
   - Geographic distance to the trial center / patient population: 20%
   - Site activation speed (historical days from contract to first patient in): 10%

5. **Return the top N sites** (default 10, max 50) in a structured response with:
   - Site name + address
   - PI name + degree
   - Site status (active / inactive / pending)
   - Recent enrollment trend (e.g. "12 patients in last 12 months across 3 trials, trending up")
   - Capacity signal (e.g. "currently enrolling on 4 trials; historical max is 7")
   - One-sentence rationale ("Selected because: top quartile enrollment in NSCLC, PI has run 3 prior phase-3 trials with this sponsor, 87mi from Boston")
   - Citation per claim — see *Citation requirement* below

6. **Refuse PHI inputs.** If the user includes patient identifiers, MRN, DOB, or any clearly-patient-level data in the query, refuse with: "This tool is for site selection only. Please remove any patient information from your query." Log the refusal but never log the offending query content.

7. **Refuse out-of-scope queries.** Diagnostic claims ("does this drug treat X?"), dosing recommendations, or patient-matching queries get refused. The kit is read-only site discovery; broader healthcare claims belong elsewhere.

## Non-functional requirements

| Requirement | Target | Why |
|---|---|---|
| Latency (p95) | < 8s end-to-end | Site selectors expect interactive feel; 8s is acceptable for a multi-tool query, slower than that turns into "I'll just use the portal." |
| Throughput | 50–500 queries/day per deployment at steady state | One per active trial × selectors per trial × iterations |
| Citation rate | ≥ 99% of factual claims | Every claim about a site must be cite-able back to ClinicalTrials.gov or your CRO database. Missing citations are blocked at output. |
| PHI containment | 100% — no PHI ever logged or persisted | Even though this kit doesn't process PHI by design, the guardrail catches accidental input |
| Auditability | Every query + response logged with structured trail | Your compliance teams must be able to reproduce a recommendation 90 days later |
| Cost per query | $0.10–$0.30 | Drives the ROI envelope |
| Source freshness | ClinicalTrials.gov data ≤ 24 hours old | Your CTMS data is real-time |

## Inputs

- **Source:** A query string (natural language) plus optional structured filters (specific NCT IDs to include or exclude, your preferred / blocked site list to apply).
- **Format:** JSON or chat — depending on whether you surface this through your site-selection portal, a Slack bot, an internal app, or directly via the AgentCore harness API.
- **Volume:** 50–500 queries/day per deployment.
- **Authentication:** AWS IAM at the harness layer; your app authenticates the user upstream and passes user identity through to CloudWatch logs for audit.

## Outputs

- **Destination:** Whatever your app does with the response — typically renders the shortlist in your site-selection UI, optionally exports to Excel/CSV for the trial team.
- **Format:** Structured JSON, with each ranked site as an object containing the fields listed in functional requirement 5.
- **Side effects:** Every query and response is logged to CloudWatch with structured fields for compliance audit. No data is written back to ClinicalTrials.gov or your CRO database — this kit is read-only.

## Citation requirement

Every factual claim about a site in the output must include a citation. Format:

```
"[Source: ClinicalTrials.gov NCT12345678 #facility-7]" — for trial-level data
"[Source: CRO_DB site_id=XYZ enrollment_history.2024-Q3]" — for internal data
"[Source: KB therapeutic-area-taxonomy.NSCLC.synonyms]" — for KB-derived inferences
```

The harness's output guard runs a regex over each response to confirm every numerical or factual claim has a citation immediately following it. Outputs without citations are rejected and the agent is asked to retry with citations. After 3 retry failures, the agent returns "I cannot answer this query with the data available — please refine the query or check the source MCP servers."

## Out of scope

The agent must NOT:

- Match patients to trials. (Different use case, different kit, different regulatory stance.)
- Make diagnostic, dosing, or treatment recommendations.
- Score or rank PI quality on attributes that aren't in your data (no inferred reputation).
- Speculate about why a site might or might not perform — only report what the data says.
- Recommend "best site." It returns a ranked list and the rationale; your site-selection lead picks.
- Modify ClinicalTrials.gov or your CRO database (read-only).

## Success metrics

The agent is working correctly when:

- Site selectors save measurable time per trial (target: 50%+ reduction in shortlist-assembly hours)
- The shortlist hit rate (sites that survive your full feasibility process) matches or exceeds the human-only baseline
- 99%+ of outputs are fully cited
- 0 PHI leaks in the audit log
- Your trial leads can reproduce any recommendation 90 days after it was made
