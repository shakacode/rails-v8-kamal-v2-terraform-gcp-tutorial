# Terraform Google Cloud with Rails 8 App and Kamal v2
This repository contains a Rails 8 app with Terraform files for deploying the app on Google Cloud. The app uses Kamal v2 for deployment.

Why use Rails 8 with Terraform, Google Cloud, and Kamal v2?
1. **Infrastructure as Code**: Terraform allows you to define your infrastructure in code, making it easier to manage and scale. By using Terraform, you don't have to configure anything in the Google Cloud Console manually.
2. **Consistent Deployments**: With Terraform, you can ensure that your infrastructure is consistent across all environments. This helps in reducing errors and ensuring that your app runs smoothly.
3. Scripts to stand-up and tear-down the infrastructure: The Terraform files in this repository include scripts to create and destroy the infrastructure. This makes it easy to spin up a new environment for testing and tear it down when you're done. Don't pay for resources you're not using!
4. **Kamal v2**: Kamal v2 is a lightweight deployment tool that makes it easy to deploy Rails apps to Google Cloud. It handles the deployment process for you, so you don't have to worry about setting up Kubernetes clusters or managing containers.
5. **Rails 8**: Rails 8 is the latest version of the popular Ruby on Rails framework. It comes with many new features and improvements that make it easier to build web applications.
6. **Google Cloud**: Google Cloud is a powerful cloud platform that offers a wide range of services for building and deploying applications. By using Google Cloud, you can take advantage of its scalability, reliability, and security features.


## Requirements

1. [Google Cloud SDK](https://cloud.google.com/sdk/docs/install) with a gcloud account.
2. [Terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli).
3. Some domain name where you can add an A record to point to your server's IP address.
3. Docker
4. Ruby 3.3.4

## Setup
1. Clone this repository.
2. Create the Master Key: Run the following command to generate the development and test `master.key` and save it in the correct location:
  ```bash
  echo "94cd5f24badf3102a4c6a09eb4a4a516" > config/master.key
  ```
  Or just make a brand new one for development and test with `rails credentials:edit`.

2. Install the required gems:
   ```bash
   bundle install
   ```
3. Edit the `terraform-gcloud/variables.tf` file with your project details. 
4. Edit the `config/deploy.yml` file with your domain name (currently set to `kamal.shakacode.com`)
5. 


# Secrets and Credentials
Note: 
1. I originally created the example to work with 1Password. However, given that a GCP account is required, I decided to use the GCP Secret Manager.
2. To demonstrate best practices for handling secrets, we will NOT use rails credentials for production secrets. Instead, we will use the Google Cloud Secret Manager. Rails credentials are great for non-production environments.

## Google Cloud Secret Manager

1. Open the [Google Cloud Secret Manager](https://console.cloud.google.com/security/secret-manager).
2. Ensure that you have the correct project selected.
3. Click on "Create Secret" to add a new secret.
4. Add the following 3 secrets:
   - `KAMAL_REGISTRY_PASSWORD`: The password for the Docker registry.
   - `DB_PASSWORD`: The password for the database, as you like. 
   - `SECRET_KEY_BASE`: Generate with `rails secret`. 

# Database Setup and Migrations
The database is automatically created and migrated when the Rails app is deployed. This is done via the [bin/docker-entrypoint.sh](bin/docker-entrypoint.sh) script which calls `rails db:prepare`.

Note, the initial deployment will fail because the database schema needs to be created. This is expected. Just run `bundle exec kamal deploy` again after the initial setup.

# Deployment

1. To create the infrastructure on Google Cloud, run the following command:
   ```bash
   ./terraform-gcloud/bin/stand-up
   ```
2. Notice the outputted IP address. Add an A record to your domain name pointing to this IP address.
3. Deploy the Rails app using Kamal v2:
   ```bash
   bundle exec kamal setup
   ```
   Notice an error message. This will happen because the schema needs to created the first time.
4. Deploy the Rails app using Kamal v2:
   ```bash
   bundle exec kamal deploy
   ```

4. Visit your domain name in the browser to see your Rails app running on Google Cloud!  

# Tear Down

1. To destroy the infrastructure on Google Cloud, run the following command:
   ```bash
   ./terraform-gcloud/bin/tear-down
   ```
That's it!



# Troubleshooting
