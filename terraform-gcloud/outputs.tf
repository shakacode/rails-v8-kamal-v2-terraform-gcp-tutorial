# Outputs
output "instance_ip" {
  description = "The external IP of the Compute Engine instance"
  value       = google_compute_instance.rails_app.network_interface[0].access_config[0].nat_ip
}

output "db_instance_connection_name" {
  description = "The connection name for the Cloud SQL instance"
  value       = google_sql_database_instance.rails_db_instance.connection_name
}

output "db_user" {
  description = "The database username for the application"
  value       = google_sql_user.rails_db_user.name
}

output "db_primary_name" {
  description = "The name of the primary production database"
  value       = google_sql_database.rails_database_primary.name
}

output "db_cache_name" {
  description = "The name of the cache production database"
  value       = google_sql_database.rails_database_cache.name
}

output "db_queue_name" {
  description = "The name of the queue production database"
  value       = google_sql_database.rails_database_queue.name
}

output "db_cable_name" {
  description = "The name of the cable production database"
  value       = google_sql_database.rails_database_cable.name
}
