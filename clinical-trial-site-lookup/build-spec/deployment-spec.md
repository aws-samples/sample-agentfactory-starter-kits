# Deployment spec — Clinical Trial Site Lookup

What "done" looks like. The coding agent reads this to know when to stop building; you read this to verify before bumping kit status to `published`.

## Target environment

- **AWS account:** Your account, deployed via your IAM role
- **Region:** Your primary region — typically `us-east-1` for US pharma, `eu-west-1` for EU deployments (data residency for your CRO database)
- **Networking:** Your existing VPC. AgentCore Managed Harness handles its own networking; you-built MCP servers (`cro_db_*`) need to be reachable from AgentCore Gateway. Default: VPC-internal endpoint with PrivateLink if your CTMS supports it, public HTTPS with IAM auth otherwise.

## AWS resources to create

For `managed-harness`, the coding agent creates the following against the live AgentCore APIs:

- **1× AgentCore Harness** with the system prompt, tool list, and Knowledge Base reference defined in the harness config. The harness loads the system prompt from this kit's `AGENTS.md` (the "System prompt" section) — kept in sync via your coding agent.
- **1× IAM execution role** that the harness assumes. Permissions:
  - `bedrock:InvokeModel` on the configured model
  - `bedrock:Retrieve` on the kit's Knowledge Base
  - `bedrock-agentcore:InvokeGateway` on your Gateway (for the `cro_db_*` MCP servers)
  - `cloudwatch:PutMetricData` for the kit's custom metrics
- **1× AgentCore Gateway** entry per MCP server you build (`cro_db_search`, `cro_db_enrollment_history`). Gateway centralizes auth + observability for your internal data sources.
- **1× Bedrock Knowledge Base** with OpenSearch Serverless backing, populated from your therapeutic-area taxonomy + site profile docs.
- **1× S3 bucket** for the KB source documents and ingestion job artifacts.
- **1× Bedrock Guardrail** with the kit's PHI / topic / content config. The guardrail is shared across all queries through this kit.
- **1× CloudWatch dashboard** showing: queries/day, citation rate, source mix (ClinicalTrials.gov vs CRO DB vs KB), p50/p95/p99 latency, refused queries (PHI / off-topic), error rate per tool.
- **1× CloudWatch log group** with 7-year retention (clinical-research compliance default; extend it per your own policy).
- **0× Lambda functions.** None of this kit's logic runs in Lambda. Tool execution happens in the MCP servers you build, agent orchestration happens in the harness.

## IAM permissions

The harness execution role needs:

```
bedrock:InvokeModel                       → on the configured Bedrock model id
bedrock:Retrieve                          → on the kit's Knowledge Base ARN
bedrock-agentcore:InvokeGateway           → on your Gateway ARN
cloudwatch:PutMetricData                  → on the AgentFactory/clinical-trial-site-lookup namespace
cloudwatch:CreateLogStream + PutLogEvents → on the kit's log group
guardrail:ApplyGuardrail                  → on the kit's Guardrail ARN
```

Your MCP servers need your own IAM roles for you-side data store (BigQuery / Postgres / Snowflake). Those are out of scope for this kit's IaC — they're built and authorized by your coding agent against your data warehouse standards.

## Secrets and credentials

- **Your CRO database connection** — connection string or service-account credentials for your CTMS. Stored in AgentCore Identity Token Vault. The MCP server fetches at request time via `${arn:aws:bedrock-agentcore:...:credentialprovider/...}` substitution.
- **No secrets for ClinicalTrials.gov** — public API, no auth.
- **No secrets for the KB** — populated by your data team, accessed via IAM.

## Deployment steps (suggested)

The coding agent decides specifics, but here's the sequence:

1. **Create the IAM execution role** with the permissions listed above
2. **Create the S3 bucket** for KB source data
3. **Create the Bedrock Guardrail** with the PHI / topic / content config
4. **Create the Bedrock Knowledge Base** + OpenSearch Serverless backing, point at the S3 bucket
5. **Your data team uploads** the therapeutic-area taxonomy + site profile docs to S3
6. **Run the KB ingestion job** to embed and index the docs
7. **Build and deploy your `cro_db_*` MCP servers** — connection details to your CTMS
8. **Register the MCP servers behind AgentCore Gateway** with the appropriate auth (SigV4 / OAuth depending on your setup)
9. **Create the AgentCore Harness** with the system prompt, tool references, KB reference, and execution role
10. **Create the CloudWatch dashboard** and log group
11. **Smoke-test** with the canonical inputs from `acceptance-tests.md`
12. **Hand off to you** for the production rollout (additional therapeutic areas, blocked-site lists, etc.)

## Handoff to your team

What your team must do **after** the coding agent finishes:

1. **Populate the KB.** Your clinical operations or data team uploads:
   - Therapeutic-area taxonomy (per program / indication, with synonyms)
   - Site profile notes (free-text, optional)
   - Any qualified-site lists from past trials
2. **Configure your CRO database MCP server.** The CTMS / data-warehouse team confirms the schema mapping: which database fields surface as `enrollment_history`, `site_status`, etc.
3. **Tune ranking weights** based on your site-selection methodology. The defaults (40/30/20/10) are reasonable starting points; you may want to weight PI track record higher for first-in-human studies, or geography lower for telemedicine-friendly trials.
4. **Set up blocked / preferred site lists** per program. These are usually maintained in your own portfolio-management system; the kit reads them from a location you specify (S3 / DynamoDB / your own database).
5. **Run the kit's `acceptance-tests.md`** against your actual data with your actual site selectors.

## Done criteria

The build is "done" when:

- All resources in **AWS resources to create** exist and are tagged appropriately (cost center, project, environment)
- All acceptance tests in `acceptance-tests.md` pass against synthetic data
- CloudWatch dashboard renders without errors and shows non-zero metrics from the smoke test
- A site selector at you can run a real query through the agent and get a credible, fully-cited shortlist
- You have recorded where your implementation lives and who certified it
- Your compliance team has reviewed the audit log format and confirmed it's adequate for your retention requirements
