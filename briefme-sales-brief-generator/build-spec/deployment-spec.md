# Deployment Spec — BriefMe Sales Brief Generator

> Audience: a coding agent provisioning resources in your account.

## Deployment context

- **Account:** your own AWS account (single-tenant).
- **Region:** `us-east-1` by default — Web Grounding + Nova Premier are US-region only. Confirm Nova Premier model access in the chosen region before deploying.
- **Trust boundary:** everything runs in your account; the only outbound dependency is in-region Bedrock model + Web Grounding invocation.
- **Delivery unit:** one AWS CDK (TypeScript) stack (`BriefMeStack`) — agent, API, frontend, auth, storage. No container build.

## Deploy steps

```bash
cd briefme-infra
npm install
npx cdk bootstrap      # first time only, per account/region
npx cdk deploy
```

CDK packages the agent (`briefme-agent/` via `AgentRuntimeArtifact.fromCodeAsset`), the Lambdas (`briefme-api/` via `lambda.Code.fromAsset`), generates the frontend `config.js` with live endpoints, and uploads the SPA. `npx cdk destroy` tears it all down (buckets + table use `DESTROY` removal policy for demo convenience — change for production).

## Resources to create

- **AI / agent:** AgentCore Runtime (`briefme_agent`, Python 3.12, entrypoint `main.py`) via `agentcore.Runtime` + `AgentRuntimeArtifact.fromCodeAsset`; Bedrock Nova Premier + Web Grounding access (no resource to create, but access must be enabled).
- **Compute:** two Lambdas — `generate_brief` (Python 3.12, 512 MB, 120 s) and `get_briefs` (Python 3.12, 256 MB, 10 s).
- **API:** API Gateway HTTP API with a Cognito JWT authorizer; routes `POST /briefs`, `GET /briefs`, `GET /briefs/{briefId}/html`.
- **Identity:** Cognito User Pool (email sign-in, self-signup, auto-verify), an app client (OAuth authorization-code + PKCE), and a Hosted UI domain (`briefme-<account>`).
- **Storage:** DynamoDB table (`briefId` PK, on-demand) with a `companyName-createdAt-index` GSI (`companyNameLower` PK, `createdAt` SK); a private briefs-HTML S3 bucket; a private frontend S3 bucket.
- **Edge:** CloudFront distribution (S3 origin via OAC, SPA error-routing to `index.html`).
- **Observability:** CloudWatch logs (Lambdas + AgentCore Runtime).

## IAM (least-privilege)

- **Agent runtime role:** `bedrock:InvokeModel` / `bedrock:InvokeModelWithResponseStream` on `amazon.nova-premier-v1:0` + the `us.amazon.nova-premier-v1:0` inference profile, and `bedrock:InvokeTool` on the `amazon.nova_grounding` system tool. Nothing broader.
- **`generate_brief` role:** read/write the briefs table + bucket, and `grantInvoke` on the AgentCore Runtime.
- **`get_briefs` role:** read the briefs table + bucket.

## What you configure during the build

| Config item | Format | Source |
|---|---|---|
| Research scope + brief schema | Python string (`SYSTEM_PROMPT`) + `web_research` queries | `briefme-agent/agent.py` |
| Slideshow slides + branding | Python/HTML/CSS | `briefme-api/html_renderer.py` |
| Model id | Env var `BRIEFME_MODEL_ID` | `briefme-infra/lib/briefme-stack.ts` |
| Auth posture | Cognito props (self-signup, domains, callbacks, federation) | `briefme-infra/lib/briefme-stack.ts` |
| Region / resource names | CDK env + construct ids | `briefme-infra/bin/briefme.ts`, stack |
| Frontend branding/UX | HTML/CSS/JS | `briefme-frontend/` |

## What's pre-built

- The Strands agent + `web_research` Web Grounding tool + citation capture.
- The AgentCore direct-code-deployment entrypoint (`main.py`).
- Both Lambdas + the self-contained HTML slideshow renderer.
- The full single-stack CDK (S3, CloudFront, Cognito, DynamoDB, HTTP API + authorizer, Lambdas, AgentCore Runtime, scoped IAM) and the vanilla-JS SPA.

## Cost expectations

| Driver | Typical range |
|---|---|
| Bedrock — Nova Premier | Dominant cost; scales with briefs × (research calls + synthesis tokens) — model per volume |
| Lambda | Low at sales-team volume (pay-per-invoke) |
| DynamoDB / S3 / CloudFront | Negligible–low |
| Cognito | Free tier covers most teams |
| CloudWatch | Low |

## Pre-deployment checklist

- [ ] Nova Premier + Web Grounding enabled in the target region.
- [ ] AWS CLI/credentials configured; CDK bootstrapped in the account/region.
- [ ] Research prompt + brief schema tuned to your motion.
- [ ] Slideshow branding/slides reviewed.
- [ ] Cognito auth posture decided (self-signup vs domain-restricted vs federation).
- [ ] Removal policies reviewed (reference uses `DESTROY` for demo convenience).

## Post-deployment validation

- [ ] Stack outputs captured (AppUrl, ApiUrl, UserPoolId, UserPoolClientId, CognitoHostedUiUrl, AgentRuntimeArn).
- [ ] Sign up + sign in via the Hosted UI succeeds; an unauthenticated `/briefs` call is rejected.
- [ ] A brief generates end-to-end with sections + a Sources slide of real citations.
- [ ] A thinly-covered company degrades gracefully (no fabrication, no 500).
- [ ] Search-by-company returns the brief and re-opens stored HTML.
- [ ] Agent IAM role confirmed least-privilege (Bedrock invoke + `nova_grounding` only).

## Day-2 operations (yours to run)

- Set a brief retention/PII policy and change S3/DynamoDB removal policies off `DESTROY` for production.
- Restrict Cognito self-signup or federate to corporate SSO as required.
- Set CloudWatch log retention + alarms; monitor Nova Premier spend vs. brief volume.
- Re-tune the prompt, brief schema, and slideshow as the selling motion evolves.
- Tear down with `npx cdk destroy` when decommissioning.
