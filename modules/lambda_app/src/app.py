"""
Visit-counter web app running on AWS Lambda.

  GET /        -> HTML page showing the environment name and a visit counter
                  (the counter is stored in DynamoDB)
  GET /health  -> JSON health check (does not touch the database)

All configuration comes from environment variables set by Terraform,
so the SAME code runs in dev and prod.
"""

import json
import logging
import os
from datetime import datetime, timezone

import boto3

LOG = logging.getLogger()
LOG.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

TABLE_NAME = os.environ["TABLE_NAME"]
ENVIRONMENT = os.environ.get("ENVIRONMENT", "unknown")
APP_VERSION = os.environ.get("APP_VERSION", "dev")
REGION = os.environ.get("AWS_REGION", "unknown")

# Created once per container and re-used across invocations (faster, cheaper).
TABLE = boto3.resource("dynamodb").Table(TABLE_NAME)

COLORS = {"dev": "#2563eb", "prod": "#16a34a"}


def _increment_counter() -> int:
    """Atomically add 1 to the counter and return the new value."""
    result = TABLE.update_item(
        Key={"pk": "visits"},
        UpdateExpression="ADD #c :one",
        ExpressionAttributeNames={"#c": "count"},
        ExpressionAttributeValues={":one": 1},
        ReturnValues="UPDATED_NEW",
    )
    return int(result["Attributes"]["count"])


def _html(count: int) -> str:
    color = COLORS.get(ENVIRONMENT, "#6b7280")
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{ENVIRONMENT.upper()} | Terraform Multi-Env Platform</title>
  <style>
    body {{ font-family: system-ui, sans-serif; margin: 0; min-height: 100vh;
           display: grid; place-items: center; background: #f8fafc; color: #0f172a; }}
    .card {{ background: #fff; border-radius: 16px; padding: 40px 48px; max-width: 480px;
            box-shadow: 0 10px 30px rgba(0,0,0,.08); text-align: center; }}
    .env {{ display: inline-block; padding: 6px 18px; border-radius: 999px; color: #fff;
           background: {color}; font-weight: 700; letter-spacing: .1em; }}
    .count {{ font-size: 64px; font-weight: 800; margin: 16px 0 0; }}
    dl {{ text-align: left; font-size: 14px; color: #475569; margin-top: 28px; }}
    dt {{ font-weight: 600; float: left; width: 110px; }}
    dd {{ margin: 0 0 6px 110px; }}
  </style>
</head>
<body>
  <div class="card">
    <span class="env">{ENVIRONMENT.upper()}</span>
    <h1>Terraform Multi-Env Platform</h1>
    <p>This page has been visited</p>
    <p class="count">{count}</p>
    <p>times in <strong>{ENVIRONMENT}</strong></p>
    <dl>
      <dt>Version</dt><dd>{APP_VERSION}</dd>
      <dt>Region</dt><dd>{REGION}</dd>
      <dt>Table</dt><dd>{TABLE_NAME}</dd>
      <dt>Served at</dt><dd>{now}</dd>
    </dl>
  </div>
</body>
</html>"""


def handler(event, context):
    path = event.get("rawPath", "/")
    LOG.info(json.dumps({"path": path, "env": ENVIRONMENT, "request_id": context.aws_request_id}))

    if path == "/health":
        return {
            "statusCode": 200,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"status": "ok", "environment": ENVIRONMENT, "version": APP_VERSION}),
        }

    if path != "/":
        return {"statusCode": 404, "headers": {"Content-Type": "text/plain"}, "body": "Not found"}

    try:
        count = _increment_counter()
    except Exception:  # noqa: BLE001 - log the full error, return a safe message
        LOG.exception("DynamoDB update failed")
        return {"statusCode": 503, "headers": {"Content-Type": "text/plain"}, "body": "Service unavailable"}

    return {
        "statusCode": 200,
        "headers": {
            "Content-Type": "text/html; charset=utf-8",
            "Cache-Control": "no-store",
            "X-Content-Type-Options": "nosniff",
            "X-Frame-Options": "DENY",
            "Strict-Transport-Security": "max-age=31536000",
        },
        "body": _html(count),
    }
