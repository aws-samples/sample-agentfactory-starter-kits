# Dental Front-Desk Agent

> **Status:** Draft · Spec-only blueprint (build it from this kit's contract) · Build level: Custom IaC

An AI front-desk agent for dental practices. A patient sends a message ("I need to move my cleaning to next week," "Do you take Delta Dental PPO?"); a **router agent** classifies intent and delegates to a **Scheduling** or **Insurance** specialist agent, or answers general practice questions directly and escalates to a human when it can't help. The agents run on **Amazon Bedrock AgentCore** with **Claude (Sonnet 4.5)** via the Strands SDK, constrained by HIPAA-safe language rules and **Bedrock Guardrails**. Every interaction is traced, scored against four quality rubrics by an LLM-as-a-judge evaluation pipeline, and surfaced to practice managers in a **React dashboard** with latency, token, hallucination-rate, and alert views.

## Why this exists

Dental front desks are interrupt-driven: staff juggle in-office patients while routine calls — book a cleaning, reschedule, "is my plan accepted?" — pile up, and after-hours calls go to voicemail or a paid answering service that can't actually book anything. The work is high-volume, repetitive, and policy-bound (office hours, accepted insurance, cancellation rules), which makes it a good fit for an agent — *if* it stays on-script, never volunteers clinical or PHI details it shouldn't, and a manager can see whether it's doing a good job. This kit's thesis is that a router-plus-specialist agent handles the routine front-desk load while a built-in observability and quality-evaluation pipeline makes that automation auditable, per practice, instead of an unmonitored black box.

## How to use this kit

This kit is a blueprint: it contains the architecture, the build contract, and acceptance tests — but **not** the agent's source code. No source is included; the system is built from the spec. Read [`AGENTS.md`](AGENTS.md) + [`build-spec/`](build-spec/) and have a coding agent (Kiro / Claude Code / Cursor / Codex) implement the pattern in your own AWS account against your data and integrations.

**What the spec targets:** a monorepo of eight packages (agents, mock services, observability, evaluations, dashboard API + UI) with four CloudFormation stacks. Mock scheduling/insurance/reminder services let you demo the full loop on synthetic data before wiring real systems.

## What this kit gives you

| File | What's in it |
|---|---|
| [`kit.json`](kit.json) | Kit manifest — services, model, outcomes, ideal customer, ROI scaffolding |
| [`architecture/architecture.md`](architecture/architecture.md) | The stack, a component diagram, data flow (happy + escalation/fallback paths), audit trail |
| [`business-case/roi-framework.md`](business-case/roi-framework.md) | ROI math template, cost drivers, objection handling, competitive framing |
| [`AGENTS.md`](AGENTS.md) | Build contract for a coding agent re-implementing or customizing the kit |
| [`build-spec/`](build-spec/) | Requirements, architecture decisions, deployment spec, acceptance tests |

## Shared responsibility

This is an accelerator and a working reference, not a managed service. You own the deployed agents, the prompts and guardrail config, the evaluation rubrics and thresholds, the patient and practice data, and the AWS infrastructure in your account. The reference ships mock services and synthetic data in a demo/PoC posture — you and your team replace those with real integrations and harden security (auth, encryption, retention, formal HIPAA review) before production. The agent is front-desk support with human escalation; it does not give clinical advice, and the practice owns every booking and coverage decision. Deploy scripts and CloudFormation are provided as-is.
