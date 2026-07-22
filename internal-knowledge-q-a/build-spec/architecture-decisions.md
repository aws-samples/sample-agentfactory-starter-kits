# Architecture Decisions — Internal Knowledge Q&A

Decisions made up front so the coding agent doesn't re-litigate them mid-build.

## AD1: Build level = `managed-harness`

**Decision:** AgentCore Managed Harness, not Bedrock Managed Agents (OpenAI) or custom-iac.

**Why.** The value of this kit is in the prompt + retrieval contract + guardrails — not in custom infrastructure. AgentCore Managed Harness gives us the agent runtime, sandbox, memory, identity, and observability for free. We focus on the corpus, the prompt, and the channel integration.

Custom-iac would mean building the agent loop, monitoring, identity wiring, and runtime ourselves — wasted effort for a generic Q&A pattern. Bedrock Managed Agents (OpenAI) is in Limited Preview and is the right choice when you specifically want OpenAI frontier models on AWS, which isn't the case here.

## AD2: Model = Claude 3.5 Sonnet (Bedrock GA)

**Decision:** `anthropic.claude-3-5-sonnet-20241022-v2:0` as the default model. Override via `AGENTFACTORY_BEDROCK_MODEL_ID` if your account doesn't have access.

**Why.** Strong instruction-following on the cite-or-decline rule. Stable Bedrock GA. Reasonable cost-per-token for the workload (1–5K tokens per query average). If you need a smaller model for cost reasons, Haiku is the fallback; if they need stronger reasoning for complex policy interpretation, opt up to Sonnet 4.5 via inference profile.

**Alternatives considered.**
- Claude Haiku — 5–10x cheaper but weaker on the cite-or-decline contract. Acceptable for high-volume / low-stakes corpora; not the default.
- GPT-4 / GPT-4o (via OpenAI on Bedrock) — solid but pulls us into Limited Preview pathway. Use only when you specifically want OpenAI.
- Llama / Mistral — open-weights and cheaper but instruction-following on the citation contract is uneven. Not the default for an enterprise Q&A kit where fabrication risk is the central concern.

## AD3: Retrieval = Knowledge Bases (Titan Embed v2 + OpenSearch Serverless)

**Decision:** Use Bedrock Knowledge Bases for ingestion, chunking, embedding, and retrieval. Default vector store is OpenSearch Serverless.

**Why.** Native connectors for Confluence, SharePoint, S3, Salesforce, and Web Crawler cover the 80% case for internal docs. We skip the chunking/embedding/vector store glue code entirely.

**When to deviate:**
- You have an existing Aurora pgvector or Pinecone investment they want to reuse → KB supports those backends; pick what they have.
- Your corpus is under 10K chunks → consider just keeping it in a simpler store; the OpenSearch baseline cost may not be worth it.
- You have unusual document structure (long contracts, code-heavy runbooks) → custom chunking strategy via Knowledge Bases parser config.

## AD4: Single-tenant, no per-document ACLs

**Decision:** One organization, one corpus, one trust boundary. The agent retrieves from any document in the corpus; access control is enforced at the document-source level (e.g., Confluence space permissions).

**Why.** Per-document ACLs at the agent layer require row-level security on retrieval, group-aware queries, identity-aware citations, and a meaningfully more complex deployment. That's a different (larger) kit.

**What this means for you.** If document A should not be visible to user U, document A should not be in the Knowledge Base. The pattern is: only put documents in the corpus that any user of the agent is entitled to see.

## AD5: Channel = you pick one (Slack default)

**Decision:** Pick one channel surface for v1: Slack slash command (default), web chat embed, Teams app, or internal portal embed.

**Why.** Avoid scope creep by trying to be everywhere. Slack is the default because it's where most knowledge work happens; web embed is the natural second option. Adding more surfaces post-v1 is straightforward.

## AD6: System prompt enforces cite-or-decline

**Decision:** The system prompt is the primary enforcement mechanism for the citation contract. Guardrails on the output is the backup check.

**Why.** Models follow strong, explicit system prompts well. The system prompt explicitly states: "If you cannot ground your answer in the retrieved content, say 'I don't have a documented answer for that.' Do not synthesize an answer from general knowledge." Guardrails on the output run a citation-check as a defense-in-depth layer.

**What we're NOT doing.** Letting the model fall back to its training knowledge when the corpus comes up empty. That breaks the audit trail — you can no longer say "this answer came from our policies."

## AD7: No agent-side memory across sessions

**Decision:** Each session is independent. No persistent user-level memory.

**Why.** Persistent memory adds privacy questions ("does the agent remember that I asked about HR policy X last month?"), retention questions, and complexity for marginal usability gain in a Q&A pattern. Each query stands on its own.

## AD8: Audit logs go to CloudWatch with your KMS key

**Decision:** All query/response audit logs go to CloudWatch Logs encrypted with a customer-managed KMS key. Retention duration is your choice.

**Why.** The audit log is a compliance artifact for you. CloudWatch is the obvious AWS-native target. Customer-managed KMS gives you rotation/revocation control. Retention is policy-driven — varies wildly across organizations.

## AD9: No write actions in v1

**Decision:** The agent retrieves and answers only. It does not write to source systems, send emails, create tickets, or modify any data.

**Why.** Read-only is a much simpler threat model: the agent reveals information, it doesn't change state. Action-taking agents need different guardrails (can the action be undone? what happens if the agent acts on the wrong target?). Out of scope for v1.

## AD10: Cost monitoring is your responsibility, not the kit's

**Decision:** The kit provides per-query token / cost metrics on the CloudWatch dashboard but doesn't auto-throttle, auto-budget, or auto-cap.

**Why.** Cost throttling at the kit level would degrade the user experience unpredictably. Your FinOps team should set up cost alerts using AWS Budgets — that's the right tool, not the kit's job.
