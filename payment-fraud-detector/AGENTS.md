# AGENTS.md — Payment Fraud Detector

> **Audience:** Coding agents (Kiro, Claude Code, Codex, Cursor) re-deploying or extending this kit in your AWS account.
> **Status:** Spec-only kit — no source code is included; the implementation is built from this contract.

## What this is

A working fraud-detection agent built on three components:

- **MCP server** (`mcp-server/`) — FastAPI rules engine on ECS Fargate, exposed via ALB. Detects unregistered receivers, threshold avoidance, self-dealing, and excessive-frequency patterns. Pure Python, no model in the loop, ~35 ms per analysis.
- **Bedrock Agent** (`infrastructure/cloudformation/bedrock-agent.yaml`) — Claude 3 Sonnet, orchestrates the rules engine via an action group with `RETURN_CONTROL` executor, then writes an analyst-grade summary.
- **Streamlit UI** (`streamlit-app/`) — analyst workspace with dashboard, alerts, raw-data, senders, and coordinator views. Runs locally for development; on ECS Fargate behind ALB in production.

Optional sidecar: `scripts/claude_only_fraud.py` calls `bedrock-runtime.converse` directly against the raw data with no rules engine — demonstrates what a frontier model finds on its own (useful for demos).

## Where to read first

The kit's own docs are the contract; read in this order:

1. `architecture/architecture.md` — high-level overview: components and data flow
2. `build-spec/requirements.md` — what the agent must do
3. `build-spec/architecture-decisions.md` — why custom-iac, why ECS+ALB, why Streamlit, why Sonnet
4. `build-spec/deployment-spec.md` — what gets deployed in your account
5. `build-spec/acceptance-tests.md` — what to verify before calling the build done

As you build, your implementation should carry its own docs: a deploy walkthrough (`README.md`), a Bedrock Agent + action-group guide, a multi-stack CFN deployment guide, and the rules-vs-LLM split rationale.

## Customizing for your deployment

The file paths below describe the target repo layout your build should produce. The customization story:

1. **Rules engine** — `mcp-server/src/rules/` has separate rule modules. For a new vertical (FSI AML, healthcare claims FWA, insurance), update or replace the rule modules. The kit's value isn't in any specific rule — it's in the architecture pattern.
2. **Data schemas** — `data/generic/` and `data/pharmacy/` show the two existing examples. Add a new directory for your payment shape (transactions, senders, receivers).
3. **Bedrock Agent action group definitions** — `bedrock-agent/bedrock_config.json` and `infrastructure/cloudformation/mcp-api-schema.json`. Adjust the OpenAPI schema to match the rules-engine endpoints you're exposing.
4. **Streamlit UI** — `streamlit-app/components/` is straightforward Streamlit. Customize the analyst views for your workflow.
5. **Deploy scripts** — `infrastructure/cloudformation/deploy.sh` walks through the master CFN stack. You fill in your account ID, region, and bucket names.

## What you're NOT deciding from scratch

The spec pins these architectural choices — don't relitigate them without a concrete reason:

- Don't replace FastAPI with a different framework
- Don't move from ECS Fargate to Lambda (the rules engine state needs warm containers)
- Don't migrate from Streamlit to a custom React app for v1 — Streamlit is a feature, not a bug, for analyst workflows

## Non-negotiables

- **Keep the rules-vs-LLM split.** The deterministic rules engine is the spine; the LLM provides analyst-grade narrative on top. Don't collapse them — that's what differentiates this from a black-box ML approach.
- **Bedrock Agent uses `RETURN_CONTROL`.** The agent calls the MCP server through action groups; the MCP server is the executor. Don't switch to direct Lambda action groups.
- **Audit log every transaction-level decision.** Your compliance team will ask "why was this flagged?" — every flagged transaction must have a rule trace + LLM rationale in the audit log.
- **Sample data stays sample data.** The `data/pharmacy/` and `data/generic/` datasets you generate must be synthetic. Never deploy with real transaction data committed to the repo.

## Defaults

- **Model:** `anthropic.claude-3-sonnet-20240229-v1:0` (the spec's default). Claude 3.5 Sonnet upgrade is your decision, based on your model access.
- **Region:** us-east-1 (spec default). You can deploy to any region with Bedrock + ECS + ALB availability.
- **Stack name:** `fraud-detection-bedrock-agent` (master) + child stacks for VPC, ECS, ALB, MCP service. Don't merge them into one mega-stack — the separation is intentional.

## Things to confirm before customizing

- Which rules domain? (FSI AML / healthcare claims FWA / insurance / generic payment integrity)
- Existing rules engine to import patterns from?
- Your transaction volume — drives ECS task count and ALB sizing
- Your existing analyst workflow — drives Streamlit UI customization
- Compliance / regulatory requirements for the audit trail
- Whether OFAC / sanctions screening needs to be added (not in the kit today)

## When to flag back

- You want the agent to auto-block transactions (this is decision-support; auto-block is a different threat model)
- You want real-time inline scoring (this kit is batch-analysis-flavored, not transaction-time)
- You want on-prem deployment (kit is cloud-native ECS+ALB+Bedrock)
- Real transaction data appears in commits (PHI/PCI exposure — different threat model)

## Done definition

The build is done when:
- Master CFN stack deploys clean, child stacks all `CREATE_COMPLETE`
- MCP server health endpoint returns 200 from the ALB
- Bedrock Agent test in console returns a fraud narrative for the sample query
- Streamlit UI loads, runs an analysis, and shows both rule fires + LLM summary
- Your analysts can run a session end-to-end without assistance
