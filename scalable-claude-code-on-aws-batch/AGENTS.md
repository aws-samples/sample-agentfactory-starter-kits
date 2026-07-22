# AGENTS.md — Scalable Claude Code on AWS Batch

> **Audience: a coding agent** (Kiro / Claude Code / etc.) re-implementing or customizing this kit for your deployment.

## What this is

- A **batch fan-out platform** that runs many parallel Claude Code coding-agent jobs on **AWS Batch**, each invoking **Amazon Bedrock** for the model — **no Anthropic API keys**, IAM job role only.
- A **job** = clone a git repo (optional) → run `claude --bare -p "<prompt>" --output-format json` headlessly with a `--max-budget-usd` ceiling and a scoped `--allowedTools` set → capture `result.json`, `changes.patch`, `metadata.json` → upload to `s3://<bucket>/jobs/<job-id>/`.
- **Two compute paths:** Fargate Spot (default, fast start, 4 vCPU / 8 GB, 2-hr timeout) and EC2 Spot (larger jobs, 8 vCPU / 32 GB, 4-hr timeout) — separate compute environments and job queues.
- Infra is a **four-stack AWS CDK app** (TypeScript): Network, Storage, Batch, Monitoring.
- Driven by a **Python CLI** (`claude-batch`) over boto3: single-job submit, manifest-based bulk submit with rate limiting, status/watch, results download, cancel, configure-from-CDK-outputs.

## The target implementation, file by file

No source code ships in this kit — you build the implementation from this contract. The paths below describe the target layout and where each piece of key logic lives:

1. `README.md` — purpose, quick start, the security-hardening table.
2. `ARCHITECTURE.md` — component diagram, the three-phase data flow (submission → execution → collection), security model, stack dependencies.
3. `infra/bin/app.ts` — how the four stacks wire together and the CDK context params (`maxvCpus`, `useSpot`, `region`).
4. `infra/lib/batch-stack.ts` — the heart of it: IAM job/execution roles, the scoped Bedrock policy, the Bedrock Guardrail, Secrets Manager git token, the HTTPS-only security group, both compute environments, both job definitions.
5. `infra/lib/network-stack.ts` — VPC, NAT, and the VPC endpoints (Bedrock Runtime, ECR x2, CloudWatch Logs interface endpoints + S3 gateway endpoint).
6. `docker/entrypoint.sh` — the actual job logic: config isolation, clone, prompt fetch (incl. `s3://` prompts), the `claude` command assembly, diff capture, metadata, S3 upload.
7. `cli/src/claude_batch/submit.py` + `config.py` — how jobs are submitted (env-var overrides on `SubmitJob`) and how config is resolved from CDK outputs / env.
8. `COST_CONTROL.md` + `docs/scaling-guide.md` — budget levers and the 10 → 1000-job scaling story (Bedrock TPM/RPM quotas are the real bottleneck).

## Deploying to your account

1. **Deploy the infra** — `cd infra && npm install && cdk bootstrap && cdk deploy --all`. Override scale/region with context: `-c region=… -c maxvCpus=… -c useSpot=false`.
2. **Build and push the container** — `./scripts/build-and-push.sh` (or the CodeBuild-free local Docker path). New jobs auto-use the `latest` image.
3. **Install and configure the CLI** — `cd cli && pip install -e .`, then `claude-batch configure` to pull ARNs/bucket from CDK stack outputs.
4. **Author the manifests** — edit `examples/*/manifest.json` (or write new ones) with your repos, prompts, per-job budgets, compute type, and allowed tools.
5. **Scope IAM, Guardrail, and tools** to your needs — adjust the Bedrock model allow-list, the Guardrail content/PII policies, and the default `--allowedTools` (read-only `Bash Read Glob Grep` vs. write-capable `Bash Edit Read Write Glob Grep`).

## What you're NOT building

- **Not a hosted control plane / SaaS.** This is infrastructure that lives in your account; there is no shared multi-tenant service.
- **Not an API-key integration.** Authentication to the model is IAM-role-based via Bedrock (`CLAUDE_CODE_USE_BEDROCK=1`). Never reintroduce `ANTHROPIC_API_KEY`.
- **Not an auto-merge pipeline.** Jobs emit patches and reports to S3; a human reviews and merges. Do not wire job output straight into `git push` to a default branch.
- **Not a copy of any source into the kit folder.** The kit holds metadata + specs only; the implementation is built from this contract and lives in your own repository.

## Non-negotiables

- **No API keys — Bedrock + IAM only.** The container sets `CLAUDE_CODE_USE_BEDROCK=1`; the job role grants `bedrock:InvokeModel` / `InvokeModelWithResponseStream` only, scoped to specific Claude model + inference-profile ARNs.
- **Least-privilege IAM, split roles.** Keep the **job role** (Bedrock invoke + S3 results write + scoped CloudWatch Logs + ApplyGuardrail) separate from the **execution role** (ECR pull + Secrets Manager read for the git token). No admin, no cross-account.
- **Every job has a hard budget.** `--max-budget-usd` is always passed (default $5.00); Claude Code stops at the ceiling. Don't ship a job path without it.
- **Secrets via Secrets Manager, never env plaintext.** `GIT_TOKEN` is injected by the Batch job definition's secrets integration from `claude-code-batch/git-token`. Never pass it as a plain environment variable or bake it into the image.
- **Egress is HTTPS-only and prefers VPC endpoints.** The Batch security group allows only port 443 outbound; AWS service traffic (Bedrock, S3, ECR, Logs) flows through VPC endpoints, not the internet.
- **Per-job isolation.** Each job gets its own `CLAUDE_CONFIG_DIR` and ephemeral working dir; nothing persists between jobs. The container runs as a non-root user.
- **Guardrail in the loop.** The Bedrock Guardrail (content + PII filters) is created in CDK and its ID/version are passed to every job definition — keep it wired.

## Defaults

- **Model:** `us.anthropic.claude-sonnet-4-6` (cross-region inference profile, set as `ANTHROPIC_MODEL` in `entrypoint.sh`). Haiku (`anthropic.claude-haiku-4-5-20251001-v1:0`) for cost-sensitive/triage jobs. Opus is not in the IAM allow-list by default.
- **Region:** `us-east-1` (override via CDK context). **Parallelism:** `maxvCpus=256`. **Spot:** enabled.
- **Naming:** ECR repo `claude-code-batch`; log group `/aws/batch/claude-code`; stacks `ClaudeCodeNetwork` / `ClaudeCodeStorage` / `ClaudeCodeBatch` / `ClaudeCodeMonitoring`; git-token secret `claude-code-batch/git-token`.
- **Allowed tools:** default `Bash Edit Read Write Glob Grep`; use `Bash Read Glob Grep` for read-only analysis/review jobs.

## Things to confirm before customizing

- What's the campaign? How many repos/modules, and is it read-only (review/analysis) or write (migration/refactor)?
- Which model tier — Sonnet for code-writing, Haiku for triage/analysis — and what per-job budget is acceptable?
- What's the expected peak parallelism, and have Bedrock TPM/RPM quotas been raised to match (see `docs/scaling-guide.md`)?
- Are private repos in scope (needs the Secrets Manager git token populated), and from which git host?
- Does your content/data policy require tightening the Guardrail content or PII filters?

## When to flag back mid-build

- You want auto-merge / auto-push of agent output (out of scope — escalate; output is for human review).
- Bedrock model access for the chosen tier isn't enabled in the target account/region, or quotas can't support the target parallelism.
- You want Opus or a non-Anthropic model (requires widening the IAM allow-list — confirm cost/latency implications).
- You need the NAT gateway removed for stricter isolation (changes the git-clone path — discuss the trade-off).
- Multi-team shared use is requested (the README calls out per-team roles/queues as a production consideration, not shipped).

## Done definition

- `cdk deploy --all` provisions all four stacks; the container builds and pushes to ECR.
- `claude-batch configure` resolves all ARNs/bucket from CDK outputs; `claude-batch submit` runs a single job end-to-end and uploads `result.json` + `metadata.json` to S3.
- A manifest run fans out multiple jobs with rate limiting; budget ceiling is enforced; a forced repo/clone failure surfaces cleanly without losing other jobs.
- IAM confirmed least-privilege (Bedrock invoke scoped to Claude ARNs; S3 scoped to the results bucket; no API key anywhere).
- The Bedrock Guardrail is attached and the security group allows only HTTPS egress.
- Acceptance tests in [`build-spec/acceptance-tests.md`](build-spec/acceptance-tests.md) pass.
