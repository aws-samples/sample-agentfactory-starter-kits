# Agentic Insurance Advisor

> **Status:** Draft · Spec derived from a working implementation · Build level: Custom IaC

An advisory agent for insurance producers. Given a client profile, a **Bedrock supervisor agent** orchestrates three specialists and returns a complete, client-ready recommendation package:

- **Product Retrieval** — RAG over a knowledge base of carrier product documents (brochures, policy summaries, rate sheets) to find products that fit the client's age, income, dependents, risk tolerance, and goals.
- **Suitability Analysis** — scores each retrieved product against eight FINRA/SEC-style rules (SUIT-01…SUIT-08) loaded from a YAML config, returning a SUITABLE / UNSUITABLE / CONDITIONAL verdict per product with the rule ID cited.
- **Recommendation Letter** — drafts a compliant letter written to the client: products considered, recommendation rationale, suitability justification, the required disclosure block, and next steps.

The output is a draft for a licensed producer to review, edit, and own — not autonomous advice.

## Why this exists

Insurance advisory is document-intensive and compliance-heavy. A producer spends meaningful time per client manually cross-referencing product material, reasoning about suitability, and hand-writing a recommendation letter. That manual flow caps how many clients a producer can serve, lets suitability reasoning vary advisor-to-advisor, and produces letters that inconsistently include the required disclosures — which makes audit prep painful. This kit decomposes that flow into specialized agents under a supervisor so the research is grounded in the carrier's own documents, the suitability check is the same documented eight rules every time, and the letter ships with its disclosures — in a single short workflow instead of an afternoon.

## How to use this kit

This kit is a blueprint: it contains the architecture, the build contract, and acceptance tests — not the agent's source code. No source is included; the agent is built from the spec. Read [`AGENTS.md`](AGENTS.md) + [`build-spec/`](build-spec/) and have a coding agent (Kiro / Claude Code / Cursor / Codex) implement the pattern in your own AWS account, against your product catalog and compliance standard.

**What the spec targets:** CloudFormation for the shared infra, shell scripts that provision the four Bedrock agents and wire the collaboration, an async Lambda API, and a React UI with six sample clients and five sample carrier products for an end-to-end demo.

## What this kit gives you

| File | What's in it |
|---|---|
| [`kit.json`](kit.json) | Kit manifest — services, model, outcomes, ideal customer, ROI scaffolding |
| [`architecture/architecture.md`](architecture/architecture.md) | The stack, a component diagram, data flow (happy + fallback paths), audit trail |
| [`business-case/roi-framework.md`](business-case/roi-framework.md) | ROI math template, cost drivers, objection handling, competitive framing |
| [`AGENTS.md`](AGENTS.md) | Build contract for a coding agent re-implementing or customizing the kit |
| [`build-spec/`](build-spec/) | Requirements, architecture decisions, deployment spec, acceptance tests |

## Shared responsibility

This is an accelerator and a working reference, not a managed service. You own the deployed agents, the product knowledge base, the suitability rules, the client and advisory data, and the AWS infrastructure in your account. The recommendation package is decision-support for a licensed producer who reviews, edits, and owns the recommendation. You and your engineering team adapt the kit to your lines of business and compliance standard; deploy scripts are provided as-is.
