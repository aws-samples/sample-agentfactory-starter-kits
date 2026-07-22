# Intelligent Ticket Triage — Starter Kit

> **Vertical:** Software & Internet · **Sub-segment:** Mid-market SaaS
> **Build Level:** Custom IaC (Bedrock Agents + KB + Guardrails)
> **Deploy Time:** 3–5 days
> **Services:** Bedrock Agents · Knowledge Bases · Guardrails · Lambda · OpenSearch Serverless · S3 · CloudWatch
> **Model:** Anthropic Claude 3.5 Sonnet (via Amazon Bedrock)

## What this solves

SaaS companies with high-volume customer support spend 30–40% of support engineering time on manual ticket triage — reading, categorizing, prioritizing, and routing before anyone starts solving the actual problem. This creates hours-long first-response delays, 20–30% misroute rates, and wasted engineer time on auto-resolvable issues.

This kit deploys a Bedrock Agent that reads incoming tickets, classifies them using historical ticket data, routes them to the correct team, and auto-resolves common issues with KB-grounded responses — all behind Bedrock Guardrails for PII redaction and topic boundaries.

## Outcomes

- **60–70% reduction** in time-to-first-response
- **80%+ classification accuracy** (vs. ~70% rule-based)
- **25–40% of tickets auto-resolved** without human intervention
- Support engineers freed for complex, high-value work

## ROI summary

| | |
|---|---|
| Annual savings (150 tickets/day, 5 engineers) | **$479K/year** |
| Annual AWS cost | **$10K/year** |
| Return on AWS spend | **50–90x** |

Full ROI model in [`business-case/roi-framework.md`](business-case/roi-framework.md).

## What's pre-built vs. what you customize

| Pre-built (in this kit) | You customize |
|---|---|
| Bedrock Agent orchestration (classify → route or resolve) | Knowledge Base content (your tickets, your docs) |
| Knowledge Base structure + Titan Embeddings v2 + OpenSearch Serverless vector store | Guardrail rules (your PII patterns, your topic boundaries) |
| Guardrails template (PII, topics, grounding, content filters) | Routing logic (which team gets what category/priority) |
| Lambda action groups: classify-ticket, route-ticket, resolve-ticket | Confidence threshold for auto-resolution (default 0.9) |
| CloudWatch dashboard | Ticket source integration (Zendesk, Jira, ServiceNow, custom API) |
| One-command deploy script (CloudFormation) | |

## Shared responsibility

This kit is an **accelerator, not a managed service**. Once deployed, you own the agent, the AWS infrastructure, and the data in your account. Scripts are provided "as-is" — AWS does not commit to ongoing maintenance or bug fixes. Partners can offer managed support engagements if needed.

## Ideal customer

| | |
|---|---|
| **Size** | $10M–$200M revenue, mid-market SaaS |
| **Volume** | 50–500+ support tickets/day |
| **Team** | 3–10+ support engineers doing manual triage |
| **Triggers** | Slow response times, 20–30% misroute rate, engineer burnout, leadership AI mandate |
| **Disqualifiers** | <20 tickets/day, no existing ticket system, regulated with no cloud-approved data path |

---

## Repository layout

```
intelligent-ticket-triage/
├── kit.json                           ← Machine-readable manifest (catalog reads this)
├── README.md                          ← You're reading it
├── architecture/
│   └── architecture.md                ← Reference architecture + Mermaid diagram
├── business-case/
│   └── roi-framework.md               ← ROI model + leadership talking points
├── infrastructure/
│   ├── template.yaml                  ← CloudFormation: Bedrock Agent + KB + Guardrails
│   ├── config.example.yaml            ← Your own config (copy to config.yaml)
│   └── deploy.sh                      ← One-command deploy
└── src/
    └── agent/
        ├── agent-config.json
        ├── system-prompt.txt
        └── tools/
            ├── classify-ticket.py
            ├── route-ticket.py
            └── resolve-ticket.py
```

## Quick start

```bash
# 1. Clone this repository and enter the kit
git clone <this-repo-url>
cd agentfactory-starter-kits/intelligent-ticket-triage

# 2. Configure for your environment
cp infrastructure/config.example.yaml infrastructure/config.yaml
# Edit config.yaml with AWS account, region, ticket source details

# 3. Deploy — stands up the stack, packages the Lambdas, prepares the agent,
#    and creates a 'live' alias ready to invoke.
./infrastructure/deploy.sh

# 4. Load your ticket history into the Knowledge Base
#    (4a is the upload, 4b is the ingestion job. Find the data-source-id
#    in the Bedrock console under your KB.)
aws s3 cp ./customer-tickets/ s3://<output-S3BucketName>/ --recursive
aws bedrock-agent start-ingestion-job \
  --knowledge-base-id <output-KnowledgeBaseId> \
  --data-source-id <data-source-id>

# 5. Smoke test
aws bedrock-agent-runtime invoke-agent \
  --agent-id <output-AgentId> \
  --agent-alias-id <output-AgentAliasId> \
  --session-id test-1 \
  --input-text "I cannot log in to my account"
```

The `deploy.sh` script accepts `--skip-package` (CFN only) and `--skip-prepare` (CFN + Lambda only) for iterative debugging.

## Architecture (one-paragraph version)

A Bedrock Agent (Claude 3.5 Sonnet) receives tickets via webhook, queries a Knowledge Base of historical tickets and product documentation for context, then orchestrates three Lambda action groups: **classify** (category + priority + complexity with confidence scores), **route** (maps classification to a team queue with enriched context), or **resolve** (generates a KB-grounded auto-resolution if confidence ≥ 0.9 and complexity is auto-resolvable). Bedrock Guardrails enforce PII redaction, topic boundaries, grounding, and content filters at every step. CloudWatch tracks volume, auto-resolution rate, classification latency, and errors.

Full diagram and component breakdown in [`architecture/architecture.md`](architecture/architecture.md).

---

**AgentFactory** · Vertical: Software & Internet · Kit v1.0
