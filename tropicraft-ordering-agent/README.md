# TropiCraft — Conversational Ordering Agent

> **Status:** Draft · Spec-only kit — a blueprint of a working implementation · Build level: Custom IaC

A conversational ordering agent for quick-service food and beverage. A guest opens the chat; **Sunny** — a single Bedrock (Claude 3 Sonnet) assistant — greets them, asks what they're in the mood for, and guides them from discovery to a confirmed order in natural language. Sunny recommends items using time-of-day, season, taste history, and order history; enforces a **zero-tolerance allergen/dietary rule** on every suggestion; upsells within strict frequency limits; and runs the cart-to-checkout flow through **Bedrock tool use** (`addToCart`, `removeFromCart`, `modifyCartItem`, `getCartSummary`, `checkout`). Guests can type or speak — voice in via **Amazon Transcribe**, voice out via **Amazon Polly**.

TropiCraft is an illustrative smoothie-and-juice brand; the pattern is a menu/catalog ordering experience for any QSR, cafe, or F&B operator.

## Why this exists

Online ordering menus put the entire catalog in front of a guest and make them do the work. Guests with dietary needs — vegan, gluten-free, dairy-free, an allergy — have to cross-reference ingredients themselves, and many give up. Blanket upsells ("add a cookie?") get ignored or annoy. TropiCraft's thesis is that a guided conversation removes that friction: it asks one question at a time, narrows to what fits the guest's diet and mood, and only suggests an add-on when it's contextually relevant and within a hard cap. Dietary safety isn't a filter bolted on the side — it's a rule in the system prompt that overrides every other recommendation. The result is meant to be higher conversion and average order value *and* a safer, friendlier experience.

## How to use this kit

This kit is a blueprint, not a codebase: it contains the architecture, the build contract, and acceptance tests — but not the agent's source code. Read [`AGENTS.md`](AGENTS.md) + [`build-spec/`](build-spec/) and have a coding agent (Kiro / Claude Code / Cursor / Codex) implement the pattern in your own AWS account, against your menu, brand voice, and ordering backend.

**What the spec targets:** a frontend that runs locally against MSW mocks (no AWS needed) for a full conversational demo, and a backend deployed to your account with AWS CDK.

## What this kit gives you

| File | What's in it |
|---|---|
| [`kit.json`](kit.json) | Kit manifest — services, model, outcomes, ideal customer, ROI scaffolding |
| [`architecture/architecture.md`](architecture/architecture.md) | The stack, a component diagram, data flow (happy path + degradation + voice), audit trail |
| [`business-case/roi-framework.md`](business-case/roi-framework.md) | ROI math template, cost drivers, objection handling, competitive framing |
| [`AGENTS.md`](AGENTS.md) | Build contract for a coding agent re-implementing or customizing the kit |
| [`build-spec/`](build-spec/) | Requirements, architecture decisions, deployment spec, acceptance tests |

## Shared responsibility

This is an accelerator and a working reference, not a managed service. You own the deployed Lambdas, the menu/allergen data, the prompt and upsell rules, the pricing/checkout logic, and all AWS infrastructure and customer data (sessions, accounts, carts, orders, voice audio) in your account. The agent **confirms orders only** — payment capture, POS/fulfillment integration, and production authentication are your responsibility. You and your engineering team adapt the kit to the brand; CDK and scripts are provided as-is.
