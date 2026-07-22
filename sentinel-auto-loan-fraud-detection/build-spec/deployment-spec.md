# Deployment Spec — Sentinel Auto-Loan Fraud Detection

> Audience: a coding agent provisioning resources in your account.

## Deployment context

- **Account:** your own AWS account (single-tenant).
- **Region:** `us-east-1` by default (where the Claude tiers were verified). Confirm Bedrock model access in the chosen region.
- **Trust boundary:** everything runs in your account; the only outbound dependency is in-region Bedrock model invocation.
- **Source code location:** not included in this kit — the kit folder holds metadata + specs only. The implementation is built from this spec and lives in your own repository.
- **Delivery unit:** one container image (built SPA + FastAPI) on App Runner, port 8000.

## Deploy paths

Two scripts in `infra/`:

| Script | When | What it does |
|---|---|---|
| `deploy-codebuild.sh` | No local Docker (used for the live demo) | Zips source → S3 → CodeBuild builds image → ECR → creates/updates App Runner service |
| `deploy-apprunner.sh` | Local Docker available | Builds image locally → ECR → App Runner |
| `destroy-apprunner.sh` | Teardown | Removes the App Runner service to stop billing |

## Resources to create

- **Compute:** App Runner service (`sentinel-fraud`), 1 vCPU / 2 GB, health check `GET /api/health`, env `MOCK_MODE=false`, `AWS_REGION`, `BEDROCK_MODEL_KEY=balanced`.
- **Container registry:** ECR repository (`sentinel-fraud`).
- **Build (CodeBuild path):** CodeBuild project (`sentinel-image-build`, privileged for Docker), S3 source bucket (`sentinel-build-<account>-<region>`).
- **AI/agent:** Bedrock model access (Claude Sonnet 4.5 default) via inference profiles — no resource to create, but access must be enabled.
- **Identity:** three IAM roles — `SentinelAppRunnerInstanceRole` (Bedrock invoke only, from `infra/bedrock-policy.json`), `SentinelAppRunnerECRAccessRole` (ECR pull), `SentinelCodeBuildRole` (logs + S3 get + ECR push).
- **Observability:** CloudWatch logs (App Runner + CodeBuild + Bedrock invocation logging).

## What you configure during the build

| Config item | Format | Source |
|---|---|---|
| Application schema | `LoanApplication` Pydantic model | `backend/models.py` |
| Agent system prompts | Python string constants | `backend/agents/*.py` |
| Heuristic rules + thresholds | Python logic | `backend/mock_results.py` |
| Scoring weights + cutoffs | Constants | orchestrator + `mock_results.py` |
| Model tier | Key in `MODEL_CHOICES` | `backend/bedrock_client.py` |
| Region / service / role names | Env + script vars | `infra/*.sh` |

## What's pre-built

- The four-agent pipeline, Bedrock client, heuristic engine, FastAPI app, and React SPA.
- Both deploy scripts, the teardown script, the Dockerfile, the buildspec, and the scoped Bedrock IAM policy.
- The pytest + Hypothesis test suite and three tuned sample scenarios.

## Cost expectations

| Driver | Typical range |
|---|---|
| Bedrock (Claude Sonnet 4.5) | Scales with applications × 4 agent calls + chat tokens — model per volume |
| App Runner (1 vCPU / 2 GB) | ~$5–25/mo light; scales with traffic |
| ECR / S3 / CodeBuild | Negligible (storage + build-time only) |
| CloudWatch | Low |

## Pre-deployment checklist

- [ ] Bedrock access enabled for the chosen Claude tier in the target region.
- [ ] AWS CLI v2 configured with permissions for App Runner, ECR, CodeBuild, S3, IAM.
- [ ] Application schema (`LoanApplication`) mapped to your data.
- [ ] Agent prompts + heuristics tuned to your product.
- [ ] Scoring weights/cutoffs reviewed against your risk appetite.
- [ ] Decision: which deploy path (CodeBuild vs local Docker).

## Post-deployment validation

- [ ] `GET /api/health` returns `status: ok` with the expected mode/region/model.
- [ ] A sample application returns a verdict with narrative + contributions.
- [ ] Forced Bedrock failure falls back to heuristics (provenance badge shows `heuristic`).
- [ ] Acceptance tests pass against the deployed instance.
- [ ] Instance role confirmed least-privilege (Bedrock invoke only).

## Day-2 operations (yours to run)

- Add a persistent datastore (reference is in-memory).
- Add authentication in front of the App Runner service.
- Set Bedrock invocation logging + CloudWatch retention/alarms.
- Re-tune prompts/thresholds as fraud patterns evolve.
- Manage Bedrock spend via the live-vs-heuristic routing split.
- Tear down with `destroy-apprunner.sh` when decommissioning.
