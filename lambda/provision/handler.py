import base64
import ipaddress
import json
import os
import re
from datetime import datetime, timezone

import boto3


codebuild = boto3.client("codebuild")
ssm = boto3.client("ssm")

PROJECT_NAME = os.environ["PROJECT_NAME"]
CODEBUILD_PROJECT_NAME = os.environ["CODEBUILD_PROJECT_NAME"]
DEFAULT_ALLOWED_CIDR = os.environ.get("DEFAULT_ALLOWED_CIDR", "0.0.0.0/0")
VALID_TTLS = {2, 4, 8, 24}
ENV_NAME_PATTERN = re.compile(r"^[a-zA-Z0-9][a-zA-Z0-9-]{1,38}[a-zA-Z0-9]$")


def lambda_handler(event, context):
    try:
        payload = parse_payload(event)
        request_data = validate_payload(payload, event)
        created_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

        metadata = {
            "environment_name": request_data["environment_name"],
            "ttl_hours": request_data["ttl_hours"],
            "owner": request_data["owner"],
            "allowed_ssh_cidr": request_data["allowed_ssh_cidr"],
            "created_at": created_at,
            "status": "provision-requested",
        }
        ssm.put_parameter(
            Name=f"/{PROJECT_NAME}/environments/{request_data['environment_name']}",
            Type="String",
            Value=json.dumps(metadata, sort_keys=True),
            Overwrite=True,
        )

        build = codebuild.start_build(
            projectName=CODEBUILD_PROJECT_NAME,
            environmentVariablesOverride=[
                env("ACTION", "provision"),
                env("ENVIRONMENT_NAME", request_data["environment_name"]),
                env("TTL_HOURS", str(request_data["ttl_hours"])),
                env("OWNER", request_data["owner"]),
                env("CREATED_AT", created_at),
                env("ALLOWED_SSH_CIDR", request_data["allowed_ssh_cidr"]),
            ],
        )["build"]

        return response(202, {
            "message": "Provision build started",
            "environment_name": request_data["environment_name"],
            "build_id": build["id"],
            "build_arn": build["arn"],
            "created_at": created_at,
        })
    except ValueError as exc:
        return response(400, {"error": str(exc)})
    except Exception as exc:
        print(f"Unexpected error: {exc}")
        return response(500, {"error": "Internal server error"})


def parse_payload(event):
    params = dict(event.get("queryStringParameters") or {})
    body = event.get("body")
    if body:
        if event.get("isBase64Encoded"):
            body = base64.b64decode(body).decode("utf-8")
        try:
            params.update(json.loads(body))
        except json.JSONDecodeError as exc:
            raise ValueError("Request body must be valid JSON.") from exc
    return params


def validate_payload(payload, event):
    environment_name = str(payload.get("environment_name") or payload.get("env") or "").strip()
    if not ENV_NAME_PATTERN.match(environment_name):
        raise ValueError("environment_name must be 3-40 chars, alphanumeric or hyphen, and cannot start/end with hyphen.")

    try:
        ttl_hours = int(payload.get("ttl_hours"))
    except (TypeError, ValueError) as exc:
        raise ValueError("ttl_hours must be one of 2, 4, 8, or 24.") from exc
    if ttl_hours not in VALID_TTLS:
        raise ValueError("ttl_hours must be one of 2, 4, 8, or 24.")

    owner = str(payload.get("owner") or source_owner(event)).strip()
    owner = re.sub(r"[^a-zA-Z0-9_.@-]", "-", owner)[:64]
    if not owner:
        raise ValueError("owner could not be determined.")

    allowed_ssh_cidr = str(payload.get("allowed_ssh_cidr") or DEFAULT_ALLOWED_CIDR).strip()
    try:
        ipaddress.ip_network(allowed_ssh_cidr, strict=False)
    except ValueError as exc:
        raise ValueError("allowed_ssh_cidr must be a valid IPv4 or IPv6 CIDR.") from exc

    return {
        "environment_name": environment_name,
        "ttl_hours": ttl_hours,
        "owner": owner,
        "allowed_ssh_cidr": allowed_ssh_cidr,
    }


def source_owner(event):
    request_context = event.get("requestContext") or {}
    http = request_context.get("http") or {}
    return http.get("sourceIp") or "api-caller"


def env(name, value):
    return {"name": name, "value": value, "type": "PLAINTEXT"}


def response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {"content-type": "application/json"},
        "body": json.dumps(body),
    }

