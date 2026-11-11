# Install the local FPT production API scan at fixed Vietnam time slots.
# Run once from the Windows account authenticated with GitHub CLI.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$node = (Get-Command node -ErrorAction Stop).Source
Get-Command gh -ErrorAction Stop | Out-Null
$action = New-ScheduledTaskAction -Execute $node `
    -Argument ('"' + (Join-Path $PSScriptRoot 'scan_fpt_local.mjs') + '" --publish') `
    -WorkingDirectory $repo
$today = (Get-Date).Date
$triggers = @(0, 3, 6, 9, 12, 15, 18, 21 | ForEach-Object {
    New-ScheduledTaskTrigger -Daily -At ($today.AddHours($_))
})
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -WakeToRun `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 10) -MultipleInstances IgnoreNew `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
$principal = New-ScheduledTaskPrincipal `
    -UserId ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name) `
    -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName 'FPT Shop Live Scan' -Action $action `
    -Trigger $triggers -Settings $settings -Principal $principal -Force | Out-Null
Get-ScheduledTaskInfo -TaskName 'FPT Shop Live Scan' |
    Select-Object LastRunTime, NextRunTime, LastTaskResult
