#!/usr/bin/env bash
set -euo pipefail

# startup.sh
# Consistent bootstrap for local IDP dev environment:
# 1) create/recreate kind cluster (with 80/443 host mappings)
# 2) patch CoreDNS forwarders (fixes Docker Desktop/WSL DNS flakiness)
# 3) install Argo CD
# 4) apply your existing bootstrap YAMLs from disk (root-app, etc.)
#
# Assumptions:
# - You already have all required YAMLs in this repo.
# - You have kind + kubectl installed.
#
# Customize via env vars below.

#######################################
# Config (override via env vars)
#######################################
CLUSTER_NAME="${CLUSTER_NAME:-idp-dev}"
KIND_NODE_IMAGE="${KIND_NODE_IMAGE:-kindest/node:v1.29.2}"

# Kind config file path (you can commit this later; for now script generates a stable one)
KIND_CONFIG_PATH="${KIND_CONFIG_PATH:-.idp/kind-${CLUSTER_NAME}.yaml}"

# DNS forwarders for CoreDNS (avoid Docker Desktop DNS timeouts)
DNS_FORWARDERS="${DNS_FORWARDERS:-1.1.1.1 8.8.8.8}"

# Argo CD install manifest (pin a version for consistency)
ARGO_NAMESPACE="${ARGO_NAMESPACE:-argocd}"
ARGO_VERSION="${ARGO_VERSION:-v2.10.9}"
ARGO_INSTALL_URL="${ARGO_INSTALL_URL:-https://raw.githubusercontent.com/argoproj/argo-cd/${ARGO_VERSION}/manifests/install.yaml}"

# Your local bootstrap YAMLs (already exist in your repo)
# Provide one or more -f entries; script applies them in order.
# Example:
#   BOOTSTRAP_FILES="clusters/dev/root-app.yaml clusters/dev/infra/namespaces/platform-namespaces.yaml"
BOOTSTRAP_FILES="${BOOTSTRAP_FILES:-clusters/dev/root-app.yaml}"

#######################################
# Helpers
#######################################
need() { command -v "$1" >/dev/null 2>&1 || { echo "❌ Missing dependency: $1"; exit 1; }; }
log() { printf "\n\033[1;34m==>\033[0m %s\n" "$*"; }

rollout() {
  local ns="$1" deploy="$2" timeout="${3:-180s}"
  kubectl -n "$ns" rollout status deploy/"$deploy" --timeout="$timeout"
}

apply_files() {
  local files=("$@")
  for f in "${files[@]}"; do
    if [[ ! -f "$f" ]]; then
      echo "❌ Bootstrap file not found: $f"
      exit 1
    fi
    log "Applying: $f"
    kubectl apply -f "$f"
  done
}

#######################################
# Pre-flight
#######################################
need kind
need kubectl

log "Bootstrap config"
echo "  CLUSTER_NAME=$CLUSTER_NAME"
echo "  KIND_NODE_IMAGE=$KIND_NODE_IMAGE"
echo "  KIND_CONFIG_PATH=$KIND_CONFIG_PATH"
echo "  DNS_FORWARDERS=$DNS_FORWARDERS"
echo "  ARGO_VERSION=$ARGO_VERSION"
echo "  BOOTSTRAP_FILES=$BOOTSTRAP_FILES"

#######################################
# 1) Recreate kind cluster (consistent clean slate)
#######################################
log "Preparing kind config"
mkdir -p "$(dirname "$KIND_CONFIG_PATH")"

cat > "$KIND_CONFIG_PATH" <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: ${CLUSTER_NAME}
nodes:
- role: control-plane
  image: ${KIND_NODE_IMAGE}
  extraPortMappings:
  - containerPort: 32142
    hostPort: 18080
    protocol: TCP
  - containerPort: 30689
    hostPort: 18443
    protocol: TCP
EOF

if kind get clusters | grep -qx "$CLUSTER_NAME"; then
  log "Deleting existing cluster: $CLUSTER_NAME"
  kind delete cluster --name "$CLUSTER_NAME"
fi

log "Creating cluster: $CLUSTER_NAME"
kind create cluster --config "$KIND_CONFIG_PATH"

log "Cluster ready"
kubectl cluster-info >/dev/null

#######################################
# 2) Patch CoreDNS forwarders (GitHub/DNS reliability)
#######################################
log "Patching CoreDNS forwarders to: $DNS_FORWARDERS"
kubectl -n kube-system get configmap coredns -o yaml > /tmp/coredns.yaml

# Replace forward line if present; otherwise leave as-is (but most distros have it)
if grep -qE '^\s*forward\s+\.\s+/etc/resolv\.conf' /tmp/coredns.yaml; then
  sed -i.bak -E "s/^\s*forward\s+\.\s+\/etc\/resolv\.conf/        forward . ${DNS_FORWARDERS}/" /tmp/coredns.yaml
fi

kubectl -n kube-system apply -f /tmp/coredns.yaml
kubectl -n kube-system rollout restart deployment coredns
kubectl -n kube-system rollout status deployment coredns --timeout=120s

log "DNS smoke test (in-cluster)"
kubectl run -it --rm dns-test --image=busybox:1.36 --restart=Never -- \
  sh -c "nslookup kubernetes.default.svc.cluster.local >/dev/null && nslookup github.com >/dev/null && echo '✅ DNS OK'" || {
    echo "⚠️ DNS test failed. Check CoreDNS logs:"
    echo "   kubectl -n kube-system logs -l k8s-app=kube-dns --tail=80"
  }

#######################################
# 3) Install Argo CD (pinned)
#######################################
log "Installing Argo CD into namespace: $ARGO_NAMESPACE"
kubectl create ns "$ARGO_NAMESPACE" >/dev/null 2>&1 || true
kubectl apply -n "$ARGO_NAMESPACE" -f "$ARGO_INSTALL_URL"
kubectl -n "$ARGO_NAMESPACE" rollout status deploy/argocd-server --timeout=300s
# rollout "$ARGO_NAMESPACE" argocd-repo-server 240s
# rollout "$ARGO_NAMESPACE" argocd-application-controller 240s
# rollout "$ARGO_NAMESPACE" argocd-server 240s


log "Argo CD installed"
kubectl create ns demo >/dev/null 2>&1 || true
log "Applying demo whoami app"
kubectl apply -f ../demo/whoami.yaml
#######################################
# 4) Apply your existing bootstrap YAMLs (root app-of-apps etc.)
#######################################
log "Applying bootstrap manifests"
# shellcheck disable=SC2206
BOOTSTRAP_ARR=($BOOTSTRAP_FILES)
apply_files "${BOOTSTRAP_ARR[@]}"

log "Bootstrap complete ✅"

cat <<'NEXT'

NEXT CHECKS:

1) Argo Applications:
   kubectl get application -n argocd

2) dev-root status (change name if yours differs):
   kubectl describe application dev-root -n argocd | sed -n '1,120p'

3) If you exposed nginx via host ports:
   curl -H "Host: whoami.local" http://localhost

If Argo cannot pull GitHub, check:
   kubectl -n kube-system logs -l k8s-app=kube-dns --tail=80

NEXT
