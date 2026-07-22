# ROI Framework — TropiCraft Ordering Agent

> The numbers here are **templates and illustrative examples** — real figures come from your own discovery, not from this doc.

## What problem this solves

Digital ordering for food & beverage usually means a static menu and a search box. The guest does all the work: scroll the catalog, guess what's good, and — if they have a dietary need — cross-reference ingredients themselves. Two costs follow. First, **lost conversion and order value**: guests stall, abandon, or default to the same small order; generic "add a drink?" upsells get ignored. Second, **dietary risk and friction**: allergen handling is manual and inconsistent, which is both a liability and a reason cautious guests don't complete an order.

TropiCraft replaces the menu wall with a guided conversation. Sunny asks one question at a time, narrows to items that fit the guest's mood *and* diet, enforces allergen safety as a hard rule, and offers a contextually-relevant add-on only within a strict cap. The intended payoff is **higher conversion and average order value** plus **deflected order-taking labor**, with a **safer, on-brand experience** as the differentiator. Voice extends the same flow to hands-free and accessibility use cases.

## ROI math (template)

**Inputs to gather in discovery:**

| Input | Symbol | Example (illustrative) |
|---|---|---|
| Digital orders / day | `O` | 4,000 |
| Current average order value | `AOV` | $11.50 |
| Expected AOV lift from guided discovery + governed upsell | `Δaov` | 6% |
| Current order-taking labor handled by staff (phone/counter/chat) / day | `H` | 30 hrs |
| Share of that deflected to self-service conversation | `d` | 40% |
| Fully-loaded staff cost / hour | `c` | $22 |
| Avg conversation turns per order (drives model cost) | `t` | 8 |

**Output formulas:**

```
Incremental order value / day   = O × AOV × Δaov
Labor deflected / day ($)       = H × d × c
Gross daily benefit             = incremental order value + labor deflected
Annual benefit                  = gross daily benefit × 365
Bedrock cost / day              ≈ O × t × (avg tokens/turn) × Bedrock price
```

**Worked example (Illustrative, research-backed — not a guarantee):**

Volume and AOV are your inputs (the example below uses 4,000 orders/day at an $11.50 AOV). The **6% AOV lift** is deliberately conservative: Salesforce's Shopping Index (150M sessions) found that recommendation-engaged visits carry a **10.3% higher AOV** across all devices, and McKinsey puts personalization-driven revenue lift at **10–15%** (up to 25% best-in-class). We model roughly half the recommendation-engaged figure to account for guests who don't take the upsell. Baymard's **~50% food/grocery cart-abandonment** baseline is the headroom the guided flow works against.

```
Incremental order value = 4,000 × $11.50 × 0.06   = $2,760/day
Labor deflected         = 30 × 0.40 × $22         = $264/day   (internal estimate — no public source; validate)
Gross daily benefit     = $3,024/day
Annual revenue uplift   ≈ $2,760 × 365            ≈ $1,007,400/yr   (the defensible, sourced term)
```

Per-order economics (volume-independent, the honest way to read the multiple):

```
Incremental basket / order     = $11.50 × 0.06        = $0.69
AI cost / order (blended)       ≈ $0.18               (see Cost section below)
Multiple on incremental revenue = $0.69 / $0.18        ≈ 3.8×
Multiple on 50% margin basis     = $0.345 / $0.18      ≈ 1.9×
```

**Annual AWS cost (illustrative, computed from AWS pricing):**

```
Per text conversation: ~45,000 input tokens + ~1,800 output tokens over ~10 Converse
  tool-use rounds (full menu + rules re-injected each call), Claude 3 Sonnet $3/$15 per 1M:
    input  45,000 × $3/1M   = $0.135
    output  1,800 × $15/1M  = $0.027
    text conversation        ≈ $0.16
Per voice conversation (incremental): Transcribe ~1.3 min × $0.024 = $0.031
    + Polly Neural ~2,400 chars × $16/1M = $0.038          ≈ $0.07
Blended @ 30% voice mix     ≈ $0.16 + 0.30 × $0.07         ≈ $0.18/conversation
Annual @ 1.46M conversations ≈ 1.46M × $0.18               ≈ $263,000/yr
  + Lambda / DynamoDB / API GW / S3 / CloudWatch (<$1K combined)  → ~$265K/yr total
  No OpenSearch Serverless: the menu is injected into the prompt, not a Knowledge Base,
  so there is no ~$350–700/mo OCU floor.
```

**Net read:** ~$1.0M/yr illustrative incremental revenue vs. ~$265K/yr AWS cost → **~3.8× on revenue, ~1.9× on a 50% contribution margin.** Honestly, for a token-heavy per-conversation design the multiple is moderate, not enormous — Bedrock is ~99% of the cost. The case strengthens with (a) tighter prompts / Claude 3 Haiku on simpler turns, (b) any conversion recovery against the ~50% abandonment baseline (not modeled above), and (c) the non-financial value: dietary safety and a differentiated branded experience.

Treat the **AOV lift** as the dominant term and the one to validate with an A/B test against the current ordering flow, not assume. Model the **Bedrock cost** explicitly from turns × tokens × volume; it's the main variable cost and scales with conversation length.

## Cost drivers

| Driver | Notes | Typical range |
|---|---|---|
| Bedrock (Claude 3 Sonnet, Converse) | 1 model call per turn + extra rounds per tool use; cost scales with orders × turns × tokens. The biggest variable cost | $ per 1K conversations — model from token sizes × volume |
| Amazon Transcribe | Per-minute speech-to-text, only on voice turns | Scales with voice mix; $0 if text-only |
| Amazon Polly | Per-character neural TTS, only on voice replies | Scales with voice mix |
| AWS Lambda (×5) | Per-request + duration; arm64, mostly short calls | Low; on-demand |
| DynamoDB (×5 tables) | On-demand read/write; sessions expire at 30-min TTL | Low–moderate with volume |
| API Gateway | Per-request REST | Low |
| S3 (audio) | Audio objects expire after 1 day | Negligible |
| CloudWatch / X-Ray | Logs, dashboard, traces | Low |

The cost lever is **conversation length and the voice mix**: tighter prompts and shorter tool loops reduce Bedrock spend, and text-only deployments avoid Transcribe/Polly entirely. Consider Claude 3 Haiku for lower per-turn cost where the menu and reasoning allow.

## Common objections + responses

- **"Will it recommend something my allergic customer can't eat?"** No — allergen/restriction safety is a hard rule in the system prompt that overrides all recommendation logic; conflicting items are warned, never suggested. The menu the agent reasons over carries the allergen/dietary flags. (This is also the #1 thing to test at sign-off — see acceptance tests T3–T4.)
- **"Can it just take payment and place the order?"** Today it confirms the order and returns a confirmation number; payment and POS/fulfillment are a deliberate, separately-scoped integration so a human/owner controls the money path. Many teams pilot confirmation-only first.
- **"Won't an LLM go off-script or get prompt-injected?"** The prompt has an anti-injection guard (it ignores role-change/prompt-reveal/off-task instructions in user input) and behavioral boundaries (no medical claims, redirect off-topic). User input is treated as untrusted.
- **"Is this another annoying upsell bot?"** No — the upsell governor caps suggestions at 2 per order, respects an opt-out immediately, and tracks declined categories so it doesn't repeat. It only suggests when contextually relevant.
- **"What if Bedrock is slow or down?"** Calls retry with backoff and degrade to a friendly message; Cart/User failures don't crash the conversation. The guest never sees a raw error.
- **"How fast can we see it on our menu?"** A focused engagement (16–24 engineering hrs over ~1–1.5 weeks) gets a branded, deployed instance running on your menu data; the SPA demos locally on mocks day one.
- **"Is our customer data safe?"** It's single-tenant in your own account/region; the only managed-AI calls are in-region Bedrock/Transcribe/Polly. Production auth and PII handling are you own (flagged in the spec).

## Time-to-value benchmarks

| Milestone | Target |
|---|---|
| Local demo of the full conversation on mocks (no AWS) | Day 1 |
| Your menu + allergen data loaded; Sunny prompt re-branded | Day 2–4 |
| Backend deployed to your account via CDK (live Bedrock) | Day 4–6 |
| Allergen-safety + acceptance tests passed; web (and voice) walkthrough | Day 6–8 |

## Differentiation vs. competitors

- **Off-the-shelf ordering platforms (Olo, Toast, ChowNow):** strong at menu, payment, and fulfillment, weak at conversational discovery and dietary reasoning. Position TropiCraft as the **conversational front-end** that hands a confirmed order to your existing platform — additive, not rip-and-replace.
- **Generic chatbot builders (Lex-only, vendor FAQ bots):** intent/slot flows that don't reason over a menu or enforce allergen safety across a whole order. TropiCraft's prompt-grounded recommendation + hard safety rule + tool-driven cart is the difference.
- **DIY ChatGPT/LLM bolt-ons:** one prompt, no governed upsell, no allergen guarantee, no session/cart orchestration, no fallback. TropiCraft ships the tool loop, the safety rule, the upsell governor, and graceful degradation.
- **When this kit is NOT the answer:** you want fully autonomous payment/fulfillment with no human in the loop, has no structured menu/allergen data, needs strict on-prem, or has order volume too low to repay the build. Disqualify early (see `kit.json`).

## Sources

All revenue-uplift figures are **illustrative and research-backed, not guarantees** — validate every input per deployment with an A/B test against the current flow. Cost figures are computed from public AWS pricing.

- **Salesforce Shopping Index — recommendations drive AOV / conversion** (via Hello Retail's compilation, citing a Salesforce study of 150M sessions): recommendation-engaged visits carried **10.3% higher AOV** across all devices (15.2% on tablet), converted 4.6× more often, and made up 7% of visits but 26% of revenue. Backs the AOV-lift ceiling we model conservatively below. https://helloretail.com/nl/blog/2026-06-01-product-recommendation-statistics/
- **McKinsey personalization revenue lift** (cited in the same Hello Retail piece): personalization typically lifts revenue **10–15%**, up to 25% best-in-class. Corroborates the AOV-lift range. https://helloretail.com/nl/blog/2026-06-01-product-recommendation-statistics/
- **Baymard Institute — cart abandonment** (via DontPayFull's compilation): global average **70.22%** across 50+ studies; **grocery/food ~50%**. Backs the abandonment baseline the guided flow works against (conversion recovery is upside, not modeled in the worked example). https://www.dontpayfull.com/explore/cart-abandonment-statistics
- **AWS Bedrock pricing** — Claude 3 Sonnet at $3.00 / 1M input tokens and $15.00 / 1M output tokens. Backs the per-conversation model cost. https://aws.amazon.com/bedrock/pricing/
- **Amazon Transcribe pricing** — $0.024/min speech-to-text. Backs the voice-in cost. https://aws.amazon.com/transcribe/pricing/
- **Amazon Polly pricing** — Neural TTS at $16 per 1M characters. Backs the voice-out cost. https://aws.amazon.com/polly/pricing/

**Internal estimate, no public source:** the labor-deflection line ($264/day in the worked example) and the assumed conversation token sizes (~45K in / ~1.8K out over ~10 Converse rounds), turns-per-order (~8), and voice mix (~30%) are engineering estimates for this kit's design — confirm against your real menu size, traffic, and channel split.
