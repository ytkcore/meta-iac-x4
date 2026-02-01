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

## 4. 검증 (Verification)

1. **노드 ProviderID 확인**:
   ```bash
   kubectl get nodes -o custom-columns=NAME:.metadata.name,PROVIDERID:.spec.providerID
   # 출력 예: aws:///ap-northeast-2a/i-0123456789abcdef0 (값이 있어야 함)
   ```

2. **LoadBalancer 상태 확인**:
   ```bash
   kubectl get svc -n ingress-nginx
   # EXTERNAL-IP에 AWS DNS 주소(예: *.elb.amazonaws.com)가 할당되어야 함.
   ```
