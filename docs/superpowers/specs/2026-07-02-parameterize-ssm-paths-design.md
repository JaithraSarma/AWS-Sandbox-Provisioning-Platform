# Design Spec: Parameterize SSM Parameter Paths

Historically, the project namespace `/jaith/aws-env-provisioner` was hardcoded in several locations, causing naming mismatches and permission issues when deploying resources under different project names.

This design generalizes the SSM parameter namespace to dynamically use the `project_name` variable and removes the hardcoded `/jaith/` owner prefix. The owner information is already captured inside the parameter values and AWS tags.

## Proposed Changes

### 1. Environment Module
Update the SSM parameter resource in [main.tf](file:///c:/Users/Jaith/Desktop/projects/aws%20env%20provisioner/terraform/modules/environment/main.tf) to use variables instead of hardcoded paths, removing `/jaith`.
- **Old path**: `/jaith/aws-env-provisioner/environments/${var.environment_name}`
- **New path**: `/${var.project_name}/environments/${var.environment_name}`

### 2. Lambda Functions
Update SSM interaction paths in Provision and Cleanup lambdas to use the cleaner `/${PROJECT_NAME}/...` structure.
- **Provision Lambda**: [handler.py](file:///c:/Users/Jaith/Desktop/projects/aws%20env%20provisioner/lambda/provision/handler.py)
  - Change SSM put-parameter name to: `f"/{PROJECT_NAME}/environments/{request_data['environment_name']}"`
- **Cleanup Lambda**: [handler.py](file:///c:/Users/Jaith/Desktop/projects/aws%20env%20provisioner/lambda/cleanup/handler.py)
  - No changes required. The cleanup lambda already uses `f"/{PROJECT_NAME}/{kind}/{environment_name}"` and does not contain any hardcoded `/jaith/` references.

### 3. Infrastructure IAM Policies
- No functional IAM policy changes are required. The existing policy pattern in [main.tf](file:///c:/Users/Jaith/Desktop/projects/aws%20env%20provisioner/terraform/infrastructure/main.tf) already matches the new SSM namespace because it is based on `project_name` rather than a hardcoded owner prefix.

### 4. Buildspec Configuration
Update the post_build teardown script in [buildspec.yml](file:///c:/Users/Jaith/Desktop/projects/aws%20env%20provisioner/buildspec.yml) to clean up parameters:
- **Old cleanup command**: `/aws-env-provisioner/<kind>/${ENVIRONMENT_NAME}` (hardcoded project name prefix)
- **New cleanup command**: `/${PROJECT_NAME:-aws-env-provisioner}/<kind>/${ENVIRONMENT_NAME}` (dynamic project name prefix)

## Verification Plan

### Manual Verification
- Deploy infrastructure using Terraform.
- Verify environment provisioning via the provision lambda/API gateway.
- Confirm SSM parameters are created under `/<project_name>/environments/...`.
- Validate cleanup lambda identifies expired environments and deletes markers successfully.
