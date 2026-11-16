@echo off
setlocal

REM Thunder Takeover Guard launcher
REM
REM Usage (run from a terminal; the .ps1 self-elevates when needed):
REM   Run-ThunderTakeoverGuard.cmd -DryRun      Preview only, no changes
REM   Run-ThunderTakeoverGuard.cmd -Apply       Apply now (stops/disables service+drivers)
REM   Run-ThunderTakeoverGuard.cmd -InstallTask Apply + install logon task
REM   Run-ThunderTakeoverGuard.cmd -Status      Show current state
REM   Run-ThunderTakeoverGuard.cmd -RemoveTask  Remove the logon task
REM
REM Optional: -DeleteServices -RemoveBHO -RemoveAgentCom -KeepFiles -Quiet

set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS%" (
    echo Windows PowerShell not found: "%PS%"
    exit /b 1
)

"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0ThunderTakeoverGuard.ps1" %*
set "RC=%ERRORLEVEL%"
endlocal & exit /b %RC%