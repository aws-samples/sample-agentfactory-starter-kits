# ROI Framework — TriageAI Patient Triage

> The numbers here are **templates and illustrative examples** — real figures come from your own discovery, not from this doc.

## What problem this solves

Front-door patient triage is human-paced and uneven. A nurse or intake staffer reads each symptom description, decides how urgent it is, and routes it to a department — case by case, all day. That creates three costs at once: **nurse time** spent triaging routine cases, **delay** in surfacing the genuinely critical patient when the queue backs up, and **mis-routing** (especially over-routing to the ED) that drives avoidable cost and patient wait times. Triage quality also varies between staff and across shifts, which clinical leadership can't easily audit.

TriageAI puts a consistent, explainable first-pass between the intake form and the nurse. The model classifies urgency, recommends a department, lists red flags, and asks the clarifying questions a clinician would — in seconds, with the reasoning attached. Critical cases sort to the top of the staff queue automatically; routine ones arrive pre-classified for a fast confirm. The nurse still owns every decision, but spends their time confirming and handling exceptions instead of triaging from scratch.

## ROI math (researched, illustrative)

The numbers below are **research-backed and illustrative — not a guarantee.** Savings are anchored to a single, defensible lever (triage-nurse time) using public sources; throughput / ED-diversion benefits are real but more variable, so they are treated as upside, not headline savings. Run the formulas with your real inputs in discovery.

**Inputs (illustrative, with sources):**

| Input | Symbol | Value used | Basis |
|---|---|---|---|
| Patient intakes / day | `I` | 600 | Illustrative busy ED / urgent-care network (kit targets "hundreds+/day") |
| Operating days / year | `D` | 365 | ED runs continuously |
| Nurse minutes per triage today | `m` | 2 min | Median ED triage **1.9 min** (IQR 1.1–3.7), n=382,027 — J Emerg Nurs 2025 (PMID 40387689); rounded up |
| Triage-time reduction from pre-classified intake | `Δt` | 30–40% | Illustrative — model pre-classifies urgency + drafts routing; nurse confirms instead of triaging from scratch. **Validate with your own numbers.** |
| Fully-loaded triage-nurse cost / hour | `c` | $76.80 | BLS: employer compensation cost for RNs in health care = **$76.80/hr worked** (Dec 2024) |

**Output formulas:**

```
Triage minutes / year today  = I × D × m
Nurse hours / year today     = (I × D × m) / 60
Nurse time saved / year ($)  = Nurse hours/yr × Δt × c
```

**Worked example (Illustrative, research-backed — not a guarantee):**

```
Triage minutes/yr today  = 600 × 365 × 2            = 438,000 min/yr  (= 7,300 hrs/yr)
Nurse time saved/yr @30%  = 7,300 × 0.30 × $76.80    ≈ $168,000/yr
Nurse time saved/yr @40%  = 7,300 × 0.40 × $76.80    ≈ $224,000/yr
=> Illustrative nurse-time floor  ≈ $170K–$225K/yr
```

**Throughput / diversion upside (not in the headline figure — more variable, validate clinically):**
- Time-to-first-routing drops from a queued manual triage step (US ED median wait **17–31 min**, national throughput study 2006–2016) to a recommendation returned in seconds on form submission.
- **More than half of US ED visits are non-urgent** (NHAMCS-based studies). Surfacing those for safe routing away from the ED queue is where additional cost-avoidance lives — but the realized diversion rate and per-diversion cost are deployment- and clinically-specific, so we do **not** bank them in the headline savings. The nurse-time floor is the defensible number; diversion is the upside to size in discovery with clinical sign-off.

## Cost (computed from AWS pricing)

**Per-intake Bedrock cost — Claude 3.5 Haiku ($0.80 / 1M input, $4.00 / 1M output):**

```
Assumed tokens/call: ~1,500 input (clinical prompt + intake form) + ~1,000 output (urgency, dept, reasoning, red flags, follow-ups)
Input cost  = 1,500 / 1,000,000 × $0.80  = $0.0012
Output cost = 1,000 / 1,000,000 × $4.00  = $0.0040
Per intake  ≈ $0.0052  (+ ~5% for the one schema-retry ≈ $0.0055)
```

**Annual cost at 600 intakes/day (219,000/yr):**

| Driver | Annual | Notes |
|---|---|---|
| Bedrock (Claude 3.5 Haiku) | ~$1,200 | 219,000 × ~$0.0055/intake |
| Compute hosting (FastAPI + React) | ~$300–600 | Small Fargate task / App Runner light tier |
| CloudWatch | ~$100–300 | Logs + retention |
| IAM | $0 | Least-privilege `bedrock:InvokeModel` — no runtime cost |
| OpenSearch / vector DB | $0 | **Not used** — in-memory store, no KB; no OCU floor |
| **Total** | **~$1,500–$2,000/yr** | Dominated by nothing — Haiku + Bedrock-only keeps it tiny |

**Multiple:** ~$170K–$225K savings ÷ ~$1,500–$2,000 cost ≈ **85×–150× on the nurse-time floor alone.** The multiple is large precisely because this is a lean kit — a cheap Haiku tier, Bedrock-only, with no vector-DB fixed floor. Be honest in the room: the headline dollar saving is moderate (one automated step in a short triage), and a large share of the real value is **speed and queue throughput** (critical cases surfaced first), which is harder to put a single dollar on.


## Common objections + responses

- **"Will it make clinical decisions on its own?"** No. It produces a recommendation; the case routes into a staff queue and a clinician confirms or overrides. The human owns every decision — that's intentional and a compliance asset.
- **"Is this a regulated medical device?"** It's decision-support, not a diagnostic device. Clinical validation and regulatory classification are your responsibility; position it inside your existing clinical-governance process.
- **"What about patient privacy / PHI?"** Name and email are excluded from the model prompt by construction; logs are PHI-redacted via an allowlist; traffic is TLS; the prototype store is scrubbed on shutdown. Production PHI handling (encrypted persistence, retention) is part of the build.
- **"What if Bedrock is down or slow?"** A deterministic safe-default fallback routes the case (Primary Care, medium urgency) and flags it for manual review — the queue never stalls and staff always know which cases bypassed the model.
- **"How do we trust the model's output?"** It can only return four urgency levels and four departments; every response is schema-validated and ships with a plain-language reasoning string and red-flag list a clinician reviews. Invalid output is retried once, then falls back.
- **"We need this on our data / in our region."** It's single-tenant in your account and region; the only outbound call is the in-region Bedrock invocation.
- **"How long until we see it on our intake form?"** A focused engagement (16–24 engineering hrs over ~1–1.5 weeks) gets a customized instance running on your intake schema and department taxonomy.

## Time-to-value benchmarks

| Milestone | Target |
|---|---|
| Local demo on your sample intakes (incl. critical-case + fallback walkthrough) | Day 1–2 |
| Triage prompt, urgency/department taxonomy, and intake schema customized | Day 3–5 |
| Deployed to your environment with a least-privilege Bedrock policy | Day 5–6 |
| Acceptance tests passed + triage-team walkthrough of reasoning/red-flag explainability | Day 6–8 |

## Differentiation vs. competitors

- **Legacy clinical decision-support / protocol tools (e.g. Schmitt-Thompson protocol triage, vendor symptom-checkers):** strong on validated protocols but rigid, often opaque to the patient's free-text story, and expensive to adapt. TriageAI reads the narrative and attaches reasoning; position it as a fast, adaptable first pass alongside your clinical protocols, not a replacement for them.
- **Black-box ML acuity scores:** a single number with no explanation. TriageAI's constrained taxonomy + plain-language reasoning + red-flag list win when clinical staff and leadership need defensible, reviewable routing.
- **Generic LLM chatbots:** unconstrained output, no schema validation, no fallback, no PHI discipline. TriageAI's enum-constrained schema-validated output, deterministic fallback, and PHI-out-of-prompt design are the differentiators.
- **When this kit is NOT the answer:** you want fully autonomous clinical decisioning, have no structured intake step, need a validated regulated medical device out of the box, or can't use Bedrock in any region. Disqualify early (see `kit.json`).

## Sources

All numbers above are illustrative and research-backed. Savings are anchored to public sources; cost is computed from AWS published pricing. Validate every figure per deployment.

- **ED triage time per case — median 1.9 min (IQR 1.1–3.7), n=382,027 triage events.** Zaboli et al., *J Emerg Nurs* 2025 (PMID 40387689). Backs the `m` = ~2 min per-triage assumption. https://pubmed.ncbi.nlm.nih.gov/40387689/
- **Fully-loaded RN cost — $76.80/hr employer compensation (health care & social assistance, Dec 2024).** U.S. Bureau of Labor Statistics, "Charting compensation costs during National Nurses Month." Backs the `c` = $76.80/hr loaded-cost input. https://www.bls.gov/opub/ted/2025/charting-compensation-costs-during-national-nurses-month.htm
- **RN median annual wage — $93,600 (May 2024).** U.S. Bureau of Labor Statistics, Occupational Outlook Handbook, Registered Nurses (SOC 29-1141). Corroborating wage reference. https://www.bls.gov/ooh/healthcare/Print/registered-nurses.htm
- **ED throughput — US median wait time 17–31 min, LWBS 1.1–2.0% (2006–2016).** "United States' Performance on Emergency Department Throughput, 2006 to 2016" (PMID 33865616). Backs the time-to-first-routing / throughput framing. https://pubmed.ncbi.nlm.nih.gov/33865616/
- **Non-urgent ED share — more than half of ED visits non-urgent.** National Study of Non-urgent Emergency Department Visits (PMID 24381681). Backs the ">50% non-urgent" diversion-upside framing (upside only, not banked). https://pubmed.ncbi.nlm.nih.gov/24381681/
- **AWS Bedrock pricing — Claude 3.5 Haiku $0.80/1M input, $4.00/1M output.** Backs the per-intake and annual Bedrock cost computation. https://aws.amazon.com/bedrock/pricing/

> Note on method: triage-nurse time is the **defensible floor**. ED-diversion cost-avoidance is real and often larger, but the realized diversion rate and per-diversion cost are deployment- and clinically-specific — size them in discovery with clinical sign-off rather than committing to them here.
