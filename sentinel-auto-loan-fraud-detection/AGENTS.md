# AGENTS.md — Sentinel Auto-Loan Fraud Detection

> **Audience: a coding agent** (Kiro / Claude Code / etc.) re-implementing or customizing this kit for your organization.

## What this is

- A **multi-agent fraud screening pipeline** for auto-loan / dealer-finance applications.
- **Four agents, each a separate Bedrock (Claude) invocation** with its own system prompt: Identity Verification → Application Velocity → Financial Anomaly → Orchestrator/Decision.
- Agents run **sequentially over a shared context dict** — each agent's output is appended so downstream agents see upstream findings.
- The Orchestrator applies a **deterministic weighted score** (`0.25·identity + 0.25·velocity + 0.25·financial + 0.25·peak`) and maps it to APPROVE (<35) / FLAG (35–69) / DECLINE (≥70). The model supplies narrative; the **score and verdict stay deterministic**.
- Every agent has a **deterministic heuristic fallback** so the system never hard-fails. There is a **mock/live toggle per request**.
- Delivery surface: **FastAPI backend** (one-shot + SSE streaming + grounded "Ask the Analyst" chat) + **React/Vite/Tailwind SPA**, shipped as **one container** to **App Runner**.

## The target implementation, file by file

No source code ships in this kit — you build the implementation from this contract. The paths below describe the target layout and where each piece of key logic lives:

1. `README.md` — the agent's purpose, the four-agent table, the scoring model, the demo script.
2. `backend/pipeline.py` — the orchestration spine: how the four agents are sequenced and the context is threaded.
3. `backend/agents/*.py` — each agent's system prompt and JSON contract. The prompts *are* the capability definition.
4. `backend/bedrock_client.py` — Bedrock invocation, model tiers (inference-profile IDs), mock/live control, streaming, the JSON-extraction + fallback logic.
5. `backend/mock_results.py` — the deterministic heuristic engine and score-contribution math (the rule logic behind every agent).
6. `backend/models.py` — `LoanApplication`, `AgentResult`, `Assessment` Pydantic schemas (the data contract).
7. `aidlc-docs/construction/design-decisions.md` — DD-1…DD-7, the rationale for the deterministic-fallback and scoring choices.
8. `infra/deploy-codebuild.sh` + `infra/bedrock-policy.json` — how it deploys and the exact IAM scope.

## Re-deploying for another tenant

1. **Replace the application schema** — edit `LoanApplication` in `backend/models.py` to match your origination data.
2. **Rewrite the four agent system prompts** in `backend/agents/` for your product and the fraud signals that matter to them.
3. **Re-tune the heuristic engine** in `backend/mock_results.py` — the per-agent rules and thresholds, plus the orchestrator weights/cutoffs if your risk appetite differs.
4. **Pick the model tier** in `backend/bedrock_client.py` (`MODEL_CHOICES` / `DEFAULT_MODEL_KEY`) — Sonnet 4.5 default; Haiku 4.5 for speed; Opus 4.8 for batch/max reasoning (note its latency).
5. **Deploy** via `infra/deploy-codebuild.sh` (builds image in CodeBuild → ECR → App Runner, no local Docker) or `infra/deploy-apprunner.sh` (local Docker). Set `MOCK_MODE=false` for live Bedrock.

## What you're NOT building

- **Not an auto-decision system.** The output is a recommendation for a human underwriter. Do not wire it to auto-approve or auto-decline funding.
- **Not a persistent datastore.** The reference uses an in-memory store seeded with three demo assessments (DD-7). A production build needs a real store — flag this to your team.
- **Not a new model.** Use Bedrock-hosted Claude via inference profiles; do not fine-tune or stand up custom inference.
- **Not a copy of any source into the kit folder.** The kit holds metadata + specs only; the implementation is built from this contract and lives in your own repository.

## Non-negotiables

- **Score and verdict are deterministic.** The LLM enriches narrative and risk factors, but `final_score` and `recommendation` are computed from agent scores in code, in both mock and live modes. Never let the model own the verdict.
- **Every agent must have a heuristic fallback.** A failed/malformed Bedrock call falls back to the deterministic engine — the pipeline never hard-fails.
- **Explainability is a feature, not a nice-to-have.** Each verdict ships a per-dimension score contribution + a plain-language narrative + cited findings. Don't collapse this to a single opaque score.
- **Agents are separate Bedrock invocations**, not one mega-prompt — that separation is what lets each dimension be scored and explained independently.
- **Claude 4.x is served via inference profiles** (`us.anthropic.*` IDs as `modelId`); omit the `temperature` field for Opus models that reject it.
- **IAM is least-privilege:** the instance role grants only `bedrock:InvokeModel` / `InvokeModelWithResponseStream` on Anthropic models + inference profiles.

## Defaults

- **Model:** `us.anthropic.claude-sonnet-4-5-20250929-v1:0` (balanced tier). Region `us-east-1`.
- **Deploy target:** App Runner, single container, port 8000, health check `/api/health`, `MOCK_MODE=false` in cloud.
- **Service/role naming:** `sentinel-fraud` service, `Sentinel*` IAM roles, `sentinel-fraud` ECR repo (rename per deployment).

## Things to confirm before customizing

- What's your application data schema, and which fields carry fraud signal?
- What's the risk appetite — where should APPROVE/FLAG/DECLINE cutoffs sit, and are equal agent weights right for this product?
- Is this decision-support only, or does you want any automated action (and is that acceptable to your risk/compliance team)?
- What datastore and retention does production need (the reference is in-memory)?
- Which model tier fits your latency vs. accuracy needs?

## When to flag back mid-build

- You want autonomous funding decisions (out of scope — escalate).
- Application data is unavailable or too sparse to feed the agents meaningfully.
- You need persistence, audit retention, or PII handling beyond the reference's in-memory demo store.
- Bedrock model access for the chosen tier isn't enabled in your account/region.

## Done definition

- Four agents run sequentially with shared context; each returns valid `AgentResult` JSON or falls back to heuristics.
- Orchestrator produces a deterministic score + APPROVE/FLAG/DECLINE + confidence + narrative + top risk factors + per-dimension contributions.
- Mock mode runs with zero AWS creds; live mode invokes Bedrock and falls back cleanly on failure.
- Acceptance tests in [`build-spec/acceptance-tests.md`](build-spec/acceptance-tests.md) pass.
- Deployed to your account on App Runner with a least-privilege Bedrock instance role; `/api/health` returns ok.
