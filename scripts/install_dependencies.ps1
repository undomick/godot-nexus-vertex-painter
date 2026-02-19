# Nexus Vertex Painter - Install Build Dependencies
# Clones godot-cpp and initializes submodules. Required for building the C++ GDExtension.
# Run this from the project root (parent of src/).
# Prerequisites: Git, Python 3 with SCons (pip install scons)

param(
    [string]$GodotCppBranch = "4.2"
)

$ErrorActionPreference = "Stop"

# Find project root (parent of scripts/, where src/ lives)
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$SrcDir = Join-Path $ProjectRoot "src"
$GodotCppDir = Join-Path $SrcDir "godot-cpp"

Write-Host "Nexus Vertex Painter - Install Dependencies" -ForegroundColor Cyan
Write-Host "Project root: $ProjectRoot"
Write-Host "godot-cpp branch: $GodotCppBranch"
Write-Host ""

if (-not (Test-Path $SrcDir)) {
    Write-Host "Error: src/ folder not found. Run this from the project root." -ForegroundColor Red
    exit 1
}

# Check Git
try {
    $null = git --version
} catch {
    Write-Host "Error: Git is required. Install Git and add it to PATH." -ForegroundColor Red
    exit 1
}

# Check Python / SCons (optional but recommended)
try {
    $sconsCheck = scons --version 2>$null
    if ($LASTEXITCODE -ne 0) { throw "scons not found" }
    Write-Host "SCons: $sconsCheck" -ForegroundColor Green
} catch {
    Write-Host "Warning: SCons not found. Install with: pip install scons" -ForegroundColor Yellow
    Write-Host "  You need SCons to build the C++ extension." -ForegroundColor Yellow
}

# Clone godot-cpp if not present
if (Test-Path $GodotCppDir) {
    $contents = Get-ChildItem $GodotCppDir -Force | Where-Object { $_.Name -notmatch "^\." }
    if ($contents.Count -gt 0) {
        Write-Host "godot-cpp already exists. Skipping clone." -ForegroundColor Green
        $SkipClone = $true
    }
}

if (-not $SkipClone) {
    Write-Host "Cloning godot-cpp (branch $GodotCppBranch)..." -ForegroundColor Cyan
    Push-Location $SrcDir
    try {
        git clone -b $GodotCppBranch https://github.com/godotengine/godot-cpp godot-cpp
        if ($LASTEXITCODE -ne 0) { throw "git clone failed" }
    } finally {
        Pop-Location
    }
    Write-Host "Clone complete." -ForegroundColor Green
}

# Initialize submodules
if (Test-Path $GodotCppDir) {
    Write-Host "Initializing godot-cpp submodules..." -ForegroundColor Cyan
    Push-Location $GodotCppDir
    try {
        git submodule update --init --recursive
        if ($LASTEXITCODE -ne 0) { throw "submodule update failed" }
    } finally {
        Pop-Location
    }
    Write-Host "Submodules initialized." -ForegroundColor Green
}

Write-Host ""
Write-Host "Dependencies installed." -ForegroundColor Cyan
Write-Host "To build the C++ extension:" -ForegroundColor Yellow
Write-Host "  cd src" -ForegroundColor Gray
Write-Host "  scons platform=windows target=editor   # or linux, macos" -ForegroundColor Gray
Write-Host ""
