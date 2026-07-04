# Setup Guide

This guide provides step-by-step instructions for setting up, verifying, and troubleshooting the AWS Sandbox Provisioning Platform.

---

## Prerequisites

Before starting, ensure you have:

- An **AWS account** (free tier eligible)
- **Terraform** `>= 1.6` installed
- **AWS CLI** installed and configured locally with credentials for initial bootstrap
- This repository hosted on GitHub, CodeCommit, or another CodeBuild-supported source
- CodeBuild source access configured if the repository is private

> [!NOTE]
> All runtime IAM roles are created by Terraform itself; no `AdministratorAccess` is required for CodeBuild or either Lambda at runtime.

---

## Setup Steps

Deploying the platform is a one-time operation to set up the management infrastructure. Once deployed, sandbox environments are provisioned automatically via the API.

### 1. Bootstrap Terraform State

This step creates the S3 bucket and DynamoDB table used for remote state storage and locking across the rest of the project.

1. Navigate to the backend directory:
   ```bash
   cd terraform/backend
   ```
2. Initialize Terraform:
   ```bash
   terraform init
   ```
3. Apply the configuration (replace placeholder values as appropriate):
   ```bash
   terraform apply \
     -var="aws_region=ap-south-1" \
     -var="state_bucket_name=<globally-unique-state-bucket>" \
     -var="lock_table_name=aws-env-provisioner-tf-locks"
   ```

> [!IMPORTANT]
> Save the output values from this step (the S3 bucket name and DynamoDB lock table name); you will need them in the next step.

### 2. Deploy the Platform

This step creates the API Gateway, both Lambdas, the CodeBuild project, EventBridge schedule, SNS topic, and runtime IAM roles.

1. Navigate to the infrastructure directory:
   ```bash
   cd terraform/infrastructure
   ```
2. Initialize Terraform with the backend configuration from Step 1:
   ```bash
   terraform init \
     -backend-config="bucket=<STATE_BUCKET>" \
     -backend-config="key=infra/main/terraform.tfstate" \
     -backend-config="region=ap-south-1" \
     -backend-config="dynamodb_table=<LOCK_TABLE>" \
     -backend-config="encrypt=true"
   ```
3. Deploy the infrastructure (replace placeholders with your details):
   ```bash
   terraform apply \
     -var="aws_region=ap-south-1" \
     -var="state_bucket_name=<STATE_BUCKET>" \
     -var="lock_table_name=<LOCK_TABLE>" \
     -var="repository_url=https://github.com/<OWNER>/aws-env-provisioner.git" \
     -var="source_version=main" \
     -var="sns_email=you@example.com"
   ```

4. **Confirm the SNS Email Subscription**: AWS will send a confirmation email to the address specified in `sns_email`. You must confirm the subscription to receive warning notifications before environments are destroyed.

5. Retrieve the API provision URL from the Terraform outputs:
   ```bash
   terraform output provision_url
   ```

> [!NOTE]
> Steps 1 and 2 deploy the *platform* and are a one-time, manual operation. They are never repeated per sandbox environment.

---

## Verification

Once setup is complete, you can verify the platform functionality using the following commands.

### 1. Provision an Environment

Send a POST request to your deployed API Gateway endpoint:

```bash
curl -X POST "<PROVISION_URL>" \
  -H "content-type: application/json" \
  -d '{"environment_name":"<OWNER>-test","ttl_hours":2,"owner":"<OWNER>","allowed_ssh_cidr":"203.0.113.10/32"}'
```

### 2. Watch the CodeBuild Run

Check the build status in CodeBuild:

```bash
aws codebuild list-builds-for-project \
  --project-name aws-env-provisioner-terraform
```

### 3. Check Live Environments

Confirm that the EC2 instances are successfully tagged and running:

```bash
aws ec2 describe-instances \
  --filters "Name=tag:provisioner/project,Values=aws-env-provisioner" \
  --query "Reservations[].Instances[].{Id:InstanceId,State:State.Name,Env:Tags[?Key=='provisioner/environment']|[0].Value}" \
  --output table
```

### 4. Check SSM Metadata

Verify that the sandbox metadata has been recorded:

```bash
aws ssm get-parameter \
  --name "/<PROJECT_NAMESPACE>/aws-env-provisioner/environments/<OWNER>-test" \
  --query "Parameter.Value" \
  --output text
```

### 5. Trigger Cleanup Manually

You can trigger the scheduled cleanup Lambda manually to verify warning emails and environment teardown:

```bash
aws lambda invoke \
  --function-name aws-env-provisioner-cleanup \
  --payload '{}' \
  response.json

cat response.json
```

---

## Troubleshooting

Common issues and solutions encountered during deployment and operations.

### Terraform apply fails during resource reconciliation
Terraform needs several EC2 *read* permissions in addition to write permissions. Ensure the deploying IAM entity has permissions for:
```json
"ec2:DescribeVpcAttribute",
"ec2:DescribeInstanceTypes",
"ec2:DescribeInstanceAttribute"
```

### `AccessDeniedException: No access to reserved parameter name`
AWS reserves the `/aws/*` SSM namespace. Ensure you use a project-scoped namespace instead, e.g. `/<PROJECT_NAMESPACE>/aws-env-provisioner/environments/*` (example: `/<OWNER>/aws-env-provisioner/environments/<OWNER>-test`).

### SSM parameter tagging fails after successful provisioning
The CodeBuild role needs:
```json
"ssm:AddTagsToResource",
"ssm:ListTagsForResource",
"ssm:RemoveTagsFromResource"
```

### API Gateway, CodeBuild, or EventBridge lookups fail unexpectedly
This is usually caused by a region mismatch. The backend region, provider region, and `-var="aws_region=..."` must all match exactly.

### `ResourceAlreadyExistsException` on redeploy
This happens when Terraform state becomes inconsistent or resources were partially destroyed. Fix this by:
1. Importing the orphaned resource into state using `terraform import`
2. Deleting the resource manually from the AWS Console or AWS CLI
3. Rebuilding the backend cleanly

### `BucketNotEmpty` when deleting the backend bucket
S3 backend buckets with versioning enabled cannot be deleted while object versions remain. You must first empty the bucket's objects, delete all object versions, and then delete the bucket.

### Recommended Deploy/Destroy Order

To avoid orphaning resources or leaving Terraform state stranded, follow this order:

| Action | Order |
|---|---|
| **Deploy** | `terraform/backend` → `terraform/infrastructure` |
| **Destroy** | `terraform/infrastructure` → `terraform/backend` |

> [!CAUTION]
> Destroying the backend first can strand Terraform state and orphan infrastructure resources, which may require manual cleanup.

### Debugging IAM Permission Gaps
To isolate which permissions Terraform needs during initial development, you can temporarily broaden IAM policies (e.g., `ec2:*`, `ssm:*`).
> [!WARNING]
> Tighten policies back down to the minimum required action set before moving to production. Broad policies should never ship in the final configuration.
