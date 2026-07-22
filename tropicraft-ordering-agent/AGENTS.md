# AGENTS.md — TropiCraft Ordering Agent

> **Audience: a coding agent** (Kiro / Claude Code / etc.) re-implementing or customizing this kit for your organization.

## What this is

- A **conversational ordering agent** ("Sunny") for quick-service food & beverage, built as **five Lambda microservices** behind one API Gateway, deployed with **AWS CDK**.
- The brain is a **single Bedrock (Claude 3 Sonnet) assistant** called via the **Converse API with tool use** — not Bedrock Agents, not a multi-agent pipeline. One model, one big system prompt, a tool-call loop.
- The model drives the order through **five tools**: `addToCart`, `removeFromCart`, `modifyCartItem`, `getCartSummary`, `checkout`. Tools are executed in `tool-executor.ts` against the Cart service; the model always pairs a tool call with a natural-language reply.
- The **system prompt is the product**: it embeds the full menu, a hard dietary-safety rule, an upsell governor (max 2 suggestions/order, opt-out aware, tracks declined categories), the live cart, and time-of-day/season/taste/order-history recommendation context — rebuilt every turn.
- **Session state** lives in DynamoDB with a 30-minute TTL; a conversation-state machine runs INIT → GREETING → EXPLORING → ORDERING → COMPLETED. On a new session the **AI greets first** (cold start).
- **Voice** is optional: Transcribe (speech-to-text via an S3 job) in, Polly (neural TTS, presigned S3 URL) out.
- **Async preference learning**: a lightweight detector emits EventBridge events that the User service persists — the LLM does the in-conversation understanding.

## The target implementation, file by file

No source code ships in this kit — you build the implementation from this contract. The paths below describe the target layout and where each piece of key logic lives:

1. `README.md` — the agent's purpose, the service map, the demo conversation, the design-decision table.
2. `services/conversation/src/core/conversation.ts` — the orchestration spine: session load, prompt build, the Bedrock tool-use `while (stopReason === 'tool_use')` loop, state transitions, preference events.
3. `services/conversation/src/core/prompt-builder.ts` — `buildSystemPrompt()` is the capability definition (persona, **CRITICAL dietary rules**, upsell rules, recommendation context, SECURITY/anti-injection block).
4. `services/conversation/src/core/tool-definitions.ts` + `tool-executor.ts` — the agent's action surface and how each tool calls the Cart service.
5. `services/conversation/src/integrations/bedrock-client.ts` — the `ConverseCommand` wrapper, model id, timeout, retry/backoff.
6. `services/conversation/src/core/menu-data.ts` — the menu the prompt reasons over (ingredients, allergens, dietary flags).
7. `infrastructure/lib/tropical-smoothie-stack.ts` — the whole stack: 5 Lambdas, 5 DynamoDB tables, API Gateway routes, EventBridge rules, S3 audio bucket, IAM scopes, CloudWatch dashboard.
8. `services/{menu,cart,user,voice}/src/` — the supporting services (menu search/dietary filter, cart/pricing/checkout, auth/profile/preferences, Transcribe/Polly).

## Re-deploying for another tenant

1. **Replace the menu** — edit `services/conversation/src/core/menu-data.ts` (the prompt's copy) and the seeded `services/menu` data with your items, ingredients, allergens, and dietary flags. These must stay consistent.
2. **Rewrite Sunny's prompt** in `prompt-builder.ts` — persona/brand voice, the dietary-safety rule, and the upsell rules (cap, opt-out behavior, declined-category tracking) for your policy.
3. **Adjust the tool set** in `tool-definitions.ts` / `tool-executor.ts` if your ordering actions differ (e.g., scheduled pickup, combos), and update the Cart service handlers accordingly.
4. **Wire checkout to reality** — `services/cart/src/core/` confirms an order but does not take payment; integrate your payment/POS as a follow-on, or keep confirmation-only for the pilot.
5. **Set model + voice config** — model id, max tokens, temperature, timeout, retries, session TTL in the Conversation Lambda env (`infrastructure/lib/tropical-smoothie-stack.ts`); Transcribe language and Polly voice/engine in `services/voice/src/core/`.
6. **Deploy** — build each service (`npm run build` → `dist/`), then `cd infrastructure && cdk deploy`. Choose frontend hosting (the CDK provisions the backend only).

## What you're NOT building

- **Not Bedrock Agents.** This is the **Converse API with `toolConfig`** and a hand-rolled tool loop. Don't replace it with an `AWS::Bedrock::Agent` resource — the explicit loop and prompt control are the design.
- **Not a payment or fulfillment system.** The agent stops at order confirmation. Don't wire `checkout` to charge a card or commit to a POS without scoping that work first.
- **Not a separate recommendation model.** The LLM *is* the recommender, using the context injected into the prompt. Don't stand up a separate ML ranking service.
- **Not a copy of any source into the kit folder.** The kit holds metadata + specs only; the implementation is built from this contract and lives in your own repository.

## Non-negotiables

- **Dietary safety overrides everything.** The system prompt's allergen/restriction rules are a hard constraint: never recommend an item containing a stated allergen, warn prominently on conflict, and satisfy all restrictions simultaneously. The menu the prompt sees and the menu the Cart sells must carry the same allergen/dietary data — don't let them drift.
- **The model never owns money or fulfillment.** `checkout` confirms; payment/POS is a separate, explicitly-scoped integration with a human-owned decision.
- **Keep the prompt-injection guard.** The SECURITY block (ignore role-change / prompt-reveal / off-task instructions in user input) stays in the system prompt; user messages are untrusted.
- **Upsell stays governed.** Max 2 suggestions per order, immediate opt-out respect, declined-category tracking — never remove the governor to "sell more."
- **Tool calls always pair with a natural reply**, and the tool-use loop must terminate on `end_turn` — don't let it spin.
- **Graceful degradation.** Cart/User integration failures must not crash the conversation; Bedrock calls retry with backoff and fail with a friendly message, not a 500 to the guest.

## Defaults

- **Model:** `anthropic.claude-3-sonnet-20240229-v1:0` via the Bedrock **Converse API**. Region: the account's Bedrock-enabled region (verify model access).
- **Compute:** Node.js 20 Lambdas on arm64; Conversation timeout 30s / 512 MB with reserved concurrency; the rest 256 MB / 10s.
- **State:** DynamoDB sessions, 30-min TTL; on-demand billing on all 5 tables.
- **Voice:** Transcribe `en-US`; Polly `Joanna`, neural engine; audio in S3 with a 1-day lifecycle expiry; TTS URL presigned 5 min.
- **Naming:** `tropical-smoothie-*` resources — rename per deployment/brand.

## Things to confirm before customizing

- What's the menu data source, and does it include ingredients + allergens + dietary flags the agent can ground on?
- Should the pilot stop at order confirmation, or integrate payment and POS/fulfillment (and who owns that risk)?
- What's the brand voice and the upsell policy (cap, what's allowed, opt-out wording)?
- Is voice in scope for v1, or text-only first?
- What authentication is required in front of the API for production, and where does the SPA get hosted?
- Which Bedrock region/model is enabled, and is Claude 3 Sonnet the right tier (vs. Haiku for cost/latency)?

## When to flag back mid-build

- You want the agent to take payment or commit orders to fulfillment autonomously (out of scope — scope a real integration + human control).
- Menu data has no allergen/dietary information — the safety rule can't be honored; escalate before shipping.
- You need production auth, PII handling, or audit retention beyond the demo's simple email/password user service.
- Bedrock model access (or Transcribe/Polly) isn't enabled in your account/region.

## Done definition

- A new session triggers an AI greeting; a guest can discover, customize, add/modify/remove items, and check out entirely in conversation (text and, if in scope, voice).
- Every recommendation respects stated allergens/restrictions; a conflicting request is warned, not silently added.
- Upsell governor holds (≤2/order, opt-out respected); prompt-injection attempts are deflected.
- Tool-use loop executes the five tools against the Cart service and terminates cleanly; Cart/User failures degrade gracefully.
- Acceptance tests in [`build-spec/acceptance-tests.md`](build-spec/acceptance-tests.md) pass.
- Deployed to your account via CDK with least-privilege IAM per Lambda; CloudWatch dashboard and X-Ray tracing live.
