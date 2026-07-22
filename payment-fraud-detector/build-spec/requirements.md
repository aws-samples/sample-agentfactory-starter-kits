# Requirements — Payment Fraud Detector

What the agent must do. Each requirement maps to one or more acceptance tests in [`acceptance-tests.md`](acceptance-tests.md).

## Functional requirements

### FR1 — Hybrid detection (rules + LLM)
The agent runs a deterministic rules engine over a transaction set and a Bedrock-powered LLM analyst layer that summarizes the rule fires. Rules and LLM are separate components; the LLM never bypasses or overrides rule output.

### FR2 — Rule fires are auditable
Every rule that fires for a transaction logs: rule ID, rule parameters (thresholds, matched values), transaction ID, timestamp. Audit log is append-only and queryable.

### FR3 — LLM narrative grounded in rule output
The LLM analyst summary references specific rule fires by ID and explains them in customer-facing language. The LLM does not invent rule fires that didn't happen.

### FR4 — Decision-support only (no auto-block)
The agent surfaces and explains; humans decide. The kit does not auto-block, auto-quarantine, or take any action on flagged transactions. Action-taking is an explicit follow-on engagement.

### FR5 — Multiple data source modes
The kit supports at least two transaction data source modes: (1) Local Folder for development/demo, (2) S3 bucket for production. Both must produce identical analysis output for the same data.

### FR6 — Bedrock Agent uses RETURN_CONTROL action groups
The Bedrock Agent calls the rules engine via action groups with `RETURN_CONTROL` executor. The MCP server is the executor. Direct Lambda action groups are not used.

### FR7 — Streamlit analyst UI
An analyst-facing UI provides: dashboard view (high-level alert volumes), alerts view (rule fires), raw-data view (transaction inspection), senders view (counterparty analysis), coordinators view (cross-transaction patterns). Each session shows both rule fires and LLM narrative.

### FR8 — Multi-vertical configurable
The rules engine is configurable per vertical: pharmacy/healthcare claims, FSI AML, insurance, generic payment integrity. Switching vertical means swapping rule modules + data schemas, not rewriting the agent.

### FR9 — Concurrent request support
The MCP server supports concurrent analyst sessions without state leakage. Tested via `mcp-server/test_concurrent_requests.py`.

### FR10 — Health endpoint
MCP server exposes `/health` returning HTTP 200 and a JSON body. ALB target group uses this for health checks.

## Non-functional requirements

### NFR1 — Rule engine latency
Pure rules engine analysis (no LLM) returns in <100 ms p95 for a single transaction analysis. Tested via load tests.

### NFR2 — End-to-end latency
Full agent invocation (rules + LLM narrative) returns in <30 s p95. Most of the latency is Bedrock token generation; rules contribute <5%.

### NFR3 — Availability
99.5% target for the production deployment. ECS Fargate auto-scaling handles load fluctuations.

### NFR4 — Security
- All AWS-side data (S3, ALB logs, CloudWatch) encrypted at rest with customer-managed KMS keys
- All traffic to ALB uses HTTPS (TLS 1.2+); HTTP redirects to HTTPS
- VPC private subnets host the MCP server and Streamlit; ALB is the only public-facing component
- IAM roles follow least privilege; the agent role does not have S3 write to production buckets

### NFR5 — Cost predictability
You can predict costs from transaction volume + analyst session count. CloudWatch dashboard exposes per-session token usage.

### NFR6 — Auditability for compliance
Every flagged decision (rule fire + LLM narrative) is logged to CloudWatch with retention per your data policy. Audit logs can be replayed to reconstruct the full decision rationale.

### NFR7 — Single-tenancy
This kit is single-tenant per deployment. Multi-tenant deployments (one CFN stack serving multiple organizations) are out of scope.

## Out of scope

- Real-time / transaction-time inline scoring
- Auto-block / auto-quarantine of flagged transactions
- Cross-customer data sharing or shared model fine-tuning
- On-premises deployment
- Mobile or native-app analyst UIs (Streamlit is browser-only)
- Direct integration with payment networks (ACH, Visa, Mastercard) — the kit consumes data, not raw network feeds

## Dependencies

- Your AWS account has Bedrock model access for Claude 3 Sonnet (or upgrade target)
- You have transaction data extractable to S3 or local file format
- You have at least one fraud-ops analyst available for pilot sessions
- Your region supports Bedrock + ECS Fargate + ALB

## Open extension points (post-v1)

- OFAC / sanctions screening rule module
- Multi-modal input (e.g., document analysis on supporting paperwork)
- Cross-session memory ("you've flagged this counterparty before")
- Real-time scoring sub-component for high-volume use cases
- Vertical-specific UI customizations beyond what Streamlit components support today
