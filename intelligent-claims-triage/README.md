# Intelligent Claims Triage

> **Status: Draft — spec-only blueprint.** This kit folder contains the catalog metadata, the build contract (`AGENTS.md` + `build-spec/`), and the docs pack — but not the agent's source code. You build the agent from the spec.

A working AI agent that automates first-notice-of-loss claims triage end to end. It extracts data from claim documents with Amazon Textract, cross-references coverage against policy documents in a Bedrock Knowledge Base, scores risk on a 0–1 scale, and then either auto-approves the claim with a calculated payout or escalates it to a human reviewer with policy-cited reasoning. Demo'd on auto insurance claims; the same extract → validate → score → route pattern drops into any document-heavy claims or intake workflow.

## Why this exists

Adjusters spend the first part of every claim doing clerical work: keying repair estimates and incident details out of PDFs, then hunting through policy documents to confirm coverage. Simple, low-risk claims wait in the same queue as complex ones, and cycle time suffers. Leadership wants straight-through processing for the easy claims — but won't sign off on a black-box that auto-approves without an audit trail. This kit is that pattern done responsibly: the agent handles the extract-and-cross-reference grind and auto-approves only low-risk claims, with the payout math and a policy-grounded rationale persisted on every decision. Anything risky escalates to a human with enriched context. Adjusters spend their time on the claims that actually need judgment.

## How to use this kit

This kit is a blueprint. It contains the architecture, the build contract, and acceptance tests — but **not** the agent's source code. No source is included; the agent is built from the spec. Open [`AGENTS.md`](AGENTS.md) + [`build-spec/`](build-spec/) in your coding agent (Kiro / Claude Code / Codex / Cursor) and have it implement the agent in your AWS account against the spec.

**What the spec targets:** a fully-working stack — a Strands triage agent on Bedrock AgentCore Runtime, a CDK (TypeScript) stack (API Gateway + 8 Lambdas + DynamoDB + S3 + SQS + SNS), and a React demo UI with adjuster, customer, and reviewer dashboards. Once built, you swap the sample auto policy for your policy corpus, tune the risk rubric, and deploy into your account.

The kit's `kit.json` describes the agent; the architecture, business case, and build spec define what you build.

## What this kit gives you

| File | What it tells you |
|---|---|
| [`kit.json`](kit.json) | Kit manifest — services, model, outcomes, who it's for, ROI scaffolding |
| [`AGENTS.md`](AGENTS.md) | Build contract for a coding agent customizing or rebuilding the kit |
| [`architecture/architecture.md`](architecture/architecture.md) | Reference architecture diagram + components + data flow |
| [`business-case/roi-framework.md`](business-case/roi-framework.md) | ROI scaffolding you fill in for your deployment |
| [`build-spec/requirements.md`](build-spec/requirements.md) | What the agent must do |
| [`build-spec/architecture-decisions.md`](build-spec/architecture-decisions.md) | Why AgentCore Runtime, why async triage, why escalate ≥ 0.7, why Haiku |
| [`build-spec/deployment-spec.md`](build-spec/deployment-spec.md) | What gets deployed in your account |
| [`build-spec/acceptance-tests.md`](build-spec/acceptance-tests.md) | Tests the build must pass before being marked `published` |

## What's NOT in this kit folder

- **Source code**
- **CDK / CloudFormation templates**
- **Sample claim + policy documents**
- **React UI**

None of these are included. This kit is the specification — your coding agent builds all of the above from `AGENTS.md` + `build-spec/` in your own repository and AWS account.

## Shared responsibility

This kit is an **accelerator and a working reference, not a managed service**. Once deployed, you own the agent, the claims data, the policy corpus, the AWS infrastructure, and the human-review workflow in your own account. You and your engineering team adapt the risk rubric, the policy Knowledge Base, and the extraction fields to your claim formats. The implementation you build is yours to operate and maintain; partners can offer managed support engagements if needed.

## Vertical applicability

The reference implementation is built and demoed for **auto insurance claims**. The architecture — document extraction, policy/coverage cross-reference, risk scoring, auto-decision with human-in-the-loop escalation — extends naturally to other document-heavy decisioning workflows:

- **Auto / P&C claims** (default demo) — repair estimates, total-loss decisions, coverage validation
- **Health / dental claims** — extract claim forms, cross-reference benefits and exclusions, auto-adjudicate clean claims, escalate the rest
- **Lending / mortgage intake** — extract income and asset documents, cross-reference underwriting policy, route exceptions to a human underwriter
- **Warranty / device claims** — extract proof-of-purchase and damage reports, validate against warranty terms, auto-approve in-policy claims

For every vertical the swap is the same: the policy/rules corpus in the Knowledge Base, the extraction fields, and the risk rubric. The orchestration, escalation, and audit plumbing stay put.
