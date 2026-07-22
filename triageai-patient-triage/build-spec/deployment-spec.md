# Deployment Spec — TriageAI Patient Triage

> Audience: a coding agent provisioning resources in your account.

## Deployment context

- **Account:** your own AWS account (single-tenant).
- **Region:** `us-east-1` by default; confirm Bedrock model access for Claude 3.5 Haiku in the chosen region.
- **Trust boundary:** everything runs in your account; the only outbound dependency is the in-region Bedrock model invocation.
- **Source code location:** not included in this kit — the kit folder holds metadata + specs only. The implementation is built from this spec and lives in your own repository.
- **Delivery unit:** a FastAPI backend (`:8443`, TLS) + a built React/Vite SPA (`:5173` in dev). The reference is **local-only**; productionizing — choosing a compute host, fronting with auth, adding a store — is your build.

## Deploy paths

The reference ships local-run tooling, not cloud IaC. The build adds the hosting.

| Asset | When | What it does |
|---|---|---|
| `backend/scripts/setup.sh` | Local stand-up | Creates the venv, installs deps, generates the self-signed TLS cert, copies `.env.example` → `.env` |
| `backend/scripts/bedrock-preflight.sh` | Before live runs | Verifies AWS creds + Bedrock model access (`bedrock:ListFoundationModels`) |
| `backend/scripts/generate-cert.sh` | Local TLS | Generates the self-signed cert for local HTTPS |
| `make dev` / `npm run dev` | Local run | Runs the backend (uvicorn + TLS) and the SPA |
| You build host | Production | Containerize/host the app, set env, attach the Bedrock instance role |

## Resources to create

- **Compute:** a host for the FastAPI + built SPA (a container service or small instance in your account; not prescribed by the reference). Single origin recommended for production.
- **AI/agent:** Bedrock model access for Claude 3.5 Haiku (`anthropic.claude-3-5-haiku-20241022-v1:0`) — no resource to create, but access must be enabled in-region.
- **Identity:** a least-privilege IAM role/policy granting `bedrock:InvokeModel` on the Claude family (template in `backend/README.md`), plus `bedrock:ListFoundationModels` if the preflight script is used.
- **Secrets:** `STAFF_PASSCODE` and `STAFF_SESSION_SECRET` (the app refuses to start without them) — store in your secret manager.
- **Storage (production):** a persistent, encrypted datastore to replace the in-memory repository (you add this — the reference is in-memory).
- **Observability:** CloudWatch for the structured JSON logs (retention/alarms are day-2).

## What you configure during the build

| Config item | Format | Source |
|---|---|---|
| Intake form schema | `TriageRequest` Pydantic model + `ALLOWED_DURATIONS` | `backend/src/triageai/domain/models.py` |
| Urgency / department taxonomy | Python enums | `backend/src/triageai/domain/enums.py` |
| Triage prompt + JSON contract | Python string constant | `backend/src/triageai/triage/prompt.py` |
| Safe-default fallback routing | Constants | `backend/src/triageai/triage/fallback.py` |
| Model id, region, timeout, retries, rate limits, CORS | Env vars | `backend/src/triageai/config.py` / `backend/.env.example` |
| PHI-redaction allowlist | Field set | `backend/src/triageai/logging/config.py` |
| Intake form UI | React component | `frontend/src/pages/IntakeForm.tsx` |

## What's pre-built

- The FastAPI backend (triage + staff + health routes), the `BedrockTriageEngine`, the deterministic fallback, and the React SPA.
- The middleware stack (security headers, body-size limit, request-id, CORS), slowapi rate limiting, and the passcode → signed-session-token staff auth.
- The PHI-redacting JSON logger and the in-memory case repository with urgency-sorted queue + scrub-on-shutdown.
- The setup / preflight / cert scripts and the least-privilege Bedrock IAM policy.
- The test suite (65 backend pytest + Hypothesis, 26 frontend vitest + fast-check) and the design documentation in `aidlc-docs/`.

## Cost expectations

| Driver | Typical range |
|---|---|
| Bedrock (Claude 3.5 Haiku) | One Converse call per intake (~1K output tokens) — scales linearly with volume; Haiku is a low-cost tier |
| Compute host | Low; scales with traffic |
| CloudWatch | Low (logs + retention) |
| IAM | None |
| Persistent store (production) | Depends on your environment |

## Pre-deployment checklist

- [ ] Bedrock access enabled for Claude 3.5 Haiku in the target region.
- [ ] AWS credentials/role configured with least-privilege `bedrock:InvokeModel`.
- [ ] Intake schema (`TriageRequest`) mapped to your form.
- [ ] Urgency/department taxonomy adapted to your service lines.
- [ ] Triage prompt + safe-default fallback tuned to your clinical model.
- [ ] `STAFF_PASSCODE` / `STAFF_SESSION_SECRET` set; TLS cert in place.
- [ ] Decision on production persistence and identity provider.

## Post-deployment validation

- [ ] `GET /healthz` returns ok.
- [ ] A sample intake returns a constrained, schema-valid triage result with reasoning + red flags.
- [ ] A critical-symptom case returns `critical` + ER routing and sorts to the top of the staff queue.
- [ ] A forced Bedrock failure routes via the safe-default and is tagged `ai_fallback`.
- [ ] Name/email appear in neither the prompt nor the logs.
- [ ] Staff routes reject missing/expired/invalid tokens; instance role confirmed least-privilege.

## Day-2 operations (yours to run)

- Add a persistent, encrypted datastore (reference is in-memory).
- Front staff routes with your identity provider.
- Set CloudWatch log retention + alarms (e.g. on rising fallback rate).
- Re-tune the prompt, taxonomy, and red-flag rules as clinical guidance evolves.
- Manage Bedrock spend vs. intake volume; revisit the model tier if accuracy needs change.
- Complete clinical validation and any regulatory sign-off before clinical use.
