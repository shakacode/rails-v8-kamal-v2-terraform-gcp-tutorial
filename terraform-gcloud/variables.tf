variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  default     = "kamal-demo-444506" # This is the ID, not the name, of your project
}

variable "ssh_user" {
  description = "The SSH username to access the instance"
  type        = string
  default     = "justin" # Replace with your preferred SSH username
}
