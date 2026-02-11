# ==============================================================================
# Opstart Dashboard (β) — Docker Image
#
# 빌드: docker build -t opstart:latest -f ops/dashboard/Dockerfile .
# 실행: docker run -p 8080:8080 opstart:latest
#
# Note: 프로젝트 루트에서 빌드해야 scripts/ 디렉토리를 포함할 수 있습니다.
# ==============================================================================
FROM python:3.12-slim

# 시스템 패키지
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    bash \
    jq \
    && rm -rf /var/lib/apt/lists/*

# kubectl 설치
RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
    && chmod +x kubectl \
    && mv kubectl /usr/local/bin/

# 앱 디렉토리
WORKDIR /app

# Python 패키지
COPY ops/dashboard/requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# 소스 복사
COPY ops/dashboard/app.py /app/app.py
COPY ops/dashboard/templates/ /app/templates/
COPY scripts/ /app/scripts/
COPY gitops-apps/ /app/gitops-apps/

# 환경 변수
ENV PROJECT_ROOT=/app
ENV FLASK_APP=app.py
ENV PYTHONUNBUFFERED=1

EXPOSE 8080

CMD ["python", "app.py"]
