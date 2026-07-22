# Code Intelligence Agent

> **Status:** Draft · Spec derived from a working implementation · Build level: Custom IaC

An MCP server that turns a GitHub codebase into an answerable knowledge base. A user asks a natural-language question in **Amazon Quick** — "Which services handle PII?", "What's in every Kafka topic key?", "How does the payment flow work end-to-end?" — and the agent answers from the actual code, with **file:line citations**. No local clone, no git skills. It ingests repos through the GitHub API, chunks them AST-aware, embeds with Bedrock Titan, retrieves with FAISS, and synthesizes a cited answer with Claude — then tailors the depth to who's asking (executive, architect, security, developer).

## Why this exists

Every engineering-led org has people who need to understand the codebase but can't navigate it: execs, security reviewers, compliance auditors, product, and M&A diligence teams. Today they ask a developer (doesn't scale), commission a stale audit, or hire consultants. This agent makes the code self-serve. It's deliberately **not** a developer IDE copilot — it's organizational code intelligence: the whole company can query the codebase through Quick, and the agent only ever answers over repos the asking user can already see, because GitHub identity is passed through per request. Auto re-indexing on push/PR keeps answers current without full re-crawls.

## How to use this kit

This kit is a blueprint: it contains the architecture, the build contract, and acceptance tests — not the agent's source code. No source is included; the agent is built from the spec. Read [`AGENTS.md`](AGENTS.md) + [`build-spec/`](build-spec/) and have a coding agent (Kiro / Claude Code / Cursor / Codex) implement the pattern in your own AWS account, against your GitHub org and compliance posture.

**What the spec targets:** a deployment with AWS SAM (`sam build && sam deploy --guided`) into your account — an IAM-authenticated MCP Lambda Function URL for Quick, plus the GitHub OAuth + webhook plumbing, and a `chat.py` CLI to exercise the tools without Quick.

## What this kit gives you

| File | What's in it |
|---|---|
| [`kit.json`](kit.json) | Kit manifest — services, model, outcomes, ideal customer, ROI scaffolding |
| [`architecture/architecture.md`](architecture/architecture.md) | The serverless stack, a component diagram, data flow (query + indexing paths), audit trail |
| [`business-case/roi-framework.md`](business-case/roi-framework.md) | ROI math template, cost drivers, objection handling, competitive framing |
| [`AGENTS.md`](AGENTS.md) | Build contract for a coding agent re-implementing or customizing the kit |
| [`build-spec/`](build-spec/) | Requirements, architecture decisions, deployment spec, acceptance tests |

## Shared responsibility

This is an accelerator and a working reference, not a managed service. You own the deployed Lambdas, the GitHub OAuth App and webhooks, the indexed source and embeddings, the KMS key, and the AWS infrastructure in your account. The agent answers only over code the requesting user can already access in GitHub, and it does not modify repositories or take autonomous actions. You and your engineering team adapt the guardrails, role filters, intent routing, and chunking to your repos and compliance posture; the SAM template and deploy steps are provided as-is.
