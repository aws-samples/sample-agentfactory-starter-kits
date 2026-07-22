# Requirements — XML Schema Inference Agent

> Audience: a coding agent implementing or customizing the kit.

## Functional requirements

**FR1 — Schema discovery from example traces.** The system shall accept a batch of JSON-parsed traces for one source and return a deduplicated field inventory: every field's dot-notation path, an inferred type, an array flag, and a sample value.
The `analyze_traces` tool flattens nested objects recursively, records array paths with element counts, and dedupes by path across the batch. *Maps to: T1, T2.*

**FR2 — Type inference from string values.** The system shall infer a type for each field from its value pattern, treating all raw XML values as strings.
Zero-padded numerics remain strings; `Y`/`N`/`true`/`false`/`PASS`/`FAIL` → boolean; ISO date/timestamp patterns → date; plain integers/decimals → integer/decimal; everything else → string. *Maps to: T3.*

**FR3 — Schema-level array detection.** The system shall detect repeating elements as arrays at the schema level across the trace batch, so an element that appears once in one trace and multiple times in another is still recognized as an array.
The parser collapses repeating tags and `ArrayElementObject`/`ArrayElementString` conventions into arrays before analysis. *Maps to: T4.*

**FR4 — Field mapping to standard logical names with confidence.** The system shall map discovered paths to a configurable catalog of standard logical field names (`STANDARD_FIELDS`), returning a confidence score per mapping and keeping the highest-confidence candidate per logical field.
Matching tries `PATH_PATTERNS` (multi-part nested suffixes) first, then keyword + context matching. *Maps to: T5, T6.*

**FR5 — Unmapped and ambiguous reporting.** The system shall return fields that match no logical name as `unmapped_fields` and shall not fabricate a mapping where confidence is absent. *Maps to: T7.*

**FR6 — Redshift SQL generation.** The system shall generate, from a set of mappings, a Redshift SUPER/PartiQL `SELECT`, a `CREATE VIEW`, and 2–3 sample analytics queries, converting each mapped dot-path to a PartiQL accessor. *Maps to: T8.*

**FR7 — Cross-source unification.** Running the flow on two structurally different sources shall produce mappings that resolve the same logical field to its different physical path per source, enabling a unified mapping registry. *Maps to: T9.*

**FR8 — Agent tool orchestration.** A Bedrock Agent (Claude Sonnet 4) with the three tools as an action group shall call `analyze_traces` → `generate_mapping` → `generate_sql` and interpret/assemble the results, returning structured output, not free-form prose only. *Maps to: T10.*

**FR9 — Local (no-AWS) execution.** The three tools shall be runnable directly (Local mode UI + `test_local.py`) without AWS credentials for demos and testing. *Maps to: T11.*

## Non-functional requirements

**NFR1 — Latency.** A full analyze→map→SQL pass over a small trace batch shall complete in interactive time (seconds to low tens of seconds) on the default model tier.

**NFR2 — Reproducibility.** Given the same traces and the same `STANDARD_FIELDS`/`PATH_PATTERNS`, the tool outputs (inventory, mappings, confidence, SQL) shall be deterministic; the model orchestrates but does not invent mappings.

**NFR3 — Security.** Single-tenant in your account. The Bedrock agent role shall grant only `bedrock:InvokeModel` on the specific Claude model; the Lambda role shall have basic execution + read-only access to the traces bucket. Data in transit over HTTPS; PII masked before parsing.

**NFR4 — Cost predictability.** Bedrock cost shall scale with sources onboarded and schema changes (bursty), not with steady-state transaction volume.

**NFR5 — Reviewability.** Every mapping shall be traceable to its source `customer_path` and carry a confidence score so a human can review before promotion.

**NFR6 — Single-tenancy.** One deployment per organization in your own account/region; no shared multi-tenant store.

## Out of scope

- Autonomous application of generated SQL/DDL to production tables (human review required).
- A persisted, versioned mapping registry (reference returns mappings; persistence is a customization).
- Provisioning a Redshift cluster / Serverless workgroup (the SQL targets it; standing it up is your step).
- Authentication/authorization on the demo UI (must be added for any production surface).
- Model fine-tuning or custom inference hosting.

## Dependencies

- Bedrock model access enabled for Claude Sonnet 4 (`anthropic.claude-sonnet-4-20250514-v1:0`) in your region.
- AWS account with permissions to create S3, Lambda, IAM roles, and a Bedrock Agent; AWS CDK v2; Python 3.12.
- Representative traces for at least two structurally different sources.
- Redshift SUPER target table (only if the query/validation layer is in scope).
