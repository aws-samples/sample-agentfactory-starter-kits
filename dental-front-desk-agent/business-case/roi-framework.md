# ROI Framework — Dental Front-Desk Agent

> The numbers here are **templates and clearly-labeled illustrative examples** — real figures come from your own discovery, not from this doc. Do not commit to these numbers.

## What problem this solves

Dental front desks are interrupt-driven. Reception staff juggle in-office patients while routine calls pile up — book a cleaning, reschedule, "is my plan accepted?", "what's a crown copay?" — and after-hours calls go to voicemail or a paid answering service that can't actually book anything. The work is high-volume, repetitive, and policy-bound (office hours, accepted insurance, cancellation rules). That combination is the cost: **receptionist time** burned on routine calls, **in-office patients** waiting while staff are on the phone, and **lost bookings** from after-hours and overflow leakage.

This kit's thesis: a router + specialist agent absorbs the routine front-desk load — booking, reschedule/cancel, eligibility and coverage questions — while a built-in observability and evaluation pipeline makes that automation **auditable per practice** (quality scores, HIPAA-safe-language checks, hallucination rate) instead of an unmonitored chatbot. The desk gets time back for in-office patients, and overflow/after-hours calls get captured instead of lost.

## ROI math (template)

**Inputs to gather in discovery:**

| Input | Symbol | Example (ILLUSTRATIVE only) |
|---|---|---|
| Inbound front-desk calls / day / location | `C` | [N] |
| Share that are routine scheduling/insurance | `r` | [X%] |
| Average handle time per routine call | `m` | [N] min |
| Receptionist fully-loaded cost / hour | `w` | $[N] |
| Share of routine calls the agent handles end-to-end | `a` | [X%] |
| Working days / month | `d` | [N] |
| After-hours / overflow calls missed today / month | `M` | [N] |
| Share of missed calls the agent captures + books | `b` | [X%] |
| Average value of a booked appointment | `v` | $[N] |

**Output formulas:**

```
Routine calls deflected / month   = C × r × a × d
Receptionist hours saved / month  = (C × r × a × d) × (m / 60)
Staff time saved / month ($)      = receptionist hours saved × w
Bookings recovered / month        = M × b
Revenue recovered / month ($)     = (M × b) × v
Gross monthly benefit             = staff time saved + revenue recovered
Annual benefit                    = gross monthly benefit × 12
```

**Worked example (ILLUSTRATIVE, RESEARCH-BACKED — not a guarantee):**

Inputs below are conservative picks from public industry benchmarks (see **## Sources**). Every number is illustrative and must be re-derived from your own data.

```
Assume: C=80 calls/day        (50–80/day per patientxpress; 60–200 per oralhealthgroup — low end)
        r=60% routine          (twig.so: ~80% of front-desk calls are repetitive booking/insurance/reschedule — discounted to 60%)
        a=60% handled e2e       (oralhealthgroup: AI frees 30–50% of front-desk time — conservative)
        m=5 min/routine call
        w=$25/hr loaded         (BLS receptionist median $17.90/hr × ~1.4 load; dental median ~$28/hr per Princess Dental Staffing — BLS figure is the conservative floor)
        d=22 working days/mo  →  264 days/yr

STAFF TIME SAVED
Routine calls deflected/yr = 80 × 0.60 × 0.60 × 264        = ~7,603 calls/yr
Receptionist hrs saved/yr  = 7,603 × (5/60)                = ~634 hrs/yr   (~12 hrs/week)
Staff time saved/yr ($)    = 634 × $25                      = ~$15,840/yr   ← hard, defensible

REVENUE RECOVERED (loss-avoidance — softer; treat conservatively)
Total inbound calls/yr     = 80 × 264                       = 21,120 calls/yr
Calls missed today/yr      = 21,120 × 0.30 (30% miss rate)  = ~6,336 lost calls/yr
Bookings recaptured/yr     = 6,336 × 0.10 (conservative)    = ~634 bookings/yr
Revenue recovered/yr ($)   = 634 × $150 (conservative first-visit value, below the $250–$350 range, lifetime value ignored)
                                                            = ~$95,100/yr

ANNUAL BENEFIT / LOCATION    = $15,840 + $95,100            ≈ ~$110K/yr per location
```

Lead with the **~$16K staff time + ~12 hrs/week returned** (easy to defend); the **~$95K revenue recovered** is the softer figure but stays well below the $100K–$200K/yr missed-call loss that dentina.ai and oralhealthgroup independently report. For a DSO or platform vendor, multiply per-location benefit by the rollout footprint.

**Cost side (ILLUSTRATIVE — computed from AWS pricing):**

```
Agent conversations/yr     ≈ 7,603 routine + ~6,336 now-answered = ~14,000 conversations/yr

Per conversation (Bedrock pricing — https://aws.amazon.com/bedrock/pricing/):
  Claude Sonnet 4.5 router+specialist: ~4 LLM calls × ~3,750 in + ~375 out
    = ~15,000 input tok × $3/1M  = $0.045
    + ~1,500 output tok × $15/1M = $0.0225            → ~$0.0675
  Haiku 4.5 eval judge (1 pass, 100% sampling):
    ~4,000 in × $1/1M + ~500 out × $5/1M              → ~$0.0065
  Bedrock Guardrails (~10 text units/conv across content + grounding):
    10 × $0.15/1k + 10 × $0.10/1k                     → ~$0.0025
  Per-conversation total                              ≈ ~$0.077

Model + eval + Guardrails/yr = 14,000 × $0.077        ≈ ~$1,080/yr
AgentCore Runtime (consumption-based, session time)   ≈ ~$1,000/yr
Lambda + DynamoDB + AppSync + API GW + CloudFront/S3 + CloudWatch (OTEL/eval/dashboard)
                                                       ≈ ~$700–1,500/yr
NOTE: this kit uses NO OpenSearch Serverless or Knowledge Base, so it avoids the
      ~$350–700/mo OCU floor that dominates RAG-style kits.

ANNUAL AWS COST / LOCATION                             ≈ ~$4K/yr per location
```

**ROI multiple:** ~$110K ÷ ~$4K ≈ **~28x**, shown conservatively as **~20–35x** per location. Even the hard staff-time floor alone (~$16K ÷ ~$4K ≈ 4x) covers the run cost several times over before any revenue recovery.

## Cost drivers

| Driver | Notes | Scales with |
|---|---|---|
| Bedrock — Claude Sonnet 4.5 | Tokens per conversation across the router turn + any specialist turns. Multi-turn bookings cost more than a single eligibility question | Conversation volume × turns per conversation |
| Bedrock — Claude Haiku (evaluation judge) | One four-rubric scoring pass per interaction at 100% sampling; cheaper model by design | Interaction volume (sample rate is tunable) |
| Bedrock Guardrails | `ApplyGuardrail` per turn for grounding/hallucination checks | Conversation volume |
| AgentCore Runtime | Session/compute time for the deployed agent | Active conversation minutes |
| Lambda | Mock services, observability + evaluation processors, dashboard resolvers | Invocation volume |
| DynamoDB (`PAY_PER_REQUEST`) | Foundation, traces, metrics, evaluations, alerts tables | Read/write volume |
| AppSync + CloudFront + S3 | Dashboard GraphQL + static hosting | Practice-manager usage (low) |
| CloudWatch / EventBridge | OTEL spans, logs, daily reminder trigger | Trace volume |

Cost scales primarily with **conversation volume and turns per conversation**. Two levers control spend: lower the evaluation sampling rate below 100% once quality is trusted, and keep specialist delegations tight (one topic at a time, as the router prompt enforces).

## Common objections + responses

- **"We already have an IVR / phone tree."** A phone tree routes; it can't book, reschedule, or answer a coverage question. This agent completes the routine task end-to-end and hands off to a human when it can't — the IVR can sit in front of it.
- **"Will it give patients bad medical advice?"** No. The agent is front-desk only — the router prompt refuses diagnoses, treatment guidance, and outcome guarantees, and a Bedrock Guardrail backstops it. Anything clinical escalates to a human.
- **"Will it leak patient health information?"** HIPAA-safe language is enforced in every agent prompt (general terms, no unprompted clinical detail, no reading back sensitive info), and the Guardrail flags ungrounded or sensitive content. The dashboard surfaces a HIPAA-safe-language score per practice so you can verify it, not just trust it.
- **"How do we know it's actually doing a good job?"** Every interaction is scored on four rubrics (accuracy, HIPAA-safe language, empathy, policy adherence) by an LLM judge, with per-practice trends, transcripts, and threshold alerts. It's auditable, not a black box.
- **"What if it invents a coverage number?"** The insurance agent never states coverage without a tool call and always appends the disclaimer; the Guardrail's hallucination detection logs and can block ungrounded claims, and the hallucination rate is on the dashboard.
- **"We're a DSO with 40 locations — is this one-off per office?"** No. It's multi-tenant by `tenant_id` partition key: one agent pattern, per-practice hours/policies/accepted-plans config, and the dashboard scoped per location.
- **"Is our patient data safe?"** It deploys single-tenant in your own AWS account/region; nothing leaves your boundary except in-region Bedrock model calls. (Note: the reference ships on synthetic data and needs production hardening — auth, encryption review, retention, formal HIPAA review — before real PHI.)

## Time-to-value benchmarks

| Milestone | Target |
|---|---|
| Demo the full loop on the 5 seeded practices (mock services) | Day 1–2 |
| Prompts + policies + accepted-plan list tuned to you | Day 2–4 |
| Specialist tools repointed to real scheduling/insurance (or seeded) | Day 4–6 |
| Deployed to your account; rubrics + alert thresholds tuned | Day 6–8 |
| Acceptance tests passed + practice-manager dashboard walkthrough | Day 8–9 |

## Differentiation vs. competitors

- **Dental answering services / call centers:** capture messages but can't book, reschedule, or answer coverage questions, and offer no quality telemetry. This agent completes the task and gives the practice manager auditable quality scores.
- **Generic voice/IVR phone trees:** menu routing only. The router + specialist pattern actually resolves the request and escalates intelligently.
- **Off-the-shelf dental front-desk SaaS bots:** typically a single closed chatbot with no per-interaction quality scoring, no HIPAA-safe-language audit, and no multi-tenant model for DSOs. This kit ships the observability + four-rubric evaluation pipeline and a per-practice dashboard as first-class parts.
- **A generic LLM "answer patient questions" prompt:** one prompt, no tool-grounded booking, no disclaimer enforcement, no escalation, no evaluation. The separation into router + scheduling + insurance specialists plus the eval/alert loop is the differentiator.
- **When this kit is NOT the answer:** you want clinical advice from the agent, need day-one HIPAA certification, have no structured practice data and won't integrate a real system, or expects fully autonomous handling of disputes/complaints. Disqualify early (see `kit.json`).

## Sources

All savings inputs are conservative picks from the public benchmarks below; cost inputs are computed from AWS published pricing. Numbers are **research-backed illustrative — not guarantees**. Validate every figure against your own data.

- **U.S. Bureau of Labor Statistics — Receptionists (OOH):** https://www.bls.gov/ooh/office-and-administrative-support/receptionists.htm — median receptionist wage **$17.90/hr (May 2024)**; used as the conservative base for the $25/hr loaded rate (×~1.4 for benefits/payroll/overhead).
- **Princess Dental Staffing — dental front-desk salary report (BLS-sourced):** https://www.princessdentalstaffing.com/front-desk-salaries-bloomington-in — dental-specific receptionist median **~$28/hr ($54K/yr)**; cross-check confirming the $25/hr loaded assumption is conservative.
- **twig.so — Dental Front Desk Automation:** https://www.twig.so/blog/dental-front-desk-automation — **~80% of front-desk calls are repetitive** (booking, pricing, insurance, reschedules); **100–300 calls/day** by practice size. Backs the routine-share `r` (discounted to 60%).
- **oralhealthgroup.com — AI-assisted scheduling efficiency:** https://www.oralhealthgroup.com/blogs/digital-workflow-optimization-how-ai-assisted-scheduling-improves-practice-efficiency-in-canadian-dental-clinics/ — **60–200 patient calls/day**, **20–38% of calls missed**, AI frees **30–50% of front-desk time** and recaptures **$50K–$200K/yr**. Backs volume, miss rate, and handled-share `a`.
- **patientxpress.us — How many calls does a dental office miss:** https://www.patientxpress.us/blog/how-many-calls-dental-office-miss-every-week — **50–80 calls/day**, **20–30% missed**. And after-hours = **20–35% of weekly volume**: https://www.patientxpress.us/blog/24-7-ai-receptionist-dental-offices . Backs the call-volume `C` and the after-hours/overflow framing.
- **dentina.ai — Revenue lost from missed calls:** https://dentina.ai/articles/revenue-lost-missed-calls-dental-practice/ — **32–38% of calls missed**, **$250–$350 first-visit revenue** per missed new-patient call, **$151K/yr** loss for a mid-size practice. Backs the miss rate and the (conservative, below-range $150) recovered-booking value.
- **Peerlogic — 4,280-call DSO case study:** https://www.peerlogic.com/post/peerlogic-dso-case-study — **38% of inbound calls unanswered**, **~78% of missed callers never leave a voicemail** (call a competitor instead), ~40% call-to-appointment conversion. Backs the missed-call and no-voicemail outcome claims.
- **mybcat.com — Revenue per call benchmark (2025):** https://mybcat.com/blog/benchmark-report-revenue-per-call-2025/ — dental practices average **~$47 revenue per call**; cross-check that the revenue-recovery estimate is conservative relative to per-call value.
- **AWS Bedrock pricing:** https://aws.amazon.com/bedrock/pricing/ — Claude Sonnet 4.5 ($3/1M in, $15/1M out), Claude Haiku 4.5 ($1/$5), and Bedrock Guardrails ($0.15/1k text units content filters, $0.10/1k grounding). Basis for the entire cost computation.

> Note: the missed-call/loss-avoidance figures above come from vendor and industry-analysis blogs (dentina.ai, peerlogic.com, oralhealthgroup.com, twig.so, patientxpress.us, mybcat.com), which have an interest in the problem being large. We therefore use the **low end** of every published range and ignore lifetime patient value entirely. The labor rate is anchored to **primary BLS data**. Re-validate all of it per deployment.
