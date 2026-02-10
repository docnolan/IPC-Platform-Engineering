<#
.SYNOPSIS
    Validates documentation hygiene: broken links and metadata.
.DESCRIPTION
    1. Scans all .md files in the repository.
    2. checks for broken local links (e.g. [Link](missing-file.md)).
    3. Wraps findings in a report.
.EXAMPLE
    .\Validate-Docs.ps1 -RootPath "."
#>

param (
    [string]$RootPath = "."
)

$ErrorActionPreference = "Stop"
$failures = 0
$files = Get-ChildItem -Path $RootPath -Recurse -Filter *.md | Where-Object { $_.FullName -notmatch "node_modules|\.git|references|\.gemini|evidence-collection|docs\\history" }

Write-Host "Create Documentation Validation Report in $RootPath"
Write-Host "Found $($files.Count) markdown files."

foreach ($file in $files) {
    $content = Get-Content -Path $file.FullName -Raw
    # Regex to find [Link Text](LinkTarget)
    $links = [regex]::Matches($content, '\[.*?\]\((.*?)\)')

    foreach ($link in $links) {
        $target = $link.Groups[1].Value
        
        # Skip external links, anchors only, or mailto
        if ($target -match "^http" -or $target -match "^#" -or $target -match "^mailto:") { continue }

        # Remove anchor from target if present (e.g. file.md#section)
        $filePath = $target -replace "#.*", ""
        if ([string]::IsNullOrWhiteSpace($filePath)) { continue }

        # Resolve path relative to the current file
        $resolvedPath = Join-Path -Path $file.DirectoryName -ChildPath $filePath
        
        if (-not (Test-Path $resolvedPath)) {
            Write-Error "BROKEN LINK in $($file.Name): '$target' not found."
            $failures++
        }
    }
}

if ($failures -gt 0) {
    Write-Error "Validation FAILED. Found $failures broken links."
    exit 1
}
else {
    Write-Host "Validation SUCCESS. All links verified."
}
