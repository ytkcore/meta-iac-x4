# 구축 후 필수 운영 가이드 (Post-Deployment Operations Guide)

> [!IMPORTANT]
> **배포 직후 필수 점검 사항 (Critical Checks)**
>
> 대부분의 초기화 작업은 **`make opstart` 대시보드**를 통해 자동화되었습니다.
> 운영자는 대시보드의 안내에 따라 버튼을 클릭하여 초기 설정을 완료하십시오.
>
> 1.  **Vault 초기화 (`§1`)**: Vault는 초기화 전까지 **Sealed** 상태입니다. 대시보드에서 상태를 확인하세요.
> 2.  **보안 리소스 생성 (`§2`)**: 대시보드를 통해 Keycloak DB/Admin Secret을 자동 생성 및 주입합니다.
> 3.  **초기 비밀번호 변경 (`§3` 이후)**: 각 서비스(Teleport, Harbor 등) 접속 후 기본 계정의 비밀번호를 즉시 변경하십시오.

 본 가이드는 `make opstart` 대시보드를 기반으로 한 **표준 운영 초기화 절차**를 다룹니다.

---

## 📋 운영 로드맵 (Operations Roadmap)

| 단계 | 대상 | 방식 | 목적 | 시간 | 비고 |
|:---:|:---|:---:|:---|:---:|:---|
| **1** | Vault 상태 확인 | 🤖 | 시크릿 저장소 Sealed 여부 체크 | — | `make opstart` |
| **2** | Secret 생성 | 🤖 | DB/Admin 비밀번호 생성 및 K8s 주입 | — | `make opstart` |
| **3** | Identity Provider | 🤖 | Keycloak Realm/Client 자동 구성 | 1M | 대시보드 실행 |
| **4** | Network (ALBC) | 🤖 | Load Balancer VPC ID 자동 주입 | 1M | 대시보드 실행 |
| **5** | Access Control | 🤖 | Teleport 관리자 생성 및 초대 링크 | 1M | 대시보드 실행 |
| **6** | GitOps Sync | 🤖 | ArgoCD 앱 상태 동기화 | 2M | 대시보드 실행 |
| **7** | Cluster 등록 | 👤 | Rancher에 클러스터 Import | 2M | **수동 작업** |
| **8** | Registry 설정 | 🤖 | Harbor 프록시 캐시 프로젝트 구성 | 1M | 대시보드 실행 |
| **9** | Monitoring | 👤 | Grafana 대시보드 접속 확인 | 1M | 대시보드 링크 |

> 🤖 = 대시보드 자동화 (원클릭) &nbsp;&nbsp;|&nbsp;&nbsp; 👤 = 운영자 수동 수행

---

## 1. Vault & Secrets (단계 1-2)

대시보드 접속 시 자동으로 **Vault 상태**를 확인하고, **Keycloak 필수 Secret**을 생성/주입합니다.
-   **Vault**: Active 상태여야 합니다.
-   **Secrets**: '배포됨' 상태여야 합니다.

---

## 2. Identity Provider (단계 3)

Keycloak의 `platform` Realm과 SSO Client를 구성합니다.

1.  대시보드 **3단계**에서 **[Realm 설정 실행]** 버튼을 클릭합니다.
2.  로그 창에 "Realm 생성 완료" 및 "Client 생성 완료" 메시지가 뜨는지 확인합니다.
3.  **[Keycloak 열기]** 버튼으로 접속하여 `platform` Realm이 생성되었는지 확인할 수 있습니다.

---

## 3. Network Config (단계 4)

AWS Load Balancer Controller(ALBC)가 정상 작동하려면 VPC ID가 필요합니다.

1.  대시보드 **4단계**에서 **[ALBC 설정 패치]** 버튼을 클릭합니다.
2.  Terraform에서 VPC ID를 가져와 ArgoCD 설정에 주입합니다.
3.  이후 ArgoCD가 자동으로 설정을 동기화하여 Ingress가 정상 배포됩니다.

---

## 4. Access Control (단계 5)

Teleport 관리자 계정을 생성합니다.

1.  대시보드 **5단계**에서 **[관리자 생성]** 버튼을 클릭합니다.
2.  콘솔에 출력된 **초대 링크(URL)**를 클릭하여 비밀번호와 OTP를 설정합니다.
3.  설정 완료 후 `tsh login` 또는 웹 UI를 통해 접속할 수 있습니다.

---

## 5. GitOps Sync (단계 6)

ArgoCD의 모든 애플리케이션 상태를 동기화합니다.

1.  대시보드 **6단계**에서 **[전체 동기화]** 버튼을 클릭합니다.
2.  모든 앱이 `Healthy` / `Synced` 상태가 될 때까지 기다립니다.
3.  **[ArgoCD 열기]** 버튼으로 상세 상태를 확인할 수 있습니다.

---

## 6. Cluster 등록 (단계 7)

Rancher에 RKE2 클러스터를 등록하는 작업은 **수동**으로 진행해야 합니다.

1.  대시보드 **7단계**에서 **[Rancher 열기]**를 클릭합니다. (초기 PW는 로그 확인)
2.  **Import Cluster** -> **Generic** 선택.
3.  표시된 `kubectl` 명령어를 복사하여 터미널(bastion)에서 실행합니다.
4.  클러스터 상태가 `Active`로 변하면 완료입니다.

---

## 7. Registry & Monitoring (단계 8-9)

### 7.1 Harbor 설정
1.  대시보드 **8단계**에서 **[Harbor 설정 실행]**을 클릭합니다.
2.  DockerHub, K8s, GHCR 등에 대한 프록시 캐시 프로젝트가 자동 생성됩니다.

### 7.2 Monitoring 확인
1.  대시보드 **9단계**에서 **[Grafana 열기]**를 클릭합니다.
2.  Keycloak SSO 로그인을 통해 접속되는지 확인합니다.

---

## 8. 보안 강화 체크리스트 (마무리)

모든 구성이 완료되면 다음 보안 조치를 수행하십시오.

-   [ ] **Keycloak Admin 비밀번호 삭제**: `kubectl delete secret keycloak-admin-secret -n keycloak`
-   [ ] **Harbor Admin 비밀번호 변경**: Harbor UI에서 `admin` 계정 비밀번호 변경.
-   [ ] **Git 히스토리 점검**: 실수로 커밋된 비밀번호가 없는지 확인.

---

## 부록: 문서 이력

| 버전 | 날짜 | 변경 내용 |
|:---:|:---:|:---|
| 1.0 | 2026-02-09 | 초안 작성 |
| 1.5 | 2026-02-10 | Day 1 운영 흐름 재배치 |
| 1.6 | 2026-02-10 | `make opstart` 대시보드 자동화 반영 (Keycloak, ALBC, Teleport, ArgoCD, Harbor) |
