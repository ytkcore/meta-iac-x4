# OpStart 서비스 K8s 배포 + CLI 자동화

> **Status**: ✅ 완료  
> **Priority**: High  
> **Labels**: `opstart`, `terraform`, `ssm`, `harbor`, `k8s-deployment`  
> **작업 기간**: 2026-02-11  
> **주요 커밋**: `2d2bd97`, `0ce9e9a`, `f9d8083`, `dc6ecb7`, `5abaf17`, `d98d3b5`

---

## 📋 요약

OpStart 서비스를 K8s Pod으로 배포하고, CLI 6단계 자동화 파이프라인을 구축.
Harbor 컨테이너 레지스트리에 이미지 빌드/푸시하고 Terraform으로 인프라를 통합 관리.
SSM 기반 EC2 원격 빌드 → Harbor Push → K8s Deployment 자동화 완성.

---

## 🎯 목표

1. OpStart K8s Pod 배포 (Deployment + Service + Ingress)
2. CLI 6단계 자동화 (build → push → deploy → verify)
3. Terraform 스택에 K8s 리소스 통합
4. Harbor docker login + SSM 기반 EC2 이미지 빌드
5. 빌드 스크립트 외부 분리 (유지보수성)

---

## 📂 변경 내역 (커밋 순서)

| 커밋 | 변경 |
|:-----|:-----|
| `2d2bd97` | K8s Pod 배포 + CLI 6단계 자동화 + Terraform 스택 통합 |
| `0ce9e9a` | Ingress, Teleport URI, null_resource 조건 수정 |
| `f9d8083` | SSM 기반 Harbor EC2 이미지 빌드 |
| `dc6ecb7` | 빌드 스크립트 외부 분리 (Harbor 패턴) |
| `5abaf17` | Harbor docker login 추가 외 |
| `d98d3b5` | Harbor 이미지 주소 수정 |

---

## ✅ 작업 내역

- [x] **1.1** OpStart K8s Deployment + Service + Ingress 작성
- [x] **1.2** Terraform 스택에 K8s 리소스 통합
- [x] **2.1** CLI 6단계 자동화 파이프라인 구현
- [x] **2.2** SSM 기반 EC2 원격 이미지 빌드
- [x] **2.3** Harbor docker login 자동화
- [x] **3.1** 빌드 스크립트 외부 분리 (유지보수성 개선)
- [x] **3.2** Ingress + Teleport URI 수정
- [x] **3.3** null_resource 조건 수정
- [x] **3.4** Harbor 이미지 주소 수정 (최종)

---

## 🔗 관련 티켓

- [harbor-dns-s3-fix](2026-02-11-harbor-dns-s3-fix.md) — Harbor 인프라 수정 (동일 세션)
- [keycloak-admin-teleport-proxy-fix](2026-02-11-keycloak-admin-teleport-proxy-fix.md) — Keycloak 수정 (동일 세션)
- [customer-services-deployment](2026-02-10-customer-services-deployment.md) — 유사 배포 패턴

---

## 📝 비고

- 이미지 빌드: EC2에서 SSM으로 원격 빌드 → Harbor push
- Harbor 패턴: 빌드 스크립트 외부 분리로 Makefile/Terraform 복잡도 감소
- Teleport URI 등록으로 OpStart 서비스도 Teleport App Access 대상
