# Requirements — Intelligent Claims Triage

What the agent must do. Each requirement maps to one or more acceptance tests in [`acceptance-tests.md`](acceptance-tests.md).

## Functional requirements

### FR1 — Ordered triage workflow
Given a submitted claim, the agent executes the workflow in order: extract document → look up policy → assess risk → apply decision. Later steps depend on earlier outputs; the agent does not decide before extraction and policy lookup have run (or explicitly fallen back).

### FR2 — Document extraction
The agent extracts structured fields (incident description, estimated amount, incident date, claim type, policy number, claimant) from a claim document in S3 using Amazon Textract. It handles FORMS/TABLES, falls back to text detection, then to raw-PDF text scraping, and finally to the submitted claim metadata so triage never hard-fails on an unreadable document.

### FR3 — Policy coverage lookup (RAG, with fallback)
The agent looks up coverage type, deductible, coverage limit, covered perils, and exclusions for the claim's policy number from a Bedrock Knowledge Base over your policy documents. When no Knowledge Base is configured (or it returns nothing), it falls back to demo/default policy data tagged with its `source`, so the kit runs before a KB is wired.

### FR4 — Risk scoring
The agent computes a risk score in [0.0, 1.0] from a documented rubric (e.g., claim amount vs. coverage limit, total loss, disputed liability, fraud indicators, peril not covered). The score is capped at 1.0 (`min(sum, 1.0)`).

### FR5 — Auto-approve decision with bounded payout
When risk < 0.7, the agent auto-approves and computes `payout = min(max(estimatedAmount − deductible, 0), coverageLimit)`. The payout is never below zero or above the coverage limit.

### FR6 — Escalate decision with human routing
When risk ≥ 0.7, the agent sets the claim to `ESCALATED`, records the escalation reason, places the claim on the SQS human-review queue, and fires an SNS notification to reviewers. The agent never auto-denies.

### FR7 — Persisted decision + cross-reference
Every decision writes to DynamoDB: `status`, `riskScore`, `riskFactors`, `reasoning`, `escalationReason` (if any), `payoutAmount` (if approved), and the `extractedData` + `policyContext` JSON the decision was based on. `decidedAt` is set on approval.

### FR8 — Policy-grounded reasoning
The agent's `reasoning` references specific policy terms (coverage, deductible, limit, perils, exclusions) used in the decision. It does not invent coverage facts not present in the retrieved policy context.

### FR9 — Asynchronous triage
`POST /claims/{id}/triage` returns HTTP 202 immediately (orchestrator) and runs the agent invocation asynchronously (worker), so triage that exceeds API Gateway's 29-second limit completes without a client timeout. A failed agent invocation marks the claim `AGENT_ERROR` rather than leaving it stuck.

### FR10 — Claim lifecycle API
The kit exposes: `POST /claims` (submit), `GET /claims` (list, filterable by `status` / `policyNumber`), `GET /claims/{id}` (detail), `POST /claims/{id}/triage` (trigger), `GET /claims/{id}/documents` (presigned URLs), `POST /claims/{id}/review` (human decision), `POST /extract` (ad-hoc extraction).

### FR11 — Reviewer decision capture
A human reviewer can submit a decision on an escalated claim via `POST /claims/{id}/review`, which updates the claim record.

### FR12 — Analyst/claimant UI
A browser UI provides adjuster, customer, and reviewer dashboards: submit a claim, trigger triage, view the decision with its policy cross-reference, and work the review queue.

## Non-functional requirements

### NFR1 — Triage latency
End-to-end triage (extract + policy lookup + reasoning + write) completes within the worker's 5-minute budget; typical claims complete in well under a minute. The orchestrator responds in < 1 s with 202.

### NFR2 — Cold-start safety
The agent lazy-loads on first invocation (model, tools, Strands `Agent`) rather than at import time, to stay within AgentCore's cold-start limit.

### NFR3 — Availability
99.5% target for the API and triage path. AgentCore Runtime and Lambda handle load fluctuation; DynamoDB is on-demand (PAY_PER_REQUEST).

### NFR4 — Security
- API Gateway requires an API key with a usage plan (throttle 50 rps / 100 burst, 10k/day quota) on every method; no unauthenticated endpoints.
- The agent execution role is least-privilege: DynamoDB on the claims table + indexes, S3 read/write on the documents bucket, `textract:AnalyzeDocument`/`DetectDocumentText`, `bedrock:Retrieve`/`InvokeModel`/`ApplyGuardrail`, `sns:Publish` on the review topic, `sqs:SendMessage` on the review queue.
- Document access is via short-lived presigned URLs, not public buckets.
- Optional Bedrock Guardrail for PII redaction and topic boundaries on claim narratives.

### NFR5 — Cost predictability
Cost scales with claim volume: Bedrock (Haiku) tokens per triage + Textract pages + the KB OpenSearch Serverless floor. You can estimate from volume and chosen Textract feature types.

### NFR6 — Auditability
Every triaged claim is reconstructable: the persisted decision record (score, factors, reasoning, extracted data, policy context) plus the agent's tool-call/reasoning logs in CloudWatch.

### NFR7 — Single-tenancy
One deployment per organization organization. Multi-tenant (one stack serving multiple orgs) is out of scope.

### NFR8 — Inference profile required
The model is invoked via a region-prefixed inference profile (e.g., `us.anthropic.claude-haiku-4-5-20251001-v1:0`), not a raw on-demand model ID.

## Out of scope

- Auto-deny of claims (the agent auto-approves or escalates only)
- Real-time / inline decisioning under a few seconds
- Payment disbursement (the agent computes a payout figure; paying it is a downstream system)
- Cross-customer data sharing or model fine-tuning
- On-premises / air-gapped deployment
- Fraud investigation workflow beyond escalation routing (SIU tooling is your)

## Dependencies

- Your AWS account has Bedrock model access for the chosen Claude inference profile, plus Textract and (for production) Bedrock Knowledge Bases
- Region supports Bedrock + AgentCore Runtime + Textract
- AgentCore CLI available for the agent deploy; AWS CDK bootstrapped for the stack
- Policy documents available to ingest into a Knowledge Base (for production-quality coverage lookup)
- At least one adjuster / reviewer available for the pilot

## Open extension points (post-v1)

- Repoint `update_claim` / `notify_reviewer` at your core claims and case-management systems
- Additional lines of business (health, warranty, lending) via new policy corpus + extraction fields + rubric
- Confidence-aware extraction (flag low-confidence Textract fields for human verification)
- Multi-document claims (corroborate across estimate + police report + photos)
- Feedback loop: reviewer overturns feed back into rubric tuning
