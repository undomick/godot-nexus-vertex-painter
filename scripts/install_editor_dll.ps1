# Copy the freshly built editor GDExtension DLL into the addon bin folder.
# Close all Godot processes first (Editor, LSP, headless runs).

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Src = Join-Path $Root "src\bin/windows/nexus_vertex_painter.windows.editor.x86_64.dll"
$DstDir = Join-Path $Root "game/addons/nexus_vertex_painter/bin/windows"
$Dst = Join-Path $DstDir "nexus_vertex_painter.windows.editor.x86_64.dll"

if (-not (Test-Path $Src)) {
    Write-Error "Build output missing. Run from src/: scons platform=windows target=editor"
}

$godot = Get-Process -Name "godot" -ErrorAction SilentlyContinue
if ($godot) {
    Write-Error "Godot is still running ($($godot.Count) process(es)). Close the editor and retry."
}

Get-ChildItem -LiteralPath $DstDir -Force -Filter "~*" -ErrorAction SilentlyContinue | ForEach-Object {
    attrib -h -r $_.FullName 2>$null
    Remove-Item -LiteralPath $_.FullName -Force
}

Copy-Item -LiteralPath $Src -Destination $Dst -Force
Write-Host "Installed editor DLL ($((Get-Item $Dst).Length) bytes) to addon bin." -ForegroundColor Green
