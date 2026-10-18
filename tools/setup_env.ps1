<#
  R26-IT-070 - one-shot environment setup for Windows.

  Run from the repo root in PowerShell:
      .\tools\setup_env.ps1            # GPU build if an NVIDIA driver is found
      .\tools\setup_env.ps1 -Cpu       # force the CPU build
      .\tools\setup_env.ps1 -Fresh     # delete .venv and rebuild it

  If PowerShell says "running scripts is disabled", run this once:
      Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
#>
param(
    [switch]$Cpu,
    [switch]$Fresh,
    [string]$PythonVersion = "3.10"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

function Step($n, $text) { Write-Host "`n[$n/6] $text" -ForegroundColor Cyan }
function Ok($text)       { Write-Host "      ok   $text" -ForegroundColor Green }
function Warn($text)     { Write-Host "      note $text" -ForegroundColor Yellow }
function Check([string]$What) {
    if ($LASTEXITCODE -ne 0) { throw "$What failed (exit code $LASTEXITCODE). Read the error above, fix it, and run this script again." }
}

Write-Host "R26-IT-070 environment setup" -ForegroundColor White
Write-Host "repo: $Root"

Step 1 "Looking for Python $PythonVersion"
if (-not (Get-Command py -ErrorAction SilentlyContinue)) {
    throw "The 'py' launcher was not found. Install Python $PythonVersion from python.org (tick 'Add python.exe to PATH'), then run this again."
}
& py "-$PythonVersion" --version
if ($LASTEXITCODE -ne 0) { throw "Python $PythonVersion is not installed. Install it from python.org, then run this again." }
Ok "Python $PythonVersion found"

Step 2 "Creating the virtual environment (.venv)"
if ($Fresh -and (Test-Path .venv)) { Remove-Item -Recurse -Force .venv; Ok "old .venv removed" }
if (-not (Test-Path .venv)) { & py "-$PythonVersion" -m venv .venv; Check "Creating .venv"; Ok ".venv created" }
else { Ok ".venv already exists, reusing it" }
$VenvPy = Join-Path $Root ".venv\Scripts\python.exe"
& $VenvPy -m pip install --upgrade pip --quiet; Check "Upgrading pip"

Step 3 "Installing PyTorch 2.2.1 (pinned in requirements.txt)"
$hasGpu = $null -ne (Get-Command nvidia-smi -ErrorAction SilentlyContinue)
if ($Cpu -or -not $hasGpu) {
    if (-not $Cpu) { Warn "nvidia-smi not found, installing the CPU build. Install the NVIDIA driver and run with -Fresh for GPU." }
    $index = "https://download.pytorch.org/whl/cpu"
} else {
    $index = "https://download.pytorch.org/whl/cu121"
}
& $VenvPy -m pip install torch==2.2.1 torchvision==0.17.1 --index-url $index; Check "Installing PyTorch"
Ok "PyTorch installed from $index"

Step 4 "Installing the team's requirements.txt"
& $VenvPy -m pip install -r requirements.txt; Check "Installing requirements.txt"
Ok "requirements installed"

Step 5 "Adding Jupyter support"
& $VenvPy -m pip install ipykernel --quiet; Check "Installing ipykernel"
& $VenvPy -m ipykernel install --user --name r26-it-070 --display-name "R26-IT-070 (.venv)"; Check "Registering the notebook kernel"
Ok "notebook kernel 'R26-IT-070 (.venv)' registered"

Step 6 "Running the environment doctor"
& $VenvPy tools\doctor.py

Write-Host "`nSetup finished." -ForegroundColor Green
Write-Host "In every new terminal, activate the environment with:  .\.venv\Scripts\Activate.ps1"
