# ROI Framework — Clinical Documentation Agent

> Every number below is illustrative scaffolding. The Bedrock cost figures are **projections** from the design, not measured results. Your real numbers come from your own baseline measurement.

## What problem this solves

Behavioral-health clinicians document after the session, not during it. A 50-minute psychotherapy visit typically carries 15–20 minutes of note-writing, and for a clinician seeing six patients a day that is 1.5–2 hours of documentation — much of it after clinic hours. The practice pays for that time in burnout, turnover, and capped panel sizes.

The documentation also fails compliance and billing checks in predictable ways. Notes miss a documented SI/HI risk screening and the gap surfaces in a payer audit or, worse, a sentinel-event review. Psychotherapy CPT codes (90832/90834/90837) are time-banded and get denied when the documented duration does not support the code. Practices with mixed credentials occasionally bill E&M or pharmacologic-management codes under a clinician not licensed to bill them.

This kit attacks both: it drafts a template-complete, evidence-mapped, pre-coded note so the clinician reviews rather than writes, and it **refuses to let the note be signed** if a mandatory element is missing, the CPT code does not match the duration, or the credential cannot bill the code. The savings are clinician time; the risk reduction is fewer denials and fewer audit findings.

## ROI math (template)

### Inputs to gather

| Input | Where to get it | Typical range |
|---|---|---|
| Number of clinicians | Practice leadership | 25–2,000 |
| Sessions per clinician per day | Scheduling system | 5–8 |
| Clinic days per month | Practice leadership | 20–22 |
| Minutes per note today | Clinician survey or EHR timestamps (note-open to note-sign) | 12–25 |
| Clinician loaded cost per hour | Finance; blended across credentials | $80–140 |
| Current psychotherapy CPT denial rate for time/documentation | RCM / billing | 2–8% |
| Average reimbursement per BH session | RCM | $90–180 |
| Notes flagged in last compliance audit for missing risk screening | Compliance officer | 1–10% |
| Share of sessions via telehealth | Scheduling | 20–80% |

### Output formulas

```
Documentation hours saved per year
  = clinicians × sessions/day × clinic days/month × 12
    × (minutes per note today − target minutes per note) / 60

Documentation savings ($)
  = hours saved × clinician loaded cost/hour

Denial recovery ($)
  = sessions/year × current time-code denial rate × recovery share × avg reimbursement

Annual benefit (illustrative)
  = documentation savings + denial recovery
  (audit-finding avoidance is real but not usually monetized in the first model)

Annual run cost
  = Connect Health sessions + Bedrock tokens + AgentCore + S3 + CloudWatch
  (see cost drivers)

ROI multiple = annual benefit / (annual run cost + build cost)
```

### Worked example (illustrative, not a guarantee)

Outpatient BH group, 100 clinicians, 6 sessions/day, 22 clinic days/month:

```
Sessions per year:
  100 × 6 × 22 × 12 = 158,400 sessions

Documentation time today:
  158,400 × 18 min / 60 = 47,520 hours/year
  × $95/hour loaded = $4.5M/year

At a 15 → 5 min per note reduction (conservative vs. the design's <2 min target):
  158,400 × 10 min / 60 = 26,400 hours saved
  × $95 = ~$2.5M/year gross

Apply a 40% realization factor (clinicians reinvest, not all time is recovered):
  ~$1.0M/year documentation savings

Denial recovery:
  158,400 × 4% time-code denial rate × 50% recoverable × $120 = ~$380K/year

Annual benefit (illustrative): ~$1.2–1.4M

Build cost: ~2–4 weeks of engineering (rules, Bedrock runner, EHR adapter, consent flow)
Annual run cost: ~$45–130K
  (Connect Health per-session + Bedrock Claude Sonnet 4.5 w/ caching
   + AgentCore + S3 + CloudWatch — see cost drivers)

ROI multiple: ~8–20x first year (if numbers above hold)
```

**Use as a template, not as a guarantee.** The realization factor and the denial recovery share are the two inputs most likely to be wrong for a given organization; measure them before relying on the model.

### What the design projects for Bedrock cost

The reference design models a 2,000-provider pipeline at ~$0.15/session unoptimized → ~$0.04/session with prompt caching (60–70%), model tiering to Haiku for QA (40–50%), streaming, and AgentCore Memory reuse — a ~73% reduction. Those percentages are **projections** from the design, not benchmarked. Use them to frame the cost conversation, not as commitments.

## Cost drivers

| Driver | Typical range | Notes |
|---|---|---|
| Amazon Connect Health ambient documentation | Per session; confirm current pricing | Dominant cost in the hybrid design. HIPAA-eligible. Includes transcription, base note, evidence map, AVS. |
| Bedrock — Claude Sonnet 4.5 | $0.04–0.15 per session for the BH layer (source projection) | Caching the template + rules prefix is the single biggest lever. |
| Bedrock — Haiku-class for QA tier | Fraction of Sonnet | Optional; source projects 40–50% savings on the QA stage. |
| Bedrock AgentCore runtime + Memory | Low per-session | Memory holds per-patient context between sessions. |
| S3 | Negligible at this scale | Transcript, note, evidence map, AVS, audit per session. |
| HealthLake | ~$0.27/GB/month storage + per-request | Only if you choose a FHIR store over a direct EHR API. |
| CloudWatch | Low | Logs + a dashboard; retention drives cost. |

## Common questions + answers

| Question | Answer |
|---|---|
| "We already have an ambient scribe (Nuance DAX, Abridge, Suki, Nabla…)." | Those produce a note. This kit adds what BH compliance and billing need on top: a blocking SI/HI risk check, time-banded CPT validation, credential scope, and a sign-off gate. If you keep your scribe, the kit's U3–U5 layer can consume that scribe's transcript instead of Connect Health's. |
| "An AI writing the clinical note is a liability." | The clinician signs every note; nothing reaches the chart without that. Every sentence maps to a transcript utterance. And the QA agent is biased toward refusal — if the screening was not done, the note is blocked, not padded. |
| "What if it hallucinates a risk assessment?" | It is designed not to. The note agent leaves Risk Assessment empty when there is no screening in the transcript, and the QA agent fails the note. Test T4 in the acceptance tests demonstrates this with a hand-edited transcript. |
| "Our payer contracts have their own CPT rules." | The bands in `coding_agent.py` are standard CPT and are a customization point. Payer-specific add-ons, modifiers, and credential rules are configuration changes with tests. |
| "We're not sure we can record sessions." | Then start on typed or dictated transcripts, or with the scribe you already have. Connect Health requires consent; the kit does not help you get it. |
| "How is PHI handled?" | Connect Health and Bedrock are HIPAA-eligible under your BAA. The prototype itself contains no PHI — all patients are synthetic — and the production deployment is in your account. Nothing in the kit sends data to AWS outside your account. |
| "We tried an NLP coding tool and it over-coded." | This kit's CPT selection is rule-based on documented duration, not model-inferred complexity. The model writes the rationale; it cannot pick 90837 for a 40-minute session. |

## Time-to-value benchmarks

| Milestone | Target |
|---|---|
| Prototype running with your own template names | Day 1 |
| Coding and QA rules match your payer mix; tests green | Day 3 |
| `BedrockAgentRunner` running all five stages on synthetic transcripts | Day 5 |
| First real (consented) session through Connect Health → signed note in EHR | Day 7–10 |
| Pilot cohort (5–10 clinicians) measuring note-review time | Week 3–4 |
| Full acceptance tests signed by compliance | Week 4 |
| Measured ROI inputs (minutes per note, denial rate) at 90 days | Quarter 1 |

## Differentiation vs. competitors

| Alternative | When it wins | When this kit wins |
|---|---|---|
| **Nuance DAX / Abridge / Suki / Nabla** (general ambient scribes) | Multi-specialty health systems that want one scribe everywhere, with vendor-managed EHR integrations. | BH groups that need SI/HI, time-code, and credential checks enforced before sign-off, and want the rules in their own code rather than a vendor roadmap. The kit can also sit on top of these scribes' transcripts. |
| **Eleos / Lyssn** (BH-specific documentation and session analytics) | Organizations that want therapy-quality analytics (fidelity scoring) as much as documentation. | Organizations that want billing-grade coding with credential scope, a blocking QA gate, and an AWS-native stack they own. |
| **EHR-native AI notes** (e.g., vendor-bundled scribes) | Practices content with the EHR vendor's pace and defaults. | Practices whose EHR vendor's notes are not BH-aware or whose compliance team needs auditable, customizable checks. |
| **Amazon Connect Health alone** | Organizations that only need transcription + base note + AVS. | Organizations that also need the BH coding, credential, and QA layer — which is exactly what the kit adds. |
| **Keep writing notes manually** | Very small practices (<100 sessions/week). | Everyone above that threshold — see the worked example. |
