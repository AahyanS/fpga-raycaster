@echo off
rem Double-click to play: loads the game onto the Basys 3 and opens the viewer.
cd /d "%~dp0"

set "VIVADO=C:\AMDDesignTools\2026.1\Vivado\bin\vivado.bat"
if not exist "%VIVADO%" for /f "delims=" %%v in ('where vivado.bat 2^>nul') do set "VIVADO=%%v"

set "PY=%USERPROFILE%\anaconda3\python.exe"
if not exist "%PY%" set "PY=python"

if not exist build\basys3\raycaster_basys3.bit (
    echo No bitstream yet - building it first ^(takes a few minutes^)...
    call "%VIVADO%" -mode batch -nojournal -nolog -source scripts\build.tcl || goto :fail
)

echo Loading the raycaster onto the board...
call "%VIVADO%" -mode batch -nojournal -nolog -source scripts\program.tcl > build\program.log 2>&1
findstr /c:"Programmed" build\program.log >nul || (
    echo Programming failed - is the board plugged in and switched on? See build\program.log
    goto :fail
)

echo Starting the viewer...
rem Vivado points Python at its own copy; undo that for the viewer.
set "PYTHONHOME="
set "PYTHONPATH="
"%PY%" viewer\viewer.py || goto :fail
exit /b 0

:fail
pause
exit /b 1
