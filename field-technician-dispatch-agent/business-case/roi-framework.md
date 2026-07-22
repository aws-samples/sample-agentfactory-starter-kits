# ROI Framework — Field Technician Dispatch Agent

> The numbers here are **templates and clearly-labeled illustrative examples** — real figures come from your own discovery, not from this doc. Do not commit to any number in this file.

## What problem this solves

Field-service dispatch is a constraint-matching problem most teams still solve by hand. To assign one work order, a dispatcher cross-references **who has the right skills and certifications**, **who's available today**, **who's closest to the job site**, and **how urgent the job is** — across an FSM/work-order system, a scheduling tool, an HR/skills record, and, often, the dispatcher's own memory of who's good at what. It's slow, it varies by which dispatcher is on shift, and on urgent jobs (a gas leak, a down commercial HVAC unit, an outage) the minutes spent finding the right person count directly against a response-time SLA.

This agent collapses that lookup into a single reasoned pass: it reads the work order, filters technicians on required skills and certifications, checks availability, computes travel time, confirms parts, and recommends a technician — streaming its reasoning so the dispatcher can see exactly why and override before confirming. The payoff is in two places at once: **dispatcher time** (less manual cross-referencing per assignment) and **SLA performance on urgent jobs** (the right qualified, nearby, available tech is identified fast and consistently, not just when the most experienced dispatcher is working).

## ROI math (template)

**Inputs to gather in discovery:**

| Input | Symbol | Example (illustrative) |
|---|---|---|
| Work orders dispatched / month | `W` | [N work orders/month] |
| Dispatcher minutes per assignment today | `m` | [N minutes] |
| Time-per-assignment reduction from agent-assisted matching | `Δt` | [X%] |
| Fully-loaded dispatcher cost / hour | `c` | [$/hr] |
| Share of work orders that are urgent / SLA-bound | `u` | [X%] |
| Urgent jobs that miss SLA today | `s` | [X% of urgent] |
| Cost of a missed-SLA urgent job (penalty, truck-roll, churn) | `p` | [$ per miss] |
| Reduction in SLA misses from faster, consistent matching | `Δs` | [X%] |

**Output formulas:**

```
Dispatch hours today / month     = W × (m / 60)
Dispatcher time saved / month $  = (W × (m / 60)) × Δt × c
Missed-SLA jobs today / month    = W × u × s
SLA-miss cost avoided / month $  = (W × u × s) × Δs × p
Gross monthly benefit            = dispatcher time saved + SLA-miss cost avoided
Annual benefit                   = gross monthly benefit × 12
```

**Worked example — ILLUSTRATIVE, RESEARCH-BACKED — NOT a guarantee.** Every number below is anchored to a public source cited in **## Sources** (or computed from AWS pricing); they show how the formulas combine for a mid-market field-service org. Replace every input with your own data before relying on it.

**Researched inputs (illustrative mid-market org):**

| Input | Value | Basis (see Sources) |
|---|---|---|
| Work orders dispatched / year (`W`) | 75,000 | ~300/day × ~250 working days — mid-market; kit's idealCustomer range is "dozens to thousands/day" |
| Dispatcher minutes per assignment today (`m`) | ~5 min | Derived: ~15 hrs/wk manual scheduling per 8-tech shop ÷ ~200 work orders/wk (8 techs × ~5 jobs/day × 5 days) — Field Promax + FieldProxy benchmark |
| Time-per-assignment reduction (`Δt`) | ~40% | Conservative — agent does the multi-system lookup in one pass (internal estimate; flag as illustrative) |
| Fully-loaded dispatcher cost / hour (`c`) | ~$33/hr | BLS/O*NET 43-5032 mean $23.50/hr × 1.4 burden multiplier |
| Avoidable-dispatch / wrong-tech truck rolls eliminated | 2% of `W` = 1,500/yr | Conservative slice of the ~12–15% avoidable-dispatch rate (Aquant); top performers run ~3% |
| Cost of an avoidable truck roll (`p`) | ~$250 | Conservative end — S&C Electric utility baseline $150–500; Aberdeen direct $200–300 (TSIA fully-loaded is $1,000+) |

**Stream 1 — dispatcher time saved (lead figure, cleanest):**

```
Dispatch minutes saved / yr   = W × m × Δt          = 75,000 × 5 min × 40%   = 150,000 min
                                                     = 150,000 / 60          = 2,500 hrs/yr
Dispatcher time saved / yr $  = 2,500 hrs × $33/hr                           ≈ $82,500/yr
```

**Stream 2 — avoided wrong-tech / repeat truck rolls (conservative loss-avoidance, the more variable number):**

```
Avoided truck rolls / yr      = W × 2%             = 75,000 × 0.02           = 1,500 rolls/yr
SLA/repeat-visit cost avoided = 1,500 × $250                                 = $375,000/yr
```

**Gross annual benefit:**

```
Annual benefit ≈ $82,500 (dispatcher time) + $375,000 (avoided truck rolls) ≈ $457,500/yr  →  ~$0.46M/yr
```

**Cost side — Bedrock only (local FastAPI demo, no OpenSearch / KB / Guardrails):**

```
Per dispatch (one ReAct loop, ~6 model turns: lookup → search → availability → travel → parts → dispatch):
  assume ~30,000 cumulative input tokens (system prompt + 7 tool schemas re-sent each turn + growing tool results)
  assume ~4,000 output tokens (streamed reasoning across turns + final summary)
  input  cost = 30,000 / 1,000,000 × $3.00  = $0.090
  output cost =  4,000 / 1,000,000 × $15.00 = $0.060
  per-dispatch cost                          ≈ $0.15

Annual Bedrock cost = 75,000 dispatches × $0.15 ≈ $11,250/yr  →  ~$11K/yr
(Local FastAPI host adds negligible compute; if hosted on App Runner, ~$60–300/yr.)
```

**ROI multiple:**

```
Blended:                $457,500 / $11,250 ≈ 41x   → ~30–55x across token/volume variability
Dispatcher time only:    $82,500 / $11,250 ≈ 7.3x  → ~8x  (conservative floor — lead with this)
```

Run the same formulas with your real inputs. Treat **truck-roll cost avoided** conservatively — it's the harder number to defend and the more variable one (it dominates the blended figure here). Dispatcher-time savings is the cleaner, more credible figure to lead with, and on its own it still clears ~8x.

## Cost drivers

| Driver | Notes | Typical range |
|---|---|---|
| Bedrock (Claude Sonnet 4) | One ReAct loop per dispatch spans **several tool-calling turns** (lookup → search → availability → travel → parts → dispatch), so a single dispatch is multiple model invocations, not one. Scales with work-order volume and how many tool turns each decision takes | Model from token sizes × turns × volume |
| Compute host (FastAPI backend) | You choose the runtime (container service, VM, serverless behind an adapter). Billed for compute time | Depends on host + traffic |
| Routing / traffic API | Only if you replace the Haversine + 35 mph stub in `calculate_travel_time` with a real provider | Per-request, vendor-priced |
| Logging / observability | You add (e.g. CloudWatch) around the agent run | Low |
| Notification / FSM integration | Cost of your own SMS/push/FSM write when `dispatch_technician` is wired to real systems | Yours |

Bedrock cost scales primarily with **work-order volume × tool turns per dispatch**. Tightening the system prompt so the agent doesn't make redundant tool calls is the main lever to control spend.

## Common objections + responses

- **"We already have an FSM / scheduling system."** This doesn't replace it — it adds the reasoning layer the FSM lacks. The FSM holds the work orders and technician records; the agent reads them through its tools and recommends the assignment the FSM can't reason about on its own.
- **"Will it dispatch the wrong tech and blow an SLA?"** It recommends; a dispatcher confirms. Required skills and certifications are a **hard filter** — an unqualified technician is never a valid recommendation — and the agent streams its reasoning (distance, availability, why this tech) so the dispatcher can override before anything is finalized.
- **"Is this a black box?"** No. Every reasoning step and tool call streams to the dispatcher in real time, and the final dispatch records the technician, the distance, the availability, and a plain-language reason. It's more transparent than tribal-knowledge dispatching.
- **"The travel times won't be accurate."** The reference uses straight-line distance and a fixed 35 mph as a deliberate stub. For production you point `calculate_travel_time` at a real routing/traffic API — the agent's logic doesn't change, only the ETA source.
- **"Our techs and jobs aren't in clean data."** Then this is premature. The agent's tools need structured technician data (skills, certifications, location, schedule) and work-order data to reason over. If that doesn't exist, the first project is the data, not the agent (a disqualifier in `kit.json`).
- **"Isn't this just route optimization?"** No — it matches one qualified, available, nearby technician to a job. If the real problem is multi-stop routing across a day's jobs, a VRP solver fits better; this agent is about skill/availability/proximity matching with a human in the loop.
- **"How long until we see it on our data?"** A focused build ([16–24 hours of effort] over roughly [5–8 days]) gets a customized agent running against your work-order and technician data, with the dispatch policy tuned to your operation.

## Time-to-value benchmarks

| Milestone | Target |
|---|---|
| Local demo on the bundled DFW dataset (mock mode) | Day 1 |
| System prompt + tool filters tuned to your trades and urgency tiers | Day 2–4 |
| Tools repointed to your real systems (work orders, skills, schedules) | Day 4–6 |
| Travel-time + dispatch integrations wired; acceptance tests + dispatcher walkthrough | Day 6–8 |

## Differentiation vs. competitors

- **FSM platforms with scheduling modules (ServiceTitan, Salesforce Field Service, IFS, Microsoft Dynamics 365 Field Service):** strong at storing work orders, schedules, and dispatch boards; your auto-assign is typically rules- or capacity-based, not reasoning that *explains* a skill/proximity/urgency trade-off in plain language. Treat this agent as a reasoning + explainability layer on top of the system of record, not a rip-and-replace.
- **Manual / tribal-knowledge dispatching:** consistent only when the best dispatcher is on shift. The agent applies the same priority logic on every order and shows its work, so quality doesn't depend on who's working.
- **Pure route-optimization / VRP solvers (e.g. OR-Tools-based tooling):** optimize multi-stop routes given assignments, but don't reason about *which qualified technician* to assign or explain the choice. Different problem — and a disqualifier if routing is the real need.
- **Generic LLM chat over a spreadsheet of techs:** one prompt, no structured tools, no hard skill/cert filter, no streamed step-by-step reasoning. This kit's seven purpose-built tools and explicit priority logic are the differentiator.
- **When this kit is NOT the answer:** you want fully autonomous dispatch with no dispatcher in the loop, have no structured technician data, need strict on-prem with no Bedrock access, or the core problem is route optimization. Rule this kit out early (see `kit.json`).

## Sources

All figures in the worked example above are illustrative and research-backed. Each external source below was retrieved and confirmed; the cost side is computed from AWS public pricing. Replace with your own data before relying on them.

- **Dispatcher wage — $23.50/hr mean ($48,880/yr), SOC 43-5032 "Dispatchers, Except Police, Fire, and Ambulance"** (U.S. BLS OES data, via O*NET OnLine): https://www.onetonline.org/link/localwages/43-5032.00 — backs the ~$33/hr fully-loaded rate (base $23.50 × 1.4 burden multiplier). Cross-checked against DataUSA's BLS-sourced $51,487/yr: https://www.datausa.io/profile/soc/dispatchers-except-police-fire-and-ambulance
- **Dispatcher manual-scheduling time — ~15 hrs/week per 8-tech operation; also first-time-fix ~72–75%, manual scheduling overhead ~$4,800/employee/yr** (Field Promax): https://www.fieldpromax.com/blog/10-field-service-scheduling-mistakes — backs the ~5 min/order baseline and the "skill match before availability" / "check parts before dispatch" value drivers.
- **Avoidable-dispatch rate — ~12–15% industry average vs ~3% top performers; unnecessary truck rolls ~14% average** (Aquant benchmarks, cited in the Field Promax benchmark table above) — backs the conservative 2%-of-volume truck-roll-avoidance slice.
- **Truck-roll cost — $150–$1,000+ per roll (TSIA fully-loaded $1,000+; Aberdeen direct $200–300; S&C Electric utility baseline $150–500); ~17–25% of rolls are "No Fault Found," first-time fix ~75%** (DPS Telecom, aggregating TSIA / Aberdeen / S&C / nClarity): https://dpstele.com/blog/how-to-choose-monitoring-solution-reduce-truck-rolls.php — backs the conservative ~$250/roll cost. Utility-specific baseline confirmed at S&C Electric: https://www.sandc.com/en/gridtalk/2017/march/20/the-real-cost-of-a-truck-roll/
- **Technicians complete ~3–6 jobs/day** (truck-roll benchmark, AEX): https://aexinc.com/blog/truck-roll-cost-benchmarks-fiber — used to derive ~200 work orders/week for an 8-tech shop (≈5 min/order).
- **Bedrock token pricing — Claude Sonnet 4 at $3.00/1M input, $15.00/1M output tokens** (AWS): https://aws.amazon.com/bedrock/pricing/ — basis for the ~$0.15/dispatch and ~$11K/yr cost figures.

**Internal estimates (no public source — flagged as illustrative):** the ~40% time-per-assignment reduction and the 2%-of-volume truck-roll-avoidance share are conservative working assumptions, not vendor-published figures; validate both with your own baseline.
