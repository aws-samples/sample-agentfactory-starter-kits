# Acceptance Tests — Scalable Claude Code on AWS Batch

> Audience: you and your engineering lead during sign-off. Each test maps to requirements in [`requirements.md`](requirements.md).

## Functional

**T1 — Single prompt-only job.**
- *Setup:* deployed infra + configured CLI; no repo.
- *Action:* `claude-batch submit --prompt "List primes 1–100, one per line" --max-budget-usd 1.00 --watch`.
- *Expected:* job reaches SUCCEEDED; `result.json` + `metadata.json` land in `s3://<bucket>/jobs/<job-id>/`.
- *Maps to:* FR1, FR6.

**T2 — Job against a cloned repo.**
- *Setup:* a public repo URL.
- *Action:* `claude-batch submit --prompt "Review for security issues; output a report" --repo-url <url> --allowed-tools "Bash Read Glob Grep"`.
- *Expected:* repo is shallow-cloned; Claude runs; `result.json` is produced (and `changes.patch` if anything changed).
- *Maps to:* FR1, FR5, FR6.

**T3 — Bulk manifest submission.**
- *Setup:* a manifest with `defaults` + multiple `jobs[]`.
- *Action:* `claude-batch submit --manifest manifest.json --rate-limit 5`.
- *Expected:* one job submitted per entry, defaults applied unless overridden, throttled to the rate limit; a single bad entry doesn't abort the batch.
- *Maps to:* FR2.

**T4 — No API key, Bedrock via IAM.**
- *Setup:* a running job.
- *Action:* inspect the container env and job role.
- *Expected:* `CLAUDE_CODE_USE_BEDROCK=1`, no `ANTHROPIC_API_KEY` anywhere; Bedrock calls succeed via the job role.
- *Maps to:* FR3.

**T5 — Per-job budget enforced.**
- *Setup:* a task likely to exceed a tiny budget.
- *Action:* submit with `--max-budget-usd 0.05`.
- *Expected:* Claude Code stops at the ceiling; the job still uploads whatever output it produced.
- *Maps to:* FR4.

**T6 — Tool scoping (read-only).**
- *Setup:* a job with `--allowed-tools "Bash Read Glob Grep"`.
- *Action:* prompt it to modify a file.
- *Expected:* no write/edit occurs; `changes.patch` is empty.
- *Maps to:* FR5.

**T7 — Result artifacts complete.**
- *Setup:* a repo job that makes changes.
- *Action:* `claude-batch results <job-id> -o ./out`.
- *Expected:* `result.json`, `metadata.json`, `changes.patch`, `changes-summary.txt`, `new-files.txt` present; metadata records exit code, model, budget, repo.
- *Maps to:* FR6.

**T8 — EC2 compute path.**
- *Setup:* a large job.
- *Action:* `claude-batch submit --prompt "…" --compute-type ec2`.
- *Expected:* runs on the EC2 queue/job def (8 vCPU / 32 GB) with the 4-hr timeout.
- *Maps to:* FR7.

**T9 — Status, watch, cancel.**
- *Action:* `claude-batch status --all --watch`, then `claude-batch cancel <job-id>`.
- *Expected:* live status updates; the cancelled job transitions out of RUNNING/RUNNABLE.
- *Maps to:* FR8.

**T10 — Prompt from S3.**
- *Setup:* a prompt file uploaded to S3.
- *Action:* submit with `--prompt s3://<bucket>/prompt.txt`.
- *Expected:* the entrypoint downloads and uses the S3 prompt.
- *Maps to:* FR1.

## Non-functional

**T11 — Least-privilege IAM.**
- *Action:* inspect the job and execution roles.
- *Expected:* job role limited to `bedrock:InvokeModel`/`InvokeModelWithResponseStream` on Claude ARNs + inference profiles, S3 on the results bucket, Logs on the job log group, ApplyGuardrail; execution role limited to ECR pull + the git-token secret. No admin/cross-account.
- *Maps to:* FR3, NFR3.

**T12 — Private repo via Secrets Manager.**
- *Setup:* store a token in `claude-code-batch/git-token`; a private repo URL.
- *Action:* submit a job cloning the private repo.
- *Expected:* clone succeeds; the token is injected from Secrets Manager, never present as a plaintext env var or in logs.
- *Maps to:* FR9, NFR3.

**T13 — Guardrail blocks sensitive content.**
- *Action:* submit a prompt that would surface a blocked PII pattern (e.g., a fake SSN/AWS key) and inspect output.
- *Expected:* the Guardrail blocks/filters the content per the configured policy.
- *Maps to:* FR10.

**T14 — HTTPS-only egress + VPC endpoints.**
- *Action:* review the Batch security group and VPC endpoints.
- *Expected:* only port 443 egress; Bedrock/S3/ECR/Logs reachable via endpoints; non-HTTPS egress blocked.
- *Maps to:* NFR3.

**T15 — Spot reclamation retry.**
- *Action:* observe (or simulate) a Spot interruption on a running job.
- *Expected:* the job retries per `retryAttempts: 2` on `Host EC2*`; application exit code 1 does not retry.
- *Maps to:* NFR2.

**T16 — S3 upload failure surfaces.**
- *Setup:* a forced S3 upload failure.
- *Action:* run a job.
- *Expected:* the job exits non-zero (code 2 if Claude itself succeeded) — never a silent success.
- *Maps to:* NFR2.

## Operational

**T17 — Dashboard and alarms.**
- *Action:* open the `ClaudeCodeBatch` CloudWatch dashboard; trip the failed-job threshold.
- *Expected:* job-outcome and Bedrock metrics render; the failed-job alarm fires to the SNS topic.
- *Maps to:* NFR6.

**T18 — Config resolved from CDK outputs.**
- *Action:* `claude-batch configure` on a fresh install.
- *Expected:* job-queue/job-def ARNs, results bucket, and ECR URI are populated from stack outputs into `~/.claude-batch/config.yaml`.
- *Maps to:* FR8.

## Sign-off

| Role | Name | Date |
|---|---|---|
| Reviewer | __________ | ______ |
| Your engineering lead | __________ | ______ |
