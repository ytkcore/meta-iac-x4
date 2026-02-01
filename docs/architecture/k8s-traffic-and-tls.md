# Kubernetes Internal Traffic & AWS ACM Architecture Research

## 개요
이 문서는 AWS Private DNS + Internal Load Balancer(ACM) 구성이 Kubernetes 내부 통신(Pod-to-Pod)에 미치는 영향과 한계, 그리고 `cert-manager`가 여전히 필요한 이유를 정리합니다.

## 핵심 질문
> "AWS Private DNS + Internal ACM으로 구성된 로드밸런서를 사용하면, Pod 간 통신도 이 경로를 타고 암호화(SSL)가 처리되는가? 그렇다면 `cert-manager` 없이도 내부 보안이 해결되는가?"

## 결론 요약
**아니요.** Pod 간 직접 통신(East-West Traffic)은 AWS 로드밸런서를 거치지 않으므로, AWS ACM의 효용이 없습니다. 따라서 내부 통신 암호화나 Webhook 동작을 위해서는 클러스터 내부의 **`cert-manager`가 필수적**입니다.

---

## 상세 분석

### 1. 트래픽 흐름 비교

#### A. North-South Traffic (외부/VPC -> Pod)
클러스터 외부(VPN, Bastion, 타 EC2)에서 K8s 서비스로 접근할 때 발생하는 트래픽입니다.
- **경로**: Client -> **AWS Internal LB (ACM SSL Offloading)** -> Ingress Controller -> Pod
- **AWS ACM 역할**: **유효함.** 클라이언트와 LB 구간을 효과적으로 암호화합니다.
- **용도**: 관리자 접속, 내부 시스템 연동 등.

#### B. East-West Traffic (Pod -> Pod)
K8s 클러스터 내부에서 Pod가 다른 서비스(Pod)를 호출할 때 발생하는 트래픽입니다.
- **경로**: Pod A -> CoreDNS (Service IP 조회) -> **Kube-Proxy (Iptables/IPVS)** -> Pod B
- **특징**: 트래픽이 Node 레벨에서 바로 라우팅되며, AWS 로드밸런서로 나갔다 들어오지 않습니다. (Hairpinning 방지 및 성능 최적화)
- **AWS ACM 역할**: **무효함.** 트래픽이 ACM이 장착된 LB를 통과하지 않으므로 암호화를 적용할 수 없습니다.

### 2. Cert-Manager가 여전히 필요한 이유

AWS ACM이 있음에도 불구하고, 다음과 같은 **Cluster 내부 보안 요구사항** 때문에 `cert-manager`는 필수적인 인프라 요소입니다.

1.  **Validating/Mutating Webhooks**:
    *   Rancher, ArgoCD, OPA Gatekeeper 등은 K8s API 서버가 자신들의 Webhook을 호출할 때 **HTTPS(TLS)**를 요구합니다.
    *   이 통신은 클러스터 내부에서 일어나므로 AWS ACM을 사용할 수 없습니다.
    *   `cert-manager`가 CA(Self-signed) 역할을 하여 내부 인증서를 발급/갱신해 줍니다.

2.  **Service Mesh (mTLS)**:
    *   Pod 간 통신을 암호화해야 하는 경우 (Zero Trust), 각 Pod에 Sidecar를 붙여 인증서를 발급해야 합니다.
    *   이 영역 역시 AWS ACM이 접근할 수 없는 영역입니다.

### 3. 권장 아키텍처 (Hybrid Approach)

| 통신 유형 | 권장 솔루션 | 설명 |
| :--- | :--- | :--- |
| **Ingress (사용자 접속)** | **AWS ACM** | 관리 편의성 높음. LB 단에서 SSL 종료(Offloading). |
| **Internal (Webhook/mTLS)** | **cert-manager** | 클러스터 내부 통신용 사설 인증서 자동 관리. |

따라서 **"외부 노출용은 AWS ACM, 내부 통신용은 Cert-Manager"**로 역할을 분담하여 구성하는 것이 표준적이고 안정적인 아키텍처입니다.
