# Manual Resource Cleanup (Force Cleanup)

## 개요
Terraform 상태(`tfstate`)와 실제 AWS 리소스 간의 불일치(Drift)가 발생했거나, `terraform destroy`가 실패하여 "좀비 리소스"가 남았을 때 사용하는 긴급 복구 가이드입니다.

이 가이드는 `scripts/force-cleanup.sh` 스크립트를 사용하여 리소스를 강제로 정리하는 방법을 설명합니다.

## 언제 사용하나요?
- `terraform destroy`를 실행했는데 에러가 발생하며 일부 리소스가 삭제되지 않을 때.
- `EntityAlreadyExists` 에러로 인해 `terraform apply`가 실패할 때.
- IAM Role, Target Group 등이 "DeleteConflict" 상태에 빠져 수동 삭제가 필요할 때.

## 사전 준비
- **AWS CLI** 설치 필요.
- **aws-vault** 설정 필요 (권한 있는 프로파일).
- `scripts/force-cleanup.sh` 실행 권한 (`chmod +x scripts/force-cleanup.sh`).

---

## 실행 방법

### 1단계: Dry Run (삭제 대상 확인)
먼저 실제로 무엇이 삭제될지 확인합니다. `--execute` 옵션 없이 실행하면 삭제하지 않고 목록만 출력합니다.

```bash
# 사용법: ./scripts/force-cleanup.sh <ENV> <PROJECT>
aws-vault exec devops -- ./scripts/force-cleanup.sh dev meta
```

출력 예시:
```text
=== DRY RUN MODE: No resources will be deleted ===
Targeting resources with prefix: dev-meta
Found Role: dev-meta-harbor-role
...
```

### 2단계: 실제 삭제 (Execute)
삭제 대상이 맞다면 `--execute` 옵션을 붙여 실행합니다. **(주의: 복구 불가능)**

```bash
aws-vault exec devops -- ./scripts/force-cleanup.sh dev meta --execute
```

---

## 스크립트가 처리하는 리소스
이 스크립트는 프로젝트 네이밍 컨벤션(`{ENV}-{PROJECT}-*`)을 따르는 다음 리소스들을 순서대로 정리합니다:

1.  **IAM (가장 중요)**
    *   Managed Policy 연결 해제 (Detach)
    *   Inline Policy 삭제
    *   Instance Profile에서 Role 제거
    *   Instance Profile 삭제
    *   Role 삭제
2.  **Load Balancers (ELB v2)**
    *   Deletion Protection 비활성화
    *   Load Balancer 삭제
    *   Target Group 삭제
3.  **EC2 Instances**
    *   Termination Protection 비활성화
    *   인스턴스 종료 (Terminate)
4.  **Security Groups**
    *   Security Group 삭제 (의존성 문제 시 재시도 로직 포함)
