@echo off
setlocal enabledelayedexpansion

echo ================================================================
echo        NYXFRAMEWORK REPOSITORY AND SYNTAX SANITY CHECK
echo ================================================================

python "%~dp0scripts\bootstrap_validator.py"

if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Nyxframework repository validation failed! Check logs above.
    exit /b 1
) else (
    echo [SUCCESS] All Nyxframework modules, manifests, and syntax validated!
    exit /b 0
)
