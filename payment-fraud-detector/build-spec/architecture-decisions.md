# Architecture Decisions — Payment Fraud Detector

Decisions made up front so the coding agent doesn't re-litigate them mid-build.

## AD1: Build level = `custom-iac`

**Decision:** Custom CloudFormation, not AgentCore Managed Harness.

**Why.** The kit's value is in the *combination* of rules engine + Bedrock Agent + Streamlit UI + ECS+ALB infrastructure. AgentCore Managed Harness handles the agent runtime but doesn't help with the MCP server, Streamlit, ECS, or ALB pieces — all of which are essential. We need explicit IaC anyway, so custom-iac is the right level.

If we move to AgentCore Managed Harness later, we'd lose visibility into the action-group executor pattern and the MCP server architecture that's the kit's differentiator.

## AD2: Rules engine + LLM analyst — separated, not merged

**Decision:** The deterministic rules engine and the LLM analyst layer are separate components. Rules fire first; LLM narrates over the rule output.

**Why.** Three reasons:

1. **Speed and cost.** Rules run in ~35 ms per transaction in pure Python. Every-transaction-through-Claude is 100x slower and 100x more expensive. Rules triage; LLM analyzes the triaged subset.
2. **Auditability.** Compliance teams accept deterministic rules. They don't accept "the model decided." This split lets the auditable rules be the spine.
3. **Trust.** Most enterprise model risk teams won't approve LLM-as-decider in fraud. LLM-as-explainer is much easier to ship.

**What this means for the build.** Don't refactor to "Claude calls the rules as just another tool." The rules engine is the spine, not a tool.

## AD3: Bedrock Agent action groups via RETURN_CONTROL

**Decision:** The Bedrock Agent calls the rules engine via action groups with `RETURN_CONTROL` executor. The MCP server is the executor. Direct Lambda action groups are not used.

**Why.** RETURN_CONTROL gives us full control over the rules-engine invocation — we can add caching, batching, multi-rule orchestration, response shaping. Direct Lambda would couple us to Lambda's container model and 15-minute execution limit, which doesn't fit ECS Fargate's stateful rules engine.

## AD4: ECS Fargate, not Lambda, for the MCP server

**Decision:** MCP server runs on ECS Fargate behind ALB, not Lambda.

**Why.** Three reasons:
1. **Warm state.** The rules engine loads transaction data + reference data into memory at startup. Lambda's cold-start would re-load on every cold invocation.
2. **Concurrency.** Multiple analysts running concurrent sessions need independent stateful containers; Lambda's per-invocation isolation makes shared caches awkward.
3. **Familiar deployment.** Most enterprise teams know ECS+ALB. Lambda + API Gateway is fine but is a less-familiar pattern for fraud-ops teams.

**Alternatives considered.** EKS (overkill — kit doesn't need K8s), App Runner (less granular control of networking), Lambda + API Gateway (cold start + state issues).

## AD5: Streamlit, not a custom React frontend

**Decision:** Analyst UI is Streamlit, not a custom React/Vue app.

**Why.** Streamlit is a feature for analyst workflows: data scientists / fraud analysts already know it; component model is lightweight; deployment is one Docker container; no need for a separate frontend team. Custom React is a 5-week build for marginal UX gain.

**When to deviate.** If you want the agent embedded in your existing analyst portal (e.g., Salesforce, custom internal app), the LLM + rules backend can be exposed via API and the frontend swapped out.

## AD6: Claude 3 Sonnet (the spec's default)

**Decision:** `anthropic.claude-3-sonnet-20240229-v1:0` as default. You can upgrade to Claude 3.5 Sonnet via inference profile.

**Why.** The reference agent was built and demoed with Claude 3 Sonnet. Production-tested. Stable Bedrock GA. Cost is reasonable for analyst-session volumes.

**When to upgrade.** Sonnet 4.5 if your narratives need more complex multi-rule reasoning. Haiku if you are high-volume and accept shorter narratives. Don't ship a different default without a concrete reason.

## AD7: Multi-stack CloudFormation

**Decision:** Master stack + 5 child stacks (`vpc-network`, `ecs-cluster`, `mcp-server-infrastructure`, `mcp-ecs-service`, `bedrock-agent`). Don't merge into one stack.

**Why.** Enterprise teams expect separable concerns. VPC team owns the network stack, platform team owns ECS, application team owns the agent stack. Merging makes ownership boundaries fuzzy and slows down updates.

## AD8: Decision-support only — no auto-block

**Decision:** The agent surfaces and explains. Humans decide whether to block. No auto-action of any kind.

**Why.** Auto-block requires a much stricter risk posture: legal liability, customer impact (false-block of a legitimate transaction), regulatory consideration. The kit is decision-support; auto-action is a separate engagement with separate guardrails.

## AD9: Synthetic test data, not real transaction data

**Decision:** The repo ships with synthetic data in `data/pharmacy/` and `data/generic/`. Real transaction data lives in your S3 bucket, never in the repo.

**Why.** Real transaction data is PHI/PCI/regulated in most verticals. Committing it to the repo (or copying one organization's data into a shared kit folder) creates compliance exposure for everyone using the kit.

## AD10: HTTPS-only, ALB termination

**Decision:** All traffic to the ALB is HTTPS (TLS 1.2+). HTTP redirects to HTTPS. ALB terminates TLS; back-end traffic to ECS tasks is HTTP within the VPC.

**Why.** Standard enterprise expectation. The source's `infrastructure/enable-https.sh` handles cert provisioning via ACM.

## AD11: VPC private subnets for compute

**Decision:** ECS tasks (Streamlit + MCP server) run in private subnets. ALB is the only public-facing component.

**Why.** Defense-in-depth. Even if a container is compromised, it can't be reached directly from the internet — only via the ALB.
