<#
.SYNOPSIS
    Locally rebuilds the AKS Edge Essentials cluster and repairs Identity.
    Intended to be run DIRECTLY on the Hyper-V Host (<edge-vm-name>).

.DESCRIPTION
    Comprehensive "Nuke and Pave" Local Script.
    1. Installs AKS Edge Essentials MSI if missing.
    2. Loads PowerShell Modules robustly.
    3. Deploys Single Machine Cluster (if missing).
    4. Repairs 'azure.json' Identity for ACR authentication.
    5. Verifies Pod Status.

.PARAMETER SubscriptionId
    Your Azure Subscription ID.

.PARAMETER ResourceGroup
    Use 'rg-ipc-dmc-poc-arc' (Default)

.PARAMETER ClusterName
    Use 'aks-edge-dmc' (Default)
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [string]$ResourceGroup = "rg-ipc-dmc-poc-arc",
    [string]$ClusterName = "aks-edge-dmc",
    [string]$Location = "centralus"
)

$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Message, [string]$Color = "Cyan")
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $Message" -ForegroundColor $Color
}

Write-Log "=== Starting Comprehensive Local Rebuild on $env:COMPUTERNAME ===" "Magenta"

# -------------------------------------------------------------
# PHASE 1: Installation & Module Loading
# -------------------------------------------------------------

# Define details
$AksEdgeInstallDir = "C:\Program Files\AksEdge"
$MsiUrl = "https://download.microsoft.com/download/3c746257-1358-4c17-a9bd-cfd2cece33db/86F37103-8F3A-4D68-B7B0-D10B62BB8271/final1.11/AksEdge-K3s-1.31.6-1.11.247.0.msi"
$MsiPath = "$env:TEMP\AksEdge.msi"

# 1. Check if Module is already loaded/available
if (-not (Get-Command Get-AksEdgeDeployment -ErrorAction SilentlyContinue)) {
    Write-Log "AKS Edge Cmdlets not found. Checking installation..." "Yellow"

    # 2. Check if installed on disk
    if (-not (Test-Path "$AksEdgeInstallDir\AksEdge.psd1") -and -not (Test-Path "$AksEdgeInstallDir\AksEdge.psm1")) {
        Write-Log "AKS Edge Essentials not installed at '$AksEdgeInstallDir'. Installing now..." "Yellow"
        
        # Download
        if (-not (Test-Path $MsiPath)) {
            Write-Log "Downloading MSI from $MsiUrl..."
            Invoke-WebRequest -Uri $MsiUrl -OutFile $MsiPath -UseBasicParsing
        }
        
        # Install
        Write-Log "Installing MSI..."
        $installArgs = "/i `"$MsiPath`" /qn /norestart INSTALLDIR=`"$AksEdgeInstallDir`" VHDXDIR=`"C:\AksEdge\vhdx`""
        $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgs -Wait -PassThru
        
        if ($process.ExitCode -ne 0 -and $process.ExitCode -ne 3010) {
            throw "Installation failed with exit code $($process.ExitCode)"
        }
        Write-Log "Installation Complete." "Green"
    }
    
    # 3. Import Module
    Write-Log "Importing AksEdge Module..."
    # Prefer Manifest (.psd1) if available, else Module (.psm1)
    if (Test-Path "$AksEdgeInstallDir\AksEdge.psd1") {
        Import-Module "$AksEdgeInstallDir\AksEdge.psd1" -Global -Force
    }
    elseif (Test-Path "$AksEdgeInstallDir\AksEdge.psm1") {
        Import-Module "$AksEdgeInstallDir\AksEdge.psm1" -Global -Force
    }
    else {
        # Fallback to standard path (though we customized INSTALLDIR)
        Import-Module AksEdge -ErrorAction Stop
    }
}

# 4. Final Verify
if (-not (Get-Command Get-AksEdgeDeployment -ErrorAction SilentlyContinue)) {
    throw "CRITICAL: Get-AksEdgeDeployment is still not recognized after install/import. Please restart PowerShell / VM."
}
Write-Log "AKS Edge Environment Ready." "Green"


# -------------------------------------------------------------
# PHASE 2: Deployment
# -------------------------------------------------------------
$deployment = Get-AksEdgeDeployment -ErrorAction SilentlyContinue
if (-not $deployment) {
    Write-Log "No existing cluster found. Deploying new..." "Yellow"
    
    $configPath = "C:\ProgramData\AksEdge\aksedge-config-template.json"
    if (-not (Test-Path $configPath)) {
        # Emergency Template Generation if missing
        Write-Log "Config template missing. Generating default..." "Yellow"
        $defaultConfig = @{
            SchemaVersion = "1.14"; Version = "1.0"; DeploymentType = "SingleMachineCluster";
            Init = @{ ServiceIPRangeSize = 10 }; Network = @{ InternetDisabled = $false };
            User = @{ AcceptEula = $true; AcceptOptionalTelemetry = $false };
            Machines = @( @{ LinuxNode = @{ CpuCount = 4; MemoryInMB = 4096; DataSizeInGB = 20 } } );
            Arc = @{ 
                ClusterName = $ClusterName; Location = $Location; 
                ResourceGroupName = $ResourceGroup; SubscriptionId = $SubscriptionId 
            }
        }
        if (-not (Test-Path "C:\ProgramData\AksEdge")) { New-Item -ItemType Directory -Path "C:\ProgramData\AksEdge" -Force }
        $defaultConfig | ConvertTo-Json -Depth 5 | Out-File $configPath -Encoding UTF8
    }
    
    New-AksEdgeDeployment -JsonConfigFilePath $configPath -Force
    Write-Log "Cluster Deployed Successfully!" "Green"
}
else {
    Write-Log "Existing Deployment Found ($($deployment.Status)). Proceeding to Repair." "Green"
}

# -------------------------------------------------------------
# PHASE 3: Identity Repair
# -------------------------------------------------------------
Write-Log "Checking Arc & Identity..."

# Helper to get auth token if needed
$azAccount = az account show -o json 2>$null | ConvertFrom-Json
if (-not $azAccount) {
    Write-Log "Please log in to Azure CLI..." "Yellow"
    az login
}

Write-Log "Retrieving Identity info..."
# Ensure Arc connected
$identityJson = az connectedk8s show --name $ClusterName --resource-group $ResourceGroup --query identity -o json 2>$null
if (-not $identityJson) {
    Write-Log "Cluster disconnected. Reconnecting..." "Yellow"
    az connectedk8s connect --name $ClusterName --resource-group $ResourceGroup --location $Location --correlation-id "repair"
    $identityJson = az connectedk8s show --name $ClusterName --resource-group $ResourceGroup --query identity -o json
}

$identity = $identityJson | ConvertFrom-Json
$principalId = $identity.principalId
$tenantId = $identity.tenantId

Write-Log "Identity Principal: $principalId" "Cyan"
$clientId = az ad sp show --id $principalId --query appId -o tsv
Write-Log "Resolved Client ID: $clientId" "Cyan"

# Generate azure.json
Write-Log "Fixing azure.json on Node..."
$azureJsonContent = @{
    cloud                       = "AzurePublicCloud"
    tenantId                    = $tenantId
    userAssignedIdentityID      = $clientId
    useManagedIdentityExtension = $true
    useInstanceMetadata         = $false
    subscriptionId              = $SubscriptionId
    resourceGroup               = $ResourceGroup
    location                    = $Location
} | ConvertTo-Json

$tempFile = "$env:TEMP\azure.json"
$azureJsonContent | Out-File $tempFile -Encoding ASCII

# Push to Node
Copy-AksEdgeNodeFile -FromFile $tempFile -ToFile "/etc/kubernetes/azure.json" -PushFile -NodeType Linux -Force

# Restart Kubelet
Invoke-AksEdgeNodeCommand -NodeType Linux -Command "sudo systemctl restart kubelet"

Write-Log "RECOVERY COMPLETE. Pods will now authenticate correctly." "Green"
kubectl get pods -A
