# XML Schema Inference Agent

> **Status:** Draft · Spec-only kit — a blueprint of a working implementation · Build level: Custom IaC

A Bedrock Agent that turns raw, undocumented XML/JSON traces into a usable data contract in one pass. You feed it a your traces; the agent calls three Lambda tools to **discover** every field and its path, **infer** types from string values, **detect** repeating elements as arrays, **map** source-specific paths to standard logical field names (`credit_score`, `income`, `dti`, `fraud_score`, `decision`…) with confidence scores, and **generate** working Redshift SUPER/PartiQL queries. The same agent handles completely different source schemas with no per-source code.

## Why this exists

This was built for a **risk-decisioning SaaS platform** that emits an XML trace for every credit decision. Every downstream customer defines its own XML structure — no XSD, no documentation — so onboarding a new source means a data engineer manually tracing nested XML and hand-writing XPath mappings to standard business fields. The source team measured that at **2–3 days per deployment**, on top of a brittle Spark-on-EKS extraction layer that breaks whenever a schema drifts. POCs with Snowflake, Databricks, and Iceberg+Glue+Athena all stalled on the same wall: deeply nested traces with repeating elements and ambiguous, all-string values.

The thesis is that schema discovery, type inference, array detection, and field mapping are exactly the kind of pattern-recognition a reasoning model does well — and that wrapping it in deterministic Lambda tools makes the output reviewable and reproducible. The agent proposes; a data engineer approves. It's an onboarding accelerator, not an autonomous pipeline.

## How to use this kit

This kit is a blueprint, not a codebase: it contains the architecture, the build contract, and acceptance tests — but not the agent's source code. Read [`AGENTS.md`](AGENTS.md) + [`build-spec/`](build-spec/) and have a coding agent (Kiro / Claude Code / Cursor / Codex) implement the pattern in your own AWS account, against your own sources and target schema.

**What the spec targets:** a Streamlit demo with a **Local mode** (runs the three tools directly, no AWS needed) and a **Bedrock Agent mode** (invokes the deployed agent and streams its reasoning trace), plus CDK that deploys the S3 bucket, the tools Lambda, and the IAM roles.

## What this kit gives you

| File | What's in it |
|---|---|
| [`kit.json`](kit.json) | Kit manifest — services, model, outcomes, ideal customer, ROI scaffolding |
| [`architecture/architecture.md`](architecture/architecture.md) | The stack, a component diagram, the analyze→map→SQL data flow, and the audit trail |
| [`business-case/roi-framework.md`](business-case/roi-framework.md) | ROI math template, cost drivers, objection handling, competitive framing |
| [`AGENTS.md`](AGENTS.md) | Build contract for a coding agent re-implementing or customizing the kit |
| [`build-spec/`](build-spec/) | Requirements, architecture decisions, deployment spec, acceptance tests |

## Vertical applicability

The agent reasons over *structure*, not domain meaning, so the pattern travels well beyond credit decisioning:

- **Financial services (origin):** unify credit-decision traces from many lenders into one logical schema for analytics in Redshift.
- **Healthcare / life sciences:** map heterogeneous HL7/clinical XML or lab feeds from different facilities to common fields without a per-facility parser.
- **Insurance:** onboard ACORD-style or carrier-specific XML submissions where every carrier's dialect differs.
- **B2B integrations / EDI:** normalize partner XML/JSON (orders, invoices, shipment events) into a shared model when each partner ships its own shape.

In every case you swap the `STANDARD_FIELDS` dictionary for your domain's logical fields; the discovery, type-inference, array-detection, and SQL-generation machinery is unchanged.

## Shared responsibility

This is an accelerator and a working reference, not a managed service. You own the deployed agent and Lambda tools, the standard-field dictionary and mapping rules, the trace data, and the AWS infrastructure in your account. The agent proposes mappings with confidence scores and generates SQL — a data engineer reviews and approves before anything is promoted to production tables. You and your engineering team adapt the kit to your sources; deploy scripts and CDK are provided as-is.
