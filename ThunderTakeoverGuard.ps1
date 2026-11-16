<#
.SYNOPSIS
    Disable Xunlei/Thunder browser download takeover and remove the Thunder browser extension payload.

.DESCRIPTION
    Thunder installs a Windows service (XLServicePlatform) and kernel drivers (XLWFP, XLGuard)
    that intercept plain-HTTP browser downloads. This script:
      - stops and disables the service/drivers
      - renames the active service/plugin/driver binaries (reversible; reboot may be required)
      - removes Chrome/Edge external-extension registry entries and native-messaging hosts
      - optionally removes the IE BHO and ThunderAgent COM registration
      - can install a logon scheduled task that re-applies the changes

    Run with -DryRun first. Changes require Administrator.

.PARAMETER Apply
    Apply the hardening now.

.PARAMETER DryRun
    Preview only; no changes are made.

.PARAMETER Status
    Show current service/driver/file/extension/task state.

.PARAMETER InstallTask
    Apply now and register a logon scheduled task that re-applies at every logon.

.PARAMETER RemoveTask
    Remove the logon scheduled task.

.PARAMETER DeleteServices
    Also delete the service/driver registry keys (stronger; Thunder may recreate them).

.PARAMETER KeepFiles
    Do not rename the service/plugin/driver binaries.

.PARAMETER RemoveBHO
    Also remove the IE XunleiBHO registration.

.PARAMETER RemoveAgentCom
    Also remove the ThunderAgent COM registration.

.PARAMETER NoElevate
    Do not self-elevate (used by the scheduled task and for read-only testing).

.PARAMETER Quiet
    Log to file only; no console output.

.EXAMPLE
    .\Run-ThunderTakeoverGuard.cmd -DryRun
    .\Run-ThunderTakeoverGuard.cmd -Apply
    .\Run-ThunderTakeoverGuard.cmd -InstallTask
    .\Run-ThunderTakeoverGuard.cmd -Status
#>

[CmdletBinding()]
param(
    [switch]$Apply,
    [switch]$DryRun,
    [switch]$Status,
    [switch]$InstallTask,
    [switch]$RemoveTask,
    [switch]$DeleteServices,
    [switch]$KeepFiles,
    [switch]$RemoveBHO,
    [switch]$RemoveAgentCom,
    [switch]$NoElevate,
    [switch]$Quiet
)

$ErrorActionPreference = 'Continue'

# Booleans derived from switches (avoid assigning to SwitchParameter variables).
$DryRunMode          = $DryRun.IsPresent
$DeleteServicesMode  = $DeleteServices.IsPresent
$KeepFilesMode       = $KeepFiles.IsPresent
$RemoveBHOMode       = $RemoveBHO.IsPresent
$RemoveAgentComMode  = $RemoveAgentCom.IsPresent
$QuietMode           = $Quiet.IsPresent

$ScriptVersion = '1.0'
$TaskName      = 'ThunderTakeoverGuard'
$LogDir        = Join-Path $env:ProgramData 'ThunderTakeoverGuard'
$LogFile       = Join-Path $LogDir 'guard.log'
$BackupDir     = Join-Path $LogDir ('backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))

$ServiceNames = @(
    [pscustomobject]@{ Name = 'XLServicePlatform'; Kind = 'Service'; Label = 'Xunlei download base service' },
    [pscustomobject]@{ Name = 'XLWFP';            Kind = 'Driver';  Label = 'Xunlei WFP driver' },
    [pscustomobject]@{ Name = 'XLGuard';          Kind = 'Driver';  Label = 'Xunlei Guard driver' }
)

$DriverFiles = @(
    (Join-Path $env:SystemRoot 'System32\drivers\XLWFP.sys'),
    (Join-Path $env:SystemRoot 'System32\drivers\XLGuard.sys')
)

$ServiceFiles = @(
    'C:\Program Files (x86)\Common Files\Thunder Network\ServicePlatform\XLSP.dll',
    'C:\Program Files (x86)\Common Files\Thunder Network\ServicePlatform\Plugins\XLWFPDownload.dll',
    'C:\Program Files (x86)\Common Files\Thunder Network\ServicePlatform\Plugins\XLWFPManager.dll'
)

# Thunder-related Chrome/Edge extension IDs (the first one is the installed external extension).
$ExtIds = @(
    'ncennffkjdiamlpmcbajkmaiiiddgioo',
    'mbbgjcjagcaldbmlmepgbdhkphmmgpmm',
    'popomkonnjgcdagdhgcpcekbdeoibglc',
    'nabfhfficpbohjlpjhcggljgkgpibhpc'
)

$NativeHosts = @('com.xunlei.thunder', 'com.thunder.chrome.host')

$BrowserRoots = @(
    [pscustomobject]@{
        Name       = 'Chrome'
        ExtHklm    = 'HKLM\SOFTWARE\Google\Chrome\Extensions'
        ExtHklmWow = 'HKLM\SOFTWARE\WOW6432Node\Google\Chrome\Extensions'
        ExtHkcu    = 'HKCU\SOFTWARE\Google\Chrome\Extensions'
        NmhHkcu    = 'HKCU\Software\Google\Chrome\NativeMessagingHosts'
        NmhHklm    = 'HKLM\Software\Google\Chrome\NativeMessagingHosts'
        NmhHklmWow = 'HKLM\SOFTWARE\WOW6432Node\Google\Chrome\NativeMessagingHosts'
        Data       = (Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data')
    },
    [pscustomobject]@{
        Name       = 'Edge'
        ExtHklm    = 'HKLM\SOFTWARE\Microsoft\Edge\Extensions'
        ExtHklmWow = 'HKLM\SOFTWARE\WOW6432Node\Microsoft\Edge\Extensions'
        ExtHkcu    = 'HKCU\SOFTWARE\Microsoft\Edge\Extensions'
        NmhHkcu    = 'HKCU\Software\Microsoft\Edge\NativeMessagingHosts'
        NmhHklm    = 'HKLM\Software\Microsoft\Edge\NativeMessagingHosts'
        NmhHklmWow = 'HKLM\SOFTWARE\WOW6432Node\Microsoft\Edge\NativeMessagingHosts'
        Data       = (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data')
    }
)

function Test-Admin {
    try {
        $identity  = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = 'INFO'
    )
    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    try {
        if (-not (Test-Path -LiteralPath $LogDir)) {
            New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
        }
        Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
    } catch { }
    if (-not $QuietMode) { Write-Host $line }
}

function Invoke-Sc {
    param([string[]]$Arguments)
    $out = & sc.exe @Arguments 2>&1
    return [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output   = (($out | ForEach-Object { "$_" }) -join "`n")
    }
}

function Test-RegKey {
    param([string]$Key)
    & reg.exe query $Key *> $null
    return ($LASTEXITCODE -eq 0)
}

function Backup-RegKey {
    param([string]$Key, [string]$Name)
    if ($DryRunMode) { return }
    if (-not (Test-RegKey $Key)) { return }
    if (-not (Test-Path -LiteralPath $BackupDir)) {
        New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    }
    $safe = ($Name -replace '[^A-Za-z0-9_.-]', '_')
    $file = Join-Path $BackupDir ($safe + '.reg')
    & reg.exe export $Key $file /y *> $null
    if ($LASTEXITCODE -eq 0) {
        Write-Log "Backed up registry $Key -> $file"
    } else {
        Write-Log "Backup failed for $Key" 'WARN'
    }
}

function Remove-RegKey {
    param([string]$Key, [string]$Name)
    if (-not (Test-RegKey $Key)) { return }
    if ($DryRunMode) {
        Write-Log "[DRY] Would delete registry key $Key"
        return
    }
    Backup-RegKey $Key $Name
    & reg.exe delete $Key /f *> $null
    if ($LASTEXITCODE -eq 0) {
        Write-Log "Deleted registry key $Key"
    } else {
        Write-Log "Failed to delete registry key $Key" 'WARN'
    }
}

function Add-PendingRename {
    param([string]$Source, [string]$Destination)
    if ($DryRunMode) {
        Write-Log "[DRY] Would schedule reboot rename: $Source -> $Destination"
        return
    }
    $regPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
    $src = '\??\' + $Source
    $dst = '\??\' + $Destination
    $existing = $null
    try {
        $existing = (Get-ItemProperty -Path $regPath -Name 'PendingFileRenameOperations' -ErrorAction Stop).PendingFileRenameOperations
    } catch { }
    $list = New-Object 'System.Collections.Generic.List[string]'
    if ($existing) { foreach ($x in [string[]]$existing) { $list.Add($x) } }
    $list.Add($src)
    $list.Add($dst)
    New-ItemProperty -Path $regPath -Name 'PendingFileRenameOperations' -Value ([string[]]$list) -PropertyType MultiString -Force | Out-Null
    Write-Log "Scheduled reboot rename: $Source -> $Destination"
}

function Move-FileSafe {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $dest = $Path + '.thunder-guard-disabled'
    if (Test-Path -LiteralPath $dest) {
        $dest = $Path + '.thunder-guard-disabled-' + (Get-Date -Format 'yyyyMMddHHmmss')
    }
    if ($DryRunMode) {
        Write-Log "[DRY] Would rename file $Path -> $dest"
        return
    }
    try {
        Move-Item -LiteralPath $Path -Destination $dest -Force -ErrorAction Stop
        Write-Log "Renamed file $Path -> $dest"
    } catch {
        Write-Log "File is locked; scheduling rename on reboot: $Path" 'WARN'
        Add-PendingRename -Source $Path -Destination $dest
    }
}

function Remove-FileSafe {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    if ($DryRunMode) {
        Write-Log "[DRY] Would remove file $Path"
        return
    }
    try {
        Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
        Write-Log "Removed file $Path"
    } catch {
        Write-Log "Could not remove file $Path" 'WARN'
    }
}

function Remove-DirectorySafe {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    if ($DryRunMode) {
        Write-Log "[DRY] Would remove directory $Path"
        return
    }
    try {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
        Write-Log "Removed directory $Path"
    } catch {
        Write-Log "Could not remove directory (browser may be running): $Path" 'WARN'
    }
}

function Get-ServiceState {
    param([string]$Name)
    $svc = Get-CimInstance -ClassName Win32_Service -Filter "Name='$Name'" -ErrorAction SilentlyContinue
    if ($svc) {
        return [pscustomobject]@{ Name = $Name; Kind = 'Service'; State = $svc.State; StartMode = $svc.StartMode }
    }
    $drv = Get-CimInstance -ClassName Win32_SystemDriver -Filter "Name='$Name'" -ErrorAction SilentlyContinue
    if ($drv) {
        return [pscustomobject]@{ Name = $Name; Kind = 'Driver'; State = $drv.State; StartMode = $drv.StartMode }
    }
    return $null
}

function Disable-ServiceItem {
    param([pscustomobject]$Item)
    $info = Get-ServiceState $Item.Name
    if (-not $info) {
        Write-Log ("{0} ({1}) not found" -f $Item.Name, $Item.Label)
        return
    }
    Write-Log ("{0} ({1}): state={2}, start={3}" -f $Item.Name, $Item.Label, $info.State, $info.StartMode)

    if ($DryRunMode) {
        Write-Log ("[DRY] Would stop {0} and set start=disabled" -f $Item.Name)
        if ($DeleteServicesMode) { Write-Log ("[DRY] Would delete {0}" -f $Item.Name) }
        return
    }

    $stop = Invoke-Sc @('stop', $Item.Name)
    if ($stop.ExitCode -eq 0) {
        Write-Log ("Stopped {0}" -f $Item.Name)
    } else {
        Write-Log ("Stop {0} returned {1}: {2}" -f $Item.Name, $stop.ExitCode, $stop.Output) 'WARN'
    }

    $cfg = Invoke-Sc @('config', $Item.Name, 'start=', 'disabled')
    if ($cfg.ExitCode -eq 0) {
        Write-Log ("Set {0} start=disabled" -f $Item.Name)
    } else {
        Write-Log ("config {0} failed: {1}" -f $Item.Name, $cfg.Output) 'WARN'
    }

    if ($DeleteServicesMode) {
        $del = Invoke-Sc @('delete', $Item.Name)
        if ($del.ExitCode -eq 0) {
            Write-Log ("Deleted {0}" -f $Item.Name)
        } else {
            Write-Log ("delete {0} returned {1}: {2}" -f $Item.Name, $del.ExitCode, $del.Output) 'WARN'
        }
    }
}

function Remove-ExtensionArtifacts {
    Write-Log 'Removing Thunder browser-extension registrations and native-messaging hosts'

    foreach ($b in $BrowserRoots) {
        foreach ($id in $ExtIds) {
            Remove-RegKey ($b.ExtHklm + '\' + $id)    ($b.Name + '_ext_hklm_' + $id)
            Remove-RegKey ($b.ExtHklmWow + '\' + $id) ($b.Name + '_ext_hklm_wow_' + $id)
            Remove-RegKey ($b.ExtHkcu + '\' + $id)    ($b.Name + '_ext_hkcu_' + $id)
        }
        foreach ($h in $NativeHosts) {
            Remove-RegKey ($b.NmhHkcu + '\' + $h)    ($b.Name + '_nmh_hkcu_' + $h)
            Remove-RegKey ($b.NmhHklm + '\' + $h)    ($b.Name + '_nmh_hklm_' + $h)
            Remove-RegKey ($b.NmhHklmWow + '\' + $h) ($b.Name + '_nmh_hklm_wow_' + $h)
        }
    }

    foreach ($h in $NativeHosts) {
        Remove-RegKey ('HKCU\Software\Mozilla\NativeMessagingHosts\' + $h) ('Firefox_nmh_hkcu_' + $h)
        Remove-RegKey ('HKLM\SOFTWARE\Mozilla\NativeMessagingHosts\' + $h) ('Firefox_nmh_hklm_' + $h)
    }

    foreach ($b in $BrowserRoots) {
        if (-not (Test-Path -LiteralPath $b.Data)) { continue }
        $profiles = Get-ChildItem -LiteralPath $b.Data -Directory -ErrorAction SilentlyContinue
        foreach ($p in $profiles) {
            $extDir = Join-Path $p.FullName 'Extensions'
            if (-not (Test-Path -LiteralPath $extDir)) { continue }
            foreach ($id in $ExtIds) {
                Remove-DirectorySafe (Join-Path $extDir $id)
            }
        }
    }

    Remove-FileSafe (Join-Path $env:LOCALAPPDATA 'ChromeExtensionCache\xl_ext_chrome.crx')
    Move-FileSafe 'C:\Program Files (x86)\Common Files\Thunder Network\bho\xl_ext_chrome\com.xunlei.thunder.json'
    Move-FileSafe 'C:\Program Files (x86)\Common Files\Thunder Network\bho\xl_ext_chrome\xunlei.firefox.json'

    if ($RemoveBHOMode) {
        Remove-RegKey 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Browser Helper Objects\{004B0726-A010-4ABF-8556-FCDB7F1FCA1E}' 'XunleiBHO_BHO'
        Remove-RegKey 'HKLM\SOFTWARE\Classes\CLSID\{004B0726-A010-4ABF-8556-FCDB7F1FCA1E}' 'XunleiBHO_CLSID_HKLM'
        Remove-RegKey 'HKCU\SOFTWARE\Classes\CLSID\{004B0726-A010-4ABF-8556-FCDB7F1FCA1E}' 'XunleiBHO_CLSID_HKCU'
    }

    if ($RemoveAgentComMode) {
        Remove-RegKey 'HKCR\ThunderAgent.Agent' 'ThunderAgent_Agent'
        Remove-RegKey 'HKCR\ThunderAgent.Agent.1' 'ThunderAgent_Agent_1'
        Remove-RegKey 'HKCR\CLSID\{485463B7-8FB2-4B3B-B29B-8B919B0EACCE}' 'ThunderAgent_CLSID'
    }
}

function Show-Status {
    Write-Host ''
    Write-Host '=== Services / drivers ==='
    foreach ($s in $ServiceNames) {
        $info = Get-ServiceState $s.Name
        if ($info) {
            Write-Host ('{0,-18} {1,-8} state={2,-10} start={3}' -f $info.Name, $info.Kind, $info.State, $info.StartMode)
        } else {
            Write-Host ('{0,-18} not found' -f $s.Name)
        }
    }

    Write-Host ''
    Write-Host '=== Files ==='
    foreach ($f in ($DriverFiles + $ServiceFiles)) {
        $exists = Test-Path -LiteralPath $f
        $renamed = @(Get-ChildItem -Path ($f + '*thunder-guard-disabled*') -ErrorAction SilentlyContinue).Count -gt 0
        Write-Host ('{0} exists={1} renamed={2}' -f $f, $exists, $renamed)
    }

    Write-Host ''
    Write-Host '=== Extension registry ==='
    foreach ($b in $BrowserRoots) {
        foreach ($id in $ExtIds) {
            $k1 = $b.ExtHklm + '\' + $id
            $k2 = $b.ExtHklmWow + '\' + $id
            $k3 = $b.ExtHkcu + '\' + $id
            if ((Test-RegKey $k1) -or (Test-RegKey $k2) -or (Test-RegKey $k3)) {
                Write-Host ('{0} {1}: present (HKLM={2}, WOW={3}, HKCU={4})' -f $b.Name, $id, (Test-RegKey $k1), (Test-RegKey $k2), (Test-RegKey $k3))
            }
        }
        foreach ($h in $NativeHosts) {
            $k1 = $b.NmhHkcu + '\' + $h
            $k2 = $b.NmhHklm + '\' + $h
            $k3 = $b.NmhHklmWow + '\' + $h
            if ((Test-RegKey $k1) -or (Test-RegKey $k2) -or (Test-RegKey $k3)) {
                Write-Host ('{0} native host {1}: present (HKCU={2}, HKLM={3}, WOW={4})' -f $b.Name, $h, (Test-RegKey $k1), (Test-RegKey $k2), (Test-RegKey $k3))
            }
        }
    }

    Write-Host ''
    Write-Host '=== Extension files ==='
    foreach ($b in $BrowserRoots) {
        if (-not (Test-Path -LiteralPath $b.Data)) { continue }
        $profiles = Get-ChildItem -LiteralPath $b.Data -Directory -ErrorAction SilentlyContinue
        foreach ($p in $profiles) {
            foreach ($id in $ExtIds) {
                $d = Join-Path $p.FullName ('Extensions\' + $id)
                if (Test-Path -LiteralPath $d) { Write-Host ('{0} exists' -f $d) }
            }
        }
    }
    $crx = Join-Path $env:LOCALAPPDATA 'ChromeExtensionCache\xl_ext_chrome.crx'
    if (Test-Path -LiteralPath $crx) { Write-Host ('{0} exists' -f $crx) }
    $manifests = @(
        'C:\Program Files (x86)\Common Files\Thunder Network\bho\xl_ext_chrome\com.xunlei.thunder.json',
        'C:\Program Files (x86)\Common Files\Thunder Network\bho\xl_ext_chrome\xunlei.firefox.json'
    )
    foreach ($m in $manifests) {
        if (Test-Path -LiteralPath $m) { Write-Host ('{0} exists' -f $m) }
    }

    Write-Host ''
    Write-Host '=== Scheduled task ==='
    $task = $null
    try { $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue } catch { }
    if ($task) {
        Write-Host ('{0}: state={1}' -f $TaskName, $task.State)
    } else {
        Write-Host ('{0}: not installed' -f $TaskName)
    }

    Write-Host ''
    Write-Host ('Log: {0}' -f $LogFile)
    $latest = Get-ChildItem -Path $LogDir -Directory -Filter 'backup-*' -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
    if ($latest) {
        Write-Host ('Latest backup: {0}' -f $latest.FullName)
    } else {
        Write-Host 'Latest backup: none'
    }
}

function Install-GuardTask {
    $psExe     = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $scriptPath = $PSCommandPath
    $actionArgs = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -Apply -Quiet -NoElevate' -f $scriptPath

    if ($DryRunMode) {
        Write-Log ('[DRY] Would register scheduled task {0}' -f $TaskName)
        return
    }

    $action = New-ScheduledTaskAction -Execute $psExe -Argument $actionArgs -WorkingDirectory (Split-Path -Parent $scriptPath)
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    try { $trigger.Delay = 'PT15S' } catch { }

    $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    try {
        $principal = New-ScheduledTaskPrincipal -UserId $sid -LogonType Interactive -RunLevel Highest
    } catch {
        $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
    }

    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 10)

    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description 'Disable Xunlei XLServicePlatform/XLWFP/XLGuard takeover and Thunder browser extension' -Force | Out-Null
    Write-Log ('Registered scheduled task {0} (at logon, +15s, highest privileges)' -f $TaskName)
}

function Remove-GuardTask {
    if ($DryRunMode) {
        Write-Log ('[DRY] Would remove scheduled task {0}' -f $TaskName)
        return
    }
    $task = $null
    try { $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue } catch { }
    if ($task) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
        Write-Log ('Removed scheduled task {0}' -f $TaskName)
    } else {
        Write-Log ('Scheduled task {0} not present' -f $TaskName)
    }
}

function Invoke-Apply {
    Write-Log ('Thunder takeover guard v{0} starting (DryRun={1})' -f $ScriptVersion, [bool]$DryRunMode)

    foreach ($s in $ServiceNames) {
        Disable-ServiceItem $s
    }

    if (-not $KeepFilesMode) {
        Write-Log 'Renaming active service/plugin/driver binaries'
        foreach ($f in ($DriverFiles + $ServiceFiles)) {
            Move-FileSafe $f
        }
    } else {
        Write-Log 'KeepFiles specified; service/plugin/driver binaries are not renamed'
    }

    Remove-ExtensionArtifacts

    if ($DryRunMode) {
        Write-Log 'Dry run complete; no changes were made.'
    } else {
        Write-Log 'Apply complete. Reboot is required to finish driver/service neutralization.'
        $running = @()
        foreach ($n in @('XLWFP', 'XLGuard', 'XLServicePlatform')) {
            $st = Get-ServiceState $n
            if ($st -and $st.State -eq 'Running') { $running += $n }
        }
        if ($running.Count -gt 0) {
            Write-Log ('Still running: {0}. Reboot to unload them.' -f ($running -join ', ')) 'WARN'
        }
        Write-Log ('Backups: {0}' -f $BackupDir)
    }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

$doApply       = $Apply.IsPresent
$doDryRun      = $DryRun.IsPresent
$doStatus      = $Status.IsPresent
$doInstallTask = $InstallTask.IsPresent
$doRemoveTask  = $RemoveTask.IsPresent

if (-not ($doApply -or $doDryRun -or $doStatus -or $doInstallTask -or $doRemoveTask)) {
    Write-Host 'No action specified. Showing status. Use -DryRun to preview or -Apply to harden.'
    $doStatus = $true
}

$needsAdmin = ($doApply -or $doInstallTask -or $doRemoveTask) -and (-not $doDryRun)
if ($needsAdmin -and (-not (Test-Admin)) -and (-not $NoElevate)) {
    $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $argString = '-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $PSCommandPath
    foreach ($k in $PSBoundParameters.Keys) {
        if ($k -eq 'NoElevate') { continue }
        $v = $PSBoundParameters[$k]
        if ($v -is [switch]) {
            if ($v.IsPresent) { $argString += (' -{0}' -f $k) }
        } elseif ($v -is [bool]) {
            if ($v) { $argString += (' -{0}' -f $k) }
        } elseif ($null -ne $v) {
            $argString += (' -{0} "{1}"' -f $k, $v)
        }
    }
    try {
        $p = Start-Process -FilePath $psExe -Verb RunAs -ArgumentList $argString -Wait -PassThru
        exit $p.ExitCode
    } catch {
        Write-Host 'Elevation was cancelled or failed.' -ForegroundColor Red
        exit 1
    }
}

if ($needsAdmin -and (-not (Test-Admin))) {
    Write-Host 'This action requires Administrator. Run the .cmd launcher and accept the UAC prompt. Use -NoElevate only for -DryRun/-Status.' -ForegroundColor Red
    exit 1
}

if ($doStatus) {
    Show-Status
    exit 0
}

if ($doRemoveTask) {
    Remove-GuardTask
    exit 0
}

if ($doInstallTask) {
    Invoke-Apply
    Install-GuardTask
    exit 0
}

if ($doApply -or $doDryRun) {
    Invoke-Apply
    exit 0
}
