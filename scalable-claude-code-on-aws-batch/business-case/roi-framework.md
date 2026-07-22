# ROI Framework — Scalable Claude Code on AWS Batch

> The numbers here are **templates and illustrative examples** — real figures come from your own discovery and a pilot run, not from this doc.

## What problem this solves

Cross-cutting code work — migrating every service off a deprecated library, bumping a language/framework version fleet-wide, sweeping hundreds of repos for a security pattern, reviewing a backlog of PRs — scales linearly with engineer time. A senior engineer doing it by hand is slow, expensive, and inconsistent across repos. Coding agents can do the work, but running one against hundreds of repositories means solving the *infrastructure* problem: compute that auto-scales, concurrency control, model access without scattering API keys, hard spend caps, and structured output you can act on.

This kit makes that infrastructure a deployable pattern. AWS Batch fans the work out across Fargate/EC2 Spot compute; Bedrock supplies the model over IAM (no keys to manage or leak); a `--max-budget-usd` ceiling caps every job; and each job returns a JSON result plus a git patch in S3. The ROI comes from two places at once: **engineer-hours displaced** on repetitive cross-repo changes, and **campaigns that simply weren't feasible before** becoming a parametrized overnight run.

## ROI math (worked example — illustrative, research-backed, NOT a guarantee)

**Inputs (illustrative; sources in the Sources section below):**

| Input | Symbol | Illustrative value | Basis |
|---|---|---|---|
| Repos / modules in the estate | `R` | 1,000 | "Tens to thousands" per `idealCustomer`; conservative vs. JPMorgan Chase's 40,000+ Spring Boot apps [1] |
| Upgrade tasks per repo per year | `u` | 2.5 | JPMorgan Chase's published Spring Boot + Java LTS cadence [1] |
| Annual upgrade tasks | `R × u` | 2,500 | derived |
| Engineer-hours per task done manually | `h` | 2 hrs | **internal estimate** — routine cross-cutting bump touching one repo (no public source; validate with your own numbers) |
| Fully-loaded engineer cost / hour | `c` | $80 | BLS median software-developer wage $133,080 (May 2024) ÷ 2,080 hrs ≈ $64 × ~1.25 loading [2] |
| Human review/merge time per agent job | `hr` | 0.6 hr | **internal estimate** — ~70% of manual effort removed, human reviews the agent's patch |
| Bedrock + compute cost per job | `b` | $4.00 | Claude Sonnet $3/$15 per 1M tokens, ~0.8M in / 0.08M out + Fargate Spot [3][4] |

**Output formulas:**

```
Manual cost / year       = R × u × h × c
Agent-path human cost    = R × u × hr × c       (review/merge the agent's output)
Agent-path AWS cost      = R × u × b  + fixed infra
Net annual saving        = manual − human-review − AWS cost
```

**Worked example (illustrative only — NOT a guarantee):**

```
Annual upgrade tasks     = 1,000 × 2.5                = 2,500 jobs/yr
Manual cost / year       = 2,500 × 2 × $80            = $400,000
Human review / merge     = 2,500 × 0.6 × $80          = $120,000
Bedrock + compute        = 2,500 × $4.00              = $10,000
Fixed infra (endpoints/NAT/S3/CloudWatch, ~$2K/yr)   = $2,000
Annual AWS cost          ≈ $10,000 + $2,000           = $12,000
Net annual saving        ≈ $400,000 − $120,000 − $12,000 = $268,000  (≈ $265K, range ~$260K–$310K)
ROI multiple             ≈ $268,000 / $12,000          ≈ 22x  (illustrative; ~15–25x range)
```

**Per-job Bedrock cost derivation (the dominant variable cost):**

```
Input tokens / job   ≈ 800,000  × $3.00 / 1M  = $2.40   (agentic loop re-reads repo context)
Output tokens / job  ≈  80,000  × $15.00 / 1M = $1.20   (patch + reasoning)
Bedrock / job        ≈ $3.60
Fargate Spot / job   ≈ 4 vCPU × 0.5 hr × $0.04048 + 8 GB × 0.5 hr × $0.004445, ~70% Spot off ≈ $0.05
Total / job          ≈ $3.65  → modeled at $4.00 (conservative)
```

**Honest note on the multiple.** Unlike a lightweight chatbot kit, the AWS bill here is a *real, material line item* — Bedrock tokens scale with every job and a busy year is ~$10K+ of model spend, not pennies. The ~22x multiple is healthy, but it is driven by the large pool of displaced senior-engineer labor, not by near-zero infra cost. If per-job token usage runs heavy (large repos, complex multi-file migrations at ~2M input tokens/job → ~$6–8/job), the multiple compresses toward ~10x. The strongest part of the value story is **throughput and feasibility**: campaigns across hundreds–thousands of repos that simply weren't practical by hand become a parametrized overnight run. Always derive `b` from a small pilot on your real repos before committing to numbers.

## Cost drivers

| Driver | Notes | Typical range |
|---|---|---|
| Bedrock (Claude Sonnet/Haiku) | Input + output tokens per job — **~90%+ of total cost**. Scales with repo size and task complexity, not parallelism | $0.10–$10+ per job (Haiku much cheaper than Sonnet) |
| Fargate / EC2 Spot compute | vCPU-hours + memory-hours; Spot saves up to ~70% | ~$0.01–$0.05 per job |
| VPC interface endpoints | Bedrock/ECR/Logs endpoints, per-AZ hourly | ~$0.01/hr each per AZ (fixed) |
| NAT gateway | Data transfer for git clone (AWS traffic uses endpoints) | $0.045/GB |
| S3 | Results storage (90-day lifecycle) | Negligible |
| CloudWatch | Log ingestion + storage | ~$0.50/GB ingested |
| SNS | Alert notifications | Negligible |

The dominant lever is **model tier and which jobs run on which model**: route triage/analysis to Haiku and reserve Sonnet for code-writing. Per-job `--max-budget-usd` is the hard ceiling that makes cost predictable as parallelism grows.

## Common objections + responses

- **"We don't want Anthropic API keys spread across our infra."** Exactly the point — this uses Bedrock with IAM job roles (`CLAUDE_CODE_USE_BEDROCK=1`). There is no API key to distribute, rotate, or leak.
- **"How do we stop a runaway job from burning budget?"** Every job carries a hard `--max-budget-usd` ceiling; Claude Code stops when it's hit. CloudWatch alarms also fire on failed-job spikes and Bedrock throttling.
- **"Will it auto-change our code?"** No. Jobs emit patches and reports to S3 for human review and merge. It does not push to your branches.
- **"What about throttling at scale?"** Bedrock TPM/RPM quota is the real bottleneck. The kit supports cross-region inference profiles, submission rate-limiting, and quota-increase guidance (`docs/scaling-guide.md`).
- **"Is our code leaving our environment?"** Bedrock calls go through a VPC interface endpoint and never traverse the internet; egress is HTTPS-only; results stay in your S3 bucket. A Bedrock Guardrail filters content and blocks PII (AWS keys, cards, SSNs) in model I/O.
- **"We need stricter encryption / isolation."** Results use SSE-S3 by default — switch to SSE-KMS; and the NAT gateway can be removed to rely solely on VPC endpoints (documented hardening options).
- **"How fast can we see it on our repos?"** A focused build (12–18 engineering hrs over ~3–5 days) stands up the infra and runs a real campaign manifest on your repositories.

## Time-to-value benchmarks

| Milestone | Target |
|---|---|
| CDK stacks deployed + container pushed in your account | Day 1–2 |
| CLI configured; first single job runs end-to-end to S3 | Day 2 |
| Campaign manifest authored + tuned (repos, prompts, tools, budget) | Day 3–4 |
| Bulk run validated, budgets/throttling confirmed, dashboard reviewed | Day 4–5 |

## Differentiation vs. competitors

- **DIY scripts / homegrown orchestration:** teams can wire `xargs` + a shell loop, but they end up reimplementing concurrency, retries, budget caps, secret handling, and result collection. This kit ships all of that, auditable as CDK.
- **CI runners (GitHub Actions / GitLab CI / Jenkins) for agent jobs:** workable for a handful of repos, but minute-billing, concurrency caps, and secret sprawl get painful at hundreds of parallel jobs. Batch + Spot is purpose-built for large, bursty fan-out and keeps model auth on IAM.
- **Hosted agent platforms / SaaS coding-agent fleets:** convenient, but your code and prompts leave your account and model access isn't on Bedrock/IAM. This kit wins when data residency, single-tenancy, and "no API keys" are requirements.
- **AWS Lambda fan-out:** great for short tasks, but coding-agent jobs routinely exceed Lambda's 15-min limit and need more memory/ephemeral storage. Batch's 2–4 hr timeouts and larger compute fit the workload.
- **When this kit is NOT the answer:** you only need a single interactive agent session, can't run CDK / own infra, can't enable Bedrock, or require a fully managed control plane. If any of these apply, this isn't the right kit (see `kit.json`).

## Sources

All savings inputs are tied to a named public source below; cost inputs are computed from AWS public pricing. Numbers are **illustrative and research-backed — not guarantees**. Items marked *internal estimate* have **no** public source and must be validated with your own numbers.

- **[1] Moderne — "Modernizing legacy code: Staying on track after 30 years of Java" (Aug 2025).** https://moderne-v2.webflow.io/blog/modernizing-legacy-java-code-at-scale — Nick McKinney (JPMorgan Chase) reports managing **40,000+ Spring Boot applications** facing **~2.5 upgrades per repo per year** from Spring Boot/Java LTS cadence. Backs the estate scale (`R`) and upgrade frequency (`u`).
- **[2] U.S. Bureau of Labor Statistics — Occupational Outlook Handbook, Software Developers (SOC 15-1252), May 2024.** https://www.bls.gov/ooh/computer-and-information-technology/software-developers.htm — **Median annual wage $133,080**. Used to derive the fully-loaded hourly engineer cost (`c` = $133,080 ÷ 2,080 ≈ $64 × ~1.25 loading ≈ $80/hr).
- **[3] Amazon Bedrock pricing.** https://aws.amazon.com/bedrock/pricing/ — Claude Sonnet $3.00 / 1M input tokens, $15.00 / 1M output tokens. Backs the per-job Bedrock cost (`b`).
- **[4] AWS Fargate pricing (used by AWS Batch on Fargate Spot).** https://aws.amazon.com/fargate/pricing/ — $0.04048 / vCPU-hour + $0.004445 / GB-hour; Fargate Spot discounts up to ~70%. Backs the per-job compute component of `b`.
- **[5] Augment Code — "Automate Multi-File Code Refactoring With AI Agents" (vendor-reported).** https://www.augmentcode.com/learn/automate-multi-file-code-refactoring-with-ai-agents-a-step-by-step-guide — Reports AI agents cutting ~40-hour multi-file refactoring operations to **16–32 hours (40–60% faster)** across 100,000+ files. Vendor benchmark; backs the turnaround-speed outcome only (labeled vendor-reported).

**Internal estimates (no public source — validate with your own numbers):** engineer-hours per task done manually (`h` = 2 hrs) and human review/merge time per agent job (`hr` = 0.6 hr). These depend heavily on codebase size, task complexity, and your test/CI maturity — derive both, and the per-job Bedrock cost `b`, from a small pilot on your real repositories.
