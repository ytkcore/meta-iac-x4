# RUNBOOK (Final v1.0)

이 문서는 “운영자가 실제로 자주 쓰는 커맨드” 중심으로 정리한 실행 가이드입니다.

## 0) 공통 전제
- MFA/STS 사용을 위해 **aws-vault**로 실행하는 것을 권장합니다.
- State backend는 **S3 + S3 native locking(`use_lockfile=true`)** 를 사용합니다.

## 1) 1회성(초기) 작업

### 1-1. 환경 파일 생성
```bash
make env-init ENV=dev
# stacks/dev/env.tfvars 생성 → STATE_BUCKET 등 값 수정
```

### 1-2. backend bootstrap (tfstate 전용 버킷 생성)
- 버킷이 이미 존재하면 bootstrap이 자동으로 state import 후 apply 합니다.
```bash
aws-vault exec <profile> -- make backend-bootstrap ENV=dev
```

## 2) Day-2 운영(스택 단위)

### 2-1. 네트워크(기반)
```bash
aws-vault exec <profile> -- make plan  ENV=dev STACK=00-network
aws-vault exec <profile> -- make apply ENV=dev STACK=00-network
```

- `00-network`에는 **Gateway VPC Endpoint(S3/DynamoDB)** 가 기본 포함됩니다.

### 2-2. 보안(SG 등)
```bash
aws-vault exec <profile> -- make plan  ENV=dev STACK=10-security
aws-vault exec <profile> -- make apply ENV=dev STACK=10-security
```

### 2-3. Interface Endpoint(기본 OFF)
Interface endpoint가 필요할 때만 `20-endpoints`를 apply 합니다.
- 기본값:
  - `enable_interface_endpoints = false`
  - `interface_services = []`

```bash
aws-vault exec <profile> -- make plan  ENV=dev STACK=20-endpoints
aws-vault exec <profile> -- make apply ENV=dev STACK=20-endpoints
```

### 2-4. DB subnet group
```bash
aws-vault exec <profile> -- make plan  ENV=dev STACK=30-db
aws-vault exec <profile> -- make apply ENV=dev STACK=30-db
```

### 2-5. Bastion(SSM only)
```bash
aws-vault exec <profile> -- make plan  ENV=dev STACK=30-bastion
- 40-harbor (Harbor EC2 레지스트리/캐시 노드)
aws-vault exec <profile> -- make apply ENV=dev STACK=30-bastion
- 40-harbor (Harbor EC2 레지스트리/캐시 노드)
```

## 3) 전체 스택 일괄 적용
```bash
aws-vault exec <profile> -- make apply-all ENV=dev
```

## 4) 품질/검증
```bash
make check        # fmt check (로컬 친화; rc=3은 오류 아님)
make check-ci     # CI용 엄격 check
make fmt          # fmt 적용
make lint-all     # tflint
aws-vault exec <profile> -- make whoami
```

## 5) 원복/강제 리셋(주의)
### backend bucket까지 삭제(정말 필요한 경우만)
```bash
aws-vault exec <profile> -- make backend-destroy ENV=dev STATE_BUCKET=enc-tfstate FORCE=1
# 필요 시(버킷이 비어있지 않다면) 비우기
aws-vault exec <profile> -- ./scripts/empty-s3-bucket.sh <bucket>
```

## 2-4. Kubernetes (RKE2) 배포 (Self-managed)

**개발망 기본값**
- Control Plane: 3대
- Worker(Data Plane): 4대
- 인스턴스: t3.large
- Root EBS: gp3 30GB
- 접속: SSM only (SSH 없음)
- 내부 NLB(기본 ON): 9345/6443

```bash
# 네트워크 선행
aws-vault exec <profile> -- make apply ENV=dev STACK=00-network

# (선택) Bastion (SSM-only)
aws-vault exec <profile> -- make apply ENV=dev STACK=30-bastion
- 40-harbor (Harbor EC2 레지스트리/캐시 노드)

# RKE2
aws-vault exec <profile> -- make plan  ENV=dev STACK=50-rke2
aws-vault exec <profile> -- make apply ENV=dev STACK=50-rke2
```

### 참고
- NAT가 비활성화되어 외부 통신이 불가하면, RKE2 설치/이미지 pull을 위해 airgap 번들이 필요합니다(추가 작업).
- 내부 NLB DNS는 `make output ENV=dev STACK=50-rke2`로 확인 가능합니다.

### OS 변경(선택)
- 기본: `al2023`
- Ubuntu 22.04로 변경:
  ```bash
  aws-vault exec <profile> -- make apply ENV=dev STACK=50-rke2 \
    TF_OPTS='-compact-warnings -var="os_family=ubuntu2204"'
  ```
