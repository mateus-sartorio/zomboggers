@echo off
setlocal
set "WINUSER=%~1"
if "%WINUSER%"=="" set /p "WINUSER=Windows user name (press Enter for %USERNAME%): "
if "%WINUSER%"=="" set "WINUSER=%USERNAME%"
echo.
echo Updating Bolsonaro Gameplays server mods for Windows user "%WINUSER%" ...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0UpdateServerMods.ps1" -WindowsUser "%WINUSER%"
echo.
pause
