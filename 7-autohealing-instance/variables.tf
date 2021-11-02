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

 
variable "project_id" {
  description = "Google Cloud Project ID"
  type        = string
}

variable "region" {
  description = "Google Cloud Region used to deploy resources"
  default     = "us-central1"
}

variable "zone" {
  description = "Google Cloud Zone used to deploy resources"
  default     = "us-central1-c"
}


variable "subnet_range" {
  description = "IP address range used for the subnet"
  default     = "10.100.0.0/16"
}

variable "floating_ip" {
  description = "IP address of the single autohealing instance"
  default     = "10.100.2.1"
}
