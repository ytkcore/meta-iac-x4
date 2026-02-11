# AIPP K8s 서비스 안정화 — 프로브/리소스/API 경로 튜닝

> **Status**: ✅ 완료  
> **Priority**: Critical  
> **Labels**: `aipp`, `k8s`, `troubleshooting`, `probe`, `stabilization`  
> **작업 기간**: 2026-02-12  
> **주요 커밋**: `c5afda4`, `c923187`, `c484ef7`, `506d22e`, `cbce612`, `861fd19`

---

## 📋 요약

AIPP K8s 배포 후 발생한 서비스 불안정 문제(CrashLoopBackOff, 무한 재시작, 로그인 실패)를
진단하고 6개 근본 원인을 수정하여 전체 서비스를 안정화.
소스코드 변경 없이 **K8s manifest 설정값 튜닝만으로** 해결.

---

## 🎯 목표

1. RabbitMQ CrashLoopBackOff 해결
2. Backend 무한 재시작 해결 (startupProbe timeout)
3. AIPP 로그인 정상화
4. 전체 7개 Pod 안정 Running 확인

---

## 📂 변경 파일

| 파일 | 변경 |
|:-----|:-----|
| `gitops-apps/apps/aipp/k8s/rabbitmq.yaml` | [MOD] 메모리 512Mi→1Gi, probe `timeoutSeconds: 10` |
| `gitops-apps/apps/aipp/k8s/backend.yaml` | [MOD] TCP socket probes, startupProbe 10min, Redis cluster env vars 제거 |
| `gitops-apps/apps/aipp/k8s/frontend.yaml` | [MOD] `API_URL: ""` (상대 경로 전환) |

---

## 🔍 근본 원인 분석 (6건)

### 1. RabbitMQ 메모리 부족
- **증상**: CrashLoopBackOff, OOM kill
- **원인**: `resources.limits.memory: 512Mi` — RabbitMQ 기본 메모리 요구 초과
- **수정**: 1Gi로 증설

### 2. RabbitMQ Probe Timeout
- **증상**: `rabbitmq-diagnostics ping` 실패 → Liveness/Readiness 연속 실패 → 재시작
- **원인**: `timeoutSeconds` 미설정 (기본 1s) — RabbitMQ diagnostics 응답 지연
- **수정**: `timeoutSeconds: 10` 추가

### 3. Backend Health Endpoint 인증 차단
- **증상**: `/actuator/health` → 401, `/api/v1/health-checks` → 500
- **원인**: Spring Security가 모든 HTTP 엔드포인트를 보호 — 프로브 항상 실패
- **수정**: `tcpSocket: port 8080` 프로브로 전환 (Spring Security 우회)

### 4. Redisson 무한 DNS 루프 (Spring Boot Startup Hang)
- **증상**: Spring Boot 시작 후 Redisson DNS polling만 반복, `Started` 로그 미출력
- **원인**: `SPRING_REDIS_CLUSTER_NODES=""` (빈 문자열) → Redisson이 빈 클러스터 노드 목록 파싱 시도 → 무한 DNS resolve 루프
- **수정**: Redis cluster 관련 env vars 제거 (`application-prod.yaml`의 `cluster.enabled: false` default 사용)

### 5. Frontend API URL — 브라우저 접근 불가
- **증상**: 로그인 버튼 클릭 시 응답 없음, Mixed Content 에러
- **원인**: `NEXT_PUBLIC_API_URL: http://enai-backend:8080` — K8s 내부 서비스명으로, 외부 브라우저에서 DNS 해석 불가 + HTTPS→HTTP Mixed Content 차단
- **수정**: `API_URL: ""` → 상대 경로 `/api/v1/...` 사용, Ingress `/api` → backend 프록시 활용

### 6. Admin 비밀번호 미확인
- **증상**: 초기 admin 비밀번호 알 수 없음
- **원인**: Liquibase로 생성된 admin 유저의 비밀번호가 bcrypt 해시로만 저장
- **수정**: PostgreSQL `pgcrypto` 확장으로 `Admin1234!` bcrypt 해시 생성 후 DB 직접 UPDATE

---

## ✅ 작업 내역

- [x] **1.1** RabbitMQ 리소스 튜닝 (메모리 1Gi)
- [x] **1.2** RabbitMQ probe timeout 추가
- [x] **1.3** Backend probe → TCP socket 전환
- [x] **1.4** Backend startupProbe 10min 확장
- [x] **1.5** Redis cluster 빈 env vars 제거
- [x] **1.6** Frontend API_URL 상대 경로 전환
- [x] **1.7** Admin 비밀번호 리셋 (pgcrypto)
- [x] **1.8** 전체 서비스 안정성 검증 (5min stability check)
- [x] **1.9** 로그인 + 대시보드 접속 검증

---

## 📊 최종 상태

```
Pod                   Ready  Restarts  Uptime
enai-backend          1/1    0         24min   ✅
enai-front            1/1    0          9min   ✅
enai-data-processor   1/1    1        113min   ✅
enai-scheduler        1/1    3        113min   ✅
pgvector-0            1/1    0        111min   ✅
rabbitmq-0            1/1    0         63min   ✅
redis-0               1/1    0        134min   ✅

ArgoCD: Synced, Healthy ✅
Login: admin@en-core.com / Admin1234! ✅
```

---

## 🔗 관련 티켓

- [aipp-k8s-deployment](2026-02-11-aipp-k8s-deployment.md) — 초기 K8s 매니페스트 작성
- [harbor-image-push-debug](2026-02-11-harbor-image-push-debug.md) — Harbor 이미지 push

---

## 📝 비고

- **소스코드 변경 없음** — 전부 K8s manifest YAML 설정값 튜닝
- `data-processor`(1회)와 `scheduler`(3회)의 restart는 초기 배포 시 발생 (안정화 전)
- **교훈**: 벤더 제공 Docker Compose → K8s 전환 시 반드시 체크할 항목:
  1. 프로브 엔드포인트의 인증 여부 확인
  2. 환경변수 빈값(`""`)의 파싱 동작 검증
  3. 프론트엔드 API URL이 브라우저에서 접근 가능한지 확인
  4. 벤더 앱의 실제 startup 시간 측정 후 프로브 조정
