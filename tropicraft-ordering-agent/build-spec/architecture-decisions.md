# Architecture Decisions — TropiCraft Ordering Agent

> Audience: a coding agent that might be tempted to deviate. These are distilled from the source README's design-decision table, the conversation service README, and the implementation. Don't reverse them without reviewing the tradeoffs first.

## AD1 — Single model via Bedrock Converse + tool use (not Bedrock Agents)
**Decision:** The agent is one Claude 3 Sonnet model called with the Bedrock `ConverseCommand` and a `toolConfig`, with a hand-rolled multi-round tool loop in `conversation.ts`.
**Why:** Full control of the prompt, the menu, the dietary-safety rules, and the tool loop — easier to tune and audit than a managed Bedrock Agent for this scope, and no agent-orchestration black box. The loop re-invokes Bedrock until `stopReason: end_turn`.
**Alternatives considered:** Bedrock Agents (rejected — less prompt control for a small, well-defined action set).
**What this means for the build:** Keep the explicit Converse + tool-loop pattern; don't swap in `AWS::Bedrock::Agent`.

## AD2 — Monolithic system prompt with the full menu
**Decision:** `buildSystemPrompt()` injects the entire menu plus all rules into one system prompt every turn.
**Why:** The menu is small enough to fit; no retrieval/context-switching complexity, and the model always sees the whole catalog for recommendations and safety checks.
**Alternatives considered:** RAG/Knowledge Base over the menu (rejected for this size — adds infra for no benefit). Revisit if a your menu is very large.
**What this means for the build:** Keep menu data and the prompt in sync; if the menu grows large, reconsider a retrieval layer.

## AD3 — Dietary safety as a hard prompt rule
**Decision:** Allergen/restriction safety is a CRITICAL section in the system prompt that overrides all other recommendation logic.
**Why:** Safety must be non-negotiable and applied to every suggestion, not a post-filter that can be bypassed. The menu carries allergen/dietary flags the rule reasons over.
**What this means for the build:** Never weaken or remove the rule; the prompt's menu and the Cart's menu must carry the same allergen data so they can't drift.

## AD4 — LLM is the recommender (no separate ML)
**Decision:** Recommendations come from the LLM using context injected into the prompt (time of day, season, tastes, order history) — there is no separate ranking model.
**Why:** The model already reasons over the menu and the guest's context; a separate ML service is unjustified complexity at this scope.
**What this means for the build:** Don't add a recommendation microservice; enrich the prompt context instead.

## AD5 — Governed upselling
**Decision:** Max 2 upsell suggestions per order, opt-out respected immediately, declined categories tracked, suggestions only when contextually relevant (after an add).
**Why:** Ungoverned upselling annoys guests and erodes trust; the governor makes suggestions feel helpful, not pushy.
**What this means for the build:** Keep the `upsellTracker` state and the rules; never remove the cap to "sell more."

## AD6 — Bedrock tool use for actions
**Decision:** Cart actions are five Bedrock tools (`addToCart`, `removeFromCart`, `modifyCartItem`, `getCartSummary`, `checkout`) executed in `tool-executor.ts` against the Cart service.
**Why:** Function calling gives structured, reliable action parsing instead of brittle text parsing; each tool maps to a Cart API call.
**What this means for the build:** Add/modify actions by editing the tool definitions and executor together; always return a tool result the model can act on.

## AD7 — DynamoDB session state with 30-minute TTL
**Decision:** Per-session context (turns, cart snapshot, preferences, upsell tracker) is stored in DynamoDB with a 30-minute TTL.
**Why:** Lambdas are stateless; a TTL'd session store gives reliable context recovery without a long-lived process, and expires abandoned carts automatically.
**What this means for the build:** Keep the session as the source of truth per turn; don't hold state in Lambda memory.

## AD8 — Confirmation-only checkout (no payment/fulfillment)
**Decision:** `checkout` confirms the order and returns a confirmation number; it does not capture payment or commit to a POS.
**Why:** The money/fulfillment path needs explicit controls and ownership; keeping it out of the agent's autonomous scope is a safety and trust decision.
**What this means for the build:** Don't wire `checkout` to a payment API without scoping that work first and a human-owned decision boundary.

## AD9 — EventBridge for async preference learning
**Decision:** A lightweight detector emits `conversation.preference.detected` events; the User service consumes them to persist preferences. `order.completed` is emitted on checkout.
**Why:** Persisting preferences shouldn't block the conversation; decoupling via events keeps the turn fast and the services independent.
**What this means for the build:** Keep preference persistence async; the LLM still does the in-conversation understanding.

## AD10 — Prompt-injection guard + behavioral boundaries in-prompt
**Decision:** The system prompt includes a SECURITY block (ignore role-change/prompt-reveal/off-task instructions) and behavioral boundaries (no medical claims, redirect off-topic, respect declines).
**Why:** User input is untrusted; the agent must stay on task and safe without an external moderation layer for the demo.
**What this means for the build:** Keep these blocks; treat user messages as untrusted. For production, consider adding Bedrock Guardrails as defense-in-depth.

## AD11 — Serverless microservices on CDK
**Decision:** Five Node.js 20 (arm64) Lambdas behind one API Gateway, five DynamoDB tables, an S3 audio bucket, EventBridge rules, least-privilege IAM per Lambda, X-Ray + CloudWatch — all one AWS CDK stack.
**Why:** On-demand scale, no idle cost, clear service boundaries, and IaC that deploys to your account in one command.
**Alternatives considered:** A single monolith Lambda (rejected — couples concerns); containers/App Runner (unnecessary for this event-driven, request/response shape).
**What this means for the build:** Keep the service split and least-privilege roles; rename `tropical-smoothie-*` resources per deployment.

## AD12 — Voice as an optional, separable service
**Decision:** Transcribe (S3 job) and Polly (neural, presigned URL) live in a dedicated Voice Lambda the SPA calls around the normal text flow.
**Why:** Voice is additive — text ordering works without it — and isolating it keeps the conversation path simple.
**What this means for the build:** Keep voice separable; a text-first rollout simply omits the Voice routes and your costs.
