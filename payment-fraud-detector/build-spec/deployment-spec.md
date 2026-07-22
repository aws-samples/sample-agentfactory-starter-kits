# Deployment Spec — Payment Fraud Detector

What gets deployed in your AWS account.

## Deployment context

- **AWS account:** Your account, deployed via your IAM role
- **Region:** Your primary region (must support Bedrock, ECS Fargate, ALB, ACM)
- **Trust boundary:** Single-tenant. One CFN deployment per organization.
- **Source code:** Not included in this kit; the implementation is built from this spec.
- **Default region:** us-east-1 (you can override at deploy time)

## CloudFormation stack hierarchy

The deployment uses a master stack + 5 child stacks. They deploy in dependency order:

```
master-stack.yaml
├── vpc-network.yaml          (VPC + subnets + NAT Gateway + internet gateway)
├── ecs-cluster.yaml           (ECS cluster, capacity provider)
├── mcp-server-infrastructure.yaml (ECR repo, IAM roles for MCP)
├── alb.yaml                   (Application Load Balancer + listeners + target groups)
├── ecs-service.yaml           (Streamlit ECS service)
├── mcp-ecs-service.yaml       (MCP server ECS service)
└── bedrock-agent.yaml         (Bedrock Agent + action groups + agent IAM role)
```

Don't collapse these into one stack — separation matches enterprise team boundaries (VPC team, platform team, application team).

## Resources to create

### Networking
- 1× VPC with 2 public + 2 private subnets across 2 AZs
- 1× Internet Gateway, 1× NAT Gateway (single NAT for cost; HA-NAT optional)
- Security groups: ALB-SG (allow 443 from internet), ECS-task-SG (allow from ALB-SG), VPC-endpoint-SG (allow from ECS-task-SG)
- VPC endpoints for Bedrock, S3, CloudWatch Logs, ECR (so ECS tasks reach AWS services without NAT egress)

### Compute
- 1× ECS Fargate cluster
- 2× ECS services on the cluster:
  - **Streamlit** — 2 task minimum, auto-scaling to 8, 0.5 vCPU + 1 GB RAM each
  - **MCP server** — 2 task minimum, auto-scaling to 8, 1 vCPU + 2 GB RAM each
- Auto-scaling policies on both services (CPU >70% scales out; <30% scales in)

### Container registry
- 2× ECR repositories: `streamlit-app`, `mcp-server`
- Image scanning enabled
- Lifecycle policy: keep last 10 images, expire older

### Load balancing
- 1× Application Load Balancer (public, internet-facing)
- HTTPS listener (443) with ACM cert; HTTP listener (80) redirects to HTTPS
- 2× target groups: streamlit-tg (path: `/*`), mcp-tg (path: `/api/*` or vhost-routed)

### AI / agent
- 1× Bedrock Agent with system prompt, action group definitions, model = Claude 3 Sonnet
- 1× action group with RETURN_CONTROL executor pointing at MCP server endpoints
- 1× IAM role for the Bedrock Agent (S3 read on data bucket, Bedrock invoke)
- 1× S3 bucket for transaction data (you manage this bucket; can be empty if using Local Folder mode)

### Observability
- 1× CloudWatch dashboard with Bedrock Agent invocations, ALB requests, ECS CPU/memory, MCP server p50/p95/p99
- 1× CloudWatch log group per ECS service (encrypted with customer-managed KMS key)
- 1× CloudWatch alarm: ALB 5xx rate > 1%
- 1× CloudWatch alarm: ECS task health < 50%

### Identity
- 1× ECS task execution role (per service): pull from ECR, write logs
- 1× ECS task role (per service): app-specific permissions (Streamlit invokes Bedrock; MCP reads S3)
- 1× Bedrock Agent service role: invoke models, call action groups

## What you configure during the build

| Configuration item | Format | Source |
|---|---|---|
| AWS region | string | Your choice |
| Bedrock model ID | string | Default Sonnet; you can upgrade |
| ACM certificate ARN | ARN | Your existing cert or new ACM request |
| Domain name (for the ALB) | DNS name | Your choice; Route 53 alias optional |
| Data S3 bucket name | string | You create; kit grants read |
| Initial test data | JSON files | You adapt pharmacy/generic samples |
| Rule modules | Python files | You curate per vertical (AML, FWA, etc.) |
| KMS key for log encryption | ARN | Your security team provides |
| Log retention duration | days | Your data policy |
| ECS task counts (min/max) | numbers | Your sizing for transaction volume |

## What's pre-built (included with the kit)

- All 6 CloudFormation templates (master + 5 children)
- Deploy script (`infrastructure/cloudformation/deploy.sh`) handles parameter substitution + stack ordering
- MCP server FastAPI codebase with sample rules engine
- Streamlit UI codebase with all analyst views
- Bedrock Agent JSON config + OpenAPI schema for action groups
- Test data generators for pharmacy + generic verticals
- Concurrent-request test harness
- Auto-scaling test harness
- All required IAM policies (least privilege)

## Cost expectations

| Cost driver | Typical range | Notes |
|---|---|---|
| Bedrock invocations (Sonnet) | $0.005–0.05 per analyst session | Token-based; depends on data + narrative length |
| ECS Fargate (4 tasks min, 2 each service) | ~$60–120/month base | Auto-scales with load |
| Application Load Balancer | ~$25/month base + LCU charges | LCU charges minor at fraud-ops scale |
| NAT Gateway | ~$30/month | Single NAT; HA-NAT doubles cost |
| ECR storage | <$10/month | Image layers compress well |
| S3 (transaction data) | $0.023/GB/month | Volume-driven |
| CloudWatch (logs + dashboards + alarms) | $20–50/month | Retention-driven |
| KMS | <$5/month | Per-key + per-API-call |

**Plan range:** $150–250/month base infrastructure for a non-production deployment. Add Bedrock token costs scaling with usage. A deployment handling 500K transactions/month with 12 analysts running ~50 sessions/day should expect $300–700/month total.

## Pre-deployment checklist

- [ ] Bedrock model access granted in your account/region
- [ ] ECS Fargate + ALB + ACM available in the region
- [ ] At least one ACM cert provisioned (DNS-validated, wildcard or specific)
- [ ] S3 bucket created (or let the kit create one)
- [ ] KMS key created with rotation policy
- [ ] Your security team's review complete (if applicable per your policy)
- [ ] Cost alerts configured in AWS Budgets
- [ ] Sample data uploaded to S3 (or kit-included synthetic data sufficient for smoke test)
- [ ] Rule modules reviewed by your fraud-ops lead

## Post-deployment validation

- [ ] All CFN stacks `CREATE_COMPLETE`
- [ ] ALB target groups all healthy
- [ ] Streamlit UI loads at the ALB DNS / your domain
- [ ] MCP server `/health` returns 200 from inside the VPC and via ALB path
- [ ] Bedrock Agent test query in console returns rule fires + LLM narrative
- [ ] Sample analyst session end-to-end works (data load → analysis → narrative)
- [ ] CloudWatch dashboard populates with metrics within 15 min of first session
- [ ] Acceptance tests in [`acceptance-tests.md`](acceptance-tests.md) all pass

## Day-2 operations (you own these)

- Adding/replacing rule modules in `mcp-server/src/rules/`
- Updating the system prompt for the Bedrock Agent
- Refreshing data in S3
- Scaling ECS services up/down based on usage
- Reviewing CloudWatch dashboards weekly
- Quarterly: rule effectiveness review, LLM narrative quality review, false-positive trend
