# Deployment Spec — Agentic PXM Platform

> Audience: a coding agent provisioning resources in your account, and the build lead verifying before bumping kit status.

## Deployment context

- **Account:** your own AWS account.
- **Region:** `us-east-1` by default (`CDK_DEFAULT_REGION` / `AWS_REGION`). Confirm Bedrock model access in the chosen region.
- **Trust boundary:** everything runs in your account; the only outbound dependency is in-region Bedrock (and optionally an AgentCore runtime).
- **Delivery unit:** six AWS CDK (Python) stacks deployed via `cdk deploy --all` (or `./deploy.sh`), plus a seed script and a demo Cognito user.

## Deploy path

`./deploy.sh` runs the full sequence (or `./deploy.sh synth` to validate only):

| Step | What it does |
|---|---|
| 0–1 | Confirm AWS credentials; install Python deps (`.venv` + `infra/requirements.txt`) |
| 2 | `cdk bootstrap` (idempotent) |
| 3 | Initial frontend build (placeholder config) so `FrontendStack` has an asset |
| 4 | `cdk deploy --all` → all six stacks, outputs written to `infra/cdk-outputs.json` |
| 5 | Write `frontend/public/config.json` from stack outputs (API URL, user pool, client, region) → rebuild → redeploy `PxmFrontendStack` |
| 6 | Seed master data + RAG corpus + products (`infra.seed.seed_data <tenant>`) |
| 7 | Create the demo Cognito user (email/password, tenant, `admin` group) |

Teardown: `cd infra && cdk destroy --all` (all dev resources use `RemovalPolicy.DESTROY`).

## Resources to create (by stack)

- **DataStack:** DynamoDB table `pxm` (PK/SK + GSI1, on-demand, AWS-managed encryption, point-in-time recovery); OpenSearch Serverless `VECTORSEARCH` collection `pxm-rag` (+ encryption & network security policies); S3 docs/corpus bucket (encrypted, public access blocked, SSL enforced).
- **AuthStack:** Cognito user pool (`custom:tenant_id` attribute, email sign-in, min-8 password policy); groups `admin` / `operator` / `viewer`; an SPA app client (USER_PASSWORD + SRP auth, no secret).
- **AgentStack:** four Lambdas (`EnrichmentFn`, `AutoApproveFn`, `ReviewGateFn`, `PublishFn`, Python 3.12, X-Ray active); the Step Functions state machine `EnrichmentSaga` (3-day timeout, tracing on); Bedrock + AgentCore IAM policies scoped to the roles.
- **ApiStack:** BFF Lambda (`services.api_bff.lambda_entry.handler`); API Gateway `LambdaRestApi` (proxy, `dev` stage, CORS) with a Cognito user-pool authorizer; the OpenSearch data-access policy for all RAG consumer roles.
- **FrontendStack:** S3 bucket + CloudFront distribution serving the built React SPA.
- **ObservabilityStack:** CloudWatch dashboard `pxm-dev` (Lambda invocations, errors, p95 duration for the agent + BFF functions).

## IAM permissions (least privilege)

- Agent + BFF roles: `bedrock:InvokeModel` on `arn:aws:bedrock:<region>::foundation-model/anthropic.*` + `.../amazon.titan-embed-*`; `bedrock-agentcore:InvokeAgentRuntime` (tighten to the runtime ARN once deployed).
- DynamoDB read/write on the `pxm` table (granted per function).
- BFF: Step Functions `StartExecution` + task-response (for the HITL `SendTaskSuccess`).
- RAG consumers: `aoss:APIAccessAll` on the collection ARN + an OpenSearch data-access policy (`CreateIndex`, `ReadDocument`, `WriteDocument`, collection items).
- API Gateway authorization via the Cognito user pool.

## Secrets and credentials

- No long-lived application secrets in the reference — auth is Cognito JWT; AWS access is via task/Lambda execution roles.
- If a your real channel adapter needs marketplace credentials, store them in AWS Secrets Manager (or AgentCore Identity) and grant the publish Lambda scoped read — never embed in code.

## What you configure during the build

| Config item | Format | Source |
|---|---|---|
| Enrichment stage logic (attributes, classify, copy, compliance rules) | Python | `services/agent/enrichment_agent.py` |
| Master data + RAG corpus | JSON fixtures | `data/products.json`, `suppliers.json`, `regulations.json`, `corpus.json` |
| Domain models / SKU validation + lifecycle | Python | `shared/models.py`, `shared/lifecycle.py` |
| Channel adapters | Python (`ChannelAdapter` protocol) | `services/review_channel/channel.py` |
| Model provider + model IDs | Env | `PXM_PROVIDER`, `PXM_BEDROCK_TEXT_MODEL`, `PXM_BEDROCK_EMBED_MODEL` (`shared/providers.py`) |
| Table/collection/stack naming, region, Cognito groups | CDK params + env | `infra/stacks/`, `infra/app.py` |
| React console | TS/React | `frontend/src/` |

## What's pre-built

- The four-stage `EnrichmentAgent` with the pluggable `LLMProvider` (Bedrock / AgentCore / fake).
- The Step Functions saga + per-state Lambda handlers with the `waitForTaskToken` HITL gate.
- The RAG service over OpenSearch Serverless k-NN with an in-memory fallback.
- The DynamoDB single-table data layer with tenant-prefixed keys + GSI1 and the validated lifecycle.
- All six CDK stacks, `deploy.sh`, the seed script, and the React/TS console.
- The `pytest` + Hypothesis backend suite, the Vitest + fast-check frontend suite, the AWS-free `run_local_demo`, and the CI workflow.

## Cost expectations

| Driver | Typical range |
|---|---|
| Bedrock (Claude 3.5 Sonnet) | ~3 model calls per SKU enrichment (+ chat tokens); compliance check is free (deterministic) — model per SKU volume |
| Bedrock (Titan Embeddings v2) | RAG ingest (one-time per corpus update) + per-query retrieval — low |
| OpenSearch Serverless | **Minimum always-on OCU cost regardless of throughput** — the dominant fixed cost; size to volume |
| Lambda + Step Functions | Per-stage invocations + state transitions per run — low |
| DynamoDB (on-demand) | Reads/writes per SKU + status transitions — low |
| API Gateway / CloudFront / S3 / CloudWatch / X-Ray | Console traffic, hosting, logs, traces — negligible-to-low |

## Pre-deployment checklist

- [ ] Bedrock access enabled for Claude 3.5 Sonnet + Titan Embeddings v2 in the target region.
- [ ] AWS CLI + CDK CLI (≥ 2.150) configured; Python ≥ 3.12; Node ≥ 18.
- [ ] Master data + RAG corpus (`data/`) replaced with your taxonomy, brand guidelines, regulations.
- [ ] Enrichment stages + compliance rules tuned to your product domain.
- [ ] Channel adapter(s) implemented (or the mock accepted for the pilot).
- [ ] Tenant id(s) and Cognito group mapping decided.

## Post-deployment validation

- [ ] `cdk deploy --all` completes; `infra/cdk-outputs.json` has the API URL, user pool, client id, table, and OpenSearch endpoint.
- [ ] Seed script loads master data + corpus for the demo tenant; demo Cognito user can sign in.
- [ ] A clean SKU auto-approves and publishes (listing id returned).
- [ ] A blocker SKU pauses in `NEEDS_REVIEW` with a cited `reg_id`, and publishes only on operator approval.
- [ ] Tenant isolation + role gating verified (cross-tenant read denied; viewer cannot start/approve).
- [ ] IAM roles confirmed least-privilege; acceptance tests pass.

## Day-2 operations (yours to run)

- Harden production defaults: change `RemovalPolicy.DESTROY`, lock down the OpenSearch network policy (currently `AllowFromPublic`), set CloudWatch log retention + alarms.
- Tighten the `bedrock-agentcore:InvokeAgentRuntime` scope to the deployed runtime ARN.
- Keep the regulation corpus current per market; add new restricted substances / prohibited claims as rules change.
- Re-tune enrichment stage prompts and the brand corpus as the catalog and brand voice evolve.
- Manage Bedrock spend vs. SKU volume and right-size OpenSearch Serverless OCUs.
- Wire real channel adapters and connect real master data in place of the seeded fixtures.
- Tear down with `cdk destroy --all` when decommissioning.
