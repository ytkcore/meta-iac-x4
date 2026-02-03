# Terraform 의존성 모델 정리 (네트워크 스택 기준)

## 결론
- **기본은 Terraform의 “참조 기반(implicit) 의존성”** 에 맡기는 것이 가장 안전하고 유지보수 비용이 낮습니다.
- **`depends_on`는 “예외적으로”**: AWS의 eventually-consistent / 타이밍 이슈로 실제 운영에서 흔들리는 지점에만 **핀포인트로** 사용합니다.
- 실행 순서를 “명시적으로 강제”하고 싶다면, 코드에 `depends_on` 체인을 늘리기보다
  - `terraform graph`로 의존성 시각화(그래프) 또는
  - Makefile/스택 분리(00-network → 10-security → …)로 “운영 순서”를 고정하는 방식이 더 견고합니다.

## 왜 `depends_on` 체인을 넓게 쓰면 위험한가?
- 인프라가 커질수록 `depends_on`가 그래프를 과하게 직렬화(serialization)하여 **plan/apply 시간이 증가**
- 리팩토링/확장 시 “의존성 체인”을 계속 갱신해야 해서 **운영 비용 증가**
- Terraform이 이미 추론 가능한 의존성까지 강제하면, 오히려 **불필요한 재생성/순서 제약**이 생깁니다.

## 우리가 네트워크에서 실제로 권장하는 방식
1. **모듈/리소스 간 참조를 명확히**
   - 예: `routing`이 `vpc_id`, `igw_id`, `nat_gateway_id_by_az` 등을 입력으로 받게 하여, Terraform 그래프가 자동으로 순서를 잡도록 함
2. **스택을 기반→확장 순서로 분리**
   - `00-network` → `10-security` → `20-endpoints` → `30-db` → `30-bastion
40-harbor`
3. **시각화/리뷰로 “순서 예측 가능성” 확보**
   - `make graph`, `make plan-json` 활용
4. 정말 필요할 때만 `depends_on`
   - 예: AWS에서 특정 리소스 생성 직후 “즉시 참조”가 흔들릴 때(실제 운영에서 재현되는 경우에 한함)

## 참고 커맨드
```bash
aws-vault exec <profile> -- make graph ENV=dev STACK=00-network
aws-vault exec <profile> -- make plan-json ENV=dev STACK=00-network
```
