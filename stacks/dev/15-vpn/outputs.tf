#------------------------------------------------------------------------------
# VPN Outputs
#------------------------------------------------------------------------------

output "vpn_endpoint_id" {
  description = "Client VPN Endpoint ID"
  value       = aws_ec2_client_vpn_endpoint.main.id
}

output "vpn_endpoint_dns_name" {
  description = "VPN Endpoint DNS Name (클라이언트 연결용)"
  value       = aws_ec2_client_vpn_endpoint.main.dns_name
}

output "vpn_security_group_id" {
  description = "VPN Endpoint Security Group ID"
  value       = aws_security_group.vpn.id
}

output "vpn_client_cidr" {
  description = "VPN Client CIDR Block"
  value       = var.vpn_cidr_block
}

output "vpn_log_group_name" {
  description = "CloudWatch Log Group for VPN connections"
  value       = aws_cloudwatch_log_group.vpn.name
}

# 인증서 파일 경로
output "client_key_path" {
  description = "Client private key file path"
  value       = local_file.client_key.filename
}

output "client_cert_path" {
  description = "Client certificate file path"
  value       = local_file.client_cert.filename
}

output "ca_cert_path" {
  description = "CA certificate file path"
  value       = local_file.ca_cert.filename
}

# 클라이언트 설정 파일 다운로드 안내
output "vpn_client_config_command" {
  description = "VPN 클라이언트 설정 파일 다운로드 명령어"
  value       = <<-EOT
    
    # VPN 클라이언트 설정 파일 다운로드:
    aws ec2 export-client-vpn-client-configuration \
      --client-vpn-endpoint-id ${aws_ec2_client_vpn_endpoint.main.id} \
      --output text > vpn-config.ovpn
    
    # 인증서 추가 (ovpn 파일 끝에 추가):
    echo '<cert>' >> vpn-config.ovpn
    cat ${local_file.client_cert.filename} >> vpn-config.ovpn
    echo '</cert>' >> vpn-config.ovpn
    echo '<key>' >> vpn-config.ovpn
    cat ${local_file.client_key.filename} >> vpn-config.ovpn
    echo '</key>' >> vpn-config.ovpn
    
    # OpenVPN 또는 AWS VPN Client로 vpn-config.ovpn 파일 import
  EOT
}

# 연동 가이드
output "usage_guide" {
  description = "VPN 사용 가이드"
  value       = <<-EOT
    
    ========================================
    AWS Client VPN 연결 가이드
    ========================================
    
    1. AWS VPN Client 설치:
       - macOS: https://aws.amazon.com/vpn/client-vpn-download/
       - Windows: https://aws.amazon.com/vpn/client-vpn-download/
    
    2. 설정 파일 준비:
       cd ${path.module}
       ./generate-ovpn.sh  # 또는 위 명령어 실행
    
    3. AWS VPN Client에서 File > Manage Profiles > Add Profile
       생성된 vpn-config.ovpn 파일 선택
    
    4. Connect 클릭
    
    5. 연결 확인:
       - Private IP로 ArgoCD, Rancher 등 접속 가능
       - kubectl 명령어 정상 동작
    
    ========================================
  EOT
}
