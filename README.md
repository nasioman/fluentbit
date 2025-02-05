# fluentbit

# Overview
This is playground project to get familiar with FluentBit pipeline ,pros ,cons and limitations - [fluentbit](https://fluentbit.io/) 


# Setup
It spins up a Kind cluster with 2 nodes. Each node directory called `/mnt/logs` is mounted to Docker host directory
simulating external Volume. `/mnt/logs` dir is mounted to fluentbit pod as `/fluent-bit/logs`  and fluentbit is configured to output result
from its pipeline into `/fluent-bit/logs`

It also deploys a log-generator which logs the current timestamp every second.

To set up the cluster  run
```python
KIND_CLUSTER_NAME="<your-kind-cluster>"
LOGS_DIR=<dir-on-machine-where-docker-runs>
```

  