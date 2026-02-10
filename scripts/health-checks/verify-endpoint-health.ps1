<#
.SYNOPSIS
    Verifies the health of an HTTP endpoint.
.DESCRIPTION
    Sends a GET request to the specified URL. Returns "Green" for 200 OK, "Red" otherwise.
.PARAMETER Url
    The URL to check.
#>
param(
    [Parameter(Mandatory=$true)]
    [string]$Url
)

try {
    $response = Invoke-RestMethod -Uri $Url -Method Get -ErrorAction Stop -TimeoutSec 5
    Write-Output "Green"
}
catch {
    Write-Output "Red"
}
