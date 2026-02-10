FROM python:3.11-slim

WORKDIR /app

# Upgrade system packages to fix vulnerabilities (e.g. CVE-2025-15467 in openssl)
RUN apt-get update && apt-get upgrade -y && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir asyncua azure-iot-device python-dotenv

COPY src/gateway.py .

# Security Hardening
RUN useradd -m -u 1000 appuser && \
    chown -R appuser:appuser /app

CMD ["python", "gateway.py"]

USER 1000
