# Sentinel — Auto-Loan Fraud Detection

> **Status:** Draft · Spec-only kit — a blueprint of a working implementation · Build level: Custom IaC

A multi-agent fraud screening agent for auto-loan and dealer-finance applications. A dealer submits an application; Sentinel runs four cooperating Bedrock (Claude) agents — **Identity**, **Velocity**, **Financial**, and an **Orchestrator** — each scoring one fraud dimension and threading findings through a shared context. The output is an explainable **APPROVE / FLAG FOR REVIEW / DECLINE** recommendation with a confidence score, a per-dimension score-contribution breakdown, and a plain-language narrative an underwriter can act on.

## Why this exists

Auto lenders and dealer-finance platforms process huge application volumes, and most fraud screening is rules-based: rigid thresholds fraudsters learn to slip past, that also bury underwriters in false positives. The patterns that matter most are the ones no single rule sees — a **synthetic identity** (SSN issued years after the applicant's stated birth year), **application stacking** across dealers, or a **financial profile** where income doesn't fit the occupation. Sentinel's thesis is that these signals only surface when identity, velocity, and financial dimensions are correlated together, then explained in language a credit analyst can trust. It's a fast, transparent second opinion — not a replacement for the underwriter.

## How to use this kit

This kit is a blueprint, not a codebase: it contains the architecture, the build contract, and acceptance tests — but not the agent's source code. Read [`AGENTS.md`](AGENTS.md) + [`build-spec/`](build-spec/) and have a coding agent (Kiro / Claude Code / Cursor / Codex) implement the pattern in your own AWS account, against your own lending data and risk policy.

**What the spec targets:** an application that runs locally in deterministic *mock mode* (no AWS creds needed) and flips to *live Bedrock* with a header toggle, with deploy scripts that ship a single container to App Runner.

## What this kit gives you

| File | What's in it |
|---|---|
| [`kit.json`](kit.json) | Kit manifest — services, model, outcomes, ideal customer, ROI scaffolding |
| [`architecture/architecture.md`](architecture/architecture.md) | The stack, a component diagram, data flow (happy + fallback paths), audit trail |
| [`business-case/roi-framework.md`](business-case/roi-framework.md) | ROI math template, cost drivers, objection handling, competitive framing |
| [`AGENTS.md`](AGENTS.md) | Build contract for a coding agent re-implementing or customizing the kit |
| [`build-spec/`](build-spec/) | Requirements, architecture decisions, deployment spec, acceptance tests |

## Shared responsibility

This is an accelerator and a working reference, not a managed service. You own the deployed agents, the fraud heuristics and scoring thresholds, the application data, and the AWS infrastructure in your account. The recommendation is decision-support for a human underwriter — you own the funding decision. You and your engineering team adapt the kit to your product; deploy scripts are provided as-is.
