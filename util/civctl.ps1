<#
.SYNOPSIS
  Agent/dev harness for driving Civilization VI with the ScreenReaderAccess mod.

.EXAMPLE
  .\util\civctl.ps1 start                 # launch game + console app, wait for main menu
  .\util\civctl.ps1 sr                    # print new screen reader lines since last call
  .\util\civctl.ps1 key Down              # press a key (Down, Up, Enter, Escape, Tab, A, F1, ...)
  .\util\civctl.ps1 key Down -Count 3     # press it several times
  .\util\civctl.ps1 wait 'Exit to Desktop' -Timeout 10   # wait for a matching screen reader line
  .\util\civctl.ps1 shot                  # screenshot game window, prints the png path
  .\util\civctl.ps1 stop                  # kill game + console app

  `key` prints the screen reader lines that the keypress produced (waits -Settle ms for them).
  Use -All with `sr`/`key` to see every new Lua.log line rather than only #SCREENREADER lines.
#>
param(
    [Parameter(Position = 0, Mandatory)]
    [ValidateSet('start', 'stop', 'key', 'sr', 'wait', 'shot', 'status')]
    [string]$Command,
    [Parameter(Position = 1)]
    [string]$Arg,
    [int]$Count = 1,
    [int]$Timeout = 120,
    [int]$Settle = 600,
    [switch]$All,
    [string]$Out
)

$ErrorActionPreference = 'Stop'

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
    # Returns Lua.log lines appended since the stored cursor (line index). Resets if the log was recreated.
    if (-not (Test-Path $LuaLog)) { return @() }
    $cursor = 0
    if (Test-Path $CursorFile) { $cursor = [int](Get-Content $CursorFile) }
    $fs = [IO.File]::Open($LuaLog, 'Open', 'Read', 'ReadWrite')
    try {
        $reader = New-Object IO.StreamReader($fs)
        $lines = $reader.ReadToEnd() -split "`r?`n" | Where-Object { $_ -ne '' }
    } finally { $fs.Dispose() }
    $lines = @($lines)
    if ($lines.Count -lt $cursor) { $cursor = 0 }
    Set-Content $CursorFile $lines.Count
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
        foreach ($l in (Read-NewLogLines)) {
            $f = Format-Lines @($l)
            # Write-Host: plain output would be swallowed into this function's return value.
            if ($f) { Write-Host $f }
            if ($l.Contains($ScreenReaderMarker) -and $l -match $pattern) { return $true }
        }
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
    Set-Content $CursorFile 0
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
    $vk = [uint32][System.Windows.Forms.Keys]::Parse([System.Windows.Forms.Keys], $Arg, $true)
    if (-not [CivCtl.Native]::Focus($game.MainWindowHandle)) { Write-Warning 'Could not bring game window to foreground; key may go elsewhere.' }
    # Output that arrived after the previous command returned; shown rather than dropped so nothing is missed.
    $pending = Format-Lines (Read-NewLogLines)
    if ($pending) { $pending | ForEach-Object { "(earlier) $_" } }
    for ($i = 0; $i -lt $Count; $i++) {
        [CivCtl.Native]::Tap($vk, 40)
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

function Invoke-Stop {
    Get-Process -Name $GameProcessNames -ErrorAction SilentlyContinue | Stop-Process -Force
    Get-ConsoleProcess | Stop-Process -Force
    Write-Output 'Stopped.'
}

switch ($Command) {
    'start' { Invoke-Start }
    'stop' { Invoke-Stop }
    'key' { Invoke-Key }
    'sr' { Format-Lines (Read-NewLogLines) }
    'wait' {
        if (-not (Wait-ForScreenReader $Arg $Timeout)) { Write-Output "Timed out waiting for '$Arg'"; exit 1 }
    }
    'shot' { Invoke-Shot }
    'status' {
        $game = Get-GameProcess
        "game: $(if ($game) { "running (pid $($game.Id), '$($game.MainWindowTitle)')" } else { 'not running' })"
        "console app: $(if (Get-ConsoleProcess) { 'running' } else { 'not running' })"
    }
}
