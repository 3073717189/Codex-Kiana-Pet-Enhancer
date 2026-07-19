@echo off
setlocal
title Uninstall Codex Kiana Pet Enhancer
set "PSModulePath=%SystemRoot%\System32\WindowsPowerShell\v1.0\Modules;%ProgramFiles%\WindowsPowerShell\Modules"
set "UNINSTALLER=%LOCALAPPDATA%\CodexKianaPet\uninstall-pet-enhancer-release.ps1"
if not exist "%UNINSTALLER%" (
  echo The installed uninstaller was not found.
  pause
  exit /b 1
)
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%UNINSTALLER%" -PromptRestart
set "EXIT_CODE=%ERRORLEVEL%"
if not "%EXIT_CODE%"=="0" pause
exit /b %EXIT_CODE%
