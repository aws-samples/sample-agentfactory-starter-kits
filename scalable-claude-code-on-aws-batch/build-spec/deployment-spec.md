# Deployment Spec — Scalable Claude Code on AWS Batch

> Audience: a coding agent provisioning resources in your account.

## Deployment context

- **Account:** your own AWS account (single-tenant).
- **Region:** `us-east-1` by default; override with CDK context `-c region=…`. Confirm Bedrock model access in the chosen region.
- **Trust boundary:** everything runs in your account/VPC; the only outbound dependencies are in-region Bedrock invocation (via VPC endpoint) and `git clone` egress (via NAT).
- **Source code location:** not included in this kit — the kit folder holds metadata + specs only. The implementation is built from this spec and lives in your own repository.
- **Delivery unit:** a four-stack AWS CDK app plus a container image in ECR and a `pip`-installed CLI.

## CloudFormation / CDK stack hierarchy

```
ClaudeCodeNetwork ──┐
                    ├──▶ ClaudeCodeBatch ──▶ ClaudeCodeMonitoring
ClaudeCodeStorage ──┘
```

- **NetworkStack** and **StorageStack** are independent and deploy first.
- **BatchStack** depends on both (consumes the VPC, ECR repo, and results bucket).
- **MonitoringStack** depends on BatchStack (consumes the job-queue ARN/name).
- Deploy all with `cdk deploy --all`; the network stack rarely changes, the batch stack changes most often.

## Deploy steps

| Step | Command | What it does |
|---|---|---|
| Bootstrap | `cd infra && npm install && cdk bootstrap` | One-time per account/region |
| Deploy infra | `cdk deploy --all` (optionally `-c region=… -c maxvCpus=… -c useSpot=false`) | Creates all four stacks |
| Build container | `./scripts/build-and-push.sh` | Builds the Claude Code image and pushes to ECR (`latest`) |
| Install CLI | `cd cli && pip install -e .` | Installs `claude-batch` |
| Configure CLI | `claude-batch configure` | Resolves ARNs/bucket from CDK stack outputs into `~/.claude-batch/config.yaml` |
| Teardown | `./scripts/cleanup.sh` | Removes stacks (note: results bucket is RETAIN) |

## Resources to create

- **Networking:** VPC (2 AZs), 1 NAT gateway, public + private subnets; interface VPC endpoints (Bedrock Runtime, ECR Docker, ECR API, CloudWatch Logs); S3 gateway endpoint; an HTTPS-only egress security group.
- **Compute:** Fargate Spot compute environment + Fargate job queue; EC2 Spot compute environment (M7i/M6i/C7i) + EC2 job queue; two ECS job definitions (`claude-code-fargate`, `claude-code-ec2`).
- **AI / model:** Bedrock model access (Claude Sonnet 4.6 default + Haiku) via inference profiles — no resource to create, but access must be enabled; a Bedrock Guardrail (`claude-code-batch-guardrail`).
- **Identity:** the **job role** (Bedrock invoke + S3 results + scoped Logs + ApplyGuardrail) and the **execution role** (ECS task execution managed policy + Secrets Manager read).
- **Storage / registry:** ECR repository (`claude-code-batch`, 10-image lifecycle); S3 results bucket (SSE-S3, block-public, enforce-SSL, 90-day lifecycle, RETAIN); Secrets Manager secret (`claude-code-batch/git-token`).
- **Observability:** CloudWatch log group (`/aws/batch/claude-code`, 1-month retention); CloudWatch dashboard (`ClaudeCodeBatch`); failed-job + Bedrock-throttle alarms; SNS topic (`claude-code-batch-alerts`).

## What you configure during the build

| Config item | Format | Source |
|---|---|---|
| Campaign jobs (repos, prompts, budgets, tools) | Manifest JSON | `examples/*/manifest.json` |
| Container job logic / toolchains | Bash + Dockerfile | `docker/entrypoint.sh`, `docker/Dockerfile` |
| Bedrock model allow-list / IAM scope | CDK (TypeScript) | `infra/lib/batch-stack.ts` |
| Guardrail content + PII policy | CDK (TypeScript) | `infra/lib/batch-stack.ts` (`ClaudeCodeGuardrail`) |
| Scale / region / Spot | CDK context | `infra/bin/app.ts` (`maxvCpus`, `useSpot`, `region`) |
| CLI defaults (model, budget, tools) | Python | `cli/src/claude_batch/config.py` |
| Private-repo git token | Secret value | Secrets Manager `claude-code-batch/git-token` |

## What's pre-built

- The four CDK stacks (`infra/lib/`) and the app wiring (`infra/bin/app.ts`).
- The Claude Code container (`docker/`) and the build/deploy/run/cleanup scripts (`scripts/`).
- The `claude-batch` Python CLI (submit/status/results/cancel/configure).
- The Bedrock Guardrail, scoped IAM policies, the git-token secret, and the HTTPS-only SG.
- The CloudWatch dashboard, alarms, and SNS topic.
- Four worked examples with runnable manifests (code-migration, code-review, mass-refactor, data-analysis).

## Cost expectations

| Driver | Typical range |
|---|---|
| Bedrock (Claude Sonnet/Haiku) | $0.10–$10+ per job — dominant cost; scales with tokens, not parallelism |
| Fargate / EC2 Spot | ~$0.01–$0.05 per job (Spot ~70% off) |
| VPC interface endpoints | ~$0.01/hr each per AZ (fixed) |
| NAT gateway | $0.045/GB (git clone traffic) |
| S3 / ECR / SNS | Negligible |
| CloudWatch | ~$0.50/GB ingested |

## Pre-deployment checklist

- [ ] Bedrock access enabled for the chosen Claude tier in the target region.
- [ ] Bedrock TPM/RPM quotas sized for target parallelism (request increase if needed).
- [ ] AWS CLI v2 + CDK 2.180+ + Node 18+ + Docker + Python 3.10+ installed.
- [ ] CDK bootstrapped in the account/region.
- [ ] Campaign manifest authored; allowed-tools posture (read-only vs write) decided.
- [ ] Private-repo git token stored in Secrets Manager (if private repos are in scope).

## Post-deployment validation

- [ ] `cdk deploy --all` completes; container pushed to ECR.
- [ ] `claude-batch configure` resolves all ARNs/bucket; a single test job uploads `result.json` + `metadata.json` to S3.
- [ ] A bulk manifest run fans out with rate limiting; per-job budget is enforced.
- [ ] Forced clone/Bedrock failure handled cleanly (other jobs unaffected; non-zero exit on upload failure).
- [ ] Instance/job role confirmed least-privilege; egress SG is HTTPS-only.
- [ ] CloudWatch dashboard shows job + Bedrock metrics; alarms wired to SNS.

## Day-2 operations (you own these)

- Add per-team IAM roles and separate job queues for shared/multi-tenant use.
- Enable CloudTrail data events on the results bucket; switch to SSE-KMS if required.
- Optionally remove the NAT gateway for endpoint-only egress (changes the git-clone path).
- Manage Bedrock spend via model-tier routing and AWS Budgets alerts.
- Establish the patch review/merge workflow; nothing auto-merges.
- Tear down with `./scripts/cleanup.sh` when decommissioning (results bucket is retained by default).
