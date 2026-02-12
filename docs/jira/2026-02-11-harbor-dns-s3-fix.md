# Harbor DNS 정상화 + S3 IAM 정책 확장

> **Status**: ✅ 완료  
> **Priority**: Medium  
> **Labels**: `harbor`, `dns`, `s3`, `iam`, `bugfix`  
> **작업 기간**: 2026-02-11  
> **주요 커밋**: `4c97905`, `616b509`

---

## 📋 요약

Harbor 컨테이너 레지스트리의 DNS /etc/hosts 의존성을 제거하고,
S3 IAM 정책에 `tmp/*` 경로를 추가하여 multipart upload 오류를 해결.
S3 삭제 비활성화로 이미지 보존 정책을 강화.

---

## 🎯 목표

1. Harbor DNS가 /etc/hosts 없이도 정상 resolve 되도록 수정
2. S3 IAM 정책에 `tmp/*` prefix 추가 (multipart upload 지원)
3. S3 오브젝트 삭제 비활성화 (이미지 보존)

---

## 📂 변경 내역

| 커밋 | 변경 |
|:-----|:-----|
| `4c97905` | Harbor S3 IAM 정책 `tmp/*` prefix 확장 |
| `616b509` | Harbor DNS 정상화 — `/etc/hosts` 의존성 제거, S3 삭제 비활성화 |

---

## 🔍 문제 원인

1. **DNS**: Harbor가 `/etc/hosts` 엔트리에 의존하여 내부 도메인을 resolve → 호스트 재부팅/변경 시 실패
2. **S3 IAM**: Harbor의 multipart upload가 `tmp/*` prefix에 쓰기 요청 → IAM 정책에 해당 경로 미포함 → 업로드 실패
3. **S3 삭제**: 기본 정책이 삭제 허용 → 의도치 않은 이미지 손실 위험

---

## ✅ 작업 내역

- [x] **1.1** Harbor Internal DNS resolve 정상화 (Kubernetes CoreDNS 활용)
- [x] **1.2** `/etc/hosts` 의존성 제거
- [x] **2.1** S3 IAM 정책에 `tmp/*` prefix Action 추가
- [x] **3.1** S3 오브젝트 삭제 Action 비활성화

---

## 🔗 관련 티켓

- [opstart-k8s-deployment](2026-02-11-opstart-k8s-deployment.md) — Harbor 이미지 빌드/푸시 (동일 세션)
- [keycloak-admin-teleport-proxy-fix](2026-02-11-keycloak-admin-teleport-proxy-fix.md) — 동일 세션

---

## 📝 비고

- S3 삭제 비활성화 = GC(Garbage Collection) 수동 관리 필요
- `/etc/hosts` 제거 후 DNS는 Kubernetes Service DNS 또는 Route53 Private Zone 활용
