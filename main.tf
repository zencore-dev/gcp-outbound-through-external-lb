resource "google_project_service" "compute" {
  service = "compute.googleapis.com"
  provisioner "local-exec" {
    command = <<-EOT
      gcloud compute firewall-rules list --format 'value(name)' --project=${var.project_id} | xargs gcloud compute firewall-rules delete -q
      gcloud -q compute networks delete default --project=${var.project_id}
    EOT
  }
}

data "google_compute_zones" "main" {
  depends_on = [google_project_service.compute]
}

resource "google_compute_network" "untrusted" {
  name                            = "untrusted"
  auto_create_subnetworks         = false
  delete_default_routes_on_create = true
  depends_on                      = [google_project_service.compute]
}

resource "google_compute_network" "trusted" {
  name                            = "trusted"
  auto_create_subnetworks         = false
  delete_default_routes_on_create = true
  depends_on                      = [google_project_service.compute]
}

resource "google_compute_subnetwork" "untrusted" {
  ip_cidr_range = "10.0.0.0/16"
  name          = "untrusted-subnet"
  network       = google_compute_network.untrusted.self_link
  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 1
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_subnetwork" "trusted" {
  ip_cidr_range = "10.1.0.0/16"
  name          = "trusted-subnet"
  network       = google_compute_network.trusted.self_link
  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 1
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_firewall" "allow_untrusted" {
  name          = "allow-untrusted"
  network       = google_compute_network.untrusted.self_link
  source_ranges = ["0.0.0.0/0"]
  allow {
    protocol = "all"
  }
}

resource "google_compute_firewall" "allow_trusted" {
  name          = "allow-trusted"
  network       = google_compute_network.trusted.self_link
  source_ranges = ["0.0.0.0/0"]
  allow {
    protocol = "all"
  }
}

resource "google_compute_address" "external" {
  name       = "external-ip"
  depends_on = [google_project_service.compute]
}

resource "google_compute_instance" "workload" {
  machine_type = "e2-micro"
  name         = "workload"
  zone         = data.google_compute_zones.main.names[0]
  tags         = ["workload"]
  boot_disk {
    initialize_params {
      image = "debian-11-bullseye-v20230206"
      size  = 10
      type  = "pd-balanced"
    }
  }
  network_interface {
    subnetwork = google_compute_subnetwork.trusted.self_link
  }
}

resource "google_compute_instance" "nat" {
  count          = 2
  machine_type   = "e2-micro"
  zone           = data.google_compute_zones.main.names[0]
  name           = "nat-${count.index + 1}"
  tags           = ["nat"]
  can_ip_forward = true
  boot_disk {
    initialize_params {
      image = "debian-11-bullseye-v20230206"
      size  = 10
      type  = "pd-balanced"
    }
  }
  network_interface {
    subnetwork = google_compute_subnetwork.untrusted.self_link
  }
  network_interface {
    subnetwork = google_compute_subnetwork.trusted.self_link
  }
  metadata = {
    startup-script = <<-EOT
      sysctl -w net.ipv4.ip_forward=1
      iptables -t nat -A POSTROUTING -o ens4 -j SNAT --to-source ${google_compute_address.external.address}
      ip addr add ${google_compute_address.external.address} br ${google_compute_address.external.address} dev ens4
      ip route change default via 10.0.0.1 src ${google_compute_address.external.address}
      ip route add 130.211.0.0/22 via 10.1.0.1
    EOT
  }
}

resource "google_compute_instance_group" "main" {
  count     = 2
  name      = "ig-nat-${count.index + 1}"
  zone      = data.google_compute_zones.main.names[0]
  instances = [google_compute_instance.nat[count.index].self_link]
}

resource "google_compute_region_health_check" "port_22" {
  depends_on          = [google_project_service.compute]
  name                = "ssh-health-check"
  check_interval_sec  = 1
  healthy_threshold   = 1
  timeout_sec         = 1
  unhealthy_threshold = 1
  tcp_health_check {
    port = 22
  }
}

resource "google_compute_region_backend_service" "external" {
  provider              = google-beta
  name                  = "external-lb"
  load_balancing_scheme = "EXTERNAL"
  protocol              = "UNSPECIFIED"
  health_checks         = [google_compute_region_health_check.port_22.self_link]
  backend {
    group = google_compute_instance_group.main[0].self_link
  }
  backend {
    group    = google_compute_instance_group.main[1].self_link
    failover = true
  }
  connection_tracking_policy {
    tracking_mode                                = "PER_SESSION"
    connection_persistence_on_unhealthy_backends = "NEVER_PERSIST"
  }
}

resource "google_compute_forwarding_rule" "external" {
  name            = "external-lb"
  ip_address      = google_compute_address.external.address
  all_ports       = true
  backend_service = google_compute_region_backend_service.external.id
  ip_protocol     = "L3_DEFAULT"
}

resource "google_compute_region_backend_service" "internal" {
  provider                        = google-beta
  name                            = "internal-lb"
  connection_draining_timeout_sec = 300
  network                         = google_compute_network.trusted.self_link
  health_checks                   = [google_compute_region_health_check.port_22.self_link]
  backend {
    group = google_compute_instance_group.main[0].self_link
  }
  backend {
    group    = google_compute_instance_group.main[1].self_link
    failover = true
  }
  failover_policy {
    disable_connection_drain_on_failover = false
    drop_traffic_if_unhealthy            = false
    failover_ratio                       = 0
  }
}

resource "google_compute_forwarding_rule" "internal" {
  name                  = "internal-lb-forwarding-rule"
  load_balancing_scheme = "INTERNAL"
  all_ports             = true
  subnetwork            = google_compute_subnetwork.trusted.self_link
  backend_service       = google_compute_region_backend_service.internal.id
}

resource "google_compute_route" "default_trusted" {
  dest_range   = "0.0.0.0/0"
  priority     = 1
  name         = "default-route-trusted"
  network      = google_compute_network.trusted.self_link
  next_hop_ilb = google_compute_forwarding_rule.internal.self_link
}
