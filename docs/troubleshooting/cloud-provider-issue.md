# Troubleshooting: AWS RKE2 LoadBalancer Pending Issue

## 1. 장애 현황 (Symptoms)
RKE2 클러스터(`v1.31.x`)에서 `ingress-nginx`와 같은 `Type: LoadBalancer` 서비스가 생성되었으나, `EXTERNAL-IP`가 할당되지 않고 `<pending>` 상태로 지속됨.

```bash
$ kubectl get svc -n kube-system
NAME                                 TYPE           CLUSTER-IP      EXTERNAL-IP   PORT(S)                      AGE
rke2-ingress-nginx-controller        LoadBalancer   10.43.128.119   <pending>     80:32030/TCP,443:31534/TCP   15m
```

---

## 2. 원인 분석 (Root Cause Analysis)

### 2.1. In-tree Cloud Provider 제거 (Kubernetes v1.27+)
- 과거 RKE2 버전에서는 `cloud-provider-name: "aws"` 설정을 통해 Kubernetes 내장(In-tree) AWS Provider를 사용했음.
- **Kubernetes v1.27부터 In-tree Provider 코드가 제거**되었으며, 대신 **External Cloud Controller Manager (CCM)** 를 사용해야 함.
- 기존 설정(`cloud-provider-name: "aws"`)을 RKE2 v1.31에 적용하면, `kubelet`이 레거시 모드로 동작하려 시도하다가 실패하거나, 올바른 Provider ID를 찾지 못함.

### 2.2. 리소스 태그 및 노드 설정 불일치
- **AWS 태그 누락**: CCM이 AWS 리소스(Subnet, Security Group, Node)를 식별하기 위해 `kubernetes.io/cluster/<cluster-name>` 태그가 필수적임.
- **Node Naming 불일치**: External CCM은 노드의 이름이 AWS Private DNS Name(e.g., `ip-10-0-10-5.ap-northeast-2.compute.internal`)과 일치해야 해당 인스턴스를 매핑할 수 있음. 임의의 노드 이름(예: `cp-01`)을 사용할 경우 매핑 실패 발생.

---

## 3. 해결 방법 (Resolution)

### 3.1. RKE2 Configuration 수정
RKE2 설정 파일(`config.yaml`)에 다음 옵션을 적용하여 External Provider 모드를 활성화하고, 노드 이름을 클라우드 메타데이터와 동기화함.

**`/etc/rancher/rke2/config.yaml`**:
```yaml
# 1. External Cloud Provider 모드 활성화 (In-tree 비활성화)
cloud-provider-name: "external"

# 2. 노드 이름을 AWS Private DNS와 일치시킴 (CCM 연동 필수)
node-name-from-cloud-provider-metadata: true
# node-name: "cp-01"  <-- (제거) 임의 호스트명 사용 금지
```

### 3.2. Terraform 인프라 태그 업데이트
AWS 리소스가 Kubernetes 클러스터 소유임을 명시.

| 리소스 | 태그 Key | 태그 Value | 비고 |
|---|---|---|---|
| **Control Plane / Worker Instances** | `kubernetes.io/cluster/<cluster-name>` | `owned` | CCM이 인스턴스 조회 |
| **Public/Private Subnets** | `kubernetes.io/cluster/<cluster-name>` | `shared` | ELB 생성 위치 식별 |
| **Security Groups** | `kubernetes.io/cluster/<cluster-name>` | `owned` | ELB 보안 그룹 관리 |

### 3.3. AWS Cloud Controller Manager (CCM) 배포
RKE2가 `external` 모드로 실행되면 클라우드 관련 컨트롤러 루프가 비활성화됨. 따라서 `aws-cloud-controller-manager`를 별도로 배포해야 함.

**Helm Chart (ArgoCD)**:
- **Chart**: `aws-cloud-controller-manager` (kubernetes/cloud-provider-aws)
- **Settings**:
  - `--cloud-provider=aws`
  - `--cluster-name=<your-cluster-name>`
  - `--configure-cloud-routes=false` (VPC CNI 사용 시 false 권장)
  - `hostNetwork: true` (컨트롤 플레인 노드에서 실행 권장)

---


## 4. 주요 트러블슈팅 사례 (Common Issues & Fixes)

이번 통합 과정에서 발생한 주요 문제와 해결 방법입니다.

### 4.1. IAM 권한 부족 (403 UnauthorizedOperation)
*   **증상**: CCM 파드 로그에 `UnauthorizedOperation: You are not authorized to perform this operation.` 에러 발생.
*   **원인**: 기본 노드 IAM 역할에 Cloud Controller Manager가 필요로 하는 EC2 및 AutoScaling 조회/수정 권한이 부족함.
*   **해결**: Terraform `rke2-cluster` 모듈의 IAM 정책(`nodes_elb`)에 다음 권한을 추가해야 함.
    ```json
    "autoscaling:DescribeAutoScalingGroups",
    "autoscaling:DescribeLaunchConfigurations",
    "autoscaling:DescribeTags",
    "ec2:DescribeRegions",
    "ec2:DescribeRouteTables",
    "ec2:CreateSecurityGroup",
    "ec2:CreateTags",
    "ec2:CreateVolume",
    "ec2:ModifyInstanceAttribute",
    // ... (기타 EC2/ELB 관련 권한)
    ```

### 4.2. Taint Deadlock (파드 스케줄링 불가)
*   **증상**: ArgoCD 및 CCM 파드가 `Pending` 상태로 멈춤. 노드 상태를 확인하면 `node.cloudprovider.kubernetes.io/uninitialized:NoSchedule` Taint가 존재함.
*   **원인**: RKE2를 `external` 모드로 설정하면 노드는 초기화되지 않은 상태로 시작되며, CCM이 실행되어야만 이 Taint가 제거됨. 하지만 CCM 자체도 파드이므로 노드에 스케줄링되어야 하는데, Taint 때문에 스케줄링되지 못하는 순환 의존성(Deadlock) 발생.
*   **해결**: 최초 1회, 수동으로 모든 노드의 Taint를 제거하여 CCM이 배포될 수 있도록 함.
    ```bash
    kubectl taint nodes --all node.cloudprovider.kubernetes.io/uninitialized-
    ```

### 4.3. Cluster Name 불일치
*   **증상**: CCM 파드는 정상 실행 중이나, 노드의 `ProviderID`가 채워지지 않고 로그에 `AWS cloud filtering on ClusterID: ...` 메시지만 반복됨.
*   **원인**: 인프라(EC2)에 태깅된 클러스터 이름(`kubernetes.io/cluster/<name>`)과 CCM 실행 인자(`--cluster-name`)가 다를 경우, CCM은 자신의 관리 대상 리소스를 식별하지 못함.
*   **해결**: Terraform 변수(`local.cluster_name`)와 ArgoCD Application의 `helm.values` 내 `--cluster-name` 파라미터를 정확히 일치시킴 (예: `meta-dev-k8s`).

### 4.4. Webhook Deadlock (유령 웹후크로 인한 삭제/생성 고착)
*   **증상**: ArgoCD의 특정 Application(예: `rancher`)이 삭제 중(`Terminating`) 또는 생성 중(`Progressing`) 멈춤. 상세 에러에 `failed calling webhook "validate.nginx.ingress.kubernetes.io": Post ... no endpoints available` 메시지 발생.
*   **원인**: RKE2 기본 Ingress를 제거했음에도 불구하고, 해당 컨트롤러가 등록해둔 `ValidatingWebhookConfiguration`이 클러스터에 남아있어 Ingress 리소스의 변경(삭제/수정)을 검증하려 시도하다가 실패함.
*   **해결**: 응답하지 않는 유령 웹후크 설정을 찾아 삭제함.
    ```bash
    kubectl get validatingwebhookconfigurations
    kubectl delete validatingwebhookconfiguration rke2-ingress-nginx-admission
    ```

---

## 5. 검증 (Verification)

### 5.1. 노드 ProviderID 확인
CCM이 정상 동작하면 모든 노드에 `ProviderID`가 주입됩니다.
```bash
$ kubectl get nodes -o custom-columns=NAME:.metadata.name,PROVIDERID:.spec.providerID
NAME                                             PROVIDERID
ip-10-0-11-153.ap-northeast-2.compute.internal   aws:///ap-northeast-2a/i-0adf471792f2bce55
```

### 5.2. LoadBalancer 외부 IP 할당 확인
Ingress Controller 서비스가 AWS ELB 주소를 획득했는지 확인합니다.
```bash
$ kubectl get svc -n kube-system rke2-ingress-nginx-controller
NAME                            TYPE           EXTERNAL-IP                                          PORT(S)
rke2-ingress-nginx-controller   LoadBalancer   xxxx.elb.ap-northeast-2.amazonaws.com   80:30080/TCP,443:30443/TCP
```
