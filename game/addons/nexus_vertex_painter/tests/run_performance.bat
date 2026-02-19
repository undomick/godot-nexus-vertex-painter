@echo off
REM Performance benchmark for Nexus Vertex Painter.
REM Edit GODOT_PATH to point to your Godot 4.x executable.
REM Example: set GODOT_PATH=C:\Godot\Godot_v4.6-stable_win64.exe

set GODOT_PATH=godot
set GAME_DIR=%~dp0..\..\..
cd /d "%GAME_DIR%"
%GODOT_PATH% --path "%GAME_DIR%" --headless --script res://addons/nexus_vertex_painter/tests/run_performance.gd
pause
