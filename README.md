# Deploying patterns for Floating IP addresses in Compute Engine

This repository provides example implementations of [patterns for using floating IP addresses in Compute Engine](https://cloud.google.com/architecture/patterns-for-floating-ip-addresses-in-compute-engine) that can be deployed using [Terraform](https://www.terraform.io/). To learn more about the different patterns, see the [companion guide](https://cloud.google.com/architecture/patterns-for-floating-ip-addresses-in-compute-engine).

The implementations in the subdirectories of this repository are examples. Instead of a real application utilizing a floating IP address, in all examples two [nginx](https://nginx.org/en/) webservers are deployed that identify if the first or second server received the request when you request the root document(/).



The following pattern implementations are available:

| Subdirectory name | Pattern name |
|------------|------------|
| 1-ilb-active-active | [Active-active load balancing](https://cloud.google.com/architecture/patterns-for-floating-ip-addresses-in-compute-engine#active-active_load_balancing) |
| 2-ilb-failover | [Load balancing with failover and application-exposed health checks](https://cloud.google.com/architecture/patterns-for-floating-ip-addresses-in-compute-engine#application-exposed) |
| 3-ilb-keepalived | [Load balancing with failover and heartbeat-exposed health checks](https://cloud.google.com/architecture/patterns-for-floating-ip-addresses-in-compute-engine#heartbeat-exposed) |
| 4-routes-ecmp | [Using equal-cost multipath (ECMP) routes](https://cloud.google.com/architecture/patterns-for-floating-ip-addresses-in-compute-engine#using_equal-cost_multipath_ecmp_routes) |
| 5-routes-priority | [Using different priority routes](https://cloud.google.com/architecture/patterns-for-floating-ip-addresses-in-compute-engine#using_different_priority_routes) |
| 6-routes-keepalived | [Using a heartbeat mechanism to switch a route's next hop](https://cloud.google.com/architecture/patterns-for-floating-ip-addresses-in-compute-engine#using_a_heartbeat_mechanism_to_switch_a_routes_next_hop) |
| 7-autohealing-instance | [Using an autohealing single instance](https://cloud.google.com/architecture/patterns-for-floating-ip-addresses-in-compute-engine#autohealing_single_instance) |

Each pattern can be deployed independently and only one pattern should be deployed in a project at a time as resource names overlap between the different patterns. 

To deploy any of the patterns, follow the instructions in the `README.md` in the respective subdirectory.
