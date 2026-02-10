// ============================================================
// UnifiedMeta Platform Dashboard — Interactive Logic
// ============================================================

const componentDetails = {
    users: {
        title: '👤 Users (External Traffic)',
        html: `<div class="detail-grid">
            <span class="detail-key">경로</span><span class="detail-value">Browser → WAF → NLB → Ingress → Service</span>
            <span class="detail-key">인증</span><span class="detail-value">Keycloak OIDC / Teleport MFA</span>
            <span class="detail-key">프로토콜</span><span class="detail-value">HTTPS (TLS 1.2+)</span>
        </div>`
    },
    waf: {
        title: '🛡️ AWS WAF',
        html: `<div class="detail-grid">
            <span class="detail-key">역할</span><span class="detail-value">L7 웹 애플리케이션 방화벽</span>
            <span class="detail-key">보호</span><span class="detail-value">SQL Injection, XSS, Rate Limiting</span>
            <span class="detail-key">위치</span><span class="detail-value">NLB 앞단 (ALB 연동)</span>
            <span class="detail-key">스택</span><span class="detail-value">20-waf (Terraform)</span>
        </div>`
    },
    nlb: {
        title: '⚖️ Dual NLB (Network Load Balancer)',
        html: `<div class="detail-grid">
            <span class="detail-key">아키텍처</span><span class="detail-value">Public NLB + Internal NLB</span>
            <span class="detail-key">Public</span><span class="detail-value">외부 트래픽 (사용자, API)</span>
            <span class="detail-key">Internal</span><span class="detail-value">관리 도구 (Grafana, Vault, ArgoCD)</span>
            <span class="detail-key">목적</span><span class="detail-value">Hairpin Routing 해결 + 보안 분리</span>
        </div>`
    },
    keycloak: {
        title: '🔑 Keycloak v25 — SSO / OIDC Provider',
        html: `<div class="detail-grid">
            <span class="detail-key">역할</span><span class="detail-value">중앙 인증 (Single Sign-On)</span>
            <span class="detail-key">Realm</span><span class="detail-value">platform</span>
            <span class="detail-key">OIDC Clients</span><span class="detail-value">grafana, harbor, rancher, teleport</span>
            <span class="detail-key">Hostname v2</span><span class="detail-value">KC_HOSTNAME=https://keycloak.dev.unifiedmeta.net</span>
            <span class="detail-key">DB</span><span class="detail-value">External PostgreSQL (60-postgres)</span>
        </div>`
    },
    vault: {
        title: '🔐 HashiCorp Vault — Secrets & Workload Identity',
        html: `<div class="detail-grid">
            <span class="detail-key">역할</span><span class="detail-value">시크릿 관리 + Pod IAM 자격증명</span>
            <span class="detail-key">Unseal</span><span class="detail-value">AWS KMS Auto-Unseal</span>
            <span class="detail-key">Auth</span><span class="detail-value">K8s Auth Method</span>
            <span class="detail-key">Secrets Engine</span><span class="detail-value">AWS Secrets Engine (STS)</span>
            <span class="detail-key">Injector</span><span class="detail-value">Agent Sidecar (자동 주입)</span>
        </div>`
    },
    teleport: {
        title: '🚪 Teleport v18 — Zero-Trust Access',
        html: `<div class="detail-grid">
            <span class="detail-key">역할</span><span class="detail-value">인프라 접근 게이트웨이</span>
            <span class="detail-key">지원</span><span class="detail-value">SSH, K8s API, Database, Web App</span>
            <span class="detail-key">보안</span><span class="detail-value">MFA, Session Recording, RBAC</span>
            <span class="detail-key">특징</span><span class="detail-value">VPN 없이 Zero-Trust 접근</span>
        </div>`
    },
    argocd: {
        title: '🔄 ArgoCD — GitOps Engine',
        html: `<div class="detail-grid">
            <span class="detail-key">역할</span><span class="detail-value">선언적 배포 (Git = SSOT)</span>
            <span class="detail-key">패턴</span><span class="detail-value">App-of-Apps</span>
            <span class="detail-key">앱 수</span><span class="detail-value">13+ Applications</span>
            <span class="detail-key">정책</span><span class="detail-value">selfHeal + prune 활성</span>
        </div>`
    },
    ingress: {
        title: '🌐 Nginx Ingress Controller (Dual)',
        html: `<div class="detail-grid">
            <span class="detail-key">아키텍처</span><span class="detail-value">nginx (public) + nginx-internal</span>
            <span class="detail-key">Public</span><span class="detail-value">사용자향 서비스</span>
            <span class="detail-key">Internal</span><span class="detail-value">관리 도구 (Grafana, Vault 등)</span>
            <span class="detail-key">TLS</span><span class="detail-value">cert-manager 자동 발급</span>
        </div>`
    },
    certmanager: {
        title: '📜 cert-manager — TLS 자동화',
        html: `<div class="detail-grid">
            <span class="detail-key">역할</span><span class="detail-value">Let's Encrypt TLS 인증서 자동 발급/갱신</span>
            <span class="detail-key">Challenge</span><span class="detail-value">DNS-01 (Route53)</span>
            <span class="detail-key">이유</span><span class="detail-value">Hairpin routing 회피 (Private VPC)</span>
        </div>`
    },
    harbor: {
        title: '🐳 Harbor — OCI Container Registry',
        html: `<div class="detail-grid">
            <span class="detail-key">역할</span><span class="detail-value">프라이빗 컨테이너 이미지 레지스트리</span>
            <span class="detail-key">스토리지</span><span class="detail-value">S3 백엔드</span>
            <span class="detail-key">인증</span><span class="detail-value">OIDC (Keycloak) 준비됨</span>
            <span class="detail-key">스택</span><span class="detail-value">40-harbor (Terraform)</span>
        </div>`
    },
    rancher: {
        title: '🐂 Rancher — Cluster Management',
        html: `<div class="detail-grid">
            <span class="detail-key">역할</span><span class="detail-value">K8s 클러스터 관리 UI</span>
            <span class="detail-key">기능</span><span class="detail-value">멀티클러스터, Fleet, 모니터링</span>
            <span class="detail-key">향후</span><span class="detail-value">고객 납품 시 Fleet Management 활성화</span>
        </div>`
    },
    prometheus: {
        title: '📊 Prometheus — Metrics',
        html: `<div class="detail-grid">
            <span class="detail-key">Pillar</span><span class="detail-value">Metrics (1/3)</span>
            <span class="detail-key">보존</span><span class="detail-value">15일, 20GiB</span>
            <span class="detail-key">스토리지</span><span class="detail-value">Longhorn PVC</span>
            <span class="detail-key">수집</span><span class="detail-value">ServiceMonitor 자동 발견</span>
        </div>`
    },
    loki: {
        title: '📝 Loki — Logs',
        html: `<div class="detail-grid">
            <span class="detail-key">Pillar</span><span class="detail-value">Logs (2/3)</span>
            <span class="detail-key">모드</span><span class="detail-value">SingleBinary (Monolithic)</span>
            <span class="detail-key">수집기</span><span class="detail-value">Promtail DaemonSet</span>
            <span class="detail-key">보존</span><span class="detail-value">7일</span>
            <span class="detail-key">연동</span><span class="detail-value">Grafana + Tempo trace correlation</span>
        </div>`
    },
    tempo: {
        title: '🔍 Tempo — Traces',
        html: `<div class="detail-grid">
            <span class="detail-key">Pillar</span><span class="detail-value">Traces (3/3)</span>
            <span class="detail-key">프로토콜</span><span class="detail-value">OTLP, Jaeger, Zipkin</span>
            <span class="detail-key">보존</span><span class="detail-value">7일</span>
            <span class="detail-key">연동</span><span class="detail-value">Grafana trace↔log 상관관계</span>
        </div>`
    },
    grafana: {
        title: '📈 Grafana — Unified Visualization',
        html: `<div class="detail-grid">
            <span class="detail-key">역할</span><span class="detail-value">메트릭/로그/트레이스 통합 시각화</span>
            <span class="detail-key">SSO</span><span class="detail-value">Keycloak OIDC ✅</span>
            <span class="detail-key">Datasources</span><span class="detail-value">Prometheus, Loki, Tempo</span>
            <span class="detail-key">인증</span><span class="detail-value">Sign in with Keycloak</span>
        </div>`
    },
    rke2: {
        title: '☸️ RKE2 — Kubernetes Distribution',
        html: `<div class="detail-grid">
            <span class="detail-key">버전</span><span class="detail-value">v1.31 (FIPS 호환)</span>
            <span class="detail-key">CNI</span><span class="detail-value">Canal (→ Cilium ENI 전환 예정)</span>
            <span class="detail-key">특징</span><span class="detail-value">CSP 독립, CIS 벤치마크 내장</span>
            <span class="detail-key">장점</span><span class="detail-value">멀티클라우드/온프렘 이식 가능</span>
        </div>`
    },
    longhorn: {
        title: '💾 Longhorn — Distributed Storage',
        html: `<div class="detail-grid">
            <span class="detail-key">역할</span><span class="detail-value">K8s 네이티브 분산 블록 스토리지</span>
            <span class="detail-key">백업</span><span class="detail-value">S3 (dev-meta-longhorn-backup)</span>
            <span class="detail-key">복제</span><span class="detail-value">replica 2 (가용성)</span>
            <span class="detail-key">사용처</span><span class="detail-value">Prometheus, Grafana, Loki, Vault, Tempo</span>
        </div>`
    },
    terraform: {
        title: '🏗️ Terraform — Infrastructure as Code',
        html: `<div class="detail-grid">
            <span class="detail-key">스택 수</span><span class="detail-value">14개 (00-network ~ 80-access-gateway)</span>
            <span class="detail-key">패턴</span><span class="detail-value">Modular Stacks + make wrapper</span>
            <span class="detail-key">State</span><span class="detail-value">S3 Backend + DynamoDB Lock</span>
            <span class="detail-key">원칙</span><span class="detail-value">SSOT, 선언적, Clean Plan</span>
        </div>`
    },
    packer: {
        title: '📦 Packer — Golden Image Factory',
        html: `<div class="detail-grid">
            <span class="detail-key">역할</span><span class="detail-value">사전 구성된 AMI 생성</span>
            <span class="detail-key">포함</span><span class="detail-value">RKE2, CCM, Harbor creds, SSM</span>
            <span class="detail-key">장점</span><span class="detail-value">부팅 시간 단축, 일관성 보장</span>
        </div>`
    },
    vpc: {
        title: '🏢 AWS VPC — Network Foundation',
        html: `<div class="detail-grid">
            <span class="detail-key">구조</span><span class="detail-value">Multi-AZ (3 AZ)</span>
            <span class="detail-key">서브넷</span><span class="detail-value">Public / Private / Database 계층</span>
            <span class="detail-key">NAT</span><span class="detail-value">NAT Gateway (Private 아웃바운드)</span>
        </div>`
    },
    ec2: {
        title: '🖥️ EC2 — Compute',
        html: `<div class="detail-grid">
            <span class="detail-key">타입</span><span class="detail-value">t3.large (2 vCPU, 8 GiB)</span>
            <span class="detail-key">노드</span><span class="detail-value">Server 1 + Agent 2</span>
            <span class="detail-key">AMI</span><span class="detail-value">Golden Image (Packer)</span>
        </div>`
    },
    s3: {
        title: '🪣 S3 — Object Storage',
        html: `<div class="detail-grid">
            <span class="detail-key">용도</span><span class="detail-value">Terraform State, Longhorn Backup, Harbor Storage</span>
            <span class="detail-key">버킷</span><span class="detail-value">dev-meta-longhorn-backup 등</span>
        </div>`
    },
    route53: {
        title: '🌍 Route53 — DNS',
        html: `<div class="detail-grid">
            <span class="detail-key">도메인</span><span class="detail-value">unifiedmeta.net / dev.unifiedmeta.net</span>
            <span class="detail-key">자동화</span><span class="detail-value">external-dns (Public + Private)</span>
            <span class="detail-key">Split-Horizon</span><span class="detail-value">Public + Private Hosted Zone</span>
        </div>`
    },
    kms: {
        title: '🗝️ AWS KMS — Key Management',
        html: `<div class="detail-grid">
            <span class="detail-key">용도</span><span class="detail-value">Vault Auto-Unseal</span>
            <span class="detail-key">방식</span><span class="detail-value">awskms seal (서버 재시작 시 자동)</span>
        </div>`
    }
};

function showDetail(element) {
    const id = element.dataset.id;
    const data = componentDetails[id];
    if (!data) return;

    // Remove active from all nodes
    document.querySelectorAll('.node').forEach(n => n.classList.remove('active'));
    element.classList.add('active');

    const panel = document.getElementById('detail-panel');
    document.getElementById('detail-title').textContent = data.title;
    document.getElementById('detail-body').innerHTML = data.html;
    panel.classList.add('open');

    panel.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
}

function closeDetail() {
    document.querySelectorAll('.node').forEach(n => n.classList.remove('active'));
    document.getElementById('detail-panel').classList.remove('open');
}

// Animate stat numbers on load
document.addEventListener('DOMContentLoaded', () => {
    const stats = document.querySelectorAll('.stat-number');
    stats.forEach(stat => {
        const target = parseInt(stat.textContent);
        let current = 0;
        const step = Math.ceil(target / 20);
        const interval = setInterval(() => {
            current += step;
            if (current >= target) {
                current = target;
                clearInterval(interval);
            }
            stat.textContent = current;
        }, 40);
    });
});
