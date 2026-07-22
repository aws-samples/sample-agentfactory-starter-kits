"""Classify Ticket - Bedrock Agent Action Group Lambda

Analyzes ticket text and metadata to determine category, priority, and complexity.
Uses the Knowledge Base for context on similar historical tickets.
"""

import json
import os
import boto3

bedrock_agent = boto3.client("bedrock-agent-runtime")
KNOWLEDGE_BASE_ID = os.environ.get("KNOWLEDGE_BASE_ID", "")
CONFIDENCE_THRESHOLD = float(os.environ.get("CONFIDENCE_THRESHOLD", "0.9"))

CATEGORY_KEYWORDS = {
    "bug": ["error", "broken", "crash", "fail", "not working", "500", "exception", "down"],
    "billing": ["invoice", "charge", "payment", "subscription", "refund", "plan", "upgrade"],
    "access": ["login", "password", "permission", "locked", "access denied", "sso", "mfa", "cannot log in"],
    "feature_request": ["would be nice", "feature", "suggestion", "wish", "add support for", "roadmap"],
}

PRIORITY_SIGNALS = {
    "P1": ["down", "outage", "data loss", "security breach", "production", "critical"],
    "P2": ["broken", "cannot use", "blocking", "major", "urgent"],
    "P3": ["minor", "cosmetic", "workaround", "low priority"],
    "P4": ["question", "how to", "wondering", "curious", "documentation"],
}


def retrieve_similar_tickets(ticket_text: str) -> list:
    """Query KB for similar historical tickets."""
    if not KNOWLEDGE_BASE_ID:
        return []
    try:
        response = bedrock_agent.retrieve(
            knowledgeBaseId=KNOWLEDGE_BASE_ID,
            retrievalQuery={"text": ticket_text},
            retrievalConfiguration={"vectorSearchConfiguration": {"numberOfResults": 3}},
        )
        return [r["content"]["text"] for r in response.get("retrievalResults", [])]
    except Exception:
        return []


def classify(ticket_text: str, customer_tier: str, product_area: str) -> dict:
    """Rule-based classification enhanced with KB context."""
    text_lower = ticket_text.lower()

    # Category detection
    category_scores = {}
    for cat, keywords in CATEGORY_KEYWORDS.items():
        score = sum(1 for kw in keywords if kw in text_lower)
        category_scores[cat] = score
    category = max(category_scores, key=category_scores.get) if any(category_scores.values()) else "bug"

    # Priority detection
    priority = "P3"
    for p, signals in PRIORITY_SIGNALS.items():
        if any(s in text_lower for s in signals):
            priority = p
            break

    # Complexity assessment
    similar_tickets = retrieve_similar_tickets(ticket_text)
    has_documented_fix = len(similar_tickets) > 0

    if has_documented_fix and priority in ("P3", "P4"):
        complexity = "auto-resolvable"
        confidence = min(0.95, 0.7 + (len(similar_tickets) * 0.1))
    elif priority == "P1":
        complexity = "engineering" if category == "bug" else "L2"
        confidence = 0.85
    elif category in ("billing", "access") and priority in ("P3", "P4"):
        complexity = "L1"
        confidence = 0.8
    else:
        complexity = "L2"
        confidence = 0.75

    # Enterprise customers get more conservative routing
    if customer_tier == "enterprise" and complexity == "auto-resolvable":
        confidence -= 0.05

    return {
        "category": category,
        "priority": priority,
        "complexity": complexity,
        "confidence": round(confidence, 2),
        "similar_tickets_found": len(similar_tickets),
    }


def lambda_handler(event, context):
    """Bedrock Agent action group handler."""
    parameters = {p["name"]: p["value"] for p in event.get("parameters", [])}
    ticket_text = parameters.get("ticket_text", "")
    customer_tier = parameters.get("customer_tier", "business")
    product_area = parameters.get("product_area", "general")

    result = classify(ticket_text, customer_tier, product_area)

    return {
        "messageVersion": "1.0",
        "response": {
            "actionGroup": event.get("actionGroup", "classify-ticket"),
            "function": event.get("function", "classify_ticket"),
            "functionResponse": {
                "responseBody": {
                    "TEXT": {"body": json.dumps(result)}
                }
            },
        },
    }
