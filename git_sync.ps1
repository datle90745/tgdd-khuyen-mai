[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$git = "C:\Users\toquo\AppData\Local\Microsoft\WinGet\Packages\Git.MinGit_Microsoft.Winget.Source_8wekyb3d8bbwe\cmd\git.exe"

& $git config user.name "datle90745"
& $git config user.email "datle90745@users.noreply.github.com"

# Check if branch main is tracking origin/main
& $git branch -M main

# Add origin if needed
$remotes = & $git remote
if ($remotes -notcontains "origin") {
    & $git remote add origin https://github.com/datle90745/tgdd-khuyen-mai.git
}

# Fetch origin
Write-Host "Fetching origin/main..." -ForegroundColor Cyan
& $git fetch origin main

# Check if we need to reset to origin/main or merge
# We want our working tree changes to stay!
# Let's see: git symbolic-ref HEAD
$currentHead = & $git rev-parse --verify HEAD 2>$null
if (-not $currentHead) {
    # Initial commit scenario: reset head to origin/main without wiping working directory
    Write-Host "Setting HEAD to origin/main..." -ForegroundColor Cyan
    & $git reset --mixed origin/main
}

Write-Host "Git Status:" -ForegroundColor Yellow
& $git status --short
