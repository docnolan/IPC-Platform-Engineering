# Documentation Update Triggers

## Automatic Triggers (Must update documentation)

| Code Change | Wiki File to Update | Max Delay |
|-------------|---------------------|-----------|
| `docker/[workload]/**` | 05/06/07-Workloads-*.md | 3 days |
| `packer/**` | 02-Golden-Image-Pipeline.md | 3 days |
| `kubernetes/**` | 03-Edge-Deployment.md, 04-GitOps-Configuration.md | 3 days |
| `pipelines/**` | 08-CI-CD-Pipelines.md | 3 days |
| `compliance/**` | 09-Compliance-as-a-Service.md | **Immediate** |
| `scripts/**` | A2-Quick-Reference.md | 3 days |
| `.trivyignore` | docs/security/risk-register.md | **Immediate** |

## Review Triggers (Consider documentation update)

| Event | Consideration |
|-------|---------------|
| Bug fix | Update A1-Troubleshooting.md if user-facing |
| Performance optimization | Update relevant workload docs |
| Dependency update | Update if version-specific docs exist |
| Configuration change | Update A2-Quick-Reference.md |

## ADR Triggers (Must create ADR)

| Decision Type | Examples |
|---------------|----------|
| Technology selection | New container base, new tool adoption |
| Architecture change | New workload type, data flow change |
| Security decision | Authentication method, encryption choice |
| Deprecation | Removing feature, changing API |

## Workload to Documentation Mapping

| Workload | Wiki File |
|----------|-----------|
| opcua-simulator | 05-Workloads-OPC-UA.md |
| opcua-gateway | 05-Workloads-OPC-UA.md |
| health-monitor | 06-Workloads-Monitoring.md |
| log-forwarder | 06-Workloads-Monitoring.md |
| anomaly-detection | 07-Workloads-Analytics.md |
| test-data-collector | 07-Workloads-Analytics.md |
| ev-battery-simulator | 07-Workloads-Analytics.md |
| vision-simulator | 07-Workloads-Analytics.md |
| motion-simulator | 07-Workloads-Analytics.md |
| motion-gateway | 07-Workloads-Analytics.md |
