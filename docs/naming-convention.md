# AWS 리소스 네이밍 컨벤션 표준 (Naming Convention Standards)

AWS 리소스의 **가독성**, **검색 용이성**, **운영 효율성**을 위한 네이밍 컨벤션 표준입니다. 모든 Terraform 모듈 및 리소스 생성 시 본 가이드를 준수합니다.

---

## 1. 기본 원칙 (Naming Strategy)

리소스 이름은 **워크로드(Workload) 중심**으로 구성하여, **특정 서비스와 관련된 모든 리소스를 한눈에 파악**할 수 있도록 합니다.

*   **포맷**: {env}-{project}-{workload}-{resource}-{suffix}
*   **예시**: dev-meta-harbor-alb, prod-meta-rke2-cp-01

| 구성 요소 | 설명 | 예시 |
| :--- | :--- | :--- |
| **env** | 환경 (dev, stg, prod) | dev |
| **project** | 프로젝트명 | meta |
| **workload** | 서비스 또는 워크로드 이름 | harbor, rke2, vpc |
| **resource** | 리소스 종류 (약어 사용) | ec2, sg, alb |
| **suffix** | 추가 식별자 (선택) | 01, pub, priv |

---

## 2. 리소스별 약어 표준 (Abbreviations)

| 카테고리 | 리소스 | 약어 | 적용 예시 |
| :--- | :--- | :--- | :--- |
| **Network** | VPC | vpc | dev-meta-vpc |
| | Subnet | snet | dev-meta-snet-pub-a |
| | Internet Gateway | igw | dev-meta-igw |
| | NAT Gateway | ngw | dev-meta-ngw-a |
| | Route Table | rt | dev-meta-rt-pub |
| **Compute** | EC2 Instance | ec2 | dev-meta-harbor-ec2 |
| | Auto Scaling Group | asg | dev-meta-rke2-asg |
| **Security** | Security Group | sg | dev-meta-harbor-sg |
| | IAM Role | role | dev-meta-rke2-role |
| **Load Balancer** | App Load Balancer | alb | dev-meta-harbor-alb |
| | Network Load Balancer | nlb | dev-meta-rke2-nlb |
| | Target Group | tg | dev-meta-harbor-tg-80 |
| **Storage** | S3 Bucket | s3 | dev-meta-harbor-s3 |
| | EBS Volume | ebs | (자동생성됨) |

---

## 3. 적용 시뮬레이션

### Case A: Harbor (단일 EC2 + ALB)

*   **EC2**: dev-meta-harbor-ec2
*   **ALB**: dev-meta-harbor-alb
*   **Target Group**: dev-meta-harbor-tg-80
*   **Security Group**: dev-meta-harbor-sg

### Case B: RKE2 Cluster (다중 노드 + NLB)

*   **Control Plane**: dev-meta-rke2-cp-01
*   **Worker Node**: dev-meta-rke2-worker-01
*   **NLB (Server)**: dev-meta-rke2-nlb-server
*   **Security Group**: dev-meta-rke2-common-sg

---

## 4. 기대 효과

1.  **가독성 향상**: AWS 콘솔에서 이름순 정렬 시, 같은 서비스의 리소스가 그룹핑되어 보임.
2.  **검색 편의성**: "harbor"로 검색 시 EC2, SG, ALB가 모두 검색됨.
3.  **자동화 용이**: 일관된 규칙으로 Terraform 코드 템플릿화 및 태깅 자동화 유리.
