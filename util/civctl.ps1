<#
.SYNOPSIS
  Agent/dev harness for driving Civilization VI with the ScreenReaderAccess mod.

.EXAMPLE
  .\util\civctl.ps1 build                 # build + deploy the mod with ModBuddy (refuses while the game runs unless -Force; kills hot reload until a restart)
  .\util\civctl.ps1 deploy                # copy changed mod files straight into the running game's deployed mod folder: hot reload, no restart
  .\util\civctl.ps1 lua InGame 'print(Game.GetCurrentGameTurn())'   # run Lua in a game Lua state via FireTuner (needs EnableTuner 1)
  .\util\civctl.ps1 states                # list the tuner's Lua states
  .\util\civctl.ps1 reload InGameAccess.lua   # force a hot reload of a deployed file even if unchanged
  .\util\civctl.ps1 menu                  # is the in-game options menu / a popup open? (exit 4 if so)
  .\util\civctl.ps1 start                 # launch game + console app, wait for main menu
  .\util\civctl.ps1 sr                    # print new screen reader lines since last call
  .\util\civctl.ps1 key Down              # press a key (Down, Up, Enter, Escape, Tab, A, F1, ...)
  .\util\civctl.ps1 key Down -Count 3     # press it several times
  .\util\civctl.ps1 key Shift+E           # chord: Shift/Control/Alt + one key
  .\util\civctl.ps1 keymap                # regenerate skills\civ-test\keymap.md from the Key Bindings dump in Lua.log
  .\util\civctl.ps1 wait 'Exit to Desktop' -Timeout 10   # wait for a matching screen reader line
  .\util\civctl.ps1 shot                  # screenshot game window, prints the png path
  .\util\civctl.ps1 stop                  # kill game + console app

  `key` prints the screen reader lines that the keypress produced (waits -Settle ms for them).
  Use -All with `sr`/`key` to see every new Lua.log line rather than only #SCREENREADER lines.
#>
param(
    [Parameter(Position = 0, Mandatory)]
    [ValidateSet('build', 'deploy', 'reload', 'lua', 'states', 'menu', 'start', 'stop', 'key', 'sr', 'wait', 'shot', 'status', 'keymap')]
    [string]$Command,
    [Parameter(Position = 1)]
    [string]$Arg,
    [Parameter(Position = 2, ValueFromRemainingArguments)]
    [string[]]$MoreArgs,   # extra words are joined onto $Arg, so `wait Begin Game` works without quotes
    [int]$Count = 1,
    [int]$Timeout = 120,
    [int]$Settle = 600,
    [int]$Hold = 40,        # ms the key stays down (raise for things the game polls, e.g. key rebinding)
    [switch]$All,
    [switch]$Force,         # build: build even though the game is running
    [string]$Out,
    [string]$File           # lua: read the Lua code from this file instead of the command line
)

$ErrorActionPreference = 'Stop'

# cmd.exe breaks a command line with two quoted strings (the quoted path of civctl.cmd plus a quoted argument such as
# 'Begin Game'; Git Bash does this: "'C:\Users\...\Code' is not recognized"). So pass multi-word arguments unquoted:
# `civctl.cmd wait Begin Game -Timeout 5`.
if ($MoreArgs) { $Arg = (@($Arg) + $MoreArgs) -join ' ' }

$RepoRoot = Split-Path $PSScriptRoot -Parent
$GameExe = "C:\Program Files (x86)\Steam\steamapps\common\Sid Meier's Civilization VI\Base\Binaries\Win64Steam\CivilizationVI.exe"
$ConsoleExe = Join-Path $RepoRoot 'ScreenreaderAccess.Console\bin\Debug\net8.0-windows\ScreenreaderAccess.Console.exe'
$LuaLog = Join-Path $env:LOCALAPPDATA "Firaxis Games\Sid Meier's Civilization VI\Logs\Lua.log"
$StateDir = Join-Path $env:TEMP 'civctl'
$CursorFile = Join-Path $StateDir 'cursor.txt'
$GameProcessNames = @('CivilizationVI', 'CivilizationVI_DX12')
$ScreenReaderMarker = '#SCREENREADER'

New-Item -ItemType Directory -Force $StateDir | Out-Null

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
if (-not ('CivCtl.Native' -as [type])) {
    Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace CivCtl {
public static class Native {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] struct KEYBDINPUT { public ushort wVk; public ushort wScan; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Sequential)] struct MOUSEINPUT { public int dx, dy; public uint mouseData, dwFlags, time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Explicit)] struct InputUnion { [FieldOffset(0)] public MOUSEINPUT mi; [FieldOffset(0)] public KEYBDINPUT ki; }
    [StructLayout(LayoutKind.Sequential)] struct INPUT { public uint type; public InputUnion u; }

    const uint INPUT_KEYBOARD = 1, KEYEVENTF_EXTENDEDKEY = 0x1, KEYEVENTF_KEYUP = 0x2, KEYEVENTF_SCANCODE = 0x8;

    [DllImport("user32.dll")] static extern uint SendInput(uint n, INPUT[] inputs, int size);
    [DllImport("user32.dll")] static extern uint MapVirtualKey(uint code, uint mapType);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);

    // Windows only lets a process steal focus if it recently received input; a synthetic ALT tap satisfies that.
    public static bool Focus(IntPtr h) {
        if (GetForegroundWindow() == h) return true;
        if (IsIconic(h)) ShowWindow(h, 9);
        keybd_event(0x12, 0, 0, UIntPtr.Zero);
        keybd_event(0x12, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
        SetForegroundWindow(h);
        System.Threading.Thread.Sleep(150);
        return GetForegroundWindow() == h;
    }

    static bool IsExtended(uint vk) {
        // arrows, ins/del, home/end, pgup/pgdn, numpad divide, right ctrl/alt
        return (vk >= 0x21 && vk <= 0x28) || vk == 0x2D || vk == 0x2E || vk == 0x6F || vk == 0xA3 || vk == 0xA5;
    }

    // Holds the modifier keys (VK codes) down around a Tap, e.g. Shift+E.
    public static void Chord(uint[] mods, uint vk, int holdMs) {
        int size = Marshal.SizeOf(typeof(INPUT));
        foreach (uint m in mods) { INPUT d = Make(m, 0); SendInput(1, new[] { d }, size); System.Threading.Thread.Sleep(30); }
        Tap(vk, holdMs);
        for (int i = mods.Length - 1; i >= 0; i--) { INPUT u = Make(mods[i], KEYEVENTF_KEYUP); SendInput(1, new[] { u }, size); }
    }

    static INPUT Make(uint vk, uint extraFlags) {
        INPUT i = new INPUT { type = INPUT_KEYBOARD };
        i.u.ki = new KEYBDINPUT { wVk = (ushort)vk, wScan = (ushort)MapVirtualKey(vk, 0), dwFlags = KEYEVENTF_SCANCODE | (IsExtended(vk) ? KEYEVENTF_EXTENDEDKEY : 0) | extraFlags };
        return i;
    }

    // Sends scancodes (not just VKs) so games reading hardware-ish input still see the key.
    public static void Tap(uint vk, int holdMs) {
        ushort scan = (ushort)MapVirtualKey(vk, 0);
        uint flags = KEYEVENTF_SCANCODE | (IsExtended(vk) ? KEYEVENTF_EXTENDEDKEY : 0);
        INPUT down = new INPUT { type = INPUT_KEYBOARD };
        down.u.ki = new KEYBDINPUT { wVk = (ushort)vk, wScan = scan, dwFlags = flags };
        INPUT up = down;
        up.u.ki.dwFlags = flags | KEYEVENTF_KEYUP;
        int size = Marshal.SizeOf(typeof(INPUT));
        SendInput(1, new[] { down }, size);
        System.Threading.Thread.Sleep(holdMs);
        SendInput(1, new[] { up }, size);
    }
}
}
'@
}

function Get-GameProcess {
    Get-Process -Name $GameProcessNames -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
}

function Get-ConsoleProcess {
    Get-Process -Name 'ScreenreaderAccess.Console' -ErrorAction SilentlyContinue
}

function Read-NewLogLines {
    # Returns Lua.log lines appended since the stored cursor "<line count> <log creation ticks>".
    # The creation time resets the cursor when the game recreates the log. A malformed cursor file (several lines, empty,
    # written concurrently by two civctl processes) is treated as 0 instead of throwing.
    if (-not (Test-Path $LuaLog)) { return @() }
    $cursor = 0
    $created = (Get-Item $LuaLog).CreationTimeUtc.Ticks
    try {
        $m = [regex]::Match([IO.File]::ReadAllText($CursorFile), '^\s*(\d+)(?:\s+(\d+))?')
        if ($m.Success) {
            $cursor = [int]$m.Groups[1].Value
            if ($m.Groups[2].Success -and [long]$m.Groups[2].Value -ne $created) { $cursor = 0 }
        }
    } catch { $cursor = 0 }
    $fs = [IO.File]::Open($LuaLog, 'Open', 'Read', 'ReadWrite')
    try {
        $reader = New-Object IO.StreamReader($fs)
        $lines = $reader.ReadToEnd() -split "`r?`n" | Where-Object { $_ -ne '' }
    } finally { $fs.Dispose() }
    $lines = @($lines)
    if ($lines.Count -lt $cursor) { $cursor = 0 }
    try { [IO.File]::WriteAllText($CursorFile, "$($lines.Count) $created") } catch { }
    if ($lines.Count -le $cursor) { return @() }
    return $lines[$cursor..($lines.Count - 1)]
}

function Format-Lines($lines) {
    foreach ($l in $lines) {
        if ($All) { $l; continue }
        $i = $l.IndexOf($ScreenReaderMarker)
        if ($i -ge 0) { 'SR> ' + $l.Substring($i + $ScreenReaderMarker.Length).TrimStart(' ', '-').Replace('[NOINTERRUPT] - ', '[NOINTERRUPT] ') }
    }
}

function Wait-ForScreenReader([string]$pattern, [int]$timeoutSec) {
    $deadline = (Get-Date).AddSeconds($timeoutSec)
    while ((Get-Date) -lt $deadline) {
        $matched = $false
        # Finish the whole batch even after a match: the cursor has already moved past these lines.
        foreach ($l in (Read-NewLogLines)) {
            $f = Format-Lines @($l)
            # Write-Host: plain output would be swallowed into this function's return value.
            if ($f) { Write-Host $f }
            if ($l.Contains($ScreenReaderMarker) -and $l -match $pattern) { $matched = $true }
        }
        if ($matched) { return $true }
        Start-Sleep -Milliseconds 250
    }
    return $false
}

function Invoke-Start {
    if (-not (Get-ConsoleProcess)) {
        if (-not (Test-Path $ConsoleExe)) { throw "Console app not built: $ConsoleExe (run: dotnet build ScreenreaderAccess.Console)" }
        Start-Process $ConsoleExe -WindowStyle Minimized | Out-Null
        Write-Output 'Started console app.'
    }
    if (Get-GameProcess) {
        Write-Output 'Game already running.'
        return
    }
    # The log is recreated on launch; point the cursor at the start of the new file.
    [IO.File]::WriteAllText($CursorFile, '0')
    $launchTime = Get-Date
    Start-Process $GameExe -WorkingDirectory (Split-Path $GameExe) | Out-Null
    Write-Output 'Launching game...'
    $deadline = $launchTime.AddSeconds($Timeout)
    while ((Get-Date) -lt $deadline) {
        if ((Test-Path $LuaLog) -and (Get-Item $LuaLog).LastWriteTime -gt $launchTime) { break }
        Start-Sleep -Seconds 1
    }
    # The intro movie holds back the main menu until a key is pressed, so keep tapping Escape until it shows.
    while ((Get-Date) -lt $deadline) {
        if (Wait-ForScreenReader 'Main menu' 3) {
            Write-Output 'Main menu ready.'
            return
        }
        $game = Get-GameProcess
        if ($game -and [CivCtl.Native]::Focus($game.MainWindowHandle)) { [CivCtl.Native]::Tap(0x1B, 40) }
    }
    Write-Output "Timed out waiting for main menu after $Timeout s. Try: civctl.ps1 shot"
    exit 1
}

function Invoke-Key {
    if (-not $Arg) { throw 'Usage: civctl.ps1 key <KeyName> [-Count n]' }
    $game = Get-GameProcess
    if (-not $game) { throw 'Game is not running.' }
    # "Shift+E", "Control+Shift+F": modifiers are held around the key. Key names never contain '+' (the + key is OemPlus).
    $parts = @($Arg -split '\+')
    $mods = [uint32[]]@($parts | Select-Object -SkipLast 1 | ForEach-Object {
        switch -Regex ($_) { '^(ctrl|control)$' { 0xA2 } '^shift$' { 0xA0 } '^(alt|menu)$' { 0xA4 } default { throw "Unknown modifier '$_' (use Shift, Control, Alt)" } }
    })
    $vk = [uint32][System.Windows.Forms.Keys]::Parse([System.Windows.Forms.Keys], $parts[-1], $true)
    if (-not [CivCtl.Native]::Focus($game.MainWindowHandle)) { Write-Warning 'Could not bring game window to foreground; key may go elsewhere.' }
    # Output that arrived after the previous command returned; shown rather than dropped so nothing is missed.
    $pending = Format-Lines (Read-NewLogLines)
    if ($pending) { $pending | ForEach-Object { "(earlier) $_" } }
    for ($i = 0; $i -lt $Count; $i++) {
        [CivCtl.Native]::Chord($mods, $vk, $Hold)
        Start-Sleep -Milliseconds $Settle
        Format-Lines (Read-NewLogLines)
    }
}

function Invoke-Shot {
    $game = Get-GameProcess
    $path = if ($Out) { $Out } else { Join-Path $StateDir ("shot_{0:yyyyMMdd_HHmmss}.png" -f (Get-Date)) }
    if ($game) {
        [CivCtl.Native]::Focus($game.MainWindowHandle) | Out-Null
        $r = New-Object CivCtl.Native+RECT
        [CivCtl.Native]::GetWindowRect($game.MainWindowHandle, [ref]$r) | Out-Null
        $rect = [System.Drawing.Rectangle]::FromLTRB($r.Left, $r.Top, $r.Right, $r.Bottom)
    } else {
        $rect = [System.Windows.Forms.SystemInformation]::VirtualScreen
    }
    $bmp = New-Object System.Drawing.Bitmap $rect.Width, $rect.Height
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($rect.Left, $rect.Top, 0, 0, $bmp.Size)
    # Downscale large captures so they are cheap to look at.
    $maxW = 1280
    if ($bmp.Width -gt $maxW) {
        $h = [int]($bmp.Height * $maxW / $bmp.Width)
        $small = New-Object System.Drawing.Bitmap $bmp, $maxW, $h
        $bmp.Dispose(); $bmp = $small
    }
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
    Write-Output $path
}

function Invoke-Build {
    if ((Get-GameProcess) -and -not $Force) {
        Write-Output "Refusing to build while the game is running: ModBuddy deletes and recreates the deployed mod folder, which kills the game's hot-reload file watcher until the game is restarted. Use ``deploy`` for changes to existing files, or ``stop`` first (or pass -Force if you will restart the game anyway)."
        exit 1
    }
    $modBuddy = (Get-Command modbuddy -ErrorAction SilentlyContinue).Source
    if (-not $modBuddy) { $modBuddy = "C:\Program Files (x86)\Steam\steamapps\common\Sid Meier's Civilization VI SDK\ModBuddy\ModBuddy.exe" }
    $outFile = Join-Path $StateDir 'build.txt'
    Remove-Item $outFile -ErrorAction SilentlyContinue
    $p = Start-Process $modBuddy -ArgumentList 'ScreenReaderAccess.civ6sln', '/out', "`"$outFile`"", '/build' -WorkingDirectory $RepoRoot -PassThru
    if (-not $p.WaitForExit($Timeout * 1000)) {
        $p | Stop-Process -Force
        Write-Output "ModBuddy did not finish within $Timeout s (likely stuck on a dialog). Try: civctl.ps1 shot"
        exit 1
    }
    $result = Get-Content $outFile -ErrorAction SilentlyContinue
    $result | Where-Object { $_ -match 'error|warning|Build:' }
    if (-not ($result -match '1 succeeded')) { exit 1 }
    if (Get-GameProcess) { Write-Output 'Note: built with -Force while the game runs; it no longer hot-reloads until it is restarted.' }
}

function Get-DeployedModDir {
    # ModBuddy deploys to <Documents>\My Games\Sid Meier's Civilization VI\Mods\<mod name> (Documents may be redirected to OneDrive).
    Join-Path ([Environment]::GetFolderPath('MyDocuments')) "My Games\Sid Meier's Civilization VI\Mods\ScreenReaderAccess"
}

# Content types the project ships (see the <Content Include> list in the .civ6proj); other files in the folder are ignored.
$ShippedExtensions = @('.lua', '.xml', '.sql', '.artdef', '.dds', '.png', '.gr2', '.ffx', '.fxh')

function Get-ShippedFiles([string]$root) {
    if (-not (Test-Path $root)) { return @() }
    Get-ChildItem $root -Recurse -File | Where-Object { $_.Extension -in $ShippedExtensions -and $_.FullName -notlike '*\.vs\*' }
}

function Read-LogSince([long]$pos) {
    # Lua.log lines after byte offset $pos (from 0 when the log is now shorter, i.e. recreated). Empty when there is no log.
    if (-not (Test-Path $LuaLog)) { return @() }
    $fs = [IO.File]::Open($LuaLog, 'Open', 'Read', 'ReadWrite')
    try {
        if ($pos -gt $fs.Length) { $pos = 0 }
        $fs.Seek($pos, 'Begin') | Out-Null
        return @((New-Object IO.StreamReader($fs)).ReadToEnd() -split "`r?`n")
    } finally { $fs.Dispose() }
}

function Write-InPlace([string]$target, [byte[]]$bytes) {
    # Rewrites the file in place (not delete+create) so the game's file watcher notices. When the file shrinks, the new content is
    # first padded with newlines to the old length, so a watcher that reads in between never sees new content + stale tail
    # (a spurious syntax error); then the file is cut to size.
    $fs = [IO.File]::Open($target, 'Open', 'Write', 'ReadWrite')
    try {
        $old = $fs.Length
        if ($old -gt $bytes.Length) {
            $padded = New-Object byte[] $old
            [Array]::Copy($bytes, $padded, $bytes.Length)
            for ($i = $bytes.Length; $i -lt $old; $i++) { $padded[$i] = 10 }
            $fs.Write($padded, 0, $old); $fs.Flush()
            $fs.SetLength($bytes.Length); $fs.Flush()
        } else {
            $fs.Write($bytes, 0, $bytes.Length); $fs.Flush()
        }
    } finally { $fs.Dispose() }
}

function Invoke-Deploy([string[]]$touch) {
    # Copies changed files from the repo's ScreenReaderAccess\ folder into the deployed mod folder; the game re-initialises the
    # affected UI context within ~1 s. With $touch (the `reload` command): rewrites the matching files even if unchanged.
    # Exit codes: 0 ok, 1 Lua errors or failure, 3 a build + restart is needed (new/deleted files, Database changes).
    $src = Join-Path $RepoRoot 'ScreenReaderAccess'
    $dst = Get-DeployedModDir
    if (-not (Test-Path $dst)) { throw "Deployed mod folder not found: $dst (run: civctl.ps1 build)" }
    $logLen = if (Test-Path $LuaLog) { (Get-Item $LuaLog).Length } else { 0 }
    $copied = 0
    $shrunk = @()
    $needsBuild = @()
    $sha = [Security.Cryptography.SHA1]::Create()
    $repoRels = @{}
    foreach ($f in (Get-ShippedFiles $src)) {
        $rel = $f.FullName.Substring($src.Length).TrimStart('\')
        $repoRels[$rel.ToLowerInvariant()] = $true
        $target = Join-Path $dst $rel
        $force = $false
        if ($touch) { $force = [bool]($touch | Where-Object { $rel -like "*$_*" }); if (-not $force) { continue } }
        if (-not (Test-Path $target)) { $needsBuild += "$rel (new file)"; continue }
        $bytes = [IO.File]::ReadAllBytes($f.FullName)
        $same = [BitConverter]::ToString($sha.ComputeHash($bytes)) -eq [BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($target)))
        if ($same -and -not $force) { continue }
        if ((Get-Item $target).Length -gt $bytes.Length) { $shrunk += , @($target, $bytes) }
        Write-InPlace $target $bytes
        $copied++
        Write-Output "$(if ($same) { 'reloaded' } else { 'deployed' }) $rel"
        if ($rel -like 'Database\*') { $needsBuild += "$rel (database changes need a full restart)" }
    }
    if (-not $touch) {
        foreach ($f in (Get-ShippedFiles $dst)) {
            $rel = $f.FullName.Substring($dst.Length).TrimStart('\')
            if (-not $repoRels.ContainsKey($rel.ToLowerInvariant())) { $needsBuild += "$rel (deleted from the repo but still deployed)" }
        }
    } elseif ($copied -eq 0) {
        Write-Output "No shipped file matches: $($touch -join ' ')"
        exit 1
    }
    if ($copied -eq 0 -and $needsBuild.Count -eq 0) { Write-Output 'Nothing changed.' }
    $failed = $false
    if ($copied -gt 0 -and (Get-GameProcess)) {
        $pattern = 'Runtime Error|Syntax Error|Error loading file|empty file'
        Start-Sleep -Milliseconds 2500
        $errs = @(Read-LogSince $logLen | Where-Object { $_ -match $pattern })
        if ($errs -and $shrunk) {
            # A watcher may still have caught a shrinking file mid-write: rewrite those once and look again.
            Write-Output 'Errors after shrinking a file; rewriting it once and rescanning...'
            $logLen = if (Test-Path $LuaLog) { (Get-Item $LuaLog).Length } else { 0 }
            foreach ($s in $shrunk) { Write-InPlace $s[0] $s[1] }
            Start-Sleep -Milliseconds 2500
            $errs = @(Read-LogSince $logLen | Where-Object { $_ -match $pattern })
        }
        if ($errs) { $errs | ForEach-Object { Write-Output "LUA ERROR> $_" }; $failed = $true }
        else { Write-Output 'No Lua errors in the 2.5 s after deploy.' }
    }
    foreach ($n in $needsBuild) { Write-Output "needs build + restart: $n" }
    if ($failed) { exit 1 }
    if ($needsBuild.Count -gt 0) { exit 3 }
}

function Get-PythonCommand {
    foreach ($c in @(@('python'), @('py', '-3'))) {
        $exe = Get-Command $c[0] -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        # The Microsoft Store stub (WindowsApps\python.exe) exists on PATH but only prints an install hint.
        if ($exe -and $exe.Source -notlike '*\WindowsApps\python*.exe') { return , (@($exe.Source) + @($c | Select-Object -Skip 1)) }
    }
    throw 'Python 3 was not found on PATH (tried `python` and `py -3`). The lua/states/menu commands need it: install Python 3 from python.org.'
}

function Invoke-Python([string[]]$pyArgs) {
    $py = Get-PythonCommand
    $old = [Console]::OutputEncoding
    [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)   # civtuner.py writes UTF-8
    try {
        & $py[0] @($py | Select-Object -Skip 1) -I @pyArgs | Out-Host
        return $LASTEXITCODE
    } finally { [Console]::OutputEncoding = $old }
}

function Invoke-Tuner {
    $py = Join-Path $PSScriptRoot 'civtuner.py'
    if ($Command -eq 'states') { exit (Invoke-Python @($py, 'states')) }
    $code = $null
    if ($File) { $state = $Arg; $code = [IO.File]::ReadAllText($File) }
    else {
        if (-not $Arg) { throw 'Usage: civctl.ps1 lua <state> <code>   (or: lua <state> -File script.lua)' }
        $state, $code = $Arg -split '\s+', 2
    }
    if (-not $state -or -not $code) { throw 'Usage: civctl.ps1 lua <state> <code>   (or: lua <state> -File script.lua)' }
    # Pass the code through a temp file: quoting Lua (quotes, newlines) through cmd.exe and PowerShell 5.1 argument parsing is unreliable.
    $tmp = Join-Path $StateDir 'tuner.lua'
    [IO.File]::WriteAllText($tmp, $code, (New-Object Text.UTF8Encoding($false)))
    exit (Invoke-Python @($py, 'lua', '-f', $tmp, $state))
}

function Invoke-Stop {
    Get-Process -Name $GameProcessNames -ErrorAction SilentlyContinue | Stop-Process -Force
    Get-ConsoleProcess | Stop-Process -Force
    # Relaunching while the old process is still tearing down makes the new launch silently exit.
    $deadline = (Get-Date).AddSeconds(30)
    while ((Get-Process -Name $GameProcessNames -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 500 }
    Start-Sleep -Seconds 3
    Write-Output 'Stopped.'
}

function ConvertTo-CivctlKey([string]$display) {
    # Key Bindings display string ("Control+Shift+F", "Down Arrow", "]") -> argument for `civctl key`.
    $names = @{
        'Return' = 'Enter'; 'Space' = 'Space'; 'Delete' = 'Delete'; 'Insert' = 'Insert'; 'Home' = 'Home'; 'End' = 'End'
        'Page Up' = 'Prior'; 'Page Down' = 'Next'; 'Up Arrow' = 'Up'; 'Down Arrow' = 'Down'; 'Left Arrow' = 'Left'; 'Right Arrow' = 'Right'
        ',' = 'Oemcomma'; '.' = 'OemPeriod'; '[' = 'OemOpenBrackets'; ']' = 'OemCloseBrackets'; '\' = 'OemPipe'
        '=' = 'Oemplus'; '-' = 'OemMinus'; '/ (Number Pad)' = 'Divide'; ';' = 'OemSemicolon'; "'" = 'OemQuotes'; '`' = 'Oemtilde'
    }
    $parts = $display -split '\+(?=.)'
    $out = foreach ($p in $parts) {
        if ($names.ContainsKey($p)) { $names[$p] }
        elseif ($p -match '^[0-9]$') { "D$p" }
        elseif ($p -match '^([A-Z]|F\d{1,2}|Shift|Control|Alt)$') { $p }
        else { '?' }
    }
    $out -join '+'
}

function Invoke-Keymap {
    # Source of truth is the `#KEYMAP` dump that Options.lua prints whenever the Options screen is shown.
    $outFile = Join-Path $RepoRoot '.claude\skills\civ-test\keymap.md'
    $rows = $null
    if (Test-Path $LuaLog) {
        $fs = [IO.File]::Open($LuaLog, 'Open', 'Read', 'ReadWrite')
        try { $lines = (New-Object IO.StreamReader($fs)).ReadToEnd() -split "`r?`n" } finally { $fs.Dispose() }
        $current = $null
        foreach ($l in $lines) {
            $i = $l.IndexOf('#KEYMAP - ')
            if ($i -lt 0) { continue }
            $t = $l.Substring($i + 10)
            if ($t -eq 'BEGIN') { $current = @() }
            elseif ($t -eq 'END') { if ($null -ne $current) { $rows = $current; $current = $null } }
            elseif ($null -ne $current) { $current += , ($t -split '\|', 5) }
        }
    }
    if (-not $rows) {
        Write-Output 'No complete #KEYMAP dump in Lua.log. Start the game (civctl start) and open Options from the main menu (Down to "Game Options", Enter), then run this again.'
        exit 1
    }
    $md = New-Object System.Collections.Generic.List[string]
    $md.Add('# Civ VI key bindings (generated)')
    $md.Add('')
    $md.Add("Generated by ``util\civctl.cmd keymap`` on $(Get-Date -Format 'yyyy-MM-dd') from the in-game Key Bindings list (Options.lua ``DumpKeyMap``). Do not edit by hand; regenerate after rebinding keys or changing mod hotkeys (``Database/*.sql``).")
    $md.Add('')
    $md.Add('"civctl key" is the argument for `util\civctl.cmd key <arg>`. These are in-game (World) hotkeys: they need a game in progress and no popup open. A blank key means unbound; `?` means civctl cannot send it yet (extend ConvertTo-CivctlKey).')
    $unbound = @($rows | Where-Object { -not $_[2] })
    if ($unbound) { $md.Add(''); $md.Add("**Unbound actions: $(($unbound | ForEach-Object { $_[1] }) -join ', ')**") }
    foreach ($group in ($rows | Group-Object { $_[0] -replace ':\s*$', '' })) {
        $md.Add('')
        $md.Add("## $($group.Name)")
        $md.Add('')
        $md.Add('| Action | Key | civctl key | Alternate | Description |')
        $md.Add('|---|---|---|---|---|')
        foreach ($r in ($group.Group | Sort-Object { $_[1] })) {
            $key = if ($r[2]) { ConvertTo-CivctlKey $r[2] } else { '' }
            $md.Add("| $($r[1]) | $($r[2]) | $key | $($r[3]) | $($r[4]) |")
        }
    }
    [IO.File]::WriteAllText($outFile, (($md -join "`n") + "`n"), (New-Object Text.UTF8Encoding($false)))
    Write-Output "Wrote $outFile ($($rows.Count) actions, $($unbound.Count) unbound)."
}

switch ($Command) {
    'build' { Invoke-Build }
    'deploy' { Invoke-Deploy }
    'reload' { if (-not $Arg) { throw 'Usage: civctl.ps1 reload <file...>  (path or name fragment, e.g. InGameAccess.lua)' }; Invoke-Deploy ($Arg -split '\s+') }
    'menu' { exit (Invoke-Python @((Join-Path $PSScriptRoot 'civtuner.py'), 'menu')) }
    { $_ -in 'lua', 'states' } { Invoke-Tuner }
    'start' { Invoke-Start }
    'stop' { Invoke-Stop }
    'key' { Invoke-Key }
    'sr' { Format-Lines (Read-NewLogLines) }
    'wait' {
        if (-not (Wait-ForScreenReader $Arg $Timeout)) { Write-Output "Timed out waiting for '$Arg'"; exit 1 }
    }
    'shot' { Invoke-Shot }
    'keymap' { Invoke-Keymap }
    'status' {
        $game = Get-GameProcess
        "game: $(if ($game) { "running (pid $($game.Id), '$($game.MainWindowTitle)')" } else { 'not running' })"
        "console app: $(if (Get-ConsoleProcess) { 'running' } else { 'not running' })"
    }
}
