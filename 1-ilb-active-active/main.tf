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
  image        = "debian-cloud/debian-11"
  machine_type = "e2-small"
}

resource "google_project_service" "required_api" {
  for_each           = toset(["compute.googleapis.com", "cloudresourcemanager.googleapis.com"])
  service            = each.key
  disable_on_destroy = false
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
    ports    = ["80"]
  }
  network = google_compute_network.failover_vpc.id
  #IP ranges used for health checks
  #See https://cloud.google.com/load-balancing/docs/health-check-concepts#ip-ranges
  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]
}

resource "google_compute_instance" "nginx_first_instance" {
  name         = "nginx-first"
  machine_type = local.machine_type
  boot_disk {
    initialize_params {
      image = local.image
    }
  }
  metadata_startup_script = templatefile("startup-script.tmpl", {
    server_number = 1
  })
  tags = ["backend"]

  network_interface {
    subnetwork = google_compute_subnetwork.failover_subnet.id
    access_config {}
  }

}
resource "google_compute_instance" "nginx_second_instance" {
  name         = "nginx-second"
  machine_type = local.machine_type
  boot_disk {
    initialize_params {
      image = local.image
    }
  }
  metadata_startup_script = templatefile("startup-script.tmpl", {
    server_number = 2
  })
  tags = ["backend"]
  network_interface {
    subnetwork = google_compute_subnetwork.failover_subnet.id
    access_config {}
  }

}

resource "google_compute_instance_group" "nginx_instance_group" {
  name = "nginx-ig"
  zone = var.zone
  instances = [
    google_compute_instance.nginx_first_instance.id,
    google_compute_instance.nginx_second_instance.id
  ]
}


resource "google_compute_health_check" "simple_http_check" {
  depends_on = [google_project_service.required_api]

  name = "simple-health-check"

  http_health_check {
    port = 80
  }
}

resource "google_compute_region_backend_service" "www_bes" {
  name                  = "www-bes"
  load_balancing_scheme = "INTERNAL"
  backend {
    group       = google_compute_instance_group.nginx_instance_group.id
    description = "First MIG"
    failover    = false
  }

  health_checks = [google_compute_health_check.simple_http_check.id]
  protocol      = "TCP"
}

resource "google_compute_forwarding_rule" "www_rule" {
  name                  = "www-lb"
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
