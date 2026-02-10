FROM python:3.11-slim-bookworm

WORKDIR /app
# Upgrade system packages to fix vulnerabilities (e.g. CVE-2025-15467)
RUN apt-get update && apt-get upgrade -y && rm -rf /var/lib/apt/lists/*


ENV PYTHONUNBUFFERED=1

RUN pip install --no-cache-dir opcua numpy azure-iot-device

COPY src/detector.py .

# Security Hardening
RUN useradd -m -u 1000 appuser && \
    chown -R appuser:appuser /app

CMD ["python", "detector.py"]

USER 1000

