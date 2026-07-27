CST8918 - DevOps: Infrastructure as Code  
Prof. Robert McKenney

# Lab 12: Terraform CI/CD on Azure with GitHub Actions

## 3. Create Azure credentials to be used by GitHub Actions

In order to allow GitHub Actions to automate CI/CD tasks, you need to create a service account that GitHub will use to authenticate with Azure. Following the best practice of granting the least required privilege, you will create two accounts. 

The first will be used for jobs requiring read-only access. These will be pre-deployment validation tasks.

The second will be used for deploying your infrastructure and applications. This will need read/write access.

### Before you start

You will need your Azure subscription ID and Azure tenant ID. You can look up these details with the `az account show` command. In the output, you will see the `id` (subscription ID) and `tenantId` fields. Copy these for use in later steps.

To make it easier to insert these values in CLI commands, you can capture the output of the commands and assign them to shell environment variables, like this.

```bash
export subscriptionId=$(az account show --query id -o tsv)
export tenantId=$(az account show --query tenantId -o tsv)
```

You will also need the name of the resource group that you created in the previous step. You can get this with the `terraform output` command.

```bash
# in the infra/tf-app folder
export resourceGroupName=$(terraform output -raw resource_group_name)
```

### Create a pair of Azure AD applications with service principals

The next step is to create an Azure AD application and service principal. In a later step you will attach _federated credentials_ that will be used by GitHub Actions to authenticate with Azure.

You will create two Azure AD applications and service principals. One will have the `contributor` role for the resource group, and the other will have the `reader` role. The `contributor` role will be used to deploy the AKS cluster and the sample web application. The `reader` role will be used to read the Terraform state file from the storage account and validate the current state of the infrastructure.

**These commands will all be run in the Azure CLI.**

> [!TIP]
> See the full documentation at [learn.microsoft.com](https://docs.microsoft.com/en-us/azure/active-directory/develop/quickstart-register-app)

#### For the `contributor` role

Create an Azure AD application with the display name `<your-college-id>-githubactions-rw`. Note the `-rw` for read/write.

```bash
az ad app create --display-name <your-college-id>-githubactions-rw
```

Copy the `appId` property from the JSON output. You will need this later as one of the GitHub secrets and in some other CLI commands. You can assign it to a shell environment variable like this.

```bash
export appIdRW=<appId>
```

Now use that `appId` to create a service principal.

```bash
az ad sp create --id $appIdRW
```

Get the object id of the service principal

```bash
export assigneeObjectId=$(az ad sp show --id $appIdRW --query id -o tsv)
```

Assign the `contributor` role to the service principal for your project's resource group.

```bash
az role assignment create \
  --role contributor \
  --subscription $subscriptionId \
  --assignee-object-id $assigneeObjectId \
  --assignee-principal-type ServicePrincipal \
  --scope /subscriptions/$subscriptionId/resourceGroups/$resourceGroupName
```

> [!TIP]
> The scope of the role assignment should be the resource group that you created in the Terraform configuration.
> You _could_ assign the role to a broader scope like the subscription, but it is a best practice to scope the role assignment to the smallest scope necessary.

#### Repeat those steps for the `reader` role

Create an Azure AD application with the display name `<your-college-id>-githubactions-r`. Note the `-r` for read.

```bash
az ad app create --display-name <your-college-id>-githubactions-r
```

Copy the `appId` property from the JSON output. You will need this later as one of the GitHub secrets.

```bash
export appIdR=<appId>
```

Now, use that `appId` to create a service principal.

```bash
az ad sp create --id $appIdR
```

Get the object id of the service principal

```bash
export assigneeObjectId=$(az ad sp show --id $appIdR --query id -o tsv)
```

Assign the `reader` role to the service principal for your project's resource group.

```bash
az role assignment create \
  --role reader \
  --subscription $subscriptionId \
  --assignee-object-id $assigneeObjectId \
  --assignee-principal-type ServicePrincipal \
  --scope /subscriptions/$subscriptionId/resourceGroups/$resourceGroupName
```

### Create three Federated Credentials

**The first** will be for the GitHub Actions triggered in the `production` environment, i.e. when a pull request is merged to the `main` branch. This will map to the `contributor` service principal with read/write access to the resource group.

> [!TIP]
> See the full documentation for Federated Credentials at [learn.microsoft.com](https://docs.microsoft.com/en-us/cli/azure/ad/app/federated-credential?view=azure-cli-latest)

The `az ad app federated-credential create` command will create a new federated credential for the Azure AD application specified by the `--id` argument. The `--parameters` argument specifies the path to a JSON file that contains the configuration parameters for the new federated credential.

Create a new file at the path `infra/az-federated-credential-params/production-deploy.json` with the following contents. Replace `<your-github-username>` and `<repo-name>` with your GitHub username and the name of your repository.

```json
{
  "name": "production-deploy",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:<your-github-username>/<repo-name>:environment:production",
  "description": "CST8918 Lab12 - GitHub Actions",
  "audiences": ["api://AzureADTokenExchange"]
}
```

Then run the AZ CLI command to create the federated credential for the `contributor` service principal with read/write access to the resource group. Use the shell environment variable `$appIdRW` with the `appId` of the Azure AD application you created earlier.

```bash
# in the infra folder
az ad app federated-credential create \
  --id $appIdRW \
  --parameters az-federated-credential-params/production-deploy.json
```

**The second credential** will be for the GitHub Actions that run pre-merge checks. This credential will map to the `reader` service principal with read-only access to the resource group. This time use the `appIdR` shell environment variable.

Create a new file at the path `infra/az-federated-credential-params/pull-request.json` with the following contents.

```json
{
  "name": "pull-request",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:<your-github-username>/<repo-name>:pull_request",
  "description": "CST8918 Lab12 - GitHub Actions",
  "audiences": ["api://AzureADTokenExchange"]
}
```

Create the credential with the following command.

```bash
# in the infra folder
az ad app federated-credential create \
  --id $appIdR \
  --parameters az-federated-credential-params/pull-request.json
```

**The third credential** will be for the GitHub Actions that run on any push or pull request event on the main branch. This will again map to the `reader` service principal with read-only access to the resource group.

Create a new file at the path `infra/az-federated-credential-params/branch-main.json` with the following contents.

```json
{
  "name": "branch-main",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:<your-github-username>/<repo-name>:branch:main",
  "description": "CST8918 Lab12 - GitHub Actions",
  "audiences": ["api://AzureADTokenExchange"]
}
```

Create the credential with the following command.

```bash
# in the infra folder
az ad app federated-credential create \
  --id $appIdR \
  --parameters az-federated-credential-params/branch-main.json
```

OK. You now have the access credentials that GitHub will use to authenticate with Azure. These credentials are stored in the Azure Active Directory and are used by the GitHub Actions to access the Azure resources.
