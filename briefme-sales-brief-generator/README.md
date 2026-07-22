# BriefMe — Sales Brief Generator

> **Status:** Draft · Spec derived from a working implementation · Build level: Custom IaC

A self-service web app that turns a company name into a sales-ready brief. A rep signs in, types a company (and optional URL), and BriefMe runs a single **AgentCore-hosted Strands agent** on **Amazon Nova Premier** that does live, **cited** web research across the company's overview, products, recent news, talking points, and key stakeholders. The agent returns a structured JSON brief; the backend renders it as a **click-through HTML slideshow**, stores it, and shows it in the browser. Past briefs are searchable by company.

## Why this exists

Reps lose hours before every meeting doing the same thing by hand: skimming the company site, hunting for recent news, piecing together who the stakeholders are, and trying to form a point of view. The output is inconsistent rep-to-rep, often stale, and impossible to audit — you can't tell where a claim came from. "AI research" SaaS tools help, but they're black boxes outside your boundary with no verifiable sources.

BriefMe's thesis is that pre-call research is a bounded, repeatable task an agent does well *when its claims are cited*. Nova Web Grounding returns real source URLs for every research pass, so the brief is a fast, transparent first draft a seller can trust and verify — not a hallucinated summary. It runs entirely inside your own AWS account.

## How to use this kit

This kit is a blueprint: it contains the architecture, the build contract, and acceptance tests — not the agent's source code. No source is included; the agent is built from the spec. Read [`AGENTS.md`](AGENTS.md) + [`build-spec/`](build-spec/) and have a coding agent (Kiro / Claude Code / Cursor / Codex) implement the pattern in your own AWS account, against your selling motion.

**What the spec targets:** a single `cdk deploy` from `briefme-infra/` that stands up the whole stack — agent, API, frontend, auth, storage — with no container build required (AgentCore direct code deployment).

## What this kit gives you

| File | What's in it |
|---|---|
| [`kit.json`](kit.json) | Kit manifest — services, model, outcomes, ideal customer, ROI scaffolding |
| [`architecture/architecture.md`](architecture/architecture.md) | The stack, a Mermaid diagram, data flow (happy + fallback paths), audit trail |
| [`business-case/roi-framework.md`](business-case/roi-framework.md) | ROI math template, cost drivers, objection handling, competitive framing |
| [`AGENTS.md`](AGENTS.md) | Build contract for a coding agent re-implementing or customizing the kit |
| [`build-spec/`](build-spec/) | Requirements, architecture decisions, deployment spec, acceptance tests |

## Shared responsibility

This is an accelerator and a working reference, not a managed service. You own the deployed agent, the research prompt and brief schema, the generated briefs, and the AWS infrastructure in your account. The brief is research output for a human seller to read and verify — the agent researches only the public web and takes no outbound actions. You and your engineering team adapt the kit to your motion; CDK and deploy steps are provided as-is.

## Vertical applicability

BriefMe is cross-vertical — the pattern is "research a named entity on the public web and produce a cited, structured brief." Re-point the prompt and schema and it serves:

- **Financial services / banking:** pre-call briefs on prospective commercial-banking or wealth clients (public company profile, recent filings/news, leadership).
- **Professional services / consulting:** account dossiers before a pitch — what the target does, recent moves, who to talk to.
- **Technology / ISV sales:** competitive and prospect research before discovery calls, with sources the AE can cite back.
- **Partner / alliances teams:** quick profiles of potential partners or co-sell targets, generated consistently across the team.

In each case only the prompt, brief schema, and slide layout change; the AgentCore + Nova Web Grounding + serverless stack stays the same.
