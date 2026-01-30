#!/bin/bash
# =============================================================================
# RKE2 Cluster Health Check
# Usage: sudo /opt/rke2/check-health.sh
# =============================================================================

set -uo pipefail

# -----------------------------------------------------------------------------
# Constants
# -----------------------------------------------------------------------------
GREEN=$'\e[32m'
RED=$'\e[31m'
YELLOW=$'\e[33m'
CYAN=$'\e[36m'
BOLD=$'\e[1m'
DIM=$'\e[2m'
NC=$'\e[0m'

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------
print()  { echo -e "$*"; }
ok()     { print "  ${GREEN}✓${NC} $*"; }
fail()   { print "  ${RED}✗${NC} $*"; }
warn()   { print "  ${YELLOW}!${NC} $*"; }
info()   { print "    ${DIM}$*${NC}"; }
header() { print "\n${CYAN}${BOLD}[$1]${NC} $2"; }

count() { grep "${1:-}" 2>/dev/null | wc -l | tr -d '[:space:]' || echo 0; }
get_harbor_host() { grep -oP 'harbor\.[a-zA-Z0-9.-]+' "$1" 2>/dev/null | head -1; }
harbor_healthy()  { curl -fsSk --connect-timeout 5 "http://$1/api/v2.0/health" 2>/dev/null | grep -q healthy; }

# -----------------------------------------------------------------------------
# Setup
# -----------------------------------------------------------------------------
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
export PATH="$PATH:/var/lib/rancher/rke2/bin"
declare -A RESULTS

# -----------------------------------------------------------------------------
# Header
# -----------------------------------------------------------------------------
print "\n${BOLD}RKE2 Health Check${NC} - $(date '+%Y-%m-%d %H:%M:%S')\n"

# -----------------------------------------------------------------------------
# 1. RKE2 Service
# -----------------------------------------------------------------------------
header 1 "RKE2 Service"
if systemctl is-active --quiet rke2-server 2>/dev/null; then 
  ok "rke2-server running"
  UPTIME=$(systemctl show rke2-server --property=ActiveEnterTimestamp | cut -d= -f2)
  info "Started: $UPTIME"
  RESULTS[SVC]=PASS
elif systemctl is-active --quiet rke2-agent 2>/dev/null; then 
  ok "rke2-agent running"
  UPTIME=$(systemctl show rke2-agent --property=ActiveEnterTimestamp | cut -d= -f2)
  info "Started: $UPTIME"
  RESULTS[SVC]=PASS
else 
  fail "not running"
  RESULTS[SVC]=FAIL
fi

# -----------------------------------------------------------------------------
# 2. Kubernetes API
# -----------------------------------------------------------------------------
header 2 "Kubernetes API"
if kubectl cluster-info &>/dev/null; then 
  ok "reachable"
  VERSION=$(kubectl version --short 2>/dev/null | grep Server | awk '{print $3}' || kubectl version 2>/dev/null | grep "Server Version" | awk '{print $3}')
  info "Server: $VERSION"
  RESULTS[API]=PASS
else 
  fail "unreachable"
  RESULTS[API]=FAIL
  exit 1
fi

# -----------------------------------------------------------------------------
# 3. etcd Cluster
# -----------------------------------------------------------------------------
header 3 "etcd Cluster"
ETCD_PODS=$(kubectl get pods -n kube-system -l component=etcd --no-headers 2>/dev/null | count "Running")
if [[ "$ETCD_PODS" -ge 1 ]]; then
  ok "Running ($ETCD_PODS members)"
  if [[ -x /var/lib/rancher/rke2/bin/etcdctl ]]; then
    ETCD_STATUS=$(/var/lib/rancher/rke2/bin/etcdctl \
      --cacert=/var/lib/rancher/rke2/server/tls/etcd/server-ca.crt \
      --cert=/var/lib/rancher/rke2/server/tls/etcd/server-client.crt \
      --key=/var/lib/rancher/rke2/server/tls/etcd/server-client.key \
      endpoint health 2>/dev/null | grep -c "is healthy" || echo 0)
    info "Healthy endpoints: $ETCD_STATUS"
  fi
  RESULTS[ETCD]=PASS
else
  warn "etcd pods not found (embedded mode?)"
  RESULTS[ETCD]=SKIP
fi

# -----------------------------------------------------------------------------
# 4. System Pods
# -----------------------------------------------------------------------------
header 4 "System Pods"
PODS=$(kubectl get pods -n kube-system --no-headers 2>/dev/null)
TOTAL_PODS=$(echo "$PODS" | wc -l | tr -d '[:space:]')
BAD=$(echo "$PODS" | count -vE "Running|Completed")

if [[ "$BAD" -eq 0 ]]; then ok "All healthy"; RESULTS[POD]=PASS
else warn "$BAD unhealthy"; RESULTS[POD]=WARN; fi

info "Total: $TOTAL_PODS pods in kube-system"

# -----------------------------------------------------------------------------
# 5. CoreDNS
# -----------------------------------------------------------------------------
header 5 "CoreDNS"
DNS=$(kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers 2>/dev/null | count "Running")
if [[ "$DNS" -ge 1 ]]; then 
  ok "Running ($DNS replicas)"
  SVC_IP=$(kubectl get svc -n kube-system -l k8s-app=kube-dns -o jsonpath='{.items[0].spec.clusterIP}' 2>/dev/null)
  [[ -n "$SVC_IP" ]] && info "Service IP: $SVC_IP"
  RESULTS[DNS]=PASS
else 
  fail "Not running"
  RESULTS[DNS]=FAIL
fi

# -----------------------------------------------------------------------------
# 6. Cluster Network
# -----------------------------------------------------------------------------
header 6 "Cluster Network"
POD_CIDR=$(kubectl get nodes -o jsonpath='{.items[0].spec.podCIDR}' 2>/dev/null)
SVC_CIDR=$(kubectl get svc kubernetes -o jsonpath='{.spec.clusterIP}' 2>/dev/null | sed 's/\.[0-9]*$/.0\/16/')
CNI=$(ls /var/lib/rancher/rke2/agent/etc/cni/net.d/*.conflist 2>/dev/null | xargs -I{} basename {} .conflist | head -1)

ok "Network configured"
[[ -n "$POD_CIDR" ]] && info "Pod CIDR: $POD_CIDR"
[[ -n "$SVC_CIDR" ]] && info "Service CIDR: ~$SVC_CIDR"
[[ -n "$CNI" ]] && info "CNI: $CNI"
RESULTS[NET]=PASS

# -----------------------------------------------------------------------------
# 7. Certificates
# -----------------------------------------------------------------------------
header 7 "Certificates"
CERT_FILE="/var/lib/rancher/rke2/server/tls/serving-kube-apiserver.crt"
if [[ -f "$CERT_FILE" ]]; then
  EXPIRY=$(openssl x509 -enddate -noout -in "$CERT_FILE" 2>/dev/null | cut -d= -f2)
  EXPIRY_EPOCH=$(date -d "$EXPIRY" +%s 2>/dev/null || echo 0)
  NOW_EPOCH=$(date +%s)
  DAYS_LEFT=$(( (EXPIRY_EPOCH - NOW_EPOCH) / 86400 ))
  
  if [[ "$DAYS_LEFT" -gt 30 ]]; then
    ok "API cert valid ($DAYS_LEFT days left)"
    RESULTS[CERT]=PASS
  elif [[ "$DAYS_LEFT" -gt 0 ]]; then
    warn "API cert expiring soon ($DAYS_LEFT days)"
    RESULTS[CERT]=WARN
  else
    fail "API cert expired!"
    RESULTS[CERT]=FAIL
  fi
  info "Expires: $EXPIRY"
else
  warn "Cert file not found"
  RESULTS[CERT]=SKIP
fi

# -----------------------------------------------------------------------------
# 8. Harbor
# -----------------------------------------------------------------------------
header 8 "Harbor"
REG_FILE="/etc/rancher/rke2/registries.yaml"
if [[ ! -f "$REG_FILE" ]]; then 
  warn "registries.yaml missing"
  RESULTS[HARBOR]=SKIP
else
  HOST=$(get_harbor_host "$REG_FILE")
  if [[ -z "$HOST" ]]; then 
    RESULTS[HARBOR]=SKIP
  elif harbor_healthy "$HOST"; then 
    ok "$HOST healthy"
    MIRRORS=$(grep -c "endpoint:" "$REG_FILE" 2>/dev/null || echo 0)
    info "Configured mirrors: $MIRRORS"
    RESULTS[HARBOR]=PASS
  else 
    warn "$HOST unreachable"
    RESULTS[HARBOR]=WARN
  fi
fi

# -----------------------------------------------------------------------------
# 9. Ingress
# -----------------------------------------------------------------------------
header 9 "Ingress"
ING=$(kubectl get pods -n kube-system -l app.kubernetes.io/name=rke2-ingress-nginx --no-headers 2>/dev/null | count "Running")
if [[ "$ING" -ge 1 ]]; then 
  ok "Running ($ING replicas)"
  ING_CLASS=$(kubectl get ingressclass 2>/dev/null | grep -v NAME | awk '{print $1}' | head -1)
  [[ -n "$ING_CLASS" ]] && info "IngressClass: $ING_CLASS"
  RESULTS[ING]=PASS
else 
  warn "Not found"
  RESULTS[ING]=WARN
fi

# -----------------------------------------------------------------------------
# 10. Storage (PV/PVC)
# -----------------------------------------------------------------------------
header 10 "Storage"
PV_TOTAL=$(kubectl get pv --no-headers 2>/dev/null | wc -l | tr -d '[:space:]')
PV_AVAIL=$(kubectl get pv --no-headers 2>/dev/null | count "Available")
PVC_TOTAL=$(kubectl get pvc -A --no-headers 2>/dev/null | wc -l | tr -d '[:space:]')
PVC_BOUND=$(kubectl get pvc -A --no-headers 2>/dev/null | count "Bound")

if [[ "$PV_TOTAL" -eq 0 && "$PVC_TOTAL" -eq 0 ]]; then
  info "No PV/PVC configured"
  RESULTS[STORAGE]=SKIP
else
  ok "Storage configured"
  info "PV: $PV_AVAIL available / $PV_TOTAL total"
  info "PVC: $PVC_BOUND bound / $PVC_TOTAL total"
  RESULTS[STORAGE]=PASS
fi

# -----------------------------------------------------------------------------
# 11. Nodes
# -----------------------------------------------------------------------------
header 11 "Nodes"
NODES=$(kubectl get nodes --no-headers 2>/dev/null)
TOTAL=$(echo "$NODES" | wc -l | tr -d '[:space:]')
BAD=$(echo "$NODES" | count -v " Ready")
CP_CNT=$(echo "$NODES" | count "control-plane")
WORKER_CNT=$((TOTAL - CP_CNT))

if [[ "$BAD" -eq 0 ]]; then ok "All $TOTAL Ready"; RESULTS[NODE]=PASS
else warn "$BAD/$TOTAL not Ready"; RESULTS[NODE]=WARN; fi

info "Control Plane: $CP_CNT, Workers: $WORKER_CNT"
print ""
kubectl get nodes 2>/dev/null || true

# -----------------------------------------------------------------------------
# 12. Resource Usage
# -----------------------------------------------------------------------------
header 12 "Resource Usage"
if kubectl top nodes &>/dev/null; then
  ok "Metrics available"
  print ""
  kubectl top nodes 2>/dev/null | head -10
  RESULTS[RESOURCE]=PASS
else
  warn "Metrics server not available"
  RESULTS[RESOURCE]=SKIP
fi

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
print "\n${BOLD}Summary:${NC}"
PASS=0 WARN_CNT=0 FAIL_CNT=0 SKIP_CNT=0
for KEY in SVC API ETCD POD DNS NET CERT HARBOR ING STORAGE NODE RESOURCE; do
  STATUS="${RESULTS[$KEY]:-SKIP}"
  case "$STATUS" in 
    PASS) ((PASS++));; 
    WARN) ((WARN_CNT++));; 
    FAIL) ((FAIL_CNT++));;
    SKIP) ((SKIP_CNT++));;
  esac
done
print "  ${GREEN}PASS:$PASS${NC}  ${YELLOW}WARN:$WARN_CNT${NC}  ${RED}FAIL:$FAIL_CNT${NC}  ${DIM}SKIP:$SKIP_CNT${NC}\n"
