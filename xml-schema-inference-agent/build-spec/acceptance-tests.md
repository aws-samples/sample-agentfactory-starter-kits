# Acceptance Tests — XML Schema Inference Agent

> Audience: you and your engineering lead during sign-off. Each test maps to requirements in [`requirements.md`](requirements.md).

## Functional

**T1 — Field inventory discovered.**
- *Setup:* a batch of parsed traces for one source (e.g. `hackathon/trace_customer_A_parsed.json`).
- *Action:* run `analyze_traces` (Local mode or via the agent).
- *Expected:* a deduplicated field inventory with dot-notation paths, a type per field, an array flag, and sample values; `total_fields` reflects unique paths.
- *Maps to:* FR1.

**T2 — Nested paths flattened correctly.**
- *Setup:* a deeply nested trace (e.g. `Origination.ServiceResponseBody.BureauA.ScreeningReport.data.fraud_score`).
- *Action:* run `analyze_traces`.
- *Expected:* the full dot-path appears in the inventory at the correct depth.
- *Maps to:* FR1.

**T3 — Type inference from strings.**
- *Setup:* fields with values `"745"`, `"0650"`, `"14.5"`, `"1985-03-22"`, `"Y"`, `"APPROVED"`.
- *Action:* run `analyze_traces`.
- *Expected:* `745`→integer, `0650`→string (zero-padded preserved), `14.5`→decimal, date→date, `Y`→boolean, `APPROVED`→string.
- *Maps to:* FR2.

**T4 — Repeating elements detected as arrays.**
- *Setup:* a batch where a credit-account element appears once in one trace and multiple times in another (`Credits[]` / `Accounts.Account[]`).
- *Action:* run `analyze_traces` over the batch.
- *Expected:* the element is reported in `arrays_detected` with an element count; array-ness holds even though one trace had a single element.
- *Maps to:* FR3.

**T5 — Standard fields mapped with confidence.**
- *Setup:* the field inventory from a source.
- *Action:* run `generate_mapping`.
- *Expected:* standard fields (`credit_score`, `income`, `dti`, `fraud_score`, `decision`…) are mapped to your `customer_path` with a confidence score; one best candidate per logical field.
- *Maps to:* FR4.

**T6 — Nested field resolved via path pattern.**
- *Setup:* `credit_score` hidden at `LoanDecision.CreditData.Score.Value` (Customer C), which name-only matching would miss.
- *Action:* run `generate_mapping`.
- *Expected:* `PATH_PATTERNS` resolves it to `credit_score` with high confidence.
- *Maps to:* FR4.

**T7 — Unmapped fields reported, not guessed.**
- *Setup:* a trace with fields outside the standard catalog.
- *Action:* run `generate_mapping`.
- *Expected:* those fields appear in `unmapped_fields`; no fabricated mapping is emitted for them.
- *Maps to:* FR5.

**T8 — Redshift SUPER/PartiQL generated.**
- *Setup:* a set of mappings for a source.
- *Action:* run `generate_sql`.
- *Expected:* a valid `SELECT` with PartiQL accessors, a `CREATE VIEW`, and sample analytics queries; mapped dot-paths become PartiQL paths against the SUPER column.
- *Maps to:* FR6.

**T9 — Cross-source unification.**
- *Setup:* Customer A and Customer C traces (structurally different).
- *Action:* run the full flow on both.
- *Expected:* the same logical field (e.g. `credit_score`) maps to its different physical path per source; a unified mapping is producible.
- *Maps to:* FR7.

**T10 — Agent orchestrates the tools.**
- *Setup:* the deployed Bedrock Agent with the action group.
- *Action:* feed a trace batch with a customer id.
- *Expected:* the agent calls `analyze_traces` → `generate_mapping` → `generate_sql` and returns assembled structured output (inventory + mappings + SQL).
- *Maps to:* FR8.

**T11 — Local mode runs with no AWS creds.**
- *Setup:* `src/lambda/test_local.py` / Streamlit Local mode, no credentials.
- *Action:* run the flow.
- *Expected:* the three tools execute end-to-end and produce results without any Bedrock/AWS call.
- *Maps to:* FR9.

## Non-functional

**T12 — Interactive latency.**
- *Action:* run a full analyze→map→SQL pass over a small batch on Claude Sonnet 4.
- *Expected:* completes in seconds to low tens of seconds.
- *Maps to:* NFR1.

**T13 — Deterministic, reproducible output.**
- *Action:* run the tools twice on the same traces with the same dictionary.
- *Expected:* identical field inventory, mappings, confidence, and SQL.
- *Maps to:* NFR2.

**T14 — Least-privilege agent role.**
- *Action:* inspect the Bedrock agent role policy.
- *Expected:* only `bedrock:InvokeModel` on the specific Claude model (+ `lambda:InvokeFunction` on the tools Lambda); the Lambda role only reads the traces bucket.
- *Maps to:* NFR3.

**T15 — Reviewability.**
- *Action:* inspect a mapping result.
- *Expected:* each mapping carries its source `customer_path` and a confidence score, so a human can trace and approve.
- *Maps to:* NFR5.

## Operational

**T16 — CDK deploy succeeds.**
- *Action:* `cd src/cdk && cdk deploy`.
- *Expected:* stack creates the S3 bucket, tools Lambda, and IAM roles; outputs (bucket name, Lambda ARN, agent role ARN) are present.
- *Maps to:* operational readiness.

**T17 — Parser handles S3 and Kinesis triggers.**
- *Action:* invoke `xml_parser.py` with an S3 event and a Kinesis record.
- *Expected:* both paths produce parsed JSON to the `parsed/` prefix with repeating elements collapsed to arrays.
- *Maps to:* FR3, operational readiness.

## Sign-off

| Role | Name | Date |
|---|---|---|
| Reviewer | __________ | ______ |
| Your engineering lead | __________ | ______ |
