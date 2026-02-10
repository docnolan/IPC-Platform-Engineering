[CmdletBinding()]
param()

$orgUrl = "https://dev.azure.com/<your-org>"
$project = "IPC-Platform-Engineering"
$definitionIds = "3,4,5,6,7,8,9,10,11" 

try {
    Write-Host "Fetching Access Token..."
    $token = az account get-access-token --query accessToken -o tsv
    if (-not $token) {
        Write-Error "Failed to get access token from Azure CLI"
        exit 1
    }

    $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($token)"))
    $headers = @{Authorization = ("Basic {0}" -f $base64AuthInfo) }

    $url = "$orgUrl/$project/_apis/build/builds?definitions=$definitionIds&queryOrder=queueTimeDescending&maxBuildsPerDefinition=1&api-version=7.1"

    Write-Host "Querying Azure DevOps Build Status..."
    $response = Invoke-RestMethod -Uri $url -Method Get -Headers $headers -ContentType "application/json"

    $results = $response.value | Select-Object `
    @{Name = "Pipeline"; Expression = { $_.definition.name } }, `
        id, `
        status, `
        result, `
    @{Name = "Branch"; Expression = { $_.sourceBranch } }, `
        startTime, `
        finishTime

    $results | Format-Table -AutoSize
    
    # Summary Check
    $failed = $results | Where-Object { $_.result -eq 'failed' }
    $running = $results | Where-Object { $_.status -in 'inProgress', 'notStarted' }
    
    if ($failed) {
        Write-Host "`nCRITICAL: Some builds have failed!" -ForegroundColor Red
        exit 1
    }
    elseif ($running) {
        Write-Host "`nBuilds are still running..." -ForegroundColor Yellow
    }
    else {
        Write-Host "`nAll builds completed successfully!" -ForegroundColor Green
    }

}
catch {
    Write-Error $_.Exception.Message
}
