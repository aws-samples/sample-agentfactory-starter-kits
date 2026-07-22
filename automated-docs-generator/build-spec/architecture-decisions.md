# Architecture Decisions — Automated Docs Generator

> Why the kit is built the way it is. If you're a coding agent tempted to deviate, read the relevant AD first.

## AD1 — Build level: Custom IaC (CDK), not a managed harness

**Decision:** Provision the whole system as a custom application with the AWS CDK (TypeScript).

**Why:** The intelligence here is browser automation (Nova Act) plus screenshot description and HTML assembly (Claude) wrapped in an event-driven batch pipeline. There is no single agent loop to host — there are two long-running containerized jobs, a CRUD API, a static UI, and scheduled triggers. An AgentCore managed harness models a request/response agent, which doesn't fit a 30–60 minute headless-browser job. CDK gives you an auditable, owned stack.

**What this means for the build:** Keep `infra/` as the source of truth for all resources. Don't try to refactor the jobs into a Bedrock Agent or AgentCore harness.

## AD2 — Two separate Fargate jobs (capture vs. generate)

**Decision:** Screenshot capture and guide generation are two distinct ECS Fargate task definitions, triggered independently.

**Why:** They have different runtimes (browser ~30–60 min vs. CLI ~5–10 min), different dependencies (Chromium vs. Node + Claude Code CLI), and different lifecycle points (capture happens, then a human reviews, then generate happens). Splitting them lets each scale and fail independently and keeps a failed generate from wasting a capture.

**Alternatives considered:** One mega-container doing both — rejected because it couples unrelated failure modes and bloats the image.

**What this means for the build:** Two Dockerfiles, two task defs, two `RunTask` triggers in the Lambda.

## AD3 — ECS Fargate, not Lambda, for the jobs

**Decision:** Run both jobs on Fargate.

**Why:** A headless browser walking an app for up to an hour, and a Node-based CLI assembling HTML, both exceed Lambda's 15-minute and memory ceilings. Fargate provides 4 GB/2 vCPU and multi-hour runtime.

**What this means for the build:** The CRUD Lambda only orchestrates (`RunTask`) and serves the API; the heavy lifting is in containers.

## AD4 — Amazon Nova Act for browser automation

**Decision:** Drive the app with Nova Act (natural-language instructions) rather than hand-written Selenium/Playwright selectors.

**Why:** Selector-based automation breaks every time the UI changes — exactly the event that triggers a docs refresh. Nova Act takes instructions like "click the blue Save button in the top-right," which survive markup churn and are far cheaper to maintain across releases.

**Alternatives considered:** Raw Playwright — rejected for maintenance brittleness (though Playwright/Chromium still underpins the runtime). 

**What this means for the build:** Workflow steps are natural-language `safe_act` calls; budget for Nova Act preview access and variable pricing.

## AD5 — Claude Code CLI on the Bedrock backend for guide assembly

**Decision:** Generate the HTML guide by running the Claude Code CLI with `CLAUDE_CODE_USE_BEDROCK=1`.

**Why:** Assembling many sections into a coherent, well-structured HTML document from a template + a feature-context doc is a code/document-generation task the CLI does well. The Bedrock backend means no Anthropic API key — it authenticates via the task's IAM role, keeping secrets out of the system.

**What this means for the build:** The generate container installs Node + the CLI and runs as a non-root user (required with `--dangerously-skip-permissions`). The model is set via `ANTHROPIC_MODEL`.

## AD6 — Claude Sonnet 4.5 as the model

**Decision:** Use `us.anthropic.claude-sonnet-4-5-20250929-v1:0` for both screenshot description and guide generation.

**Why:** Strong vision (screenshot understanding) and long-form structured generation in one model keeps the stack simple. The cross-region inference profile (`us.` prefix) improves availability.

**What this means for the build:** Request model access early; make the model ID configurable for version bumps.

## AD7 — DynamoDB + S3, no relational database

**Decision:** Store run/section metadata in DynamoDB (runs: PK `runId`, SK `createdAt`; sections: PK `runId`, SK `sectionId`) and all binary/text assets in S3.

**Why:** Access patterns are simple and key-addressed (list runs, list sections for a run, get a run). There are no relational queries. DynamoDB PAY_PER_REQUEST keeps idle cost near zero; S3 holds screenshots, descriptions, and guides under a per-run prefix for traceability.

**What this means for the build:** Don't introduce RDS/Aurora. Keep the S3 key convention exact so guides trace back to source captures.

## AD8 — Single CRUD Lambda behind API Gateway

**Decision:** One Lambda function routes all REST endpoints by `resource + httpMethod`.

**Why:** The API is thin (CRUD + presigned URLs + two `RunTask` triggers). One bundled (esbuild) function is simpler to deploy and reason about than a fleet of micro-Lambdas.

**What this means for the build:** Bundle with `--external:@aws-sdk/*`; keep routing in one place.

## AD9 — Human-in-the-loop between capture and generate

**Decision:** Guide generation is a separate, user-initiated step after review; captures are never auto-published.

**Why:** AI descriptions are first drafts. Documentation that ships to end users needs a human's eyes. Inserting review between capture and generate is the core quality control.

**What this means for the build:** Don't chain generate automatically after capture. The schedule re-captures; a human still triggers generate (until you explicitly opts into auto-regenerate).

## AD10 — Safe-by-default capture (no destructive actions, close modals)

**Decision:** The workflow never clicks Delete/Remove or submits forms that create real data, and always closes modals after capturing.

**Why:** The agent runs against a real app with real credentials. A docs run must be side-effect-free. Leaving modals open also pollutes subsequent captures.

**What this means for the build:** Bake this into every `step_*`; treat it as a non-negotiable, not a guideline.

## AD11 — Block third-party domains during capture

**Decision:** Route-block ad/tracking/third-party domains in the browser session.

**Why:** Those domains cause SSL errors, slow loads, and occasional redirects that navigate the agent away from the app, corrupting captures.

**What this means for the build:** Maintain a blocklist in `run.py`; expand it per your app.

## AD12 — Single NAT Gateway, private task subnets

**Decision:** One NAT Gateway; Fargate tasks in private subnets with public IPs disabled.

**Why:** Tasks need egress (Bedrock, Nova Act, the target app, package installs at build) but must not be publicly reachable. One NAT keeps the security posture clean at the lowest fixed cost — and that cost (~$32/mo) is the dominant line item, so it's called out for optimization (VPC endpoints / NAT instance) rather than hidden.

**What this means for the build:** Don't put tasks in public subnets to save the NAT cost; document the optimization options instead.
