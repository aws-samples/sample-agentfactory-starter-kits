"""Route Ticket - Bedrock Agent Action Group Lambda

Routes a classified ticket to the appropriate support team with enriched context.
"""

import json
import os
from urllib.parse import urlparse

import requests

WEBHOOK_URL = os.environ.get("WEBHOOK_URL", "")

# Routing rules: maps (category, complexity) to team
ROUTING_RULES = {
    ("bug", "engineering"): "engineering",
    ("bug", "L2"): "engineering",
    ("bug", "L1"): "l1-support",
    ("billing", "L1"): "billing-team",
    ("billing", "L2"): "billing-team",
    ("access", "L1"): "l1-support",
    ("access", "L2"): "l2-support",
    ("feature_request", "L1"): "product-team",
    ("feature_request", "L2"): "product-team",
    ("feature_request", "engineering"): "product-team",
}

DEFAULT_TEAM = "l2-support"


def route(ticket_id: str, category: str, priority: str, complexity: str, context_summary: str) -> dict:
    """Determine routing and send to ticket system."""
    team = ROUTING_RULES.get((category, complexity), DEFAULT_TEAM)

    # P1 always goes to engineering on-call
    if priority == "P1":
        team = "engineering-oncall"

    routing_decision = {
        "ticket_id": ticket_id,
        "assigned_team": team,
        "category": category,
        "priority": priority,
        "complexity": complexity,
        "context_summary": context_summary,
        "action": "routed",
    }

    # Post to webhook if configured
    if WEBHOOK_URL:
        parsed_url = urlparse(WEBHOOK_URL)
        if parsed_url.scheme not in ("https",):
            routing_decision["webhook_error"] = f"Unsupported URL scheme: {parsed_url.scheme}. Only HTTPS is allowed."
            return routing_decision

        try:
            response = requests.post(WEBHOOK_URL, json=routing_decision, timeout=10)
            response.raise_for_status()
        except Exception as e:
            routing_decision["webhook_error"] = str(e)

    return routing_decision


def lambda_handler(event, context):
    """Bedrock Agent action group handler."""
    parameters = {p["name"]: p["value"] for p in event.get("parameters", [])}

    result = route(
        ticket_id=parameters.get("ticket_id", "unknown"),
        category=parameters.get("category", "bug"),
        priority=parameters.get("priority", "P3"),
        complexity=parameters.get("complexity", "L2"),
        context_summary=parameters.get("context_summary", ""),
    )

    return {
        "messageVersion": "1.0",
        "response": {
            "actionGroup": event.get("actionGroup", "route-ticket"),
            "function": event.get("function", "route_ticket"),
            "functionResponse": {
                "responseBody": {
                    "TEXT": {"body": json.dumps(result)}
                }
            },
        },
    }
