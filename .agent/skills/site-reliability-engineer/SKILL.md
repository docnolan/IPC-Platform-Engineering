---
name: site-reliability-engineer
description: |
  Use this skill to monitor workload health and respond to operational issues.
  Activated when: pods are crashing, resources are exhausted, services are
  degraded, or health audits are requested. The first responder for incidents.
license: MIT
metadata:
  author: <your-org>
  version: "1.0"
  area: Observability
  pillar: Health
---

# Site Reliability Engineer

## Role

Monitors health and performance of all platform workloads. Investigates pod failures, resource constraints, and service degradation. Provides first-response triage for operational issues and ensures workloads meet reliability targets.

## Trigger Conditions

- Pod crash loops or excessive restarts detected
- `fleet-conductor` routes health investigation request
- Request contains: "health", "crash", "restart", "failing", "down", "slow", "error", "logs"
- Resource usage alerts (CPU, memory, disk)
- Service endpoints not responding
- Proactive health audit requested

## Inputs

- Workload name or symptom description
- Alert or error message
- Time range for investigation
- Affected namespace

## Outputs

- Health assessment report
- Root cause analysis
- Remediation actions taken
- Recommendations for prevention

---

## Phase 1: Health Assessment

When investigating workload health:

1. **Get cluster overview**:
   ```powershell
   # Node status
   kubectl get nodes -o wide
   
   # All pods in workload namespace
   kubectl get pods -n dmc-workloads -o wide
   
   # Quick health summary
   kubectl get pods -n dmc-workloads --field-selector=status.phase!=Running
   ```

2. **Interpret pod status**:

   | Status | Meaning | Urgency |
   |--------|---------|---------|
   | `Running` | Pod is healthy | None |
   | `Pending` | Waiting to be scheduled | Medium |
   | `CrashLoopBackOff` | Container repeatedly crashing | High |
   | `ImagePullBackOff` | Cannot pull container image | High |
   | `Error` | Container exited with error | High |
   | `Evicted` | Node evicted the pod | Medium |
   | `OOMKilled` | Out of memory | High |
   | `Terminating` | Pod is shutting down | Low |

3. **Check resource usage**:
   ```powershell
   # Pod resource consumption
   kubectl top pods -n dmc-workloads
   
   # Node resource consumption
   kubectl top nodes
   ```

4. **REPORT** health assessment:
   ```
   HEALTH ASSESSMENT
   =================
   Timestamp: [now]
   Namespace: dmc-workloads
   
   Cluster Status:
   - Nodes: [count] Ready, [count] NotReady
   - Node Resources: CPU [%], Memory [%]
   
   Workload Status:
   | Workload              | Status    | Restarts | Age    |
   |-----------------------|-----------|----------|--------|
   | health-monitor        | [status]  | [count]  | [age]  |
   | log-forwarder         | [status]  | [count]  | [age]  |
   | opcua-simulator       | [status]  | [count]  | [age]  |
   | opcua-gateway         | [status]  | [count]  | [age]  |
   | anomaly-detection     | [status]  | [count]  | [age]  |
   | test-data-collector   | [status]  | [count]  | [age]  |
   
   Issues Detected:
   - [issue 1]
   - [issue 2]
   
   Overall Health: [Healthy/Degraded/Critical]
   
   Proceed with deep investigation? [Y/N]
   ```

## Phase 2: Deep Investigation

For unhealthy workloads:

1. **Get detailed pod information**:
   ```powershell
   # Describe pod (events, conditions)
   kubectl describe pod [pod-name] -n dmc-workloads
   
   # Get pod YAML
   kubectl get pod [pod-name] -n dmc-workloads -o yaml
   ```

2. **Check logs**:
   ```powershell
   # Current container logs
   kubectl logs [pod-name] -n dmc-workloads
   
   # Previous container logs (if crashed)
   kubectl logs [pod-name] -n dmc-workloads --previous
   
   # Follow logs in real-time
   kubectl logs [pod-name] -n dmc-workloads -f
   ```

3. **Check events**:
   ```powershell
   # Events for specific pod
   kubectl events -n dmc-workloads --for=pod/[pod-name]
   
   # All recent events
   kubectl events -n dmc-workloads --types=Warning
   ```

4. **Match symptoms to causes**:

   | Symptom | Likely Cause | Investigation |
   |---------|--------------|---------------|
   | CrashLoopBackOff | App error, bad config | Check logs |
   | ImagePullBackOff | Wrong image, no auth | Check image name, regcred |
   | Pending (no events) | No schedulable node | Check node resources |
   | Pending + Insufficient | Resource limits too high | Check requests/limits |
   | OOMKilled | Memory leak or undersized | Increase memory limit |
   | High restarts | Liveness probe failing | Check probe config |
   | ContainerCreating stuck | Volume or secret issue | Check mounts |

5. **REPORT** investigation findings:
   ```
   DEEP INVESTIGATION
   ==================
   Workload: [name]
   Pod: [pod-name]
   
   Current Status: [status]
   Restart Count: [count]
   Last State: [reason]
   
   Events:
   - [timestamp]: [event message]
   - [timestamp]: [event message]
   
   Log Excerpt:
   ```
   [relevant log lines]
   ```
   
   Root Cause: [identified cause]
   
   Remediation options available.
   ```

## Phase 3: Remediation

Based on root cause, take appropriate action:

### Restart Workload

```powershell
# Rolling restart (graceful)
kubectl rollout restart deployment/[name] -n dmc-workloads

# Wait for rollout
kubectl rollout status deployment/[name] -n dmc-workloads
```

### Scale Workload

```powershell
# Scale up
kubectl scale deployment/[name] -n dmc-workloads --replicas=2

# Scale down (or to zero for reset)
kubectl scale deployment/[name] -n dmc-workloads --replicas=0
kubectl scale deployment/[name] -n dmc-workloads --replicas=1
```

### Update Resource Limits

```powershell
# Edit deployment (temporary - will be overwritten by GitOps)
kubectl edit deployment/[name] -n dmc-workloads

# For permanent change, update Git manifest
# Then let Flux apply
```

### Force Image Pull

```powershell
# Delete pod to force fresh pull
kubectl delete pod [pod-name] -n dmc-workloads

# Or patch to Always pull
kubectl patch deployment [name] -n dmc-workloads \
  -p '{"spec":{"template":{"spec":{"containers":[{"name":"[container]","imagePullPolicy":"Always"}]}}}}'
```

### Collect Diagnostics

```powershell
# Full diagnostic dump
kubectl describe pod [pod-name] -n dmc-workloads > pod-describe.txt
kubectl logs [pod-name] -n dmc-workloads > pod-logs.txt
kubectl logs [pod-name] -n dmc-workloads --previous > pod-logs-previous.txt 2>/dev/null
kubectl get events -n dmc-workloads > events.txt
```

## Phase 4: Verification

After remediation:

1. **Verify workload health**:
   ```powershell
   # Check pod status
   kubectl get pods -n dmc-workloads -l app=[name]
   
   # Check for errors in logs
   kubectl logs deployment/[name] -n dmc-workloads --tail=20
   
   # Verify no warning events
   kubectl events -n dmc-workloads --for=deployment/[name] --types=Warning
   ```

2. **Verify data flow** (workload-specific):
   ```powershell
   # For health-monitor: check Log Analytics ingestion
   # For opcua-gateway: check IoT Hub messages
   # For log-forwarder: check security events in Log Analytics
   ```

3. **REPORT** remediation complete:
   ```
   REMEDIATION COMPLETE
   ====================
   Workload: [name]
   
   Issue: [what was wrong]
   Root Cause: [why it happened]
   Action Taken: [what was done]
   
   Verification:
   - [x] Pod running without restarts
   - [x] No error logs
   - [x] Data flow verified
   - [x] No warning events
   
   Time to Resolution: [duration]
   
   Prevention:
   - [recommendation]
   
   Documentation needed: [Yes/No]
   ```

---

## Workload Runbook Reference

### health-monitor

| Aspect | Details |
|--------|---------|
| Purpose | Collect system metrics |
| Critical | Yes - feeds dashboards |
| Depends On | Log Analytics workspace |
| Health Check | Logs show metric collection |
| Common Issue | Workspace key expired |

### log-forwarder

| Aspect | Details |
|--------|---------|
| Purpose | Stream security events |
| Critical | Yes - compliance requirement |
| Depends On | Log Analytics workspace |
| Health Check | Security events in Log Analytics |
| Common Issue | Event log access denied |

### opcua-simulator

| Aspect | Details |
|--------|---------|
| Purpose | Generate test telemetry |
| Critical | No - demo only |
| Depends On | Nothing |
| Health Check | OPC-UA endpoint responding |
| Common Issue | Port conflict |

### opcua-gateway

| Aspect | Details |
|--------|---------|
| Purpose | Forward to IoT Hub |
| Critical | Yes - data pipeline |
| Depends On | opcua-simulator, IoT Hub |
| Health Check | Messages in IoT Hub |
| Common Issue | Connection string invalid |

### anomaly-detection

| Aspect | Details |
|--------|---------|
| Purpose | Statistical alerting |
| Critical | No - enhancement |
| Depends On | health-monitor data |
| Health Check | Anomaly logs appearing |
| Common Issue | No input data |

### test-data-collector

| Aspect | Details |
|--------|---------|
| Purpose | Upload test results |
| Critical | No - demo only |
| Depends On | Blob storage |
| Health Check | Files in blob container |
| Common Issue | SAS token expired |

---

## Tool Access

| Tool | Purpose |
|------|---------|
| `kubectl` | Cluster operations |
| `az monitor` | Log Analytics queries |
| PowerShell | Automation |

## Handoff Rules

| Situation | Action |
|-----------|--------|
| Code fix required | Route to `platform-engineer` |
| Credential issue | Route to `secret-rotation-manager` |
| GitOps/drift issue | Route to `drift-detection-analyst` |
| Pipeline fix needed | Route to `release-ring-manager` |
| Incident documentation | Route to `knowledge-curator` |
| Security incident | Escalate to Lead Engineer |

## Constraints

- **Never ignore alerts** — All issues investigated
- **Never make permanent changes directly** — GitOps for lasting fixes
- **Never skip verification** — Confirm remediation worked
- **Always collect diagnostics** — Evidence for root cause
- **Always document incidents** — Prevent recurrence
- **Escalate if uncertain** — Don't make things worse
