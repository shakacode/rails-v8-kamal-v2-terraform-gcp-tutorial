# lib/database_checker.rb
require 'yaml'
require 'pg'
require 'erb'

class DatabaseChecker
  def self.check_connections(env: ENV['RAILS_ENV'] || 'production', config_path: 'config/database.yml')
    db_config_path = File.expand_path(config_path, Dir.pwd)
    raise "Database configuration file not found at #{db_config_path}" unless File.exist?(db_config_path)

    # Load and parse database.yml
    db_config = YAML.load(ERB.new(File.read(db_config_path)).result)
    raise "No database configuration found for environment: #{env}" unless db_config[env]

    # Define the database roles to check
    roles = %w[primary cache queue cable]

    # Check each database connection
    roles.each do |role|
      db_settings = db_config.dig(env, role)
      raise "No database configuration found for role: #{role}" unless db_settings

      check_connection_for_role(role, db_settings)
    end

    puts "✅ All database connections successful!"
    true
  rescue => e
    puts "❌ Database check failed: #{e.message}"
    false
  end

  private

  def self.check_connection_for_role(role, db_settings)
    # Extract database connection details
    db_host = db_settings['host'] || 'localhost'
    db_user = db_settings['username']
    db_password = db_settings['password']
    db_name = db_settings['database']

    # Attempt to connect to the database
    puts "Checking #{role} database connection for #{db_name}..."
    begin
      conn = PG.connect(
        host: db_host,
        user: db_user,
        password: db_password,
        dbname: db_name
      )
      puts "✅ Successfully connected to the #{role} database: #{db_name}."
    rescue PG::Error => e
      raise "Connection to #{role} database failed: #{e.message}"
    ensure
      conn&.close
    end
  end
end
