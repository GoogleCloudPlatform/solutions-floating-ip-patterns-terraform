# Deploying patterns for Floating IP addresses on Google Cloud

This repository provides example implementations of [patterns for using floating IP addresses on Google Cloud](https://cloud.google.com/architecture/patterns-for-floating-ip-addresses) that can be deployed using [Terraform](https://www.terraform.io/). To learn more about the different patterns, see the [companion guide](https://cloud.google.com/architecture/patterns-for-floating-ip-addresses).

The implementations in the subdirectories of this repository are examples. Instead of a real application utilizing a floating IP address, in all examples two [nginx](https://nginx.org/en/) webservers are deployed that identify if the first or second server received the request when you request the root document(/).



The following pattern implementations are available:

| Subdirectory name | Pattern name |
|------------|------------|
| 1-ilb-active-active | [Active-Active load balancing](https://cloud.google.com/architecture/patterns-for-floating-ip-addresses#active-active-load-balancing) |
| 2-ilb-failover | [Load balancing using failover and native health checks](https://cloud.google.com/architecture/patterns-for-floating-ip-addresses#load-balancing-failover) |
| 3-ilb-keepalived | [Load balancing using failover and heartbeat exposed health checks](https://cloud.google.com/architecture/patterns-for-floating-ip-addresses#load-balancing-failover-heartbeat) |
| 4-routes-ecmp | [Using ECMP routes](https://cloud.google.com/architecture/patterns-for-floating-ip-addresses#using-ecmp-routes) |
| 5-routes-priority | [Using different priority routes](https://cloud.google.com/architecture/patterns-for-floating-ip-addresses#using-different-priority-routes) |
| 6-routes-keepalived | [Using a heartbeat mechanism to switch route destination](https://cloud.google.com/architecture/patterns-for-floating-ip-addresses#using-heartbeat-to-switch-route-destination) |
| 7-autohealing-instance | [Using an autohealing single instance](https://cloud.google.com/architecture/patterns-for-floating-ip-addresses#using-an-autohealing-single-instance) |

Each pattern can be deployed independently and only one pattern should be deployed in a project at a time as resource names overlap between the different patterns. 

To deploy any of the patterns, follow the instructions in the `README.md` in the respective subdirectory.
