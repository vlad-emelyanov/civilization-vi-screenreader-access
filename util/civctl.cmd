@echo off
rem cmd/PowerShell entry point. From Git Bash use util/civctl instead: Git Bash starts this file as
rem   cmd /c ""...\civctl.cmd" arg "quoted arg""
rem and cmd strips the outer quotes BEFORE this file runs, so a path with a space (Code Projects) breaks
rem whenever any argument is quoted. That cannot be fixed from inside the .cmd.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0civctl.ps1" %*
