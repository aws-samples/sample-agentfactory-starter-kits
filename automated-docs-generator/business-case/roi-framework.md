# ROI Framework — Automated Docs Generator

> ROI scaffolding you fill in for your deployment. Fill the inputs in during discovery. The worked example below is **illustrative, not a commitment** — real numbers come from your own docs cadence and loaded rates.

## What problem this solves

End-user documentation for a web app decays continuously. Every release moves a button, renames a tab, or adds a screen, and the published guide drifts out of sync. Screenshots are the worst offenders — they're expensive to re-capture by hand and they visibly date a guide the moment the UI changes.

Today the work falls to a technical writer, a product manager, or an engineer "when there's time," which means it's usually behind. The cost shows up in three places: (1) the hours spent manually screenshotting and writing captions each release, (2) support and onboarding friction when customers follow stale instructions, and (3) the opportunity cost of skilled people doing screenshot busywork instead of higher-value content.

This kit turns the refresh into a triggered (or scheduled) pipeline: an AI browser agent re-walks the app, re-captures every screen, and drafts a description; a human reviews and edits; the guide regenerates. The human stays in the loop for quality, but the mechanical 80% is automated.

## ROI math (template)

### Inputs to gather

| Input | Symbol | How to get it |
|---|---|---|
| Documentation refreshes per year | `R` | Releases or scheduled refresh cadence (e.g., 12 monthly, 4 quarterly) |
| Hours per refresh today | `H` | Time a writer/engineer spends re-screenshotting + rewriting per refresh |
| Loaded hourly rate of that person | `W` | Fully-loaded cost/hour (writer ~$60–90; engineer ~$90–140) |
| Residual review hours per refresh with the kit | `H_r` | Time to review/edit AI drafts (typically a fraction of `H`) |
| Stale-docs support tickets/year attributable to bad docs | `T` | From the support system, if tracked |
| Avg. cost to resolve one such ticket | `C_t` | Loaded support cost per ticket |

### Output formulas

```
Labor saved per refresh   = (H − H_r) × W
Annual labor savings      = R × (H − H_r) × W
Annual support savings    = T × C_t × [fraction attributable to stale docs]
Annual gross savings      = Annual labor savings + Annual support savings
Annual AWS cost           = ~$40–50/mo base + (R × per-run cost ~$6–14)
Net annual savings        = Annual gross savings − Annual AWS cost
Return on AWS spend        = Annual gross savings ÷ Annual AWS cost
```

### Worked example (illustrative — not a guarantee)

A mid-market SaaS team refreshes its end-user guide monthly (`R = 12`). Each refresh takes a writer `H = 16` hours of screenshotting + rewriting at `W = $75/hr` loaded. With the kit, review/edit drops to `H_r = 4` hours.

```
Labor saved per refresh = (16 − 4) × $75              = $900
Annual labor savings    = 12 × $900                   = $10,800
Annual AWS cost         = ~$50/mo × 12 + 12 × ~$10     ≈ $720
Net annual savings      ≈ $10,800 − $720              ≈ $10,080
Return on AWS spend     ≈ $10,800 ÷ $720              ≈ ~15x
```

This excludes support-deflection and onboarding-speed benefits, which can dwarf the labor line for high-traffic products. Scale `R` and `H` up for teams documenting multiple apps or larger surfaces. **Validate every input with you.**

## Cost drivers

| AWS service | Typical range | Notes |
|---|---|---|
| NAT Gateway | ~$32/month | The dominant fixed cost (1 NAT in the VPC). VPC endpoints or a NAT instance can reduce it. |
| ECS Fargate (screenshot job) | ~$2–4 per run | 4 GB / 2 vCPU for ~30–60 min |
| ECS Fargate (generate job) | ~$1–2 per run | 4 GB / 2 vCPU for ~5–10 min |
| Bedrock (Claude Sonnet 4.5) | ~$3–8 per run | ~50 screenshots' analysis + guide assembly |
| Amazon Nova Act | Variable (preview) | Preview pricing — confirm in your account |
| S3 | < $1/month | Screenshots + descriptions + guide HTML |
| DynamoDB | < $1/month | Pay-per-request, low volume |
| Lambda | < $1/month | Minimal invocations |
| CloudFront | < $1/month | Low-traffic management UI |

**Base total: ~$40–50/month** on a weekly schedule; per-run incremental ~$6–14. The fixed NAT cost dominates at low run volume, so heavier usage improves the per-guide economics.

## Common objections + responses

1. **"Won't an AI write inaccurate descriptions?"** — The kit is human-in-the-loop. Every AI description is editable in the review UI before the guide is generated, and you can replace any screenshot. The AI does the first draft; the human owns the publish.
2. **"Our app needs login / has sensitive data."** — The agent logs in with credentials you supply (passed at run time, never baked into images) and you scope the workflow to the screens you want documented. Keep it on non-production or on screens without real customer data.
3. **"Browser automation is flaky."** — Nova Act is an LLM-driven agent that takes natural-language instructions ("click the blue Save button top-right"), not brittle CSS selectors. The capture wrapper retries and fails gracefully, and partial runs still produce a usable guide.
4. **"We already have a docs tool."** — This doesn't replace your docs site or CMS; it produces an HTML guide (and the source screenshots/descriptions) you can publish wherever you already publish. It automates the capture-and-draft step that your tool doesn't.
5. **"What about Nova Act being in preview?"** — It requires preview access in your account and pricing is variable. We confirm access during the design session; if it's a blocker we flag it before building.
6. **"Why ECS Fargate and not Lambda?"** — A headless browser walking an app for 30–60 minutes and a Node-based CLI assembling HTML both exceed Lambda's limits. Fargate gives the memory and run-time headroom; the jobs scale and fail independently.
7. **"How do we keep it current?"** — Turn on the EventBridge schedule (e.g., weekly) so capture re-runs automatically; a human still reviews before the guide regenerates.

## Time-to-value benchmarks

| Milestone | Target |
|---|---|
| Discovery + design complete | Day 1–2 |
| Stack deployed in your account (`deploy.sh`) | Day 2–3 |
| First workflow steps written + first real capture run | Day 3–5 |
| First reviewed + generated guide | Day 5–6 |
| Schedule enabled + handoff | Day 6–8 |

## Differentiation vs. alternatives

- **Manual screenshotting + a doc editor (status quo):** the baseline this replaces. The kit removes the mechanical capture/draft labor and keeps screenshots fresh via re-runs.
- **Scribe / Tango (capture-as-you-click tools):** great for recording a human's clickthrough, but they need a person to drive every capture each time. This kit re-runs autonomously on a schedule and drafts descriptions with an LLM. Choose those when a human is already doing the clicks; choose this when you want unattended, repeatable refreshes.
- **Docusaurus / GitBook / Readme.com (docs platforms):** these host and publish docs but don't capture screenshots or write first drafts. Complementary — the kit feeds them content; it doesn't replace them.
- **Selenium/Playwright screenshot scripts (DIY):** brittle selector maintenance every time the UI changes. Nova Act's natural-language navigation is more resilient, and you get AI descriptions + guide assembly for free. Choose DIY only if the app is tiny and stable.
- **Outsourced tech writing:** higher quality narrative, far higher cost and latency per refresh. The kit gets the routine refresh done in-house; reserve outsourcing for flagship narrative docs.

When this kit is the wrong call: a single static page, a canvas/WebGL UI automation can't navigate, an app with no scripted login, or a hard rule against automated browsers near production.
