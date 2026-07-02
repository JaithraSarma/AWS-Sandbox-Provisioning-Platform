# Parameterize SSM Parameter Paths Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generalize SSM parameter paths by replacing the hardcoded namespace with one derived from `project_name`.

**Architecture:** Update the parameter paths in the environment module and provision lambda function to use the dynamic `project_name` namespace. Cleanup lambda and IAM policies do not need modification since they already use this dynamic namespace.

**Tech Stack:** Terraform, Python (Boto3)

## Global Constraints
- None

---

### Task 1: Update Environment Terraform Module

**Files:**
- Modify: [main.tf](file:///c:/Users/Jaith/Desktop/projects/aws%20env%20provisioner/terraform/modules/environment/main.tf)

**Interfaces:**
- Consumes: `var.project_name` and `var.environment_name`
- Produces: SSM parameter named `/${var.project_name}/environments/${var.environment_name}`

- [ ] **Step 1: Modify the SSM parameter path in Terraform**

  Edit [main.tf](file:///c:/Users/Jaith/Desktop/projects/aws%20env%20provisioner/terraform/modules/environment/main.tf#L124):
  ```diff
  -  name      = "/jaith/aws-env-provisioner/environments/${var.environment_name}"
  +  name      = "/${var.project_name}/environments/${var.environment_name}"
  ```

- [ ] **Step 2: Run Terraform validation**

  Run: `terraform validate` inside `terraform/environment/` and `terraform/infrastructure/` to ensure no syntax errors.

---

### Task 2: Update Provision Lambda Function

**Files:**
- Modify: [handler.py](file:///c:/Users/Jaith/Desktop/projects/aws%20env%20provisioner/lambda/provision/handler.py)

**Interfaces:**
- Consumes: Environment variable `PROJECT_NAME`
- Produces: SSM parameter at `/${PROJECT_NAME}/environments/${environment_name}`

- [ ] **Step 1: Modify the SSM parameter path in Lambda python code**

  Edit [handler.py](file:///c:/Users/Jaith/Desktop/projects/aws%20env%20provisioner/lambda/provision/handler.py#L36):
  ```diff
  -            Name=f"/jaith/{PROJECT_NAME}/environments/{request_data['environment_name']}",
  +            Name=f"/{PROJECT_NAME}/environments/{request_data['environment_name']}",
  ```

- [ ] **Step 2: Verify the updated SSM path**

  - Deploy or invoke the Provision Lambda.
  - Confirm parameters are created only under `/${PROJECT_NAME}/environments/...`.
  - Confirm no new parameters are created under the legacy `/jaith/...` namespace.
