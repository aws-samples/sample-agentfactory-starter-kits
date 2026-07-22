# Scalable Claude Code on AWS Batch

> **Status:** Draft · Spec-only kit — a blueprint of a working implementation · Build level: Custom IaC

A platform for running hundreds of parallel [Claude Code](https://docs.anthropic.com/en/docs/claude-code) coding-agent jobs on **AWS Batch** against **Amazon Bedrock** — with **no Anthropic API keys**, using IAM roles only. You hand it a prompt and (optionally) a git repo; a Batch job clones the repo, runs Claude Code headlessly with a hard per-job dollar budget, captures the result and a git patch, and uploads everything to S3. Submit one job from the CLI or fan out a whole campaign from a manifest. The same pattern drives bulk code migrations, automated PR review, mass refactors, and parallel data analysis across a fleet of repositories.

## Why this exists

The hard part of using a coding agent at scale isn't the agent — it's the plumbing. Running Claude Code against 500 repositories means provisioning compute, managing concurrency, keeping API keys out of every worker, capping spend so one runaway job doesn't blow the budget, and collecting structured output you can actually act on. Teams end up hand-rolling brittle scripts or never attempting fleet-wide changes at all. This kit makes the agent a **queue-and-fan-out batch workload**: AWS Batch auto-scales Fargate/EC2 Spot compute, Bedrock supplies the model with IAM auth (no keys to distribute), a `--max-budget-usd` ceiling bounds every job, and results land in S3 as JSON + git patches. It turns "we should migrate all our repos off the deprecated library" from a quarter-long manual slog into a parametrized run.

## How to use this kit

This kit is a blueprint, not a codebase: it contains the architecture, the build contract, and acceptance tests — but not the platform's source code. Read [`AGENTS.md`](AGENTS.md) + [`build-spec/`](build-spec/) and have a coding agent (Kiro / Claude Code / Cursor / Codex) implement the platform in your own AWS account, against your own conventions.

**What the spec targets:** a four-stack AWS CDK app (`cd infra && cdk deploy --all` stands up the VPC, Batch, ECR, S3, and monitoring), a container image shipped by `./scripts/build-and-push.sh`, and a Python CLI installed with `pip install -e cli`. Once built, `claude-batch submit` runs a single job and `claude-batch submit --manifest` fans out a whole campaign.

## What this kit gives you

| File | What's in it |
|---|---|
| [`kit.json`](kit.json) | Kit manifest — services, model, outcomes, fit profile, ROI scaffolding |
| [`architecture/architecture.md`](architecture/architecture.md) | The stack, a component diagram, data flow (submission → execution → collection), audit trail |
| [`business-case/roi-framework.md`](business-case/roi-framework.md) | ROI math template, cost drivers, objection handling, competitive framing |
| [`AGENTS.md`](AGENTS.md) | Build contract for a coding agent re-implementing or customizing the kit |
| [`build-spec/`](build-spec/) | Requirements, architecture decisions, deployment spec, acceptance tests |

## Shared responsibility

This is an accelerator and a working reference, not a managed service. You own the deployed AWS infrastructure, the job manifests and prompts, the source repositories the jobs clone, the results in S3, and the Bedrock spend in your account. The agent's output — code changes, patches, reports — is for human review and merge; you own what lands in your repositories. You and your engineering team adapt the kit to your workloads; CDK stacks and scripts are provided as-is.
