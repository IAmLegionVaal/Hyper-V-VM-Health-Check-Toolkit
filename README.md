# Hyper-V VM Health Check Toolkit

A PowerShell toolkit for Windows host inventory and guarded Hyper-V virtual-machine repair.

## Existing inventory script

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\Windows_Host_Inventory_Reporter.ps1
```

The existing script remains read-only and reports local host operating-system, hardware, disk and network context.

## Hyper-V repair script

Preview an action:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\HyperV_VM_Repair_Toolkit.ps1 -VMName 'APP01' -Action Restart -DryRun
```

Examples:

```powershell
.\HyperV_VM_Repair_Toolkit.ps1 -VMName 'APP01' -Action Start
.\HyperV_VM_Repair_Toolkit.ps1 -VMName 'APP01' -Action Stop
.\HyperV_VM_Repair_Toolkit.ps1 -VMName 'APP01' -Action Resume
.\HyperV_VM_Repair_Toolkit.ps1 -VMName 'APP01' -Action Save
.\HyperV_VM_Repair_Toolkit.ps1 -VMName 'APP01' -EnableIntegrationService 'Guest Service Interface'
.\HyperV_VM_Repair_Toolkit.ps1 -RestartVmms
```

`-Action TurnOff` requires `-Force` because it removes power from the guest.

## Repair behaviour

- Starts, stops, restarts, resumes, saves or explicitly turns off one selected VM.
- Restarts the Hyper-V Virtual Machine Management service when requested.
- Enables explicitly named VM integration services.
- Captures VM, disk, network and integration-service state before and after repair.
- Exports pre-change Hyper-V object evidence into the run backup directory.
- Supports `-DryRun`, confirmation prompts or `-Yes`, administrator checks, logs and verification.

## Safety and exit codes

VM stop, restart, save and turn-off actions can interrupt workloads. The tool does not delete VMs, checkpoints, virtual disks or switches and does not alter guest configuration automatically.

Exit codes: `0` success, `2` invalid arguments, `3` unsupported platform or feature, `4` elevation required, `10` cancelled, `20` action failure and `30` verification failure.

## Validation note

The repair script was committed and statically reviewed, but it was not runtime-tested on a Hyper-V host.

## Author

Dewald Pretorius — L2 IT Support Engineer
