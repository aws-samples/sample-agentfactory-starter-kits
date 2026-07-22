# Requirements — Automated Docs Generator

> Functional + non-functional requirements for the coding agent implementing this kit. Each functional requirement maps to acceptance tests in `acceptance-tests.md`.

## Functional requirements

**FR1 — Create and trigger a run.**
A user can create a documentation "run" and trigger a screenshot capture against a target app URL with supplied credentials. A run can also be triggered by an EventBridge schedule. Creating a run writes a record to the runs table with `status: created`; triggering moves it to `running`. *(Maps to: T1, T2)*

**FR2 — Automated screenshot capture.**
The screenshot job uses Amazon Nova Act to log into the target app and walk a sequence of pages/features defined as `step_*` functions, capturing a PNG of each screen. Each capture re-checks it is on the app first (`ensure_on_app`) and uses a safe wrapper for browser actions. *(Maps to: T3, T4)*

**FR3 — AI screenshot description.**
For every captured screenshot, the job sends the image to Claude on Bedrock and stores the returned natural-language description. *(Maps to: T5)*

**FR4 — Persist sections.**
Each capture writes the screenshot to S3 (`runs/{runId}/screenshots/{name}.png`), the description to S3 (`runs/{runId}/descriptions/{name}.txt`), and a section record to the sections table (PK `runId`, SK `sectionId`) with title, keys, and order. *(Maps to: T5, T6)*

**FR5 — Human review and edit.**
A user can list a run's sections, edit any AI description inline, and replace any screenshot via a presigned S3 upload URL. Edits persist and are reflected in the generated guide. *(Maps to: T7, T8)*

**FR6 — Generate guide.**
On "Generate Guide," the generate job downloads section metadata + screenshots, runs the Claude Code CLI (Bedrock backend) to populate `template.html` (placeholders `<!-- SIDEBAR_NAV -->` and `<!-- SECTIONS -->`) using `feature_context.txt` as the primary source of truth, and uploads `runs/{runId}/user_guide.html` to S3. Run status moves `generating → generated`. *(Maps to: T9, T10)*

**FR7 — Regenerate with feedback.**
A user can supply revision instructions; the generate job runs a feedback prompt that revises the existing guide rather than rebuilding from scratch. *(Maps to: T11)*

**FR8 — View / download guide.**
A user can retrieve the generated guide via a presigned S3 URL. *(Maps to: T10)*

**FR9 — Status lifecycle + live UI.**
Run status progresses `created → running → completed → generating → generated` (and `error` from any state). The UI auto-refreshes every ~8 seconds while a run is active. *(Maps to: T1, T9, T12)*

**FR10 — Safe capture behavior.**
The capture workflow never clicks destructive actions (Delete/Remove/real submits) and always closes modals/dialogs after capturing them. *(Maps to: T13)*

**FR11 — Timeout resilience.**
The screenshot job enforces a wall-clock timeout (default 60 min) and, on timeout, saves whatever was captured and marks the run `completed` with `timedOut: true`. *(Maps to: T14)*

## Non-functional requirements

**NFR1 — Runtime fit.** The screenshot job runs a headless browser for ~30–60 min and the generate job runs a Node-based CLI for ~5–10 min; both require sized compute (default 4096 MiB / 2048 CPU on ECS Fargate). Neither fits Lambda's limits.

**NFR2 — Security & least privilege.** Task roles are scoped: screenshot role = S3 + DynamoDB + `bedrock:InvokeModel` + Nova Act; generate role = S3 + DynamoDB + `bedrock:InvokeModel` + `bedrock:InvokeModelWithResponseStream`. Lambda = `ecs:RunTask` + `iam:PassRole` limited to the two task/exec roles. App credentials are passed as runtime container overrides, never baked into images or committed.

**NFR3 — Network posture.** Fargate tasks run in `PRIVATE_WITH_EGRESS` subnets with `assignPublicIp: DISABLED`; egress via a single NAT Gateway. S3 buckets block public access except the frontend bucket served through CloudFront.

**NFR4 — Encryption.** Data at rest in S3 and DynamoDB is encrypted (SSE); data in transit uses TLS (API Gateway, CloudFront, presigned URLs).

**NFR5 — Cost predictability.** Base ~$40–50/month on a weekly schedule (NAT dominant), +~$6–14 per run. PAY_PER_REQUEST DynamoDB and on-demand Fargate keep idle cost near the NAT floor.

**NFR6 — Observability.** Each ECS task streams to CloudWatch with a per-container stream prefix and two-week retention. DynamoDB run records are the source of truth for lifecycle state.

**NFR7 — Single-tenancy.** One deployment documents one app (or a few via per-run URLs). The kit is not a multi-tenant SaaS docs platform.

**NFR8 — Presigned URL hygiene.** Upload and guide URLs default to 3600s expiry and are generated on demand.

## Out of scope

- Auto-publishing the guide to a docs site or CMS (kit outputs an HTML file in S3).
- Redaction of sensitive data in captured screenshots (you scope the workflow away from such screens).
- Crawling or documenting third-party sites you doesn't own.
- A relational datastore, a multi-tenant control plane, or user management/auth for the management UI beyond what you add.
- Agent business logic beyond browser automation, screenshot description, and HTML assembly.

## Dependencies

Your AWS account must support / provide:
- **Bedrock model access** to `us.anthropic.claude-sonnet-4-5-*` (request via console).
- **Amazon Nova Act access** (currently preview — request via AWS).
- A **VPC** (the CDK creates one) and the ability to provision a NAT Gateway.
- **Docker** available at deploy time (CDK builds the container images; Fargate requires `linux/amd64`).
- A **target web app** with a scriptable (non-interactive-MFA) login and a non-production environment is strongly preferred.
- Standard IAM permissions to create S3, DynamoDB, ECS, Lambda, API Gateway, CloudFront, EventBridge, and ECR resources.
