CST8918 - DevOps: Infrastructure as Code  
Prof. Robert McKenney

# Lab 12: Terraform CI/CD on Azure with GitHub Actions

## 6. Create the GitHub Actions workflows
### 6.4 Daily drift detection

Configuration drift is a common issue in infrastructure as code (IaC) environments. Drift occurs when the deployed infrastructure does not match the desired state defined in the Terraform configuration. This can happen due to manual changes made to the infrastructure, or changes made outside of the Terraform configuration, i.e. when there are a mix of tools being used.

The final workflow will run daily to detect drift between the deployed infrastructure and the Terraform configuration. This workflow will be triggered on a schedule (like a CRON task), running once a day.

If drift is detected, the workflow will create an issue in the repository to alert the team.

If there is no drift, the workflow will automatically close any open issues related to drift detection.

Create a new GitHub Actions workflow in the `.github/workflows` folder called `infra-drift-detection.yml`. Add the following content to the file.


<details><summary>Show workflow details</summary>

```yaml
name: 'Terraform Configuration Drift Detection'

on:
  workflow_dispatch: 
  schedule:
    - cron: '41 3 * * *' # runs nightly at 3:41 am

#Special permissions required for OIDC authentication
permissions:
  id-token: write
  contents: read
  issues: write

#These environment variables are used by the terraform azure provider to setup OIDD authenticate. 
env:
  ARM_CLIENT_ID: "${{ secrets.AZURE_CLIENT_ID }}"
  ARM_SUBSCRIPTION_ID: "${{ secrets.AZURE_SUBSCRIPTION_ID }}"
  ARM_TENANT_ID: "${{ secrets.AZURE_TENANT_ID }}"
  # This one is for the storage account that stores the terraform state
  ARM_ACCESS_KEY: "${{ secrets.ARM_ACCESS_KEY }}"

jobs:
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

    # If changes are detected, create a new issue
    - name: Publish Drift Report
      if: steps.tf-plan.outputs.exitcode == 2
      uses: actions/github-script@v7
      env:
        SUMMARY: "${{ steps.tf-plan-string.outputs.summary }}"
      with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          script: |
            const body = `${process.env.SUMMARY}`;
            const title = 'Terraform Configuration Drift Detected';
            const creator = 'github-actions[bot]'
          
            // Look to see if there is an existing drift issue
            const issues = await github.rest.issues.listForRepo({
              owner: context.repo.owner,
              repo: context.repo.repo,
              state: 'open',
              creator: creator,
              title: title
            })
              
            if( issues.data.length > 0 ) {
              // We assume there shouldn't be more than 1 open issue, since we update any issue we find
              const issue = issues.data[0]
              
              if ( issue.body == body ) {
                console.log('Drift Detected: Found matching issue with duplicate content')
              } else {
                console.log('Drift Detected: Found matching issue, updating body')
                github.rest.issues.update({
                  owner: context.repo.owner,
                  repo: context.repo.repo,
                  issue_number: issue.number,
                  body: body
                })
              }
            } else {
              console.log('Drift Detected: Creating new issue')

              github.rest.issues.create({
                owner: context.repo.owner,
                repo: context.repo.repo,
                title: title,
                body: body
             })
            }
            
    # If changes aren't detected, close any open drift issues
    - name: Publish Drift Report
      if: steps.tf-plan.outputs.exitcode == 0
      uses: actions/github-script@v7
      with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          script: |
            const title = 'Terraform Configuration Drift Detected';
            const creator = 'github-actions[bot]'
          
            // Look to see if there is an existing drift issue
            const issues = await github.rest.issues.listForRepo({
              owner: context.repo.owner,
              repo: context.repo.repo,
              state: 'open',
              creator: creator,
              title: title
            })
              
            if( issues.data.length > 0 ) {
              const issue = issues.data[0]
              
              github.rest.issues.update({
                owner: context.repo.owner,
                repo: context.repo.repo,
                issue_number: issue.number,
                state: 'closed'
              })
            } 
             
    # Mark the workflow as failed if drift detected 
    - name: Error on Failure
      if: steps.tf-plan.outputs.exitcode == 2
      run: exit 1
```

</details>


### Test it out

Commit the changes to your local repository and then push the changes to GitHub. The workflow will run at the next scheduled time, but you can test it by running the workflow manually in the Actions tab of your repository.

> [!TIP]
> You can only trigger the workflow manually if you have the `workflow_dispatch` event in the `on` section of the workflow file, and the workflow file is merged into the main branch.

You can simulate drift by making a manual change to the deployed infrastructure in the Azure portal. This could be changing a tag, adding a resource, or changing a configuration setting. When the workflow runs, it will detect the drift and create a new issue in the repository.
