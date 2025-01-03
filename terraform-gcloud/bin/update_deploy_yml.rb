#!/usr/bin/env ruby

# This script is used to update the deploy.yml file with the server IP address
# after the Terraform infrastructure is created.
# Usage: ruby update_deploy_yml.rb
# Note: Update the deploy_yml_path variable to point to your deploy.yml file.

require 'json'

# Fetch the Terraform output
terraform_output = Dir.chdir(File.expand_path('..', __dir__)) { `terraform output -json` }
output = JSON.parse(terraform_output)
#
# Define the full path to the deploy.yml file
deploy_yml_path = File.expand_path('../../../config/deploy.yml', __FILE__)
puts "Using deploy.yml path: #{deploy_yml_path}"

# Check if the instance_ip key exists
if output.key?('instance_ip') && output['instance_ip'].key?('value')
  instance_ip = output['instance_ip']['value']
  puts "Found instance IP: #{instance_ip}"

  # Check if the deploy.yml file exists
  if File.exist?(deploy_yml_path)
    # Read and update the deploy.yml file
    deploy_yml_content = File.read(deploy_yml_path)
    updated_content = deploy_yml_content.gsub(/- \d+\.\d+\.\d+\.\d+/, "- #{instance_ip}")
    File.write(deploy_yml_path, updated_content)
    puts "deploy.yml updated with instance IP: #{instance_ip}"
  else
    puts "Error: deploy.yml file not found at path: #{deploy_yml_path}"
  end
else
  puts "Error: 'instance_ip' key not found in Terraform output"
end
