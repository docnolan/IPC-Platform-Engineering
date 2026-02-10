<#
.SYNOPSIS
    Setup Workload Identity infrastructure for IPC Platform
    
.DESCRIPTION
    This script provisions Azure resources for identity-based authentication:
    - Assigns AcrPull role to Arc agent (for secret-less container pulls)
    - Creates User-Assigned Managed Identity for Flux GitOps
    - Configures Federated Identity Credential for Kubernetes service accounts
    
.PARAMETER ClusterResourceGroup
    The resource group containing the Arc Cluster and Identity resources
    
.PARAMETER AcrResourceGroup
    The resource group containing the Azure Container Registry
    
.PARAMETER SubscriptionId
    Azure subscription ID
    
.PARAMETER ClusterName
    Arc-connected Kubernetes cluster name
    
.PARAMETER AcrName
    Azure Container Registry name
    
.PARAMETER Phase
    Which phase to execute: 'ACR', 'Flux', or 'All'
    
.EXAMPLE
    # Phase 1: ACR only (recommended first)
    .\setup-workload-identity.ps1 -Phase ACR
    
    # Phase 2: Flux Workload Identity
    .\setup-workload-identity.ps1 -Phase Flux
    
    # Both phases
    .\setup-workload-identity.ps1 -Phase All
    
.NOTES
    Author: IPC Platform Engineering
    Version: 1.0.2
    Requires: Az CLI 2.50+, Owner or User Access Administrator role
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$ClusterResourceGroup = "rg-ipc-platform-arc",

    [Parameter()]
    [string]$AcrResourceGroup = "rg-ipc-platform-acr",
    
    [Parameter()]
    [string]$SubscriptionId = "<your-subscription-id>",
    
    [Parameter()]
    [string]$ClusterName = "<your-arc-cluster-name>",
    
    [Parameter()]
    [string]$AcrName = "<your-acr-name>",
    
    [Parameter()]
    [string]$Location = "eastus",
    
    [Parameter()]
    [ValidateSet("ACR", "Flux", "All")]
    [string]$Phase = "ACR",
    
    [Parameter()]
    [switch]$WhatIf
)

$ErrorActionPreference = "Continue" # Relaxed to handle benign stderr (Python warnings)
Set-StrictMode -Version Latest

#region Helper Functions

function Write-Step {
    param([string]$Message)
    Write-Host "`n------------------------------------------------------------" -ForegroundColor Cyan
    Write-Host "  $Message" -ForegroundColor Cyan
    Write-Host "------------------------------------------------------------" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "  [OK] $Message" -ForegroundColor Green
}

function Write-Info {
    param([string]$Message)
    Write-Host "  [INFO] $Message" -ForegroundColor Gray
}

function Write-Warn {
    param([string]$Message)
    Write-Host "  [WARN] $Message" -ForegroundColor Yellow
}

function Test-AzCliLoggedIn {
    $account = az account show 2>$null | ConvertFrom-Json
    if (-not $account) {
        throw "Not logged into Azure CLI. Run 'az login' first."
    }
    return $account
}

function Test-RequiredPermissions {
    param([string]$Scope)
    
    # Check if user has required roles
    $assignments = az role assignment list --assignee (az ad signed-in-user show --query id -o tsv) --scope $Scope 2>$null | ConvertFrom-Json
    $hasOwner = $assignments | Where-Object { $_.roleDefinitionName -eq "Owner" }
    $hasUAA = $assignments | Where-Object { $_.roleDefinitionName -eq "User Access Administrator" }
    
    if (-not ($hasOwner -or $hasUAA)) {
        Write-Warn "You may not have sufficient permissions. Requires Owner or User Access Administrator."
        Write-Warn "Continuing anyway - Azure will reject if permissions are insufficient."
    }
}

#endregion

#region Main Script

Write-Host @"

===============================================================
     IPC Platform - Workload Identity Setup                    
     Phase: $Phase                                               
===============================================================

"@ -ForegroundColor Magenta

# Verify Azure CLI login
Write-Step "Verifying Azure CLI Authentication"
$account = Test-AzCliLoggedIn
Write-Success "Logged in as: $($account.user.name)"
Write-Info "Subscription: $($account.name) ($($account.id))"

# Set subscription context
az account set --subscription $SubscriptionId
Write-Success "Subscription context set to: $SubscriptionId"

# Build scope
$clusterRgScope = "/subscriptions/$SubscriptionId/resourceGroups/$ClusterResourceGroup"
$acrScope = "/subscriptions/$SubscriptionId/resourceGroups/$AcrResourceGroup/providers/Microsoft.ContainerRegistry/registries/$AcrName"

#region Phase 1: ACR Managed Identity

if ($Phase -eq "ACR" -or $Phase -eq "All") {
    
    Write-Step "Phase 1: ACR Managed Identity (Secret-less Container Pulls)"
    
    # Get Arc agent managed identity
    Write-Info "Retrieving Arc cluster identity from $ClusterResourceGroup..."
    
    $arcCluster = az connectedk8s show `
        --name $ClusterName `
        --resource-group $ClusterResourceGroup `
        2>$null | ConvertFrom-Json
    
    if (-not $arcCluster) {
        throw "Arc cluster '$ClusterName' not found in resource group '$ClusterResourceGroup'"
    }
    
    # Arc clusters can have different identity types
    # For Arc-connected K8s, we need the extension identity or system identity
    $arcIdentityPrincipalId = $arcCluster.identity.principalId
    
    if (-not $arcIdentityPrincipalId) {
        Write-Warn "Arc cluster does not have a system-assigned identity."
        Write-Info "Checking for Azure Arc extensions with managed identity..."
        
        # List extensions to find one with identity
        $extensions = az k8s-extension list `
            --cluster-name $ClusterName `
            --cluster-type connectedClusters `
            --resource-group $ClusterResourceGroup `
            2>$null | ConvertFrom-Json
        
        # Look for flux extension identity
        $fluxExt = $extensions | Where-Object { $_.extensionType -eq "microsoft.flux" }
        if ($fluxExt -and $fluxExt.identity) {
            $arcIdentityPrincipalId = $fluxExt.identity.principalId
            Write-Info "Using Flux extension identity: $arcIdentityPrincipalId"
        }
    }
    
    if (-not $arcIdentityPrincipalId) {
        Write-Warn "Could not find a managed identity on the Arc cluster or extensions."
        Write-Warn "ACR pull will continue to use Kubernetes secrets."
        Write-Info "To enable managed identity, ensure the cluster has system-assigned identity enabled."
    }
    else {
        Write-Success "Found Arc identity: $arcIdentityPrincipalId"
        
        # Assign AcrPull role
        Write-Info "Assigning AcrPull role to Arc identity on scope: $acrScope..."
        
        if ($WhatIf) {
            Write-Warn "[WhatIf] Would assign AcrPull role"
        }
        else {
            $existingAssignment = az role assignment list `
                --assignee $arcIdentityPrincipalId `
                --role "AcrPull" `
                --scope $acrScope `
                2>$null | ConvertFrom-Json
            
            if ($existingAssignment -and $existingAssignment.Count -gt 0) {
                Write-Info "AcrPull role already assigned"
            }
            else {
                # We need to ensure we catch errors here
                try {
                    az role assignment create `
                        --assignee-object-id $arcIdentityPrincipalId `
                        --assignee-principal-type ServicePrincipal `
                        --role "AcrPull" `
                        --scope $acrScope `
                        --output none
                    
                    Write-Success "AcrPull role assigned to Arc identity"
                }
                catch {
                    Write-Warn "Failed to assign role: $_"
                }
            }
        }
        
        # Output next steps
        Write-Host "`n  [NEXT STEPS] ACR:" -ForegroundColor Yellow
        Write-Host "     1. Remove 'imagePullSecrets' from deployments" -ForegroundColor White
        Write-Host "     2. Restart pods to pick up new authentication" -ForegroundColor White
        Write-Host "     3. Verify: kubectl get events -n dmc-workloads | grep -i pull" -ForegroundColor White
    }
}

#endregion

#region Phase 2: Flux Workload Identity

if ($Phase -eq "Flux" -or $Phase -eq "All") {
    
    Write-Step "Phase 2: Flux Workload Identity (Secret-less Git Access)"
    
    $miName = "mi-flux-gitops"
    $fcName = "fc-flux-source-controller"
    
    # Get cluster OIDC issuer URL
    Write-Info "Retrieving cluster OIDC issuer URL..."
    
    # For Arc-connected clusters, OIDC issuer comes from the cluster
    $oidcIssuer = az connectedk8s show `
        --name $ClusterName `
        --resource-group $ClusterResourceGroup `
        --query "oidcIssuerProfile.issuerUrl" `
        -o tsv 2>$null
    
    if (-not $oidcIssuer -or $oidcIssuer -eq "null" -or $oidcIssuer -eq "") {
        Write-Warn "OIDC issuer not configured on Arc cluster."
        Write-Info "Enabling OIDC issuer profile (this takes time)..."
        
        if ($WhatIf) {
            Write-Warn "[WhatIf] Would enable OIDC issuer"
        }
        else {
            az connectedk8s update `
                --name $ClusterName `
                --resource-group $ClusterResourceGroup `
                --enable-oidc-issuer `
                --output none 2>$null
            
            # Re-fetch issuer URL
            Write-Info "Waiting 30 seconds for OIDC settings to propagate..."
            Start-Sleep -Seconds 30
            $oidcIssuer = az connectedk8s show `
                --name $ClusterName `
                --resource-group $ClusterResourceGroup `
                --query "oidcIssuerProfile.issuerUrl" `
                -o tsv
        }
    }
    
    if ($oidcIssuer -and $oidcIssuer -ne "null" -and $oidcIssuer -ne "") {
        Write-Success "OIDC Issuer: $oidcIssuer"
    }
    else {
        Write-Warn "Could not enable OIDC issuer. Workload Identity may not be available."
        Write-Info "This is common for AKS Edge Essentials clusters."
        
        # Exit Flux phase early
        if ($Phase -eq "Flux") {
            Write-Host ""
            exit 0
        }
    }
    
    # Only continue if OIDC is available
    if ($oidcIssuer -and $oidcIssuer -ne "null" -and $oidcIssuer -ne "") {
        
        # Create User-Assigned Managed Identity
        Write-Info "Creating User-Assigned Managed Identity: $miName in $ClusterResourceGroup"
        
        if ($WhatIf) {
            Write-Warn "[WhatIf] Would create managed identity"
            $miPrincipalId = "00000000-0000-0000-0000-000000000000"
            $miClientId = "00000000-0000-0000-0000-000000000000"
        }
        else {
            $existingMi = az identity show `
                --name $miName `
                --resource-group $ClusterResourceGroup `
                2>$null | ConvertFrom-Json
            
            if ($existingMi) {
                Write-Info "Managed Identity already exists"
                $miPrincipalId = $existingMi.principalId
                $miClientId = $existingMi.clientId
            }
            else {
                $newMi = az identity create `
                    --name $miName `
                    --resource-group $ClusterResourceGroup `
                    --location $Location `
                    2>$null | ConvertFrom-Json
                
                $miPrincipalId = $newMi.principalId
                $miClientId = $newMi.clientId
                Write-Success "Created Managed Identity: $miName"
            }
        }
        
        Write-Info "Principal ID: $miPrincipalId"
        Write-Info "Client ID: $miClientId"
        
        # Create Federated Identity Credential
        Write-Info "Creating Federated Identity Credential: $fcName"
        
        $subject = "system:serviceaccount:flux-system:source-controller"
        
        if ($WhatIf) {
            Write-Warn "[WhatIf] Would create federated credential"
        }
        else {
            $existingFc = az identity federated-credential show `
                --name $fcName `
                --identity-name $miName `
                --resource-group $ClusterResourceGroup `
                2>$null | ConvertFrom-Json
            
            if ($existingFc) {
                Write-Info "Federated credential already exists"
            }
            else {
                az identity federated-credential create `
                    --name $fcName `
                    --identity-name $miName `
                    --resource-group $ClusterResourceGroup `
                    --issuer $oidcIssuer `
                    --subject $subject `
                    --audiences "api://AzureADTokenExchange" `
                    --output none
                
                Write-Success "Created Federated Identity Credential"
            }
        }
        
        # Output configuration values
        Write-Host "`n  [CONFIG] Flux Values:" -ForegroundColor Yellow
        Write-Host "     AZURE_CLIENT_ID: $miClientId" -ForegroundColor White
        Write-Host "     AZURE_TENANT_ID: $($account.tenantId)" -ForegroundColor White
        Write-Host "     OIDC_ISSUER: $oidcIssuer" -ForegroundColor White
        
        Write-Host "`n  [NEXT STEPS] Flux:" -ForegroundColor Yellow
        Write-Host "     1. Grant the Managed Identity access to Azure DevOps" -ForegroundColor White
        Write-Host "        (Azure DevOps -> Organization Settings -> Users -> Add)" -ForegroundColor White
        Write-Host "     2. Update GitRepository manifest with provider: azure" -ForegroundColor White
        Write-Host "     3. Annotate source-controller ServiceAccount:" -ForegroundColor White
        Write-Host "        azure.workload.identity/client-id: $miClientId" -ForegroundColor White
    }
}

#endregion

#region Summary

Write-Step "Summary"

$results = @()

if ($Phase -eq "ACR" -or $Phase -eq "All") {
    $results += [PSCustomObject]@{
        Component = "ACR Pull"
        Status    = if ($arcIdentityPrincipalId) { "OK Configured" } else { "WARN Manual Setup Required" }
        Method    = if ($arcIdentityPrincipalId) { "Managed Identity" } else { "Kubernetes Secret" }
    }
}

if ($Phase -eq "Flux" -or $Phase -eq "All") {
    $results += [PSCustomObject]@{
        Component = "Flux GitOps"
        Status    = if ($oidcIssuer -and $oidcIssuer -ne "null" -and $oidcIssuer -ne "") { "OK Identity Created" } else { "WARN OIDC Not Available" }
        Method    = if ($oidcIssuer -and $oidcIssuer -ne "null" -and $oidcIssuer -ne "") { "Workload Identity" } else { "PAT / SSH Key" }
    }
}

$results | Format-Table -AutoSize

Write-Host @"

===============================================================
     Setup Complete                                            
     See 'Next Steps' above for remaining manual actions       
===============================================================

"@ -ForegroundColor Magenta

#endregion
