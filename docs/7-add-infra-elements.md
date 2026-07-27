CST8918 - DevOps: Infrastructure as Code  
Prof. Robert McKenney

# Lab 12: Terraform CI/CD on Azure with GitHub Actions

## 7. Add some infrastructure elements

It is time to test everything out!

Create a new git branch called `infra-elements` and switch to it.

```sh
git checkout -b infra-elements
```

Update the Terraform configuration in the `infra/tf-app` folder to include the some additional resource elements:

- A Virtual Network
- A Subnet

Commit your changes and push them to the repository. This should trigger the GitHub Actions workflow for the static analysis.

On GitHub, create a pull request to merge the `infra-elements` branch into the `main` branch. This should trigger the testing workflow.

Check the GitHub Actions workflows to see the status of the pull request.

> [!IMPORTANT]
> Make sure to get your screenshots needed for the lab submission.

When everything is working as expected, approve and merge the pull request. You should now see the deployment workflow running.

When the deployment workflow is complete, check the Azure portal to verify that the new resources have been created.

### Cleanup

When you have finished with the lab, dont forget to run `terraform destroy` to clean up the resources.
