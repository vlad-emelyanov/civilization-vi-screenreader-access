using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace ScreenreaderAccess.Console.Gamepad;

/// <summary>SendInput keyboard events with scan codes (like util/civctl.ps1 Chord). Every event carries <see cref="Magic"/>.</summary>
public sealed class KeyInjector
{
    public static readonly UIntPtr Magic = new(0x53524147);
    private const int ModifierDelayMs = 40, TapHoldMs = 15;

    [StructLayout(LayoutKind.Sequential)]
    private struct KEYBDINPUT { public ushort wVk; public ushort wScan; public uint dwFlags; public uint time; public UIntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Sequential)]
    private struct MOUSEINPUT { public int dx, dy; public uint mouseData, dwFlags, time; public UIntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Explicit)]
    private struct InputUnion { [FieldOffset(0)] public MOUSEINPUT mi; [FieldOffset(0)] public KEYBDINPUT ki; }
    [StructLayout(LayoutKind.Sequential)]
    private struct INPUT { public uint type; public InputUnion u; }

    private const uint INPUT_KEYBOARD = 1, KEYEVENTF_EXTENDEDKEY = 1, KEYEVENTF_KEYUP = 2, KEYEVENTF_SCANCODE = 8;

    [DllImport("user32.dll")] private static extern uint SendInput(uint n, INPUT[] inputs, int size);
    [DllImport("user32.dll")] private static extern uint MapVirtualKey(uint code, uint mapType);

    public void KeyDown(PadKey k, bool shift = false)
    {
        Keys? mod = shift ? Keys.LShiftKey : k.Control ? Keys.LControlKey : null;
        if (mod is null) { Send(k.Key, false); return; }
        Send(mod.Value, false);
        try { Thread.Sleep(ModifierDelayMs); Send(k.Key, false); }
        catch { Send(mod.Value, true); throw; }
    }

    public void KeyUp(PadKey k, bool shift = false)
    {
        Keys? mod = shift ? Keys.LShiftKey : k.Control ? Keys.LControlKey : null;
        if (mod is null) { Send(k.Key, true); return; }
        try { Send(k.Key, true); Thread.Sleep(ModifierDelayMs); }
        finally { Send(mod.Value, true); }
    }

    public void Tap(PadKey k, bool shift = false)
    {
        KeyDown(k, shift);
        try { Thread.Sleep(TapHoldMs); }
        finally { KeyUp(k, shift); }
    }

    private static bool IsExtended(uint vk) =>
        (vk >= 0x21 && vk <= 0x28) || vk == 0x2D || vk == 0x2E || vk == 0x6F || vk == 0xA3 || vk == 0xA5;   // PgUp..Down, Ins, Del, divide, right ctrl/alt

    private static void Send(Keys key, bool up)
    {
        uint vk = (uint)key;
        uint flags = KEYEVENTF_SCANCODE;
        if (IsExtended(vk)) flags |= KEYEVENTF_EXTENDEDKEY;
        if (up) flags |= KEYEVENTF_KEYUP;
        INPUT inp = new() { type = INPUT_KEYBOARD };
        inp.u.ki = new KEYBDINPUT { wVk = (ushort)vk, wScan = (ushort)MapVirtualKey(vk, 0), dwFlags = flags, dwExtraInfo = Magic };
        SendInput(1, new[] { inp }, Marshal.SizeOf<INPUT>());
    }
}
