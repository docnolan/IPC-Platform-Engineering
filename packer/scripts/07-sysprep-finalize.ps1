# 07-sysprep-finalize.ps1
# Purpose: Final cleanup and Sysprep for image generalization

$ErrorActionPreference = "Stop"
Write-Host "=== Stage 7: Final Cleanup and Sysprep ===" -ForegroundColor Cyan

# Clear Windows Update cache
Write-Host "Clearing Windows Update cache..." -ForegroundColor Yellow
Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
Remove-Item -Path "C:\Windows\SoftwareDistribution\*" -Recurse -Force -ErrorAction SilentlyContinue
Start-Service -Name wuauserv -ErrorAction SilentlyContinue

# Clear temp files
Write-Host "Clearing temporary files..." -ForegroundColor Yellow
$tempPaths = @(
    "$env:TEMP\*",
    "C:\Windows\Temp\*"
)
foreach ($path in $tempPaths) {
    Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
}

# Clear event logs (optional - comment out if you want to preserve build logs)
Write-Host "Clearing event logs..." -ForegroundColor Yellow
Get-WinEvent -ListLog * -ErrorAction SilentlyContinue | ForEach-Object {
    try {
        [System.Diagnostics.Eventing.Reader.EventLogSession]::GlobalSession.ClearLog($_.LogName)
    }
    catch { }
}

# Wait for Azure agent services
Write-Host "Waiting for Azure agent services..." -ForegroundColor Yellow
while ((Get-Service RdAgent -ErrorAction SilentlyContinue).Status -ne 'Running') {
    Start-Sleep -Seconds 5
}
while ((Get-Service WindowsAzureGuestAgent -ErrorAction SilentlyContinue).Status -ne 'Running') {
    Start-Sleep -Seconds 5
}

# Run Sysprep
Write-Host "Running Sysprep..." -ForegroundColor Yellow
& $env:SystemRoot\System32\Sysprep\Sysprep.exe /oobe /generalize /quiet /quit /mode:vm

# Wait for Sysprep to complete
Write-Host "Waiting for Sysprep to complete..." -ForegroundColor Yellow
while ($true) {
    $imageState = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\State" | 
    Select-Object -ExpandProperty ImageState
    if ($imageState -eq 'IMAGE_STATE_GENERALIZE_RESEAL_TO_OOBE') {
        break
    }
    Write-Host "  Current state: $imageState" -ForegroundColor Gray
    Start-Sleep -Seconds 10
}

Write-Host "=== Stage 7 Complete ===" -ForegroundColor Green
Write-Host "Image is ready for capture." -ForegroundColor Cyan
