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
  name = "failover-ilb-http-traffic"
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
    ports    = [var.health_check_port]
  }
  network = google_compute_network.failover_vpc.id
  #IP ranges used for health checks
  #See https://cloud.google.com/load-balancing/docs/health-check-concepts#ip-ranges
  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]
}

resource "google_compute_firewall" "failover_firewall_vrrp" {
  name = "failover-vrrp"
  allow {
    #112 is VRRP IP protocol number required for keepalived communication
    protocol = "112"
  }
  network     = google_compute_network.failover_vpc.id
  source_tags = ["backend"]
  target_tags = ["backend"]
}

resource "google_compute_instance_template" "nginx_primary_instance_template" {
  name_prefix  = "nginx-primary-"
  machine_type = local.machine_type
  disk {
    source_image = local.image
    auto_delete  = true
    boot         = true
  }
  metadata_startup_script = templatefile("startup-script.tmpl", {
    server_number     = 1
    health_check_port = var.health_check_port
    ip                = var.primary_ip
    peer_ip           = var.secondary_ip
    state             = "MASTER"
    priority          = 100
    vrrp_password     = var.vrrp_password
  })
  tags = ["backend"]

  network_interface {
    subnetwork = google_compute_subnetwork.failover_subnet.id
    network_ip = var.primary_ip
    access_config {}
  }

  lifecycle {
    create_before_destroy = true
  }
}
resource "google_compute_instance_template" "nginx_secondary_instance_template" {
  name_prefix  = "nginx-secondary-"
  machine_type = local.machine_type
  disk {
    source_image = local.image
    auto_delete  = true
    boot         = true
  }
  metadata_startup_script = templatefile("startup-script.tmpl", {
    server_number     = 2
    health_check_port = var.health_check_port
    ip                = var.secondary_ip
    peer_ip           = var.primary_ip
    state             = "BACKUP"
    priority          = 50
    vrrp_password     = var.vrrp_password
  })
  tags = ["backend"]
  network_interface {
    subnetwork = google_compute_subnetwork.failover_subnet.id
    network_ip = var.secondary_ip
    access_config {}
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_instance_group_manager" "nginx_instance_group_primary" {
  name               = "nginx-primary"
  base_instance_name = "nginx-primary"
  target_size        = 1
  version {
    instance_template = google_compute_instance_template.nginx_primary_instance_template.id
  }
}

resource "google_compute_instance_group_manager" "nginx_instance_group_secondary" {
  name               = "nginx-secondary"
  base_instance_name = "nginx-secondary"
  target_size        = 1
  version {
    instance_template = google_compute_instance_template.nginx_secondary_instance_template.id
  }
}

resource "google_compute_health_check" "tcp_health_check" {
  depends_on = [google_project_service.required_api]
  name       = "tcp-health-check"

  tcp_health_check {
    port = var.health_check_port
  }
}

resource "google_compute_region_backend_service" "www_bes" {
  name                  = "nginx-bes"
  load_balancing_scheme = "INTERNAL"
  backend {
    group       = google_compute_instance_group_manager.nginx_instance_group_primary.instance_group
    description = "primary MIG"
    failover    = false
  }
  backend {
    group       = google_compute_instance_group_manager.nginx_instance_group_secondary.instance_group
    description = "secondary MIG"
    failover    = true
  }
  health_checks = [google_compute_health_check.tcp_health_check.id]
  protocol      = "TCP"
}

resource "google_compute_forwarding_rule" "www_rule" {
  name                  = "nginx-lb"
  ports                 = [80]
  load_balancing_scheme = "INTERNAL"
  backend_service       = google_compute_region_backend_service.www_bes.id
  network               = google_compute_network.failover_vpc.id
  subnetwork            = google_compute_subnetwork.failover_subnet.id
  ip_address            = var.floating_ip
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