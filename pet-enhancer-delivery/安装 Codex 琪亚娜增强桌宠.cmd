@echo off
setlocal
title Install Codex Kiana Pet Enhancer
set "PSModulePath=%SystemRoot%\System32\WindowsPowerShell\v1.0\Modules;%ProgramFiles%\WindowsPowerShell\Modules"
set "INSTALL_ARGS="
if /i "%~1"=="--verify-only" set "INSTALL_ARGS=-VerifyOnly"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-pet-enhancer-release.ps1" %INSTALL_ARGS%
set "EXIT_CODE=%ERRORLEVEL%"
if "%EXIT_CODE%"=="0" (
  echo.
  echo Installation completed. Follow the selection steps shown above before using the enhanced shortcut.
  pause
) else (
  echo.
  echo Installation failed. Exit code: %EXIT_CODE%
  pause
)
exit /b %EXIT_CODE%
