# Automated Docs Generator — Starter Kit

> **Vertical:** Cross-vertical · **Sub-segment:** SaaS/ISVs and platform teams that ship a web app and must keep end-user docs current
> **Build Level:** Custom IaC (ECS Fargate + Nova Act + Bedrock + Lambda/CloudFront UI)
> **Deploy Time:** 5–8 days
> **Services:** Bedrock · Nova Act · ECS Fargate · Lambda · API Gateway · CloudFront · S3 · DynamoDB · EventBridge · ECR · VPC · CloudWatch
> **Model:** Anthropic Claude Sonnet 4.5 (via Amazon Bedrock) + Amazon Nova Act (browser automation)

## What this solves

End-user product documentation goes stale the moment the UI changes. Screenshots show last quarter's layout, the steps no longer match, and refreshing a guide means a writer manually re-walking every screen, re-capturing every screenshot, and re-writing every caption. Teams without a dedicated technical writer fall behind by entire releases.

This kit deploys a pipeline that drives your own web app with an AI browser agent (Amazon Nova Act), captures a screenshot of each screen, drafts a description of what's on it with Claude on Bedrock, and assembles the whole set into a polished HTML user guide via the Claude Code CLI. A management UI lets a human review and edit every section before publishing, and an optional schedule re-runs the capture so the guide tracks the product. Human-in-the-loop by design — nothing publishes without review.

## Outcomes

- **[X%] reduction** in time to produce and refresh end-user documentation
- **[N hours/week] saved** per technical writer / enablement owner on manual screenshotting and write-ups
- **Docs stay current** — scheduled re-runs regenerate the guide as the UI changes
- **Human-in-the-loop quality** — every screen ships with an AI-drafted description a reviewer edits before publish, with a full audit trail of runs and sections

## ROI summary

| | |
|---|---|
| Annual savings | Not yet modeled — depends on your docs volume and release cadence |
| Annual AWS cost | ~$40–50/month base (weekly schedule; NAT Gateway dominates) + ~$6–14 per run |
| Return on AWS spend | Model it with your own numbers using the framework below |

Full ROI model in [`business-case/roi-framework.md`](business-case/roi-framework.md).

## What's pre-built vs. what you customize

| Pre-built (in this kit) | You customize |
|---|---|
| CDK stack: S3, DynamoDB, ECS Fargate cluster + 2 task defs, Lambda API, API Gateway, CloudFront, EventBridge, VPC/NAT | Per-app workflow steps in `screenshot-job/workflows.py` |
| Screenshot job container (Nova Act + Chromium) with reusable `helpers.py` | Target app URL + credentials + Nova Act workflow name in `screenshot-job/run.py` |
| Generate job container (Claude Code CLI on Bedrock) | Feature walkthrough in `generate-job/feature_context.txt` |
| Single Lambda API (CRUD, presigned uploads, ECS triggers) | Guide design in `generate-job/template.html` + prompts in `generate.py` |
| React + Vite management UI (review / edit / regenerate) | Stack/bucket/table names + schedule in `infra/lib/stack.ts` |
| One-command `deploy.sh` + implementation guide | Screenshot-analysis prompt context (`PRODUCT_CONTEXT` in `helpers.py`) |

## Shared responsibility

This kit is an accelerator and reference implementation, not a managed service. You deploy it into your own AWS account and own the stack, the workflow definitions, the credentials the agent uses to log into your app, and the published guide. The browser agent navigates your own application with credentials they supply and is scripted to avoid destructive actions; AI-drafted descriptions are reviewed by a human before publish. Nova Act access (preview) and Bedrock model access must be requested in your account. Scripts are provided as-is — partners can offer managed support engagements if needed.

## Ideal customer

| | |
|---|---|
| **Size** | SaaS/ISVs, internal platform/tooling teams, or any org that ships a web app owing end-user/admin/onboarding docs |
| **Volume** | One or more web apps with frequently-changing UIs; docs refreshed monthly/quarterly (or perpetually behind) today |
| **Team** | 1–3 technical writers / enablement owners — or an eng/PM team carrying docs as a side task |
| **Triggers** | UI changes faster than docs can keep up · stale screenshots in published docs · no dedicated writer · slow per-release enablement content |
| **Disqualifiers** | No scripted login / hardware-MFA · compliance-authored docs with no automation tolerance · single static page · canvas/WebGL UI · no automated browser allowed near prod |

---

## How this kit ships (Path B — spec-first)

This kit is **not yet built**. It ships as:
- **Kit metadata** (`kit.json`, this README, `architecture/`, `business-case/`)
- **Coding-agent contract** ([`AGENTS.md`](AGENTS.md) + [`build-spec/`](build-spec/))

You and your engineering team build the pipeline in your AWS account using the contract above and a coding agent of your choice (Kiro / Claude Code / Codex / Cursor). When the build is certified against [`build-spec/acceptance-tests.md`](build-spec/acceptance-tests.md), record where your implementation lives and bump `status` to `published`.

## Quick start

```bash
# 1. Open the kit in your coding agent of choice
cd automated-docs-generator

# 2. Read AGENTS.md — the build contract
# 3. Read build-spec/requirements.md — what the pipeline must do
# 4. Read build-spec/architecture-decisions.md — why these choices
# 5. Read build-spec/deployment-spec.md — what to create in your AWS account
# 6. Read build-spec/acceptance-tests.md — how to verify the build

# 7. Build in your AWS account against the spec
# 8. Run the acceptance tests (T1–T15)
# 9. Record where your implementation lives
# 10. Bump kit.json.status from "draft" to "published"
```

## Architecture (one-paragraph version)

A user triggers a "run" from a React management UI (or EventBridge fires on a schedule). The Lambda API starts an ECS Fargate task — the screenshot job — which uses Amazon Nova Act to log into your app and walk its pages, capturing a PNG of each screen and sending each to Claude on Bedrock for a description. Screenshots land in S3 and section metadata in DynamoDB. The user reviews sections in the UI, edits descriptions, and replaces screenshots as needed, then triggers "Generate Guide," which kicks off a second Fargate task — the generate job — that runs the Claude Code CLI (Bedrock backend) to assemble the sections into an HTML guide from a template plus a feature-context document. The finished HTML is uploaded to S3 and served via a presigned URL. Every run and section is tracked in DynamoDB with a `created → running → completed → generating → generated` status trail.

Full diagram and component breakdown in [`architecture/architecture.md`](architecture/architecture.md).

## Vertical applicability

This is a cross-vertical kit — the pipeline is app-agnostic and the customization surface is "describe your app's screens." It applies anywhere a web UI needs documentation:

- **Software & Internet / SaaS:** keep the product user guide and admin guide in sync with every release.
- **Financial Services:** generate up-to-date operator/back-office tooling walkthroughs for internal platforms under change control.
- **Healthcare:** produce admin and clinician-facing app guides for non-PHI configuration/administration screens (keep the agent off patient-data screens).
- **Public sector / internal IT:** auto-document internal line-of-business apps that no one has time to write guides for.

---

**AgentFactory** · Vertical: Cross-vertical · Kit v0.1.0
