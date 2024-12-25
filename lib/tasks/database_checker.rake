namespace :db do
  desc "Check database connections"
  task check_connections: :environment do
    roles = %w[primary cache queue cable]

    roles.each do |role|
      check_connection_for_role(role)
    end

    puts "✅ All database connections successful!"
  rescue => e
    puts "❌ Database check failed: #{e.message}"
    exit(1) # Exit with failure status for CI/CD pipelines
  end

  def check_connection_for_role(role)
    db_config = ActiveRecord::Base.configurations[Rails.env][role]
    raise "No database configuration found for role: #{role}" unless db_config

    db_host = db_config['host'] || 'localhost'
    db_user = db_config['username']
    db_password = db_config['password']
    db_name = db_config['database']

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
