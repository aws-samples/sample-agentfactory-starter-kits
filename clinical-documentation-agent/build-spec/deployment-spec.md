# Deployment Spec — Clinical Documentation Agent

> Audience: a coding agent provisioning resources. Two deployment modes are described: the **prototype** (local, no AWS) and the **target** (hybrid Amazon Connect Health + Bedrock AgentCore in your account). Build the prototype first, then deploy the target.

## Deployment context

- **Account:** your AWS account. Single tenant. All PHI stays inside it under your BAA.
- **Region:** `us-west-2` default (Connect Health availability). Any region where Connect Health, Bedrock (Claude Sonnet 4.5), and AgentCore are available works.
- **Trust boundary:** clinic audio enters via Connect Health after patient consent; the EHR adapter is the only component that writes outside AWS. The clinician UI sits inside your existing authenticated web tier or EHR front end.
- **Source code:** built from this spec in your own repository; the kit folder holds only metadata.
- **Prototype runtime:** Python 3.12, `pip install -r requirements.txt` (fastapi, uvicorn, pydantic, pytest, hypothesis, httpx), `python run.py` → `http://127.0.0.1:8080`. No environment variables, no credentials.

## Resources to create (target)

**Transcription and base note**
- Amazon Connect Health domain and ambient-documentation subscription — Psychiatry specialty, dual-channel audio, a clinical note template matching your primary BH template.
- Patient-consent capture integrated into your scheduling or check-in flow (you own this; Connect Health requires it).

**AI / agent layer**
- Bedrock model access: `anthropic.claude-sonnet-4-5-20250929-v1:0`; optionally a Haiku-class model for the QA tier.
- Bedrock AgentCore runtime hosting four Strands agents: `context` (U1), `note` (U3), `coding` (U4), `qa` (U5). U2 becomes an S3 reader of Connect Health outputs.
- AgentCore Memory store for per-patient context (treatment goals, previous-session summary, homework, PHQ-9/GAD-7 trends, authorized-session count).
- Prompt caching enabled on the static template + rules prefix for each agent.

**Storage**
- S3 bucket for Connect Health outputs (transcript, clinical documentation + evidence mapping, after-visit summary) — SSE-KMS, versioning, lifecycle per retention policy.
- S3 bucket (or prefix) for pipeline audit events — same encryption and retention.
- Amazon HealthLake FHIR R4 datastore **or** credentials for your EHR write API (one of the two).

**Compute for API + orchestrator**
- The FastAPI service and orchestrator run as a container (ECS Fargate or your existing platform) **or** are folded into an AgentCore-hosted orchestrator agent. The kit does not prescribe this; the API contract is what matters.

**Identity**
- IAM role for AgentCore agents: `bedrock:InvokeModel*` on the chosen model IDs, read on the Connect Health output bucket, read/write on the audit bucket, AgentCore Memory read/write, HealthLake read/write (if used).
- IAM role for the Connect Health subscription to write to its output bucket.
- Secrets Manager entry for the EHR API credential (if a direct API is used); fetched at request time, never baked into images.
- Authentication on the FastAPI routes (the prototype has none): your SSO/IdP via your web tier.

**Observability**
- CloudWatch Logs for AgentCore, the API, and audit mirror; retention per policy.
- CloudWatch dashboard: sessions/day, QA FAIL rate by check, sign-off latency, Bedrock tokens/session, Connect Health sessions.
- Alarms: QA FAIL rate spike, sign-off 422 rate, Bedrock throttling, EHR write failures.

## What you configure during the build

| Configuration item | Format | Source |
|---|---|---|
| AWS region | string | Your choice; `us-west-2` default |
| Bedrock model ID (primary) | string | Default `anthropic.claude-sonnet-4-5-20250929-v1:0` |
| Bedrock model ID (QA tier) | string, optional | Haiku-class; your cost decision |
| Connect Health specialty + note template | Connect Health config | Psychiatry; mapped to your primary template |
| Note templates and required sections | `TEMPLATE_SECTIONS` dict | Your compliance officer |
| Session-type → template routing | `select_template` rules | Your clinical lead |
| CPT duration bands | `cpt_for_duration` | CPT standard unless payer contract differs |
| Credential sets | `PRESCRIBER_CREDENTIALS`, prescriber-only codes | Your payer contracts + licensure |
| Payer-specific add-ons / modifiers | `coding_agent.py` | RCM manager |
| QA check severity (FAIL vs WARN) | `qa_agent.py` | Compliance officer |
| Clinical vocabulary allowlist | `clinical_vocab` set | Clinical lead; grows over time |
| Auth-alert threshold | `sessions_remaining < N` | Default 3 |
| EHR adapter target | HealthLake datastore ID **or** EHR API endpoint + credential | Your engineering team |
| Audit retention | S3 lifecycle + CloudWatch retention (days) | Compliance; 7 years typical |
| Transcript size cap | `MAX_TRANSCRIPT_CHARS` | Default 20,000 |

## What the spec fully specifies (so you are not designing from scratch)

- Orchestrator with fixed U1→U5 order, per-stage audit events, and the QA-gated `write_back`.
- `AgentRunner` interface and `SimulatedAgentRunner` with all five deterministic handlers.
- FastAPI service: `GET /`, `GET /api/catalog`, `POST /api/sessions`, `POST /api/sessions/{sid}/run`, `GET /api/sessions/{sid}`, `POST /api/sessions/{sid}/signoff`, `GET /api/sessions/{sid}/audit`.
- Data model (`models.py`) with JSON serialization including computed QA properties.
- BH coding rules, seven QA checks, eight note templates.
- Clinician review UI (`web/index.html`).
- A test suite including Hypothesis property tests on the CPT bands.
- Three synthetic patients and transcripts covering the happy path, an auth alert + telehealth modifier, and a crisis session.
- Target architecture with Options A/B/C analysis and the Bedrock cost model (see `architecture-decisions.md` AD7–AD8).

## Cost expectations

| Driver | Typical range | Notes |
|---|---|---|
| Connect Health ambient documentation | Per session — confirm current pricing | Largest line in hybrid mode |
| Bedrock Claude Sonnet 4.5 (BH layer) | ~$0.04–0.15 / session | Source projection; caching is the main lever |
| Bedrock Haiku-class (QA tier) | Small fraction of Sonnet | Optional |
| AgentCore runtime + Memory | Low per session | |
| S3 (outputs + audit) | Negligible at <1M sessions/yr | Retention drives it |
| HealthLake | ~$0.27/GB-month + requests | Only if chosen over a direct EHR API |
| CloudWatch | Low | Dashboard + alarms + log retention |
| Container for API/orchestrator | ~$30–100/month Fargate | Or $0 if folded into AgentCore |

For a 100-clinician group at ~160K sessions/year the kit's ROI model estimates ~$45–130K/year all-in. Measure against pilot sessions before relying on it.

## Pre-deployment checklist

- [ ] BAA with AWS in place covering Connect Health, Bedrock, AgentCore, S3, HealthLake
- [ ] Bedrock model access granted for Claude Sonnet 4.5 (and QA-tier model) in the region
- [ ] Connect Health available in the region; Psychiatry specialty confirmed
- [ ] Patient-consent workflow for session recording approved by your compliance/legal team
- [ ] EHR write-back path decided (HealthLake vs. direct API) and credential provisioned in Secrets Manager
- [ ] KMS key created for S3 buckets; retention policy agreed with compliance
- [ ] Templates, credential matrix, and QA severities encoded; `pytest -q` green
- [ ] Security review complete per your policy
- [ ] Cost alerts configured in AWS Budgets
- [ ] Authentication strategy for the API/UI agreed with your web team

## Post-deployment validation

- [ ] Three synthetic transcripts run through `BedrockAgentRunner` with QA verdicts matching the simulation (CBT PASS; LCSW med-management credential FAIL; no-SI/HI risk FAIL)
- [ ] Transcript with SI/HI screening removed is blocked at `POST /signoff` with 422 in the deployed UI
- [ ] One consented real session: Connect Health outputs in S3 → pipeline → clinician sign-off → note and superbill visible in EHR/HealthLake
- [ ] Audit events for that session present in `GET /audit`, S3, and CloudWatch Logs
- [ ] CloudWatch dashboard populated; QA FAIL-rate alarm tested
- [ ] Bedrock spend per session recorded and compared to the ROI model
- [ ] `acceptance-tests.md` T1–T16 signed by your engineering lead; compliance officer present for T4–T7, T14

## Day-2 operations (you own this)

- Rule changes (templates, bands, credentials, QA severities) go through the repo with a test per change.
- Expand `clinical_vocab` as hallucination-check false positives are reviewed.
- Review QA FAIL distribution monthly — a high `risk_assessment` FAIL rate is a clinician-training signal.
- Rotate the EHR API credential per your policy.
- Monitor Bedrock model lifecycle announcements; Claude Sonnet 4.5 has a published EOL and the model ID is a single configuration value.
- Re-run the acceptance tests after any model, template, or payer-rule change.
