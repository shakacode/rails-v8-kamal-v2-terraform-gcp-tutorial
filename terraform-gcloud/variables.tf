# This file contains the variables that will be used in the main configuration file
# (main.tf). The variables are defined with a name, description, type, and default value.
# The default value is used when no value is provided when running Terraform commands.
# The variables are referenced in the main configuration file using the var.<variable_name>
# syntax. For example, var.project_id references the project_id variable defined in this file.

# project_id corresponds to your GCP project ID, (not the project name)
variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  default     = "kamal-demo-444506" # This is the ID, not the name, of your project
}

# ssh_user is the SSH username that will be used to access the instance.
# This is the username that you use to SSH into the instance. The default value is justin.
# You need to change this to whatever you will use to SSH into the instance.

# explain how to set up ssh with gcp
# https://cloud.google.com/compute/docs/instances/connecting-advanced#thirdpartytools

variable "ssh_user" {
  description = "The SSH username to access the instance"
  type        = string
  default     = "justin" # Replace with your preferred SSH username
}
