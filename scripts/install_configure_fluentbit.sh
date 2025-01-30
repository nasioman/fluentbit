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

# Install FluentBit CRD
helm repo add fluent https://fluent.github.io/helm-charts
helm upgrade --install fluent-bit fluent/fluent-bit


kubectl delete daemonsets.apps fluent-bit

#Deploy Sample application that logs something
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: example-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: example-app
  template:
    metadata:
      labels:
        app: example-app
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            - labelSelector:
                matchExpressions:
                  - key: app
                    operator: In
                    values:
                      - example-app
              topologyKey: "kubernetes.io/hostname"
      containers:
        - name: timestamp-logger
          image: busybox
          imagePullPolicy: Always
          command: ["/bin/sh", "-c"]
          args:
            - while true; do date; sleep 1; done

EOF


# Create FluentBit  Daemonset and configure it
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: fluent-bit
  labels:
    app: fluent-bit
spec:
  selector:
    matchLabels:
      app.kubernetes.io/instance: fluent-bit
      app.kubernetes.io/name: fluent-bit
      app: fluent-bit
  template:
    metadata:
      labels:
        app.kubernetes.io/instance: fluent-bit
        app.kubernetes.io/name: fluent-bit
        app: fluent-bit
    spec:
      containers:
      - name: fluent-bit
        image: fluent/fluent-bit:latest
        volumeMounts:
          - name: fluent-bit-config
            mountPath: /fluent-bit/etc/fluent-bit.conf
            subPath: fluent-bit.conf
          - name: varlog
            mountPath: /var/log  # Mount /var/log to allow Fluent Bit to read logs
          - name: log-output
            mountPath: /fluent-bit/logs
        env:
          - name: FLUENT_BIT_CONFIG
            value: /fluent-bit/etc/fluent-bit.conf
        args:
          - -c
          - /fluent-bit/etc/fluent-bit.conf
      volumes:
        - name: fluent-bit-config
          configMap:
            name: fluent-bit-config
        - name: varlog
          hostPath:
            path: /var/log
            type: DirectoryOrCreate
        - name: log-output
          hostPath:
            path: /mnt/logs  # This will mount the host's /mnt/logs (mapped from /Users/tatanas/logs)
            type: DirectoryOrCreate
EOF


kubectl apply -f ../config/fluentbit_config.yaml



cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: fluent-bit-role
  namespace: default
rules:
  - apiGroups: [""]
    resources:
      - pods
    verbs:
      - get
      - list
      - watch
EOF

cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: fluent-bit-role-binding
  namespace: default
subjects:
  - kind: ServiceAccount
    name: default
    namespace: default
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: fluent-bit-role

EOF



#https://github.com/fluent/fluent-bit/issues/7109?utm_source=chatgpt.com


# kube.var.log.containers.fluent-bit-flhww_default_fluent-bit-927ad10b5b8d33a54f02378f198667696bdd87242accd5e95afede6091e22a83.log: [1738140911.566537713,
#  {"log":"2025-01-29T08:55:11.566304505Z stderr F [2025/01/29 08:55:11] [ info] [input:tail:tail.0] inotify_fs_add():
#  inode=7381722 watch_fd=5 name=/var/log/pods/default_fluent-bit-flhww_11ed36e2-4dfa-4f7d-9a4e-1a75cf3d12ca/fluent-bit/0.log.20250129-085511",
# "kubernetes":{"pod_name":"fluent-bit-flhww","namespace_name":"default","pod_id":"11ed36e2-4dfa-4f7d-9a4e-1a75cf3d12ca",
# "labels":{"app":"fluent-bit","controller-revision-hash":"79f457b4b6","pod-template-generation":"92"},"annotations":{"kubectl.kubernetes.io/restartedAt":"2025-01-29T10:55:00+02:00"},"host":"kind-worker2","container_name":"fluent-bit","docker_id":"927ad10b5b8d33a54f02378f198667696bdd87242accd5e95afede6091e22a83","container_image":"fluent/fluent-bit:latest"}}]