# ROI Framework — Code Intelligence Agent

> The numbers here are **templates and clearly-labeled illustrative examples** — real figures come from your own discovery, not from this doc. Do not commit to numbers from this kit.

## What problem this solves

In an engineering-led org, the codebase is a knowledge base that only engineers can read. Everyone else who needs code-level answers — execs sizing technical risk, security reviewers, compliance auditors, product, and M&A/PE diligence teams — has three bad options: interrupt a developer (doesn't scale, and the answer is one person's memory), commission a point-in-time audit (stale the day it ships), or hire consultants (expensive and slow). The cost shows up in two places: **senior-engineer time lost** to answering "what does our code do here?" and **slow/stale answers** to questions like "which services touch PII and is it encrypted?" across dozens of repos.

The Code Intelligence Agent makes the code self-serve. Anyone asks in Amazon Quick and gets an answer grounded in the actual code with `file:line` citations — scoped to only the repos that person can already see in GitHub, with the depth tuned to their role. The codebase becomes an answerable, always-current knowledge base instead of something a human has to read.

## ROI math (template)

**Inputs to gather in discovery:**

| Input | Symbol | Example (illustrative) |
|---|---|---|
| Stakeholder code questions / week (across execs, security, compliance, product) | `Q` | [N] /week |
| Share that today require interrupting a developer | `d` | [X%] |
| Developer time per interrupted question (find context + answer) | `t` | [N] min |
| Fully-loaded developer cost / hour | `c` | $[N] |
| Developer-time reduction once questions are self-served | `Δd` | [X%] |
| Annual spend on code audits / consultant-led diligence the agent displaces | `S` | $[N] |
| Share of that audit/diligence spend offset by on-demand cited answers | `Δs` | [X%] |

**Output formulas:**

```
Developer hours spent / week today = Q × d × (t / 60)
Developer time reclaimed / yr ($)  = (Q × d × (t / 60)) × Δd × c × 52
Audit/diligence spend avoided / yr = S × Δs
Gross annual benefit               = developer time reclaimed + audit spend avoided
```

**Worked example — ILLUSTRATIVE, RESEARCH-BACKED — not a guarantee.** Inputs below are anchored to public sources (see [Sources](#sources)) and deliberately conservative; replace every one with your discovery data.

This example uses the **engineer-time-reclaimed** model, which ties directly to the strongest public benchmark: research finds developers spend **~58% of their time comprehending code** (ACM/CACM, 2023). A 40-hour week implies ~23 hrs/wk on comprehension. We credit the agent with reclaiming just **2 hrs/wk per engineer** — a conservative ~9% slice of that comprehension time, not the whole thing.

```
Loaded developer rate (c):
  BLS May-2024 median wage (15-1252 Software Developers) = $133,080/yr
  × ~1.4 loaded (benefits, taxes, overhead)              = $186,312/yr
  ÷ 2,080 hrs/yr                                         = ~$90/hr

Assume: 50 engineers, 2 hrs/wk reclaimed each, 46 working weeks/yr (PTO/holidays), $90/hr

Hours reclaimed / week  = 50 × 2                         = 100 hrs/wk
Hours reclaimed / year  = 100 × 46                       = 4,600 hrs/yr
Engineer time reclaimed = 4,600 × $90                    = ~$414,000/yr  → ~$410K/yr (illustrative)
```

Lead with this reclaimed-engineer-time line — it's the harder dollar. The audit/consultant-diligence-avoided line (formulas above) is real but softer; treat it as upside, not the headline.

**Cost (illustrative, computed from AWS pricing):**

```
Per query (Bedrock):
  Claude Sonnet 4.5 synthesis: 6,000 in × $3/1M + 1,000 out × $15/1M = $0.018 + $0.015 = $0.033
  Intent-classification call:  ~1,000 in × $3/1M + 50 out × $15/1M   ≈ $0.004
  Titan Embed v2 query vector: ~100 tokens × $0.02/1M                ≈ $0.000002 (negligible)
  → ~$0.04 / query

Volume: ~200 queries/day × ~250 working days                        = ~50,000 queries/yr
  Query Bedrock spend        = 50,000 × $0.04                        = ~$2,000/yr
  Guardrails (~5 text units/query @ $0.15–0.10/1k)                   = ~$60/yr
  Titan embeddings (initial index + incremental on push)            = ~$10/yr
  Lambda (4 GB, ~5 s/query) + DynamoDB + S3 + SQS + KMS + CloudWatch = ~$170/yr
  → ~$2,240/yr  → round conservatively to ~$3K/yr
```

```
Multiple = ~$410K savings ÷ ~$3K cost ≈ ~137x  → stated conservatively as ~80–140x
```

The multiple is unusually high because the architecture is **serverless with FAISS-on-S3** — there is **no OpenSearch Serverless OCU floor** (~$350+/mo) that dominates many RAG kits. Cost scales almost entirely with query volume; the per-user daily token budget (default 100K) is the direct lever to cap it.

## Cost drivers

| Driver | Notes | Reference signal |
|---|---|---|
| Bedrock — Claude Sonnet 4.5 | Synthesis (max 2048 output tokens/answer) + a cheap intent-classification call (~20 tokens). Scales with queries/day | Largest single line in the source's reference estimate |
| Bedrock — Titan Embed v2 | Per-chunk at index time + one query embedding per question (1024-dim). Indexing cost is one-time per repo + incremental on push | Scales with repo size and change rate |
| Lambda | MCP + webhook + OAuth + incremental indexer; MCP is 4 GB / 900 s, reserved concurrency 50 | ~$3/mo reference (single small repo) |
| DynamoDB | Single-table, PAY_PER_REQUEST, KMS-encrypted, PITR | ~$0.25/mo reference |
| S3 | FAISS indexes (one object per repo) | ~$0.05/mo reference |
| SQS / KMS / CloudWatch / X-Ray | FIFO queue + DLQ, CMK, dashboard/alarms, 90-day logs | KMS ~$1/mo; rest low |

The source's reference estimate for a **single small-repo deployment is ~$20–35/month**, Bedrock-dominated. Cost scales primarily with **query volume** and **how many/large the indexed repos are**. The per-user daily token budget (default 100K) is the direct lever to cap spend; the incremental indexer keeps re-indexing cheap by re-embedding only changed files instead of full re-crawls.

## Common objections + responses

- **"Isn't this just GitHub Copilot / our IDE assistant?"** No — those are developer code-completion tools inside the IDE. This is *organizational* code Q&A through Amazon Quick: a non-engineer asks in plain language and gets a cited answer. It complements a Copilot; it doesn't compete with it. (The kit explicitly disqualifies "wants an IDE copilot.")
- **"We already use Amazon Quick — why this?"** Quick's native GitHub indexing hits walls on a large org: ingestion failures, no code-aware chunking, no incremental sync, no per-user repo scoping. This kit adds AST-aware chunking, `file:line` citations, webhook-driven incremental re-indexing, and GitHub identity pass-through — and still surfaces through the Quick UI you already knows.
- **"Will it leak code to people who shouldn't see it?"** No. GitHub identity is passed through per request and access is checked against the GitHub API per user (cached 5 min). The agent only answers over repos that user can already see — it never widens scope to "all indexed repos."
- **"Will it hallucinate or invent code that isn't there?"** The synthesis prompt forbids it: the model must ground every claim in retrieved chunks and emit `file:line` citations, or say it can't answer from the indexed context. Code in context is treated as data, so instructions hidden in comments are ignored.
- **"What about secrets and sensitive data in our code?"** Two layers: a Bedrock Guardrail anonymizes PII (AWS keys, passwords, emails, IPs) plus GitHub-token and API-key regexes, and a local output sanitizer redacts secret-shaped strings before any answer leaves the account. Input is also screened for injection/prompt-attack patterns.
- **"Does our source code leave our environment?"** Single-tenant in your own account and region. Code is fetched via the GitHub API you authorize, embeddings live in your S3, and the only outbound calls are in-region Bedrock and GitHub.
- **"Will it run up an unbounded Bedrock bill?"** No. A per-user daily token budget (default 100K) and reserved Lambda concurrency cap blast radius, and the incremental indexer avoids full re-crawls. Spend scales predictably with query volume.
- **"How long until we see it on our repos?"** A focused engagement (16–24 hours over ~5–8 days) stands up a customized, deployed instance indexing 2–3 representative repos and connected to Quick.

## Time-to-value benchmarks

| Milestone | Target |
|---|---|
| SAM stack deployed to your account; `tools/list` returns the tools | Day 1–2 |
| GitHub OAuth App + webhooks wired; 2–3 representative repos indexed | Day 3–5 |
| Guardrail / role filters / chunker tuned; connected to Amazon Quick | Day 5–7 |
| Acceptance tests passed + stakeholder walkthrough of cited cross-repo answers | Day 7–8 |

## Differentiation vs. competitors

- **IDE copilots (GitHub Copilot, Cursor, Kiro):** built for developers writing code in the editor. This kit serves *non-engineers* asking organizational questions through Quick, with per-user repo scoping and citations. Position as additive, not competitive.
- **Amazon Quick native GitHub indexing:** great front door, limited indexer. This kit keeps the Quick UX and adds AST-aware chunking, citations, incremental webhook sync, and identity pass-through — the things that break when you point native indexing at a large org.
- **Generic "chat with your repo" RAG tools:** typically clone the repo, index one snapshot, ignore who's asking, and answer without verifiable citations. This kit fetches via the GitHub API (no clone), re-indexes on push, scopes per user, and cites `file:line`.
- **Point-in-time audits / consultant-led code diligence:** a human reads the code and writes a report that's stale on delivery. This kit makes the same questions answerable on demand, always current, at a fraction of the cost.
- **When this kit is NOT the answer:** you want an IDE copilot, want the agent to write code or open PRs, can't grant GitHub OAuth/webhook access, or requires fully on-prem deployment with no Bedrock. Disqualify early (see `kit.json`).

## Sources

All savings benchmarks below are public; cost figures are computed from AWS public pricing. Every number in this doc is **illustrative and research-backed — not a guarantee.** Validate with your own numbers.

| Source | URL | What it backs |
|---|---|---|
| ACM / Communications of the ACM — *From Code Complexity Metrics to Program Comprehension* (Feitelson, 2023) | https://cacm.acm.org/research/from-code-complexity-metrics-to-program-comprehension/ | "Developers spend, on average, 58% and 70% of their time trying to comprehend code but only 5% editing it." Basis for the ~58% comprehension share and the conservative 2 hrs/wk reclaimed. |
| U.S. Bureau of Labor Statistics — Occupational Outlook Handbook, Software Developers (SOC 15-1252), May 2024 | https://www.bls.gov/ooh/computer-and-information-technology/software-developers.htm | Median annual wage $133,080 (May 2024). Basis for the ~$90/hr loaded developer rate (×1.4 burden ÷ 2,080 hrs). |
| U.S. Bureau of Labor Statistics — OEWS, Software Developers (15-1252) | https://www.bls.gov/oes/2023/may/oes151252.htm | Corroborating occupational wage detail for SOC 15-1252. |
| AWS — Amazon Bedrock pricing | https://aws.amazon.com/bedrock/pricing/ | Claude Sonnet 4.5 ($3/1M in, $15/1M out), Titan Text Embeddings V2 ($0.02/1M), and Guardrails unit pricing used in the per-query and annual cost math. |

**Notes / honesty caveats:**
- The team size (50 engineers), 2 hrs/wk reclaimed per engineer, 46 working weeks, ~200 queries/day, and the ~1.4× salary-loading factor are **internal illustrative assumptions**, not citations — chosen conservatively. Replace them with discovery data.
- The audit/consultant-diligence-avoided line in the template formulas is an internal estimate with no public citation attached; treat it as upside and challenge it in discovery.
- The BLS Occupational Outlook Handbook figure was confirmed via BLS search results; the page may rate-limit automated fetches but is publicly viewable in a browser.
