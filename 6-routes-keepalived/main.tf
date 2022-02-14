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
  image                   = "debian-cloud/debian-9"
  machine_type            = "e2-small"
  primary_instance_name   = "nginx-primary"
  secondary_instance_name = "nginx-secondary"
  python_script = templatefile("cloud-function/main.py.tmpl", {
    route_name         = var.route_name
    network_name       = var.network_name
    floating_ip        = var.floating_ip
    primary_instance   = local.primary_instance_name
    secondary_instance = local.secondary_instance_name
    zone               = var.zone
  })
}

provider "google" {

  project = var.project_id
  region  = var.region
  zone    = var.zone
}

provider "archive" {

}

data "archive_file" "function_zip" {
  type        = "zip"
  output_path = "${path.module}/function-switch.zip"
  source {
    content  = local.python_script
    filename = "main.py"
  }
  source {
    content  = file("cloud-function/requirements.txt")
    filename = "requirements.txt"
  }
}

resource "google_project_service" "required_api" {
  for_each = toset(["compute.googleapis.com", "cloudresourcemanager.googleapis.com", "cloudfunctions.googleapis.com", "cloudbuild.googleapis.com","storage.googleapis.com"])
  service  = each.key
  disable_dependent_services = true
}

resource "google_service_account" "function_service_account" {
  account_id   = "switcher-function"
  display_name = "Service Account that is able to create routes"
}

resource "google_service_account" "invoker_service_account" {
  account_id   = "cf-invoker"
  display_name = "Service Account that is able to invoke the created functions"
}

resource "google_project_iam_member" "function_sa_membership" {
  project = var.project_id
  role    = "roles/compute.networkAdmin"
  member  = "serviceAccount:${google_service_account.function_service_account.email}"
}

resource "random_id" "bucketname_suffix" {
  byte_length = 4
}

resource "google_storage_bucket" "function_bucket" {
  depends_on    = [google_project_service.required_api]
  name          = "${lower(var.project_id)}-function-${random_id.bucketname_suffix.hex}"
  location      = var.bucket_location
  force_destroy = true
}

resource "google_storage_bucket_object" "function_archive" {
  depends_on = [data.archive_file.function_zip]
  name       = "function-switch.zip"
  bucket     = google_storage_bucket.function_bucket.name
  source     = "${path.module}/function-switch.zip"
}

resource "google_cloudfunctions_function" "function_switch" {
  depends_on  = [google_project_service.required_api]
  name        = "switch-route"
  description = "Function to switch route to primary or secondary VM"
  runtime     = "python38"

  available_memory_mb   = 256
  source_archive_bucket = google_storage_bucket.function_bucket.name
  source_archive_object = google_storage_bucket_object.function_archive.name
  trigger_http          = true
  entry_point           = "main"
}

# IAM entry for all users to invoke the function
resource "google_cloudfunctions_function_iam_member" "invoker" {
  project        = var.project_id
  region         = google_cloudfunctions_function.function_switch.region
  cloud_function = google_cloudfunctions_function.function_switch.name

  role   = "roles/cloudfunctions.invoker"
  member = "serviceAccount:${google_service_account.invoker_service_account.email}"
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
  name = local.primary_instance_name

  machine_type = local.machine_type
  boot_disk {
    initialize_params {
      image = local.image
    }
  }

  metadata_startup_script = templatefile("startup-script.tmpl", {
    server_number = 1
    function_url  = google_cloudfunctions_function.function_switch.https_trigger_url
    target        = "primary"
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
    email  = google_service_account.invoker_service_account.email
    scopes = ["cloud-platform"]
  }
  allow_stopping_for_update = true
}
resource "google_compute_instance" "nginx_secondary_instance" {
  name         = local.secondary_instance_name
  machine_type = local.machine_type
  boot_disk {
    initialize_params {
      image = local.image
    }
  }
  metadata_startup_script = templatefile("startup-script.tmpl", {
    server_number = 2
    function_url  = google_cloudfunctions_function.function_switch.https_trigger_url
    target        = "secondary"
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
    email  = google_service_account.invoker_service_account.email
    scopes = ["cloud-platform"]
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
