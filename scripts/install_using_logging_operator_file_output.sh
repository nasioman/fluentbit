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
spec:
  inputTail:
    storage.type: filesystem
    Refresh_Interval: "60"
    Rotate_Wait: "5"
  filterKubernetes:
    Kube_URL: "https://kubernetes.default.svc:443"
    Match: "*"
EOF



# Configure FluentBit filters (filter by namespace) + normalize tag
# Forward logs to Fluentd
kubectl apply -f ../config/cluster_flow.yaml

# Installs Fluentd which is optional component and is not installed by default
# Attach external volume and store logs
cat <<EOF | kubectl apply -f -
apiVersion: logging.banzaicloud.io/v1beta1
kind: Logging
metadata:
  name: tpsm-logging
spec:
  controlNamespace: tpsm-logging
  fluentd:
    disablePvc: true
    extraVolumes:
      - path: /service-logs
        volume:
          hostPath:
            path: /mnt/logs
        volumeName: logs-output
---

# This configures the Fluentd that aggregates and forwards the logs to receiver
apiVersion: logging.banzaicloud.io/v1beta1
kind: ClusterOutput
metadata:
  name: fluentd-forwarder
  namespace: tpsm-logging
spec:
  file:
    path: "/service-logs/${tag}/%Y%m%d/%H/%M.log"
    format:
      type: json
EOF

# Create namespace tanzusm
kubectl create namespace tanzusm


# Deploy log generator application
helm upgrade --install --wait --namespace tanzusm log-generator oci://ghcr.io/kube-logging/helm-charts/log-generator

#https://github.com/fluent/fluent-bit/issues/7109?utm_source=chatgpt.com


# kube.var.log.containers.fluent-bit-flhww_default_fluent-bit-927ad10b5b8d33a54f02378f198667696bdd87242accd5e95afede6091e22a83.log: [1738140911.566537713,
#  {"log":"2025-01-29T08:55:11.566304505Z stderr F [2025/01/29 08:55:11] [ info] [input:tail:tail.0] inotify_fs_add():
#  inode=7381722 watch_fd=5 name=/var/log/pods/default_fluent-bit-flhww_11ed36e2-4dfa-4f7d-9a4e-1a75cf3d12ca/fluent-bit/0.log.20250129-085511",
# "kubernetes":{"pod_name":"fluent-bit-flhww","namespace_name":"default","pod_id":"11ed36e2-4dfa-4f7d-9a4e-1a75cf3d12ca",
# "labels":{"app":"fluent-bit","controller-revision-hash":"79f457b4b6","pod-template-generation":"92"},"annotations":{"kubectl.kubernetes.io/restartedAt":"2025-01-29T10:55:00+02:00"},"host":"kind-worker2","container_name":"fluent-bit","docker_id":"927ad10b5b8d33a54f02378f198667696bdd87242accd5e95afede6091e22a83","container_image":"fluent/fluent-bit:latest"}}]