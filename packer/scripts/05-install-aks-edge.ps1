param(
    [Parameter(Mandatory = $false)]
    [string]$ClusterName = $env:ClusterName,

    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId = $env:SubscriptionId,

    [Parameter(Mandatory = $false)]
    [string]$TenantId = $env:TenantId,

    [Parameter(Mandatory = $false)]
    [string]$ClientId = $env:ClientId,

    [Parameter(Mandatory = $false)]
    [string]$ClientSecret = $env:ClientSecret
)

if ([string]::IsNullOrWhiteSpace($ClusterName) -or [string]::IsNullOrWhiteSpace($ClientSecret)) {
    Write-Warning "Missing parameters. Ensure ClusterName, ClientSecret, etc. are passed or set as environment variables."
    if ([string]::IsNullOrWhiteSpace($ClusterName)) { throw "ClusterName is required." }
}

$ErrorActionPreference = "Stop"
Write-Host "=== Stage 5: Installing AKS Edge Essentials ===" -ForegroundColor Cyan

# Version-Pinned Installation Configuration
# Release Notes: https://github.com/Azure/AKS-Edge/releases
$TargetVersion = "1.11.247.0"

# Version Dictionary (Extensible for future versions)
$versionConfig = @{
    "1.11.247.0" = @{
        K3sVersion  = "1.31.6"
        ReleaseDate = "2024-09-24"
        Url         = "https://download.microsoft.com/download/3c746257-1358-4c17-a9bd-cfd2cece33db/86F37103-8F3A-4D68-B7B0-D10B62BB8271/final1.11/AksEdge-K3s-1.31.6-1.11.247.0.msi"
        Sha256      = $null # Add hash verification if strict integrity check is required
    }
}

if (-not $versionConfig.ContainsKey($TargetVersion)) {
    throw "Target version '$TargetVersion' is not defined in the configuration."
}

$config = $versionConfig[$TargetVersion]
$downloadUrl = $config.Url
$installerPath = "$env:TEMP\AksEdge-K3s-$($config.K3sVersion).msi"

Write-Host "Targeting AKS Edge Essentials Version: $TargetVersion (K3s $($config.K3sVersion))" -ForegroundColor Cyan
Write-Host "Download URL: $downloadUrl" -ForegroundColor Cyan

# Verify URL availability
try {
    $response = Invoke-WebRequest -Uri $downloadUrl -Method Head -UseBasicParsing -TimeoutSec 10
    if ($response.StatusCode -ne 200) {
        throw "Download URL returned status $($response.StatusCode)"
    }
    Write-Host "Reference URL verified." -ForegroundColor Green
}
catch {
    throw "Failed to verify download URL: $_"
}

# Download AKS Edge Essentials
Write-Host "Downloading AKS Edge Essentials..." -ForegroundColor Yellow
if (-not (Test-Path $installerPath)) {
    Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath -UseBasicParsing
}
else {
    Write-Host "Installer already exists at $installerPath. Skipping download." -ForegroundColor Yellow
}

# Verify file size sanity check (> 500MB)
$fileSize = (Get-Item $installerPath).Length / 1MB
if ($fileSize -lt 500) {
    throw "Downloaded MSI is too small ($([math]::Round($fileSize, 2)) MB). Potential partial download."
}

# Install AKS Edge Essentials
Write-Host "Installing AKS Edge Essentials..." -ForegroundColor Yellow
$installArgs = "/i `"$installerPath`" /qn /norestart INSTALLDIR=`"C:\Program Files\AksEdge`" VHDXDIR=`"C:\AksEdge\vhdx`""
$process = Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgs -Wait -PassThru

if ($process.ExitCode -ne 0 -and ($process.ExitCode -ne 3010)) {
    throw "AKS Edge Essentials installation failed with exit code: $($process.ExitCode)"
}

Write-Host "Installation successful." -ForegroundColor Green

# Create deployment configuration template
$deploymentConfig = @{
    SchemaVersion  = "1.14"
    Version        = "1.0"
    DeploymentType = "SingleMachineCluster"
    Init           = @{
        ServiceIPRangeSize = 10
    }
    Network        = @{
        InternetDisabled = $false
    }
    User           = @{
        AcceptEula              = $true
        AcceptOptionalTelemetry = $false
    }
    Machines       = @(
        @{
            LinuxNode = @{
                CpuCount     = 4
                MemoryInMB   = 4096
                DataSizeInGB = 20
            }
        }
    )
    Arc            = @{
        ClusterName       = $ClusterName
        Location          = "centralus"
        ResourceGroupName = "rg-ipc-platform-arc"
        SubscriptionId    = $SubscriptionId
        TenantId          = $TenantId
        ClientId          = $ClientId
        ClientSecret      = $ClientSecret
    }
}

$configPath = "C:\ProgramData\AksEdge"
if (-not (Test-Path $configPath)) {
    New-Item -ItemType Directory -Path $configPath -Force | Out-Null
}

$deploymentConfig | ConvertTo-Json -Depth 10 | Out-File -FilePath "$configPath\aksedge-config-template.json" -Encoding UTF8

# Clean up
Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue

Write-Host "=== Stage 5 Complete ===" -ForegroundColor Green
Write-Host "AKS Edge Essentials installed. Config template: $configPath\aksedge-config-template.json" -ForegroundColor Cyan
