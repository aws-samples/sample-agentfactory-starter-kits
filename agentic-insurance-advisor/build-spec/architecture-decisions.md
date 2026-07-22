# Architecture Decisions — Agentic Insurance Advisor

> Audience: a coding agent that might be tempted to deviate. These are distilled from the source implementation (`agents/`, `infrastructure/template.yaml`, `data/rules/`) plus kit-level packaging decisions. Don't reverse them without checking with your build lead.

## AD1 — Supervisor-router topology, not one prompt
**Decision:** A supervisor agent (`agentCollaboration: SUPERVISOR_ROUTER`) orchestrates three single-responsibility specialists — Product Retrieval, Suitability, Recommendation — each its own Bedrock agent.
**Why:** Each step must be independently inspectable: retrieval grounded and cited, suitability a documented per-rule verdict, the letter a discrete artifact with disclosures. A mega-prompt collapses that separation and can't give compliance a decomposable trail.
**What this means for the build:** Keep the four agents separate; don't merge them to save calls. The supervisor routes and consolidates — it does not make recommendations itself.

## AD2 — Suitability rules externalized to YAML in S3
**Decision:** The eight rules (SUIT-01…SUIT-08), your criteria, and `verdict_if_violated` live in `data/rules/suitability-rules.yaml`, loaded at runtime by the action-group Lambda's `load_suitability_rules`.
**Why:** A your compliance team must be able to change a rule or threshold (e.g. the 10%-of-income affordability ceiling) without a code change or redeploy.
**What this means for the build:** Never hardcode rule logic into the agent prompt or Lambda. The YAML is the source of truth; the agent reasons over whatever it loads.

## AD3 — Deterministic verdict logic, model supplies reasoning
**Decision:** Overall verdict follows fixed precedence — any UNSUITABLE → UNSUITABLE; all pass → SUITABLE; some CONDITIONAL and none UNSUITABLE → CONDITIONAL. The model supplies per-rule reasoning and the citations.
**Why:** Verdicts must be reproducible and defensible to compliance. A worst-case-wins rule on a documented rule set is auditable; an LLM-chosen overall label is not.
**What this means for the build:** Encode the precedence in the suitability instruction (and ideally enforce it downstream); keep the rule IDs cited in every per-rule line.

## AD4 — Retrieval grounded in the Knowledge Base, with citations
**Decision:** Product Retrieval answers only from the indexed carrier documents (Bedrock KB over OpenSearch Serverless, Titan Text v2 embeddings) and returns source citations and eligibility checks.
**Why:** The agent must not invent products or eligibility — that's a compliance and trust failure in a regulated advisory.
**What this means for the build:** Keep retrieval KB-grounded; re-sync the KB when the catalog changes. Don't let the agent free-associate products.

## AD5 — Mandatory disclosure block on every letter
**Decision:** The standard not-FDIC-insured / not-a-deposit / not-financial-advice disclosure lives in the recommendation agent's instruction and appears on every generated letter.
**Why:** Missing disclosures are the most common compliance defect in hand-written letters; making it structural removes the failure mode.
**What this means for the build:** Compliance reviews and owns the disclosure wording, but the block is non-optional — don't make it conditional on letter content.

## AD6 — Per-agent model mix (Sonnet 4.5 / Nova 2 Lite / Nova Pro)
**Decision:** Suitability + supervisor reasoning on Claude Sonnet 4.5; Product Retrieval on Nova 2 Lite (fast, cheap RAG); Recommendation and (optionally) the supervisor on Nova Pro for speed (`agents/speed-up-models.sh`).
**Why:** Suitability is the reasoning-critical step and stays on the strongest tier; retrieval and letter writing are well served by faster, cheaper Nova models, which controls latency and cost on a 1–3 min multi-agent run.
**Alternatives considered:** All-Sonnet (rejected — slower and costlier with no quality gain on retrieval/letter).
**What this means for the build:** Don't downgrade suitability off Sonnet 4.5. Tune the rest to your latency/cost target.

## AD7 — Models served via inference profiles
**Decision:** Use `us.`-prefixed inference-profile IDs (`us.anthropic.claude-sonnet-4-5-…`, `us.amazon.nova-pro-v1:0`, `us.amazon.nova-2-lite-v1:0`) as the agent `foundationModel`.
**Why:** Claude 4.x and Nova are served via inference profiles; bare foundation-model IDs fail or aren't available cross-region.
**What this means for the build:** Don't hardcode bare model IDs; confirm inference-profile access in the target region.

## AD8 — Async job API, not synchronous request/response
**Decision:** `start_advisory.py` writes a job row, returns `202 + jobId`, self-invokes via `InvocationType=Event`, then calls `invoke_agent`; the SPA polls `get_job_status` / `get_job_result`.
**Why:** A four-agent run takes ~1–3 minutes — far beyond a comfortable synchronous HTTP timeout. Async decouples the long run from the request.
**What this means for the build:** Keep the create-job → self-invoke → write-result pattern; don't try to make the advisory synchronous.

## AD9 — Job state + partial results in DynamoDB with TTL
**Decision:** The `advisory-jobs` table holds job status, the per-stage partial results (`productResults`, `suitabilityResults`, `letterResult`), updated by the action group's `update_job_status`; the table has a TTL.
**Why:** Status transitions drive the UI progress tracker; partial results survive a sub-agent failure; the TTL keeps the table from accumulating stale jobs.
**What this means for the build:** Update status at each stage; production may need a longer-lived audit store than a TTL'd job table — flag this for review.

## AD10 — Single container of resources via CloudFormation, agents script-assisted
**Decision:** `infrastructure/template.yaml` provisions S3, DynamoDB, API Gateway, CloudFront/OAC, and four IAM roles in one stack; the Bedrock agents + KB + collaboration wiring are created by `setup-agents.sh` / `provision-agents.sh` (console/CLI-assisted), not CloudFormation.
**Why:** Multi-agent collaboration setup isn't cleanly expressible in CloudFormation today; the shared infra is.
**What this means for the build:** Deploy the stack first, then run the agent scripts; write the supervisor agent ID/alias into the `start-advisory` Lambda env.

## AD11 — Least-privilege IAM, scoped per role
**Decision:** Four roles — Bedrock agent role (`InvokeModel` on the specific Sonnet/Nova ARNs + KB `Retrieve` + Lambda invoke on `insurance-advisor-*`), KB role (product bucket + OpenSearch + Titan embed), action role (rules bucket read + jobs table update), API Lambda role (DynamoDB on the two tables + `bedrock:InvokeAgent`).
**Why:** Each component gets only what it needs; the blast radius of any one role is bounded.
**What this means for the build:** Keep the grants tight; widen deliberately, never with `*` on model/data actions where an ARN will do.

## AD12 — Decision-support, not autonomous advice
**Decision:** The output is a draft recommendation package for a licensed producer to review, edit, and own; nothing binds, issues, or sends a recommendation.
**Why:** Regulatory posture and accountability in insurance advisory — the licensed human is responsible for the recommendation.
**What this means for the build:** Never wire the package to an automated bind/issue/send action. The human is always in the loop.
