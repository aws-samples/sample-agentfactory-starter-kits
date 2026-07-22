# Internal Knowledge Q&A

> **Status: Draft — Path B (spec-only).** This kit ships as a build contract: AGENTS.md + build-spec/ tells a coding agent how to implement it. You build it in your AWS account, then bump status to `published`.

A **retrieval-grounded Q&A agent** that answers employee questions from the company's own internal documentation. Wikis, runbooks, policy docs, HR handbooks, engineering specs, SOPs — whatever you already have but no one can find quickly.

The agent retrieves; it doesn't author. Every answer cites its source. When the documentation doesn't have the answer, the agent says so instead of fabricating one.

## Why this exists

Most companies past 100 employees have the documentation problem in some form: information exists but is invisible. Senior engineers, HR partners, and ops leads spend a meaningful fraction of every day answering questions whose answers are already written down somewhere. Wiki search bars are notoriously bad. Slack channels like `#ask-eng` and `#ask-hr` become low-value support queues that erode senior capacity.

This kit gives them a lookup agent grounded in your own corpus, surfaced through Slack / web chat / Teams, with a hard rule: cite or decline.

---

## How it applies across verticals

This is the *same kit* with different documents in the Knowledge Base. Same architecture, same guardrails, same shared-responsibility contract — just point it at your own corpus.

Jump to: [Software & Internet](#software--internet) · [Healthcare](#healthcare) · [Financial Services](#financial-services) · [Manufacturing](#manufacturing)

### Software & Internet

**The pain.** A 500-engineer SaaS company has 12,000 Confluence pages, 4,000 GitHub wikis, and a years-old internal docs site. Onboarding takes 4–6 weeks because new hires can't find the runbook for service X or the on-call rotation for team Y. Senior engineers field ~10 "where do I find this?" Slack pings per day, each one breaking flow for 5–15 minutes.

**The kit.** Connect Confluence, GitHub wikis, and the internal docs S3 bucket to the Knowledge Base. Surface the agent in the company's existing Slack workspace as a slash command. New hires ask `/ask "how do I deploy service X to staging?"` and get a cited answer pointing to the runbook. Senior engineers stop being human routers.

**Sample question:** *"What's the on-call rotation for the payments team and how do I page them?"* → Cited answer linking to the runbook + PagerDuty docs.

### Healthcare

**The pain.** A regional health system has thousands of clinical SOPs, compliance policies, IT runbooks, and HR documents spread across SharePoint, network shares, and a paper-era policy library. Front-line staff (nurses, billing teams, schedulers) routinely escalate "what's the policy on X?" questions to managers who have to look it up themselves. HIPAA training updates lag because no one finds the new policy until they need to cite it.

**The kit.** Index the (non-PHI) policy library, IT runbooks, and HR handbook into the Knowledge Base. Deploy guardrails that explicitly refuse PHI inputs and stay in policy/admin lane only — no clinical advice, no PHI lookup. Surface in the staff intranet portal. Authentication ties to your IdP (Okta / Azure AD) so role-based access is preserved at the document layer.

**Sample question:** *"What's our infection control policy for visitor screening during flu season?"* → Cited answer pulled from the current policy document, with a link to the source for verification.

**Note on PHI:** This kit is for non-PHI documents (policies, SOPs, runbooks). Patient data lookup is a different kit with a different threat model — do not extend this one to handle PHI without a security review.

### Financial Services

**The pain.** A mid-market broker-dealer has 800+ compliance policies, trading procedures, KYC runbooks, and client-onboarding checklists. New advisors take 6+ months to become independently productive because every "what's the policy on X?" question goes to compliance officers who have a backlog. Audit prep is a manual scavenger hunt every year.

**The kit.** Index the policy library, compliance manual, and standard operating procedures into the Knowledge Base. Deploy strict guardrails: no investment advice, no client-specific responses, citations required, escalation language for anything ambiguous. Surface in the firm's web portal behind SSO so audit logs show who asked what. Compliance officers gain back hours; advisors get faster ramp.

**Sample question:** *"What's the policy on accepting gifts from clients during the holiday season?"* → Cited answer from the firm's compliance manual, with the exact policy section and last-revised date.

**Note on regulatory exposure:** Configure guardrails to refuse anything that crosses into investment advice, client-specific recommendations, or unverified compliance interpretation. The agent answers what's in the firm's documents, nothing more.

### Manufacturing

**The pain.** A 2,000-person manufacturing company has equipment manuals, safety SOPs, troubleshooting guides, and shift handoff documents in a mix of PDFs, OEM portals, and paper binders. New technicians spend your first 90 days asking senior techs basic questions about specific machines. Equipment downtime is 30% longer than necessary because the troubleshooting steps for less-common faults are buried in 800-page manuals nobody reads cover to cover.

**The kit.** Index the (digitized, OCR-extracted) equipment manuals, safety SOPs, and troubleshooting trees into the Knowledge Base. Surface the agent on shop-floor tablets and in the maintenance ticketing system. Technicians can ask questions in natural language during a service call — "Line 4 conveyor is throwing fault code E-237, what's the troubleshooting sequence?" — and get cited answers from the manual without leaving the work order.

**Sample question:** *"What's the lockout-tagout procedure for the laser cutter on Line 7?"* → Cited answer from the safety SOP, with the exact step sequence and the last date the SOP was reviewed.

**Note on extraction quality:** This kit assumes your documents are machine-readable. PDFs of scanned paper manuals need OCR preprocessing before they go into the Knowledge Base. Plan extra time on the build for ingestion if the corpus is paper-era.

---

## What's in this kit

| File | What it tells you |
|---|---|
| [`kit.json`](kit.json) | Kit manifest — services, model, outcomes, ideal customer, ROI scaffolding |
| [`AGENTS.md`](AGENTS.md) | The build contract for a coding agent (Kiro / Claude Code / Codex / Cursor) |
| [`build-spec/requirements.md`](build-spec/requirements.md) | What the agent must do |
| [`build-spec/architecture-decisions.md`](build-spec/architecture-decisions.md) | Why we picked managed-harness, KB strategy, model |
| [`build-spec/deployment-spec.md`](build-spec/deployment-spec.md) | What gets deployed in your account |
| [`build-spec/acceptance-tests.md`](build-spec/acceptance-tests.md) | Tests the build must pass before being marked `published` |
| [`architecture/architecture.md`](architecture/architecture.md) | The reference architecture diagram + components |
| [`business-case/roi-framework.md`](business-case/roi-framework.md) | ROI scaffolding you fill in for your deployment |

This kit is an **accelerator, not a managed service**. Once deployed, you own the agent, the AWS infrastructure, and the data in your account. Scripts are provided "as-is" — AWS does not commit to ongoing maintenance.
