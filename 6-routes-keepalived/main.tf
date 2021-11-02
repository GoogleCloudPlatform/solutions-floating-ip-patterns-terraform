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

locals {
  image = "debian-cloud/debian-9"
  machine_type = "e2-small"
  python_script = templatefile("switch_vip.py.tmpl", {
    route_name    = var.route_name
    network_name  = var.network_name
    floating_ip   = var.floating_ip
  })
}

provider "google" {

  project = var.project_id
  region  = var.region
  zone    = var.zone
}

resource "google_project_service" "required_api" {
  for_each = toset(["compute.googleapis.com", "cloudresourcemanager.googleapis.com"])
  service  = each.key
}

resource "google_compute_network" "failover_vpc" {
  depends_on              = [google_project_service.required_api]
  name                    = var.network_name
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "failover_subnet" {
  name          = var.subnet_name
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

resource "google_compute_instance" "nginx_primary_instance" {
  name         = "nginx-primary"
  machine_type = local.machine_type
  boot_disk {
    initialize_params {
      image = local.image
    }
  }

  metadata_startup_script = templatefile("startup-script.tmpl", {
    server_number = 1
    python_script = local.python_script
    floating_ip   = var.floating_ip
    ip            = var.primary_ip
    peer_ip       = var.secondary_ip
    state         = "MASTER"
    priority      = 100
    vrrp_password = var.vrrp_password
  })

  can_ip_forward = true
  tags           = ["backend"]

  network_interface {
    subnetwork = google_compute_subnetwork.failover_subnet.id
    access_config {}
    network_ip = var.primary_ip

  }
  service_account {
    scopes = ["compute-rw"]
  }
  allow_stopping_for_update = true
}
resource "google_compute_instance" "nginx_secondary_instance" {
  name         = "nginx-secondary"
  machine_type = local.machine_type
  boot_disk {
    initialize_params {
      image = local.image
    }
  }
  metadata_startup_script = templatefile("startup-script.tmpl", {
    server_number = 2
    python_script = local.python_script
    floating_ip   = var.floating_ip
    ip            = var.secondary_ip
    peer_ip       = var.primary_ip
    state         = "BACKUP"
    priority      = 50
    vrrp_password = var.vrrp_password
  })
  can_ip_forward = true
  tags           = ["backend"]
  network_interface {
    subnetwork = google_compute_subnetwork.failover_subnet.id
    access_config {}
    network_ip = var.secondary_ip
  }
  service_account {
    scopes = ["compute-rw"]
  }
  allow_stopping_for_update = true
}



resource "google_compute_route" "floating_ip_route" {
  depends_on = [google_compute_subnetwork.failover_subnet]

  name              = var.route_name
  dest_range        = "${var.floating_ip}/32"
  network           = google_compute_network.failover_vpc.name
  next_hop_instance = google_compute_instance.nginx_primary_instance.id
  priority          = 1000
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
  allow_stopping_for_update = true
}