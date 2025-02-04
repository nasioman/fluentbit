#!/bin/sh

PROJECT_DIR=$(git rev-parse --show-toplevel)

KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-my-cluster}"
LOGS_DIR="${LOGS_DIR:-/Users/tatanas/logs}"

# Deploy kind cluster with 2 nodes and mount directory where logs are stored into host FS
cat <<EOF | kind create cluster --name "$KIND_CLUSTER_NAME" --config -
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    extraMounts:
      - hostPath: ${LOGS_DIR}/node-control-plane
        containerPath: /mnt/logs
  - role: worker
    extraMounts:
      - hostPath: ${LOGS_DIR}/node-worker-1
        containerPath: /mnt/logs
  - role: worker
    extraMounts:
      - hostPath: ${LOGS_DIR}/node-worker-2
        containerPath: /mnt/logs
EOF

# Install Logging Operator
helm upgrade --install --wait \
     --create-namespace --namespace tpsm-logging \
     --set testReceiver.enabled=true \
     logging-operator oci://ghcr.io/kube-logging/helm-charts/logging-operator




# Install FluentBit  on every node

cat <<EOF | kubectl apply -f -
apiVersion: logging.banzaicloud.io/v1beta1
kind: FluentbitAgent
metadata:
    name: tpsm-logging
spec: {}
EOF


# Install Fluentd as central aggregator
# ClusterFlow is equivalent of Filter that filters logs by namespace and forwards them to Fluentd forwarder
# Doc how to define rules to filter and exclude logs based on different criterias
# https://kube-logging.dev/docs/configuration/log-routing/
cat <<EOF | kubectl apply -f -
apiVersion: logging.banzaicloud.io/v1beta1
kind: ClusterFlow
metadata:
  name: log-generator
  namespace: tpsm-logging
spec:
  globalOutputRefs:
    - fluentd-forwarder
  match:
    - select:
        namespaces:
          - tanzusm


---
# Installs Fluentd which is optional component and is not installed by default
apiVersion: logging.banzaicloud.io/v1beta1
kind: Logging
metadata:
  name: tpsm-logging-operator
  namespace: tpsm-logging
spec:
  controlNamespace: tpsm-logging
  fluentd:
    disablePvc: true
  
---
# This configures the Fluentd that aggregates and forwards the logs to receiver
apiVersion: logging.banzaicloud.io/v1beta1
kind: ClusterOutput
metadata:
  name: fluentd-forwarder
  namespace: tpsm-logging
spec:
  http:
    endpoint: http://logging-operator-test-receiver:8080
    content_type: application/json
    buffer:
      type: memory
      tags: time
      timekey: 1s
      timekey_wait: 0s

EOF




#Create namespace tanzusm
kubectl create namespace tanzusm


helm upgrade --install --wait --namespace tanzusm log-generator oci://ghcr.io/kube-logging/helm-charts/log-generator
