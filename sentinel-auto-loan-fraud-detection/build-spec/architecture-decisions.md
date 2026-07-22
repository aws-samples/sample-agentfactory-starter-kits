# Architecture Decisions — Sentinel Auto-Loan Fraud Detection

> Audience: a coding agent that might be tempted to deviate. These are distilled from the source's `aidlc-docs/construction/design-decisions.md` (DD-1…DD-7) plus kit-level packaging decisions. Don't reverse them without reviewing the tradeoffs first.

## AD1 — Four separate agents, not one prompt
**Decision:** Decompose screening into Identity, Velocity, Financial, and Orchestrator agents, each its own Bedrock invocation.
**Why:** A single prompt can't score and explain each fraud dimension independently. Separation is what produces a per-dimension contribution breakdown — the core explainability the product sells. It also lets dimensions be weighted and lets one decisive signal surface.
**What this means for the build:** Keep agents independent; don't collapse them to save model calls.

## AD2 — Deterministic engine behind every agent (DD-1)
**Decision:** Every agent has a deterministic heuristic fallback (`mock_results.py`); a failed/malformed Bedrock call falls back automatically.
**Why:** The system must never hard-fail (no creds, throttling, bad output). Mock mode is also instant and reproducible for the seeded dashboard and tests.
**What this means for the build:** Never ship an agent without its heuristic path.

## AD3 — Deterministic score, LLM narrative (DD-1, DD-4)
**Decision:** `final_score` and `recommendation` are computed in code; the LLM supplies only narrative + top risk factors.
**Why:** Verdicts must be stable, reproducible, and defensible to compliance. An LLM-owned score is neither.
**What this means for the build:** The model output is enrichment, never the verdict.

## AD4 — Equal-weight scoring + peak-signal term (DD-4)
**Decision:** `final = 0.25·identity + 0.25·velocity + 0.25·financial + 0.25·peak`.
**Why:** The original 0.30/0.30/0.25/0.15 let identity+velocity dominate, so a pure single-dimension anomaly never reached "moderate." The peak term ensures one decisive red flag still surfaces — the thesis that rules systems miss correlated/peak signals.
**Alternatives considered:** Fixed unequal weights (rejected — masked single-dimension fraud).
**What this means for the build:** Re-tune weights per deployment risk appetite, but keep a peak term.

## AD5 — Sonnet 4.5 default; Opus 4.8 offered, not default (DD-2)
**Decision:** Default live tier is Claude Sonnet 4.5; expose Haiku 4.5 (Fast) and Opus 4.8 (Max Accuracy) in a selector.
**Why:** Measured latency — Opus 4.8 ≈ 60–75s/agent (≈5 min for a 4-agent run), too slow for interactive use; Sonnet ≈ 10s, Haiku ≈ 4.5s.
**What this means for the build:** Default to Sonnet 4.5; reserve Opus for batch scoring.

## AD6 — Claude 4.x via inference profiles; drop temperature for Opus (DD-3)
**Decision:** Use `us.anthropic.*` inference-profile IDs as `modelId`; omit `temperature` for models that reject it (Opus 4.6/4.7/4.8).
**Why:** These models are served only via inference profiles, and Opus returns a ValidationException when `temperature` is sent.
**What this means for the build:** Don't hardcode bare foundation-model IDs or a global temperature.

## AD7 — SSE over POST for streaming (DD-5)
**Decision:** Stream pipeline + chat as `text/event-stream` from POST endpoints; the frontend reads the body stream manually.
**Why:** The pipeline needs a JSON request body *and* a streamed response; `EventSource` only supports GET.
**What this means for the build:** Keep the manual ReadableStream reader on the frontend.

## AD8 — Per-request mode/model control (DD-6)
**Decision:** `mock` and `model_key` are accepted per request, not just via env.
**Why:** Lets the UI toggle Mock/Live and switch models without restarting — essential for an interactive demo and for routing only borderline apps to live Bedrock.

## AD9 — In-memory store for the demo (DD-7)
**Decision:** Dashboard seeded with three deterministic mock assessments at startup; new runs held in memory.
**Why:** Zero infra for the demo; deterministic seed regardless of mode.
**What this means for the build:** **Production must replace this with a real datastore** — flag this to your team. Not persistent across restarts.

## AD10 — Single container on App Runner
**Decision:** Ship the built SPA + API as one image; deploy to App Runner with a least-privilege Bedrock instance role. CodeBuild path builds the image in-cloud (no local Docker).
**Why:** One deployable unit, one origin (no CORS in prod), minimal infra, fast path to a live URL.
**Alternatives considered:** API Gateway + Lambda (the app maps cleanly to it; App Runner chosen for the demo's single-container simplicity).
**What this means for the build:** Keep single-origin SPA serving; add auth in front for production.

## AD11 — Decision-support, not autonomous decisioning
**Decision:** Output is a recommendation for a human underwriter; no automated funding action.
**Why:** Compliance and risk posture in lending; trust and adoption.
**What this means for the build:** Never wire the verdict to an automated approve/decline action.
