@echo off
setlocal
set "implementation="
if not "%~2"=="" goto usage
if "%~1"=="" goto run
if /i "%~1"=="sql" set "implementation=Sql"
if /i "%~1"=="ef" set "implementation=EntityFramework"
if /i "%~1"=="sp" set "implementation=EntityFrameworkStoredProcedures"
if /i "%~1"=="all" set "implementation=All"
if not defined implementation goto usage

:run
if defined implementation (
    "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -File "%~dp0scripts\Initialize-UserDatabase.ps1" -Implementation "%implementation%"
) else (
    "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -File "%~dp0scripts\Initialize-UserDatabase.ps1"
)
exit /b %errorlevel%

:usage
echo Usage: db.cmd [sql^|ef^|sp^|all]
exit /b 2
