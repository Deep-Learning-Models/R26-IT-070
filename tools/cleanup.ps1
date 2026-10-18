<#
  R26-IT-070 - repo tidy-up for Windows.

  Run from the repo root, on YOUR branch (not main):
      .\tools\cleanup.ps1                 # safe tier only
      .\tools\cleanup.ps1 -TeamApproved   # also the empty placeholders the team agreed to drop

  Nothing is committed. Every change shows up in GitHub Desktop for review.
  To undo everything before committing: GitHub Desktop > Branch > Discard all changes
  (or: git restore --staged --worktree .)
#>
param([switch]$TeamApproved)

$ErrorActionPreference = "Stop"
Set-Location (Split-Path -Parent $PSScriptRoot)

$branch = (git rev-parse --abbrev-ref HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw "This folder is not a git repository." }
if ($branch -eq "main") { throw "You are on main. Switch to your own branch in GitHub Desktop first." }
Write-Host "Tidying R26-IT-070 on branch '$branch'" -ForegroundColor White

function Remove-IfEmpty([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { Write-Host "  skip    $Path (not found)" -ForegroundColor DarkGray; return }
    if ((Get-Item -LiteralPath $Path).Length -ne 0) { Write-Host "  KEEP    $Path (it has content now)" -ForegroundColor Yellow; return }
    git rm --quiet -- $Path
    if ($LASTEXITCODE -ne 0) { throw "git rm failed for $Path" }
    Write-Host "  removed $Path" -ForegroundColor Green
}

function Move-Tracked([string]$From, [string]$To) {
    if (-not (Test-Path -LiteralPath $From)) { Write-Host "  skip    $From (not found)" -ForegroundColor DarkGray; return }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $To) | Out-Null
    git mv -- $From $To
    if ($LASTEXITCODE -ne 0) { throw "git mv failed for $From" }
    Write-Host "  moved   $From -> $To" -ForegroundColor Green
}

Write-Host "`nSafe tier: empty duplicates and loose images" -ForegroundColor Cyan
Remove-IfEmpty "configs/config.yaml"                  # empty; configs/default.yaml is the real config
Remove-IfEmpty "docs/lada_diagram.png.placeholder"    # empty placeholder file
Remove-IfEmpty "notebooks/01_data_exploration.ipynb"  # empty; the real one is preprocessing/notebooks/
Remove-IfEmpty "notebooks/02_module_testing.ipynb"    # empty, and Jupyter cannot open a 0-byte notebook
Move-Tracked "output.png" "docs/figures/sla_attention_example.png"
Move-Tracked "XCA_before_training.png" "docs/figures/xca_before_training.png"

if ($TeamApproved) {
    Write-Host "`nTeam tier: empty placeholders the team agreed to remove" -ForegroundColor Cyan
    if (Test-Path src) { Get-ChildItem src -Filter *.py | ForEach-Object { Remove-IfEmpty ("src/" + $_.Name) } }
    Remove-IfEmpty "notebooks/04_inference_demo.ipynb"
    Remove-IfEmpty "preprocessing/scripts/download_dataset.py"
} else {
    Write-Host "`nTeam tier skipped. Ask the team about src/, notebooks/04_inference_demo.ipynb and" -ForegroundColor DarkGray
    Write-Host "preprocessing/scripts/download_dataset.py, then run again with -TeamApproved." -ForegroundColor DarkGray
}

Write-Host "`nNot touched: lada/, preprocessing/ code, training/, retrieval/, tomato_guard/, README.md, requirements.txt" -ForegroundColor DarkGray
Write-Host "Next: review in GitHub Desktop, then commit 'Tidy repo: remove empty placeholders, move figures to docs/figures'." -ForegroundColor Green
