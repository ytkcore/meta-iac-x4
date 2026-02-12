# =============================================================================
# Teleport Access Gateway Module - Main
# =============================================================================
# 
# 이 모듈은 서비스 목록을 받아 Teleport App Service에 등록합니다.
# SSM을 통해 Teleport 서버의 teleport.yaml에 app_service 섹션을 직접 업데이트합니다.
# =============================================================================

locals {
  # internal = true인 서비스만 필터링
  internal_services = [for s in var.services : s if s != null && s.internal == true]

  # Teleport 앱 설정 생성
  # name = display_name (unified-meta-* 패턴) 또는 svc.name (fallback)
  # description = 한국어 설명 (Teleport UI에 표시)
  teleport_apps_config = [
    for svc in local.internal_services : {
      name                 = svc.display_name != "" ? svc.display_name : svc.name
      uri                  = svc.uri
      description          = svc.description
      public_addr          = "${svc.name}.teleport.${var.teleport_server.domain}"
      insecure_skip_verify = var.insecure_skip_verify
      rewrite_redirect     = svc.rewrite_redirect
      labels = {
        env  = "dev"
        type = svc.type
      }
    }
  ]

  # app_service YAML 블록 직접 생성 (yamlencode 대신 직접 구성)
  app_service_yaml = join("\n", concat(
    ["app_service:", "  enabled: 'yes'", "  apps:"],
    flatten([
      for app in local.teleport_apps_config : concat(
        [
          "    - name: ${app.name}",
          "      uri: ${app.uri}",
          "      public_addr: ${app.public_addr}",
          "      insecure_skip_verify: ${app.insecure_skip_verify}",
        ],
        # description 설정 (UI 표시 이름)
        app.description != "" ? [
          "      description: \"${app.description}\"",
        ] : [],
        # rewrite redirect 설정 (내부 호스트명 → Teleport 프록시 호스트명 변환)
        length(app.rewrite_redirect) > 0 ? concat(
          ["      rewrite:", "        redirect:"],
          [for r in app.rewrite_redirect : "          - ${r}"]
        ) : [],
        [
          "      labels:",
          "        env: ${app.labels.env}",
          "        type: ${app.labels.type}",
        ]
      )
    ])
  ))

  # SSM Parameter 저장용 (추적)
  apps_yaml = yamlencode({
    apps = local.teleport_apps_config
  })
}

# Teleport 앱 설정 파일 생성 및 서비스 재시작
resource "null_resource" "configure_teleport_apps" {
  count = length(local.internal_services) > 0 ? 1 : 0

  triggers = {
    apps_config_hash = md5(local.app_service_yaml)
    services_count   = length(local.internal_services)
  }

  provisioner "local-exec" {
    command = <<-EOT
      # 1. app_service YAML을 SSM Parameter에 저장
      aws ssm put-parameter \
        --name "/teleport/${var.teleport_server.domain}/app-service-yaml" \
        --value '${replace(local.app_service_yaml, "'", "'\\''")}' \
        --type "String" \
        --overwrite \
        --region ${var.region}

      # 2. Teleport 서버에 설정 적용: teleport.yaml의 app_service 섹션 교체
      aws ssm send-command \
        --instance-ids "${var.teleport_server.instance_id}" \
        --document-name "AWS-RunShellScript" \
        --parameters 'commands=[
          "#!/bin/bash",
          "set -e",
          "echo \"=== Teleport App Service Update ===\"",
          "echo \"Step 1: Fetching app_service config from SSM...\"",
          "aws ssm get-parameter --name /teleport/${var.teleport_server.domain}/app-service-yaml --query Parameter.Value --output text --region ${var.region} > /tmp/app_service_block.yaml",
          "echo \"Step 2: Removing old app_service from teleport.yaml...\"",
          "sudo sed -i \"/^app_service:/,/^[a-z]/{ /^app_service:/d; /^[a-z]/!d; }\" /etc/teleport.yaml",
          "sudo sed -i \"/^$/d\" /etc/teleport.yaml",
          "echo \"Step 3: Appending new app_service section...\"",
          "echo \"\" | sudo tee -a /etc/teleport.yaml",
          "cat /tmp/app_service_block.yaml | sudo tee -a /etc/teleport.yaml",
          "echo \"Step 4: Restarting Teleport...\"",
          "sudo systemctl restart teleport",
          "sleep 5",
          "if systemctl is-active --quiet teleport; then echo \"SUCCESS: Teleport restarted with updated apps\"; else echo \"ERROR: Teleport failed to restart\"; journalctl -u teleport -n 20 --no-pager; fi"
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
