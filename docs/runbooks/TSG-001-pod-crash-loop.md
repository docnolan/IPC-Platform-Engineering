# TSG-001: Pod Crash Loop

## Symptoms
- Pod status is `CrashLoopBackOff` or `Error`.
- Restart count is increasing.

## Diagnostic Steps

1. **Check Pod Status**
   ```powershell
   kubectl get pods -n <namespace>
   ```

2. **Inspect Logs (Previous Instance)**
   > Critical for seeing why the *last* container died.
   ```powershell
   kubectl logs <pod-name> -n <namespace> --previous
   ```

3. **Describe Pod**
   > Check for OOMKilled, Liveness Probe failures, or Mount errors.
   ```powershell
   kubectl describe pod <pod-name> -n <namespace>
   ```

4. **Check Events**
   ```powershell
   kubectl get events -n <namespace> --sort-by='.lastTimestamp'
   ```

## Common Resolutions
- **OOMKilled**: Increase memory limit in deployment manifest.
- **Probe Failed**: adjusting `initialDelaySeconds` or fixing health endpoint.
- **Config Missing**: Verify ConfigMaps and Secrets are mounted correctly.
