CST8918 - DevOps: Infrastructure as Code  
Prof. Robert McKenney

# Lab 12: Terraform CI/CD on Azure with GitHub Actions

## 6. Create the GitHub Actions workflows

### 6.3 Terraform deploy

The third workflow will deploy the Terraform configuration to Azure. This workflow will be triggered on a merge to the main branch from a pull-request.

Update the GitHub Actions workflow in the `.github/workflows` folder called `infra-ci-cd.yml`. 

Add the following content to the bottom of the file.

<details><summary>Show workflow details</summary>

```yaml
# This will only run if the terraform plan has changes, and when the PR is approved and merged to main.
  terraform-apply:
    name: 'Terraform Apply'
    if: github.ref == 'refs/heads/main' && needs.terraform-plan.outputs.tfplanExitCode == 2
    runs-on: ubuntu-latest
    environment: production
    needs: [terraform-plan]
    
    steps:
    # Checkout the repository to the GitHub Actions runner
    - name: Checkout
      uses: actions/checkout@v4

    # Install the latest version of Terraform CLI and configure the Terraform CLI configuration file with a Terraform Cloud user API token
    - name: Setup Terraform
      uses: hashicorp/setup-terraform@v3

    # Initialize a new or existing Terraform working directory by creating initial files, loading any remote state, downloading modules, etc.
    - name: Terraform Init
      run: terraform init

    # Download saved plan from artifacts  
    - name: Download Terraform Plan
      uses: actions/download-artifact@v4
      with:
        name: tfplan

    # Terraform Apply
    - name: Terraform Apply
      run: terraform apply -auto-approve tfplan
```

</details>

This workflow will only run if the terraform plan has changes, and when the PR is approved and merged to the `main` branch. The workflow will use the production environment, and therefore the Azure clientID with read/write permission. The workflow will depend on the `terraform-plan` job to have previously completed successfully.
