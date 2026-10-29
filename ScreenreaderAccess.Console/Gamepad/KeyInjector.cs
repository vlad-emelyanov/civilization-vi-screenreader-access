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

    // Shift (RT held, or a wheel key) and Control (second bank); RT-as-Shift never meets a second-bank key, the wheel's keys may have both.
    private static List<Keys> Modifiers(PadKey k, bool shift)
    {
        List<Keys> mods = new();
        if (k.Control && !(shift && !k.Shift)) mods.Add(Keys.LControlKey);
        if (shift || k.Shift) mods.Add(Keys.LShiftKey);
        return mods;
    }

    public void KeyDown(PadKey k, bool shift = false)
    {
        List<Keys> mods = Modifiers(k, shift);
        if (mods.Count == 0) { Send(k.Key, false); return; }
        int sent = 0;
        try
        {
            foreach (Keys mod in mods) { Send(mod, false); sent++; }
            Thread.Sleep(ModifierDelayMs);
            Send(k.Key, false);
        }
        catch { for (int i = sent - 1; i >= 0; i--) Send(mods[i], true); throw; }
    }

    public void KeyUp(PadKey k, bool shift = false)
    {
        List<Keys> mods = Modifiers(k, shift);
        if (mods.Count == 0) { Send(k.Key, true); return; }
        try { Send(k.Key, true); Thread.Sleep(ModifierDelayMs); }
        finally { for (int i = mods.Count - 1; i >= 0; i--) Send(mods[i], true); }
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
