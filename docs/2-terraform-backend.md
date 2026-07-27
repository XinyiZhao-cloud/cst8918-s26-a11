CST8918 - DevOps: Infrastructure as Code  
Prof. Robert McKenney

# Lab 12: Terraform CI/CD on Azure with GitHub Actions

## 2. Create Azure infrastructure to store Terraform state

As you will be using GitHub Actions to run Terraform, you will need to store the Terraform state file in a remote location. In this lab, you will use an Azure Storage Account to store the Terraform state file.

In last week's lab, you created the storage account and container manually using AZ CLI. This week, you will create them using a separate Terraform module. All of the Terraform configuration for the storage account and container should be created in the `infra/tf-backend` folder. This will keep the Terraform configuration for the storage account and container separate from the configuration for the AKS cluster.

> [!WARNING]
> The `tf-backend` and `tf-app` folders are separate Terraform configurations. Commands like `terraform init`, `terraform plan`, and `terraform apply` should be run in each folder separately.

The reason for separating the two configurations is because the storage account and container are used to store the Terraform state file for the app infrastructure configuration. If the backend infrastructure and app infrastructure are in the same configuration, you will run into a chicken-and-egg problem where the Terraform state file is stored in the storage account that is being created by Terraform.

### Create the backend Terraform configuration

This will be a simple configuration with only the necessary resources to store the Terraform state file. It can all go in the `main.tf` file. The configuration should include:

- the `terraform` block
- the `provider` block
- a resource group called `<your-college-id>-githubactions-rg`
- a storage account named `<your-college-id>githubactions`
- the storage account should require a minimum version of `TLS1_2`
- a container in the storage account called `tfstate` - make sure it is private

> [!TIP]
> Remember that the storage account name must be unique across all of Azure, and must be between 3 and 24 characters in length. **Use only lowercase letters and numbers.**

The output of the configuration should be the _resource group name_, _storage account name_, the _container name_ and the _primary access key_ (which will be added to the GitHub secrets). These will be the values that you need to use in the app infrastructure configuration's `backend` block.

### Verify the and deploy the backend Terraform configuration

You will deploy the backend Terraform configuration using your local AZ CLI credentials. You will need to have the Azure CLI installed and be logged in to your Azure account. Then you can run the following commands to validate and deploy the backend configuration.

```bash
cd infra/tf-backend
terraform init
terraform fmt
terraform validate
terraform plan --out=tf-backend.plan
terraform apply tf-backend.plan
```

## Create the base Terraform configuration for the app infrastructure

Setup the base base Terraform configuration for the app infrastructure in the `infra/tf-app` folder. Create a `terraform.tf` file that defines:

- the `terraform` block,
- the `provider` block,
- and the `terraform.backend` block.

The backend configuration should use the Azure Storage Account you created in the previous step, and the file name (key) should be `prod.app.tfstate`.

### Add a resource group

So that we can test the Terraform configuration, add a resource group in the `main.tf` file. The resource group should be named `<your-college-id>-a12-rg`.

### Test it!

Remember, one of the best practice strategies from software development is to develop in small increments and test often. Run the following commands to validate and deploy the Terraform configuration.

> [!IMPORTANT]
> Before you can test the Terraform configuration, you will need to set the `ARM_ACCESS_KEY` environment variable to the primary access key of the storage account. You can get this from the output of the backend Terraform configuration. You can set the environment variable with the following command:

```bash
# in the infra/tf-backend folder

export ARM_ACCESS_KEY=$(terraform output -raw arm_access_key)
```

Then you can run the following commands to validate and deploy the Terraform configuration.

```bash
# in the infra/tf-app folder

terraform init
terraform fmt
terraform validate
terraform plan --out=tf-app.plan
terraform apply tf-app.plan
```

- Verify that there were no errors in the output of the `terraform apply` command.
- Verify that the resource group was created in the Azure portal.
- Verify that the Terraform state file was created in the storage account.

OK - now you have the base Terraform configuration for the app infrastructure, and it correctly connects to Azure Blob Storage for the remote Terraform state file. You will add the AKS cluster and the deployment of the sample web application later in this lab. For now, you will complete the steps to create the GitHub Actions CI/CD workflows.
