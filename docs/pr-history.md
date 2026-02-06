# Pull Request History

프로젝트의 주요 PR 이력과 트러블슈팅 내용을 기록합니다.

---

## [2026-02-06] Access Control Refactoring

**Branch:** `golden-all`  
**Commit:** `e4b2742`

### 📋 Summary

Teleport 스택을 모듈화된 `15-access-control` 아키텍처로 리팩토링하고, Harbor Application Access 문제를 해결했습니다.

### 🏗️ 주요 변경사항

#### 신규 모듈
| 모듈 | 설명 |
|------|------|
| `modules/alb-public` | 재사용 가능한 Public ALB 모듈 |
| `modules/apps/teleport` | Teleport 앱 로직 (IAM, Storage, SG, Target Group) |

#### 핵심 설정 변경 (`teleport.yaml`)
```yaml
proxy_service:
  web_listen_addr: 0.0.0.0:3080      # Web UI
  tunnel_listen_addr: 0.0.0.0:3024   # Reverse Tunnel
  tunnel_public_addr: $(hostname):3024  # 내부 터널 주소

app_service:
  apps:
    - name: harbor
      uri: https://harbor.${base_domain}
      insecure_skip_verify: true
```

#### Security Group
- 포트 3024 (VPC CIDR) - Reverse Tunnel 허용
- 포트 3080 (VPC CIDR) - 내부 Web UI 허용

### 🔧 트러블슈팅 이력

#### 문제 1: DNS 해석 실패 (Split-Horizon)
| 항목 | 내용 |
|------|------|
| **증상** | Teleport 인스턴스에서 `teleport.unifiedmeta.net` 해석 불가 |
| **원인** | Private Route53 Zone에 CNAME 레코드 누락 |
| **해결** | Private Zone에 `teleport.unifiedmeta.net` → ALB CNAME 추가 |

#### 문제 2: SSL 인증서 불일치
| 항목 | 내용 |
|------|------|
| **증상** | `harbor.teleport.unifiedmeta.net` 접속 시 "Connection not private" |
| **원인** | ACM 인증서에 Wildcard SAN 누락 |
| **해결** | `subject_alternative_names = ["*.teleport.${var.base_domain}"]` 추가 |

#### 문제 3: Application Access 503 오류
| 항목 | 내용 |
|------|------|
| **증상** | Harbor 앱 접속 시 "Unable to serve application requests" |
| **원인** | ALB가 포트 443 → 3080으로 전달하며 SSH 프로토콜(Reverse Tunnel) 파손 |
| **해결** | 별도 포트 분리: Web(3080), Tunnel(3024) |

#### 문제 4: YAML 구문 오류
| 항목 | 내용 |
|------|------|
| **증상** | Teleport 서비스 시작 실패 (`mapping values are not allowed`) |
| **원인** | `sed` 명령어로 인한 들여쓰기 오류 |
| **해결** | `tunnel_listen_addr` 앞에 공백 2칸 수동 추가 |

### ✅ 검증 결과

| 항목 | 상태 |
|------|------|
| Teleport Web UI | ✅ |
| Harbor App Access | ✅ |
| `tsh login` CLI | ✅ |
| Terraform Apply | ✅ |

### 📁 변경 파일 (29 files)

**신규:**
- `modules/alb-public/` (main.tf, outputs.tf, variables.tf)
- `modules/apps/teleport/` (main.tf, outputs.tf, user-data.sh, variables.tf)
- `stacks/dev/15-access-control/` (main.tf, outputs.tf, variables.tf, versions.tf)
- `docs/access-control/teleport-user-guide.md`
- `docs/research/apache_guacamole_adoption_review.md`
- `docs/reports/20260205-cloud-native-transition-architecture/`

**수정:**
- `docs/access-control/README.md`
- `makefiles/config.mk`
- `modules/teleport-ec2/` (main.tf, user-data.sh)
- `scripts/terraform/post-apply-hook.sh`
- `stacks/dev/15-teleport/`, `55-bootstrap/`, `60-db/`

---

<!-- 
템플릿:
## [YYYY-MM-DD] PR Title

**Branch:** `branch-name`  
**Commit:** `hash`

### 📋 Summary
### 🏗️ 주요 변경사항
### 🔧 트러블슈팅 이력
### ✅ 검증 결과
### 📁 변경 파일
-->
