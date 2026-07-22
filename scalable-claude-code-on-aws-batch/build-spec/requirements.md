# Requirements — Scalable Claude Code on AWS Batch

> Audience: a coding agent implementing or customizing the kit.

## Functional requirements

**FR1 — Job submission.** The system shall submit a Claude Code job to AWS Batch with a prompt and optional git repo, passing the prompt, repo URL/branch, per-job budget, allowed tools, and optional model/turns/system-prompt as container environment overrides.
A job runs `claude --bare -p "<prompt>" --output-format json` headlessly inside the container. *Maps to: T1, T2.*

**FR2 — Bulk submission from a manifest.** The system shall submit many jobs from a manifest JSON (`defaults` + per-job `jobs[]`), applying defaults unless a job overrides them, with a configurable submission rate limit. *Maps to: T3.*

**FR3 — No-API-key model access.** The container shall authenticate to Amazon Bedrock using its IAM job role (`CLAUDE_CODE_USE_BEDROCK=1`) — never an Anthropic API key. The job role grants only `bedrock:InvokeModel` / `InvokeModelWithResponseStream`, scoped to specific Claude model + inference-profile ARNs. *Maps to: T4, T11.*

**FR4 — Per-job budget enforcement.** Every job shall carry a hard `--max-budget-usd` ceiling (default $5.00); Claude Code stops execution when the budget is reached. *Maps to: T5.*

**FR5 — Tool scoping.** The system shall restrict which tools a job can use via `--allowedTools` (default `Bash Edit Read Write Glob Grep`; a read-only set for analysis/review). *Maps to: T6.*

**FR6 — Result collection.** Each job shall write `result.json`, `changes.patch` (+ summary and new-files lists when a repo was cloned), and `metadata.json`, and upload them to `s3://<bucket>/jobs/<job-id>/`. *Maps to: T7.*

**FR7 — Two compute paths.** The system shall offer Fargate (default, 4 vCPU / 8 GB, 2-hr timeout) and EC2 (8 vCPU / 32 GB, 4-hr timeout) compute, each with its own queue and job definition. *Maps to: T8.*

**FR8 — Status, results, cancel.** The CLI shall report job status (with watch mode), download/show results and diffs, and cancel running jobs. *Maps to: T9.*

**FR9 — Private repo support.** The system shall clone private repos using a git token injected at runtime from Secrets Manager (`claude-code-batch/git-token`), never as a plaintext environment variable. *Maps to: T12.*

**FR10 — Content guardrail.** A Bedrock Guardrail shall filter prompts and responses for harmful content and block sensitive PII (AWS keys, card numbers, SSNs). *Maps to: T13.*

## Non-functional requirements

**NFR1 — Scalability.** The system shall auto-scale compute via AWS Batch up to a configurable `maxvCpus` (default 256). The dominant scaling limit is Bedrock TPM/RPM quota; cross-region inference profiles and submission rate-limiting are the levers.

**NFR2 — Resilience.** Job definitions shall retry on Spot reclamation (`Host EC2*`, `retryAttempts: 2`) and exit on application failure. An S3 upload failure shall surface as a non-zero exit code (never a silent success).

**NFR3 — Security.** Single-tenant in your account. Egress is HTTPS-only; AWS service traffic flows through VPC endpoints (Bedrock, S3, ECR, Logs). Split least-privilege IAM roles (job vs execution). The container runs as a non-root user with an isolated per-job config dir.

**NFR4 — Cost predictability.** Cost shall be bounded per job by `--max-budget-usd`; Fargate/EC2 Spot reduces compute ~70%; model-tier routing (Haiku vs Sonnet) controls Bedrock spend.

**NFR5 — Encryption.** Results at rest use SSE-S3 (SSE-KMS optional); data in transit over HTTPS; the bucket blocks public access and enforces SSL.

**NFR6 — Observability.** A CloudWatch dashboard shall track job outcomes and Bedrock invocation/latency/throttle metrics; alarms fire to SNS on failed-job spikes and sustained throttling.

## Out of scope

- Auto-merge / auto-push of agent output to repositories (output is for human review).
- A hosted/multi-tenant control plane or app-level authentication in front of the CLI.
- A persistent application datastore (job state is in Batch; results are in S3).
- Non-Anthropic or Opus models by default (the IAM allow-list ships Sonnet + Haiku only).
- Fine-tuning or custom model hosting.

## Dependencies

- Bedrock model access enabled for the chosen Claude tier in the target region (`us-east-1` default), via inference profiles; sufficient TPM/RPM quota for the target parallelism.
- AWS account with permissions for CloudFormation, EC2/VPC, ECR, IAM, AWS Batch, S3, Secrets Manager, CloudWatch Logs, SNS, and Bedrock.
- Tooling: AWS CLI v2, AWS CDK 2.180+, Node.js 18+, Docker, Python 3.10+.
- Git access to the repositories the jobs will clone (public, or a token in Secrets Manager for private).
