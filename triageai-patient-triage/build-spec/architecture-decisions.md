# Architecture Decisions — TriageAI Patient Triage

> Audience: a coding agent that might be tempted to deviate. These are distilled from the source's `aidlc-docs/` (requirements, business rules `RULE-*`, NFR design) plus kit-level packaging decisions. Don't reverse them without reviewing the tradeoffs first.

## AD1 — One constrained Converse call, not a multi-agent pipeline or a harness
**Decision:** Triage is a single Bedrock **Converse** call per intake with one PHI-aware user turn.
**Why:** The job is a bounded classification (urgency + department + supporting fields), not an open-ended task. One constrained call is fast, cheap, predictable, and easy to validate — multi-agent orchestration or an AgentCore harness would add latency and surface area for no benefit.
**What this means for the build:** Keep it one call; don't introduce tools, agents, or multi-turn chat for the core triage path.

## AD2 — Enum-constrained, schema-validated JSON output (RULE-AI-1, RULE-AI-5)
**Decision:** The model must return JSON matching `TriageResult`, with `urgency` and `department` restricted to fixed enums; the response is parsed, code-fence-stripped, and validated; schema-invalid output is retried once.
**Why:** Downstream routing and queue ordering depend on a constrained, trustworthy shape. Free-text or out-of-taxonomy output would break sorting and clinical routing.
**What this means for the build:** Validate with Pydantic; never consume raw model text. Keep the single retry-on-invalid.

## AD3 — Deterministic safe-default behind the model (RULE-AI-2)
**Decision:** Any timeout, AWS error, or post-retry schema-invalid response resolves to a fixed fallback — medium urgency, Primary Care, `model_id="fallback"`, tagged `ai_fallback`.
**Why:** A triage queue must never stall on an external dependency, and a failed AI call must degrade to a safe, conservative, human-reviewed routing — not an error page.
**Alternatives considered:** Surfacing an error to the patient (rejected — leaves the case un-triaged and the queue inconsistent).
**What this means for the build:** Never ship the engine without the deterministic fallback; always tag fallback cases.

## AD4 — PHI excluded from prompt and logs by construction (RULE-AI-7, LOG-*)
**Decision:** `patient_name` and `email` are never placed in the prompt; the logger is allowlist-first and scans for PHI markers; the in-memory store is scrubbed on shutdown.
**Why:** Identity adds nothing to clinical triage and everything to privacy risk. Excluding it by construction (not by redaction-after-the-fact) is the strongest control.
**What this means for the build:** When you customize the prompt or the logger allowlist, keep name/email out. Don't add PHI fields to either.

## AD5 — Claude 3.5 Haiku default, configurable (RULE-AI-3)
**Decision:** Default model is `anthropic.claude-3-5-haiku-20241022-v1:0`, read from config; region and budget are env-driven.
**Why:** Haiku is low-latency and low-cost, which fits a high-volume interactive intake step. The IAM policy and config allow swapping to a higher Claude tier if a you want deeper reasoning.
**What this means for the build:** Keep the model id in config; don't hardcode it. Re-confirm model access per deployment region.

## AD6 — Bounded latency budget with timeout-then-fallback (RULE-AI-4)
**Decision:** The Converse call runs on a worker thread under an 8s timeout; on timeout the engine falls back rather than retrying or blocking.
**Why:** Intake is interactive; an indefinitely slow model call is worse than a safe fallback. Timeouts are not retried (the budget is spent); only schema-invalid responses are.
**What this means for the build:** Keep the timeout/retry semantics distinct — retry schema-invalid, fall back on timeout/error.

## AD7 — In-memory store for the prototype (source requirements §5)
**Decision:** Cases live in an in-memory repository, scrubbed on shutdown; the queue is computed by sorting a snapshot (urgency-desc, submitted-at-asc).
**Why:** Zero infra and strong PHI hygiene for a prototype, with deterministic queue ordering.
**What this means for the build:** **Production must replace this with a real, encrypted, retained datastore** — flag this to your team. Not persistent across restarts.

## AD8 — Staff access is a passcode → signed session token (RULE-STAFF-1..4)
**Decision:** Staff exchange a shared passcode (constant-time compared) for an expiring signed session token (itsdangerous `URLSafeTimedSerializer`); staff routes require a valid Bearer token; the app won't start without the secrets.
**Why:** A demo needs an access gate without standing up an IdP, but it must still be non-trivial — signed, expiring, constant-time, fail-fast on missing config.
**Alternatives considered:** No auth (rejected — staff routes expose case data); full IdP (deferred to production).
**What this means for the build:** Keep the gate for the demo; replace with your IdP for production. Never log the passcode or token.

## AD9 — Security middleware on by default (RULE-HTTP-1..4, SECURITY-04)
**Decision:** Every response carries 5 security headers; requests are rate-limited, body-size-limited (64 KB), and CORS-restricted to an explicit origin.
**Why:** A health-data app should be secure by default, not as an afterthought; these are cheap, standard controls.
**What this means for the build:** Keep the middleware chain and order; tune limits/origins per deployment, don't remove them.

## AD10 — Decision-support, not autonomous triage
**Decision:** Output is a recommendation that routes into a human staff queue; the system takes no clinical action.
**Why:** Clinical safety, regulatory posture, and adoption all require a human clinician in the loop.
**What this means for the build:** Never wire the urgency/department output to an automated clinical action.
