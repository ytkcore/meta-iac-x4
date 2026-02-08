# [INFRA] AWS CCM 통합 + Observability 스택 구축

## 📋 Summary

RKE2 클러스터에 **AWS Cloud Controller Manager(CCM)**를 통합하여 NLB 자동 프로비저닝을 구현하고,
**70-observability 스택**을 신설하여 Longhorn(분산 스토리지) + Prometheus/Grafana(모니터링)를 배포한다.

## 🎯 Goals

1. **CCM 통합**: LoadBalancer Service 생성 시 NLB 자동 프로비저닝
2. **Taint 자동 제거**: `node.cloudprovider.kubernetes.io/uninitialized` 자동 해소
3. **Longhorn**: CSP 독립 분산 스토리지, S3 백업 자동화
4. **Monitoring**: Prometheus + Grafana 중앙 메트릭 대시보드

## 📊 배포 구조

```
70-observability (Terraform)
├── S3 Bucket (Longhorn backup)
├── IAM Role (Longhorn backup 용)
└── ArgoCD Apps trigger

gitops-apps/bootstrap/
├── longhorn.yaml          → Longhorn CSI + UI
├── monitoring.yaml        → Prometheus + Grafana + Alertmanager
└── aws-cloud-controller-manager.yaml → CCM DaemonSet
```

## 📋 Tasks (완료)

### AWS CCM 통합
- [x] `enable_aws_ccm` 변수 추가 (modules/rke2-cluster)
- [x] EC2 인스턴스에 `kubernetes.io/cluster/<name>=owned` 태그 추가
- [x] server/agent userdata에 `provider-id` 자동 주입
- [x] CCM ArgoCD App 생성
- [x] CCM Leader Election 확인 + NLB 자동 생성 검증

### Observability 스택
- [x] `70-observability` 스택 신설 (S3 + IAM)
- [x] Longhorn ArgoCD App → bootstrap 폴더로 이동
- [x] Monitoring ArgoCD App → bootstrap 폴더로 이동
- [x] Longhorn PVC 프로비저닝 확인
- [x] Grafana/Prometheus 접근 확인

## 🔧 주요 변경 파일

| 파일 | 작업 |
|------|------|
| `modules/rke2-cluster/variables.tf` | ✏️ `enable_aws_ccm`, `disable_ingress` |
| `modules/rke2-cluster/main.tf` | ✏️ 클러스터 태그 추가 |
| `modules/rke2-cluster/templates/rke2-server-userdata.sh.tftpl` | ✏️ provider-id, CCM 매니페스트 |
| `stacks/dev/70-observability/` | 🆕 스택 생성 (S3, IAM) |
| `gitops-apps/bootstrap/longhorn.yaml` | ✏️ bootstrap으로 이동 |
| `gitops-apps/bootstrap/monitoring.yaml` | ✏️ bootstrap으로 이동 |

## 📊 검증 결과

| 항목 | 상태 |
|------|------|
| 노드 Ready (CP3+W4) | ✅ |
| CCM Taint 자동 제거 | ✅ |
| NLB 자동 프로비저닝 | ✅ |
| Longhorn CSI | ✅ |
| Grafana 접근 | ✅ (`grafana.unifiedmeta.net`) |
| DB Egress VPC 한정 | ✅ |

## ⚠️ 알려진 제약

- CCM이 NLB **Target Group에 Worker를 자동 등록하지 못하는** 버그 발견
- 별도 티켓: [NLB Target 수동 등록 자동화](2026-02-07-nlb-target-automation.md)

## 📎 References

- [07-cloud-provider-migration-report.md](../architecture/07-cloud-provider-migration-report.md)
- [06-rke2-optimization-guide.md](../architecture/06-rke2-optimization-guide.md)
- [PR: golden2 → main](../pr-golden2-to-main.md)

## 🏷️ Labels

`ccm`, `observability`, `longhorn`, `grafana`, `prometheus`

## 📌 Priority / Status

**High** / ✅ 완료 (2026-02-02~03)
