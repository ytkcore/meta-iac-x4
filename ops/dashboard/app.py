# ==============================================================================
# Opstart Dashboard (β) — Backend API
#
# Description:
#   - 배포 후 운영 초기화(Bootstrap)를 위한 웹 대시보드의 Flask 백엔드.
#   - K8s Pod 또는 로컬에서 실행 가능.
#   - 6단계: Vault → Secret → Keycloak → ArgoCD → Rancher → Monitoring
#
# Maintainer: DevOps Team
# ==============================================================================

from flask import Flask, render_template, jsonify, request
import subprocess
import json
import os
import shutil

app = Flask(__name__)

# ------------------------------------------------------------------------------
# Helpers (유틸리티)
# ------------------------------------------------------------------------------
def get_project_root():
    """프로젝트 루트 경로를 반환합니다. 환경변수 PROJECT_ROOT 우선, 없으면 자동 계산."""
    env_root = os.environ.get('PROJECT_ROOT')
    if env_root:
        return env_root
    current_dir = os.path.dirname(os.path.abspath(__file__))
    return os.path.dirname(os.path.dirname(current_dir))

def run_cmd(cmd):
    """셸 명령어를 실행하고 stdout을 반환합니다. 실패 시 None을 반환합니다."""
    try:
        result = subprocess.run(
            cmd, shell=True, check=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
        return result.stdout.strip()
    except subprocess.CalledProcessError as e:
        print(f"[ERROR] 명령 실패: {cmd}\n{e.stderr}")
        return None

# ------------------------------------------------------------------------------
# Routes — 페이지
# ------------------------------------------------------------------------------
@app.route("/")
def index():
    return render_template("index.html")

# ------------------------------------------------------------------------------
# Routes — 상태 확인 API
# ------------------------------------------------------------------------------
@app.route("/api/status/vault")
def status_vault():
    """Vault Unseal 상태를 확인합니다."""
    # 사전 조건: kubectl 연결
    kube_check = run_cmd("kubectl cluster-info --request-timeout=5s 2>&1 | head -1")
    if not kube_check:
        return jsonify({"status": "missing", "message": "K8s 클러스터 연결 실패 — tsh kube login 필요"})

    ns_check = run_cmd("kubectl get ns vault --no-headers")
    if not ns_check:
        return jsonify({"status": "missing", "message": "Vault Namespace를 찾을 수 없습니다"})

    pod_status = run_cmd("kubectl get pod vault-0 -n vault -o jsonpath='{.status.phase}'")
    if pod_status != "Running":
        return jsonify({"status": "not_running", "message": f"Vault Pod 상태: {pod_status}"})

    try:
        vault_json_str = run_cmd("kubectl exec vault-0 -n vault -- vault status -format=json")
        if not vault_json_str:
            return jsonify({"status": "error", "message": "Vault 상태를 가져올 수 없습니다"})

        vault_status = json.loads(vault_json_str)
        sealed = vault_status.get("sealed", True)
        seal_type = vault_status.get("seal_type", "shamir")

        if sealed:
            return jsonify({"status": "sealed", "message": "Vault가 Sealed 상태입니다", "seal_type": seal_type})
        else:
            return jsonify({"status": "active", "message": "Vault가 Active 상태입니다", "seal_type": seal_type})

    except Exception as e:
        return jsonify({"status": "error", "message": str(e)})

@app.route("/api/status/secrets")
def status_secrets():
    """Keycloak K8s Secret 존재 여부를 확인합니다."""
    ns = "keycloak"

    ns_check = run_cmd(f"kubectl get ns {ns} --no-headers")
    if not ns_check:
        return jsonify({"namespace": False, "db": False, "admin": False})

    db_secret = run_cmd(f"kubectl get secret keycloak-db-secret -n {ns} --no-headers")
    admin_secret = run_cmd(f"kubectl get secret keycloak-admin-secret -n {ns} --no-headers")

    return jsonify({
        "namespace": True,
        "db": bool(db_secret),
        "admin": bool(admin_secret)
    })

@app.route("/api/status/keycloak")
def status_keycloak():
    """Keycloak Platform Realm 존재 여부를 확인합니다."""
    try:
        cmd = "curl -sk -o /dev/null -w '%{http_code}' https://keycloak.dev.unifiedmeta.net/realms/platform"
        code = run_cmd(cmd)

        if code == "200":
            return jsonify({"configured": True, "message": "Platform Realm이 존재합니다"})
        else:
            return jsonify({"configured": False, "message": "Platform Realm을 찾을 수 없습니다"})
    except Exception as e:
        return jsonify({"configured": False, "message": str(e)})

# ------------------------------------------------------------------------------
# Routes — 액션 API
# ------------------------------------------------------------------------------
@app.route("/api/actions/generate-secrets", methods=["POST"])
def generate_secrets():
    """랜덤 비밀번호를 생성하고 K8s Secret을 생성합니다."""
    ns = "keycloak"

    # Namespace 생성 (멱등)
    run_cmd(f"kubectl create namespace {ns} --dry-run=client -o yaml | kubectl apply -f -")

    generated = {}

    # DB Secret 생성
    if not run_cmd(f"kubectl get secret keycloak-db-secret -n {ns} --no-headers"):
        password = run_cmd("openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 20")
        cmd = f"kubectl create secret generic keycloak-db-secret -n {ns} --from-literal=KC_DB_USERNAME=keycloak --from-literal=KC_DB_PASSWORD={password}"
        run_cmd(cmd)
        generated["db_password"] = password

    # Admin Secret 생성
    if not run_cmd(f"kubectl get secret keycloak-admin-secret -n {ns} --no-headers"):
        password = run_cmd("openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 20")
        cmd = f"kubectl create secret generic keycloak-admin-secret -n {ns} --from-literal=KEYCLOAK_ADMIN=admin --from-literal=KEYCLOAK_ADMIN_PASSWORD={password}"
        run_cmd(cmd)
        generated["admin_password"] = password

    return jsonify({"status": "success", "generated": generated})

@app.route("/api/actions/configure-keycloak", methods=["POST"])
def configure_keycloak():
    """configure-realm.sh 스크립트를 실행하여 Keycloak Realm을 설정합니다."""
    # Admin 비밀번호 조회
    password = run_cmd(
        "kubectl get secret keycloak-admin-secret -n keycloak "
        "-o jsonpath='{.data.KEYCLOAK_ADMIN_PASSWORD}' | base64 -d"
    )
    if not password:
        return jsonify({"status": "error", "message": "Keycloak Admin Secret이 없습니다. Step 2를 먼저 실행하세요."})

    # 스크립트 경로 확인
    project_root = get_project_root()
    script_path = os.path.join(project_root, "scripts", "keycloak", "configure-realm.sh")

    if not os.path.exists(script_path):
        return jsonify({"status": "error", "message": f"스크립트를 찾을 수 없습니다: {script_path}"})

    run_cmd(f"chmod +x {script_path}")

    env = os.environ.copy()
    env["KEYCLOAK_ADMIN_PASS"] = password

    try:
        result = subprocess.run(
            [script_path], env=env, cwd=project_root,
            capture_output=True, text=True
        )

        if result.returncode == 0:
            return jsonify({"status": "success", "output": result.stdout})
        else:
            return jsonify({
                "status": "error",
                "message": "스크립트 실행 실패",
                "output": result.stdout + "\n" + result.stderr
            })
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)})

@app.route("/api/actions/sync-argocd", methods=["POST"])
def sync_argocd():
    """ArgoCD 애플리케이션 전체 동기화를 실행합니다."""
    # 사전 조건: kubectl 연결
    kube_check = run_cmd("kubectl cluster-info --request-timeout=5s 2>&1 | head -1")
    if not kube_check:
        return jsonify({
            "status": "error",
            "message": "kubectl 클러스터 연결 실패",
            "output": "✗ K8s 클러스터에 연결할 수 없습니다."
        })

    project_root = get_project_root()
    script_path = os.path.join(project_root, "scripts", "argocd", "sync-all.sh")

    if not os.path.exists(script_path):
        return jsonify({"status": "error", "message": f"스크립트를 찾을 수 없습니다: {script_path}"})

    run_cmd(f"chmod +x {script_path}")

    try:
        result = subprocess.run(
            [script_path], cwd=project_root,
            capture_output=True, text=True
        )

        if result.returncode == 0:
            return jsonify({"status": "success", "output": result.stdout})
        else:
            return jsonify({
                "status": "error",
                "message": "스크립트 실행 실패",
                "output": result.stdout + "\n" + result.stderr
            })
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)})

# ------------------------------------------------------------------------------
# Routes — 가이드 API
# ------------------------------------------------------------------------------
@app.route("/api/guide")
def get_guide():
    """Post-Deployment Operations Guide 마크다운을 반환합니다."""
    project_root = get_project_root()
    guide_path = os.path.join(project_root, "docs", "guides", "post-deployment-operations-guide.md")

    try:
        if os.path.exists(guide_path):
            with open(guide_path, "r", encoding="utf-8") as f:
                content = f.read()
            return jsonify({"status": "success", "content": content})
        else:
            return jsonify({"status": "error", "message": f"가이드를 찾을 수 없습니다: {guide_path}"})
    except Exception as e:
        return jsonify({"status": "error", "message": f"가이드 로딩 실패: {str(e)}"})

# ------------------------------------------------------------------------------
# 엔트리포인트
# ------------------------------------------------------------------------------
if __name__ == "__main__":
    host = os.environ.get('FLASK_HOST', '0.0.0.0')
    port = int(os.environ.get('FLASK_PORT', '8080'))
    debug = os.environ.get('FLASK_DEBUG', 'false').lower() == 'true'
    print(f"Opstart Dashboard (β) 시작: http://{host}:{port}")
    app.run(host=host, port=port, debug=debug)
