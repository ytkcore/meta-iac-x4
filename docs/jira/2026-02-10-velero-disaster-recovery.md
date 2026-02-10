# Velero Disaster Recovery 구성

> **Status**: ✅ 완료  
> **Priority**: High  
> **Labels**: `disaster-recovery`, `velero`, `gitops`, `terraform`  
> **적용일**: 2026-02-10  
> **커밋**: `c0b023a` — `v0.5: Source Code Freeze`

---

## 📋 요약

Kubernetes 클러스터 전체 리소스의 **자동 백업/복구** 체계를 구축한다.
Velero를 ArgoCD Application으로 배포하고, S3 버킷 및 IAM Policy를
Terraform `70-observability` 스택에 추가하여 Node IAM Role 기반 인증을 사용한다.

---

## 🎯 목표

1. Velero ArgoCD Application 매니페스트 작성 (daily backup, 7-day retention)
2. S3 버킷 `dev-meta-velero-backup` + IAM Policy Terraform 리소스 추가
3. EBS Snapshot 권한 포함 (PV 복구 대비)
4. Longhorn 백업과 동일한 패턴(Node IAM Role) 적용

---

## 📂 변경 파일

| 파일 | 변경 |
|:-----|:-----|
| `gitops-apps/bootstrap/velero.yaml` | [NEW] ArgoCD Application — Velero Helm Chart |
| `stacks/dev/70-observability/main.tf` | [MOD] S3 버킷 + IAM Policy + Role Attachment 추가 |
| `stacks/dev/70-observability/variables.tf` | [MOD] `velero_backup_bucket` 변수 추가 |
| `stacks/dev/env.tfvars` | [MOD] `velero_backup_bucket = "dev-meta-velero-backup"` |

### velero.yaml 주요 설정

```yaml
configuration:
  backupStorageLocations:
    - name: default
      provider: aws
      bucket: dev-meta-velero-backup
      config:
        region: ap-northeast-2
  defaultBackupTTL: "168h"   # 7일
schedules:
  daily-backup:
    schedule: "0 2 * * *"    # 매일 02:00 UTC
    includedNamespaces: ["*"]
    excludedNamespaces: ["kube-system", "kube-public"]
```

### IAM Policy 주요 권한

```
s3:PutObject, s3:GetObject, s3:ListBucket, s3:DeleteObject, s3:GetBucketLocation
ec2:DescribeVolumes, ec2:DescribeSnapshots, ec2:CreateTags, ec2:CreateSnapshot, ec2:DeleteSnapshot
```

---

## ✅ 작업 내역

- [x] **1.1** Velero ArgoCD Application 매니페스트 작성
- [x] **1.2** Helm values 설정 (daily backup, 7-day TTL, AWS plugin)
- [x] **1.3** Terraform S3 버킷 + IAM Policy 리소스 추가
- [x] **1.4** Node IAM Role Attachment (Longhorn 패턴 동일)
- [x] **1.5** `env.tfvars`에 버킷명 추가

---

## 🔗 관련 티켓 / 문서

- [longhorn-distributed-storage](2026-02-03-longhorn-distributed-storage.md) — S3 백업 패턴 원형
- [v0.5-customer-services](2026-02-10-customer-services-deployment.md) — 동일 커밋
- [v0.5-source-freeze](2026-02-10-v05-source-freeze.md) — v0.5 프리징

---

## 📝 비고

- Post-deploy: `70-observability` 스택 `make apply` 필요 (S3 버킷 생성)
- `env.tfvars`는 `.gitignore` 대상 — 로컬에서만 관리
- etcd 백업은 RKE2 built-in `etcd-snapshot-schedule-cron` 사용 (별도 설정 불필요)
