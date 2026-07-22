# Deployment Spec — Intelligent Claims Triage

What gets deployed in your AWS account.

## Deployment context

- **AWS account:** Your account, deployed via your IAM role
- **Region:** Your primary region (must support Bedrock + AgentCore Runtime + Textract; for production policy RAG, Bedrock Knowledge Bases / OpenSearch Serverless)
- **Trust boundary:** Single-tenant. One deployment per organization.
- **Source code:** the kit folder is metadata only; the reference implementation repo is the source of truth.
- **Default region in source:** us-east-1 (you can override)

## Two deploy units, in order

The agent runtime and the supporting stack deploy separately. **Order matters** — the CDK stack needs the AgentCore runtime ARN at synthesis time.

```
1. Agent  →  AgentCore Runtime        (agentcore deploy)   →  capture runtime ARN
2. export AGENTCORE_RUNTIME_ARN=...
3. Stack  →  CloudFormation via CDK   (npx cdk deploy)
```

If you deploy the stack before the agent, the `triage-worker` Lambda is wired to a placeholder ARN and triage fails.

## Resources to create

### Agent runtime (AgentCore CLI)
- 1× Bedrock AgentCore Runtime hosting the Strands agent (`agent/claims_triage_agent.py`) with its four tools
- 1× agent execution IAM role (the CLI creates it; least-privilege template at `agent/agent-permissions-policy.template.json`)
- Runtime environment variables: `CLAIMS_TABLE`, `DOCUMENTS_BUCKET`, `REVIEW_QUEUE_URL`, `REVIEW_TOPIC_ARN`, optional `KNOWLEDGE_BASE_ID`, optional `GUARDRAIL_ID` / `GUARDRAIL_VERSION`

### API / compute (CDK stack)
- 1× API Gateway REST API with API key + usage plan (throttle 50 rps / 100 burst, 10k/day quota), CORS enabled, API key required on every method
- 8× Lambda functions (Node.js 20): `submit-claim`, `triage-claim` (orchestrator), `triage-worker` (async → AgentCore, 5-min timeout), `extract-document`, `get-claim`, `list-claims`, `get-document-url`, `review-claim`
- Per-function CloudWatch log groups (`/aws/lambda/claims-triage-*`, 1-week retention in source)

### Data / storage (CDK stack)
- 1× DynamoDB table `claims-triage-claims` (PK `claimId`, SK `createdAt`, PAY_PER_REQUEST) with GSIs `status-index` and `policyNumber-index`
- 2× S3 buckets: `claims-triage-documents-<acct>-<region>` (CORS for browser upload) and `claims-triage-policies-<acct>-<region>`

### Escalation (CDK stack)
- 1× SQS queue `claims-triage-human-review-queue` (5-min visibility timeout, 14-day retention)
- 1× SNS topic `claims-triage-human-review`

### AI services (provisioned alongside)
- Amazon Textract (no resource to create — IAM permission only)
- 1× Bedrock Knowledge Base + OpenSearch Serverless collection over the policy-docs bucket (production; optional for smoke test)
- Optional 1× Bedrock Guardrail for PII redaction / topic boundaries

### Frontend (optional, demo)
- React (Vite) app configured via `frontend/.env` (`VITE_API_URL`, `VITE_API_KEY`); run locally or host as you prefer

## IAM permissions (agent execution role)

Per `agent/agent-permissions-policy.template.json`, least-privilege:
- `dynamodb:GetItem|PutItem|UpdateItem|Query` on `claims-triage-claims` + `/index/*`
- `s3:GetObject|PutObject` on the documents bucket
- `textract:AnalyzeDocument|DetectDocumentText`
- `bedrock:Retrieve|InvokeModel|ApplyGuardrail`
- `sns:Publish` on the review topic; `sqs:SendMessage` on the review queue

The `triage-worker` Lambda separately needs `bedrock-agentcore:InvokeAgentRuntime` (scoped to the runtime ARN at deploy time).

## What you configure during the build

| Configuration item | Format | Source |
|---|---|---|
| AWS region | string | Your choice |
| Bedrock inference profile ID | string | `aws bedrock list-inference-profiles`; set in `agent/claims_triage_agent.py` |
| `AGENTCORE_RUNTIME_ARN` | ARN | Output of `agentcore deploy`; exported before `cdk deploy` |
| `KNOWLEDGE_BASE_ID` | string | Bedrock KB over the policy bucket (production) |
| `GUARDRAIL_ID` / `GUARDRAIL_VERSION` | string | Optional; PII / topic guardrail |
| Risk rubric + threshold | system prompt | `agent/claims_triage_agent.py` |
| Extraction field patterns | code | `agent/tools/extract_document.py` |
| Reviewer routing | env | `REVIEW_QUEUE_URL`, `REVIEW_TOPIC_ARN` |
| Frontend config | `.env` | `frontend/.env` |

## What's pre-built (included with the kit source)

- The full CDK stack (`infra/claims-triage-stack.ts` + `app.ts`)
- All 8 Lambda handlers
- The Strands agent + 4 tools, with the system prompt and risk rubric
- The agent IAM policy template
- The React UI (adjuster / customer / reviewer)
- Sample claim documents (`sample-docs/`) and a sample policy (`policy-docs/`)

## Cost expectations

| Cost driver | Typical range | Notes |
|---|---|---|
| Bedrock (Claude Haiku 4.5) | $0.002–0.02 per claim | Multi-tool reasoning over a claim |
| Amazon Textract | $1.50–$50+ per 1,000 pages | DetectText vs. FORMS/TABLES; the per-claim driver |
| Bedrock KB (OpenSearch Serverless) | ~$345/month floor + usage | OCU minimum dominates at low volume; share across org |
| Lambda + API Gateway + DynamoDB | <$1 per 1,000 claims combined | Negligible at claims volume |
| S3 / SQS / SNS | Pennies–dollars/month | Document storage + escalation volume |
| CloudWatch | $20–50/month | Agent reasoning logs; set retention |

**Plan range:** the KB floor (~$345/month) plus Textract usage are what matter; everything else is cheap and near-linear. At 5,000 claims/month, expect roughly $2–5K/month depending on Textract feature usage.

## Pre-deployment checklist

- [ ] Bedrock model access granted for the chosen inference profile in your region
- [ ] Textract available in the region
- [ ] AgentCore CLI installed; AWS CDK bootstrapped (`npx cdk bootstrap`)
- [ ] Node.js 20+ and Python 3.11+ available
- [ ] Policy documents available to ingest into a Knowledge Base (for production)
- [ ] Your security team's review complete (if applicable)
- [ ] Cost alerts configured in AWS Budgets

## Post-deployment validation

- [ ] Agent deployed to AgentCore; runtime ARN captured and exported
- [ ] `npx cdk deploy` complete; API URL, API key ID, queue URL, topic ARN captured
- [ ] `POST /claims` then `POST /claims/{id}/triage` returns 202 and reaches a terminal status in DynamoDB
- [ ] An auto-approved claim shows a bounded payout and a policy-cited rationale
- [ ] An escalated claim lands on the SQS queue and fires an SNS notification
- [ ] `lookup_policy` returns `source: knowledge_base` once the KB is wired (not the demo fallback)
- [ ] Acceptance tests in [`acceptance-tests.md`](acceptance-tests.md) all pass

## Day-2 operations (you own these)

- Tuning the risk rubric and the auto-approve threshold in the system prompt (redeploy the agent)
- Refreshing the policy Knowledge Base as policies change
- Adjusting extraction field patterns for new document formats
- Repointing `update_claim` / `notify_reviewer` at your claims and review systems
- Reviewing CloudWatch logs and the auto-approval / escalation rates
- Quarterly: rubric effectiveness, escalation precision, extraction accuracy
