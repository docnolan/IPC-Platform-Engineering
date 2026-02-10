<#
.SYNOPSIS
    Analyzes a task description and recommends skill routing.

.DESCRIPTION
    Parses input text for keywords and patterns that match skill triggers.
    Returns recommended primary skill and any supporting skills.

.PARAMETER TaskDescription
    Natural language description of the work to be done.

.EXAMPLE
    .\Get-SkillRouting.ps1 -TaskDescription "Update the Packer template to add BitLocker"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$TaskDescription
)

# Skill trigger patterns
$SkillPatterns = @{
    "ipc-junior-engineer" = @(
        "implement", "create", "write", "build", "deploy", "configure",
        "packer", "terraform", "bicep", "yaml", "dockerfile", "kubernetes",
        "script", "powershell", "manifest", "pipeline"
    )
    "knowledge-curator" = @(
        "document", "update wiki", "update docs", "readme", "markdown",
        "documentation", "guide", "runbook"
    )
    "compliance-auditor" = @(
        "nist", "cmmc", "cis", "compliance", "audit", "control", "evidence",
        "hardening", "security baseline", "800-171"
    )
    "release-ring-manager" = @(
        "pipeline", "ci/cd", "build", "release", "deploy", "promote",
        "canary", "rollout", "azure devops pipeline"
    )
    "drift-detection-analyst" = @(
        "drift", "sync", "flux", "gitops", "desired state", "actual state",
        "reconcile", "out of sync"
    )
    "site-reliability-engineer" = @(
        "health", "monitor", "alert", "sli", "slo", "incident", "restart",
        "remediation", "pod", "node", "crash"
    )
    "telemetry-data-engineer" = @(
        "kql", "query", "log analytics", "dashboard", "workbook", "metrics",
        "telemetry", "event hub", "data explorer"
    )
    "secret-rotation-manager" = @(
        "secret", "credential", "pat", "token", "key vault", "rotate",
        "certificate", "expir"
    )
    "architecture-governor" = @(
        "review", "pattern", "architecture", "technical debt", "best practice",
        "pr review", "code review", "design"
    )
}

# Score each skill
$Scores = @{}
$TaskLower = $TaskDescription.ToLower()

foreach ($Skill in $SkillPatterns.Keys) {
    $Score = 0
    foreach ($Pattern in $SkillPatterns[$Skill]) {
        if ($TaskLower -match $Pattern) {
            $Score++
        }
    }
    if ($Score -gt 0) {
        $Scores[$Skill] = $Score
    }
}

# Sort by score descending
$Ranked = $Scores.GetEnumerator() | Sort-Object -Property Value -Descending

# Output recommendation
Write-Host "`nROUTING ANALYSIS" -ForegroundColor Cyan
Write-Host "================" -ForegroundColor Cyan
Write-Host "Task: $TaskDescription`n"

if ($Ranked.Count -eq 0) {
    Write-Host "No clear skill match found." -ForegroundColor Yellow
    Write-Host "Recommend: Escalate to Lead Engineer for clarification."
}
else {
    $Primary = $Ranked | Select-Object -First 1
    Write-Host "Primary Skill: $($Primary.Name)" -ForegroundColor Green
    Write-Host "Match Score: $($Primary.Value) trigger(s)`n"
    
    $Supporting = $Ranked | Select-Object -Skip 1 | Where-Object { $_.Value -ge 1 }
    if ($Supporting) {
        Write-Host "Supporting Skills:" -ForegroundColor Yellow
        foreach ($Skill in $Supporting) {
            Write-Host "  - $($Skill.Name) (score: $($Skill.Value))"
        }
    }
}

# Return primary skill name for programmatic use
if ($Ranked.Count -gt 0) {
    return ($Ranked | Select-Object -First 1).Name
}
return $null
