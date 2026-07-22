"""Resolve Ticket - Bedrock Agent Action Group Lambda

Auto-resolves a ticket by sending a KB-grounded response back to the ticket source.
Falls back to routing if confidence is insufficient.
"""

import json
import os
from urllib.parse import urlparse

import requests

WEBHOOK_URL = os.environ.get("WEBHOOK_URL", "")
CONFIDENCE_THRESHOLD = float(os.environ.get("CONFIDENCE_THRESHOLD", "0.9"))
KNOWLEDGE_BASE_ID = os.environ.get("KNOWLEDGE_BASE_ID", "")


def resolve(ticket_id: str, ticket_text: str, resolution_text: str, confidence: float) -> dict:
    """Validate confidence and send resolution or escalate."""
    if confidence < CONFIDENCE_THRESHOLD:
        return {
            "ticket_id": ticket_id,
            "action": "escalated",
            "reason": f"Confidence {confidence} below threshold {CONFIDENCE_THRESHOLD}",
        }

    resolution = {
        "ticket_id": ticket_id,
        "action": "auto-resolved",
        "confidence": confidence,
        "response_sent": resolution_text,
    }

    # Post resolution to ticket source
    if WEBHOOK_URL:
        parsed_url = urlparse(WEBHOOK_URL)
        if parsed_url.scheme not in ("https",):
            resolution["webhook_error"] = f"Unsupported URL scheme: {parsed_url.scheme}. Only HTTPS is allowed."
            return resolution

        payload = {
            "ticket_id": ticket_id,
            "status": "resolved",
            "comment": resolution_text,
            "internal_note": f"Auto-resolved by triage agent (confidence: {confidence})",
        }
        try:
            response = requests.post(WEBHOOK_URL, json=payload, timeout=10)
            response.raise_for_status()
        except Exception as e:
            resolution["webhook_error"] = str(e)

    return resolution


def lambda_handler(event, context):
    """Bedrock Agent action group handler."""
    parameters = {p["name"]: p["value"] for p in event.get("parameters", [])}

    confidence = float(parameters.get("confidence", "0"))
    result = resolve(
        ticket_id=parameters.get("ticket_id", "unknown"),
        ticket_text=parameters.get("ticket_text", ""),
        resolution_text=parameters.get("resolution_text", ""),
        confidence=confidence,
    )

    return {
        "messageVersion": "1.0",
        "response": {
            "actionGroup": event.get("actionGroup", "resolve-ticket"),
            "function": event.get("function", "resolve_ticket"),
            "functionResponse": {
                "responseBody": {
                    "TEXT": {"body": json.dumps(result)}
                }
            },
        },
    }
