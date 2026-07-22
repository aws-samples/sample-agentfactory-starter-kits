# Deployment Spec — Automated Docs Generator

> What gets deployed and how, for the coding agent provisioning resources in your AWS account.

## Deployment context

- **Account:** Your own AWS account.
- **Region:** Default `us-east-1` (configurable; keep all resources in one region).
- **Trust boundary:** Everything runs in your account/VPC. The browser agent reaches out to your own target app with credentials you supply at run time.
- **Source code location:** Built in your repository (Path B). The kit folder holds only metadata; record where your implementation lives when done.
- **IaC:** AWS CDK (TypeScript). `deploy.sh` orchestrates build + deploy.

## Resources to create

**Networking**
- VPC (`maxAzs: 2`, `natGateways: 1`)
- Private-with-egress subnets for Fargate tasks; security group for the tasks

**Compute**
- ECS Fargate cluster
- Screenshot task definition (4096 MiB / 2048 CPU), container built from `screenshot-job/` (`linux/amd64`)
- Generate task definition (4096 MiB / 2048 CPU), container built from `generate-job/` (`linux/amd64`)
- Lambda function (Node 20, esbuild bundle) for the API

**AI / automation**
- Bedrock model access to `us.anthropic.claude-sonnet-4-5-20250929-v1:0`
- Amazon Nova Act access (preview)

**API / edge**
- API Gateway (REST) fronting the Lambda, with CORS preflight configured
- CloudFront distribution serving the frontend S3 bucket

**Storage**
- Data bucket: screenshots, descriptions, generated guides (CORS for GET/PUT/POST; block public access)
- Frontend bucket: hosts the React build (block public access; served via CloudFront/OAC)
- DynamoDB runs table (PK `runId`, SK `createdAt`, PAY_PER_REQUEST)
- DynamoDB sections table (PK `runId`, SK `sectionId`, PAY_PER_REQUEST)
- ECR repositories (managed by CDK asset publishing)

**Identity (IAM)**
- Screenshot task role: S3 (data bucket) + DynamoDB (both tables) + `bedrock:InvokeModel` + Nova Act
- Generate task role: S3 + DynamoDB + `bedrock:InvokeModel` + `bedrock:InvokeModelWithResponseStream`
- Lambda role: DynamoDB + S3 + `ecs:RunTask` (both task defs) + `iam:PassRole` (task + execution roles only)

**Scheduling / observability**
- EventBridge rule (optional) to trigger the screenshot task on a cron (default weekly Mon 06:00)
- CloudWatch log groups per task (stream prefixes `screenshot` / `generate`, two-week retention)

## Key CDK outputs

`ApiUrl`, `FrontendUrl`, `FrontendBucketName`, `DistributionId` — consumed by `deploy.sh` to build and publish the frontend.

## What you configure during the build

| Config item | Format | Source |
|---|---|---|
| Target app URL | string | `APP_URL` in `screenshot-job/run.py` |
| App credentials | runtime env override | Passed at `RunTask` time (UI prompt / schedule), never baked in |
| Workflow steps | Python functions | `screenshot-job/workflows.py` |
| Screenshot-analysis context | string | `PRODUCT_CONTEXT` in `screenshot-job/helpers.py` |
| Feature walkthrough | text | `generate-job/feature_context.txt` |
| Guide template | HTML | `generate-job/template.html` |
| Generation prompts | string | `generate-job/generate.py` |
| Stack / bucket / table names | strings | `infra/lib/stack.ts` |
| Schedule cadence | cron | EventBridge rule in `infra/lib/stack.ts` |
| Nova Act workflow name | string | `run.py` decorator |

## What's pre-built (ships with the kit)

- The full CDK stack and resource wiring
- Reusable `helpers.py` (capture/analyze/timeout/re-navigation utilities)
- Generic Lambda CRUD + trigger logic
- The React management UI
- Both Dockerfiles and the deploy script
- The implementation guide (customization checklist, cost model, troubleshooting)

## Cost expectations

| Driver | Typical range |
|---|---|
| NAT Gateway | ~$32/month (dominant fixed cost) |
| ECS Fargate — screenshot | ~$2–4 per run |
| ECS Fargate — generate | ~$1–2 per run |
| Bedrock (Claude Sonnet 4.5) | ~$3–8 per run |
| Nova Act | Variable (preview) |
| S3 / DynamoDB / Lambda / CloudFront | < $1/month each |

Base ~$40–50/month on a weekly schedule. Reduce the NAT line with VPC endpoints or a NAT instance.

## Pre-deployment checklist

- [ ] Bedrock model access approved for `us.anthropic.claude-sonnet-4-5-*`
- [ ] Nova Act preview access approved
- [ ] Docker running locally (CDK builds images)
- [ ] Target app URL + a low-privilege test account (non-prod preferred)
- [ ] Confirmed login is scriptable (no interactive/push MFA)
- [ ] Stack/bucket/table names chosen and unique

## Post-deployment validation

- [ ] `deploy.sh` completes (run twice on first setup due to the API-URL chicken-and-egg)
- [ ] Frontend loads at the CloudFront URL
- [ ] A triggered run captures screens and writes S3 + DynamoDB
- [ ] Descriptions are generated per screenshot
- [ ] Review edits + screenshot replace persist
- [ ] "Generate Guide" produces valid HTML; presigned "View Guide" works
- [ ] EventBridge schedule fires (if enabled)
- [ ] Task roles are least-privilege; tasks in private subnets; credentials not baked in

## Day-2 operations (yours to run)

- Update `workflows.py` when the app's UI changes break a step.
- Watch CloudWatch logs for Nova Act navigation failures and tune `max_steps` / `sleep_after`.
- Manage the schedule cadence and review backlog.
- Decide where the generated HTML guide is hosted/published.
- Optionally optimize the NAT cost and explore extensions (diff detection, notifications, PDF export, versioning).
