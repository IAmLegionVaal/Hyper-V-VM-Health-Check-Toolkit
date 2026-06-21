[CmdletBinding()]
param(
    [string]$VMName,
    [ValidateSet('Start','Stop','Restart','Resume','Save','TurnOff')]
    [string]$Action,
    [switch]$Force,
    [switch]$RestartVmms,
    [string[]]$EnableIntegrationService,
    [switch]$DryRun,
    [switch]$Yes,
    [string]$OutputPath = (Join-Path $env:ProgramData 'HyperVVMRepair')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:Failures = 0
$script:VerificationFailures = 0
$script:Actions = 0

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if ($env:OS -ne 'Windows_NT') { Write-Error 'This tool requires Windows.'; exit 3 }
if (-not ($Action -or $RestartVmms -or $EnableIntegrationService)) { Write-Error 'Choose at least one repair action.'; exit 2 }
if (($Action -or $EnableIntegrationService) -and [string]::IsNullOrWhiteSpace($VMName)) { Write-Error '-VMName is required for VM actions.'; exit 2 }
if ($Action -eq 'TurnOff' -and -not $Force) { Write-Error 'TurnOff requires -Force because it is equivalent to removing power.'; exit 2 }
if (-not $DryRun -and -not (Test-Administrator)) { Write-Error 'Run from an elevated PowerShell session.'; exit 4 }
Import-Module Hyper-V -ErrorAction Stop
if ($VMName) { Get-VM -Name $VMName -ErrorAction Stop | Out-Null }

$runPath = Join-Path $OutputPath (Get-Date -Format 'yyyyMMdd_HHmmss')
$backupPath = Join-Path $runPath 'backup'
New-Item -ItemType Directory -Path $backupPath -Force | Out-Null
$logPath = Join-Path $runPath 'repair.log'
$beforePath = Join-Path $runPath 'before.json'
$afterPath = Join-Path $runPath 'after.json'

function Write-Log([string]$Message) { "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message" | Tee-Object -FilePath $logPath -Append }
function Invoke-RepairAction([string]$Description,[scriptblock]$Script) {
    $script:Actions++
    Write-Log "ACTION: $Description"
    if ($DryRun) { Write-Log "DRY-RUN: $Description"; return }
    try {
        $result = & $Script 2>&1
        if ($null -ne $result) { $result | Out-String | Add-Content $logPath }
        Write-Log "SUCCESS: $Description"
    } catch {
        $script:Failures++
        Write-Log "FAILED: $Description - $($_.Exception.Message)"
    }
}
function Get-RepairState {
    [pscustomobject]@{
        Collected = Get-Date
        Vmms = Get-Service vmms -ErrorAction SilentlyContinue | Select-Object Name,Status,StartType
        VM = if ($VMName) { Get-VM -Name $VMName | Select-Object Name,State,Status,Uptime,AutomaticStartAction,AutomaticStopAction,CheckpointType } else { $null }
        IntegrationServices = if ($VMName) { @(Get-VMIntegrationService -VMName $VMName | Select-Object Name,Enabled,PrimaryStatusDescription,SecondaryStatusDescription) } else { @() }
        NetworkAdapters = if ($VMName) { @(Get-VMNetworkAdapter -VMName $VMName | Select-Object Name,SwitchName,Status,MacAddress,IPAddresses) } else { @() }
        HardDisks = if ($VMName) { @(Get-VMHardDiskDrive -VMName $VMName | Select-Object ControllerType,ControllerNumber,ControllerLocation,Path) } else { @() }
    }
}

Get-RepairState | ConvertTo-Json -Depth 8 | Set-Content $beforePath -Encoding UTF8
if ($VMName) {
    Get-VM -Name $VMName | Export-Clixml (Join-Path $backupPath 'vm.xml')
    Get-VMIntegrationService -VMName $VMName | Export-Clixml (Join-Path $backupPath 'integration-services.xml')
    Get-VMNetworkAdapter -VMName $VMName | Export-Clixml (Join-Path $backupPath 'network-adapters.xml')
    Get-VMHardDiskDrive -VMName $VMName | Export-Clixml (Join-Path $backupPath 'hard-disks.xml')
}

if (-not $DryRun -and -not $Yes) {
    if ((Read-Host 'Apply the selected Hyper-V repairs? Type YES') -cne 'YES') { Write-Log 'Repair cancelled.'; exit 10 }
}

if ($RestartVmms) {
    Invoke-RepairAction 'Restarting Hyper-V Virtual Machine Management service' { Restart-Service vmms -Force; (Get-Service vmms).WaitForStatus('Running',[TimeSpan]::FromSeconds(30)) }
}
if ($Action) {
    switch ($Action) {
        'Start'   { Invoke-RepairAction "Starting VM $VMName" { Start-VM -Name $VMName | Out-Null } }
        'Stop'    { Invoke-RepairAction "Requesting graceful shutdown of VM $VMName" { if ($Force) { Stop-VM -Name $VMName -Force } else { Stop-VM -Name $VMName } } }
        'Restart' { Invoke-RepairAction "Restarting VM $VMName" { Restart-VM -Name $VMName -Force:$Force } }
        'Resume'  { Invoke-RepairAction "Resuming VM $VMName" { Resume-VM -Name $VMName } }
        'Save'    { Invoke-RepairAction "Saving VM $VMName" { Save-VM -Name $VMName } }
        'TurnOff' { Invoke-RepairAction "Turning off VM $VMName" { Stop-VM -Name $VMName -TurnOff -Force } }
    }
}
foreach ($serviceName in @($EnableIntegrationService)) {
    Invoke-RepairAction "Enabling integration service '$serviceName' on $VMName" { Enable-VMIntegrationService -VMName $VMName -Name $serviceName }
}

if (-not $DryRun) { Start-Sleep -Seconds 2 }
$state = Get-RepairState
$state | ConvertTo-Json -Depth 8 | Set-Content $afterPath -Encoding UTF8
if ($RestartVmms -and (Get-Service vmms).Status -ne 'Running') { $script:VerificationFailures++; Write-Log 'VERIFY FAILED: vmms is not running.' }
if ($Action -in @('Start','Restart','Resume') -and (Get-VM -Name $VMName).State -ne 'Running') { $script:VerificationFailures++; Write-Log "VERIFY FAILED: $VMName is not running." }
if ($Action -in @('Stop','TurnOff') -and (Get-VM -Name $VMName).State -ne 'Off') { $script:VerificationFailures++; Write-Log "VERIFY FAILED: $VMName is not off." }
if ($Action -eq 'Save' -and (Get-VM -Name $VMName).State -ne 'Saved') { $script:VerificationFailures++; Write-Log "VERIFY FAILED: $VMName is not saved." }
foreach ($serviceName in @($EnableIntegrationService)) {
    $integration = Get-VMIntegrationService -VMName $VMName -Name $serviceName -ErrorAction SilentlyContinue
    if (-not $integration -or -not $integration.Enabled) { $script:VerificationFailures++; Write-Log "VERIFY FAILED: integration service '$serviceName' is not enabled." }
}

if ($script:Failures -gt 0) { exit 20 }
if ($script:VerificationFailures -gt 0) { exit 30 }
Write-Log "Repair completed. Actions: $script:Actions"
exit 0
