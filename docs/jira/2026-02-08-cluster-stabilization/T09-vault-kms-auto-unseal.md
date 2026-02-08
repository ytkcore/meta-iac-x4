# T9: Vault AWS KMS Auto-Unseal

> **Parent**: [클러스터 안정화](../2026-02-08-cluster-stabilization.md) | **Status**: ✅ 완료

## 📋 Summary

Vault의 Seal 메커니즘을 Shamir (수동 5/3 threshold) → AWS KMS (자동 unseal)로 마이그레이션. Pod 재시작 시 자동 unseal 확인.

> [!IMPORTANT]
> Cilium ENI 모드에서 Pod IMDS 접근에 2 hop이 필요하지만 AWS 기본 hop_limit=1 → IMDS 접근 실패.
> `ec2-instance` 모듈에 `hop_limit=2` 추가로 해결.

## 🔍 변경 전 (Shamir)

```
$ vault status
Seal Type       shamir
Sealed          true
Total Shares    5
Threshold       3
```

Pod 재시작 → **Sealed** → 관리자가 수동으로 3개 키 입력 필요 → 운영 부담

## 🔧 마이그레이션 과정

### Step 1: KMS 키 생성 (Terraform)
```hcl
# stacks/dev/55-bootstrap/main.tf
resource "aws_kms_key" "vault_unseal" {
  description             = "Vault Auto-Unseal Key"
  deletion_window_in_days = 30
  enable_key_rotation     = true    # 보안: 자동 키 로테이션
}
```

KMS Key ID: `fcaa0e8d-2ee9-4f2e-8895-947d2bfd19e6`

### Step 2: IAM Policy (Node Role)
```hcl
resource "aws_iam_role_policy" "vault_kms_unseal" {
  name = "vault-kms-unseal"
  role = data.aws_iam_role.worker_node.id
  policy = jsonencode({
    Statement = [{
      Effect = "Allow"
      Action = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:DescribeKey"
      ]
      Resource = [aws_kms_key.vault_unseal.arn]
    }]
  })
}
```

### Step 3: Vault Seal 설정 변경
```yaml
# gitops-apps/bootstrap/vault.yaml → values
server:
  standalone:
    config: |
      seal "awskms" {
        region     = "ap-northeast-2"
        kms_key_id = "fcaa0e8d-2ee9-4f2e-8895-947d2bfd19e6"
      }
```

### Step 4: IMDS hop_limit 수정 ⚠️
**발견된 이슈**: Cilium ENI 모드에서 Pod → EC2 IMDS 경로가 2 hop (Pod → veth → ENI → IMDS). AWS 기본 hop_limit=1이므로 IMDS 접근 실패 → KMS 인증 불가.

```hcl
# modules/ec2-instance/main.tf
metadata_options {
  http_endpoint               = "enabled"
  http_tokens                 = "required"    # IMDSv2 강제
  http_put_response_hop_limit = 2             # ← 1 → 2 (Cilium ENI 필수)
}
```

> worker-04 노드에서 먼저 수동 변경 후 검증:
> ```bash
> aws ec2 modify-instance-metadata-options \
>   --instance-id i-xxx \
>   --http-put-response-hop-limit 2
> ```

### Step 5: Seal Migration
```bash
# Vault Pod 내부에서 실행
vault operator unseal -migrate <key-1>
vault operator unseal -migrate <key-2>
vault operator unseal -migrate <key-3>
# → Seal migration complete!
```

기존 Shamir 키 → **Recovery Keys**로 자동 전환. JIC(Just In Case) 보관.

### Step 6: 자동 Unseal 검증
```bash
# Pod 강제 삭제 (재시작 트리거)
kubectl -n vault delete pod vault-0

# 30초 후 확인
vault status
# Seal Type       awskms
# Sealed          false     ← 자동 unseal!
```

## ✅ 변경 후 (KMS)

```
$ vault status
Seal Type       awskms
Sealed          false          ← 자동!
Total Recovery Shares  5
Recovery Threshold     3
```

## 💡 Lessons Learned

1. **Cilium ENI + IMDS**: ENI 모드에서 Pod의 IMDS 접근은 2 hop을 소모. `hop_limit=2` 필수.
2. **Seal Migration**: Shamir → KMS migration은 5분 이내 완료. 기존 키는 Recovery Keys로 유지.
3. **Key Rotation**: KMS key에 `enable_key_rotation = true` 설정 → AWS가 자동으로 연간 키 로테이션.

## 🔧 변경 파일

| 파일 | 변경 | 커밋 |
|------|------|------|
| `stacks/dev/55-bootstrap/main.tf` | KMS Key + IAM Policy | `94d787c` |
| `gitops-apps/bootstrap/vault.yaml` | `seal "awskms"` stanza | `ffb5877` |
| `modules/ec2-instance/main.tf` | `hop_limit=2` | `bf18e79` |
| `docs/vault/vault-kms-auto-unseal.md` | [NEW] 운영 가이드 | `bf18e79` |

## 🏷️ Labels
`vault`, `kms`, `auto-unseal`, `imds`, `security`, `cilium`
