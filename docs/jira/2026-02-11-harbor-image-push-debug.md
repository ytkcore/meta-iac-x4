# Harbor 대용량 이미지 Push 디버깅 — /tmp tmpfs 제한

> **Status**: ✅ 완료  
> **Priority**: Medium  
> **Labels**: `harbor`, `docker`, `ssm`, `ec2`, `bugfix`  
> **작업 기간**: 2026-02-11  
> **관련 대화**: `097ab85c-c66e-4b04-86c5-e8373e582a8b`

---

## 📋 요약

`make harbor-push`로 AIPP/linker 이미지(25.7GB tar)를 Harbor에 푸시 시
EC2의 `/tmp` tmpfs 용량 초과로 실패. 디스크 기반 임시 디렉토리(`/var/tmp`)로 
전환하고 SSM 타임아웃을 확장하여 해결.

---

## 🎯 목표

1. 대용량 Docker 이미지의 Harbor push 성공
2. /tmp tmpfs 한계 우회 (디스크 기반 임시 디렉토리)
3. SSM 타임아웃 대용량 전송 대응

---

## 🔍 문제 원인

```
Docker save → /tmp/image.tar (25.7GB)
                  ↓
/tmp는 tmpfs (RAM 기반) → 메모리 부족 → 실패
```

- EC2의 `/tmp`는 tmpfs로 마운트되어 RAM 용량에 의존
- 25.7GB tar 파일이 tmpfs 한계 초과
- SSM 명령 기본 타임아웃(300초)으로는 대용량 전송 시간 부족

---

## ✅ 작업 내역

- [x] **1.1** 근본 원인 분석 — `/tmp` tmpfs vs 디스크 공간
- [x] **1.2** 임시 디렉토리를 `/var/tmp` (디스크 기반)으로 변경
- [x] **1.3** SSM 타임아웃 300s → 900s 확장
- [x] **1.4** sleep 간격 5s → 10s 조정
- [x] **1.5** Harbor push 성공 확인

---

## 📂 변경 파일

| 파일 | 변경 |
|:-----|:-----|
| `makefiles/ssm.mk` | [MOD] SSM 타임아웃 900s, /var/tmp 사용, sleep 10s |

---

## 🔗 관련 티켓

- [aipp-k8s-deployment](2026-02-11-aipp-k8s-deployment.md) — AIPP 이미지 빌드/배포
- [opstart-k8s-deployment](2026-02-11-opstart-k8s-deployment.md) — 유사 빌드 패턴

---

## 📝 비고

- EC2 인스턴스 타입에 따라 tmpfs 크기가 다름 — 대용량 처리 시 항상 `/var/tmp` 권장
- SSM 타임아웃은 이미지 크기에 비례하여 조정 필요
- 향후 Harbor Proxy Cache 활용 시 직접 push 빈도 감소 예상
