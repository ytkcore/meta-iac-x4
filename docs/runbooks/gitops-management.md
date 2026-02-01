# GitOps Operation & Troubleshooting Guide (운영 가이드)

## 1. 개요 및 배경 (Background)
본 시스템은 인프라(Terraform)와 애플리케이션(GitOps/ArgoCD)이 유기적으로 결합된 구조입니다. 이러한 복합적인 환경에서는 장애 발생 시 원인이 인프라(네트워크, 터널), 쿠버네티스(포드), 또는 GitOps(동기화) 중 어디에 있는지 파악하는 데 많은 시간이 소요됩니다.

`make status` 명령어는 이러한 진단 과정을 자동화하여, 운영자가 문제의 핵심에 단 몇 초 만에 도달할 수 있도록 설계된 **지능형 가시성 도구**입니다.

## 2. 핵심 기능 상세 (Key Features)

### 2.1. 인프라-클러스터 브릿지 (Auto-Tunneling)
- **배경**: Bastion 호스트를 통한 SSM 포트 포워딩이 끊어져 있으면 `kubectl` 명령어가 실패합니다.
- **기능**: 점검 시작 시 6443 포트가 닫혀있다면 `scripts/common/tunnel.sh`를 자동 실행하여 백그라운드 터널을 확보합니다.

### 2.2. 다차원 상태 진단 (Multi-dimensional Checks)
1.  **ArgoCD 배포 현황**: Git 리포지토리의 정의와 현재 클러스터의 상태가 일치하는지(`Synced`), 서비스가 건강한지(`Healthy`) 확인.
2.  **시스템 포드 감시**: `Running`이나 `Succeeded`가 아닌 문제 포드들만 필터링하여 출력.
3.  **외부 접속 정보 (Ingress)**: 서비스 배포 후 생성된 실제 접속 URL과 로드밸런서 주소를 요약 제공.

### 2.3. 운영 지능 (Operational Intelligence)
본 도구의 정수로, 단순 조회를 넘어 **장애 패턴을 분석하고 해결책을 제시**합니다.
- **Stuck Namespace/Application**: 네임스페이스나 앱이 삭제 중에 멈춘 경우, Finalizer 제거 명령어를 통해 즉각적인 복구가 가능하도록 가이드합니다.
- **Unknown Sync**: ArgoCD 내부 통신 장애 상황이나 `repo-server`의 과부하(OOM) 상황을 인지하여 대기 조치 및 리소스 상향을 제안합니다.
- **Container Health**: `OOMKilled`(메모리 부족)나 `ImagePullError`(이미지 주소 오류)를 실시간 감지하여 원인과 해결책을 제시합니다.

---

## 3. 사용 가이드 (Usage Guide)

### 기본 실행
```bash
# dev 환경의 부트스트랩 스택 상태 점검
aws-vault exec devops -- make status ENV=dev STACK=55-bootstrap
```

### 결과 해석 및 조치 (Standard SOP)

#### 상황 A: 전체 녹색 (`Synced`, `Healthy`)
- **해석**: 시스템이 완벽히 안정적입니다.
- **조치**: 5번 항목에 출력된 Ingress URL로 접속하여 서비스를 이용합니다.

#### 상황 B: `Missing` 상태 + `Stuck Namespace` 경고
- **해석**: 이전 리소스가 완전히 삭제되지 않아 새 버전 설치가 차단되었습니다.
- **조치**: 화면 하단에 출력된 `kubectl replace --raw ...` 명령어를 복사하여 실행합니다.

#### 상황 C: `Unknown` 상태 + `권장 조치` 안내
- **해석**: ArgoCD 컴포넌트(`repo-server`)가 일시적으로 사용 불가능하거나 메모리 부족으로 재시작 중입니다.
- **조치**: 1~2분 대기 후에도 지속된다면 `repo_server.limits.memory`를 상향(예: 1Gi) 조정합니다.

#### 상황 D: `ImagePullBackOff` 또는 `OOMKilled` 경고
- **해석**: 컨테이너가 이미지를 가져오지 못하거나 실행 중 메모리 부족으로 다운되었습니다.
- **조치**: `make status` 하단의 가이드에 따라 이미지 주소를 수정하거나 리소스 제한을 상향합니다.

---

## 4. 장애 대응 용어 정의 (Glossary)
| 상태 | 의미 | 조치 |
| :--- | :--- | :--- |
| **Synced** | Git 리포지토리와 클러스터가 완벽히 일치함 | 정상 |
| **OutOfSync** | Git의 수정사항이 아직 반영되지 않음 | 자동 동기화 대기 또는 수동 Sync 클릭 |
| **Missing** | Git에는 있으나 클러스터에 리소스가 없음 | 네임스페이스 삭제 중인지 확인 (위 가이드 3-B) |
| **Healthy** | 포드가 모두 정상 가동 중 | 정상 |
| **Progressing** | 리소스를 생성하거나 업데이트 중 | 대기 (보통 2~3분 내 완료) |
| **Unknown** | 상태 정보를 가져오지 못함 | 일시적 통신 이슈. 1분 후 재시도 |

---

> [!IMPORTANT]
> **황금률 (Golden Rule)**: 클러스터의 모든 상태 변화는 Git(`gitops-apps/`)을 통해 이루어져야 합니다. `make status`는 진단과 긴급 복구를 위한 도구이며, 설정 변경은 언제나 코드 수정과 Push로 진행하십시오.
