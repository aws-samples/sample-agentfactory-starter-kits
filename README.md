# AgentFactory Starter Kits

**Blueprints for building vertical AI agents on AWS.** Each kit is a complete, opinionated specification for a production-oriented AI agent that solves a specific industry problem on [Amazon Bedrock](https://aws.amazon.com/bedrock/) — the reference architecture, the build contract, the acceptance tests, and the business case.

## Read this first: these kits are specs, not code drops

Most kits in this repo **do not contain the agent's source code.** A kit is the design and the contract: it tells you (and your coding agent) exactly what to build, why each architectural choice was made, and how to verify the result — then you implement it in your own AWS account.

That's deliberate. These patterns get adapted to your data, your schemas, your compliance posture, and your integrations anyway; the durable value is in the architecture and the decision rationale, not in a fork of someone else's repo. Modern coding agents (Kiro, Claude Code, Cursor, Codex) can implement a well-specified agent quickly, and `AGENTS.md` + `build-spec/` are written to be handed directly to one.

Concretely, here's what ships in this repo:

| | Kits | What you get |
|---|---|---|
| **Spec only** | 17 kits | Architecture + build contract + acceptance tests. You implement it. |
| **Ships working code** | `intelligent-ticket-triage` | CloudFormation template, Lambda action groups, system prompt, one-command deploy. |
| **Points to public source** | `manufacturing-operations-hub` | Spec plus a clone-and-adapt path to an MIT-licensed AWS sample repo. |

If you were expecting `git clone && deploy` for every kit, that's not what this is. Start with `intelligent-ticket-triage` or `manufacturing-operations-hub` if you want running code fastest.

## What's in a kit

```
<kit-id>/
├── kit.json                  ← Machine-readable manifest (services, model, outcomes, ROI, ideal customer)
├── README.md                 ← The problem, outcomes, what you customize, how to use the kit
├── AGENTS.md                 ← Build contract: hand this to your coding agent first
├── architecture/             ← Reference architecture, component breakdown, data flow
├── build-spec/               ← requirements · architecture-decisions · deployment-spec · acceptance-tests
└── business-case/            ← ROI model and value narrative
```

`intelligent-ticket-triage` is the exception: instead of `build-spec/` it ships the real thing — `infrastructure/` (CloudFormation template, config example, deploy script) and `src/` (system prompt and Lambda tools).

The four `build-spec/` files are the core of the contract:

- **`requirements.md`** — what the agent must do, functionally and non-functionally
- **`architecture-decisions.md`** — why these choices, and what not to reverse
- **`deployment-spec.md`** — the AWS resources to create in your account
- **`acceptance-tests.md`** — the test matrix the finished build must pass

## How to use a kit

```bash
# 1. Clone this repo and pick a kit
git clone <this-repo-url>
cd agentfactory-starter-kits/<kit-id>

# 2. Read the contract, in this order
#    README.md                        → the problem and the shape of the solution
#    AGENTS.md                        → the build contract
#    build-spec/requirements.md       → what to build
#    build-spec/architecture-decisions.md → why, and what not to change
#    build-spec/deployment-spec.md    → what to create in your AWS account
#    build-spec/acceptance-tests.md   → how to prove it works

# 3. Hand the kit to your coding agent
#    e.g. open this folder in Kiro / Claude Code / Cursor and ask it to
#    implement the agent per AGENTS.md and build-spec/

# 4. Deploy into your own AWS account, then run the acceptance tests
```

## Build levels

Each kit declares a `buildLevel` in `kit.json` describing how much infrastructure you own:

| Build level | Best for | What you deploy |
|---|---|---|
| **Managed harness** | Value is in the prompt + tools + knowledge base | A lightweight agent harness on Amazon Bedrock AgentCore |
| **Custom IaC** | Teams that want the full, auditable stack | Complete infrastructure-as-code (Bedrock Agents/AgentCore + Knowledge Bases + Guardrails + Lambda + supporting services) |

## Catalog

| Kit | Vertical | Build Level | Ships |
|---|---|---|---|
| Intelligent Ticket Triage | Software & Internet | Custom IaC (Bedrock Agents + KB + Guardrails) | **Code** |
| Manufacturing Operations Hub | Manufacturing & Industrial | Managed Harness (Strands + Streamlit) | **Public source** |
| Agentic Insurance Advisor | Financial Services | Custom IaC (Multi-Agent + KB + React UI) | Spec |
| Agentic PXM Platform | Retail & Consumer | Custom IaC (CDK: Step Functions HITL + AgentCore) | Spec |
| Automated Docs Generator | Cross-vertical | Custom IaC (ECS Fargate + Nova Act + Bedrock) | Spec |
| BriefMe Sales Brief Generator | Cross-vertical | Custom IaC (AgentCore + Nova Premier Web Grounding) | Spec |
| Clinical Documentation Agent | Healthcare & Life Sciences | Managed Harness (AgentCore + Amazon Connect Health) | Spec |
| Clinical Trial Site Lookup | Healthcare & Life Sciences | Managed Harness (AgentCore) | Spec |
| Code Intelligence Agent | Software & Internet | Custom IaC (SAM: MCP Lambda + Bedrock + Guardrails) | Spec |
| Field Technician Dispatch Agent | Cross-vertical | Custom Stack (Strands + FastAPI + React) | Spec |
| Intelligent Claims Triage | Financial Services | Custom IaC (CDK: AgentCore + Textract + DynamoDB) | Spec |
| Internal Knowledge Q&A | Cross-vertical | Managed Harness (AgentCore) | Spec |
| Dental Front-Desk Agent | Healthcare | Custom IaC (AgentCore + Guardrails + Eval Pipeline) | Spec |
| Payment Fraud Detector | Financial Services | Custom IaC (Bedrock Agent + MCP Server + Streamlit) | Spec |
| Scalable Claude Code on AWS Batch | Software & Internet | Custom IaC (AWS Batch + Fargate/EC2 Spot + CDK) | Spec |
| Sentinel Auto-Loan Fraud Detection | Financial Services | Custom IaC (Multi-Agent FastAPI + React on App Runner) | Spec |
| TriageAI Patient Triage | Healthcare | Custom IaC (FastAPI + React + Bedrock Converse) | Spec |
| TropiCraft Ordering Agent | Retail & Consumer | Custom IaC (CDK: Bedrock tool-use + Lambda + voice) | Spec |
| XML Schema Inference Agent | Cross-vertical | Custom IaC (CDK: Bedrock Agent + Lambda + Redshift) | Spec |

Kits carry a `status` in `kit.json`. `draft` means the spec is complete but hasn't been validated end to end by a finished build; `published` means it has.

## Prerequisites

- An AWS account with access to **Amazon Bedrock** and the model(s) the kit uses (enable model access in the Bedrock console for your region)
- **AWS CLI v2**, configured with credentials (`aws configure`)
- The IaC toolchain the kit's `deployment-spec.md` calls for — typically CloudFormation, the **AWS CDK**, or **AWS SAM CLI**
- Language runtimes per kit (typically **Python 3.11+** and/or **Node.js 18+**)
- A coding agent is strongly recommended for the spec-only kits

## Cost & responsibility

- **Implementing a kit deploys real, billable AWS resources** (Bedrock invocations, Lambda, storage, vector stores, and more) into *your* account. Review the kit's architecture and the [AWS Pricing Calculator](https://calculator.aws/) before deploying, and tear down stacks you're not using.
- The ROI figures in each kit's `business-case/` are **illustrative models with stated assumptions**, not guarantees. Re-run them with your own numbers.
- Kits are provided **as-is, without warranty**. You own the infrastructure, configuration, and data in your account.
- A kit is a starting point, not a compliance-certified product. **Review security, data handling, guardrails, and regulatory requirements** (e.g. PII/PHI handling) for your own use case before production. Several kits deliberately keep a human in the loop for consequential decisions — preserve that.

## Repository layout

```
agentfactory-starter-kits/
├── README.md                 ← You're here
├── LICENSE                   ← MIT-0
├── schemas/
│   └── kit.schema.json       ← Manifest schema every kit.json validates against
├── scripts/
│   └── validate-kits.py      ← Validates all manifests against the schema
└── <kit-id>/                 ← One folder per starter kit (see "What's in a kit")
```

### Validating manifests

Every `kit.json` is validated against [`schemas/kit.schema.json`](schemas/kit.schema.json):

```bash
python3 -m venv .venv && .venv/bin/pip install jsonschema
.venv/bin/python scripts/validate-kits.py
```

Run this after editing any manifest; it exits non-zero if a kit is invalid.

## License

Licensed under MIT-0 (MIT No Attribution) — see [`LICENSE`](LICENSE). You can use, modify, and deploy these kits without attribution. They are provided as-is, without warranty.