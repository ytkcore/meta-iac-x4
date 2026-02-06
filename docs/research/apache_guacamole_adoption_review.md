# Apache Guacamole 도입 전략 및 심층 분석 보고서

**문서 정보**
- **작성일**: 2026-02-05
- **주제**: Clientless ZTNA(Zero Trust Network Access) 솔루션으로서의 Apache Guacamole 전략적 검토
- **대상**: 솔루션 아키텍트, PM, 납품 담당자

---

## 1. 요약 (Executive Summary)

### 비즈니스 케이스 (The Business Case)
B2B 솔루션 납품, 특히 국내 공공/금융 및 대기업 시장 진입을 위해서는 **라이선스로부터의 자유**와 **ISMS-P 컴플라이언스 준수**가 필수불가결한 조건입니다. Teleport는 강력한 기능을 제공하지만, AGPLv3 라이선스로 인한 상용 패키징의 법적 리스크와 재판매(Resale) 시 발생하는 높은 라이선스 비용이 걸림돌이 됩니다.

**Apache Guacamole**는 이에 대한 최적의 대안입니다. **Apache 2.0 라이선스**를 따르기 때문에 소스 코드 공개 의무 없이 수정, 브랜드화(Rebranding), 상용 패키징 및 납품이 가능하며, 클라이언트 설치가 필요 없는 강력한 원격 접속 게이트웨이를 제공합니다.

### 핵심 가치 제안 (Key Value Proposition)
1.  **비용 "0" & 라이선스 자유**: 사용자 수에 따른 비용이 없으며, 상용 솔루션에 임베딩하여 납품하기에 안전합니다.
2.  **클라이언트리스(Clientless) 운영**: 최종 사용자는 별도의 에이전트나 플러그인 설치 없이 웹 브라우저만으로 접속 가능합니다.
3.  **감사(Audit) 대응 완비**: ISMS-P 필수 요건인 '세션 레코딩(녹화)' 기능을 내장하고 있습니다.
4.  **유연한 아키텍처**: "Black Box" 형태의 단일 어플라이언스로 컨테이너 패키징하여 납품 가능합니다.

---

## 2. 납품을 위한 기술 아키텍처

고객사 환경에 복잡성을 숨기고 견고한 B2B 솔루션으로 납품하기 위해 다음과 같은 아키텍처를 권장합니다.

### 2.1 구성도 (Component Diagram)

```mermaid
flowchart TD
    subgraph Customer_Network ["고객사 네트워크 (On-Prem / Cloud)"]
        User(("사용자")) -->|HTTPS (443)| LB[로드밸런서 / Nginx]
        
        subgraph Delivery_Package ["📦 납품 패키지 (Dockerized)"]
            LB -->|Proxy| Client[Guacamole Client (Tomcat/Java)]
            Client -->|Guacamole Protocol| Guacd[Guacd (Proxy Daemon)]
            Client -->|인증| DB[(PostgreSQL / MariaDB)]
            Client -.->|2FA| TOTP[TOTP 플러그인]
        end
        
        Guacd -->|SSH/RDP/VNC| Servers[대상 서버 (Linux/Windows)]
        Guacd -->|Kubectl Exec| K8s[Kubernetes 클러스터 (Bastion 경유)]
    end
```

### 2.2 핵심 컴포넌트
-   **Guacamole Client (프론트엔드)**: HTML5 웹 인터페이스입니다. 이 부분을 커스터마이징하여 로고나 CSS를 변경, 고객사 전용 솔루션처럼 보이게 만듭니다.
-   **Guacd (백엔드 프록시)**: RDP/SSH/VNC 프로토콜을 Guacamole 프로토콜(HTML5 캔버스/웹소켓)로 변환하는 핵심 엔진입니다.
-   **Database**: 접속 정보(Connection Profile), 사용자 계정, 감사 로그(접속 이력)를 저장합니다.

---

## 3. 경쟁 솔루션 비교 분석

### 3.1 vs. 기존 VPN (Legacy VPN)
| 항목 | 기존 VPN | Apache Guacamole | Guacamole 강점 |
| :--- | :--- | :--- | :--- |
| **접근 범위** | 네트워크 레벨 (L3) - 내부망 전체 스캔 위험 | 애플리케이션 레벨 (L7) - 지정된 화면만 전송 | **Guacamole** (보안성 우수) |
| **사용자 경험** | 클라이언트 설치 및 설정 필요 | 브라우저만 있으면 즉시 접속 (100% Clientless) | **Guacamole** (편의성 우수) |
| **데이터 유출** | 파일 전송/클립보드 통제 어려움 | 접속 단위로 정밀한 기능 제어 가능 | **Guacamole** |
| **감사(Audit)** | 단순 패킷 로그만 남음 | **화면 녹화** 및 텍스트 로그 저장 | **Guacamole** (ISMS-P 대응) |

### 3.2 vs. Teleport (Community Edition)
| 항목 | Teleport (Community) | Apache Guacamole | 비교 우위 |
| :--- | :--- | :--- | :--- |
| **라이선스** | **AGPLv3** (상용 납품 시 리스크 큼) | **Apache 2.0** (상용 납품 안전) | **Guacamole** |
| **프로토콜** | SSH, K8s, DB, App | RDP, SSH, VNC, Telnet, K8s(SSH경유) | **상호 보완** |
| **K8s 접근** | 네이티브 지원 (매우 강력) | 간접 접근 (SSH Bastion 경유) | Teleport |
| **Windows** | 제한적 (데스크톱 접근은 Enterprise 기능) | **네이티브 RDP 지원** (매우 강력) | **Guacamole** |

---

## 4. ISMS-P 컴플라이언스 대응 전략

국내 시장에서는 **컴플라이언스 준수** 여부가 솔루션 도입의 핵심 결정 요인입니다. Guacamole는 별도 개발 없이 주요 통제 항목을 충족합니다.

### 4.1 접근 통제 (2.5.1, 2.5.2)
-   **중앙화된 인증**: 자체 DB 인증 외에 LDAP/AD 연동을 지원하여 계정 관리를 일원화할 수 있습니다.
-   **MFA (다중 인증)**: TOTP 플러그인을 활성화하여 관리자 접근 시 "2채널 인증" 요건을 충족합니다.

### 4.2 로그 및 감사 추적 (2.6.7)
-   **식별(Identification)**: 누가(ID), 언제(Time), 어디서(IP), 무엇을 했는지 기록합니다.
-   **세션 레코딩(Session Recording)**: 가장 강력한 세일즈 포인트입니다.
    -   **그래픽 녹화**: RDP/VNC 화면을 영상처럼 다시볼 수 있습니다.
    -   **텍스트 녹화 (TypeScript)**: SSH 세션의 입력/출력 텍스트를 모두 저장하며, 검색이 가능하고 용량이 매우 작습니다.
    -   *참고: 녹화 파일은 로컬에 저장되므로, 주기적으로 S3나 Cold Storage로 백업하는 정책이 필요합니다.*

---

## 5. 배포 및 패키징 전략 (Delivery Strategy)

### 5.1 Docker Compose "Appliance" 모델
전체 스택을 하나의 `docker-compose.yml`로 구성하여 납품합니다. 현장 엔지니어의 설치 복잡도를 없애고 "설치형 어플라이언스"처럼 제공합니다.

**패키징 예시 (`docker-compose.yml`):**
```yaml
version: '3'
services:
  guacd:
    image: guacamole/guacd
  postgres:
    image: postgres:15
    volumes:
      - ./init:/docker-entrypoint-initdb.d
  guacamole:
    image: guacamole/guacamole
    environment:
      - POSTGRES_HOSTNAME=postgres
      - GUACAMOLE_HOME=/etc/guacamole
      - EXTENSIONS=auth-totp
    volumes:
      - ./branding:/etc/guacamole/extensions/branding # 커스텀 로고/CSS 적용
```

### 5.2 브랜딩 (White-labelling)
-   **Extension 시스템 활용**: `guac-manifest.json`과 CSS, 이미지 파일이 담긴 `.jar` 파일을 생성하여 기본 UI를 덮어씁니다.
-   **로그인 화면**: Apache Guacamole 로고를 고객사 로고나 제품 로고로 교체합니다.
-   **타이틀 변경**: 브라우저 탭 타이틀을 "Secure Access Gateway" 등으로 변경하여 솔루션의 정체성을 부여합니다.

---

## 6. 도입 사례 및 레퍼런스

### 6.1 글로벌 (Global)
-   **Azure Bastion**: 브라우저 기반의 RDP/SSH 접속을 위해 Guacamole와 동일한 HTML5-over-WebSocket 아키텍처를 사용합니다.
-   **Kali Linux**: 브라우저 내에서 칼리 리눅스를 구동할 때 Guacamole 기술을 사용합니다.
-   **Glyptodon**: Guacamole 원작자가 설립한 엔터프라이즈 기술 지원 회사 (현재 Keeper Security에 인수됨).

### 6.2 국내 (Domestic)
-   **보안 솔루션 (PAM/접근제어)**: 국내 주요 D사, H사 등의 접근제어 솔루션에서 '웹 터미널' 기능 구현 시 Guacamole 엔진을 커스터마이징하여 탑재하고 있습니다. (ActiveX/Plugin 제거 목적)
-   **클라우드 MSP**: 고객에게 제공하는 통합 대시보드(CMP) 내의 '서버 접속' 기능 구현에 널리 사용됩니다.

---

## 7. 결론

**Apache Guacamole는 납품형 원격 접속 솔루션을 위한 'De Facto Standard(사실상의 표준)'입니다.**

**보안(감사, 망분리 효과)**과 **편의성(웹 기반, 무설치)**이라는 두 마리 토끼를 잡을 수 있으며, Teleport의 라이선스 제약 없이 **상용 패키징이 가능한 최상의 선택지**입니다.
