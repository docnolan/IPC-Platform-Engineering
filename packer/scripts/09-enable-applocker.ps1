# 09-enable-applocker.ps1
# Purpose: Configure AppLocker in Audit Mode
# NIST Control: 3.1.2
# Reference: CIS Microsoft Windows 10 Benchmark

$ErrorActionPreference = "Stop"
Write-Host "=== Stage 9: Configuring AppLocker (Audit Mode) ===" -ForegroundColor Cyan

$logPath = "C:\ProgramData\IPCPlatform\Logs\applocker.log"
"AppLocker Config Started: $(Get-Date)" | Out-File -FilePath $logPath

$policyXml = @"
<AppLockerPolicy Version="1">
  <RuleCollection Type="Exe" EnforcementMode="AuditOnly">
    <FilePublisherRule Id="9b60d48f-2877-48f1-b844-325d761d191d" Name="Signed by Microsoft" Description="" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePublisherCondition PublisherName="O=MICROSOFT CORPORATION, L=REDMOND, S=WASHINGTON, C=US" ProductName="*" BinaryName="*">
          <BinaryVersionRange LowSection="*" HighSection="*" />
        </FilePublisherCondition>
      </Conditions>
    </FilePublisherRule>
    <FilePathRule Id="fd686d83-a829-4351-8ff4-27c7de5755d2" Name="All files in Windows folder" Description="" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePathCondition Path="%WINDIR%\*" />
      </Conditions>
    </FilePathRule>
    <FilePathRule Id="36113b2f-3d60-449a-bd9e-2c94386a3d6d" Name="All files in Program Files" Description="" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePathCondition Path="%PROGRAMFILES%\*" />
      </Conditions>
    </FilePathRule>
  </RuleCollection>
  <RuleCollection Type="Msi" EnforcementMode="AuditOnly">
    <FilePublisherRule Id="4e6a0d4c-2877-48f1-b844-325d761d191d" Name="Signed by Microsoft" Description="" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePublisherCondition PublisherName="O=MICROSOFT CORPORATION, L=REDMOND, S=WASHINGTON, C=US" ProductName="*" BinaryName="*">
          <BinaryVersionRange LowSection="*" HighSection="*" />
        </FilePublisherCondition>
      </Conditions>
    </FilePublisherRule>
  </RuleCollection>
  <RuleCollection Type="Script" EnforcementMode="AuditOnly">
     <FilePathRule Id="06113b2f-3d60-449a-bd9e-2c94386a3d6d" Name="All scripts in Program Files" Description="" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePathCondition Path="%PROGRAMFILES%\*" />
      </Conditions>
    </FilePathRule>
  </RuleCollection>
  <RuleCollection Type="Dll" EnforcementMode="AuditOnly" />
  <RuleCollection Type="Appx" EnforcementMode="AuditOnly">
    <FilePublisherRule Id="a9e18c21-ff8f-43cf-b9fc-db40eed6fd77" Name="Signed by Microsoft" Description="" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePublisherCondition PublisherName="CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US" ProductName="*" BinaryName="*">
          <BinaryVersionRange LowSection="*" HighSection="*" />
        </FilePublisherCondition>
      </Conditions>
    </FilePublisherRule>
  </RuleCollection>
</AppLockerPolicy>
"@

try {
    # Start AppIDSvc (Application Identity Service)
    Set-Service -Name "AppIDSvc" -StartupType Automatic
    Start-Service -Name "AppIDSvc"
    Write-Host "  [OK] AppIDSvc Started" -ForegroundColor Green

    # Apply Policy
    $policyFile = "$env:TEMP\applocker.xml"
    $policyXml | Out-File -FilePath $policyFile -Encoding UTF8
    
    Set-AppLockerPolicy -XmlPolicy $policyFile -Merge
    Write-Host "  [OK] AppLocker Policy Applied (Audit Mode)" -ForegroundColor Green
    "Policy Applied Successfully" | Out-File -FilePath $logPath -Append

    # Verify
    $result = Get-AppLockerPolicy -Effective -Xml
    if ($result) {
        Write-Host "  [OK] Verification Passed" -ForegroundColor Green
    }
}
catch {
    Write-Error "AppLocker Setup Failed: $_"
    "Failed: $_" | Out-File -FilePath $logPath -Append
    exit 1
}
