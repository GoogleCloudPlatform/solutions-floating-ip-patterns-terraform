/**
 * Copyright 2021 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

locals {
  image = "debian-cloud/debian-9"
  machine_type = "e2-small"
}

resource "google_project_service" "required_api" {
  for_each = toset(["compute.googleapis.com", "cloudresourcemanager.googleapis.com"])
  service  = each.key
}

resource "google_compute_network" "failover_vpc" {
  depends_on              = [google_project_service.required_api]
  name                    = "ip-failover"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "failover_subnet" {
  name          = "ip-failover-subnet"
  ip_cidr_range = var.subnet_range
  network       = google_compute_network.failover_vpc.id
}

resource "google_compute_firewall" "failover_firewall_http" {
  name = "failover-instances-http-traffic"
  allow {
    protocol = "tcp"
    ports    = [80]
  }
  network     = google_compute_network.failover_vpc.id
  source_tags = ["client"]
  target_tags = ["backend"]
}

resource "google_compute_firewall" "failover_firewall_ssh_iap" {
  name = "failover-ssh-iap"
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  network = google_compute_network.failover_vpc.id
  #IP range used by Identity-Aware-Proxy
  #See https://cloud.google.com/iap/docs/using-tcp-forwarding#create-firewall-rule
  source_ranges = ["35.235.240.0/20"]
}

resource "google_compute_firewall" "failover_firewall_hc" {
  name = "failover-hc"
  allow {
    protocol = "tcp"
    ports    = ["80"]
  }
  network = google_compute_network.failover_vpc.id
  #IP ranges used for health checks
  #See https://cloud.google.com/load-balancing/docs/health-check-concepts#ip-ranges
  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]
}

resource "google_compute_instance_template" "nginx_first_instance_template" {
  name_prefix  = "nginx-first-template"
  machine_type = local.machine_type
  disk {
    source_image = local.image
    auto_delete  = true
    boot         = true
  }
  metadata_startup_script = templatefile("startup-script.tmpl", {
    server_number = 1
    floating_ip   = var.floating_ip
  })
  can_ip_forward = true
  tags           = ["backend"]

  network_interface {
    subnetwork = google_compute_subnetwork.failover_subnet.id
    access_config {}
    network_ip = var.first_ip

  }
  lifecycle {
    create_before_destroy = true
  }
}
resource "google_compute_instance_template" "nginx_second_instance_template" {
  name_prefix  = "nginx-second-template"
  machine_type = local.machine_type
  disk {
    source_image = local.image
    auto_delete  = true
    boot         = true
  }

  metadata_startup_script = templatefile("startup-script.tmpl", {
    server_number = 2
    floating_ip   = var.floating_ip
  })
  can_ip_forward = true
  tags           = ["backend"]
  network_interface {
    subnetwork = google_compute_subnetwork.failover_subnet.id
    access_config {}
    network_ip = var.second_ip
  }
  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_health_check" "autohealing_http_check" {
  depends_on          = [google_project_service.required_api]
  name                = "autohealing-health-check"
  check_interval_sec  = 5
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 3
  http_health_check {
    port = 80
  }
}

resource "google_compute_instance_group_manager" "nginx_first_instance_group" {
  name               = "nginx-first"
  base_instance_name = "nginx-first"
  target_size        = 1
  version {
    instance_template = google_compute_instance_template.nginx_first_instance_template.id
  }
  auto_healing_policies {
    health_check      = google_compute_health_check.autohealing_http_check.id
    initial_delay_sec = 300
  }
}

resource "google_compute_instance_group_manager" "nginx_second_instance_group" {
  name               = "nginx-second"
  base_instance_name = "nginx-second"
  target_size        = 1

  version {
    instance_template = google_compute_instance_template.nginx_second_instance_template.id
  }
  auto_healing_policies {
    health_check      = google_compute_health_check.autohealing_http_check.id
    initial_delay_sec = 300
  }
}

resource "google_compute_route" "first_route" {
  depends_on = [google_compute_subnetwork.failover_subnet]

  name        = "floating-route-1"
  dest_range  = "${var.floating_ip}/32"
  network     = google_compute_network.failover_vpc.name
  next_hop_ip = var.first_ip
  priority    = 100
}

resource "google_compute_route" "second_route" {
  depends_on = [google_compute_subnetwork.failover_subnet]

  name        = "floating-route-2"
  dest_range  = "${var.floating_ip}/32"
  network     = google_compute_network.failover_vpc.name
  next_hop_ip = var.second_ip
  priority    = 100
}
resource "google_compute_instance" "client-vm" {
  name         = "client"
  machine_type = local.machine_type

  tags = ["client"]

  boot_disk {
    initialize_params {
      image = local.image
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.failover_subnet.name


  }

}