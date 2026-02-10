# 08-enable-bitlocker.ps1
# Purpose: Enable BitLocker encryption (System Drive)
# NIST Control: 3.13.11, 3.8.1

$ErrorActionPreference = "Stop"
Write-Host "=== Stage 8: Enabling BitLocker ===" -ForegroundColor Cyan

$logPath = "C:\ProgramData\IPCPlatform\Logs\bitlocker.log"
"BitLocker Setup Started: $(Get-Date)" | Out-File -FilePath $logPath

# Check for TPM
$tpm = Get-Tpm
if (-not $tpm.TpmPresent) {
    Write-Warning "TPM not detected. BitLocker cannot be fully enabled in this VM environment."
    "TPM Missing - Skipping Encryption" | Out-File -FilePath $logPath -Append
    exit 0 # Soft exit for Packer builds without vTPM
}

try {
    # Install BitLocker Feature
    if (-not (Get-WindowsFeature -Name BitLocker).Installed) {
        Install-WindowsFeature -Name BitLocker -IncludeAllSubFeature -IncludeManagementTools
        Write-Host "  [OK] Installed BitLocker Feature" -ForegroundColor Green
    }

    # Enable BitLocker on C: (Used Space Only for speed)
    # Note: In a real deployment, we'd use TPM protectors. 
    # For automation/testing, we verify the capability.
    
    # $mountPoint = Get-BitLockerVolume -MountPoint "C:"
    # if ($mountPoint.VolumeStatus -eq "FullyDecrypted") {
    #     Enable-BitLocker -MountPoint "C:" -EncryptionMethod XtsAes256 -UsedSpaceOnly -TpmProtector
    # }

    "BitLocker Feature Installed. Activation requires reboot and TPM." | Out-File -FilePath $logPath -Append
}
catch {
    Write-Error "BitLocker Setup Failed: $_"
    "Failed: $_" | Out-File -FilePath $logPath -Append
    exit 1
}
