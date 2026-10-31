@echo off
setlocal
rem Lists every account on the server with its access level (read-only, safe while the server runs).
rem Usage: ListPlayers.bat [server name]   (default: bolsonaro_gameplays)
set "SERVERNAME=%~1"
if "%SERVERNAME%"=="" set "SERVERNAME=bolsonaro_gameplays"
set "PZDS=C:\Program Files (x86)\Steam\steamapps\common\Project Zomboid Dedicated Server"
if not exist "%PZDS%\jre64\bin\java.exe" (
  echo Project Zomboid Dedicated Server not found in "%PZDS%".
  pause
  exit /b 1
)
"%PZDS%\jre64\bin\java.exe" --enable-native-access=ALL-UNNAMED -cp "%~dp0.;%PZDS%\java\projectzomboid.jar" ListPlayers "%USERPROFILE%\Zomboid\db\%SERVERNAME%.db"
echo.
pause
