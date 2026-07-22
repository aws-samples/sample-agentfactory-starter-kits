# Requirements — Sentinel Auto-Loan Fraud Detection

> Audience: a coding agent implementing or customizing the kit.

## Functional requirements

**FR1 — Multi-agent fraud screening.** The system shall screen an auto-loan application with four cooperating agents (Identity, Velocity, Financial, Orchestrator).
Each specialist agent analyzes one fraud dimension via its own Bedrock (Claude) system prompt and returns a `risk_score` (0–100), confidence, summary, and structured findings. Agents run sequentially over a shared context so each sees upstream results. *Maps to: T1, T2, T3.*

**FR2 — Deterministic verdict.** The orchestrator shall compute `final_score = 0.25·identity + 0.25·velocity + 0.25·financial + 0.25·peak` and map it to APPROVE (<35), FLAG FOR REVIEW (35–69), or DECLINE (≥70).
The score and recommendation are computed in code in both mock and live modes; the LLM supplies narrative and top risk factors only. *Maps to: T4, T5.*

**FR3 — Explainable output.** Each assessment shall include a per-dimension score-contribution breakdown, a plain-language narrative, top risk factors, and per-agent provenance (`bedrock` vs `heuristic`, model, latency). *Maps to: T6.*

**FR4 — Mock/live toggle with graceful fallback.** The system shall support per-request `mock` and `model_key` control. On any Bedrock failure (no creds, throttling, malformed output) the affected agent shall fall back to the deterministic heuristic engine without failing the pipeline. *Maps to: T7, T8.*

**FR5 — Streaming progress.** The system shall stream per-agent progress (`agent_start` / `agent_complete`) and a final `complete` event over SSE from a POST endpoint, and shall stream analyst-chat answers token-by-token. *Maps to: T9, T10.*

**FR6 — Grounded analyst chat.** The system shall answer follow-up questions about a specific assessment, grounded in that assessment's data. *Maps to: T10.*

**FR7 — Single-origin delivery.** The built SPA and API shall be served from one origin in a single container so the app is one deployable unit. *Maps to: T11.*

## Non-functional requirements

**NFR1 — Latency.** A four-agent live run shall complete in a timeframe acceptable for interactive use with the default tier (Sonnet 4.5 ≈ 10s/agent). Opus 4.8 is offered for batch only, with a documented latency caveat.

**NFR2 — Availability / resilience.** The system shall never hard-fail on Bedrock unavailability; the deterministic engine guarantees a verdict.

**NFR3 — Security.** Single-tenant in your account. The instance role shall grant only `bedrock:InvokeModel` / `InvokeModelWithResponseStream` on Anthropic models + inference profiles. Production deployments shall place authentication in front of the API. Data in transit over HTTPS.

**NFR4 — Cost predictability.** Bedrock cost shall scale with application volume and the live-vs-heuristic split; clear-cut applications can be cleared by the heuristic engine to control spend.

**NFR5 — Determinism / auditability.** Verdicts shall be reproducible from agent scores; provenance shall be recorded per agent so any verdict can be decomposed.

**NFR6 — Single-tenancy.** One deployment per organization in your own account/region; no shared multi-tenant store.

## Out of scope

- Autonomous funding decisions (auto-approve/auto-decline).
- Persistent datastore (reference is in-memory; production persistence is a customization).
- Authentication/authorization layer (must be added for production).
- External credit-bureau / KYC data-source integrations.
- Model fine-tuning or custom inference hosting.

## Dependencies

- Bedrock model access enabled for the chosen Claude tier in your region (`us-east-1` default), via inference profiles.
- AWS account with permissions to create App Runner, ECR, CodeBuild, S3, and IAM roles.
- AWS CLI v2 configured; Docker only for the local-build deploy path.
- Structured application data with identity, velocity, and financial attributes.
