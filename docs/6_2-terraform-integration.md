CST8918 - DevOps: Infrastructure as Code  
Prof. Robert McKenney

# Lab 12: Terraform CI/CD on Azure with GitHub Actions

## 6. Create the GitHub Actions workflows

### 6.2 Integration tests

The second workflow will run integration tests on the Terraform configuration. This will include running `terraform init`, `terraform plan`, and `tflint` to check for common errors and best practices. These are more computationally expensive than the static tests, so they will only be run on _pull requests_ or push to the _main branch_.

> [!TIP]
> You could also include any Terratest tests in this workflow, but we will not be using Terratest in this lab.

Create a new GitHub Actions workflow in the `.github/workflows` folder called `infra-ci-cd.yml`. 

Add the following content to the file.

<details><summary>Show workflow details</summary>

```yaml
name: Terraform CI-CD
on:
  push:
    branches: [ main ]
  pull_request:

#Special permissions required for OIDC authentication
permissions:
  id-token: write
  contents: read
  pull-requests: write

#These environment variables are used by the terraform azure provider to setup OIDD authenticate. 
env:
  ARM_CLIENT_ID: "${{ secrets.AZURE_CLIENT_ID }}"
  ARM_SUBSCRIPTION_ID: "${{ secrets.AZURE_SUBSCRIPTION_ID }}"
  ARM_TENANT_ID: "${{ secrets.AZURE_TENANT_ID }}"
  ARM_ACCESS_KEY: "${{ secrets.ARM_ACCESS_KEY }}"

defaults:
  run:
    working-directory: ./infra/tf-app  
  
jobs:
  tflint:
    runs-on: ubuntu-latest

    steps:
    - uses: actions/checkout@v4
      name: Checkout source code

    - uses: actions/cache@v4
      name: Cache plugin dir
      with:
        path: ~/.tflint.d/plugins
        key: tflint-${{ hashFiles('.tflint.hcl') }}

    - uses: terraform-linters/setup-tflint@v4
      name: Setup TFLint
      with:
        tflint_version: latest

    - name: Show version
      run: tflint --version

    - name: Init TFLint
      run: tflint --init
      env:
        # https://github.com/terraform-linters/tflint/blob/master/docs/user-guide/plugins.md#avoiding-rate-limiting
        GITHUB_TOKEN: ${{ github.token }}

    - name: Run TFLint
      id: tflint
      run: tflint -f compact
```
</details>

That will run the `tflint` tool. Now, at the bottom of the file, add the instructions to run Terraform plan and publish the result to the GitHub PR discussion thread.

<details><summary>Show additional workflow details</summary>

```yaml
  
  terraform-plan:
    name: 'Terraform Plan'
    runs-on: ubuntu-latest
    env:
      #this is needed since we are running terraform with read-only permissions
      ARM_SKIP_PROVIDER_REGISTRATION: true
    outputs:
      tfplanExitCode: ${{ steps.tf-plan.outputs.exitcode }}

    steps:
    # Checkout the repository to the GitHub Actions runner
    - name: Checkout
      uses: actions/checkout@v4

    # Install the latest version of the Terraform CLI
    - name: Setup Terraform
      uses: hashicorp/setup-terraform@v3
      with:
        terraform_wrapper: false

    # Initialize a new or existing Terraform working directory by creating initial files, loading any remote state, downloading modules, etc.
    - name: Terraform Init
      run: terraform init

    # Checks that all Terraform configuration files adhere to a canonical format
    # Will fail the build if not
    - name: Terraform Format
      run: terraform fmt -check

    # Generates an execution plan for Terraform
    # An exit code of 0 indicated no changes, 1 a terraform failure, 2 there are pending changes.
    - name: Terraform Plan
      id: tf-plan
      run: |
        export exitcode=0
        terraform plan -detailed-exitcode -no-color -out tfplan || export exitcode=$?

        echo "exitcode=$exitcode" >> $GITHUB_OUTPUT
        
        if [ $exitcode -eq 1 ]; then
          echo Terraform Plan Failed!
          exit 1
        else 
          exit 0
        fi
        
    # Save plan to artifacts  
    - name: Publish Terraform Plan
      uses: actions/upload-artifact@v4
      with:
        name: tfplan
        path: tfplan
        
    # Create string output of Terraform Plan
    - name: Create String Output
      id: tf-plan-string
      run: |
        TERRAFORM_PLAN=$(terraform show -no-color tfplan)
        
        delimiter="$(openssl rand -hex 8)"
        echo "summary<<${delimiter}" >> $GITHUB_OUTPUT
        echo "## Terraform Plan Output" >> $GITHUB_OUTPUT
        echo "<details><summary>Click to expand</summary>" >> $GITHUB_OUTPUT
        echo "" >> $GITHUB_OUTPUT
        echo '```terraform' >> $GITHUB_OUTPUT
        echo "$TERRAFORM_PLAN" >> $GITHUB_OUTPUT
        echo '```' >> $GITHUB_OUTPUT
        echo "</details>" >> $GITHUB_OUTPUT
        echo "${delimiter}" >> $GITHUB_OUTPUT
        
    # Publish Terraform Plan as task summary
    - name: Publish Terraform Plan to Task Summary
      env:
        SUMMARY: ${{ steps.tf-plan-string.outputs.summary }}
      run: |
        echo "$SUMMARY" >> $GITHUB_STEP_SUMMARY
      
    # If this is a PR post the changes
    - name: Push Terraform Output to PR
      if: github.ref != 'refs/heads/main'
      uses: actions/github-script@v7
      env:
        SUMMARY: "${{ steps.tf-plan-string.outputs.summary }}"
      with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          script: |
            const body = `${process.env.SUMMARY}`;
            github.rest.issues.createComment({
                issue_number: context.issue.number,
                owner: context.repo.owner,
                repo: context.repo.repo,
                body: body
            })

```
</details>


#### Add tflint configuration
In the `infra/tf-app` directory, create a new file called `.tflint.hcl` and add the following content.

```hcl
plugin "terraform" {
  enabled = true
  preset  = "all"
}

plugin "azurerm" {
  enabled = true
  version = "0.25.1"
  source  = "github.com/terraform-linters/tflint-ruleset-azurerm"
}
```

Commit the changes to your local repository and then push the changes to GitHub. The workflow will run automatically when you open a pull request. 

**Check the results in the PR discussion thread.**
