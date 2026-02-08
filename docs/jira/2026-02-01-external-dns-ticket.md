# [Task] ExternalDNS 도입 및 최소 권한(Least Privilege) 적용

## 요약 (Summary)
Kubernetes Ingress 리소스에 대한 DNS 레코드 관리를 자동화하고, 글로벌 GitOps 표준을 준수하기 위해 **ExternalDNS**를 도입합니다. 이때, 보안 원칙인 **최소 권한(Least Privilege)**을 준수하여 AWS Route53 권한을 특정 호스팅 영역(Hosted Zone)으로 엄격히 제한합니다.

## 배경 및 필요성 (Context & Motivation)
현재 ArgoCD, Rancher 등의 서비스 배포 시 DNS 레코드를 수동으로 생성하거나, "닭과 달걀(Chicken-and-Egg)" 문제로 인해 Terraform에서 불안정하게 처리하고 있습니다.

**ExternalDNS** 도입 시 기대 효과:
1.  **자동화 (Automation)**: Kubernetes Ingress 생성 시 자동으로 Route53 레코드를 생성/업데이트합니다.
2.  **GitOps 일원화**: 인프라 설정(DNS)을 별도 작업이 아닌 애플리케이션 매니페스트(Ingress)의 일부로 관리합니다.
3.  **안정성 (Reliability)**: 수동 작업으로 인한 휴먼 에러를 제거합니다.

## 글로벌 표준 및 보안 (Global Standards)
-   **CNCF Landscape**: ExternalDNS는 K8s 서비스와 DNS 공급자를 동기화하는 업계 표준 컨트롤러입니다.
-   **보안 (최소 권한 원칙)**:
    -   `AmazonRoute53FullAccess` (모든 도메인에 대한 Wildcard 권한) 사용을 지양합니다.
    -   `base_domain`에서 파생된 **특정 Hosted Zone ID**에 대해서만 `ChangeResourceRecordSets` 권한을 허용하는 **Scoped Policy**를 적용해야 합니다.

## 구현 계획 (Implementation Plan)

### 1. 인프라 (Terraform)
-   **대상 스택**: `50-rke2`
-   **작업 내용**: Scoped IAM Policy 생성 및 부착
-   **정책 상세**:
    -   Allow Action: `route53:ChangeResourceRecordSets`
    -   Resource: `arn:aws:route53:::hostedzone/<HOSTED_ZONE_ID>` (입력된 `base_domain` 기준)
    -   Allow Action: `route53:ListHostedZones`, `route53:ListResourceRecordSets` (Global/ReadOnly - 탐색용)
-   **적용 방법**: 생성된 정책의 ARN을 RKE2 모듈의 `extra_policy_arns` 변수에 주입

### 2. GitOps (ArgoCD)
-   **애플리케이션**: `external-dns`
-   **구성**:
    -   Source: `bitnami/external-dns`
    -   Domain Filter: `<base_domain>` (예: `dev.unifiedmeta.net`)
    -   Policy: `sync` (생성/수정/삭제 동기화)

## 완료 조건 (Acceptance Criteria)
-   [ ] `50-rke2` 스택에서 특정 Zone으로 제한된 IAM Policy가 생성되어야 한다.
-   [ ] RKE2 노드 역할(Role)에 해당 정책이 정상적으로 부착되어야 한다.
-   [ ] ExternalDNS 파드가 오류 없이 구동되어야 한다.
-   [ ] 테스트 Ingress (예: `nginx-test`) 생성 시 Route53 레코드가 자동으로 생성되어야 한다.
