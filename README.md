# AWS Sandbox Provisioning Platform

Self-service, API-driven AWS sandbox environments with automatic TTL-based cleanup, built on Lambda, CodeBuild, and Terraform.

---

## Overview

Provisioning a throwaway AWS environment for testing or debugging usually means one of two things: filing a ticket and waiting on a platform team, or handing developers standing AWS access and hoping they remember to clean up after themselves. Neither scales well: the first creates a bottleneck, the second creates cost leakage and security drift.

This project removes both problems. A developer calls a single API endpoint with an environment name and a time-to-live (TTL). Everything after that (provisioning, tagging, expiry tracking, warning notifications, and teardown) is fully automated. No AWS console access, no manual Terraform commands, and no environment left running past its TTL.

---

## Architecture

![AWS Infrastructure Provisioning & Cleanup Architecture](docs/images/architecture.png)

**Two independent Terraform layers:**

| Layer | Root | State key | Deployed by |
|---|---|---|---|
| **Platform:** API Gateway, both Lambdas, CodeBuild project, EventBridge rule, SNS topic, IAM roles | `terraform/infrastructure` | `infra/main/terraform.tfstate` | Deployed once, manually, by the operator |
| **Sandbox environment:** VPC, subnet, security group, EC2 instance | `terraform/environment` | `envs/<environment-name>/terraform.tfstate` | Deployed automatically, per request, by CodeBuild |

Each sandbox gets its own isolated state file, so provisioning or destroying one environment can never touch another environment, or the platform itself.

---

## How It Works

1. **Provision:** A developer sends `POST /environments` with an environment name and TTL. API Gateway invokes the **Provision Lambda**, which validates the request, records metadata in SSM Parameter Store, and starts a **CodeBuild** run against the `terraform/environment` Terraform root using a state key scoped to that environment name.
2. **Tag:** Every resource created is tagged with `owner`, `created-at`, `ttl-hours`, `allowed-ssh-cidr`, `provisioner/project`, and `provisioner/environment` (the source of truth the cleanup process reads back later.
3. **Monitor:** An **EventBridge** rule invokes the **Cleanup Lambda** every 2 hours. It scans live EC2 instances by tag, computes each environment's expiry time from its tags, and sends a one-time SNS warning email 30 minutes before expiry.
4. **Destroy:** Once an environment's TTL has elapsed, the Cleanup Lambda starts a CodeBuild `destroy` run scoped to that environment's own state file. On success, its warning and teardown markers in SSM are cleaned up.

No developer ever runs `terraform apply` or `terraform destroy` themselves for a sandbox; CodeBuild does, triggered entirely by the Lambdas.

---

## Repository Layout

```text
buildspec.yml                      # CodeBuild provision/destroy commands

lambda/
  provision/handler.py             # API Gateway Lambda: validates & starts provisioning
  cleanup/handler.py               # Scheduled Lambda: TTL scan, warnings, teardown

terraform/
  backend/                         # One-time S3 + DynamoDB state backend bootstrap
  infrastructure/                  # Platform: API Gateway, Lambdas, CodeBuild, SNS, EventBridge, IAM
  environment/                     # Terraform root executed by CodeBuild per sandbox
  modules/environment/             # Reusable VPC / subnet / EC2 / security group module
```

---

## Setup

To set up the AWS Sandbox Provisioning Platform, see the detailed [Setup Guide](setup.md) for step-by-step instructions. The setup guide covers:

- [Prerequisites](setup.md#prerequisites)
- [Bootstrapping Terraform State](setup.md#1-bootstrap-terraform-state)
- [Deploying the Platform](setup.md#2-deploy-the-platform)
- [Verifying the Setup](setup.md#verification)
- [Troubleshooting](setup.md#troubleshooting)

---

## API Reference

### `POST /environments`

**Request body:**

```json
{
  "environment_name": "<OWNER>-test",
  "ttl_hours": 2,
  "owner": "<OWNER>",
  "allowed_ssh_cidr": "203.0.113.10/32"
}
```

| Field | Required | Description |
|---|---|---|
| `environment_name` | Yes | 3–40 characters, alphanumeric or hyphen, no leading/trailing hyphen |
| `ttl_hours` | Yes | One of `2`, `4`, `8`, `24` |
| `owner` | No | Stored in tags. Defaults to the caller's source IP if omitted |
| `allowed_ssh_cidr` | No | Security group SSH CIDR. Defaults to `default_allowed_ssh_cidr` |

**Response (`200`):**

```json
{
  "message": "Provision build started",
  "environment_name": "<OWNER>-test",
  "build_id": "aws-env-provisioner-terraform:...",
  "build_arn": "arn:aws:codebuild:...",
  "created_at": "2026-05-18T10:15:00Z"
}
```

---

## Runtime IAM Roles

| Role | Purpose |
|---|---|
| `aws-env-provisioner-terraform-role` | CodeBuild service role that runs Terraform provision/destroy |
| `aws-env-provisioner-provision-api-role` | Provision Lambda role: writes SSM metadata, starts provision builds |
| `aws-env-provisioner-cleanup-role` | Cleanup Lambda role: scans tags, sends SNS warnings, starts destroy builds |

Each role is scoped to only what its function needs; no role has broad EC2, IAM, or account-wide permissions.

---

## Cost Profile

This project is designed to stay inside AWS free tier for light usage:

- EC2 `t2.micro`
- One VPC and one public subnet per environment
- CodeBuild `BUILD_GENERAL1_SMALL`
- Lambda, 128 MB
- EventBridge, scheduled every 2 hours
- S3 and DynamoDB with minimal state/lock usage
- SNS email notifications
- SSM standard parameters

Actual free-tier eligibility depends on account age, region, and existing usage (check AWS Billing after testing.

---

## Known Limitations / Roadmap

This is a working prototype, not a production-hardened platform. Known gaps, in rough priority order:

- No authorizer (IAM or JWT) on the API Gateway endpoint, meaning anyone with the URL can provision environments
- SSH access is CIDR-restricted but still public; SSM Session Manager would remove the need for open inbound SSH entirely
- No API keys or usage plans / rate limiting
- No manual endpoint to extend an environment's TTL or force an early destroy
- No cost guardrails (e.g., AWS Budgets integration)
- Notification routing is a single SNS topic rather than per-owner email routing
- IAM policies are scoped but not yet fully least-privilege audited

---

## License

This project is licensed under the [MIT License](LICENSE).
