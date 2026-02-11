require "yaml"
require "json"
require "open3"

class DeploymentManager
  DEPLOY_TIMEOUT_WITH_SCHEMA_CHANGE = 120

  def initialize
    @root_dir = File.expand_path("../..", __FILE__)
    @terraform_dir = File.join(@root_dir, "terraform-gcloud")
    @deploy_yml_path = File.join(@root_dir, "config", "deploy.yml")

    load_config
  end

  def deploy
    puts "\n=== Starting Deployment ==="
    apply_terraform
    update_config
    verify_dns
    flush_local_dns_cache
    run_kamal
    restore_original_timeout
    puts "\n=== Deployment Complete ==="
  end

  def deployed_ip_matches_configured_ip?
    configured_ip = @config.dig("servers", "web")[0]
    if deployed_ip == configured_ip
      puts "✅ Deployed IP matches the configured IP: #{configured_ip}"
      true
    else
      puts "❌ Deployed IP does not match the configured IP. Deployed: #{deployed_ip}, Configured: #{configured_ip}"
      false
    end
  end

  private
  def resolved_host_is_deployed_ip
    resolve_dns == deployed_ip
  end

  def load_config
    raise "❌ deploy.yml not found at #{@deploy_yml_path}" unless File.exist?(@deploy_yml_path)
    @yaml_content = File.read(@deploy_yml_path)
    @config = YAML.safe_load(@yaml_content, permitted_classes: [ Date ], aliases: true)
    @host = @config.dig("proxy", "host")
  rescue => e
    abort "❌ Failed to load configuration: #{e.message}"
  end

  def apply_terraform
    log_step "Applying Terraform Infrastructure"
    execute_command_in_dir("terraform init", @terraform_dir, "❌ Terraform init failed!")
    import_static_ip_if_exists
    execute_command_in_dir("terraform apply -auto-approve", @terraform_dir, "❌ Terraform apply failed!")
  end

  def import_static_ip_if_exists
    # If the IP is already in Terraform state, nothing to do.
    _, status = Open3.capture2("terraform", "state", "show", "google_compute_address.rails_app_ip",
                               chdir: @terraform_dir, err: File::NULL)
    if status.success?
      puts "✅ Static IP already in Terraform state"
      return
    end

    project_id = parse_project_id_from_variables
    return unless project_id

    # Try to import a static IP preserved from a previous tear-down.
    puts "Checking for existing static IP to import..."
    import_id = "projects/#{project_id}/regions/us-central1/addresses/rails-app-ip"
    _, status = Open3.capture2("terraform", "import", "google_compute_address.rails_app_ip", import_id,
                               chdir: @terraform_dir, err: File::NULL)
    if status.success?
      puts "✅ Imported existing static IP — DNS and deploy.yml remain stable"
    else
      puts "ℹ️  No existing static IP found — Terraform will create a new one"
    end
  end

  def parse_project_id_from_variables
    vars_file = File.join(@terraform_dir, "variables.tf")
    return unless File.exist?(vars_file)

    File.read(vars_file)[/variable\s+"project_id".*?default\s*=\s*"([^"]+)"/m, 1]
  end

  def deployed_ip
    @deployed_ip ||= begin
                       output, status = Open3.capture2("terraform", "output", "-json", chdir: @terraform_dir)
                       abort("❌ terraform output failed (exit #{status.exitstatus})") unless status.success?
                       terraform_output = JSON.parse(output)
                       ip = terraform_output.dig("instance_ip", "value") or abort("❌ Missing instance_ip in Terraform output")
                       puts "✅ Deployed IP acquired: #{ip}"
                       ip
                     end
  end

  def update_config
    log_step "Updating Configuration"
    old_ip = @config.dig("servers", "web")[0]
    @ip_changed = old_ip != deployed_ip
    @old_timeout = @config["deploy_timeout"]
    puts "Old timeout was set to #{@old_timeout} seconds"

    update_ip_in_config(old_ip, deployed_ip)
    update_timeout_in_config

    File.write(@deploy_yml_path, @yaml_content)
    @config = YAML.safe_load(@yaml_content, permitted_classes: [ Date ], aliases: true)

    puts "✅ Updated deploy.yml with new IP and timeout"
    puts "✅ Timeout is now set to #{@config['deploy_timeout']} seconds"
  end

  def update_ip_in_config(old_ip, new_ip)
    @yaml_content.sub!(old_ip, new_ip)
  end

  def update_timeout_in_config
    if @yaml_content.match?(/deploy_timeout:\s*\d+\s*($|#)/)
      @yaml_content.gsub!(/deploy_timeout:\s*\d+\s*($|#)/, "deploy_timeout: #{DEPLOY_TIMEOUT_WITH_SCHEMA_CHANGE}\\1")
    else
      @yaml_content << "\ndeploy_timeout: #{DEPLOY_TIMEOUT_WITH_SCHEMA_CHANGE}\n"
    end
  end

  def verify_dns
    log_step "Verifying DNS Configuration"

    # Initial DNS check before asking for update
    if resolved_host_is_deployed_ip
      puts "\n✅ DNS verification successful! #{@host} → deployed IP #{deployed_ip}"
      return
    end

    subdomain = @host.split(".").first
    domain = @host.split(".").drop(1).join(".")

    puts "Edit DNS for `#{domain}`: Update or add a DNS Type `A` record, Name: `#{subdomain}`, Value: `#{deployed_ip}`"

    loop do
      print "Press return to check DNS (or Ctrl-C to exit): "
      gets.strip

      print "\rChecking DNS..."
      if resolved_host_is_deployed_ip
        puts "\n✅ DNS verification successful! #{@host} → #{deployed_ip}"
        return
      end

      puts "\n⏳ Current DNS: #{resolve_dns || 'not resolved'} (Expected: #{deployed_ip})"
    end
  end

  def flush_local_dns_cache
    return unless @ip_changed

    # dig (used by verify_dns) queries DNS servers directly, bypassing the OS cache.
    # The browser and other apps use the OS cache, which may still have the old IP.
    log_step "Flushing local DNS cache"
    if RUBY_PLATFORM.include?("darwin")
      puts "IP address changed — flushing macOS DNS cache..."
      system("sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder")
    elsif File.exist?("/usr/bin/systemd-resolve") || File.exist?("/usr/bin/resolvectl")
      puts "IP address changed — flushing Linux DNS cache..."
      system("sudo systemd-resolve --flush-caches 2>/dev/null || sudo resolvectl flush-caches 2>/dev/null")
    else
      puts "IP address changed — you may need to flush your local DNS cache manually."
    end
  end

  def resolve_dns
    output, = Open3.capture2("dig", "+short", @host)
    output.lines.find { |line| line.match?(/^\d{1,3}(\.\d{1,3}){3}$/) }&.strip
  rescue => e
    puts "\n❌ Error during DNS verification: #{e.message}"
    false
  end

  def run_kamal
    log_step "Running Kamal Setup"
    execute_command_in_dir("bundle exec kamal setup", @root_dir, "❌ Kamal setup failed!")
    puts "\n=== Kamal Details ==="
    execute_command_in_dir("bundle exec kamal details", @root_dir, "❌ Kamal details failed!")
  end

  def restore_original_timeout
    @yaml_content.gsub!(/deploy_timeout:\s*\d+\s*($|#)/, "deploy_timeout: #{@old_timeout}\\1")
    @yaml_content << "\n" unless @yaml_content.end_with?("\n")
    File.write(@deploy_yml_path, @yaml_content)
    puts "✅ Restored timeout configuration to #{@old_timeout} seconds"
  end

  def log_step(message)
    puts "\n=== #{message} ==="
  end

  def execute_command_in_dir(command, dir, error_message)
    green = "\e[32m"
    reset = "\e[0m"
    puts "🛠️ Executing: #{green}#{command}#{reset}\n\n"
    status_ok = nil
    start_time = Time.now
    Dir.chdir(dir) do
      status_ok = system(command)
    end
    end_time = Time.now
    duration = end_time - start_time
    minutes = (duration / 60).to_i
    seconds = (duration % 60).round(2)
    puts "⏱️ Command '#{command}' took #{minutes} minutes and #{seconds} seconds to execute.\n\n"
    abort(error_message) unless status_ok
  end
end
