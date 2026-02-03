# 트러블슈팅 - Terraform Destroy Provisioner 변수 참조 오류

`make destroy` 과정에서 발생할 수 있는 Terraform의 설계상 제약 사항과 해결 방법을 정리합니다.

## 문제 상황

Terraform의 `destroy` 단계 프로비저너(`provisioner "local-exec" { when = destroy }`)에서 외부 변수(예: `var.kubeconfig_path`)를 직접 참조하려고 할 때 다음과 같은 에러가 발생하며 초기화(`init`)가 실패합니다.

```text
Error: Invalid reference from destroy provisioner
Destroy-time provisioners and their connection configurations may only reference attributes of the related resource, via 'self', 'count.index', or 'each.key'.
```

## 원인

Terraform의 설계 구조상, 리소스가 삭제되는 시점에는 해당 리소스의 의존성 그래프가 이미 해제되었을 가능성이 높습니다. 따라서 `destroy` 시점의 프로비저너는 보안상의 이유와 정합성 보장을 위해 오직 **자기 자신(`self`)**의 속성이나 `count.index`, `each.key`만을 참조할 수 있도록 제한되어 있습니다.

## 해결 방법

`triggers` 속성을 가진 `null_resource`를 사용하여, **리소스가 생성되거나 업데이트되는 시점에 필요한 값을 미리 캡처(Capture)**해 두어야 합니다.

### 예시 코드 (리팩토링 후)

```hcl
resource "null_resource" "graceful_cleanup" {
  triggers = {
    # 삭제 시점에 필요한 값을 미리 저장
    kubeconfig_path = pathexpand(var.kubeconfig_path)
    cleanup_script  = "${path.module}/scripts/cleanup.sh"
  }

  provisioner "local-exec" {
    when    = destroy
    # 외부 변수가 아닌 self.triggers를 통해 접근
    command = "${self.triggers.cleanup_script} ${self.triggers.kubeconfig_path}"
  }
}
```

## 추가 이슈: Makefile 인프라 삭제 시 의존성 체크 실패

`make destroy` 실행 시, 클러스터가 이미 삭제되었거나 접근 불가능한 상태에서 `kubeconfig` 탐색 중 에러가 발생하여 프로세스가 중단되는 경우가 있습니다.

### 문제 상황
```text
Error: No running Control Plane nodes found.
make: *** [kubeconfig-check] Error 1
```

### 해결 방법
`makefiles/ssm.mk`를 수정하여, 명령 대상(Goal)이 `destroy`를 포함하고 있을 경우 클러스터 탐색 실패를 '치명적 에러'가 아닌 '경고(Warning)'로 처리하고 프로세스를 계속 진행하도록 로직을 개선했습니다. 

삭제 시점에는 인프라가 이미 부재할 수 있다는 점을 고려한 **멱등성(Idempotency)** 확보의 일환입니다.

---

## 교훈 (최종)
1.  **Destroy Provisioner의 한계**: 삭제 시점에는 `var.*`나 다른 리소스의 속성을 직접 참조할 수 없음을 항상 인지해야 합니다.
2.  **Triggers 활용**: 삭제 시점에 외부 정보가 필요하다면 반드시 `triggers`에 해당 정보를 명시하여 리소스 상태 데이터에 포함시켜야 합니다.
3.  **Makefile 유연성**: 자동화 스크립트(Makefile) 단계에서도 `destroy` 모드일 때는 체크 로직을 완화하여, 이미 삭제된 인프라에 대한 중복 삭제 시도를 허용해야 합니다.

---

## 추가 이슈: Security Group 삭제 시 DependencyViolation 발생

`make destroy STACK=50-rke2` 실행 중 보안 그룹(SG) 삭제 단계에서 멈추거나 실패하는 현상입니다.

### 문제 상황
```text
module.rke2.aws_security_group.nodes: Still destroying... [id=sg-xxxx, 02m00s elapsed]
api error DependencyViolation: resource sg-xxxx has a dependent object
```

### 원인
RKE2/Kubernetes 상에서 생성된 **로드밸런서(ELB/NLB)**나 **네트워크 인터페이스(ENI)**가 해당 보안 그룹을 여전히 참조하고 있기 때문입니다. 
- 클러스터가 활성 상태일 때는 `pre-destroy-hook.sh`가 이를 정리하지만, 클러스터 제어부(Control Plane)가 이미 중지되었거나 삭제된 상태라면 `kubectl`을 통한 자동 정리가 불가능해집니다.

### 해결 방법 (자동화 및 방법론)

테라폼 상태 파일(tfstate)에는 없으나 실제 클라우드 환경에서 의존성을 방해하는 자원들을 처리하는 **"Identify-Verify-Automate"** 방법론을 적용합니다.

1.  **자원 식별 (Identify via Tags)**:
    - Kubernetes가 동적으로 생성한 모든 AWS 자원(LB, ENI 등)은 `kubernetes.io/cluster/<cluster-name>` 태그를 가집니다.
    - SG 삭제를 막는 주범은 주로 이 태그가 달린 고아(Orphaned) **ENI**들입니다.

2.  **검증 및 적용 (Verify & Automate)**:
    - `pre-destroy-hook.sh`를 통해 테라폼 삭제 전 해당 태그를 가진 모든 **LoadBalancer**와 **Network Interface(ENI)**를 AWS CLI로 직접 조회하여 삭제합니다.
    - **중요**: 클러스터 제어부(Control Plane)가 이미 삭제된 경우 `tunnel.sh` 에러나 `kubectl` 스킵 메시지가 뜰 수 있으나, 이는 정상입니다. 훅은 이를 감지하고 **AWS API를 통한 직접 정리** 단계로 자동 전환하여 SG 해방을 완수합니다.

### 해결 방법 (수동 정리)
... (기존 내용 동일)

1.  **점유 중인 ENI 찾기 (AWS CLI)**:
    ```bash
    # SG_ID를 에러 메시지에 나온 ID로 대체
    SG_ID="sg-03bea70608a27baba"
    aws ec2 describe-network-interfaces --filters Name=group-id,Values=$SG_ID --query "NetworkInterfaces[*].{ID:NetworkInterfaceId,Status:Status,Description:Description}" --output table
    ```

2.  **리소스 식별 및 삭제**:
    - `Description` 필드에 `ELB net/k8s-...`와 같이 표시된다면, 해당 로드밸런서를 찾아 삭제해야 합니다.
    - EC2 콘솔의 **Network Interfaces** 메뉴에서 해당 SG로 필터링하여 수동으로 `Detach` 및 `Delete`를 수행할 수도 있습니다.

3.  **테라폼 상태 정리 (최후의 수단)**:
    - 클라우드 리소스를 콘솔에서 직접 지웠음에도 테라폼이 인지하지 못하고 계속 멈춰있다면, 상태 파일에서 해당 리소스를 제거합니다.
    ```bash
    aws-vault exec devops -- terraform -chdir=stacks/dev/50-rke2 state rm module.rke2.aws_security_group.nodes
    ```

### 추가 이슈: 교차 보안 그룹 참조(Cross-SG Reference)에 의한 삭제 지연

ENI와 LB를 모두 지웠음에도 불구하고 `Still destroying...` 상태가 2분-6분 이상 지속되거나 최종적으로 실패하는 경우입니다.

#### 문제 상황
- `pre-destroy-hook.sh` 로그에서 ENI가 없음을 확인했으나 테라폼은 SG 삭제를 못 함.
- AWS API 에러: `DependencyViolation: resource sg-xxxx has a dependent object`

#### 원인
타 스택(예: `60-db`의 Neo4j, Postgres)에서 K8s 노드와 통신하기 위해 **K8s SG ID를 직접 참조**하는 규칙을 가지고 있기 때문입니다. 
- AWS는 다른 SG가 삭제하려는 SG를 참조하고 있으면 삭제를 허용하지 않습니다.
- Terraform은 이 "순환 참조" 또는 "교차 참조"를 해결하려 수 차례 재시도하며 시간을 소모합니다.

#### 해결 방법 (응급 처치: Proactive Purge)
`pre-destroy-hook.sh`에 **교차 참조 규칙 자동 제거** 로직을 추가했습니다.
- 테라폼이 삭제 명령을 내리기 전, AWS CLI로 타 SG들을 검색하여 우리를 참조하는 룰을 강제로 **Revoke** 처리합니다.
- 이때 자원의 태그를 식별하여 `[Cluster Resource]`는 즉시 정리하고, `[External Resource]`는 연결 고리만 쏙 제거하는 안정 장치를 포함합니다.

#### 해결 방법 (근본 대책: Hybrid Decoupling)
인프라 설계를 **강한 결합(Tight Coupling)**에서 **느슨한 결합(Decoupling)**으로 리팩토링했습니다.

1.  **Static Client SG 도입**: `10-security`에서 이름이 고정된 'K8s Client SG'를 생성합니다. (룰이 비어있는 불변의 ID)
2.  **하이브리드 보안 규칙**: DB 스택(`60-db`)에서 SG ID 대신 **`Static SG ID` + `Subnet CIDR`**을 조합하여 Ingress를 허용합니다.
3.  **노드 자동 부착**: RKE2 노드가 생성될 때 자신의 SG 외에 이 `Static SG`를 추가로 입고 나오게 합니다.

**결과**: RKE2를 파괴해도 DB 설정은 단 1mm도 변하지 않으며, 참조 관계가 해소되어 SG 삭제가 **지연 없이 1~2초 내에 즉시 완료**됩니다.

---

### 교훈
- **생명 주기 분리(Decoupling)**: 생명 주기가 다른 자원(RKE2 vs DB)은 서로의 ID를 직접 참조하지 않도록 '중간 매개체(Static SG)'나 '공통 신뢰 구역(CIDR)'을 설계 단계에서 고려해야 합니다.
- **신원 + 위치 기반 보안**: 단순 SG ID 참조보다는 "신원(SG 옷) + 위치(CIDR 구역)" 조합이 보안성과 운영성(삭제 속도) 면에서 훨씬 우월합니다.
- **자동화의 한계**: 설계(Architecture)가 엉켜 있으면 자동화(Hook)는 복잡해질 수밖에 없습니다. 최고의 트러블슈팅은 설계 개선을 통한 문제의 원천 봉쇄입니다.
