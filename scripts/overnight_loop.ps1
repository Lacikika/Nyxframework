# ==============================================================================
#                 NYXFRAMEWORK AUTONOMOUS OVERNIGHT RUNNER (PowerShell)
# ==============================================================================
# Continuously executes an autonomous agent turn, validates changes with verify.ps1,
# commits successful iterations, and rolls back broken syntax/manifests.

param (
    [string]$BranchName = "agent/overnight-experiments",
    [int]$CooldownSeconds = 5,
    [int]$MaxCycles = 0, # 0 = infinite until error or manual stop
    [string]$CustomAgentCommand = ""
)

$RootDir = Split-Path -Parent $PSScriptRoot
Set-Location $RootDir

$LogFile = Join-Path $RootDir "agent_loop.log"
$StopFile = Join-Path $RootDir "STOP_LOOP"

# Ensure git is ready and on dedicated development branch
Write-Host "=== Setting Up Dedicated Autonomous Branch: $BranchName ===" -ForegroundColor Cyan
git checkout -B $BranchName

# Determine Agent CLI Command
$AgentExecutable = ""
if ($CustomAgentCommand) {
    Write-Host "Using Custom Agent Command: $CustomAgentCommand" -ForegroundColor Magenta
} else {
    $AgyCmd = (Get-Command agy -ErrorAction SilentlyContinue).Source
    if (-not $AgyCmd) {
        $LocalAgy = "$env:LOCALAPPDATA\agy\bin\agy.exe"
        if (Test-Path $LocalAgy) { $AgyCmd = $LocalAgy }
    }
    
    if ($AgyCmd) {
        $AgentExecutable = $AgyCmd
        Write-Host "Detected Google Antigravity CLI: $AgentExecutable" -ForegroundColor Green
    } else {
        # Fallback to generic agent-canvas or openhands-cli if available
        $CanvasCmd = (Get-Command "agent-canvas" -ErrorAction SilentlyContinue).Source
        if ($CanvasCmd) {
            $AgentExecutable = $CanvasCmd
        } else {
            Write-Host "[WARN] 'agy' CLI not found directly in path. Will attempt 'agy' invocation." -ForegroundColor Yellow
            $AgentExecutable = "agy"
        }
    }
}

$AgentPrompt = "Read AGENT_TASK.md. Pick the highest priority uncompleted task in the Task Backlog (or plan and implement the next feature from Tervek.md if backlog is empty). Implement it completely: write clean Lua 5.4 code, update fxmanifest.lua, add database migration if required, run tests, and update AGENT_TASK.md marking the task completed."

Write-Host "`n================================================================" -ForegroundColor Cyan
Write-Host "         STARTING AUTONOMOUS OVERNIGHT DEVELOPMENT LOOP          " -ForegroundColor Cyan
Write-Host " Repository : $RootDir" -ForegroundColor Gray
Write-Host " Branch     : $BranchName" -ForegroundColor Gray
Write-Host " Log File   : $LogFile" -ForegroundColor Gray
Write-Host " Stop Signal: Create a file named 'STOP_LOOP' to exit gracefully" -ForegroundColor Gray
Write-Host "================================================================`n" -ForegroundColor Cyan

$CycleCount = 0

while ($true) {
    # Check for graceful stop sentinel file
    if (Test-Path $StopFile) {
        Write-Host "[STOP] Detected 'STOP_LOOP' signal file. Exiting loop cleanly." -ForegroundColor Yellow
        Remove-Item -Force $StopFile -ErrorAction SilentlyContinue
        break
    }

    $CycleCount++
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $Header = "[$Timestamp] [Cycle $CycleCount] >>> Starting Agent Iteration <<<"
    Write-Host $Header -ForegroundColor Yellow
    Add-Content -Path $LogFile -Value "`n$Header"

    # 1. Run Agent Headless
    $AgentExitCode = 0
    if ($CustomAgentCommand) {
        Invoke-Expression "$CustomAgentCommand" *>> $LogFile
        $AgentExitCode = $LASTEXITCODE
    } elseif ($AgentExecutable -like "*agy*") {
        # Run agy in headless print mode with auto-approvals
        & $AgentExecutable --print $AgentPrompt --dangerously-skip-permissions --mode auto *>> $LogFile
        $AgentExitCode = $LASTEXITCODE
    } else {
        # Generic fallback
        & $AgentExecutable --headless --message $AgentPrompt *>> $LogFile
        $AgentExitCode = $LASTEXITCODE
    }

    if ($AgentExitCode -ne 0) {
        $ErrMsg = "[$Timestamp] Agent process exited with code $AgentExitCode. Stopping loop (possible quota, token limit, or runtime error)."
        Write-Host $ErrMsg -ForegroundColor Red
        Add-Content -Path $LogFile -Value $ErrMsg
        break
    }

    # 2. Run Local Verification Gatekeeper
    Write-Host "[$Timestamp] Running automated validation checks..." -ForegroundColor Cyan
    $VerifyOutput = & powershell -ExecutionPolicy Bypass -File "$PSScriptRoot\verify.ps1" 2>&1
    $VerifyExit = $LASTEXITCODE
    $VerifyOutput | Out-File -Append -FilePath $LogFile

    if ($VerifyExit -eq 0) {
        Write-Host "[$Timestamp] Verification PASSED!" -ForegroundColor Green

        # Check if there are modified or untracked files
        $GitStatus = git status --porcelain
        if ($GitStatus) {
            Write-Host "[$Timestamp] Committing verified changes..." -ForegroundColor Green
            git add -A
            $CommitMsg = "autonomous: feature iteration $Timestamp (cycle $CycleCount)"
            git commit -m $CommitMsg *>> $LogFile

            # Attempt push if remote is configured
            $HasRemote = git remote
            if ($HasRemote) {
                Write-Host "[$Timestamp] Pushing to remote branch $BranchName..." -ForegroundColor Gray
                git push origin $BranchName *>> $LogFile 2>&1
            }
            Add-Content -Path $LogFile -Value "[$Timestamp] Successfully committed: $CommitMsg"
        } else {
            Write-Host "[$Timestamp] Verification passed, but no working tree modifications detected." -ForegroundColor Gray
            Add-Content -Path $LogFile -Value "[$Timestamp] Cycle finished with no file changes."
        }
    } else {
        Write-Host "[$Timestamp] Verification FAILED! Rolling back broken changes..." -ForegroundColor Red
        Add-Content -Path $LogFile -Value "[$Timestamp] [ROLLBACK] Verification failed. Reverting dirty working tree..."
        git reset --hard HEAD *>> $LogFile
        git clean -fd *>> $LogFile
        Write-Host "[$Timestamp] Working tree reset to clean HEAD." -ForegroundColor Yellow
    }

    # Check max cycles if specified
    if ($MaxCycles -gt 0 -and $CycleCount -ge $MaxCycles) {
        Write-Host "[DONE] Reached maximum requested cycles ($MaxCycles). Stopping." -ForegroundColor Green
        break
    }

    Write-Host "[$Timestamp] Cycle $CycleCount finished. Cooldown pause ($CooldownSeconds s)...`n" -ForegroundColor DarkGray
    Start-Sleep -Seconds $CooldownSeconds
}

Write-Host "=== Autonomous Development Loop Terminated ===" -ForegroundColor Cyan
