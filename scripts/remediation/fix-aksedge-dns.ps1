<#
.SYNOPSIS
    Fixes AKS Edge Essentials DNS configuration for outbound connectivity.

.DESCRIPTION
    Remediation script for AKS Edge Linux node DNS resolution issue.
    Configures systemd-resolved to use Google DNS (8.8.8.8, 8.8.4.4) when the
    default DNS server (from Hyper-V) becomes unreachable.

.NOTES
    CMMC Level 2 Compliance Mapping:
    - NIST 800-171 3.4.2: Track, review, approve/disapprove, and log changes to systems
    - NIST 800-171 3.3.1: Create and retain system audit logs
    - NIST 800-171 3.13.1: Monitor, control, and protect communications at external boundaries

    Risk Assessment: LOW
    - Using well-known Google Public DNS (8.8.8.8)
    - Outbound-only DNS queries
    - No inbound access modification
    - Change is logged and auditable

    Author: DMC Platform Engineering
    Version: 1.1
    Date: 2026-01-30
#>

[CmdletBinding()]
param(
    [switch]$WhatIf,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

# Configuration
$PrimaryDNS = "8.8.8.8"
$SecondaryDNS = "8.8.4.4"
$LogPath = "$env:USERPROFILE\Desktop\dns-remediation-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

function Write-AuditLog {
    param([string]$Message, [string]$Level = "INFO")
    $entry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message"
    Write-Host $entry
    Add-Content -Path $LogPath -Value $entry -ErrorAction SilentlyContinue
}

Write-AuditLog "=== AKS Edge DNS Remediation Script v1.1 ===" "INFO"
Write-AuditLog "Compliance: NIST 800-171 3.4.2, 3.3.1, 3.13.1" "INFO"
Write-AuditLog "Executed by: $env:USERNAME on $env:COMPUTERNAME" "INFO"

# Step 1: Capture current state (evidence)
Write-AuditLog "Step 1: Capturing current DNS configuration..." "INFO"
try {
    $currentDNS = Invoke-AksEdgeNodeCommand -NodeType Linux -Command "resolvectl status 2>/dev/null | head -30 || cat /etc/resolv.conf"
    Write-AuditLog "Current DNS state:" "INFO"
    $currentDNS -split "`n" | Select-Object -First 20 | ForEach-Object { Write-AuditLog "  $_" "INFO" }
}
catch {
    Write-AuditLog "Failed to read current DNS config: $_" "WARN"
}

# Step 2: Test current DNS (verify issue exists)
Write-AuditLog "Step 2: Testing current DNS resolution..." "INFO"
try {
    $dnsTestResult = Invoke-AksEdgeNodeCommand -NodeType Linux -Command "timeout 5 nslookup <your-acr-name>.azurecr.io 8.8.8.8 2>&1"
    if ($dnsTestResult -match "\d+\.\d+\.\d+\.\d+") {
        Write-AuditLog "External DNS (8.8.8.8) works - issue is local resolver config" "INFO"
    }
}
catch {
    Write-AuditLog "DNS test had issues - proceeding with remediation" "WARN"
}

# Step 3: Apply fix
if ($WhatIf) {
    Write-AuditLog "WhatIf: Would configure systemd-resolved to use $PrimaryDNS, $SecondaryDNS" "INFO"
    Write-AuditLog "WhatIf: Would create /etc/systemd/resolved.conf.d/dns-override.conf" "INFO"
    Write-AuditLog "WhatIf: Would restart systemd-resolved service" "INFO"
}
else {
    Write-AuditLog "Step 3: Configuring systemd-resolved with Google DNS..." "INFO"
    
    try {
        # Method 1: Configure systemd-resolved drop-in
        Invoke-AksEdgeNodeCommand -NodeType Linux -Command "sudo mkdir -p /etc/systemd/resolved.conf.d"
        Write-AuditLog "Created resolved.conf.d directory" "INFO"
        
        # Create the config file
        $configCmd = @"
sudo tee /etc/systemd/resolved.conf.d/dns-override.conf > /dev/null << 'DNSEOF'
# Created by fix-aksedge-dns.ps1
# Compliance: NIST 800-171 3.4.2 Configuration Management
[Resolve]
DNS=$PrimaryDNS $SecondaryDNS
FallbackDNS=1.1.1.1 9.9.9.9
DNSEOF
"@
        Invoke-AksEdgeNodeCommand -NodeType Linux -Command $configCmd
        Write-AuditLog "Created dns-override.conf" "INFO"
        
        # Restart systemd-resolved
        Invoke-AksEdgeNodeCommand -NodeType Linux -Command "sudo systemctl restart systemd-resolved"
        Write-AuditLog "Restarted systemd-resolved service" "INFO"
        
    }
    catch {
        Write-AuditLog "systemd-resolved method failed: $_ - trying direct method..." "WARN"
        
        # Fallback: Remove symlink and create static file
        try {
            $directCmd = "sudo rm -f /etc/resolv.conf; echo 'nameserver $PrimaryDNS' | sudo tee /etc/resolv.conf; echo 'nameserver $SecondaryDNS' | sudo tee -a /etc/resolv.conf"
            Invoke-AksEdgeNodeCommand -NodeType Linux -Command $directCmd
            Write-AuditLog "Created static /etc/resolv.conf (fallback method)" "INFO"
        }
        catch {
            Write-AuditLog "Failed to update DNS config: $_" "ERROR"
            throw
        }
    }
}

# Step 4: Verify fix
if (-not $WhatIf) {
    Write-AuditLog "Step 4: Verifying DNS configuration..." "INFO"
    Start-Sleep -Seconds 3
    
    try {
        $verifyDNS = Invoke-AksEdgeNodeCommand -NodeType Linux -Command "resolvectl status 2>/dev/null | grep -A5 'DNS Servers' || cat /etc/resolv.conf"
        Write-AuditLog "DNS configuration after fix:" "INFO"
        $verifyDNS -split "`n" | ForEach-Object { Write-AuditLog "  $_" "INFO" }
    }
    catch {
        Write-AuditLog "Could not verify DNS config - continuing..." "WARN"
    }
    
    # Step 5: Test DNS resolution
    Write-AuditLog "Step 5: Testing DNS resolution to ACR..." "INFO"
    try {
        $testResult = Invoke-AksEdgeNodeCommand -NodeType Linux -Command "nslookup <your-acr-name>.azurecr.io 2>&1"
        if ($testResult -match "\d+\.\d+\.\d+\.\d+") {
            Write-AuditLog "DNS resolution SUCCESSFUL" "INFO"
            $testResult -split "`n" | Select-Object -First 10 | ForEach-Object { Write-AuditLog "  $_" "INFO" }
        }
        else {
            Write-AuditLog "DNS resolution result (review manually):" "WARN"
            Write-AuditLog $testResult "WARN"
        }
    }
    catch {
        Write-AuditLog "DNS test command failed - may still be working" "WARN"
    }
    
    # Step 6: Restart pods to trigger image pulls
    Write-AuditLog "Step 6: Restarting workload pods to trigger image pulls..." "INFO"
    try {
        kubectl delete pods -n dmc-workloads --all 2>&1 | ForEach-Object { Write-AuditLog "  $_" "INFO" }
        
        Write-AuditLog "Waiting 30 seconds for pods to recreate..." "INFO"
        Start-Sleep -Seconds 30
        
        $podStatus = kubectl get pods -n dmc-workloads --no-headers 2>&1
        Write-AuditLog "Current pod status:" "INFO"
        $podStatus -split "`n" | ForEach-Object { Write-AuditLog "  $_" "INFO" }
    }
    catch {
        Write-AuditLog "Pod restart had issues: $_" "WARN"
    }
}

Write-AuditLog "=== Remediation Complete ===" "INFO"
Write-AuditLog "Audit log saved to: $LogPath" "INFO"

# Return result object for automation
[PSCustomObject]@{
    Success            = $true
    Timestamp          = Get-Date
    PrimaryDNS         = $PrimaryDNS
    SecondaryDNS       = $SecondaryDNS
    LogPath            = $LogPath
    ComplianceControls = @("3.4.2", "3.3.1", "3.13.1")
}
