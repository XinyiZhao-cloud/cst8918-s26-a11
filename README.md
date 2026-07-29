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
| Xinyi Zhao | zhao0201 | [@XinyiZhao-cloud](https://github.com/XinyiZhao-cloud) |
| Mireille (Mimi) Dib | dib00016 | [@mimidib](https://github.com/mimidib) |

**Repository URL:** https://github.com/XinyiZhao-cloud/cst8918-s26-a11

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

All work is done on short-lived feature branches and merged into `main` through a reviewed
pull request:

| Branch | Role | Protected |
| ------ | ---- | --------- |
| `main` | Production and default branch. A merge here triggers the `terraform apply` deploy job. | Yes |
| feature branches (e.g. `infra-elements`) | Short-lived, one per assignment step. | No |

Flow: `feature branch` → pull request into `main` → review and approval by the other team
member → merge → deploy.

The `main` branch is protected by an active ruleset with no bypass list, so the rules apply
to the repository owner as well:

- Direct pushes are blocked — all changes arrive through a pull request
- At least one approving review is required
- Force pushes and branch deletion are blocked

> [!NOTE]
> The static analysis workflow runs on a push to any branch, so it fires on feature
> branches before a pull request even exists. The integration-test (`terraform plan`) job
> runs on the pull request itself. The **deploy** job is gated on a push to `main`, so
> infrastructure is only applied once a pull request is approved and merged.

### GitHub Environment

- **Environment name:** `production`
- **Required reviewers:** both team members ([@XinyiZhao-cloud](https://github.com/XinyiZhao-cloud), [@mimidib](https://github.com/mimidib)), with **Prevent self-review** enabled
- **Administrator bypass:** disabled
- **Deployment branches:** restricted to `main` only

The environment does two jobs. It scopes the contributor `AZURE_CLIENT_ID` secret so that
only jobs declaring `environment: production` receive write access to Azure, and it adds a
manual approval gate before any `terraform apply` runs.

---

## 2. Terraform Remote Backend

_Reference: [docs/2-terraform-backend.md](docs/2-terraform-backend.md)_

The backend configuration in `infra/tf-backend` creates the Azure Storage Account
and container that hold the Terraform state file for `infra/tf-app`.

| Item | Value |
| ---- | ----- |
| Resource group | `dib00016-githubactions-rg` |
| Storage account name | `dib00016githubactions` |
| Container name | `tfstate` |
| State file key | `prod.app.tfstate` |
| Location | `canadacentral` |

The two configurations are deliberately separate. If the storage account lived in the same
configuration as the app infrastructure, Terraform would need the storage account to exist
before it could store the state that records creating it — a chicken-and-egg problem. So
`tf-backend` is applied once using local state and local Azure CLI credentials, and
`tf-app` then points its remote state at what `tf-backend` built.

Backend block used in `infra/tf-app/terraform.tf`:

```hcl
backend "azurerm" {
  resource_group_name  = "dib00016-githubactions-rg"
  storage_account_name = "dib00016githubactions"
  container_name       = "tfstate"
  key                  = "prod.app.tfstate"
  use_oidc             = true
}
```

Remote state is required for CI/CD for three reasons:

- **Shared state** — the GitHub Actions runner is a fresh machine every run. Local state
  would mean every workflow starting from nothing and trying to recreate infrastructure
  that already exists.
- **Locking** — Azure Blob Storage leases the state file during an operation, so a deploy
  and a drift-detection run can't corrupt it by writing simultaneously.
- **Nothing sensitive in git** — state contains resource attributes in plaintext, including
  the storage account access key. `*.tfstate` is in `.gitignore` for exactly that reason.

---

## 3. Azure Credentials for Automation

_Reference: [docs/3-azure-credentials.md](docs/3-azure-credentials.md)_

Two Azure AD (Entra ID) app registrations / service principals were created:

| App registration | Role | Scope | Used by |
| ---------------- | ---- | ----- | ------- |
| `dib00016-githubactions-r` | Reader | resource group `dib00016-a12-rg` | PR / plan + drift detection workflows |
| `dib00016-githubactions-rw` | Contributor | resource group `dib00016-a12-rg` | `production` environment deploy job |

Two identities rather than one, following least privilege. The workflows that run on every
pull request only need to *read* Azure to produce a plan, so they get the reader identity —
meaning a pull request cannot create, modify, or destroy infrastructure no matter what it
contains. Only the deploy job, gated behind the `production` environment and its approval
step, receives contributor access.

Both roles are scoped to the `dib00016-a12-rg` resource group rather than the whole
subscription, again to keep the blast radius as small as the task allows.

### Federated Credentials

Parameter files are stored in `infra/az-federated-credential-params/`:

| File | Subject | Attached to | Purpose |
| ---- | ------- | ----------- | ------- |
| `pull-request.json` | `repo:XinyiZhao-cloud/cst8918-s26-a11:pull_request` | Reader | plan on PRs |
| `branch-main.json` | `repo:XinyiZhao-cloud/cst8918-s26-a11:branch:main` | Reader | drift detection / main branch |
| `production-deploy.json` | `repo:XinyiZhao-cloud/cst8918-s26-a11:environment:production` | Contributor | apply on merge |

Each `subject` is a rule describing *which GitHub context Azure will trust* — not a
password. When a workflow runs, GitHub issues a short-lived signed token describing the
repository, branch, and environment; Azure verifies the signature and matches the claims
against these subjects before issuing an access token. A run that doesn't match gets
nothing.

Commands used (from `infra/`):

```sh
az ad app create --display-name dib00016-githubactions-rw
az ad sp create --id $appIdRW
az role assignment create \
  --role contributor \
  --subscription $subscriptionId \
  --assignee-object-id $assigneeObjectId \
  --assignee-principal-type ServicePrincipal \
  --scope /subscriptions/$subscriptionId/resourceGroups/$resourceGroupName

az ad app federated-credential create \
  --id $appIdRW \
  --parameters az-federated-credential-params/production-deploy.json
```

Repeated with `dib00016-githubactions-r`, the `reader` role, and the remaining two
parameter files.

---

## 4. GitHub Secrets

_Reference: [docs/4-github-secrets.md](docs/4-github-secrets.md)_

### Repository-level secrets

| Secret | Description | Set |
| ------ | ----------- | --- |
| `AZURE_TENANT_ID` | Entra ID tenant id | ✅ |
| `AZURE_SUBSCRIPTION_ID` | Azure subscription id | ✅ |
| `AZURE_CLIENT_ID` | appId of the **Reader** app registration (`dib00016-githubactions-r`) | ✅ |
| `ARM_ACCESS_KEY` | primary access key of the state storage account | ✅ |

### Environment-level secrets (`production`)

| Secret | Description | Set |
| ------ | ----------- | --- |
| `AZURE_CLIENT_ID` | appId of the **Contributor** app registration (`dib00016-githubactions-rw`) — overrides the repo-level value | ✅ |

Both levels define a secret named `AZURE_CLIENT_ID`. That is deliberate: GitHub gives
environment-level secrets precedence, so a job declaring `environment: production` receives
the contributor identity while every other job silently receives the reader one. The plan
job that runs on pull requests therefore cannot modify Azure even if its workflow were
altered to try.

> Secret **values** are never committed to this repository. Only the names and their
> purpose are documented here — the values live in
> `Settings > Secrets and variables > Actions` and in the `production` environment.

---

## 5. OIDC Authentication in Terraform

_Reference: [docs/5-use-oidc.md](docs/5-use-oidc.md)_

`use_oidc = true` is set in **two** places in `infra/tf-app/terraform.tf` — once in the
`backend` block, so Terraform can authenticate to read and write remote state, and once in
the `provider` block, so it can authenticate to manage Azure resources. These are separate
authentication paths and both are needed.

```hcl
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=4.1.0"
    }
  }
  backend "azurerm" {
    resource_group_name  = "dib00016-githubactions-rg"
    storage_account_name = "dib00016githubactions"
    container_name       = "tfstate"
    key                  = "prod.app.tfstate"
    use_oidc             = true
  }
}

provider "azurerm" {
  resource_provider_registrations = "none"
  features {}
  use_oidc = true
}
```

**Why OIDC instead of a client secret:** the alternative is generating a long-lived
password for the service principal and storing it as a GitHub secret. That secret works
from anywhere, for anyone who obtains it, until someone remembers to rotate it — and it has
to be copied between systems to be set up, which is itself a point of exposure.

With OIDC there is no stored password at all. GitHub mints a token per workflow run, valid
for minutes, and Azure only accepts it if the claims match a federated credential subject
naming this exact repository and context. Nothing in the repository or its settings can be
replayed by anyone else. That's why the secrets in section 4 are only *identifiers* —
tenant, subscription, and client ids — and contain no credential except `ARM_ACCESS_KEY`.

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

Branch: `infra-elements` → `main`

Resources added to `infra/tf-app`:

| Resource | Type | Name | Address space / prefix |
| -------- | ---- | ---- | ---------------------- |
| Virtual Network | `azurerm_virtual_network` | _TODO_ | _TODO_ |
| Subnet | `azurerm_subnet` | _TODO_ | _TODO_ |

Observed results:

1. **Push to `infra-elements`** → _TODO: static analysis workflow result_
2. **Open PR `infra-elements` → `main`** → _TODO: static analysis + integration test / plan
   result, plan comment posted on the PR_ 📸 **both submission screenshots are taken here**
3. **Approve & merge into `main`** → _TODO: deploy workflow result, including the
   `production` environment approval step_
4. **Azure Portal verification** → _TODO: confirm the VNet and Subnet exist_

_TODO (optional): link to the PR — https://github.com/XinyiZhao-cloud/cst8918-s26-a11/pull/N_

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

Work was split across 7 stacked pull requests, each targeting `main`, in the order the
assignment lists the steps. Each partner authored roughly half and reviewed and approved
the other half, so no change reached `main` without a second pair of eyes.

| PR | Description | Author | Reviewer |
| -- | ----------- | ------ | -------- |
| 1 | Foundation — Terraform backend, app infrastructure, Azure identities + federated credentials, OIDC (docs 2, 3, 5) | Mimi | Cindy |
| 2 | Static analysis workflow — `infra-static-tests.yml` (docs 6.0–6.1) | Mimi | Cindy |
| 3 | Integration-test job — plan-on-PR half of `infra-ci-cd.yml` (doc 6.2) | Mimi | Cindy |
| 4 | README — structure, team details, and write-up of docs 2, 3, 5 | Mimi | Cindy |
| 5 | Deploy job — apply-on-merge half of `infra-ci-cd.yml` (doc 6.3) | Cindy | Mimi |
| 6 | Drift-detection workflow — `infra-drift-detection.yml` (doc 6.4) | Cindy | Mimi |
| 7 | Add VNet + Subnet, run the full pipeline, screenshots, final README (doc 7) | Cindy | Mimi |

The repository-settings work in docs 1 and 4 — branch protection ruleset, the `production`
environment, and all repository and environment secrets — was done by Cindy as repository
owner. On a personal-account repository, only the owner can access the Settings tab, so
that half of the foundation step could not be split. Doc 1 and doc 4 produce no commits.

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
