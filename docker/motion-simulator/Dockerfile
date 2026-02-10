FROM python:3.11-slim-bookworm

WORKDIR /app
# Upgrade system packages to fix vulnerabilities (e.g. CVE-2025-15467)
RUN apt-get update && apt-get upgrade -y && rm -rf /var/lib/apt/lists/*


RUN pip install --no-cache-dir asyncua

COPY src/simulator.py .

EXPOSE 4841

# Security Hardening
RUN useradd -m -u 1000 appuser && \
    chown -R appuser:appuser /app

CMD ["python", "-u", "simulator.py"]

USER 1000

