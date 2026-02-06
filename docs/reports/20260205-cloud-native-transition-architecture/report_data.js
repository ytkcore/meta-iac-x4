const reportData = {
    title: "Unified Meta Cloud Native 전환 아키텍처 보고서",
    sections: [
        {
            id: "timeline",
            title: "1. 진화 타임라인 (The Journey)",
            description: "지난 3주간의 파편화된 인프라에서 표준화된 엔터프라이즈 플랫폼으로의 변화 여정입니다.",
            type: "mermaid",
            content: `timeline
    title Key Milestones
    section 1주차 - 기반 (Foundation)
        수동 운영 (Legacy) : AWS Client VPN (OpenVPN)
                          : 수동 EC2 생성 및 관리
                          : 로컬 Terraform State 운용
        파편화 (Fragmentation) : 보안 그룹(SG) 난립
                            : 일관성 없는 OS 설정
    section 2주차 - 표준화 (Standardization)
        골든 이미지 (Immutable) : Packer 파이프라인 구축
                              : 보안 에이전트(CrowdStrike 등) 통합
                              : OS Hardening 및 최적화
        아키텍처 (Refactoring) : 계층형 스택 구조(Layers) 정립
                            : 통합 VPC 및 서브넷 표준화
    section 3주차 - 플랫폼 (Enterprise)
        제로 트러스트 (Access) : Teleport 도입 (VPN 제거)
                            : SSO 연동 및 감사 로그
        데이터 & 레지스트리 : Harbor OCI 레지스트리 구축
                         : PostgreSQL HA (Primary-Standby)
    section 4주차 - 클라우드 네이티브 완성 (Cloud Native Complete)
        Kubernetes 전환 : RKE2 엔터프라이즈 클러스터
                       : Ingress / Cert-Manager 통합
        GitOps 파이프라인 : ArgoCD 도입 및 Sync 자동화
                         : Helm Chart 표준 패키징
        통합 관측성 (Observability) : Prometheus + Grafana 스택
                                 : Longhorn 스토리지 및 백업
    section Future - 고도화 (Next Step)
        Unified Meta Solution : 개발환경(Dev) 통합 배포
                              : Cloud Native(MSA) 전환 가속화
        운영 자동화 (Automation) : Karpenter (Node Autoscaling)
                                : Velero (Disaster Recovery)
        보안 심화 (Security) : 제로 트러스트(Zero Trust) 완성
                            : 컴플라이언스 자동화 (CSPM)`
        },
        {
            id: "architecture",
            title: "2. 현재 아키텍처 (Current Architecture)",
            description: "논리적 계층 분리와 심층 방어(Defense in Depth) 원칙이 적용된 현재의 시스템 구조입니다.",
            type: "mermaid",
            content: `C4Context
    title System Context: Enterprise Cloud Platform

    Boundary(b0, "Layer 0: 백엔드 (Foundation)", "기반 계층") {
        System(s3, "S3 Backend", "Terraform State")
        System(dynamo, "DynamoDB", "Locking")
    }

    Boundary(b1, "Layer 1: 네트워크 (Network)", "00-network") {
        System(vpc, "통합 VPC", "Multi-AZ Core")
    }

    Boundary(b2, "Layer 2: 보안 & 액세스 (Security)", "Access Plane") {
        System(teleport, "Teleport Cluster", "Unified Access")
        System(waf, "AWS WAF", "Edge Security")
    }

    Boundary(b3, "Layer 3: 플랫폼 & 관측성 (Runtime)", "Platform") {
        System(rke2, "RKE2 Enterprise", "K8s + Ext Components")
        System(harbor, "Harbor Registry", "OCI Store")
        System(db, "PostgreSQL HA", "Primary/Standby")
        System(obs, "Observability", "Prom/Grafana/Loki")
    }

    Rel(teleport, rke2, "IAM RBAC Access")
    Rel(waf, teleport, "Protects")
    Rel(rke2, harbor, "Images (Private)")
    Rel(rke2, db, "Apps Data")
    Rel(obs, rke2, "Metrics/Logs")`
        },
        {
            id: "pipeline",
            title: "3. 배포 파이프라인 (The Factory Mechanism)",
            description: "코드 커밋부터 인프라 배포, 애플리케이션 동기화까지의 완전한 GitOps 흐름입니다.",
            type: "image",
            src: "./pipeline_diagram.png",
            alt: "DevOps Deployment Pipeline",
            style: "width: 100%; border-radius: 12px; box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.3);"
        },
        {
            id: "metrics",
            title: "4. 주요 개선 지표 (Key Metrics & Solutions)",
            type: "table",
            headers: ["영역 (Area)", "Before (3주 전)", "After (현재)", "개선 효과 및 적용 솔루션 (Impact & Solution)"],
            rows: [
                {
                    area: "골든 이미지 (Golden Image)",
                    before: "Vanilla AMI + UserData 설치",
                    after: "<strong>Hardened Golden AMI</strong><br>(Packer Factory)",
                    impact: `<ul>
                                <li><strong>부팅 속도</strong>: 5분+ → <strong>90초 이내 (300%↑)</strong></li>
                                <li><strong>보안</strong>: CloudWatch Agent, SSM Agent, 보안 패치 사전 통합(Pre-baked).</li>
                                <li><strong>일관성</strong>: 모든 환경(Dev/Prod)에 동일한 불변 이미지 사용.</li>
                            </ul>`
                },
                {
                    area: "Kubernetes 플랫폼",
                    before: "단순 EC2 / 기본 K8s",
                    after: "<strong>RKE2 Enterprise</strong><br>+ Extended Components",
                    impact: `<ul>
                                <li><strong>Core</strong>: RKE2 (FIPS 준수 Hardened K8s).</li>
                                <li><strong>Network</strong>: AWS Load Balancer Controller 연동으로 유연한 라우팅.</li>
                                <li><strong>Components</strong>: Ingress, Cert-Manager, External-DNS 자동화.</li>
                            </ul>`
                },
                {
                    area: "접근 제어",
                    before: "VPN, 정적 SSH 키",
                    after: "<strong>Teleport Access Plane</strong>",
                    impact: `<ul>
                                <li><strong>Zero Trust</strong>: 영구 키 제거, 생체 인증(TouchID) 및 SSO.</li>
                                <li><strong>Audit</strong>: 모든 명령어/세션 녹화 및 실시간 감사.</li>
                            </ul>`
                }
            ]
        },
        {
            id: "summary",
            title: "5. 3주간의 주요 활동 요약 (Executive Summary)",
            description: "지난 3주간(1/29 ~ 2/4) 수행된 주요 엔지니어링 활동의 계층적 요약입니다.",
            type: "cards",
            cards: [
                {
                    type: "major",
                    title: "🏗️ Major (핵심 기반 구축)",
                    items: [
                        { title: "아키텍처 근본 개선 (Fundamental Tech Stack)", desc: "Layer 0(State)부터 Layer 4(App)까지 명확한 계층 격리.<br>순환 참조 제거 및 스택 간 의존성 체계화 (Clean Design)." },
                        { title: "Zero Trust 액세스 완성", desc: "기존 AWS Client VPN 완전 대체.<br>Teleport 도입으로 인프라 접근을 ID 기반, 감사 가능한 체계로 전환." },
                        { title: "Immutable 인프라 팩토리", desc: "Packer를 통한 골든 이미지 자동화.<br>보안 패치와 필수 에이전트가 내장된 AMI로 배포 속도 및 안정성 극대화." }
                    ]
                },
                {
                    type: "medium",
                    title: "🛠 Medium (플랫폼 확장)",
                    items: [
                        { title: "완전한 엔터프라이즈 K8s (RKE2)", desc: "단순 쿠버네티스를 넘어선 '프로덕션 플랫폼'.<br>Ingress, Cert-Manager, External-DNS 등 필수 컴포넌트 통합." },
                        { title: "데이터 주권 및 보안 (Harbor/DB)", desc: "Docker Hub 의존성 제거를 위한 Harbor 프라이빗 레지스트리.<br>PostgreSQL HA 구성을 통한 데이터 안정성 확보." },
                        { title: "Full-Stack 관측성", desc: "인프라(Metric)부터 앱(Log)까지 통합 모니터링 체계.<br>Longhorn을 활용한 영구 스토리지 관리." }
                    ]
                },
                {
                    type: "minor",
                    title: "🛡️ 보안 요건 표준화 (Security Standardization)",
                    items: [
                        { title: "운영 가드레일 (Guardrails)", desc: "스크립트 실행 시 필수 확인 절차(Confirm) 강제.<br>실수로 인한 데이터/인프라 손실 원천 차단." },
                        { title: "감사 표준 (Audit Standards)", desc: "모든 접근 및 변경 이력에 대한 로깅 표준 수립.<br>SSM, CloudTrail, Teleport 로그 통합 저장." },
                        { title: "필수 보안 에이전트 표준", desc: "골든 이미지 내 SSM, CloudWatch, 보안 에이전트 탑재 의무화.<br>배포되는 모든 인스턴스의 베이스라인 보안 수준 보장." }
                    ]
                }
            ]
        }
    ]
};
