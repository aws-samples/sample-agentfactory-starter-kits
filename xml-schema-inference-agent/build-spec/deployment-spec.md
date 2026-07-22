# Deployment Spec — XML Schema Inference Agent

> Audience: a coding agent provisioning resources in your account.

## Deployment context

- **Account:** your own AWS account (single-tenant).
- **Region:** reconcile before deploying — the CDK app (`src/cdk/app.py`) targets `us-west-2`, while the reference agent was deployed in `us-east-1`. Pick one, confirm Bedrock Claude Sonnet 4 access there, and make the CDK env and the agent region consistent.
- **Trust boundary:** everything runs in your account; the only outbound dependency is in-region Bedrock model invocation.
- **Source code location:** not included in this kit — the kit folder holds metadata + specs only. The implementation is built from this spec and lives in your own repository.
- **Delivery unit:** a CDK stack (`SchemaInferenceAgent`) plus a Bedrock Agent created (console or IaC) and pointed at the action-group Lambda.

## Deploy path

| Step | Command / action | What it does |
|---|---|---|
| 1. Install CDK deps | `cd src/cdk && pip install -r requirements.txt` | aws-cdk-lib + constructs |
| 2. Deploy the stack | `cdk deploy` | Creates the S3 traces bucket (+ sample data), the tools Lambda, the Lambda role, and the Bedrock agent role |
| 3. Create the Bedrock Agent | Console or IaC | Name the agent, select Claude Sonnet 4, paste the system prompt from `hackathon/agent_prompt.md` |
| 4. Attach the action group | Console or IaC | Lambda = `schema-inference-agent-tools`; API schema = `src/lambda/api_schema.json` |
| 5. Grant invoke | (in stack) | The Lambda already grants `bedrock.amazonaws.com` permission to invoke it |
| 6. Test | Streamlit Bedrock mode / agent test window | Run a trace batch end-to-end |

## Resources to create

- **AI/agent:** Bedrock Agent (Claude Sonnet 4) + one action group → the tools Lambda. Model access must be enabled in-region (no resource, but a prerequisite).
- **Compute:** Lambda `schema-inference-agent-tools` (Python 3.12, 512 MB, 60 s timeout) for the three tools; optionally the XML→JSON parser Lambda (`lambda/xml_parser.py`) wired to S3 PutObject or Kinesis.
- **Storage:** S3 traces bucket `schema-agent-traces-<account>-<region>` (raw + `parsed/` prefix); sample data deployed via `BucketDeployment`.
- **Identity:** Lambda execution role (`AWSLambdaBasicExecutionRole` + S3 read on the bucket) and the Bedrock agent role (inline `bedrock:InvokeModel` on the specific Claude model + `lambda:InvokeFunction` on the tools Lambda).
- **Ingestion (optional):** Kinesis stream if streaming trace ingestion is used instead of S3.
- **Analytics (optional):** Redshift Serverless workgroup if the generated SQL is to be run/validated.
- **Observability:** CloudWatch log groups for both Lambdas; optional Bedrock invocation logging.

## What you configure during the build

| Config item | Format | Source |
|---|---|---|
| Standard logical-field dictionary | Python dict | `STANDARD_FIELDS` in `src/lambda/schema_agent.py` |
| Nested path patterns | Python dict | `PATH_PATTERNS` in `generate_mapping` |
| Agent system prompt + field catalog | Markdown / agent config | `hackathon/agent_prompt.md` |
| Parser conventions + type rules | Python logic | `lambda/xml_parser.py` (`infer_type`, array handling) |
| SQL target (table, view naming, PartiQL paths) | Python logic | `generate_sql` in `src/lambda/schema_agent.py` |
| Action-group schema | OpenAPI JSON | `src/lambda/api_schema.json` |
| Region / resource names | CDK env + construct ids | `src/cdk/app.py`, `src/cdk/stack.py` |

## What's pre-built

- The three-tool Lambda (`schema_agent.py`) with confidence scoring and unmapped-field reporting.
- The XML→JSON parser Lambda (`xml_parser.py`) with S3 + Kinesis triggers and array handling.
- The OpenAPI action-group schema (`api_schema.json`).
- The CDK stack (S3 bucket + sample-data deployment, Lambda, IAM roles, Bedrock invoke permission).
- The Streamlit demo UI (Local + Bedrock modes) and the local test harness (`test_local.py`).
- Cross-sample traces (`sample_data/`, `hackathon/`).

## Cost expectations

| Driver | Typical range |
|---|---|
| Bedrock (Claude Sonnet 4) | Per onboarding: a few tool-calling turns over a trace batch — model from token sizes × turns |
| Lambda (tools + parser) | Negligible to low (short-lived, on-demand) |
| S3 | Low; scales with retained traces |
| Redshift Serverless (optional) | Charged for RPU-hours when queries run |
| Kinesis (optional) | Only if streaming ingestion is used |
| CloudWatch | Low |

## Pre-deployment checklist

- [ ] Bedrock access enabled for Claude Sonnet 4 in the target region.
- [ ] Region reconciled between CDK app and agent (us-west-2 vs us-east-1).
- [ ] AWS CLI v2 + CDK v2 configured with permissions for S3, Lambda, IAM, Bedrock.
- [ ] `STANDARD_FIELDS` / `PATH_PATTERNS` tuned to your logical model.
- [ ] Parser conventions adapted to the source's array/type idioms.
- [ ] `generate_sql` target table/view confirmed (if Redshift is in scope).
- [ ] PII masking confirmed upstream of parsing.

## Post-deployment validation

- [ ] `cdk deploy` succeeds; stack outputs (bucket, Lambda ARN, agent role ARN) present.
- [ ] Agent runs `analyze_traces` → `generate_mapping` → `generate_sql` on a sample batch.
- [ ] Two structurally different sources resolve to the same logical fields.
- [ ] Mappings carry confidence; unmapped/ambiguous fields are reported.
- [ ] Generated SUPER/PartiQL is valid against the target table (if deployed).
- [ ] Agent role confirmed least-privilege (`bedrock:InvokeModel` on the one model).

## Day-2 operations (yours to run)

- Add a persisted, versioned mapping registry and a schema-change diff workflow.
- Add authentication in front of any UI surface.
- Set CloudWatch retention/alarms and enable Bedrock invocation logging.
- Re-tune `STANDARD_FIELDS`/`PATH_PATTERNS` as new source types appear.
- Provision/scale Redshift Serverless if the query layer moves to production.
- Manage Bedrock spend per onboarding volume.
