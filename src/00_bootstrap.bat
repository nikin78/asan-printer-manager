@echo off
setlocal EnableExtensions DisableDelayedExpansion

rem ============================================================================
rem Asan Medical Center - Printer & Driver Migration Tool
rem Module 00: Zero-USB-Write Bootstrap Launcher
rem - Final merged .bat MUST be saved as UTF-8 (No BOM) + Windows (CRLF)
rem ============================================================================

set "ORIGINAL_SELF=%~f0"
set "STAGE_DIR=%TEMP%\AsanPrinterMgr"
set "STAGED_SELF=%STAGE_DIR%\AsanMgr_Staged_%RANDOM%_%RANDOM%.bat"

rem [WOW64 Fix] Force 64-bit CMD & PowerShell even if launched from a 32-bit process
set "CMD_EXE=%ComSpec%"
set "PS_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if defined PROCESSOR_ARCHITEW6432 (
    if exist "%SystemRoot%\Sysnative\cmd.exe" set "CMD_EXE=%SystemRoot%\Sysnative\cmd.exe"
    if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "PS_EXE=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
)

cd /d "%TEMP%" >nul 2>&1

if /i "%~1"=="__STAGED__" goto STAGED_ENTRY

if not exist "%STAGE_DIR%" mkdir "%STAGE_DIR%" >nul 2>&1
if /i not "%ORIGINAL_SELF%"=="%STAGED_SELF%" copy /y "%ORIGINAL_SELF%" "%STAGED_SELF%" >nul 2>&1
if errorlevel 1 goto ERR_COPY

fltmc >nul 2>&1
if not errorlevel 1 goto RUN_STAGED_NOW

rem Encode ORIGINAL_SELF as URL-safe Base64 ([A-Za-z0-9_-], safe across CMD metacharacters & UAC)
"%PS_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $b64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($env:ORIGINAL_SELF)).Replace('+','-').Replace('/','_').TrimEnd('='); $q=[char]34; $cmdLine=$q+$q+$env:STAGED_SELF+$q+' __STAGED__ '+$b64+$q; Start-Process -FilePath $env:CMD_EXE -Verb RunAs -ArgumentList @('/d','/c',$cmdLine) | Out-Null"
if errorlevel 1 (
    if exist "%STAGED_SELF%" del /f /q "%STAGED_SELF%" >nul 2>&1
    goto ERR_UAC
)
exit /b 0

:RUN_STAGED_NOW
set "ASAN_ORIGINAL_SELF_B64="
set "ASAN_ORIGINAL_SELF=%ORIGINAL_SELF%"
call "%STAGED_SELF%" __STAGED__
set "RUN_RC=%ERRORLEVEL%"
if exist "%STAGED_SELF%" del /f /q "%STAGED_SELF%" >nul 2>&1
exit /b %RUN_RC%

:STAGED_ENTRY
set "SELF=%~f0"
set "SELF_NAME=%~nx0"
if not "%~2"=="" set "ASAN_ORIGINAL_SELF_B64=%~2"
if "%ASAN_ORIGINAL_SELF%"=="" set "ASAN_ORIGINAL_SELF=%~f0"
set "PSTEMP=%TEMP%\AsanPrinterMgr_%RANDOM%_%RANDOM%.ps1"
set "START_LOG=%TEMP%\AsanPrinterMgr_Startup_%RANDOM%_%RANDOM%.log"
cd /d "%TEMP%" >nul 2>&1
chcp 65001 >nul 2>&1

fltmc >nul 2>&1
if errorlevel 1 goto ERR_NOADMIN

"%PS_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $raw=[IO.File]::ReadAllText($env:SELF,[Text.Encoding]::UTF8); $m=[regex]::Match($raw,'(?m)^##__POWERSHELL_PAYLOAD__\s*$',[Text.RegularExpressions.RegexOptions]::RightToLeft); if(-not $m.Success){throw 'Payload marker not found.'}; $ps=$raw.Substring($m.Index+$m.Length); [IO.File]::WriteAllText($env:PSTEMP,$ps,(New-Object Text.UTF8Encoding($true)))" > "%START_LOG%" 2>&1
if errorlevel 1 goto ERR_EXTRACT

rem Execute in STA mode (required for WinForms & OpenFileDialog)
"%PS_EXE%" -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%PSTEMP%" > "%START_LOG%" 2>&1
set "RC=%ERRORLEVEL%"

if exist "%PSTEMP%" del /f /q "%PSTEMP%" >nul 2>&1
if "%RC%"=="99" (
    if exist "%START_LOG%" del /f /q "%START_LOG%" >nul 2>&1
    if /i "%SELF_NAME:~0,15%"=="AsanMgr_Staged_" (
        start "" /b cmd.exe /d /c "ping -n 2 127.0.0.1 >nul & del /f /q ""%SELF%"" >nul 2>&1"
    )
    exit /b 0
)

rem Non-99 exit means unexpected error or PS 5.1 ParserError -> Always show GUI MessageBox + Log
"%PS_EXE%" -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -Command "Add-Type -AssemblyName System.Windows.Forms; $msg='Script terminated unexpectedly (ExitCode='+$env:RC+').'; if(Test-Path -LiteralPath $env:START_LOG){ $txt=[IO.File]::ReadAllText($env:START_LOG,[Text.Encoding]::UTF8); if($txt.Length -gt 1200){ $txt=$txt.Substring(0,1200)+'...' }; if(-not [string]::IsNullOrWhiteSpace($txt)){ $msg=$msg+[Environment]::NewLine+[Environment]::NewLine+$txt } }; [System.Windows.Forms.MessageBox]::Show($msg,'Asan Printer Manager - Startup Error',[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null"
if exist "%START_LOG%" del /f /q "%START_LOG%" >nul 2>&1
if /i "%SELF_NAME:~0,15%"=="AsanMgr_Staged_" (
    start "" /b cmd.exe /d /c "ping -n 2 127.0.0.1 >nul & del /f /q ""%SELF%"" >nul 2>&1"
)
exit /b 1

:ERR_COPY
echo [ERROR] Failed to stage BAT file to local TEMP folder.
pause
exit /b 1

:ERR_UAC
echo [ERROR] UAC elevation was cancelled or failed.
pause
exit /b 1

:ERR_NOADMIN
echo [ERROR] Administrator privileges are required.
if /i "%SELF_NAME:~0,15%"=="AsanMgr_Staged_" (
    start "" /b cmd.exe /d /c "ping -n 2 127.0.0.1 >nul & del /f /q ""%SELF%"" >nul 2>&1"
)
pause
exit /b 1

:ERR_EXTRACT
echo [ERROR] Failed to extract PowerShell payload. Save this file as UTF-8 without BOM.
if exist "%START_LOG%" type "%START_LOG%"
if exist "%START_LOG%" del /f /q "%START_LOG%" >nul 2>&1
if /i "%SELF_NAME:~0,15%"=="AsanMgr_Staged_" (
    start "" /b cmd.exe /d /c "ping -n 2 127.0.0.1 >nul & del /f /q ""%SELF%"" >nul 2>&1"
)
pause
exit /b 1

##__POWERSHELL_PAYLOAD__
