# Deployment Spec — Internal Knowledge Q&A

What gets deployed in your AWS account.

## Deployment context

- **AWS account:** Your account, deployed via your IAM role
- **Region:** Your primary region (must support AgentCore + Knowledge Bases + Bedrock model access)
- **Trust boundary:** Single-tenant. One AgentFactory kit deployment per deployment organization.
- **Source code location:** Your own repo (kit folder is metadata only). Recommended source layout in [`AGENTS.md`](../AGENTS.md).

## Resources to create

### 1× AgentCore Managed Harness instance
- Configured with the cite-or-decline system prompt
- Wired to the Knowledge Base (one)
- Wired to Guardrails policy (one)
- Identity provider: your IdP via OIDC or SAML

### 1× Knowledge Base
- Vector store: OpenSearch Serverless (default)
- Embedding model: Amazon Titan Embed v2
- Chunking: 300 tokens, 20% overlap (default)
- Sources: you provide list of Confluence / SharePoint / S3 / GitHub wiki / Notion / Google Drive
- Refresh cadence: you define (daily sync default; webhooks where supported)

### 1× Guardrails policy
- PII redaction on input (emails, phone numbers, SSN-like patterns, account numbers)
- Denied topics list (you customize per vertical)
- Citation enforcement check on output
- No-fabrication enforcement check on output (defense-in-depth alongside system prompt)

### 1× IAM role per workload component
- Harness execution role: invoke Bedrock, query Knowledge Base, write CloudWatch logs
- Knowledge Base sync role: read from source systems, write to OpenSearch Serverless
- Audit log role: write to CloudWatch with KMS encryption

### 1× CloudWatch dashboard
- Queries per day
- Citation rate
- Refusal rate
- p50 / p95 latency
- Top documents accessed
- Top queries (post-PII-redaction)
- Guardrail intervention counts (by type)
- Estimated cost per query

### 1× CloudWatch log group
- Encrypted with customer-managed KMS key
- Retention duration per your data policy
- Log entries: timestamp, user identity, question (post-redaction), retrieved chunks, cited URIs, answer text, guardrail interventions

### 1× Channel integration (one of)
- Slack: slash command + bot token in AWS Secrets Manager + Lambda for HTTP signature verification
- Web chat: API Gateway + Lambda + your web app embed
- Teams: bot framework + bot token in Secrets Manager
- Portal embed: signed JWT auth from your portal

## What you configure during the build

| Configuration item | Format | Source |
|---|---|---|
| Document source connections | KB connector configs (Confluence URL + token; SharePoint site + cred; S3 bucket + prefix; etc.) | You provide |
| Refresh cadence | Cron / on-demand / webhook | Your choice |
| Denied topics list | YAML list per vertical | You curate |
| Channel surface choice | Slack / web / Teams / portal | Your choice |
| IdP details | OIDC issuer URL + client ID + secret OR SAML metadata | Your IdP team |
| KMS key | ARN of customer-managed KMS key | Your security team |
| Log retention duration | Days | Your data policy |
| Escalation language | Free text — what the agent says when it declines | You customize |

## What's pre-built (included with the kit)

- AgentCore harness configuration template
- System prompt enforcing cite-or-decline
- Knowledge Base configuration template
- Guardrails policy template (denied topics list + PII rules + citation check)
- CloudWatch dashboard JSON
- Sample channel integration code (Slack slash command reference implementation)
- Acceptance test runner

## Cost expectations

| Cost driver | Typical range | Notes |
|---|---|---|
| Bedrock invocations (Claude 3.5 Sonnet) | $0.003–0.015 per query | Depends on input + output tokens |
| Knowledge Base queries | $0.0001–0.001 per retrieval | Volume-driven |
| OpenSearch Serverless | $0.24/OCU/hour baseline | Has minimum baseline regardless of query volume |
| AgentCore runtime | Pay-per-use | Minimal idle cost |
| CloudWatch Logs | $0.50/GB ingested + $0.03/GB stored/month | Retention drives storage cost |
| Document source API calls | Free (your own systems) | Your existing systems |

**Plan range:** $40–80K/year for a 500-employee deployment with moderate query volume. Confirm with your FinOps team before deployment.

## Pre-deployment checklist

- [ ] Bedrock model access granted in your account/region
- [ ] AgentCore + Knowledge Bases + OpenSearch Serverless available in the region
- [ ] IdP integration tested (test user can authenticate)
- [ ] At least one document source connector validated (tokens work, sample doc retrievable)
- [ ] KMS key created with rotation policy
- [ ] Your security review complete (if applicable per your internal policy)
- [ ] Cost alerts configured in AWS Budgets
- [ ] Acceptance tests reviewed by the engineering lead

## Post-deployment validation

- [ ] All acceptance tests in [`acceptance-tests.md`](acceptance-tests.md) pass
- [ ] CloudWatch dashboard shows queries flowing
- [ ] Citation rate ≥ 90% on first 100 production queries
- [ ] Refusal rate between 5–20% (lower = fabrication risk, higher = corpus gap)
- [ ] No PII appears in logs (redaction working)
- [ ] First-week query volume matches discovery estimates ±50%

## Day-2 operations (yours to run)

- Adding/removing document sources
- Refreshing the index after major doc updates
- Updating denied topics list
- Reviewing CloudWatch dashboard weekly for usage trends
- Quarterly: corpus quality review (which questions get refused, which docs are stale)
