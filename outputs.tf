output "external_ip" {
  description = "This is the external IP address of your Load Balancer:"
  value       = google_compute_address.external.address
}
