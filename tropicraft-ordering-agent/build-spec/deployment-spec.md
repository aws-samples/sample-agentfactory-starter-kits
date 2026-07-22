# Deployment Spec — TropiCraft Ordering Agent

> Audience: a coding agent provisioning resources in your account.

## Deployment context

- **Account:** your own AWS account (single-tenant).
- **Region:** a Bedrock-enabled region where Claude 3 Sonnet (and Transcribe/Polly if voice) access is on. Confirm before deploying.
- **Trust boundary:** everything runs in your account; the only managed-AI dependencies are in-region Bedrock, Transcribe, and Polly.
- **Source code location:** not included in this kit — the kit folder holds metadata + specs only. The implementation is built from this spec and lives in your own repository.
- **Delivery unit:** one AWS CDK (TypeScript) stack provisioning the five-service backend; the SPA is hosted separately by you.

## Deploy path

1. **Build each service** to `dist/` (esbuild): `services/{conversation,menu,cart,user,voice}` → `npm install && npm run build`.
2. **Deploy infra:** `cd infrastructure && npm install && cdk deploy`.
3. **Host the SPA:** build `frontend/` (`npm run build`) and host on your choice (AWS Amplify, or S3 + CloudFront); point it at the deployed API Gateway URL (a CDK stack output).
4. **Seed menu data** into the Menu DynamoDB table and keep it consistent with the prompt's menu copy.

## CloudFormation stack (via CDK)

`TropicalSmoothieStack` (`infrastructure/lib/tropical-smoothie-stack.ts`) provisions everything below in one stack.

## Resources to create

- **Compute (AWS Lambda, Node.js 20, arm64):** `conversation` (30s / 512 MB, reserved concurrency 100), `menu` / `cart` / `user` / `voice` (256 MB; voice 30s, others 10s). X-Ray active tracing on all.
- **API (Amazon API Gateway):** one REST API with CORS, routing `/api/conversation/*`, `/api/menu/*`, `/api/cart/*`, `/api/users/*`, `/api/voice/*` to the matching Lambda.
- **Data (Amazon DynamoDB, on-demand):** `sessions` (TTL), `menu` (+ category GSI), `cart`, `users` (+ email GSI), `orders`. All on-demand billing.
- **Events (Amazon EventBridge):** rules for `conversation.preference.detected` and `cart-service` `order.completed` → User Lambda.
- **Storage (Amazon S3):** audio bucket for Transcribe input / Polly output, 1-day lifecycle expiry, auto-delete on stack removal.
- **AI:** Bedrock model access (Claude 3 Sonnet) — no resource to create, but access must be enabled; Transcribe + Polly likewise.
- **Identity (AWS IAM):** least-privilege role per Lambda — Conversation gets `bedrock:InvokeModel` on the Claude model + session table RW + EventBridge put; Voice gets Transcribe/Polly + audio bucket RW; each data Lambda only its own table(s).
- **Observability (CloudWatch + X-Ray):** the `TropicalSmoothie-Operations` dashboard (Conversation invocations/errors/p95) and X-Ray traces.

## What you configure during the build

| Config item | Format | Source |
|---|---|---|
| Menu (prompt copy) | TypeScript constant | `services/conversation/src/core/menu-data.ts` |
| Menu (data) | DynamoDB seed | `services/menu` table |
| Sunny persona + safety + upsell rules | Prompt strings | `services/conversation/src/core/prompt-builder.ts` |
| Tool set | Tool definitions + handlers | `tool-definitions.ts` / `tool-executor.ts` |
| Pricing / tax / checkout | TypeScript logic | `services/cart/src/core/` |
| Model id / tokens / temp / timeout / TTL | Lambda env | `infrastructure/lib/tropical-smoothie-stack.ts` |
| Voice language + Polly voice/engine | TypeScript | `services/voice/src/core/` |
| Frontend branding + API URL | SPA config | `frontend/` |

## What's pre-built

- The five-service backend, the Bedrock Converse tool-use orchestration, the system-prompt builder, the session store, and the voice pipeline.
- The full AWS CDK stack (Lambdas, DynamoDB, API Gateway, EventBridge, S3, IAM, CloudWatch dashboard).
- The React/Vite/Tailwind SPA with MSW mocks and a Vitest/RTL + service-level test suite.

## Cost expectations

| Driver | Typical range |
|---|---|
| Bedrock (Claude 3 Sonnet) | Dominant variable cost — orders × turns × tokens; model per volume |
| Transcribe / Polly | Voice turns only; $0 if text-only |
| Lambda (×5) | Low; on-demand, mostly short calls |
| DynamoDB (×5) | Low–moderate; on-demand, sessions TTL'd |
| API Gateway / S3 / CloudWatch / X-Ray | Low–negligible |

## Pre-deployment checklist

- [ ] Bedrock access enabled for Claude 3 Sonnet (and Transcribe/Polly if voice) in the target region.
- [ ] AWS CLI v2 + CDK configured with permissions for Lambda, API Gateway, DynamoDB, EventBridge, S3, IAM, CloudWatch.
- [ ] Menu data (with allergens/dietary flags) loaded into the Menu table and synced to the prompt copy.
- [ ] Sunny prompt, upsell rules, and tools customized to the brand.
- [ ] Decision recorded: confirmation-only vs. payment/POS integration.
- [ ] Production auth plan and SPA hosting decided.

## Post-deployment validation

- [ ] `GET /api/conversation/health` returns healthy.
- [ ] A new session triggers an AI greeting; a full text order completes to a confirmation number.
- [ ] An allergen/restriction scenario yields zero unsafe recommendations and a prominent conflict warning.
- [ ] Upsell governor (≤2/order, opt-out) and prompt-injection guard behave.
- [ ] Voice transcribe/synthesize round-trip works (if in scope).
- [ ] Per-Lambda IAM confirmed least-privilege; dashboard + X-Ray traces live.

## Day-2 operations (yours to run)

- Add real authentication/IdP in front of the API (the demo user service is email/password).
- Integrate payment + POS/fulfillment if going beyond confirmation-only.
- Establish the menu-update workflow (keep prompt copy + Menu table in sync) and re-test allergen safety after changes.
- Manage Bedrock spend via conversation length, model tier, and the voice mix.
- Set CloudWatch retention/alarms and Bedrock invocation logging.
