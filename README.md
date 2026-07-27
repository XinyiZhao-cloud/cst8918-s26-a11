CST8918 - DevOps: Infrastructure as Code
Prof. Robert McKenney

# Assignment 12: Terraform CI/CD on Azure with GitHub Actions

Automated CI/CD for a Terraform configuration that deploys supporting Azure
infrastructure for a containerized web app on AKS. Four GitHub Actions workflows
cover static analysis, integration tests on pull request, deployment on merge to
`main`, and daily drift detection.

---

## Team Members

| Full Name | College Username | GitHub Profile |
| --------- | ---------------- | -------------- |
| Xinyi Zhao | _TODO: abcd0001_ | [@XinyiZhao-cloud](https://github.com/XinyiZhao-cloud) |
| Mireille (Mimi) Dib | dib00016 | [@mimidib](https://github.com/mimidib) |

**Repository URL:** _TODO: https://github.com/XinyiZhao-cloud/cst8918-s26-a11_

---

## Table of Contents

- [1. Repository Settings](#1-repository-settings)
- [2. Terraform Remote Backend](#2-terraform-remote-backend)
- [3. Azure Credentials for Automation](#3-azure-credentials-for-automation)
- [4. GitHub Secrets](#4-github-secrets)
- [5. OIDC Authentication in Terraform](#5-oidc-authentication-in-terraform)
- [6. GitHub Actions Workflows](#6-github-actions-workflows)
- [7. Testing the Pipeline](#7-testing-the-pipeline)
- [Screenshots (Submission Requirements)](#screenshots-submission-requirements)
- [Division of Work](#division-of-work)
- [Cleanup](#cleanup)
- [References](#references)

---

## Project Structure

```plaintext
cst8918-s26-a11
├── .github
│   └── workflows
│       ├── infra-ci-cd.yml
│       ├── infra-drift-detection.yml
│       └── infra-static-tests.yml
├── app
│   └── .gitkeep
├── infra
│   ├── az-federated-credential-params
│   │   ├── branch-main.json
│   │   ├── production-deploy.json
│   │   └── pull-request.json
│   ├── tf-app
│   │   ├── .tflint.hcl
│   │   ├── main.tf
│   │   ├── outputs.tf
│   │   ├── terraform.tf
│   │   └── variables.tf
│   └── tf-backend
│       └── main.tf
├── screenshots
│   ├── pr-checks.png
│   └── pr-tf-plan.png
├── .editorconfig
├── .gitignore
└── README.md
```

---

## 1. Repository Settings

_Reference: [docs/1-github-settings.md](docs/1-github-settings.md)_

## Branching Strategy

This project uses a `main` / `dev` branching model:

| Branch | Role | Protected |
| ------ | ---- | --------- |
| `main` | Production. A merge here triggers the `terraform apply` deploy job. | Yes |
| `dev` | Shared integration branch. All feature work is merged here first. | Yes |
| feature branches (e.g. `infra-elements`) | Short-lived, one per unit of work. | No |

Flow: `feature branch` → PR into `dev` (review + approval required) → PR from `dev` into
`main` (review + approval required) → deploy.

> [!NOTE]
> The static analysis workflow runs on a push to any branch, and the integration-test
> (`terraform plan`) job runs on every pull request regardless of base branch, so both
> fire on PRs into `dev`. The **deploy** job is gated on a push to `main`, so
> infrastructure is only applied when `dev` is merged into `main`.

### GitHub Environment

- **Environment name:** `production`
- **Required reviewers:** both team members, with **Prevent self-review** enabled
- **Deployment branches:** restricted to `main` only
- _TODO: confirm each of the above was configured in `Settings > Environments`._

---

## 2. Terraform Remote Backend

_Reference: [docs/2-terraform-backend.md](docs/2-terraform-backend.md)_

The backend configuration in `infra/tf-backend` creates the Azure Storage Account
and container that hold the Terraform state file for `infra/tf-app`.

| Item | Value |
| ---- | ----- |
| Resource group | _TODO_ |
| Storage account name | _TODO_ |
| Container name | _TODO_ |
| State file key | _TODO_ |
| Location | _TODO_ |

Backend block used in `infra/tf-app/terraform.tf`:

```hcl
# TODO: paste the backend "azurerm" block here
```

_TODO: brief note on why remote state is required for CI/CD (shared state, locking,
no state file in git)._

---

## 3. Azure Credentials for Automation

_Reference: [docs/3-azure-credentials.md](docs/3-azure-credentials.md)_

Two Azure AD (Entra ID) app registrations / service principals were created:

| App registration | Role | Scope | Used by |
| ---------------- | ---- | ----- | ------- |
| _TODO: name_ | Reader | _TODO: subscription_ | PR / plan + drift detection workflows |
| _TODO: name_ | Contributor | _TODO: subscription_ | `production` environment deploy job |

### Federated Credentials

Parameter files are stored in `infra/az-federated-credential-params/`:

| File | Subject | Purpose |
| ---- | ------- | ------- |
| `pull-request.json` | `repo:OWNER/REPO:pull_request` | plan on PRs |
| `branch-main.json` | `repo:OWNER/REPO:ref:refs/heads/main` | drift detection / main branch |
| `production-deploy.json` | `repo:OWNER/REPO:environment:production` | apply on merge |

_TODO: confirm the exact `subject` values used and note the commands run
(`az ad app create`, `az ad app federated-credential create`, `az role assignment create`)._

---

## 4. GitHub Secrets

_Reference: [docs/4-github-secrets.md](docs/4-github-secrets.md)_

### Repository-level secrets

| Secret | Description | Set |
| ------ | ----------- | --- |
| `AZURE_TENANT_ID` | Entra ID tenant id | _TODO_ |
| `AZURE_SUBSCRIPTION_ID` | Azure subscription id | _TODO_ |
| `AZURE_CLIENT_ID` | appId of the **Reader** app registration | _TODO_ |
| `ARM_ACCESS_KEY` | primary access key of the state storage account | _TODO_ |

### Environment-level secrets (`production`)

| Secret | Description | Set |
| ------ | ----------- | --- |
| `AZURE_CLIENT_ID` | appId of the **Contributor** app registration (overrides the repo-level value) | _TODO_ |

> Secret **values** are never committed to this repository.

---

## 5. OIDC Authentication in Terraform

_Reference: [docs/5-use-oidc.md](docs/5-use-oidc.md)_

_TODO: describe the changes made to `infra/tf-app/terraform.tf` (e.g. `use_oidc = true`
on the provider and/or backend) and why OIDC is preferred over a long-lived client
secret._

```hcl
# TODO: paste the relevant provider / terraform block
```

---

## 6. GitHub Actions Workflows

### 6.1 Static Code Analysis — `infra-static-tests.yml`

_Reference: [docs/6_1-terraform-static-tests.md](docs/6_1-terraform-static-tests.md)_

- **Trigger:** push to any branch
- **Working directory:** `./infra/tf-app`
- **Steps:** `terraform fmt -check` → `terraform init` → `terraform validate` → `checkov`
- **Notes:** _TODO: anything you had to adjust (checkov soft-fail, SARIF upload, permissions)._

### 6.2 Integration Tests — `infra-ci-cd.yml` (plan job)

_Reference: [docs/6_2-terraform-integration.md](docs/6_2-terraform-integration.md)_

- **Trigger:** pull request targeting `main`
- **What it does:** authenticates to Azure via OIDC, runs `terraform plan`, and posts
  the plan output back to the PR as a comment.
- **Notes:** _TODO_

### 6.3 Deployment — `infra-ci-cd.yml` (apply job)

_Reference: [docs/6_3-terraform-deploy.md](docs/6_3-terraform-deploy.md)_

- **Trigger:** push / merge to `main`
- **Environment:** `production` (uses the Contributor `AZURE_CLIENT_ID`)
- **What it does:** `terraform apply -auto-approve` against the deployed infrastructure.
- **Notes:** _TODO_

### 6.4 Drift Detection — `infra-drift-detection.yml`

_Reference: [docs/6_4-terraform-drift.md](docs/6_4-terraform-drift.md)_

- **Trigger:** nightly schedule (`cron: '41 3 * * *'`) + manual `workflow_dispatch`
- **What it does:** runs `terraform plan -detailed-exitcode`; opens a GitHub issue when
  drift is detected and closes the open drift issue when the configuration matches.
- **Notes:** _TODO: paste a link to a drift issue if you triggered one for testing._

---

## 7. Testing the Pipeline

_Reference: [docs/7-add-infra-elements.md](docs/7-add-infra-elements.md)_

Branch: `infra-elements` → `dev` → `main`

Resources added to `infra/tf-app`:

| Resource | Type | Name | Address space / prefix |
| -------- | ---- | ---- | ---------------------- |
| Virtual Network | `azurerm_virtual_network` | _TODO_ | _TODO_ |
| Subnet | `azurerm_subnet` | _TODO_ | _TODO_ |

Observed results:

1. **Push to `infra-elements`** → _TODO: static analysis workflow result_
2. **Open PR `infra-elements` → `dev`** → _TODO: static analysis + integration test / plan
   result, plan comment posted on the PR_ 📸 **both submission screenshots are taken here**
3. **Approve & merge into `dev`** → _TODO: confirm no deploy runs at this point (expected —
   the deploy job only triggers on `main`)_
4. **Open PR `dev` → `main`, approve & merge** → _TODO: deploy workflow result, including
   the `production` environment approval step_
5. **Azure Portal verification** → _TODO: confirm the VNet and Subnet exist_

_TODO (optional): link to the PRs — https://github.com/OWNER/REPO/pull/N_

---

## Screenshots (Submission Requirements)

### 1. Pull Request — all checks have passed (expanded)

_TODO: save as `screenshots/pr-checks.png`_

![Pull request showing all checks have passed, expanded to show each workflow step](screenshots/pr-checks.png)

### 2. Pull Request — Terraform Plan output (expanded)

_TODO: save as `screenshots/pr-tf-plan.png`_

![Pull request showing the expanded results of the Terraform Plan step](screenshots/pr-tf-plan.png)

---

## Division of Work

Work was split across 7 stacked pull requests, each targeting `dev`, in the order the
assignment lists the steps. Each partner authored roughly half and reviewed/approved the
other half. `dev` was merged into `main` at the end to trigger the deployment.

| PR | Description | Author | Reviewer |
| -- | ----------- | ------ | -------- |
| 1 | Foundation — repo settings, branch protection, Terraform backend, Azure identity, GitHub secrets, OIDC (docs 1–5) | _TODO_ | _TODO_ |
| 2 | Static analysis workflow — `infra-static-tests.yml` (docs 6.0–6.1) | _TODO_ | _TODO_ |
| 3 | Integration-test job — plan-on-PR half of `infra-ci-cd.yml` (doc 6.2) | _TODO_ | _TODO_ |
| 4 | README skeleton | _TODO_ | _TODO_ |
| 5 | Deploy job — apply-on-merge half of `infra-ci-cd.yml` (doc 6.3) | _TODO_ | _TODO_ |
| 6 | Drift-detection workflow — `infra-drift-detection.yml` (doc 6.4) | _TODO_ | _TODO_ |
| 7 | Add VNet + Subnet, run the full pipeline, screenshots, final README (doc 7) | _TODO_ | _TODO_ |

---

## Challenges & Lessons Learned *(optional)*

_TODO (optional but good for marks): anything that broke and how you fixed it —
federated credential subject mismatches, `Error: building AzureRM Client`, checkov
failures, plan-comment permissions, etc._

---

## Cleanup *(optional)*

```sh
cd infra/tf-app
terraform destroy

cd ../tf-backend
terraform destroy
```

_TODO: confirm resources were destroyed._

---

## References *(optional)*

- [GitHub Actions Workflows for Terraform (Azure-Samples)](https://github.com/Azure-Samples/terraform-github-actions)
- [Connect to Azure from GitHub Actions with OIDC](https://learn.microsoft.com/en-ca/azure/developer/github/connect-from-azure?tabs=azure-cli%2Clinux#use-the-azure-login-action-with-openid-connect)
- [About security hardening with OpenID Connect](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
- [About protected branches](https://docs.github.com/en/github/administering-a-repository/defining-the-mergeability-of-pull-requests/about-protected-branches)
- [Checkov](https://www.checkov.io/)
