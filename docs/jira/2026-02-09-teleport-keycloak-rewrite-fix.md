# [INFRA] Teleport keycloak-admin App Access rewrite.redirect 수정

## 📋 Summary

Teleport App Access에서 keycloak-admin 앱 Launch 시 **404 nginx** 발생.
Keycloak의 302 리다이렉트가 Teleport 프록시 밖으로 이탈하면서
Public Ingress에 `/admin` 경로가 없어 404 반환.
`rewrite.redirect` 설정을 추가하여 리다이렉트 URL이 Teleport 프록시 내에 유지되도록 수정.

## 🎯 Root Cause

```
1. Browser → keycloak-admin.teleport.unifiedmeta.net
2. Teleport → Internal NLB → Nginx → Keycloak
3. Keycloak → 302 Location: https://keycloak.dev.unifiedmeta.net/admin/master/console/
4. Browser → keycloak.dev.unifiedmeta.net/admin/ (Public Ingress)
5. Public Ingress: /admin 경로 없음 → 404 nginx
```

`rewrite.redirect`가 있으면 Teleport가 Location header의 `keycloak.dev.unifiedmeta.net`을
`keycloak-admin.teleport.unifiedmeta.net`으로 rewrite하여 프록시 내 유지.

## 📋 Tasks

- [x] **1.1** 진단: 다른 Teleport 앱 정상, keycloak-admin만 404
- [x] **1.2** Teleport EC2 → Keycloak 직접 curl 정상(302) 확인
- [x] **1.3** `/etc/teleport.yaml`에 `rewrite.redirect` 추가
- [x] **1.4** Teleport 서비스 재시작 → 정상 접근 확인

## 🔧 변경 내용

```yaml
# /etc/teleport.yaml (Teleport EC2)
- name: keycloak-admin
  uri: https://keycloak.dev.unifiedmeta.net
  insecure_skip_verify: true
  rewrite:                                    # ← 추가
    redirect:                                 # ← 추가
      - keycloak.dev.unifiedmeta.net          # ← 추가
```

## ⚠️ 후속 과제

- `modules/teleport-ec2/user-data.sh` 템플릿에 `rewrite` 렌더링 로직 미구현
- 현재 keycloak-admin은 수동 추가 상태 → Terraform 코드화 필요
- `80-access-gateway/variables.tf`의 `rewrite_redirect` 필드가 user-data 템플릿에 반영 안 됨

## 🔗 Dependencies

- `2026-02-07-access-gateway-stack.md` — Teleport Access Gateway 스택
- `2026-02-09-keycloak-k8s-native-deployment.md` — Keycloak K8s 전환

## 🏷️ Labels

`teleport`, `app-access`, `keycloak`, `bugfix`

## 📌 Priority / Status

**High** | ✅ **Done**
