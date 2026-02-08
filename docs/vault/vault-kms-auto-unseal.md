# Vault KMS Auto-Unseal — 운영 가이드

> **목적**: Vault Shamir 수동 Unseal → AWS KMS 자동 Unseal 마이그레이션의 **배경, 구현, 운영 절차**를 문서화한다.  
> **상태**: ✅ 완료 (2026-02-08)  
> **관련 문서**: [Vault HA 전환 로드맵](vault-ha-transition-roadmap.md) (Phase A)

---

## 1. 왜 Auto-Unseal이 필요한가

### 1.1 Shamir Seal의 운영 리스크

Vault는 기본적으로 **Shamir's Secret Sharing** 알고리즘으로 Master Key를 분할한다.  
초기화 시 5개의 Unseal Key가 생성되며, Vault를 열려면 **최소 3개의 키를 수동 입력**해야 한다.

```
Master Key ──▶ Shamir 5-of-3 분할
                ├── Unseal Key 1  (관리자 A 보관)
                ├── Unseal Key 2  (관리자 B 보관)
                ├── Unseal Key 3  (관리자 C 보관)
                ├── Unseal Key 4  (금고 보관)
                └── Unseal Key 5  (금고 보관)
```

**문제 시나리오:**

| 시나리오 | 영향 | 복구 시간 |
|----------|------|----------|
| Pod 재시작 (OOM, 노드 드레인) | Vault **Sealed** → 모든 시크릿 접근 차단 | 사람이 3개 키 입력할 때까지 |
| 새벽/주말 장애 | 담당자 연락 → 키 3개 수집 → 입력 | **30분~수시간** |
| Vault Agent Injector 의존 서비스 | ALBC 등 credential 갱신 중단 → NLB Target 절체 실패 | 연쇄 장애 |

> **핵심**: Kubernetes 환경에서 Pod은 언제든 재시작될 수 있다.  
> 재시작마다 **사람이 개입해야 하는** 구조는 운영에 적합하지 않다.

### 1.2 Auto-Unseal의 해결 방식

KMS Auto-Unseal은 Master Key 자체를 **AWS KMS로 암호화**하여 보관한다.  
Pod 시작 시 Vault가 자동으로 KMS API를 호출하여 Master Key를 복호화하고, **사람 개입 없이** Unseal한다.

```
기존 (Shamir):
  Pod 시작 → Sealed → 사람이 3개 키 입력 → Unsealed

Auto-Unseal (KMS):
  Pod 시작 → KMS API 호출 → Master Key 복호화 → 자동 Unsealed ✅
```

### 1.3 기존 Shamir Key의 역할 변화

| | Shamir 모드 | KMS Auto-Unseal 모드 |
|---|---|---|
| **Unseal Key 용도** | Vault 열기 (일상 운영) | ❌ 사용 안 함 |
| **Recovery Key 용도** | 없음 | Root Token 생성, KMS Key 변경 시 필요 |
| **보관 필요** | ✅ 필수 | ✅ **여전히 필수** (비상용) |

> ⚠️ **Recovery Key는 반드시 안전하게 보관해야 한다.**  
> KMS Key 분실/삭제 시 Recovery Key로만 복구할 수 있다.

---

## 2. 아키텍처

### 2.1 구성 요소

```
┌─────────────────────────────────────────────┐
│              AWS KMS                         │
│  ┌─────────────────────────────────┐        │
│  │ Key: dev-meta-vault-unseal       │        │
│  │ ID:  fcaa0e8d-2ee9-4f2e-8895-... │        │
│  │ Auto-Rotation: ✅ (365일)        │        │
│  └─────────┬───────────────────────┘        │
│            │ Encrypt / Decrypt               │
│            │                                 │
│  ┌─────────▼───────────────────────┐        │
│  │ IAM Policy: VaultKMSUnseal       │        │
│  │ Actions: kms:Encrypt             │        │
│  │          kms:Decrypt             │        │
│  │          kms:DescribeKey         │        │
│  └─────────┬───────────────────────┘        │
│            │ Attached to                     │
│            ▼                                 │
│  ┌──────────────────────────────┐           │
│  │ IAM Role: RKE2 Node Role     │           │
│  │ (EC2 Instance Profile)       │           │
│  └──────────────────────────────┘           │
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│              RKE2 Cluster                    │
│  ┌──────────────────────────────┐           │
│  │ vault-0 Pod                   │           │
│  │  ├── Config: seal "awskms"    │           │
│  │  ├── IMDS → IAM Role Creds   │           │
│  │  └── KMS API Call → Unseal    │           │
│  └──────────────────────────────┘           │
└─────────────────────────────────────────────┘
```

### 2.2 IMDS Hop Limit — Cilium ENI 환경 필수 설정

Vault Pod이 EC2 Instance Metadata Service(IMDS)를 통해 IAM 자격증명을 가져오려면,  
**`http_put_response_hop_limit ≥ 2`** 설정이 필수다.

```
문제:
  Vault Pod → veth(1 hop) → eth0(2 hop) → IMDS
  AWS 기본 hop_limit = 1 → Pod에서 IMDS 도달 불가

해결:
  hop_limit = 2 → Pod에서 IMDS 정상 접근
```

이 설정은 **Cilium ENI 모드를 사용하는 모든 클러스터에 필수**다.  
`modules/ec2-instance/main.tf`에 `metadata_options` 블록으로 코드화되어 있다.

---

## 3. 구현 상세

### 3.1 Terraform 리소스 (55-bootstrap)

| 리소스 | 설명 |
|--------|------|
| `aws_kms_key.vault_unseal` | KMS 키 (자동 rotation 365일) |
| `aws_kms_alias.vault_unseal` | Alias: `alias/dev-meta-vault-unseal` |
| `aws_iam_policy.vault_kms_unseal` | KMS Encrypt/Decrypt/DescribeKey |
| `aws_iam_role_policy_attachment.vault_kms_unseal` | Node Role에 정책 연결 |

모든 리소스는 `var.enable_vault_auto_unseal` (default: `true`)로 조건 제어된다.

### 3.2 Vault Helm Values (vault.yaml)

```hcl
# standalone config 내 seal stanza
seal "awskms" {
  region     = "ap-northeast-2"
  kms_key_id = "fcaa0e8d-2ee9-4f2e-8895-947d2bfd19e6"
}
```

### 3.3 주요 파일

| 파일 | 변경 내용 |
|------|----------|
| `stacks/dev/55-bootstrap/main.tf` | KMS Key + IAM Policy + Role Attachment |
| `stacks/dev/55-bootstrap/variables.tf` | `enable_vault_auto_unseal` 변수 |
| `stacks/dev/55-bootstrap/outputs.tf` | `vault_kms_key_id` output |
| `gitops-apps/bootstrap/vault.yaml` | `seal "awskms"` 추가 |
| `modules/ec2-instance/main.tf` | `metadata_options { hop_limit = 2 }` |

---

## 4. Seal 마이그레이션 절차

### 4.1 사전 조건

- [x] KMS Key 생성 (`make apply STACK=55-bootstrap`)
- [x] IAM Policy가 Node Role에 연결됨
- [x] vault.yaml에 `seal "awskms"` 추가 + ArgoCD 동기화
- [x] EC2 IMDS hop_limit = 2
- [x] Shamir Unseal Key 3개 확보

### 4.2 마이그레이션 실행

> ⚠️ **다운타임**: 마이그레이션 중 Vault는 Sealed 상태 (5~10분)

```bash
KC="/path/to/.kube/config"

# 1. Vault Pod 재시작 (새 config 적용)
kubectl --kubeconfig $KC -n vault delete pod vault-0

# 2. 30초 대기 후 상태 확인
sleep 30
kubectl --kubeconfig $KC -n vault exec vault-0 -- vault status
# 예상 출력:
#   Seal Type                  awskms
#   Recovery Seal Type         shamir
#   Sealed                     true
#   Seal Migration in Progress true

# 3. Unseal Key 3개로 마이그레이션 (3회 반복)
kubectl --kubeconfig $KC -n vault exec vault-0 -- \
  vault operator unseal -migrate "<UNSEAL_KEY_1>"

kubectl --kubeconfig $KC -n vault exec vault-0 -- \
  vault operator unseal -migrate "<UNSEAL_KEY_2>"

kubectl --kubeconfig $KC -n vault exec vault-0 -- \
  vault operator unseal -migrate "<UNSEAL_KEY_3>"

# 4. 완료 확인
#   Seal Type           awskms
#   Sealed              false    ← 자동 Unsealed!
```

### 4.3 자동 Unseal 검증

```bash
# Pod 재시작 → 사람 개입 없이 자동 Unseal 되는지 확인
kubectl --kubeconfig $KC -n vault delete pod vault-0
sleep 45
kubectl --kubeconfig $KC -n vault exec vault-0 -- vault status
# 예상:
#   Seal Type    awskms
#   Sealed       false  ← 수동 입력 없이 자동!
```

---

## 5. 운영 시 주의사항

### 5.1 KMS Key 관리

| 항목 | 정책 |
|------|------|
| Key Deletion | **절대 삭제 금지** — 삭제 시 Vault 데이터 복구 불가 |
| Key Rotation | 자동 (365일) — Vault는 새 키로 자동 전환 |
| Key Policy | Terraform 관리 — 수동 변경 금지 |

### 5.2 Recovery Key 보관

마이그레이션 후 기존 Shamir Key는 **Recovery Key**로 전환된다.  
아래 시나리오에서 Recovery Key가 필요하다:

- Root Token 생성 (`vault operator generate-root`)
- KMS Key Region 변경, 교체 시
- KMS 접근 불가 시 비상 복구

> **보관 위치**: 최소 3곳에 분산 보관 (예: AWS Secrets Manager, 물리 금고, 별도 KMS)

### 5.3 비상 복구 시나리오

| 시나리오 | 대응 |
|----------|------|
| KMS Key 일시 접근 불가 | Vault는 Sealed 유지 → KMS 복구 후 자동 Unseal |
| KMS Key 삭제 | Recovery Key로 `seal "shamir"` 복원 후 재마이그레이션 |
| IMDS 접근 불가 | EC2 hop_limit 확인, Pod Node 확인 |
| IAM Policy 실수 삭제 | `make apply STACK=55-bootstrap`으로 복원 |

---

## 6. 비용

| 항목 | 월 비용 |
|------|---------|
| KMS Key | **$1/월** (대칭키) |
| KMS API 호출 | ~$0.03/월 (Vault 재시작 빈도에 따라) |
| **합계** | **~$1.03/월** |

> KMS Auto-Unseal은 **월 $1**로 수동 unseal 운영 부담을 완전히 제거한다.  
> 새벽 장애 1건의 인건비 대비 압도적 ROI.

---

## 7. Phase B (Raft HA) 연계

Auto-Unseal은 **Raft HA 전환의 전제 조건**이다.

```
현재 (Phase A 완료):            Phase B (향후):
┌─────────────────┐          ┌──────────────────────────┐
│ Standalone       │   ──▶   │ Raft HA (3 Replicas)     │
│ File Storage     │          │ + Auto-Unseal 유지       │
│ Auto-Unseal ✅   │          │ + PodAntiAffinity        │
│ 1 Replica        │          │ + PDB minAvailable: 2    │
└─────────────────┘          └──────────────────────────┘
```

3-replica Raft 구성에서 각 Pod이 **독립적으로 자동 Unseal** 되어야  
노드 장애/재시작 시 클러스터가 자동 복구된다. Shamir 모드에서는 이것이 불가능하다.

---

*작성일: 2026-02-08 | KMS Key ID: fcaa0e8d-2ee9-4f2e-8895-947d2bfd19e6*  
*환경: dev (RKE2 + Cilium ENI) | Vault 1.17.2 | Helm Chart 0.28.1*
