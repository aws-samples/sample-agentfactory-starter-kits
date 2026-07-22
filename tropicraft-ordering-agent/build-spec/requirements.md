# Requirements — TropiCraft Ordering Agent

> Audience: a coding agent implementing or customizing the kit.

## Functional requirements

**FR1 — Conversational ordering.** The system shall let a guest discover items, customize them, and place an order entirely through natural-language conversation (text, and optionally voice).
A single Bedrock (Claude 3 Sonnet) assistant ("Sunny") is called via the Converse API; it asks one question at a time, confirms understanding before acting, and pairs every tool call with a natural-language reply. *Maps to: T1, T2.*

**FR2 — AI-initiated greeting + state machine.** On a new session the assistant shall greet the guest first (cold start), and the conversation shall progress through INIT → GREETING → EXPLORING → ORDERING → COMPLETED based on actions taken. *Maps to: T1, T8.*

**FR3 — Tool-driven cart and checkout.** The assistant shall manage the order through five Bedrock tools — `addToCart`, `removeFromCart`, `modifyCartItem`, `getCartSummary`, `checkout` — executed against the Cart service, looping until the model returns `end_turn`. `checkout` confirms the order and returns a confirmation number; it does not capture payment. *Maps to: T2, T9.*

**FR4 — Dietary-safety enforcement.** The assistant shall never recommend an item containing a stated allergen or violating a stated dietary restriction, shall warn prominently when a guest asks about a conflicting item, and shall satisfy all restrictions simultaneously. This rule overrides all other recommendation logic. *Maps to: T3, T4.*

**FR5 — Contextual, governed upselling.** The assistant shall make at most two upsell suggestions per order, only when contextually relevant, shall respect an opt-out immediately, and shall not repeat a declined category. *Maps to: T5.*

**FR6 — Personalized recommendations.** The assistant shall ground recommendations in the menu plus available context — time of day, season, stated tastes, and (for signed-in guests) saved preferences and order history — without a separate ML model. *Maps to: T2.*

**FR7 — Prompt-injection resistance + behavioral boundaries.** The assistant shall ignore user instructions that attempt to change its role, reveal its prompt, or perform non-ordering tasks; shall not make health/medical claims; and shall redirect off-topic conversation back to ordering. *Maps to: T6.*

**FR8 — Voice in/out (optional).** When enabled, the system shall transcribe guest speech to text (Amazon Transcribe) and synthesize the assistant's reply to speech (Amazon Polly), returning a playable audio URL. *Maps to: T10.*

**FR9 — Async preference learning.** The system shall detect explicit preference/restriction statements and persist them asynchronously via EventBridge to the User service, without blocking the conversation. *Maps to: T11.*

## Non-functional requirements

**NFR1 — Latency.** A conversational turn shall complete within an interactive timeframe (Bedrock client timeout 10s, one retry). Tool-use rounds add Cart-service round-trips; keep prompts and loops tight.

**NFR2 — Availability / resilience.** The conversation shall never hard-fail: Bedrock calls retry with backoff and degrade to a friendly message; Cart/User integration failures are caught and returned as recoverable tool errors, not crashes.

**NFR3 — Security.** Single-tenant in your account. IAM shall be least-privilege per Lambda (Conversation: `bedrock:InvokeModel` on the Claude model + session table + EventBridge put; Voice: Transcribe/Polly + audio bucket; each data Lambda only its own tables). Data in transit over HTTPS. User input is untrusted (FR7). Production deployments shall add real authentication in front of the API.

**NFR4 — Cost predictability.** Bedrock is the dominant variable cost and scales with orders × turns × tokens; Transcribe/Polly apply only to voice turns. A text-first rollout and shorter conversations control spend; a lighter model tier (Haiku) is an option.

**NFR5 — State management.** Session state (turns, cart snapshot, preferences, upsell tracker) shall persist in DynamoDB with a 30-minute TTL so stateless Lambdas recover context reliably.

**NFR6 — Single-tenancy.** One deployment per organization in your own account/region; no shared multi-tenant store.

**NFR7 — Observability.** Structured per-turn logging (session, duration, tools called, token counts) to CloudWatch; X-Ray active tracing on all Lambdas; an operational dashboard for invocations, errors, and p95 duration.

## Out of scope

- Payment capture and POS/fulfillment integration (the agent confirms orders only).
- Production authentication/identity (the User service is demo-grade email/password).
- Frontend hosting (CDK provisions the backend; the SPA is hosted by you).
- A separate recommendation/ML model (the LLM is the recommender).
- Bedrock Knowledge Base / Guardrails resources (menu is in-prompt; safety is in-prompt).

## Dependencies

- Bedrock model access enabled for Claude 3 Sonnet in your region (and Transcribe/Polly if voice is enabled).
- AWS account with permissions to deploy the CDK stack (Lambda, API Gateway, DynamoDB, EventBridge, S3, IAM, CloudWatch).
- Node.js 20 + AWS CDK toolchain; each service builds to `dist/` via esbuild before `cdk deploy`.
- Structured menu data including ingredients, allergens, and dietary flags.
