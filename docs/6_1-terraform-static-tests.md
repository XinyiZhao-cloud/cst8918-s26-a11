CST8918 - DevOps: Infrastructure as Code  
Prof. Robert McKenney

# Lab 12: Terraform CI/CD on Azure with GitHub Actions

## 6. Create the GitHub Actions workflows

### 6.1 Static code analysis

The first workflow will run static code analysis on the Terraform configuration. This will include running `terraform fmt` and `terraform validate` on the configuration.  It will also run [checkov](https://www.checkov.io/) to check for security issues.

This workflow will be triggered on _any push_ to _any branch_, ensuring that all commits pushed to the repository are checked for common errors.

Create a new GitHub Actions workflow in the `.github/workflows` folder (at the root of the repository) called `infra-static_tests.yml`. Add the following content to the file:


<details><summary>Show workflow details</summary>

```yaml
name: 'Terraform Static Tests'

on:
  push:

defaults:
  run:
    working-directory: ./infra/tf-app

permissions:
  actions: read
  contents: read
  security-events: write

jobs:
  terraform-static-tests:
    name: 'Terraform Static Tests'
    runs-on: ubuntu-latest
    
    steps:
    # Checkout the repository to the GitHub Actions runner
    - name: Checkout
      uses: actions/checkout@v4

    # Install the latest version of Terraform CLI and configure the Terraform CLI configuration file with a Terraform Cloud user API token
    - name: Setup Terraform
      uses: hashicorp/setup-terraform@v3

    # Initialize a new or existing Terraform working directory by creating initial files, loading any remote state, downloading modules, etc.
    # The -backend=false flag is used to prevent Terraform from using the remote backend, which is not needed for static tests.
    - name: Terraform Init
      run: terraform init -backend=false

    # Validate terraform files
    - name: Terraform Validate
      run: terraform validate

    # Checks that all Terraform configuration files adhere to a canonical format
    # Note: This will not modify files, but will exit with a non-zero status if any files need formatting
    - name: Terraform Format
      run: terraform fmt -check -recursive

    # Perform a security scan of the terraform code tfsec
    - name: tfsec
      uses: tfsec/tfsec-sarif-action@master
      with:
        sarif_file: tfsec.sarif         

    - name: Upload SARIF file
      uses: github/codeql-action/upload-sarif@v3
      with:
        # Path to SARIF file relative to the root of the repository
        sarif_file: tfsec.sarif
```
</details>

Commit the changes to your local repository and then push the changes to GitHub. The workflow will run automatically on the push to the repository. Check the results in the Actions tab of your repository.
