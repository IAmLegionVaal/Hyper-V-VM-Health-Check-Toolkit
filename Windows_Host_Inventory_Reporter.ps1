#requires -Version 5.1
<#
.SYNOPSIS
    Windows Host Inventory Reporter.
.DESCRIPTION
    Read-only Windows host inventory reporter for support review.
#>
[CmdletBinding()]
param([string]$OutputPath)
$RunStamp = Get-Date -Format 'yyyyMMdd_HHmmss'
if ([string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Host_Inventory_Reports' }
New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
function Export-Data { param($Name,$Data) $Data | Export-Csv (Join-Path $OutputPath "$Name.csv") -NoTypeInformation -Encoding UTF8; $Data | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $OutputPath "$Name.json") -Encoding UTF8 }
$os = Get-CimInstance Win32_OperatingSystem
$cs = Get-CimInstance Win32_ComputerSystem
$bios = Get-CimInstance Win32_BIOS
$summary = [PSCustomObject]@{Computer=$env:COMPUTERNAME;OS=$os.Caption;Build=$os.BuildNumber;LastBoot=$os.LastBootUpTime;Manufacturer=$cs.Manufacturer;Model=$cs.Model;MemoryGB=[math]::Round($cs.TotalPhysicalMemory/1GB,2);Serial=$bios.SerialNumber;Generated=Get-Date}
$disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | Select-Object DeviceID,VolumeName,FileSystem,@{n='SizeGB';e={[math]::Round($_.Size/1GB,2)}},@{n='FreeGB';e={[math]::Round($_.FreeSpace/1GB,2)}}
$nics = Get-NetAdapter -ErrorAction SilentlyContinue | Select-Object Name,Status,LinkSpeed,MacAddress,InterfaceDescription
Export-Data "host_summary_$RunStamp" @($summary)
Export-Data "disk_summary_$RunStamp" $disks
Export-Data "network_adapters_$RunStamp" $nics
$html = "<h1>Windows Host Inventory - $env:COMPUTERNAME</h1><p>Generated $(Get-Date)</p><h2>Summary</h2>$(@($summary)|ConvertTo-Html -Fragment)<h2>Disks</h2>$($disks|ConvertTo-Html -Fragment)<h2>Network Adapters</h2>$($nics|ConvertTo-Html -Fragment)"
$html | ConvertTo-Html -Title 'Windows Host Inventory' | Set-Content (Join-Path $OutputPath "host_inventory_$RunStamp.html") -Encoding UTF8
$summary | Format-List
Write-Host "Reports saved to: $OutputPath" -ForegroundColor Green
Start-Process explorer.exe -ArgumentList "`"$OutputPath`"" -ErrorAction SilentlyContinue
