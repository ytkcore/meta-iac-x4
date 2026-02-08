# [INFRA] 웹서비스 온보딩 표준 절차 수립

## 📋 Summary

RKE2 클러스터에 새로운 고객 대상 웹서비스를 추가할 때의 표준 절차를 정의한다.
Public NLB를 통한 외부 접근과 Internal NLB를 통한 내부 관리 접근 모두를 포함한다.

## 🎯 Goals

1. 웹서비스 추가 시 체크리스트 표준화
2. CCM bug 환경과 ALBC 환경 각각의 절차 문서화
3. 서비스 배포부터 DNS 등록까지 E2E 가이드 제공

## 📋 Tasks

- [ ] **1** 웹서비스 온보딩 가이드 작성 (`docs/guides/web-service-onboarding.md`)
- [ ] **2** ArgoCD Application 템플릿 제공
- [ ] **3** Ingress 템플릿 제공 (TLS, annotation 포함)
- [ ] **4** 서비스 추가 시 80-access-gateway 연동 절차 문서화
- [ ] **5** 검증 체크리스트 제공

## 📎 References

- [NLB 아키텍처](../architecture/nlb-architecture.md)
- [DNS 전략](../architecture/dns-strategy.md)
- [Teleport App Access 트러블슈팅](../troubleshooting/teleport-app-access-internal-nlb.md)
