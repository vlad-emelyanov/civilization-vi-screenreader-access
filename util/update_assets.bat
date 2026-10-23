@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "CIV_ROOT=D:\SteamLibrary\steamapps\common\Sid Meier's Civilization VI\Base\Assets"
set "TARGET_ROOT=%~dp0..\ScreenReaderAccess\Assets"

REM Normalize: remove trailing backslash to make path math consistent
if "%CIV_ROOT:~-1%"=="\" set "CIV_ROOT=%CIV_ROOT:~0,-1%"
if "%TARGET_ROOT:~-1%"=="\" set "TARGET_ROOT=%TARGET_ROOT:~0,-1%"
for %%I in ("%TARGET_ROOT%") do set "TARGET_ROOT=%%~fI"


if not exist "%CIV_ROOT%\" (
  echo ERROR: Civ 6 root not found: "%CIV_ROOT%"
  exit /b 1
)
if not exist "%TARGET_ROOT%\" (
  echo ERROR: Target dir not found: "%TARGET_ROOT%"
  exit /b 1
)

echo Updating assets...
set /a COPIED=0
set /a MISSING=0
set /a FAILED=0

REM Enumerate files that already exist in TARGET_ROOT
for /r "%TARGET_ROOT%" %%F in (*) do (
  set "TARGET_FILE=%%F"
  set "REL=!TARGET_FILE:%TARGET_ROOT%\=!"
  set "SRC_FILE=%CIV_ROOT%\!REL!"

  echo Copy !SRC_FILE! to !TARGET_FILE!
  if exist "!SRC_FILE!" (
    copy /Y "!SRC_FILE!" "!TARGET_FILE!" 1>nul
    if !ERRORLEVEL! neq 0 (
      set /a FAILED+=1
      echo FAILED
    ) else (
      set /a COPIED+=1
      echo SUCCESS
    )
  ) else (
    set /a MISSING+=1
    echo MISSING
  )
)

echo.
echo Done.
echo   Copied : %COPIED%
echo   Missing: %MISSING%
echo   Failed : %FAILED%
echo.

if %FAILED% neq 0 exit /b 2
if %MISSING% neq 0 exit /b 2
exit /b 0
