# ==============================================================================
#                 NYXFRAMEWORK AUTOMATED VERIFICATION SCRIPT (PowerShell)
# ==============================================================================
# Validates manifest declarations, balanced Lua 5.4 block syntax, migration indices,
# and SPA web assets. Returns exit code 0 on success, 1 on failure.

param (
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = Split-Path -Parent $ScriptDir

# Locate Python
$PythonExe = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $PythonExe) {
    Write-Host "[ERROR] Python 3 was not found in system PATH!" -ForegroundColor Red
    exit 1
}

$ValidatorScript = Join-Path $ScriptDir "validator.py"
if (-not (Test-Path $ValidatorScript)) {
    $ValidatorScript = Join-Path $RootDir "FiveM\scripts\bootstrap_validator.py"
}

if (-not (Test-Path $ValidatorScript)) {
    Write-Host "[ERROR] Could not find validator script: $ValidatorScript" -ForegroundColor Red
    exit 1
}

# Run the core validator
& python $ValidatorScript
$ValidatorExit = $LASTEXITCODE

if ($ValidatorExit -ne 0) {
    Write-Host "[FAIL] Verification check failed with exit code $ValidatorExit" -ForegroundColor Red
    exit 1
}

# Optional Luacheck validation if available in PATH
$LuacheckCmd = Get-Command luacheck -ErrorAction SilentlyContinue
if ($LuacheckCmd) {
    Write-Host "Running luacheck on modified/staged Lua files..." -ForegroundColor Cyan
    & luacheck "$RootDir\FiveM" --std "lua54" --no-color
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[FAIL] Luacheck reported errors!" -ForegroundColor Red
        exit 1
    }
}

Write-Host "`n>>> [VERIFICATION PASSED] All tests and assertions clean. Safe to commit. <<<" -ForegroundColor Green
exit 0
