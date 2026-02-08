# =============================================================================
# Teleport Access Gateway Module - Main
# =============================================================================
# 
# 이 모듈은 서비스 목록을 받아 Teleport App Service에 등록합니다.
# SSM을 통해 Teleport 서버에 앱 설정을 적용합니다.
# =============================================================================

locals {
  # internal = true인 서비스만 필터링
  internal_services = [for s in var.services : s if s != null && s.internal == true]

  # Teleport 앱 설정 생성
  teleport_apps_config = [
    for svc in local.internal_services : {
      name                 = svc.name
      uri                  = svc.uri
      public_addr          = "${svc.name}.teleport.${var.teleport_server.domain}"
      insecure_skip_verify = var.insecure_skip_verify
      labels = {
        env  = "dev"
        type = svc.type
      }
    }
  ]

  # teleport.yaml apps 섹션 생성
  apps_yaml = yamlencode({
    apps = local.teleport_apps_config
  })
}

# Teleport 앱 설정 파일 생성 및 서비스 재시작
resource "null_resource" "configure_teleport_apps" {
  count = length(local.internal_services) > 0 ? 1 : 0

  triggers = {
    apps_config_hash = md5(local.apps_yaml)
    services_count   = length(local.internal_services)
  }

  provisioner "local-exec" {
    command = <<-EOT
      # Teleport 앱 설정을 SSM Parameter Store에 저장
      aws ssm put-parameter \
        --name "/teleport/${var.teleport_server.domain}/apps-config" \
        --value '${replace(local.apps_yaml, "'", "\\'")}' \
        --type "String" \
        --overwrite \
        --region ${var.region}

      # Teleport 서버에 설정 적용 명령 전송
      # teleport.yaml의 app_service 섹션을 직접 업데이트
      aws ssm send-command \
        --instance-ids "${var.teleport_server.instance_id}" \
        --document-name "AWS-RunShellScript" \
        --parameters 'commands=[
          "#!/bin/bash",
          "set -e",
          "echo \"Updating Teleport app configuration...\"",
          "aws ssm get-parameter --name /teleport/${var.teleport_server.domain}/apps-config --query Parameter.Value --output text > /tmp/apps-config.yaml",
          "sudo cp /tmp/apps-config.yaml /etc/teleport/apps.yaml",
          "sudo chown teleport:teleport /etc/teleport/apps.yaml",
          "sudo python3 -c \"",
          "import yaml, sys",
          "with open(\"/etc/teleport.yaml\") as f: conf = yaml.safe_load(f)",
          "with open(\"/etc/teleport/apps.yaml\") as f: apps = yaml.safe_load(f)",
          "conf[\"app_service\"] = {\"enabled\": \"yes\", \"apps\": apps.get(\"apps\", [])}",
          "with open(\"/etc/teleport.yaml\", \"w\") as f: yaml.dump(conf, f, default_flow_style=False, allow_unicode=True)",
          "print(\"Updated teleport.yaml with\", len(apps.get(\"apps\",[])), \"apps\")",
          "\"",
          "sudo systemctl restart teleport",
          "sleep 3",
          "systemctl is-active teleport && echo \"Teleport restarted successfully\" || echo \"ERROR: Teleport failed to restart\""
        ]' \
        --region ${var.region} \
        --output text
    EOT
  }
}

# Teleport 앱 설정을 SSM Parameter Store에도 저장 (백업/추적용)
resource "aws_ssm_parameter" "apps_config" {
  count = length(local.internal_services) > 0 ? 1 : 0

  name        = "/teleport/${var.teleport_server.domain}/apps-config"
  description = "Teleport Application Access configuration"
  type        = "String"
  value       = local.apps_yaml

  tags = {
    ManagedBy = "terraform"
    Stack     = "80-access-gateway"
  }
}
