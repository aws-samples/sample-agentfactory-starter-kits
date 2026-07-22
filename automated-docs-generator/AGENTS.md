# AGENTS.md — Automated Docs Generator

> Coding-agent contract for `automated-docs-generator`. Read this file first if you are a coding agent (Kiro, Claude Code, Codex, Cursor, or similar) being asked to build this kit.

## What this kit does

A pipeline that generates end-user product documentation for a web application:

- An AI browser agent (**Amazon Nova Act**) logs into the target app and walks its pages, capturing a screenshot of each screen.
- Each screenshot is sent to **Claude on Bedrock** for a natural-language description.
- Screenshots go to **S3**, section metadata to **DynamoDB**.
- A human reviews sections in a **React management UI**, edits descriptions, and replaces screenshots.
- A second job runs the **Claude Code CLI** (Bedrock backend) to assemble the reviewed sections into a polished **HTML user guide** from a template + a feature-context document.
- **EventBridge** can re-run the capture on a schedule so the guide tracks the product.

**Vertical:** Cross-vertical (any web app needing end-user docs)
**Build level:** Custom IaC (CDK)
**Build status:** Not yet built — implement against this spec

## Build-level guidance

This kit is `custom-iac`. It is **not** an AgentCore harness and not a single Bedrock Agent — it's a small event-driven application: two containerized batch jobs on ECS Fargate, a CRUD Lambda API, a static React UI on CloudFront, and DynamoDB/S3 state, all provisioned with the AWS CDK (TypeScript). The "agent" intelligence is (1) Nova Act doing browser automation and (2) Claude doing screenshot description and HTML assembly. Keep it `custom-iac`; do not collapse it into a managed harness — the value depends on owning the ECS jobs, the browser-automation container, and the scheduling.

## What you (the coding agent) should do

This is a **Path B kit** — spec-first, no source code in the kit folder. Build the pipeline in your AWS account against this spec.

Read in order: `build-spec/requirements.md` (functional + non-functional spec) → `build-spec/architecture-decisions.md` (why these choices) → `build-spec/deployment-spec.md` (resources to create) → `build-spec/acceptance-tests.md` (how we know it works).

Do not commit code into the kit folder. The kit folder is catalog metadata, not the pipeline's source. When the build is done, record where your implementation lives.

## Components to build

| Component | Stack | Responsibility |
|---|---|---|
| `infra/` | CDK (TypeScript) | Provisions S3, DynamoDB (runs + sections), ECS Fargate cluster + 2 task defs, Lambda API, API Gateway, CloudFront, EventBridge, VPC/NAT, IAM roles |
| `screenshot-job/` | Python container (Nova Act + Chromium) | Logs into the app, walks pages, captures + analyzes screenshots, writes S3 + DynamoDB |
| `generate-job/` | Python + Node container (Claude Code CLI) | Downloads reviewed sections, assembles HTML guide from template + feature context, uploads to S3 |
| `lambda/api/` | TypeScript (esbuild) | Runs/sections CRUD, presigned upload URLs, ECS `RunTask` triggers, presigned guide URL |
| `frontend/` | React + Vite | Runs list (live status), section review/edit, screenshot replace, generate / regenerate-with-feedback |
| `deploy.sh` | Bash | Build Lambda → CDK deploy → build frontend with API URL → sync to S3 → invalidate CloudFront |

## Required behavior

The pipeline must:

- Let a user create a "run" and trigger a screenshot capture against a target app URL with supplied credentials (or fire a run on an EventBridge schedule).
- In the screenshot job: navigate the app with Nova Act using natural-language instructions, capture a PNG per screen, send each to Claude for a description, and persist screenshot (S3) + section metadata (DynamoDB) per capture.
- Be resilient: every browser action goes through a `safe_act` wrapper that fails gracefully; every step re-checks it's still on the app (`ensure_on_app`); the job enforces a wall-clock timeout (default 60 min) and saves partial results on timeout.
- **Never click destructive actions** (Delete, Remove, real form submissions that create data). Always close modals after capturing them.
- Let a human review every section: edit the AI description inline, replace a screenshot via presigned S3 upload, reorder/curate.
- On "Generate Guide": run the Claude Code CLI (Bedrock backend, no API key) to assemble the reviewed sections into a single HTML file using `template.html` (two placeholders: `<!-- SIDEBAR_NAV -->`, `<!-- SECTIONS -->`) and `feature_context.txt` as the primary source of truth.
- Support a "Regenerate with feedback" path that revises an existing guide from user instructions.
- Track run status through `created → running → completed → generating → generated` (and `error` from any state); the UI polls every ~8s while a run is active.
- Serve the finished guide via a presigned URL.

## Conventions

- **AWS region:** Default `us-east-1` (configurable). Containers are built `--platform=linux/amd64` (Fargate is x86).
- **Models:** Screenshot analysis + guide generation use Claude Sonnet 4.5 on Bedrock (`us.anthropic.claude-sonnet-4-5-20250929-v1:0`). Browser automation uses Amazon Nova Act (preview). The generate job uses the Claude Code CLI with `CLAUDE_CODE_USE_BEDROCK=1` (IAM-based, no Anthropic API key).
- **Storage layout (S3):** `runs/{runId}/screenshots/{name}.png`, `runs/{runId}/descriptions/{name}.txt`, `runs/{runId}/user_guide.html`.
- **DynamoDB:** `runs` table (PK `runId`, SK `createdAt`), `sections` table (PK `runId`, SK `sectionId`), both PAY_PER_REQUEST.
- **Logging:** Each ECS task streams to CloudWatch with a per-container stream prefix; two-week log retention.
- **Lambda build:** esbuild bundle, `--external:@aws-sdk/*` (SDK is in the Lambda runtime).
- **You customize** (don't hardcode — make configurable):
  - Workflow steps in `screenshot-job/workflows.py`
  - `APP_URL`, default credentials, Nova Act `workflow_definition_name` in `screenshot-job/run.py`
  - `PRODUCT_CONTEXT` in `screenshot-job/helpers.py`
  - `generate-job/feature_context.txt`, `generate-job/template.html`, and the prompts in `generate-job/generate.py`
  - Stack/bucket/table names and the EventBridge schedule in `infra/lib/stack.ts`

## Non-negotiables

These are not subject to coding-agent discretion:

1. **Human-in-the-loop publish.** AI-drafted descriptions are always reviewable/editable before the guide is generated. Never auto-publish a guide straight from capture.
2. **No destructive browser actions.** The capture workflow never clicks Delete/Remove or submits forms that create real data. Capture forms, then close without saving.
3. **Credentials are runtime inputs, never baked into images.** App credentials are passed as ECS container `environment` overrides at `RunTask` time, not committed to the repo or the container.
4. **Least-privilege IAM.** Screenshot task role: S3 + DynamoDB + `bedrock:InvokeModel` + Nova Act. Generate task role: S3 + DynamoDB + `bedrock:InvokeModel` + `bedrock:InvokeModelWithResponseStream`. Lambda: `ecs:RunTask` + `iam:PassRole` scoped to the two task/exec roles only.
5. **Private subnets for tasks.** Fargate tasks run in `PRIVATE_WITH_EGRESS` subnets; `assignPublicIp: DISABLED`; egress via NAT.
6. **Block third-party domains during capture** to avoid SSL/redirect failures and accidental navigation away from the app.

## Defaults

- **Model ID:** `us.anthropic.claude-sonnet-4-5-20250929-v1:0`
- **Region:** `us-east-1`
- **Job timeout:** 60 minutes (Fargate hard max is 24h; partial results are saved on timeout)
- **Task sizing:** 4096 MiB / 2048 CPU for both jobs (headless browser + Node CLI are memory-hungry)
- **Presigned URL expiry:** 3600s
- **Stack name:** `<App>DocsStack` convention

## Things to confirm before customizing/coding

- What is the target app URL, and is there a non-production environment to run against?
- How does login work — username/password, SSO, MFA? (MFA/push may block Nova Act — see disqualifiers.)
- What are the app's top pages/features to document, and in what order?
- What terminology does the app use (drives `PRODUCT_CONTEXT` + `feature_context.txt`)?
- Who is the audience for the guide (end user, admin, new hire)? This sets the tone in `generate.py`.
- Is a schedule wanted, and how often? (Or trigger-only.)
- Any screens the agent must never touch (real customer data, destructive admin actions)?

## When to pause and flag for review mid-build

- The app can't be logged into without interactive MFA the agent can't satisfy.
- The UI is canvas/WebGL/heavily animated and Nova Act can't reliably navigate it.
- Capturing the required screens would necessarily touch real/production data.
- The 60-minute job timeout is consistently hit before the workflow finishes (split into multiple runs).

## What you're NOT building

- A general web crawler or scraper of third-party sites — this drives your own app only.
- An autonomous publisher — a human reviews before generate.
- A CMS or hosting platform for the guide — output is a single HTML file in S3; you decide where to host it.
- Agent business logic beyond browser automation + screenshot description + HTML assembly.

## Acceptance — how we know it works

Before bumping `kit.json.status` from `draft` / `in-build` to `published`:

1. All acceptance tests in `build-spec/acceptance-tests.md` pass against your app.
2. A full run captures the target screens, drafts a description per screen, and lands them in S3 + DynamoDB.
3. The review UI can edit a description and replace a screenshot, and those changes survive into the generated guide.
4. "Generate Guide" produces a valid, styled HTML file with working sidebar nav and one card per section.
5. "Regenerate with feedback" measurably changes the guide per the instruction.
6. The capture demonstrably avoids destructive actions and closes modals after capture.
7. Timeout handling verified: a job that hits the limit still saves partial results and marks `timedOut`.
8. IAM roles are least-privilege; tasks run in private subnets; credentials are runtime overrides, not baked in.

## Repository convention

This kit folder (`automated-docs-generator/`) is **catalog metadata**, not the pipeline's source code. When the build is finished, the source lives in your repository — the implementation is built from this spec.

Do NOT add pipeline code under this kit folder.

## When you finish a build

Record where your implementation lives, then bump `kit.json.status` from `draft` to `published` once you have reviewed the build against the acceptance tests.
