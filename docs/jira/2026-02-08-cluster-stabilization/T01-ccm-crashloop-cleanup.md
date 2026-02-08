# T1: CCM CrashLoopBackOff 정리

> **Parent**: [클러스터 안정화](../2026-02-08-cluster-stabilization.md) | **Status**: ✅ 완료

## 📋 Summary

Cilium CNI로 전환 후 더 이상 필요 없는 AWS Cloud Controller Manager(CCM)가 CrashLoopBackOff 상태로 남아 있어 클러스터 로그를 오염시키는 문제를 정리.

## 🔍 문제

RKE2가 기본 설치하는 CCM(HelmChart CR `aws-cloud-controller-manager`)이 Cilium ENI 모드 전환 후에도 잔존.
CCM Pod가 시작 시 AWS credentials/metadata에 접근하려다 실패 → CrashLoopBackOff 반복.

```
NAME                                    READY   STATUS             RESTARTS
aws-cloud-controller-manager-xxxxx      0/1     CrashLoopBackOff   147
```

## 🔧 해결 과정

### Step 1: HelmChart CR 삭제
```bash
kubectl delete helmchart aws-cloud-controller-manager -n kube-system
# helm.cattle.io/v1 HelmChart — RKE2가 자동 생성한 CCM Helm release
```

### Step 2: Addon 삭제
```bash
kubectl delete addon aws-ccm -n kube-system
# k3s.cattle.io/v1 Addon — RKE2 addon controller가 관리하는 CCM 컴포넌트
```

### Step 3: CrashLoop Pod 강제 삭제
```bash
kubectl delete pod -n kube-system -l app=aws-cloud-controller-manager --force --grace-period=0
```

### Step 4: 서버 매니페스트 영구 비활성화
CCM이 CP 노드 재시작 시 RKE2에 의해 자동 재생성되는 것을 방지하기 위해, 3대 CP 노드 모두에서 서버 매니페스트를 `.disabled` 확장자로 변경:

```bash
# SSM을 통해 각 CP 노드에서 실행
mv /var/lib/rancher/rke2/server/manifests/aws-cloud-controller-manager.yaml \
   /var/lib/rancher/rke2/server/manifests/aws-cloud-controller-manager.yaml.disabled
```

| 노드 | IP | 결과 |
|------|-----|------|
| CP-1 (init) | 10.0.1.x | ✅ `.disabled` |
| CP-2 | 10.0.2.x | ✅ `.disabled` |
| CP-3 | 10.0.3.x | ✅ `.disabled` |

## ✅ 검증

- CrashLoopBackOff Pod 완전 제거
- HelmChart CR / Addon 잔존 없음
- `kube-system` 정상 상태 확인

## 💡 배경

Cilium ENI 모드에서는 CCM이 불필요:
- **노드 라벨/taint**: Cilium이 직접 관리
- **NLB 관리**: ALBC가 대체 (TargetGroupBinding)
- **라우팅**: ENI mode에서 VPC-native Pod IP 사용

## 🔧 변경 파일

| 파일 | 변경 |
|------|------|
| K8s CRs | HelmChart, Addon 삭제 (runtime) |
| 서버 매니페스트 | `.disabled` (SSM, 3 CP 노드) |

## 🏷️ Labels
`ccm`, `cleanup`, `cilium`, `rke2`
