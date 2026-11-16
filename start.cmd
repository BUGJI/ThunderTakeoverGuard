@echo off
setlocal EnableExtensions
title Thunder Takeover Guard 启动器

set "SCRIPT_DIR=%~dp0"
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "PS1=%SCRIPT_DIR%ThunderTakeoverGuard.ps1"

if not exist "%PS%" (
    echo [错误] 未找到 Windows PowerShell: "%PS%"
    pause & exit /b 1
)
if not exist "%PS1%" (
    echo [错误] 未找到脚本文件: "%PS1%"
    pause & exit /b 1
)

REM 带参数启动则直接透传，兼容原命令行用法
if not "%~1"=="" goto legacy

:menu
cls
echo ================================
echo    Thunder Takeover Guard
echo ================================
echo.
echo [1] 仅预览 DryRun（不改任何东西）
echo [2] 立即应用 Apply（停/禁用服务与驱动）
echo [3] 应用并安装登录任务 InstallTask
echo [4] 查看状态 Status
echo [5] 移除登录任务 RemoveTask
echo [0] 退出
echo.
choice /c 123450 /n /m "请输入数字(0-5): "

if %errorlevel%==1 goto act_dryrun
if %errorlevel%==2 goto act_apply
if %errorlevel%==3 goto act_install
if %errorlevel%==4 goto act_status
if %errorlevel%==5 goto act_removetask
if %errorlevel%==6 goto end
goto menu

:act_dryrun
set "ARGS=-DryRun"
set "EXTRA="
goto run

:act_apply
set "ARGS=-Apply"
set "EXTRA="
choice /c YN /n /m "将停止并禁用服务与驱动，确认？[Y/N]: "
if %errorlevel%==2 goto menu
goto extra

:act_install
set "ARGS=-InstallTask"
set "EXTRA="
choice /c YN /n /m "将应用更改并安装登录任务，确认？[Y/N]: "
if %errorlevel%==2 goto menu
goto extra

:act_status
set "ARGS=-Status"
set "EXTRA="
goto run

:act_removetask
set "ARGS=-RemoveTask"
set "EXTRA="
goto run

:extra
echo.
echo 附加可选参数（可多选，按 N 结束）:
echo   [A] -DeleteServices  [B] -RemoveBHO
echo   [C] -RemoveAgentCom  [D] -KeepFiles  [E] -Quiet
echo.
:extra_loop
choice /c ABCDEN /n /m "选择 [A-E, N=完成]: "
if %errorlevel%==6 goto run
if %errorlevel%==5 ( set "EXTRA=%EXTRA% -Quiet"          & goto extra_loop )
if %errorlevel%==4 ( set "EXTRA=%EXTRA% -KeepFiles"      & goto extra_loop )
if %errorlevel%==3 ( set "EXTRA=%EXTRA% -RemoveAgentCom" & goto extra_loop )
if %errorlevel%==2 ( set "EXTRA=%EXTRA% -RemoveBHO"      & goto extra_loop )
if %errorlevel%==1 ( set "EXTRA=%EXTRA% -DeleteServices" & goto extra_loop )
goto extra_loop

:run
if "%ARGS%"=="" goto menu
set "FULLARGS=%ARGS%%EXTRA%"
echo.
echo [执行] powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %FULLARGS%
echo --------------------------------
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %FULLARGS%
set "RC=%ERRORLEVEL%"
echo --------------------------------
echo [完成] 退出码: %RC%
echo.
pause
goto menu

:legacy
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
set "RC=%ERRORLEVEL%"
endlocal & exit /b %RC%

:end
endlocal
exit /b 0