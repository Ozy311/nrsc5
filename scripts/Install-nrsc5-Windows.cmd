@echo off
powershell -ExecutionPolicy Bypass -File "%~dp0install-windows.ps1" %*
set RC=%ERRORLEVEL%
rem Keep the window open when started by double-click (no arguments).
if "%~1"=="" echo %cmdcmdline% | find /i "%~nx0" >nul && pause
exit /b %RC%
