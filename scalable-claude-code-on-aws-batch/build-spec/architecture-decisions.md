# Architecture Decisions — Scalable Claude Code on AWS Batch

> Audience: a coding agent that might be tempted to deviate. These are grounded in the source's CDK stacks, the container entrypoint, and the CLI. Don't reverse them without reviewing the tradeoffs first.

## AD1 — Bedrock + IAM, never API keys
**Decision:** The container sets `CLAUDE_CODE_USE_BEDROCK=1` and authenticates to the model via its IAM job role; no Anthropic API key exists anywhere.
**Why:** API keys spread across hundreds of workers are a rotation and leak liability, and many enterprises mandate Bedrock as the only model gateway. IAM roles give per-job, auditable, key-free access.
**What this means for the build:** Never reintroduce `ANTHROPIC_API_KEY`. Scope the role to `bedrock:InvokeModel` / `InvokeModelWithResponseStream` on Claude ARNs + inference profiles only.

## AD2 — AWS Batch as the fan-out engine
**Decision:** Use AWS Batch (job queues + managed compute environments) rather than a bespoke orchestrator, Step Functions, or a CI matrix.
**Why:** Batch natively handles queuing, auto-scaling, concurrency, retries, and Spot — exactly the primitives a large agent fan-out needs — with no control-plane to operate.
**Alternatives considered:** Lambda fan-out (rejected — coding jobs exceed the 15-min limit and need more memory/storage); CI runners (rejected at scale — concurrency caps, minute-billing, secret sprawl).
**What this means for the build:** Keep submission as `SubmitJob` with env overrides; let Batch own scheduling.

## AD3 — Fargate Spot default, EC2 Spot for big jobs
**Decision:** Two compute environments and queues: Fargate Spot (4 vCPU / 8 GB, 2-hr timeout) as default and EC2 Spot (8 vCPU / 32 GB, 4-hr timeout, M7i/M6i/C7i) for large repos/long tasks.
**Why:** Fargate starts fast (~30s) and needs no instance management; EC2 gives more memory and longer timeouts for heavy jobs. Spot cuts compute cost ~70% — and the workload tolerates interruption (retry on `Host EC2*`).
**What this means for the build:** Keep the two paths separate (Batch requires separate Fargate/EC2 queues); choose per job via `--compute-type`.

## AD4 — Hard per-job budget as the primary cost control
**Decision:** Every job passes `--max-budget-usd` (default $5.00); Claude Code halts at the ceiling.
**Why:** Bedrock tokens are ~90%+ of cost and the most variable; an unbounded agent loop is the main runaway-cost risk. A hard ceiling makes spend predictable per job and per campaign.
**What this means for the build:** Never ship a submit path without a budget; surface it in manifest defaults too.

## AD5 — Split least-privilege IAM roles
**Decision:** A **job role** (Bedrock invoke + S3 results write + scoped CloudWatch Logs + ApplyGuardrail) distinct from an **execution role** (ECR pull via managed policy + Secrets Manager read for the git token).
**Why:** The running container and the ECS/Batch execution context need different permissions; splitting them keeps each minimal. Co-locating the roles in BatchStack avoids cross-stack dependency cycles.
**What this means for the build:** Don't merge the roles or broaden them; keep S3 scoped to the results bucket and Logs to the job log group.

## AD6 — VPC endpoints + HTTPS-only egress
**Decision:** Private subnets; interface endpoints for Bedrock Runtime, ECR (x2), and CloudWatch Logs, plus an S3 gateway endpoint; a security group allowing only port 443 outbound.
**Why:** Keeps AWS service traffic (especially Bedrock responses) off the internet and off the NAT data-transfer meter, and shrinks the egress surface. NAT remains only for `git clone`.
**Alternatives considered:** NAT-only (rejected — Bedrock data transfer cost and a wide egress surface); fully endpoint-only with no NAT (offered as a hardening option, removes public git clone).
**What this means for the build:** Don't widen the egress SG; route AWS traffic through endpoints.

## AD7 — Bedrock Guardrail in the loop
**Decision:** A CDK-created Bedrock Guardrail (content filters: sexual/violence/hate/insults/misconduct at HIGH; PII blocks: AWS keys, cards, SSNs) is wired into every job definition via `BEDROCK_GUARDRAIL_ID` / `_VERSION`.
**Why:** Provides a content and sensitive-data backstop on model I/O independent of the prompt, which matters when many jobs run unattended over arbitrary repos.
**What this means for the build:** Keep the Guardrail attached; tune its policies to your needs rather than removing it.

## AD8 — S3 as the result sink, structured output
**Decision:** Each job uploads `result.json` (Claude's JSON output), `changes.patch` (git diff), and `metadata.json` to `s3://<bucket>/jobs/<job-id>/`; the bucket is encrypted, private, SSL-enforced, with a 90-day lifecycle.
**Why:** A durable, structured, per-job artifact set is what makes results actionable and auditable at fleet scale; S3 needs no servers and the gateway endpoint is free.
**What this means for the build:** Preserve the JSON-result + git-patch contract; an upload failure must produce a non-zero exit code.

## AD9 — Per-job isolation, non-root container
**Decision:** Each job gets an isolated `CLAUDE_CONFIG_DIR` and ephemeral working dir; the container runs as a non-root `claude` user; nothing persists between jobs.
**Why:** Prevents state leakage between concurrent jobs and limits blast radius if a job processes hostile input.
**What this means for the build:** Don't share config dirs or add a persistent volume.

## AD10 — Decision-support output, no auto-merge
**Decision:** Jobs emit patches and reports for human review; the platform never pushes to repositories.
**Why:** Code changes must be reviewed before they land; auto-merge is a trust and safety risk and out of scope.
**What this means for the build:** Don't wire job output into `git push`; auto-PR is an extension you build, not part of the kit.

## AD11 — Default model via cross-region inference profile
**Decision:** Default `ANTHROPIC_MODEL=us.anthropic.claude-sonnet-4-6` (inference profile); Haiku for triage/analysis; Opus excluded from the IAM allow-list by default.
**Why:** Inference profiles give aggregate cross-region throughput and availability — essential at high parallelism — and Sonnet balances code-writing quality with latency/cost. Opus is too slow/expensive for default fan-out.
**What this means for the build:** Don't hardcode bare foundation-model IDs; to use Opus, widen the IAM allow-list deliberately.
