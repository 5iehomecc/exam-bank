@echo off
cd /d "%~dp0"

set "PSEXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PSEXE%" set "PSEXE=powershell.exe"

"%PSEXE%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0serve.ps1" %*

set "RC=%errorlevel%"
if not "%RC%"=="0" (
  echo.
  echo [FAILED] see messages above. Press any key to close.
  pause >nul
)