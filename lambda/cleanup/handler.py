import json
import os
from datetime import datetime, timedelta, timezone

import boto3


codebuild = boto3.client("codebuild")
ec2 = boto3.client("ec2")
sns = boto3.client("sns")
ssm = boto3.client("ssm")

PROJECT_NAME = os.environ["PROJECT_NAME"]
CODEBUILD_PROJECT_NAME = os.environ["CODEBUILD_PROJECT_NAME"]
DEFAULT_ALLOWED_CIDR = os.environ.get("DEFAULT_ALLOWED_CIDR", "127.0.0.1/32")
SNS_TOPIC_ARN = os.environ["SNS_TOPIC_ARN"]
NOTIFICATION_LEAD_MINUTES = int(os.environ.get("NOTIFICATION_LEAD_MINUTES", "30"))


def lambda_handler(event, context):
    now = datetime.now(timezone.utc)
    environments = discover_environments()

    results = {
        "checked_at": now.isoformat(),
        "project": PROJECT_NAME,
        "environment_count": len(environments),
        "warnings_sent": [],
        "destroy_builds_started": [],
        "skipped": [],
    }

    for env_data in environments:
        expires_at = env_data["created_at"] + timedelta(hours=env_data["ttl_hours"])
        warn_at = expires_at - timedelta(minutes=NOTIFICATION_LEAD_MINUTES)

        if now >= expires_at:
            if marker_exists("teardown-requests", env_data["name"]):
                results["skipped"].append({"environment": env_data["name"], "reason": "destroy already requested"})
                continue

            build = start_destroy_build(env_data)
            put_marker("teardown-requests", env_data["name"], {
                "build_id": build["id"],
                "requested_at": now.isoformat(),
                "expires_at": expires_at.isoformat(),
                "reason": "ttl-expired",
            })
            results["destroy_builds_started"].append({"environment": env_data["name"], "build_id": build["id"]})
            continue

        if now >= warn_at and not marker_exists("warnings", env_data["name"]):
            publish_warning(env_data, expires_at)
            put_marker("warnings", env_data["name"], {
                "warned_at": now.isoformat(),
                "expires_at": expires_at.isoformat(),
            })
            results["warnings_sent"].append(env_data["name"])

    print(json.dumps(results, default=str))
    return results


def discover_environments():
    paginator = ec2.get_paginator("describe_instances")
    pages = paginator.paginate(
        Filters=[
            {"Name": "tag:provisioner/project", "Values": [PROJECT_NAME]},
            {"Name": "instance-state-name", "Values": ["pending", "running", "stopping", "stopped"]},
        ]
    )

    environments = {}
    for page in pages:
        for reservation in page.get("Reservations", []):
            for instance in reservation.get("Instances", []):
                tags = {tag["Key"]: tag["Value"] for tag in instance.get("Tags", [])}
                env_name = tags.get("provisioner/environment")
                if not env_name or env_name in environments:
                    continue

                try:
                    environments[env_name] = {
                        "name": env_name,
                        "owner": tags["owner"],
                        "created_at": parse_utc(tags["created-at"]),
                        "ttl_hours": int(tags["ttl-hours"]),
                        "allowed_ssh_cidr": tags.get("allowed-ssh-cidr", DEFAULT_ALLOWED_CIDR),
                        "instance_id": instance["InstanceId"],
                    }
                except (KeyError, ValueError) as exc:
                    print(f"Skipping {instance.get('InstanceId')} because required tags are invalid: {exc}")

    return list(environments.values())


def parse_utc(value):
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def start_destroy_build(env_data):
    return codebuild.start_build(
        projectName=CODEBUILD_PROJECT_NAME,
        environmentVariablesOverride=[
            env("ACTION", "destroy"),
            env("ENVIRONMENT_NAME", env_data["name"]),
            env("TTL_HOURS", str(env_data["ttl_hours"])),
            env("OWNER", env_data["owner"]),
            env("CREATED_AT", env_data["created_at"].strftime("%Y-%m-%dT%H:%M:%SZ")),
            env("ALLOWED_SSH_CIDR", env_data.get("allowed_ssh_cidr") or DEFAULT_ALLOWED_CIDR),
        ],
    )["build"]


def marker_exists(kind, environment_name):
    try:
        ssm.get_parameter(Name=marker_name(kind, environment_name), WithDecryption=False)
        return True
    except ssm.exceptions.ParameterNotFound:
        return False


def put_marker(kind, environment_name, value):
    ssm.put_parameter(
        Name=marker_name(kind, environment_name),
        Type="String",
        Value=json.dumps(value, sort_keys=True),
        Overwrite=True,
    )


def marker_name(kind, environment_name):
    return f"/env/{PROJECT_NAME}/{kind}/{environment_name}"


def publish_warning(env_data, expires_at):
    subject = f"{PROJECT_NAME}: {env_data['name']} expires soon"
    message = (
        f"Environment {env_data['name']} owned by {env_data['owner']} will be destroyed at "
        f"{expires_at.isoformat()} because its TTL is {env_data['ttl_hours']} hours.\n\n"
        "Destroy will be performed by an automated CodeBuild Terraform run."
    )
    sns.publish(TopicArn=SNS_TOPIC_ARN, Subject=subject[:100], Message=message)


def env(name, value):
    return {"name": name, "value": value, "type": "PLAINTEXT"}

