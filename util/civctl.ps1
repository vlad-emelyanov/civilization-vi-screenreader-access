<#
.SYNOPSIS
  Agent/dev harness for driving Civilization VI with the ScreenReaderAccess mod.

.EXAMPLE
  .\util\civctl.ps1 build                 # build + deploy the mod with ModBuddy (refuses while the game runs unless -Force; kills hot reload until a restart)
  .\util\civctl.ps1 deploy                # copy changed mod files straight into the running game's deployed mod folder: hot reload, no restart
  .\util\civctl.ps1 lua InGame 'print(Game.GetCurrentGameTurn())'   # run Lua in a game Lua state via FireTuner (needs EnableTuner 1)
  .\util\civctl.ps1 states                # list the tuner's Lua states
  .\util\civctl.ps1 deploy -NoLint        # same without the lint pass (deploy lints the changed .lua files first; lint errors refuse the deploy)
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
  .\util\civctl.ps1 status                # game / console / lock / front end or in game + turn
  .\util\civctl.ps1 save bug-foo -Purpose 'why'   # named save of the running game -> test\fixtures\bug-foo.Civ6Save + .txt sidecar
  .\util\civctl.ps1 load early-start     # load a fixture (leaves the current game first; LoadGame only works from the main menu)
  .\util\civctl.ps1 fixtures             # list fixtures
  .\util\civctl.ps1 newgame early        # create a game from util\profiles\early.lua (~45 s), then `save early-start`
  .\util\civctl.ps1 autoplay 29 -Save medieval-t100   # let the AI play n turns (observing as player 0), poll every 30 s, then save the fixture
  .\util\civctl.ps1 unlock                # release the driving lock (see below)

  Lock (owner lease): commands that drive the game take %TEMP%\civctl\lock for -Owner (or $env:CIVCTL_OWNER, default 'default') and
  keep it between commands. Another owner gets "game in use by X, last used N s ago" (exit 6) while the owner's last use is
  younger than 10 min; after that the lease is taken over with a warning. `unlock` releases it.
  .\util\civctl.ps1 regress all           # speech regression scripts (python util\civregress.py; extra words are passed on: regress all --share-load)
  Crash / hang: key, wait, sr, lua, save, load print GAME CRASHED / GAME HUNG (with the crash dump path) and exit 5.

  `key` prints the screen reader lines that the keypress produced (waits -Settle ms for them).
  Use -All with `sr`/`key` to see every new Lua.log line rather than only #SCREENREADER lines.
#>
param(
    [Parameter(Position = 0, Mandatory)]
    [ValidateSet('build', 'deploy', 'reload', 'lua', 'states', 'menu', 'start', 'stop', 'key', 'sr', 'wait', 'shot', 'status', 'keymap', 'save', 'load', 'fixtures', 'newgame', 'unlock', 'autoplay', 'regress')]
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
    [int]$HangGrace = 0,    # seconds an unresponsive window (with a silent Lua.log) is tolerated before GAME HUNG; load/newgame/autoplay/wait default to 150
    [switch]$NoLint,        # deploy/reload: skip the luacheck pass over the changed .lua files
    [string]$Out,
    [string]$File,          # lua: read the Lua code from this file instead of the command line
    [string]$Owner,         # name of the agent driving the game (lock file); default $env:CIVCTL_OWNER or 'default'
    [string]$Purpose,       # save: why this fixture exists (goes into the sidecar)
    [string]$Profile,       # save: game profile it came from (newgame passes it)
    [string]$Save           # autoplay: fixture name to save when it finishes
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)   # speech lines can hold non-ASCII; the regress runner decodes UTF-8

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
$FixtureDir = Join-Path $RepoRoot 'test\fixtures'
$LockFile = Join-Path $StateDir 'lock'
$LockLeaseMinutes = 10
$script:HungSince = $null
$StopMarker = Join-Path $StateDir 'stopped.txt'   # written by `stop`, removed by `start`: a deliberate stop is not a crash

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

# --- lock: only one agent drives the game ---------------------------------------------------------------------------------------------
function Get-Owner { if ($Owner) { $Owner } elseif ($env:CIVCTL_OWNER) { $env:CIVCTL_OWNER } else { 'default' } }

function Enter-Lock {
    # Owner lease. The lock file holds the owner's name; its LastWriteTime is the last use. It is NOT released when a command ends:
    # the owner keeps it between commands (every command of the owner refreshes it; wait/autoplay refresh it while running) and
    # releases it with `civctl unlock`. Another owner is refused (exit 6) while the lease is fresh (< $LockLeaseMinutes idle);
    # after that the lease is taken over with a warning. Creating the file is atomic (CreateNew).
    $me = Get-Owner
    for ($try = 0; $try -lt 5; $try++) {
        try {
            $fs = [IO.File]::Open($LockFile, 'CreateNew', 'Write', 'Read')
            try { $b = [Text.Encoding]::UTF8.GetBytes($me); $fs.Write($b, 0, $b.Length) } finally { $fs.Dispose() }
            $script:LockHeld = $true
            return
        } catch [IO.IOException] {
            if (-not (Test-Path $LockFile)) { continue }
            # An empty file is a lock being written right now (create and write are two steps): read again before judging.
            $holder = $null
            for ($r = 0; $r -lt 10 -and -not $holder; $r++) { $holder = (Get-Content $LockFile -TotalCount 1 -ErrorAction SilentlyContinue); if (-not $holder) { Start-Sleep -Milliseconds 100 } }
            if (-not $holder -and (Test-Path $LockFile) -and ((Get-Date) - (Get-Item $LockFile).LastWriteTime).TotalSeconds -lt 5) { continue }
            $idle = ((Get-Date) - (Get-Item $LockFile).LastWriteTime).TotalSeconds
            if ($holder -eq $me) { (Get-Item $LockFile).LastWriteTime = Get-Date; $script:LockHeld = $true; return }
            if ($holder -and $idle -lt $LockLeaseMinutes * 60) {
                Write-Output ("game in use by {0}, last used {1:N0} s ago (lease {2} min). Ask them to run ``civctl unlock``, wait, or run ``civctl unlock`` yourself if they are gone. You are '{3}'." -f $holder, $idle, $LockLeaseMinutes, $me)
                exit 6
            }
            if ($holder) { Write-Warning ("Taking over the expired lease of '{0}' (idle {1:N0} s)." -f $holder, $idle) }
            Remove-Item $LockFile -Force -ErrorAction SilentlyContinue
        }
    }
    throw 'Could not take the civctl lock.'
}

function Quit-Civctl([int]$code) { Exit-Lock; exit $code }   # `exit` skips the finally/cleanup: always leave through here

function Update-Lock { if ($script:LockHeld -and (Test-Path $LockFile)) { try { (Get-Item $LockFile).LastWriteTime = Get-Date } catch { } } }

function Exit-Lock { Update-Lock }   # the lease stays with the owner; only `unlock` releases it

function Invoke-Unlock {
    if (Test-Path $LockFile) {
        $holder = Get-Content $LockFile -TotalCount 1
        Remove-Item $LockFile -Force
        Write-Output "Lock released (was held by '$holder')."
    } else { Write-Output 'No lock was held.' }
}

# --- crash / hang detection -------------------------------------------------------------------------------------------------------
function Get-CrashDump {
    $root = Join-Path $env:LOCALAPPDATA "Firaxis Games\Sid Meier's Civilization VI"
    $f = foreach ($d in 'dumps', 'packagedDumps') {
        $dir = Join-Path $root $d
        if (Test-Path $dir) { Get-ChildItem $dir -Recurse -File -ErrorAction SilentlyContinue }
    }
    $f | Where-Object { $_.LastWriteTime -gt (Get-Date).AddMinutes(-5) } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
}

# Throws 'CIVCTL5:...' (crashed/hung, exit 5) or 'CIVCTL1:...' (not running). -Grace: seconds an unresponsive window is tolerated;
# -Block waits for it here, otherwise the unresponsive time is tracked across calls (for polling loops).
function Assert-GameHealthy([int]$Grace = 0, [switch]$Block, [switch]$AllowStopped) {
    $rep = Get-Process -Name 'FiraxisBugReporter' -ErrorAction SilentlyContinue
    $procs = @(Get-Process -Name $GameProcessNames -ErrorAction SilentlyContinue)
    if ($procs.Count -gt 0 -and (Test-Path $StopMarker)) {
        # A game that started after the last `stop` (launched by hand or by Steam) makes the marker obsolete.
        $mt = (Get-Item $StopMarker).LastWriteTime
        try { if ($procs[0].StartTime -gt $mt) { Remove-Item $StopMarker -Force -ErrorAction SilentlyContinue } } catch { }
    }
    if ($rep -and $procs.Count -gt 0) {
        # The reporter also runs next to a healthy game (seen after a fresh build) and while a long load makes the window
        # briefly "not responding". With a live game process it is a crash only if a dump is newer than the game process;
        # otherwise the hang logic below decides.
        $gp = $procs | Select-Object -First 1
        $d = Get-CrashDump
        $newer = $false
        try { $newer = $d -and $d.LastWriteTime -gt $gp.StartTime } catch { }
        if (-not $newer) { $rep = $null }
    }
    $deliberate = (-not $rep) -and $procs.Count -eq 0 -and (Test-Path $StopMarker)   # `stop` ran, nothing started since
    if ($rep -or $procs.Count -eq 0) {
        $dump = if ($deliberate) { $null } else { Get-CrashDump }
        if ($rep -or $dump) {
            $msg = if ($procs.Count -gt 0) { 'GAME CRASHED (a fresh crash dump exists and FiraxisBugReporter.exe is running).' } elseif ($rep) { 'GAME CRASHED (FiraxisBugReporter.exe is running, the game process is gone).' } else { 'GAME CRASHED (the game process is gone).' }
            if ($dump) { $msg += " Crash dump: $($dump.FullName)" }
            throw "CIVCTL5:$msg Recover: civctl stop; civctl start; civctl load <latest fixture>."
        }
        if ($AllowStopped) { return }
        throw 'CIVCTL1:Game is not running.'
    }
    $p = $procs | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
    if (-not $p) { return }   # still starting up / closing
    if ($HangGrace -gt 0) { $Grace = $HangGrace }
    elseif ($script:DefaultHangGrace -gt $Grace) { $Grace = $script:DefaultHangGrace }
    while ($true) {
        $p.Refresh()
        if ($p.Responding) { $script:HungSince = $null; $script:UnrespSince = $null; return }
        # Hard cap: a frozen window whose Lua.log keeps growing (a print loop) is still a hang after 10 min.
        if (-not $script:UnrespSince) { $script:UnrespSince = Get-Date }
        if (((Get-Date) - $script:UnrespSince).TotalSeconds -ge 600) { throw "CIVCTL5:GAME HUNG (window not responding for 10 min although Lua.log still grows). Take a ``civctl shot``; if it stays frozen: civctl stop; civctl start; civctl load <latest fixture>." }
        # A busy but alive game (long AI turn, load) keeps writing to Lua.log or at least did so recently: not a hang.
        if ((Test-Path $LuaLog) -and ((Get-Date) - (Get-Item $LuaLog).LastWriteTime).TotalSeconds -lt 20) { $script:HungSince = $null; if (-not $Block) { return }; Start-Sleep -Milliseconds 500; continue }
        if (-not $script:HungSince) { $script:HungSince = Get-Date }
        $waited = ((Get-Date) - $script:HungSince).TotalSeconds
        if ($waited -ge $Grace) { break }
        if (-not $Block) { return }
        Start-Sleep -Milliseconds 500
    }
    throw "CIVCTL5:GAME HUNG (window not responding for $([int]$waited) s). Take a ``civctl shot``; if it stays frozen: civctl stop; civctl start; civctl load <latest fixture>."
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

function Wait-ForScreenReader([string]$pattern, [int]$timeoutSec, [bool]$check = $true) {
    Update-Lock
    $deadline = (Get-Date).AddSeconds($timeoutSec)
    $n = 0
    while ((Get-Date) -lt $deadline) {
        if ($check -and ($n++ % 12) -eq 0) { Assert-GameHealthy -Grace 25; Update-Lock }
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
    Remove-Item $StopMarker -Force -ErrorAction SilentlyContinue
    $rep = Get-Process -Name 'FiraxisBugReporter' -ErrorAction SilentlyContinue
    if ($rep) { $rep | Stop-Process -Force; Write-Output 'Killed leftover FiraxisBugReporter.exe (left by a crash).'; Start-Sleep -Seconds 2 }
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
        if (Wait-ForScreenReader 'Main menu' 3 $false) {
            Write-Output 'Main menu ready.'
            return
        }
        $game = Get-GameProcess
        if ($game -and [CivCtl.Native]::Focus($game.MainWindowHandle)) { [CivCtl.Native]::Tap(0x1B, 40) }
    }
    Write-Output "Timed out waiting for main menu after $Timeout s. Try: civctl.ps1 shot"
    Quit-Civctl 1
}

# Keys that JAWS grabs: NumPad +/- toggle the JAWS cursor (arrows, Home, End then stop reaching any window, even after a game restart);
# the other numpad keys and Insert are JAWS commands too. Divide stays allowed (a game hotkey).
$JawsReservedKeys = @('Add', 'Subtract', 'Multiply', 'Decimal', 'Insert', 'Clear', 'NumPad0', 'NumPad1', 'NumPad2', 'NumPad3', 'NumPad4', 'NumPad5', 'NumPad6', 'NumPad7', 'NumPad8', 'NumPad9')

function Invoke-Key([string]$KeyArg = $Arg, [int]$Count = $Count, [int]$Settle = $Settle) {
    if (-not $KeyArg) { throw 'Usage: civctl.ps1 key <KeyName> [-Count n]' }
    $parts = @($KeyArg -split '\+')
    if ($JawsReservedKeys -contains $parts[-1]) {
        Write-Output "REFUSED: '$($parts[-1])' is a JAWS-reserved key (Add/Subtract toggle the JAWS cursor and break keyboard input system-wide). Use OemPlus / OemMinus for the main keyboard +/-."
        Quit-Civctl 1
    }
    Assert-GameHealthy -Grace 8 -Block
    $game = Get-GameProcess
    if (-not $game) { throw 'CIVCTL1:Game is not running.' }
    # "Shift+E", "Control+Shift+F": modifiers are held around the key. Key names never contain '+' (the + key is OemPlus).
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
        Assert-GameHealthy -Grace 8 -Block
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
        Quit-Civctl 1
    }
    $modBuddy = (Get-Command modbuddy -ErrorAction SilentlyContinue).Source
    if (-not $modBuddy) { $modBuddy = "C:\Program Files (x86)\Steam\steamapps\common\Sid Meier's Civilization VI SDK\ModBuddy\ModBuddy.exe" }
    $outFile = Join-Path $StateDir 'build.txt'
    Remove-Item $outFile -ErrorAction SilentlyContinue
    $p = Start-Process $modBuddy -ArgumentList 'ScreenReaderAccess.civ6sln', '/out', "`"$outFile`"", '/build' -WorkingDirectory $RepoRoot -PassThru
    if (-not $p.WaitForExit($Timeout * 1000)) {
        $p | Stop-Process -Force
        Write-Output "ModBuddy did not finish within $Timeout s (likely stuck on a dialog). Try: civctl.ps1 shot"
        Quit-Civctl 1
    }
    $result = Get-Content $outFile -ErrorAction SilentlyContinue
    $result | Where-Object { $_ -match 'error|warning|Build:' }
    if (-not ($result -match '1 succeeded')) { Quit-Civctl 1 }
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
    if (-not $NoLint) {
        # Lint the .lua files that would be copied (util\lint.py: exit 1 = errors -> refuse; exit 2 = tool problem -> warn and go on).
        $lintFiles = @()
        foreach ($f in (Get-ShippedFiles $src)) {
            if ($f.Extension -ne '.lua') { continue }
            $rel = $f.FullName.Substring($src.Length).TrimStart('\')
            $target = Join-Path $dst $rel
            if ($touch) { if (-not ($touch | Where-Object { $rel -like "*$_*" })) { continue } }
            elseif ((Test-Path $target) -and ([BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($f.FullName))) -eq [BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($target))))) { continue }
            $lintFiles += $f.FullName
        }
        if ($lintFiles.Count -gt 0) {
            $lo = Invoke-PythonCapture (@((Join-Path $PSScriptRoot 'lint.py')) + $lintFiles)
            $lo | ForEach-Object { Write-Output "lint> $_" }
            if ($script:PyExit -eq 1) { Write-Output 'Lint errors: deploy refused (fix them, or pass -NoLint).'; Quit-Civctl 1 }
            if ($script:PyExit -ne 0) { Write-Warning "lint.py failed (exit $($script:PyExit)); deploying anyway." }
        }
    }
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
        Quit-Civctl 1
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
    if ($failed) { Quit-Civctl 1 }
    if ($needsBuild.Count -gt 0) { Quit-Civctl 3 }
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
    if ($Command -eq 'states') { Quit-Civctl (Invoke-Python @($py, 'states')) }
    $code = $null
    if ($File) { $state = $Arg; $code = [IO.File]::ReadAllText($File) }
    else {
        if (-not $Arg) { throw 'Usage: civctl.ps1 lua <state> <code>   (or: lua <state> -File script.lua)' }
        $state, $code = $Arg -split '\s+', 2
    }
    if (-not $state -or -not $code) { throw 'Usage: civctl.ps1 lua <state> <code>   (or: lua <state> -File script.lua)' }
    Assert-GameHealthy -Grace 8 -Block
    # Pass the code through a temp file: quoting Lua (quotes, newlines) through cmd.exe and PowerShell 5.1 argument parsing is unreliable.
    $tmp = Join-Path $StateDir 'tuner.lua'
    [IO.File]::WriteAllText($tmp, $code, (New-Object Text.UTF8Encoding($false)))
    $rc = Invoke-Python @($py, 'lua', '-f', $tmp, $state)
    if ($rc -ne 0) { Assert-GameHealthy -Grace 8 -Block }   # a failed call may mean the game just crashed or froze
    Quit-Civctl $rc
}

function Invoke-Stop {
    Get-Process -Name $GameProcessNames -ErrorAction SilentlyContinue | Stop-Process -Force
    Get-ConsoleProcess | Stop-Process -Force
    Get-Process -Name 'FiraxisBugReporter' -ErrorAction SilentlyContinue | Stop-Process -Force
    # Relaunching while the old process is still tearing down makes the new launch silently exit.
    $deadline = (Get-Date).AddSeconds(30)
    while ((Get-Process -Name $GameProcessNames -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 500 }
    Start-Sleep -Seconds 3
    [IO.File]::WriteAllText($StopMarker, (Get-Date).ToString('o'))
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
        Quit-Civctl 1
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

# --- tuner helpers, fixtures, profiles ---------------------------------------------------------------------------------------------
function Invoke-PythonCapture([string[]]$pyArgs) {
    $py = Get-PythonCommand
    $old = [Console]::OutputEncoding
    [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
    try {
        $out = & $py[0] @($py | Select-Object -Skip 1) -I @pyArgs
        $script:PyExit = $LASTEXITCODE
        return @($out)
    } finally { [Console]::OutputEncoding = $old }
}

# Runs Lua in a tuner state; returns the printed lines ($script:PyExit holds the exit code).
function Invoke-LuaCapture([string]$state, [string]$code) {
    $tmp = Join-Path $StateDir 'tuner.lua'
    [IO.File]::WriteAllText($tmp, $code, (New-Object Text.UTF8Encoding($false)))
    return Invoke-PythonCapture @((Join-Path $PSScriptRoot 'civtuner.py'), 'lua', '-f', $tmp, $state)
}

# 'INGAME <turn> <leader> <civ>', 'FRONTEND', or $null when the tuner cannot be reached.
function Get-GameWhere {
    $o = Invoke-PythonCapture @((Join-Path $PSScriptRoot 'civtuner.py'), 'status')
    if ($script:PyExit -ne 0) { return $null }
    return ($o -join ' ').Trim()
}

function Get-SaveDir { Join-Path ([Environment]::GetFolderPath('MyDocuments')) "My Games\Sid Meier's Civilization VI\Saves\Single" }

function Assert-FixtureName([string]$n) {
    if ($n -notmatch '^[A-Za-z0-9_.-]+$') { throw "Usage: civctl.ps1 <save|load> <name>   (name: letters, digits, _ - . only)" }
}

function Invoke-Save([string]$name) {
    Assert-FixtureName $name
    Assert-GameHealthy -Grace 8 -Block
    $where = Get-GameWhere
    if (-not $where -or -not $where.StartsWith('INGAME')) { throw "save needs a game in progress (state: $where)" }
    $w = $where -split ' '
    $file = Join-Path (Get-SaveDir) "$name.Civ6Save"
    $t0 = Get-Date
    $res = Invoke-LuaCapture 'InGame' ('local s={}; s.Name="' + $name + '"; s.Location=SaveLocations.LOCAL_STORAGE; s.Type=SaveTypes.SINGLE_PLAYER; s.IsAutosave=false; s.IsQuicksave=false; return tostring(Network.SaveGame(s))')
    if ($script:PyExit -ne 0 -or ($res -join '') -notmatch 'true') { throw "Network.SaveGame failed: $($res -join ' ')" }
    $ok = $false
    for ($i = 0; $i -lt 40 -and -not $ok; $i++) {
        Start-Sleep -Milliseconds 250
        if ((Test-Path $file) -and (Get-Item $file).LastWriteTime -ge $t0.AddSeconds(-1) -and (Get-Item $file).Length -gt 0) {
            Start-Sleep -Milliseconds 500   # let the game finish writing
            $ok = $true
        }
    }
    if (-not $ok) { throw "Save file did not appear within 10 s: $file" }
    New-Item -ItemType Directory -Force $FixtureDir | Out-Null
    Copy-Item $file (Join-Path $FixtureDir "$name.Civ6Save") -Force
    $commit = (& git -C $RepoRoot rev-parse --short HEAD)
    Invoke-PythonCapture @((Join-Path $PSScriptRoot 'civfix.py'), 'sidecar', $FixtureDir, $name, "--turn=$($w[1])", "--civ=$($w[3]) / $($w[2])",
        "--profile=$Profile", "--purpose=$Purpose", "--commit=$commit") | Out-Null
    Write-Output "Saved fixture '$name' (turn $($w[1]), $($w[3]), $([int]((Get-Item $file).Length / 1024)) KB) -> test\fixtures\$name.Civ6Save"
}

# Leaves a running game for the main menu (Network.LoadGame crashes the game when called from InGame; it only works from MainMenu).
function Ensure-MainMenu {
    $where = Get-GameWhere
    if ($null -eq $where) { throw 'Tuner not reachable (is the game at least at the main menu, with EnableTuner 1?)' }
    if ($where.StartsWith('INGAME')) {
        Write-Output 'Leaving the current game...'
        Invoke-LuaCapture 'InGame' 'Events.ExitToMainMenu()' | Out-Null
        if (-not (Wait-ForScreenReader 'Single Player' 45)) { throw 'Main menu did not appear after ExitToMainMenu' }
    }
}

function Invoke-LoadOnce([string]$name) {
    if (-not (Get-GameProcess) -and -not (Get-Process -Name 'FiraxisBugReporter' -ErrorAction SilentlyContinue)) { Invoke-Start }
    Assert-GameHealthy -Grace 8 -Block
    Ensure-MainMenu
    $res = Invoke-LuaCapture 'MainMenu' ('local s={}; s.Name="' + $name + '"; s.Location=SaveLocations.LOCAL_STORAGE; s.Type=SaveTypes.SINGLE_PLAYER; s.IsAutosave=false; s.IsQuicksave=false; s.Directory=SaveDirectories.DEFAULT; return tostring(Network.LoadGame(s, ServerType.SERVER_TYPE_NONE))')
    if ($script:PyExit -ne 0 -or ($res -join '') -notmatch 'true') { throw "Network.LoadGame failed: $($res -join ' ')" }
    if (-not (Wait-ForScreenReader 'Continue Game' 90)) { throw "'Continue Game' did not show after loading '$name'" }
    $o = @(Invoke-Key -KeyArg 'Enter' -Count 1 -Settle 3000)
    $o | ForEach-Object { Write-Output $_ }
    if (-not ($o -match 'Turn \d+,') -and -not (Wait-ForScreenReader 'Turn \d+,' 60)) { throw "No turn announcement after loading '$name'" }
}

function Invoke-Load([string]$name) {
    Assert-FixtureName $name
    $src = Join-Path $FixtureDir "$name.Civ6Save"
    $dstDir = Get-SaveDir
    $dst = Join-Path $dstDir "$name.Civ6Save"
    if (-not (Test-Path $src) -and -not (Test-Path $dst)) { throw "No such fixture: $src" }
    if ((Test-Path $src) -and (-not (Test-Path $dst) -or (Get-FileHash $dst -Algorithm MD5).Hash -ne (Get-FileHash $src -Algorithm MD5).Hash)) {
        New-Item -ItemType Directory -Force $dstDir | Out-Null
        Copy-Item $src $dst -Force
        Write-Output "Copied fixture into $dstDir"
    }
    try { Invoke-LoadOnce $name }
    catch {
        if ($_.Exception.Message -notmatch '^CIVCTL5:GAME CRASHED') { throw }   # a hang is never retried: the game may just be loading
        Write-Output ($_.Exception.Message -replace '^CIVCTL5:', '')
        Write-Output 'Crash while loading: restarting the game and retrying once from the main menu.'
        Invoke-Stop
        Invoke-Start
        Invoke-LoadOnce $name
    }
    # A turn-1 save shows the Gathering Storm intro again after loading: close it.
    Start-Sleep -Seconds 2
    $m = Invoke-PythonCapture @((Join-Path $PSScriptRoot 'civtuner.py'), 'menu')
    if ($m -match 'ExpansionIntro') { Invoke-Key -KeyArg 'Escape' -Count 1 -Settle 1500 | ForEach-Object { Write-Output $_ } }
    Write-Output "Loaded '$name'."
}

function Invoke-Fixtures {
    Quit-Civctl (Invoke-Python @((Join-Path $PSScriptRoot 'civfix.py'), 'fixtures', $FixtureDir))
}

function Invoke-NewGame([string]$profileName) {
    if (-not $profileName) { throw 'Usage: civctl.ps1 newgame <profile>   (util\profiles\<profile>.lua)' }
    $pf = Join-Path $PSScriptRoot "profiles\$profileName.lua"
    if (-not (Test-Path $pf)) { throw "No such profile: $pf" }
    if (-not (Get-GameProcess)) { Invoke-Start }
    Assert-GameHealthy -Grace 8 -Block
    Ensure-MainMenu
    # 1. Single Player -> Create Game (creates the AdvancedSetup state)
    $o = @(Invoke-Key -KeyArg 'Enter' -Count 1 -Settle 1200)
    for ($i = 0; $i -lt 8 -and -not ($o -match 'Create Game'); $i++) { $o = @(Invoke-Key -KeyArg 'Down' -Count 1 -Settle 600) }
    if (-not ($o -match 'Create Game')) { throw "Could not reach 'Create Game' (last output: $($o -join ' | '))" }
    $o = @(Invoke-Key -KeyArg 'Enter' -Count 1 -Settle 3000)
    # 2. Apply the profile in the AdvancedSetup state
    $res = Invoke-LuaCapture 'AdvancedSetup' ([IO.File]::ReadAllText($pf))
    $res | ForEach-Object { Write-Output "profile> $_" }
    if ($script:PyExit -ne 0) { throw "Profile script failed ($($res -join ' '))" }
    if ($res -match 'WARN') { Write-Warning 'The profile reported WARN lines (see above).' }
    # 3. Start
    Start-Sleep -Seconds 2
    Invoke-LuaCapture 'AdvancedSetup' 'HostGame()' | Out-Null
    # 4. Load screen -> Begin Game -> first turn
    if (-not (Wait-ForScreenReader 'Begin Game' 240)) { throw 'Begin Game did not show within 240 s' }
    $o = @(Invoke-Key -KeyArg 'Enter' -Count 1 -Settle 3000)
    $o | ForEach-Object { Write-Output $_ }
    if (-not ($o -match 'Turn \d+,') -and -not (Wait-ForScreenReader 'Turn \d+,' 25)) {
        Write-Output 'No turn announcement yet: skipping a possible intro movie with Escape.'
        Invoke-Key -KeyArg 'Escape' -Count 1 -Settle 1500 | Out-Null
        if (-not (Wait-ForScreenReader 'Turn \d+,' 40)) { throw 'No turn announcement after Begin Game' }
    }
    Start-Sleep -Seconds 2
    # A fresh profile shows the Gathering Storm intro and advisor popups: Escape closes them (up to 4 tries).
    for ($i = 0; $i -lt 4; $i++) {
        $m = Invoke-PythonCapture @((Join-Path $PSScriptRoot 'civtuner.py'), 'menu')
        $m | ForEach-Object { Write-Output "menu> $_" }
        if ($script:PyExit -ne 4) { break }
        Invoke-Key -KeyArg 'Escape' -Count 1 -Settle 1500 | ForEach-Object { Write-Output $_ }
    }
    # 5. Fixture
    $script:Profile = $profileName
    if (-not $Purpose) { $script:Purpose = "fresh '$profileName' game at its start (made by civctl newgame)" }
    Invoke-Save "$profileName-start"
}

# AI plays our civ for n turns (InGame state; SetObserveAsPlayer(0), never OBSERVER: that is 3x slower and tears down the UI).
# Polls IsActive every 30 s (more frequent tuner calls slow the game); gives up after ~25 s per turn.
function Invoke-Autoplay([string]$n) {
    if ($n -notmatch '^\d+$' -or [int]$n -lt 1) { throw 'Usage: civctl.ps1 autoplay <turns> [-Save <fixture>]' }
    $turns = [int]$n
    Assert-GameHealthy -Grace 8 -Block
    $where = Get-GameWhere
    if (-not $where -or -not $where.StartsWith('INGAME')) { throw "autoplay needs a game in progress (state: $where)" }
    $startTurn = [int](($where -split ' ')[1])
    $res = Invoke-LuaCapture 'InGame' "AutoplayManager.SetTurns($turns); AutoplayManager.SetReturnAsPlayer(0); AutoplayManager.SetObserveAsPlayer(0); AutoplayManager.SetActive(true); return tostring(AutoplayManager.IsActive())"
    if ($script:PyExit -ne 0) { throw "Could not start autoplay: $($res -join ' ')" }   # IsActive() still says false right after SetActive(true)
    Start-Sleep -Seconds 4
    $chk = Invoke-LuaCapture 'InGame' 'return tostring(AutoplayManager.IsActive()) .. " " .. tostring(Game.GetCurrentGameTurn())'
    if (($chk -join ' ') -notmatch '^\s*(true|false) (\d+)') { throw "Autoplay status unreadable: $($chk -join ' ')" }
    # Small n can be done within the 4 s: not active any more is fine if the turn advanced.
    if ($Matches[1] -eq 'false' -and [int]$Matches[2] -le $startTurn) { throw "Autoplay did not start (IsActive: false, turn still $($Matches[2]))" }
    Write-Output "Autoplay started: $turns turns from turn $startTurn."
    $t0 = Get-Date
    $deadline = $t0.AddSeconds(25 * $turns)
    $lastTurn = $startTurn
    $done = $false
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 30
        Update-Lock
        Assert-GameHealthy -Grace 150 -Block
        $r = Invoke-LuaCapture 'InGame' 'return tostring(AutoplayManager.IsActive()) .. " " .. tostring(Game.GetCurrentGameTurn())'
        $txt = ($r -join ' ').Trim()
        if ($script:PyExit -ne 0 -or $txt -notmatch '^(true|false) (\d+)') { Write-Output ("{0,4:N0}s  tuner busy ({1})" -f ((Get-Date) - $t0).TotalSeconds, $txt); continue }
        $lastTurn = [int]$Matches[2]
        Write-Output ("{0,4:N0}s  turn {1} ({2}/{3})" -f ((Get-Date) - $t0).TotalSeconds, $lastTurn, ($lastTurn - $startTurn), $turns)
        if ($Matches[1] -eq 'false') { $done = $true; break }
    }
    $secs = ((Get-Date) - $t0).TotalSeconds
    if (-not $done) { throw "Autoplay did not finish within $([int]$secs) s (turn $lastTurn)." }
    Write-Output ("Autoplay finished: turn {0} -> {1} in {2:N0} s ({3:N1} s/turn)." -f $startTurn, $lastTurn, $secs, ($secs / [Math]::Max(1, $lastTurn - $startTurn)))
    Start-Sleep -Seconds 3
    if ($Save) {
        if (-not $Purpose) { $script:Purpose = "autoplayed $($lastTurn - $startTurn) turns from turn $startTurn (civctl autoplay)" }
        Invoke-Save $Save
    }
}

function Show-Status {
    $game = Get-GameProcess
    "game: $(if ($game) { "running (pid $($game.Id), '$($game.MainWindowTitle)')" } else { 'not running' })"
    "console app: $(if (Get-ConsoleProcess) { 'running' } else { 'not running' })"
    "lock: $(if (Test-Path $LockFile) { "held by '$(Get-Content $LockFile -TotalCount 1)', last used $([int]((Get-Date) - (Get-Item $LockFile).LastWriteTime).TotalSeconds) s ago" } else { 'free' })"
    Assert-GameHealthy -Grace 8 -Block -AllowStopped
    if ($game) {
        $where = Get-GameWhere
        if ($null -eq $where) { 'location: unknown (tuner not reachable)' }
        elseif ($where.StartsWith('INGAME')) { $w = $where -split ' '; "location: in game, turn $($w[1]) ($($w[3]), $($w[2]))" }
        else { 'location: front end (main menu / setup screens)' }
    }
}

$script:LockHeld = $false
$script:DefaultHangGrace = if ($Command -in 'load', 'newgame', 'autoplay', 'wait') { 150 } else { 0 }
$LockedCommands = @('deploy', 'reload', 'lua', 'start', 'stop', 'key', 'sr', 'wait', 'save', 'load', 'newgame', 'autoplay')
if ($Command -in $LockedCommands) {
    Enter-Lock
}

try {
switch ($Command) {
    'build' { Invoke-Build }
    'deploy' { Invoke-Deploy }
    'reload' { if (-not $Arg) { throw 'Usage: civctl.ps1 reload <file...>  (path or name fragment, e.g. InGameAccess.lua)' }; Invoke-Deploy ($Arg -split '\s+') }
    'menu' { Quit-Civctl (Invoke-Python @((Join-Path $PSScriptRoot 'civtuner.py'), 'menu')) }
    { $_ -in 'lua', 'states' } { Invoke-Tuner }
    'start' { Invoke-Start }
    'stop' { Invoke-Stop }
    'key' { Invoke-Key }
    'sr' { Assert-GameHealthy -AllowStopped; Format-Lines (Read-NewLogLines) }
    'save' { Invoke-Save $Arg }
    'load' { Invoke-Load $Arg }
    'fixtures' { Invoke-Fixtures }
    'newgame' { Invoke-NewGame $Arg }
    'autoplay' { Invoke-Autoplay $Arg }
    'unlock' { Invoke-Unlock }
    'regress' { $env:CIVCTL_OWNER = Get-Owner; Quit-Civctl (Invoke-Python (@('-u', (Join-Path $PSScriptRoot 'civregress.py')) + @(($Arg -split '\s+') | Where-Object { $_ }))) }
    'wait' {
        if (-not (Wait-ForScreenReader $Arg $Timeout)) { Write-Output "Timed out waiting for '$Arg'"; Quit-Civctl 1 }
    }
    'shot' { Invoke-Shot }
    'keymap' { Invoke-Keymap }
    'status' { Show-Status }
}
} catch {
    # 'CIVCTL<exit code>:<message>' errors come from the crash/hang/not-running checks.
    if ($_.Exception.Message -match '^CIVCTL(\d+):(.*)') { Write-Output $Matches[2]; Exit-Lock; exit [int]$Matches[1] }
    Exit-Lock
    throw
}
Exit-Lock
