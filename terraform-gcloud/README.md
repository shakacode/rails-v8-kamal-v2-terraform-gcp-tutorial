# Google Cloud Terraform with Rails App
     
## Requirements
1. Update variables in `terraform-gcloud/variables.tf` with your project details.
2. Ensure you have the [Google Cloud SDK](https://cloud.google.com/sdk/docs/install) installed with a gcloud account.
3. Install [Terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli).

## Should Terraform files be in the same repository as a Rails app?

Yes, for a demo or small-scale example, you can mix Terraform files with your Rails app directory for simplicity. However, it’s important to keep a few best practices in mind to maintain clarity and scalability:

Suggested Setup for Simplicity:
	1.	Create a terraform Directory:
	•	Place all your Terraform files in a subdirectory within the Rails app, such as terraform/.
	•	Example structure:

my_rails_app/
├── app/
├── config/
├── db/
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── .terraform.lock.hcl
├── Gemfile
└── ...


	2.	Isolate State Files:
	•	Ensure that your terraform state files (e.g., terraform.tfstate) are either excluded from version control (via .gitignore) or stored remotely (e.g., in an S3 bucket for AWS setups).
	•	Example .gitignore entry:

terraform/.terraform/
terraform/terraform.tfstate*


	3.	Use a Separate Namespace:
	•	Use descriptive names for your Terraform resources to avoid conflicts if the Rails app scales or integrates with other infrastructure.
	4.	Add Documentation:
	•	Include a README.md in the terraform/ directory to explain how the Terraform setup interacts with the Rails app.

When to Separate Terraform Files:

For production-grade applications or long-term maintenance, it’s better to keep infrastructure as code (Terraform) in a separate repository or infrastructure-specific directory. This separation ensures:
	•	Clear Boundaries: Between application code and infrastructure management.
	•	Ease of Use: For teams managing either Rails development or infrastructure.
	•	Scalability: Simplifies infrastructure scaling and reusability.

If this demo involves terraform working closely with Rails deployment (e.g., provisioning databases, load balancers, etc.), you can tightly couple them temporarily, but plan for eventual decoupling as the setup grows.
