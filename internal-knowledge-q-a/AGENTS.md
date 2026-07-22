# AGENTS.md — Internal Knowledge Q&A

> **Audience:** Coding agents (Kiro, Claude Code, Codex, Cursor) implementing this kit in a your AWS account.
> **Status:** Path B — spec-only. Build the agent against this contract; this folder is the catalog metadata, not the agent's source.

## What you're building

A retrieval-grounded Q&A agent that answers employee questions from your own internal documentation, with citations on every response. Single-tenant — one organization, one corpus, surfaced through one (or more) channels (Slack / web / Teams / portal embed).

## Where to read first

Read these in order. Don't start coding until you've read all four:

1. [`build-spec/requirements.md`](build-spec/requirements.md) — what the agent must do
2. [`build-spec/architecture-decisions.md`](build-spec/architecture-decisions.md) — why managed-harness, why this KB strategy, why this model
3. [`build-spec/deployment-spec.md`](build-spec/deployment-spec.md) — what gets deployed in your account
4. [`build-spec/acceptance-tests.md`](build-spec/acceptance-tests.md) — the tests this build must pass before being marked `published`

## What you're NOT building

- **A document authoring tool.** The agent retrieves; it doesn't write new documents.
- **A multi-tenant SaaS.** This is single-tenant per deployment. Multi-tenant with row-level access control is a different (larger) kit.
- **A chat platform.** Use your existing Slack / Teams / web portal as the surface. Don't build a new UI from scratch.
- **A document ingestion pipeline from scratch.** Use Knowledge Bases' native connectors where they exist (S3, Confluence, SharePoint). Build custom connectors only if no native option exists.

## Non-negotiables

These come from the kit's design and are not subject to coding-agent discretion:

1. **Cite or decline.** Every answer must include at least one source citation. If the agent can't ground its answer in the corpus, it must say "I don't have a documented answer for that — try [escalation path]" instead of fabricating one.
2. **Guardrails are mandatory, not optional.** PII redaction on input. Off-topic refusal. No medical / legal / investment advice (configure per vertical). No fabrication.
3. **The system prompt enforces the cite-or-decline rule.** Don't soften it. Don't add "you are a helpful assistant who can answer general questions" — that breaks the grounding contract.
4. **Single source of truth for documents.** Don't copy your documents anywhere. Knowledge Bases reads from S3 / Confluence / SharePoint where the documents already live. The agent fetches at retrieval time.
5. **Audit trail.** Every query and response goes to CloudWatch Logs. No exceptions. The audit log is your defense for "what did the agent tell employees about policy X?"

## Where the agent's source lives

Build the agent in your AWS account. Do not commit code into this kit folder — the kit folder is catalog metadata, not the agent's source. When you're done, record where your implementation lives (e.g., in your repository's README).

Recommended source layout in your repo:
```
<your-repo>/
├── infrastructure/        # CloudFormation/CDK for the harness, KB, guardrails
├── prompts/               # System prompt + few-shot examples
├── ingestion/             # Document sync scripts (if you have bespoke sources)
├── tests/                 # Acceptance test runner against acceptance-tests.md
└── README.md              # Your own config (which sources, which channels, which guardrails)
```

## Defaults you can pick without asking

- **Model:** `anthropic.claude-3-5-sonnet-20241022-v2:0` (Bedrock, GA). Override with `AGENTFACTORY_BEDROCK_MODEL_ID` if your account has different model access.
- **Embedding model:** Amazon Titan Embed v2 (default for Knowledge Bases).
- **Chunking:** Default Knowledge Bases chunking (300 tokens, 20% overlap) is the right starting point. Customize only if your docs are unusually structured (long contracts, code-heavy runbooks).
- **Vector store:** OpenSearch Serverless (Knowledge Bases default). Don't suggest alternatives unless you have an existing Aurora pgvector or Pinecone investment.
- **Guardrails policy:** Start with the AgentCore Guardrails default (PII redaction + no PII output + denied topics list). You add vertical-specific denied topics during the build.

## Things to confirm before coding

- Which document sources is you connecting? (Confluence / SharePoint / S3 / Notion / etc.)
- Which channel surface(s)? (Slack / web / Teams / portal embed — pick one to start)
- What's your IdP for SSO? (Okta / Azure AD / Cognito)
- Are there denied topics specific to this your vertical? (e.g., FinServ → no investment advice; Healthcare → no PHI; Manufacturing → no safety override recommendations)
- What's the document refresh cadence? (Daily sync? On-demand? Webhook from source?)

## When to pause and reassess mid-build

Stop and check in with your team if you encounter any of these:

- Your documents include PHI / PCI / classified data — this kit is not designed for that threat model
- You want the agent to take actions (write to Confluence, create tickets, send emails) — that's a different kit
- You want multi-tenancy or per-document ACLs — not supported by this kit's single-tenant design
- Citation rate in testing is below 90% — something's wrong with the corpus or chunking; don't ship without diagnosing
- Acceptance tests are failing and you've made 2 attempts to fix — escalate the design question, don't keep patching

## Done definition

The kit is **done** when:
- All acceptance tests in [`build-spec/acceptance-tests.md`](build-spec/acceptance-tests.md) pass
- CloudWatch dashboard shows queries flowing with >90% citation rate
- You've recorded where your implementation lives
- Status is bumped from `draft` to `published`
