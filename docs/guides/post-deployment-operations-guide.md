# 구축 후 필수 운영 가이드 (Post-Deployment Operations Guide)

> 전체 스택 배포 완료 후, 관리자가 **순서대로** 수행해야 하는 초기 설정 및 검증 가이드

---

## 📋 실행 순서 요약

| 순서 | 대상 | 예상 시간 | 우선순위 |
|:---:|:---|:---:|:---:|
| **1** | Keycloak — Realm/Client 구성 | 30분 | 🔴 필수 |
| **2** | Teleport — 관리자 생성 및 리소스 등록 | 20분 | 🔴 필수 |
| **3** | Vault — Unseal 및 초기 시크릿 구성 | 20분 | 🔴 필수 |
| **4** | ArgoCD — 관리자 로그인 및 앱 상태 확인 | 10분 | 🔴 필수 |
| **5** | Rancher — 부트스트랩 비밀번호 변경 | 5분 | 🟡 권장 |
| **6** | Harbor — 프로젝트/사용자 구성 | 15분 | 🟡 권장 |
| **7** | Monitoring — Grafana SSO 및 대시보드 | 10분 | 🟡 권장 |
| **8** | Database — 접속 확인 | 10분 | 🟡 권장 |
| **9** | 전체 헬스체크 | 15분 | 🔴 필수 |

---

## 1. Keycloak — SSO 기반 IdP 구성

> **왜 가장 먼저?** Grafana, ArgoCD 등 대부분의 서비스가 Keycloak SSO에 의존합니다.

### 1.1 Admin Console 접근

Keycloak Admin Console은 **Internal Ingress**를 통해서만 접근 가능합니다.  
Teleport 또는 VPN을 통해 접근하세요.

```
URL: https://keycloak.dev.unifiedmeta.net/admin
```

> [!IMPORTANT]
> Public Ingress에서는 `/admin` 경로가 CiliumNetworkPolicy에 의해 **L7 레벨에서 차단**됩니다.
> 반드시 Internal NLB 경로 (Teleport App Access 또는 VPN)를 사용하세요.

### 1.2 Realm 생성

| 항목 | 값 |
|:---|:---|
| Realm Name | `platform` |
| Display Name | Platform SSO |
| Login Theme | keycloak (기본) |

```
Admin Console → Create Realm → Name: platform
```

### 1.3 Client 등록 (서비스별)

각 서비스별로 OIDC Client를 등록합니다:

#### Grafana Client

| 항목 | 값 |
|:---|:---|
| Client ID | `grafana` |
| Client Protocol | openid-connect |
| Access Type | confidential |
| Valid Redirect URIs | `https://grafana.unifiedmeta.net/*` |
| Web Origins | `https://grafana.unifiedmeta.net` |

> Client Secret 생성 후, `monitoring.yaml`의 `client_secret` 값과 일치시켜야 합니다.

#### ArgoCD Client (선택)

| 항목 | 값 |
|:---|:---|
| Client ID | `argocd` |
| Valid Redirect URIs | `https://argocd.unifiedmeta.net/auth/callback` |

#### Rancher Client (선택)

| 항목 | 값 |
|:---|:---|
| Client ID | `rancher` |
| Valid Redirect URIs | `https://rancher.unifiedmeta.net/verify-auth` |

### 1.4 사용자 그룹 생성

Grafana Role Mapping에 사용되는 그룹:

| 그룹 | 용도 | Grafana Role |
|:---|:---|:---|
| `admin` | 관리자 그룹 | Admin |
| `editor` | 편집자 그룹 | Editor |
| `viewer` | 조회자 그룹 (기본) | Viewer |

```
Admin Console → Groups → Create group
```

### 1.5 초기 사용자 생성

```
Admin Console → Users → Add user
→ Email / Username 입력
→ Credentials 탭에서 비밀번호 설정
→ Groups 탭에서 그룹 할당
```

### 1.6 검증

```bash
# OIDC Discovery 엔드포인트 응답 확인
curl -s https://keycloak.dev.unifiedmeta.net/realms/platform/.well-known/openid-configuration | jq .issuer
# 기대값: "https://keycloak.dev.unifiedmeta.net/realms/platform"
```

---

## 2. Teleport — 접근 제어 솔루션 초기 설정

> Teleport는 SSH, K8s, DB, Web App 접근을 통합 관리합니다.

### 2.1 최초 관리자 생성

```bash
# 1. Teleport 인스턴스 ID 확인
INSTANCE_ID=$(aws-vault exec devops -- \
  terraform -chdir=stacks/dev/15-access-control output -json instance_ids | jq -r '.[0]')

# 2. SSM으로 접속
aws-vault exec devops -- aws ssm start-session --target $INSTANCE_ID

# 3. 관리자 생성 (인스턴스 내부에서 실행)
sudo tctl users add admin \
  --roles=editor,access \
  --logins=root,ubuntu,ec2-user
```

> [!IMPORTANT]
> 출력되는 초대 URL은 **1시간 유효**합니다. 즉시 브라우저에서 열어 비밀번호와 OTP를 설정하세요.

### 2.2 tsh 로그인 확인

```bash
# 로컬에서 tsh 설치
brew install teleport  # macOS

# 로그인 테스트
tsh login --proxy=teleport.dev.unifiedmeta.net:443 --user=admin
tsh status
```

### 2.3 Kubernetes Agent 연동 확인

```bash
# K8s 클러스터 목록
tsh kube ls

# 클러스터 접근
tsh kube login meta-dev
kubectl get nodes
```

### 2.4 App Access 등록 확인

`80-access-gateway` 스택에서 자동 등록된 서비스 확인:

```bash
tsh apps ls
# 예상 결과: harbor, neo4j, opensearch 등
```

### 2.5 커스텀 Role 생성 (권장)

```yaml
# developer-role.yaml
kind: role
version: v5
metadata:
  name: developer
spec:
  allow:
    logins: [ubuntu]
    kubernetes_groups: [developers]
    node_labels:
      env: [dev, staging]
  deny:
    node_labels:
      env: production
```

```bash
sudo tctl create -f developer-role.yaml
```

---

## 3. Vault — 시크릿 관리 초기 설정

> Vault는 AWS KMS Auto-Unseal이 설정되어 있습니다.

### 3.1 Vault 초기화 (최초 1회)

```bash
# Vault Pod 접속
kubectl exec -it vault-0 -n vault -- sh

# 초기화 (Recovery Key 5개, Threshold 3개)
vault operator init \
  -recovery-shares=5 \
  -recovery-threshold=3
```

> [!CAUTION]
> 출력되는 **Recovery Key 5개**와 **Initial Root Token**을 안전한 곳에 반드시 저장하세요.
> 이 값은 다시 확인할 수 없습니다!

### 3.2 Unseal 상태 확인

AWS KMS Auto-Unseal이 정상이면 Pod 재시작 시에도 자동으로 Unseal됩니다.

```bash
kubectl exec -it vault-0 -n vault -- vault status

# Sealed: false ← 정상
# Recovery Seal Type: awskms ← KMS 연동 확인
```

### 3.3 시크릿 엔진 활성화

```bash
# KV v2 시크릿 엔진 활성화 (가장 기본)
vault secrets enable -path=secret kv-v2

# 샘플 시크릿 저장
vault kv put secret/platform/grafana \
  admin-user=admin \
  admin-password='<SECURE_PASSWORD>'

vault kv put secret/platform/database \
  postgres-password='<SECURE_PASSWORD>'
```

### 3.4 인증 방식 설정

```bash
# Kubernetes Auth (Pod → Vault 인증)
vault auth enable kubernetes

vault write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc:443"
```

### 3.5 UI 접근 확인

```
Internal URL: https://vault.dev.unifiedmeta.net
접근 방식: Teleport App Access 또는 VPN 경유
```

---

## 4. ArgoCD — GitOps 관리 도구

### 4.1 관리자 비밀번호 확인

```bash
# 초기 admin 비밀번호
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo
```

### 4.2 UI 접근 및 로그인

```
URL: https://argocd.unifiedmeta.net (Internal)
User: admin
Password: (위에서 확인한 값)
```

### 4.3 앱 상태 전체 확인

```bash
# CLI로 확인
kubectl get applications -n argocd

# 모든 앱이 Synced/Healthy 상태인지 확인
kubectl get applications -n argocd -o custom-columns=\
NAME:.metadata.name,\
SYNC:.status.sync.status,\
HEALTH:.status.health.status
```

**기대 결과 (전체 앱 목록):**

| App | Namespace | 역할 |
|:---|:---|:---|
| cert-manager | cert-manager | TLS 인증서 자동화 |
| cert-manager-issuers | cert-manager | ClusterIssuer |
| nginx-ingress | ingress-nginx | Public Ingress |
| nginx-ingress-internal | ingress-nginx-internal | Internal Ingress |
| external-dns | external-dns | 외부 DNS 자동화 |
| external-dns-private | external-dns-private | 내부 DNS 자동화 |
| aws-load-balancer-controller | kube-system | NLB/ALB 관리 |
| longhorn | longhorn-system | 분산 스토리지 |
| vault | vault | 시크릿 관리 |
| monitoring | monitoring | Prometheus + Grafana |
| loki | monitoring | 로그 수집 |
| promtail | monitoring | 로그 전송 |
| tempo | monitoring | 분산 트레이싱 |
| rancher | cattle-system | K8s 관리 |
| keycloak-ingress | keycloak | Keycloak Ingress + NetworkPolicy |

### 4.4 초기 admin 비밀번호 변경 (권장)

```bash
# ArgoCD CLI 설치
brew install argocd

# 로그인
argocd login argocd.unifiedmeta.net --grpc-web

# 비밀번호 변경
argocd account update-password
```

---

## 5. Rancher — Kubernetes 관리 UI

### 5.1 초기 로그인

```
URL: https://rancher.unifiedmeta.net (Internal)
Bootstrap Password: admin (초기 설정값)
```

### 5.2 비밀번호 변경

첫 로그인 시 비밀번호 변경 프롬프트가 나타납니다. **반드시 강력한 비밀번호로 변경**하세요.

### 5.3 클러스터 확인

Rancher UI에서 RKE2 클러스터가 자동 감지되어야 합니다:
- 노드 상태: Active
- 컴포넌트 상태: All Healthy

---

## 6. Harbor — 컨테이너 레지스트리

### 6.1 접근 방식

Harbor는 EC2 기반으로 배포되었으며, Teleport App Access를 통해 접근합니다.

```bash
# Teleport 경유 접근
tsh apps login harbor
# 브라우저에서 자동 오픈
```

또는 직접 접근 (Internal):
```
URL: https://harbor.unifiedmeta.net
```

### 6.2 초기 설정

| 항목 | 작업 |
|:---|:---|
| **관리자 비밀번호 변경** | Administration → Users → admin → 비밀번호 변경 |
| **프로젝트 생성** | Projects → New Project → `platform` (Private) |
| **프록시 캐시 구성** | Registries → New Endpoint → Docker Hub 캐시 |
| **Garbage Collection** | Administration → Garbage Collection → 스케줄 설정 |

### 6.3 Docker 로그인 테스트

```bash
docker login harbor.unifiedmeta.net
# Username: admin
# Password: (변경한 비밀번호)
```

---

## 7. Monitoring — 관측성 스택

### 7.1 Grafana 접근 및 SSO 테스트

```
URL: https://grafana.unifiedmeta.net
```

**SSO 로그인 흐름:**
1. Grafana 로그인 페이지 → "Sign in with Keycloak" 클릭
2. Keycloak 로그인 페이지로 리디렉트
3. 인증 완료 후 Grafana로 복귀
4. Keycloak 그룹에 따라 Role 자동 매핑 (`admin` → Admin, `editor` → Editor)

### 7.2 데이터소스 확인

Grafana → Configuration → Data Sources에서 다음 3개가 정상인지 확인:

| 데이터소스 | 타입 | 용도 |
|:---|:---|:---|
| Prometheus | prometheus | 메트릭 |
| Loki | loki | 로그 |
| Tempo | tempo | 트레이스 |

각 데이터소스에서 **"Test"** 버튼을 클릭하여 연결 확인.

### 7.3 필수 대시보드 Import

| Dashboard ID | 용도 |
|:---|:---|
| 1860 | Node Exporter Full |
| 315 | K8s Cluster Monitoring |
| 13770 | K8s Pod Monitoring |
| 14900 | Longhorn Storage |

```
Grafana → Dashboards → Import → Dashboard ID 입력
```

### 7.4 Alertmanager 확인

```
URL: https://alertmanager.unifiedmeta.net (Internal)
```

기본 Alert Rule이 활성화되어 있는지 확인:
- `Watchdog` (항상 Firing — 정상 동작 확인용)
- `KubeNodeNotReady`
- `KubePodCrashLooping`

---

## 8. Database — 접속 검증

### 8.1 PostgreSQL

```bash
# Teleport 경유 (권장)
tsh db ls
tsh db connect postgres --db-user=admin --db-name=postgres

# 또는 Bastion 경유 (SSM)
aws-vault exec devops -- aws ssm start-session \
  --target <bastion-instance-id> \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["5432"],"localPortNumber":["15432"]}'
```

### 8.2 Neo4j

```bash
# Teleport App Access 경유
tsh apps login neo4j

# 브라우저: https://neo4j.dev.unifiedmeta.net:7474
# bolt 연결: neo4j://neo4j.dev.unifiedmeta.net:7687
```

### 8.3 OpenSearch

```bash
# Teleport App Access 경유
tsh apps login opensearch

# API 확인
curl -k https://opensearch.dev.unifiedmeta.net:9200/_cluster/health?pretty
```

---

## 9. 전체 헬스체크 체크리스트

배포 후 최종적으로 아래 항목을 모두 확인하세요:

### 인프라 계층

- [ ] **네트워크**: VPC, 서브넷, NAT Gateway 정상
- [ ] **보안**: Security Group, VPC Endpoints 정상
- [ ] **인증서**: cert-manager ClusterIssuer → Let's Encrypt 정상 발급

```bash
kubectl get certificates -A
kubectl get clusterissuer
```

### 접근 제어 계층

- [ ] **Keycloak**: OIDC Discovery 엔드포인트 응답 정상
- [ ] **Teleport**: tsh login 성공, K8s/SSH/App 접근 정상
- [ ] **Split-Horizon**: Keycloak Admin은 Internal에서만 접근 가능

### 플랫폼 계층

- [ ] **ArgoCD**: 모든 Application → Synced / Healthy
- [ ] **Rancher**: 클러스터 Active, 노드 전체 Ready
- [ ] **Longhorn**: 볼륨 정상, Replica 분배 확인

```bash
kubectl get nodes
kubectl get volumes.longhorn.io -n longhorn-system
```

### 관측성 계층

- [ ] **Grafana**: SSO 로그인 성공, 대시보드 데이터 표시
- [ ] **Prometheus**: Target 전체 UP
- [ ] **Loki**: 로그 수집 확인 (Grafana Explore → Loki)
- [ ] **Tempo**: 트레이스 수집 확인

```bash
# Prometheus Targets
kubectl port-forward svc/monitoring-prometheus 9090:9090 -n monitoring
# 브라우저: http://localhost:9090/targets → All UP
```

### 데이터 계층

- [ ] **PostgreSQL**: 접속 및 쿼리 정상
- [ ] **Neo4j**: 브라우저 접속 및 Cypher 쿼리 정상
- [ ] **OpenSearch**: Cluster Health → green

### 레지스트리 계층

- [ ] **Harbor**: docker login 성공
- [ ] **Harbor**: 프록시 캐시 (Docker Hub) 정상 동작

---

## 10. 보안 강화 체크리스트

> [!WARNING]
> 배포 직후 반드시 확인해야 하는 보안 항목입니다.

| # | 항목 | 확인 방법 |
|:---:|:---|:---|
| 1 | 모든 기본 비밀번호 변경 | Rancher(`admin`), ArgoCD, Harbor, Grafana |
| 2 | Keycloak Client Secret 변경 | Grafana 연동 Secret이 약한 값이면 즉시 교체 |
| 3 | Public 노출 서비스 점검 | Internal 서비스가 Public NLB로 노출되지 않는지 확인 |
| 4 | SSH 직접 접근 차단 확인 | Port 22가 Security Group에서 차단되어 있는지 확인 |
| 5 | Vault Root Token 폐기 | 초기화 후 Root Token 사용 → 일반 관리자 토큰으로 전환 |
| 6 | Recovery Key 백업 | Vault Recovery Key를 암호화된 저장소에 분산 보관 |

---

## 📎 관련 문서

| 문서 | 경로 |
|:---|:---|
| Day-2 운영 런북 | [day-2-operations.md](../runbooks/day-2-operations.md) |
| Teleport 운영 매뉴얼 | [teleport-operations-manual.md](../access-control/teleport-operations-manual.md) |
| Teleport 사용자 가이드 | [teleport-user-guide.md](../access-control/teleport-user-guide.md) |
| Vault KMS Auto-Unseal | [vault-kms-auto-unseal.md](../vault/vault-kms-auto-unseal.md) |
| Break-Glass SSH | [break-glass-ssh.md](../runbooks/break-glass-ssh.md) |
| GitOps 관리 | [gitops-management.md](../runbooks/gitops-management.md) |
| 보안 최적화 | [security-optimization-best-practices.md](../access-control/security-optimization-best-practices.md) |
| 웹 서비스 온보딩 | [web-service-onboarding.md](web-service-onboarding.md) |

---

## 변경 이력

| 버전 | 날짜 | 변경 내용 |
|:---|:---|:---|
| 1.0 | 2026-02-09 | 초안 작성 — 전체 스택 기반 구축 후 필수 운영 가이드 |
