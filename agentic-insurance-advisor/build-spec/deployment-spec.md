# Deployment Spec — Agentic Insurance Advisor

> Audience: a coding agent provisioning resources in your account.

## Deployment context

- **Account:** your own AWS account (single-tenant).
- **Region:** `us-east-1` by default (where the model tiers were verified). Confirm Bedrock model access and multi-agent collaboration in the chosen region.
- **Trust boundary:** everything runs in your account; the only outbound dependency is in-region Bedrock model invocation. Client profiles live in your DynamoDB, product docs in your S3.
- **Delivery surface:** a React/Vite SPA on S3 + CloudFront, an async Lambda + API Gateway HTTP API, and four Bedrock agents under a supervisor router.

## Deploy paths

Run in order; each step has a script:

| Step | Script | What it does |
|---|---|---|
| 1. Infra | `infrastructure/deploy.sh` | CloudFormation: S3 buckets, DynamoDB tables, API Gateway, CloudFront/OAC, 4 IAM roles |
| 2. Seed data | `data/seed-data.sh` | Loads client profiles, the suitability rules YAML, and carrier product docs into S3/DynamoDB |
| 3. Agents | `agents/setup-agents.sh` then `agents/provision-agents.sh` | Deploys the action-group Lambda, creates the four agents, attaches the KB + action group, wires the collaborators, creates aliases |
| 4. API | `api/deploy-api.sh` | Deploys the 5 handler Lambdas; sets the supervisor agent ID/alias in `start-advisory` env |
| 5. Frontend | `frontend/deploy-frontend.sh` | Vite build → S3 → CloudFront invalidation |

Helper scripts in `agents/` (`speed-up-models.sh`, `fix-*.sh`, `publish-versions.sh`) tune model tiers and agent versions after provisioning.

## Resources to create

- **Storage:** three S3 buckets — `insurance-advisor-carrier-products-<account>` (KB source, versioned), `insurance-advisor-rules-config-<account>` (suitability YAML), `insurance-advisor-frontend-<account>` (SPA, OAC-locked).
- **Data:** two DynamoDB tables (PAY_PER_REQUEST) — `insurance-advisor-clients` (HASH `clientId`), `insurance-advisor-advisory-jobs` (HASH `jobId`, TTL on `ttl`).
- **AI/agents:** four Bedrock agents (supervisor `SUPERVISOR_ROUTER` + product-retrieval + suitability + recommendation); one Bedrock Knowledge Base + an **OpenSearch Serverless** vector collection (Titan Text v2 embeddings). Bedrock model access must be enabled (no resource, but a gate).
- **Compute:** six Lambdas — five API handlers (`list-clients`, `get-client`, `start-advisory`, `get-job-status`, `get-job-result`) + the suitability action-group Lambda (`insurance-advisor-suitability-actions`).
- **API:** API Gateway HTTP API + stage with routes to the handler Lambdas.
- **CDN:** CloudFront distribution + Origin Access Control fronting the frontend bucket.
- **Identity:** four IAM roles — API Lambda role, agent action-group role, Bedrock agent role, Bedrock KB role (see AD11 for scoping).
- **Observability:** CloudWatch logs for the Lambdas and Bedrock agent invocations.

## What you configure during the build

| Config item | Format | Source |
|---|---|---|
| Carrier product catalog | PDF / markdown docs indexed into the KB | `data/carrier-products/` (replace samples, re-sync KB) |
| Suitability rules + thresholds | YAML (SUIT-01…SUIT-08, criteria, `verdict_if_violated`) | `data/rules/suitability-rules.yaml` |
| Agent instructions | JSON `instruction` strings | `agents/{supervisor,product-retrieval,suitability,recommendation}/agent-config.json` |
| Disclosure block | Text inside the recommendation instruction | `agents/recommendation/agent-config.json` |
| Client profile schema + seed | JSON → DynamoDB `clients` table | `data/client-profiles/clients.json` |
| Per-agent model tier | Inference-profile IDs in the provisioning scripts | `agents/setup-agents.sh`, `agents/speed-up-models.sh` |
| Region / project prefix / naming | Script + env vars | `infrastructure/*.sh`, `agents/*.sh`, `api/*.sh` |

## What's pre-built

- The four-agent supervisor-router topology with provisioning scripts.
- The suitability action-group Lambda (`load_suitability_rules` from S3, `update_job_status` to DynamoDB) and the eight pre-authored rules.
- The CloudFormation template for all shared infra and the four least-privilege IAM roles.
- The async REST API (5 handlers) and the React + Vite producer UI with tabbed results + letter export.
- Six diverse sample client profiles and five sample carrier product documents for an end-to-end demo.

## Cost expectations

| Driver | Typical range |
|---|---|
| **OpenSearch Serverless (vector collection)** | **Fixed monthly OCU floor — dominates at low advisory volume; validate with your own numbers** |
| Bedrock — Claude Sonnet 4.5 (suitability + supervisor reasoning) | Largest per-advisory token cost; scales with volume |
| Bedrock — Nova 2 Lite (retrieval) + Nova Pro (optional routing/letter) | Low–moderate per advisory |
| Bedrock — Titan Text v2 (KB embeddings) | One-time per ingest + on re-sync |
| Lambda (6 functions) + API Gateway + DynamoDB (PAY_PER_REQUEST) | Negligible at advisory volumes |
| S3 + CloudFront + CloudWatch | Negligible / low |

## Pre-deployment checklist

- [ ] Bedrock model access enabled for Claude Sonnet 4.5, Nova 2 Lite, Nova Pro, and Titan Text v2 in the target region.
- [ ] Bedrock multi-agent collaboration available in the account/region.
- [ ] AWS CLI v2 configured with permissions for S3, DynamoDB, OpenSearch Serverless, Lambda, API Gateway, CloudFront, IAM, Bedrock Agents/KB.
- [ ] Carrier product catalog collected and ready to index; sample docs replaced in `data/carrier-products/`.
- [ ] Suitability YAML reviewed against your compliance standard; disclosure block signed off by compliance.
- [ ] Client-profile schema mapped to your CRM/policy-admin fields.
- [ ] Per-agent model tier decided against your latency/cost targets.

## Post-deployment validation

- [ ] CFN stack outputs present (bucket names, table names, API URL, CloudFront domain, role ARNs).
- [ ] Knowledge Base synced over your product documents; a test query returns cited products.
- [ ] All four agents provisioned; KB + action group attached; supervisor's three collaborators wired; aliases created.
- [ ] `start-advisory` Lambda env has the real supervisor agent ID + alias ID (not `PLACEHOLDER`).
- [ ] An advisory run returns `202 + jobId`, status transitions to `complete`, and the result has products (with citations), per-rule suitability verdicts, and a letter with the disclosure block.
- [ ] Forced sub-agent failure returns partial results, not a blank.
- [ ] The four IAM roles confirmed least-privilege (model ARNs scoped, no stray `*` on model/data actions).

## Day-2 operations (yours to run)

- Add **authentication** in front of the API Gateway HTTP API (reference is open).
- Integrate the client schema with your **CRM / policy-admin** system of record.
- **Re-sync the Knowledge Base** whenever the product catalog changes; retire discontinued products.
- Replace the TTL'd job table with a longer-lived **audit store** if retention/audit policy requires it.
- Set CloudWatch retention/alarms and Bedrock invocation logging.
- Manage Bedrock spend via the model mix; revisit the OpenSearch Serverless OCU floor against actual volume.
- Tear down with `aws cloudformation delete-stack --stack-name insurance-advisor-infra`; delete the Bedrock agents, Knowledge Base, and OpenSearch Serverless collection separately (console/CLI).
