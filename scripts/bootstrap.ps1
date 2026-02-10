<#
.SYNOPSIS
    Orchestrates the "Nuke and Pave" bootstrap process for the IPC Edge Platform.
    Implements a Layered approach for modularity and recovery.

.DESCRIPTION
    This script is the single entry point for provisioning a new customer environment or recovering an existing one.
    It handles:
    - Layer 0: Pre-flight checks (Network, Auth, Config)
    - Layer 1: Infrastructure (Terraform)
    - Layer 2: DevOps (AzDO Project, SPN, Pipelines)
    - Layer 3: Golden Image (Packer)
    - Layer 4: Edge Deployment (VM, Arc)
    - Layer 5: GitOps & Workloads (Flux)
    - Layer 6: Validation (Health Checks)

.PARAMETER CustomerName
    The name of the customer profile to load (e.g. "DMC").

.PARAMETER Environment
    The target environment (e.g. "PoC", "Prod"). Default is "PoC".

.PARAMETER Destroy
    Switch to TEAR DOWN all resources instead of building them.

.PARAMETER Layer
    Specific layers to run (e.g. "1","2"). Default is "All".

.PARAMETER Force
    Bypasses safety confirmation prompts.

.EXAMPLE
    ./bootstrap.ps1 -CustomerName "DMC"
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)]
    [string]$CustomerName,

    [string]$Environment = "PoC",

    [switch]$Destroy,

    [string[]]$Layer = "All",

    [switch]$Force
)

$ErrorActionPreference = "Stop"
$Script:LogFile = "$PSScriptRoot/../logs/bootstrap_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

# region Helper Functions

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    Write-Host $logEntry -ForegroundColor ($Level -eq "ERROR" ? "Red" : "Cyan")
    Add-Content -Path $Script:LogFile -Value $logEntry -Force
}

function Get-CustomerConfig {
    param([string]$Name)
    # in a real scenario, this would read from a JSON file. 
    # For the PoC, we default to the DMC profile if not present.
    
    $configPath = "$PSScriptRoot/../config/$Name.json"
    if (Test-Path $configPath) {
        return Get-Content $configPath | ConvertFrom-Json
    }

    # Default / Fallback for "DMC"
    if ($Name -eq "DMC") {
        return @{
            CustomerName   = "DMC"
            SubscriptionId = "<your-subscription-id>" # Using the user's provided sub ID
            Location       = "centralus"
            ResourcePrefix = "ipc-dmc-poc"
            AzDoOrgUrl     = "https://dev.azure.com/<your-org>"
            AzDoProject    = "IPC-Platform-Engineering"
            IsoPath        = "F:\ISOs\en-us_windows_10_iot_enterprise_ltsc_2021_x64_dvd_257ad90f.iso"
            # Explicitly override VM Name to match user environment
            VmName         = "<edge-vm-name>"
            SwitchName     = "Default Switch"
        }
    }
    
    throw "Configuration for customer '$Name' not found."
}

function Test-AzureConnectivity {
    Write-Log "Testing Network Connectivity to Azure endpoints..."
    $endpoints = @(
        "management.azure.com",
        "login.microsoftonline.com",
        "dev.azure.com"
    )
    
    foreach ($endpoint in $endpoints) {
        try {
            $test = Test-NetConnection -ComputerName $endpoint -Port 443 -WarningAction SilentlyContinue
            if (-not $test.TcpTestSucceeded) {
                throw "Failed to reach $endpoint. Check firewall/proxy."
            }
            Write-Log "  Verified access to $endpoint"
        }
        catch {
            Write-Log "Connectivity check failed for $endpoint" "ERROR"
            throw $_
        }
    }
}

function Get-VmCredential {
    if (-not $Script:VmCredential) {
        if ($env:IPC_VM_PASSWORD) {
            # Secure handling for automation/headless runs
            $securePass = ConvertTo-SecureString $env:IPC_VM_PASSWORD -AsPlainText -Force
            $Script:VmCredential = [PSCredential]::new("Administrator", $securePass)
            Write-Log "Using VM Credential from environment variable (IPC_VM_PASSWORD)."
        }
        else {
            $Script:VmCredential = Get-Credential -UserName "Administrator" -Message "Enter VM Administrator password to use/set"
        }
    }
    return $Script:VmCredential
}





# endregion

# region Main Execution Logic

try {
    # Ensure logs directory exists
    New-Item -ItemType Directory -Path "$PSScriptRoot/../logs" -Force | Out-Null
    Write-Log "Starting Bootstrap Sequence for Customer: $CustomerName Environment: $Environment"

    $metrics = [ordered]@{}
    $overallSw = [System.Diagnostics.Stopwatch]::StartNew()



    # Load Configuration
    $Config = Get-CustomerConfig -Name $CustomerName
    Write-Log "Loaded Configuration for $($Config.ResourcePrefix)"

    # Safety Check
    if (-not $Force) {
        if ($Destroy) {
            $confirmation = Read-Host "WARNING: You are about to DESTROY all resources for $($Config.ResourcePrefix). Type 'DESTROY' to confirm"
            if ($confirmation -ne "DESTROY") { throw "Operation cancelled by user." }
        }
        else {
            $confirmation = Read-Host "About to provision resources for $($Config.ResourcePrefix). Type 'YES' to confirm"
            if ($confirmation -ne "YES") { throw "Operation cancelled by user." }
        }
    }

    # Layer 0: Pre-flight
    if ($Layer -contains "All" -or $Layer -contains "0") {
        $lSw = [System.Diagnostics.Stopwatch]::StartNew()
        Write-Log "=== Layer 0: Pre-flight Checks ==="

        
        # 1. Check Auth Subscription
        $currentSub = az account show --query "id" -o tsv
        if ($currentSub -ne $Config.SubscriptionId) {
            Write-Log "Switching to target subscription: $($Config.SubscriptionId)"
            az account set --subscription $Config.SubscriptionId
        }
        
        # 2. Network Validations
        Test-AzureConnectivity

        Write-Log "Layer 0 Complete."
        $lSw.Stop()
        $metrics["Layer0"] = $lSw.Elapsed
    }


    # Placeholder for other layers
    # Layer 1: Infrastructure (Terraform)
    if ($Layer -contains "All" -or $Layer -contains "1") {
        $lSw = [System.Diagnostics.Stopwatch]::StartNew()
        Write-Log "=== Layer 1: Infrastructure (Terraform) ==="
        
        # 1.1 Bootstrap Terraform Backend (State Storage)
        $tfRgName = "rg-$($Config.ResourcePrefix)-tfstate"
        $tfSaName = ("st" + $Config.ResourcePrefix + "tfstate").Replace("-", "").Substring(0, [math]::Min(24, ("st" + $Config.ResourcePrefix + "tfstate").Replace("-", "").Length))
        $tfContainerName = "tfstate"
        $tfKey = "$($Config.Environment).terraform.tfstate"
        
        Write-Log "Ensuring Request Backend Storage: RG=$tfRgName SA=$tfSaName"
        
        # Create RG if missing
        if (-not (az group show --name $tfRgName --query id -o tsv 2>$null)) {
            Write-Log "Creating Backend Resource Group $tfRgName..."
            az group create --name $tfRgName --location $Config.Location -o none
        }
        
        # Create SA if missing
        $saKey = ""
        if (-not (az storage account show --name $tfSaName --resource-group $tfRgName --query id -o tsv 2>$null)) {
            Write-Log "Creating Backend Storage Account $tfSaName..."
            az storage account create --name $tfSaName --resource-group $tfRgName --location $Config.Location --sku Standard_LRS --encryption-services blob -o none
        }
        
        # Get SA Key
        $saKey = az storage account keys list --account-name $tfSaName --resource-group $tfRgName --query "[0].value" -o tsv
        
        # Create Container
        if (-not (az storage container show --name $tfContainerName --account-name $tfSaName --account-key $saKey --query name -o tsv 2>$null)) {
            if ($PSCmdlet.ShouldProcess($tfContainerName, "Create Storage Container")) {
                Write-Log "Creating Backend Container $tfContainerName..."
                az storage container create --name $tfContainerName --account-name $tfSaName --account-key $saKey -o none
            }
        }

        # 1.2 Run Terraform
        $tfDir = "$PSScriptRoot/../terraform/environments/dev"
        Push-Location $tfDir
        try {
            Write-Log "Initializing Terraform..."
            terraform init `
                -backend-config="resource_group_name=$tfRgName" `
                -backend-config="storage_account_name=$tfSaName" `
                -backend-config="container_name=$tfContainerName" `
                -backend-config="key=$tfKey" `
                -reconfigure -input=false

            Write-Log "Planning Terraform..."
            terraform plan `
                -var="resource_prefix=$($Config.ResourcePrefix)" `
                -var="location=$($Config.Location)" `
                -var="environment=$($Config.Environment)" `
                -out=tfplan -input=false

            Write-Log "Applying Terraform..."
            terraform apply -input=false -auto-approve tfplan
            
            # 1.3 Capture Outputs
            # We don't have outputs defined in outputs.tf yet, but if we did:
            # $tfOutputs = terraform output -json | ConvertFrom-Json
            # Write-Log "Terraform Apply Complete."
        }
        catch {
            Check-TfError
            throw $_
        }
        finally {
            Pop-Location
        }
    }

    if ($Layer -contains "All" -or $Layer -contains "1") {
        $lSw.Stop()
        $metrics["Layer1"] = $lSw.Elapsed
    }


    if ($Layer -contains "All" -or $Layer -contains "2") {
        $lSw = [System.Diagnostics.Stopwatch]::StartNew()
        Write-Log "=== Layer 2: DevOps (AzDO) ==="
        
        $orgUrl = $Config.AzDoOrgUrl
        $projName = $Config.AzDoProject
        
        # 2.1 Create Project (Idempotent)
        if (-not (az devops project show --project $projName --organization $orgUrl --output none 2>$null)) {
            Write-Log "Creating AzDO Project $projName..."
            az devops project create --name $projName --organization $orgUrl --visibility private -o none
        }
        else {
            Write-Log "AzDO Project $projName already exists."
        }
        
        # 2.2 Create Service Principal (90-day expiry)
        $spName = "sp-$($Config.ResourcePrefix)-cicd"
        Write-Log "Ensuring Service Principal $spName (90-day expiry)..."
        
        # Check if exists, if so, we reuse (or rotate - for now reuse)
        # Note: In a real "Nuke" scenario we uses -Destroy to clean this up first.
        
        $spId = az ad sp list --display-name $spName --query "[0].appId" -o tsv
        $spPassword = ""
        $tenantId = az account show --query tenantId -o tsv
        $subId = $Config.SubscriptionId
        $subName = az account show --query name -o tsv
        
        if (-not $spId) {
            Write-Log "Creating new SPN..."
            # Create with Contributor role on the Subscription
            $spJson = az ad sp create-for-rbac --name $spName --role contributor --scopes "/subscriptions/$subId" --years 0.25 -o json
            $spObj = $spJson | ConvertFrom-Json
            $spId = $spObj.appId
            $spPassword = $spObj.password
            Write-Log "Created SPN with ID: $spId"
        }
        else {
            Write-Log "SPN already exists ($spId). Resetting credential to ensure we have it..."
            $spJson = az ad sp credential reset --name $spName --years 0.25 -o json
            $spObj = $spJson | ConvertFrom-Json
            $spPassword = $spObj.password
        }
        
        # 2.3 Create Service Connection
        $scName = "sc-$($Config.ResourcePrefix)-arm"
        Write-Log "Creating/Updating Service Connection $scName..."
        
        # Authenticate for AzDO (assuming current user auth works, otherwise requires PAT)
        # We use the AZURE_DEVOPS_EXT_AZURE_RM_SERVICE_PRINCIPAL_KEY env var to pass the secret
        
        $env:AZURE_DEVOPS_EXT_AZURE_RM_SERVICE_PRINCIPAL_KEY = $spPassword
        
        # Check if SC exists
        $scId = az devops service-endpoint list --project $projName --organization $orgUrl --query "[?name=='$scName'].id" -o tsv
        
        if ($scId) {
            # Update is complex via CLI, easier to delete and recreate for idempotent bootstrap
            Write-Log "Deleting existing Service Connection to start fresh..."
            az devops service-endpoint delete --id $scId --project $projName --organization $orgUrl -y -o none
        }
        
        Write-Log "Creating Service Connection..."
        az devops service-endpoint azurerm create `
            --name $scName `
            --project $projName `
            --organization $orgUrl `
            --azure-rm-service-principal-id $spId `
            --azure-rm-subscription-id $subId `
            --azure-rm-subscription-name $subName `
            --azure-rm-tenant-id $tenantId `
            -o none
            
        # Clear secret from env
        Remove-Item Env:\AZURE_DEVOPS_EXT_AZURE_RM_SERVICE_PRINCIPAL_KEY
        
        # 2.4 Seed Environments
        $environments = @("Dev", "Alpha", "Beta", "Prod")
        foreach ($env in $environments) {
            Write-Log "Seeding Environment: $env"
            if (-not (az devops environment show --name $env --project $projName --organization $orgUrl -o none 2>$null)) {
                az devops environment create --name $env --project $projName --organization $orgUrl -o none
            }
        }
    }
    
    if ($Layer -contains "All" -or $Layer -contains "2") {
        $lSw.Stop()
        $metrics["Layer2"] = $lSw.Elapsed
    }

    
    if ($Layer -contains "All" -or $Layer -contains "3") {
        $lSw = [System.Diagnostics.Stopwatch]::StartNew()
        Write-Log "=== Layer 3: Golden Image (Packer) ==="
        
        $packerDir = "$PSScriptRoot/../packer"
        $outputDir = "$packerDir/output-dmc-golden" # Default in pkr.hcl
        
        # Check if already exists
        if (Test-Path "$outputDir/*.vhdx") {
            Write-Log "Golden Image already exists in $outputDir. Skipping build (Recovery Mode)."
        }
        else {
            Write-Log "Building Golden Image (this may take 20+ minutes)..."
            
            # Ensure we have credentials
            if (-not $spId -or -not $spPassword) {
                Write-Log "Missing SPN credentials for Arc onboarding. Checking env vars..."
                if ($env:ARC_CLIENT_ID -and $env:ARC_CLIENT_SECRET) {
                    $spId = $env:ARC_CLIENT_ID
                    $spPassword = $env:ARC_CLIENT_SECRET
                }
                else {
                    throw "Cannot build image: Missing Service Principal credentials (ARC_CLIENT_ID/SECRET)."
                }
            }
            
            if ($PSCmdlet.ShouldProcess("Golden Image", "Build with Packer")) {
                Push-Location $packerDir
                try {
                    packer build `
                        -var "iso_url=$($Config.IsoPath)" `
                        -var "switch_name=$($Config.SwitchName)" `
                        -var "arc_subscription_id=$($Config.SubscriptionId)" `
                        -var "arc_tenant_id=$tenantId" `
                        -var "arc_location=$($Config.Location)" `
                        -var "arc_client_id=$spId" `
                        -var "arc_client_secret=$spPassword" `
                        -force `
                        dmc-golden.pkr.hcl
                }
                finally {
                    Pop-Location
                }
                Write-Log "Packer Build Complete."
            }

        }
    }
    
    if ($Layer -contains "All" -or $Layer -contains "3") {
        $lSw.Stop()
        $metrics["Layer3"] = $lSw.Elapsed
    }

    
    if ($Layer -contains "All" -or $Layer -contains "4") {
        $lSw = [System.Diagnostics.Stopwatch]::StartNew()
        Write-Log "=== Layer 4: Edge Deployment (Hyper-V) ==="
        
        # Use Configured VM Name
        $vmName = $Config.VmName
        if (-not $vmName) { $vmName = "IPC-$($Config.CustomerName)-Edge-01" }

        $vhdxPath = Get-ChildItem "$PSScriptRoot/../packer/output-dmc-golden/*.vhdx" | Select-Object -First 1 -ExpandProperty FullName
        
        if (-not $vhdxPath) {
            # In Recovery Mode, if VHDX is missing, we might assume VM exists.
            Write-Log "Golden Image VHDX not found in packer output." "WARNING"
        }
        
        # Check if VM exists
        if (Get-VM -Name $vmName -ErrorAction SilentlyContinue) {
            Write-Log "VM $vmName already exists. Skipping creation."
            # Ideally check state and start if stopped
        }
        else {
            if ($PSCmdlet.ShouldProcess($vmName, "Create VM")) {
                Write-Log "Creating VM $vmName..."
                # Copying VHDX to final location to avoid locking the packer output
                $vmBaseDir = "C:\Hyper-V\IPC"
                if (-not (Test-Path $vmBaseDir)) {
                    New-Item -ItemType Directory -Path $vmBaseDir -Force | Out-Null
                }
                $vmDiskPath = "$vmBaseDir\$vmName.vhdx"
                
                Write-Log "Copying disk to $vmDiskPath..."
                Copy-Item -Path $vhdxPath -Destination $vmDiskPath
                
                # Gen 2 for AKS Edge Essentials
                New-VM -Name $vmName -MemoryStartupBytes 8GB -VHDPath $vmDiskPath -SwitchName $Config.SwitchName -Generation 2
                
                # Enable Nested Virtualization
                Set-VMProcessor -VMName $vmName -ExposeVirtualizationExtensions $true
                
                Write-Log "Starting VM..."
                Start-VM -Name $vmName
            }
        }
        $lSw.Stop()
        $metrics["Layer4"] = $lSw.Elapsed
    }

        
    if ($Layer -contains "All" -or $Layer -contains "5") {
        $lSw = [System.Diagnostics.Stopwatch]::StartNew()
        Write-Log "=== Layer 5: Edge Deployment (Arc & GitOps) ==="
        
        $vmName = $Config.VmName
        if (-not $vmName) { $vmName = "IPC-$($Config.CustomerName)-Edge-01" }
        $cred = Get-VmCredential
        
        Write-Log "Waiting for VM $vmName to be accessible..."
        # Loop check for WinRM/PS availability
        $ready = $false
        for ($i = 0; $i -lt 30; $i++) {
            try {
                Invoke-Command -VMName $vmName -Credential $cred -ScriptBlock { Get-ComputerInfo } -ErrorAction Stop | Out-Null
                $ready = $true
                break
            }
            catch {
                Start-Sleep -Seconds 10
            }
        }
        
        if (-not $ready) { throw "VM did not become responsive after boot." }
        
        # 5.0 Ensure Cluster Deployment (Inside VM)
        if ($PSCmdlet.ShouldProcess("VM: $vmName", "Ensure AKS Edge Cluster Deployment")) {
            Write-Log "Checking AKS Edge Deployment status..."
            Invoke-Command -VMName $vmName -Credential $cred -ScriptBlock {
                $deployment = Get-AksEdgeDeployment -ErrorAction SilentlyContinue
                if (-not $deployment) {
                    Write-Host "No deployment found. Starting New-AksEdgeDeployment..."
                    $configPath = "C:\ProgramData\AksEdge\aksedge-config-template.json"
                    
                    if (-not (Test-Path $configPath)) {
                        throw "Config template not found at $configPath. Packer build may be incomplete."
                    }
                    
                    # Deploy with Force to overwrite any potential stale state
                    New-AksEdgeDeployment -JsonConfigFilePath $configPath -Force
                    
                    if (-not (Get-AksEdgeDeployment)) {
                        throw "Deployment failed to verify after execution."
                    }
                    Write-Host "New-AksEdgeDeployment Successful."
                }
                else {
                    Write-Host "AKS Edge Deployment already exists."
                }
            }
        }

        # 5.1 Connect Arc (Inside VM - Connected K8s)
        if ($PSCmdlet.ShouldProcess("VM: $vmName", "Connect to Azure Arc (Connected K8s)")) {
            Write-Log "Triggering Arc Connected K8s Connection inside VM..."
            Invoke-Command -VMName $vmName -Credential $cred -ScriptBlock {
                param($SubId, $TenantId, $Loc, $ClientId, $Secret, $Rg, $ClusterName)
                    
                # Requires 'az' installed in VM (Packer image should have this)
                $env:PATH = "$env:PATH;C:\Program Files (x86)\Microsoft SDKs\Azure\CLI2\wbin"
                    
                az login --service-principal -u $ClientId -p $Secret --tenant $TenantId -o none
                az account set --subscription $SubId
                    
                Write-Host "Connecting K8s Cluster to Arc..."
                # Assuming this is after Initialize-AksEdgeNode
                az connectedk8s connect --name $ClusterName --resource-group $Rg --location $Loc --correlation-id "bootstrap"
                    
            } -ArgumentList $Config.SubscriptionId, $tenantId, $Config.Location, $spId, $spPassword, "rg-$($Config.ResourcePrefix)-arc", "aks-edge-$($Config.CustomerName)"
            
            # 5.1b Repair Identity (The "Azure.json" Fix)
            Write-Log "Applying Identity Authentication Fix (azure.json)..."
            Invoke-Command -VMName $vmName -Credential $cred -ScriptBlock {
                param($ClusterName, $Rg)
                
                # 1. Retrieve the Arc Managed Identity
                Write-Host "Retrieving Arc Managed Identity for $ClusterName..."
                $identityJson = az connectedk8s show --name $ClusterName --resource-group $Rg --query identity -o json
                $identity = $identityJson | ConvertFrom-Json
                $principalId = $identity.principalId
                $tenantId = $identity.tenantId
                
                if (-not $principalId) {
                    throw "Failed to retrieve Identity Principal ID from Arc Connected Cluster."
                }
                
                Write-Host "Found Identity: $principalId"
                
                # 2. Re-create azure.json with the CORRECT identity
                # AKS Edge often defaults to SPN or missing ID in disconnected scenarios.
                # We enforce the Arc Agent's MI for ACR Pulls.
                
                $azureJsonPath = "/etc/kubernetes/azure.json" # Linux Node Path
                if (Test-Path "C:\Users\Administrator\azure.json") {
                    Remove-Item "C:\Users\Administrator\azure.json" -Force
                }
                
                # Note: We need the CLIENT ID, not Principal ID, for azure.json usually. 
                # But for SystemAssigned MI, we might only have Principal ID easily.
                # Let's try to get Client ID via AZ (requires rights)
                # If SystemAssigned, we use useManagedIdentityExtension: true
                
                # For Arc on Edge, the most reliable path verified manually:
                # Use the 'userAssignedIdentityID' field mapped to the CLIENT ID.
                
                # Attempt to get Client ID
                $clientId = az ad sp show --id $principalId --query appId -o tsv
                
                if (-not $clientId) {
                    Write-Warning "Could not resolve ClientID for Principal $principalId. Authentication might fail."
                }
                else {
                    Write-Host "Resolved Client ID: $clientId"
                    
                    $azureJsonContent = @{
                        cloud                       = "AzurePublicCloud"
                        tenantId                    = $tenantId
                        userAssignedIdentityID      = $clientId
                        useManagedIdentityExtension = $true
                        useInstanceMetadata         = $false # Edge nodes often lack IMDS
                        subscriptionId              = "$($env:SubscriptionId)" # Fallback or pass in
                        resourceGroup               = "$Rg"
                        location                    = "centralus" # Hardcoded to matched verified config
                    } | ConvertTo-Json
                    
                    $azureJsonContent | Out-File "C:\Users\Administrator\azure.json" -Encoding ASCII
                    
                    # 3. Push to Node
                    Write-Host "Pushing fixed azure.json to Linux Node..."
                    Copy-AksEdgeNodeFile -FromFile "C:\Users\Administrator\azure.json" -ToFile "/etc/kubernetes/azure.json" -PushFile -NodeType Linux -Force
                    
                    # 4. Restart Kubelet
                    Write-Host "Restarting Kubelet to apply changes..."
                    Invoke-AksEdgeNodeCommand -NodeType Linux -Command "sudo systemctl restart kubelet"
                    
                    Write-Host "Identity Repaired."
                }
            } -ArgumentList "aks-edge-$($Config.CustomerName)", "rg-$($Config.ResourcePrefix)-arc"
        }

        
        # 5.2 Install Flux (Azure Side)
        Write-Log "Installing Flux Extension..."
        # Wait for Arc resource availability
        $clusterName = "aks-edge-$($Config.CustomerName)"
        $arcRg = "rg-$($Config.ResourcePrefix)-arc"
        
        $resourceId = ""
        for ($i = 0; $i -lt 12; $i++) {
            $resourceId = az connectedk8s show --name $clusterName --resource-group $arcRg --query id -o tsv 2>$null
            if ($resourceId) { break }
            Start-Sleep -Seconds 10
        }
        
        if ($resourceId) {
            if ($PSCmdlet.ShouldProcess("Arc Cluster: $clusterName", "Install Flux Extension")) {
                az k8s-extension create `
                    --name "flux" `
                    --cluster-name $clusterName `
                    --resource-group $arcRg `
                    --cluster-type "connectedClusters" `
                    --extension-type "microsoft.flux" `
                    --auto-upgrade-minor-version true `
                    -o none
            }

        }
        else {
            Write-Log "Warning: Arc K8s resource not found. Skipping Flux install." "WARNING"
        }
        $lSw.Stop()
        $metrics["Layer5"] = $lSw.Elapsed
    }

    if ($Layer -contains "All" -or $Layer -contains "6") {
        $lSw = [System.Diagnostics.Stopwatch]::StartNew()
        Write-Log "=== Layer 6: Validation & Reporting ==="
        
        # 6.1 Workload Health
        Write-Log "Validating Workload Health (Definition of Done)..."
        # Since we don't have direct kubectl access to the edge cluster from here (unless we setup Kubeconfig),
        # we check via Invoke-Command inside the VM.
        
        $vmName = "<edge-vm-name>"
        $cred = Get-VmCredential
        
        Invoke-Command -VMName $vmName -Credential $cred -ScriptBlock {
            param($TimeoutMinutes)
            $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
            do {
                $pods = kubectl get pods -n dmc-workloads -o json | ConvertFrom-Json
                $running = ($pods.items | Where-Object { $_.status.phase -eq "Running" }).Count
                $expected = 6 
                if ($running -ge $expected) {
                    Write-Host "All $expected workloads are RUNNING."
                    return
                }
                Start-Sleep -Seconds 10
            } while ((Get-Date) -lt $deadline)
            throw "Workloads failed to stabilize."
        } -ArgumentList 10
        
        $lSw.Stop()
        $metrics["Layer6"] = $lSw.Elapsed
        
        # 6.2 Metrics and Report
        $overallSw.Stop()
        
        $finalMetrics = @{
            Timestamp      = Get-Date
            Customer       = $CustomerName
            Status         = "Success"
            TotalDuration  = $overallSw.Elapsed.ToString()
            LayerBreakdown = $metrics
        }
        $finalMetrics | ConvertTo-Json -Depth 5 | Out-File "$PSScriptRoot/../metrics.json"
        
        Write-Log "Metrics saved to metrics.json"
        
        # Create Markdown Report
        $reportParams = @{
            Config  = $Config
            Metrics = $metrics
        }
    }
    
    Write-Log "Bootstrap Sequence Completed Successfully."
}
catch {
    Write-Log "Bootstrap Failed: $_" "ERROR"
    exit 1
}

# endregion
