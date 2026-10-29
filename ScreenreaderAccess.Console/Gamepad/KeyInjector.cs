using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace ScreenreaderAccess.Console.Gamepad;

/// <summary>Keyboard events for the game. Default: WM_KEYDOWN / WM_KEYUP posted to the foreground window (the game: GamepadService only
/// injects while it is in front). Posted keys bypass the low-level keyboard hooks, so screen readers (JAWS speaks "Shift F13") do not
/// hear them, and the game reads the modifiers from the posted Shift / Control messages in order, so no delays are needed (verified in
/// game: posted Shift+F19, Control+Shift+F13, arrows). With post = false (--gamepad-sendinput): SendInput with scan codes (like
/// util/civctl.ps1 Chord), every event carrying <see cref="Magic"/>, with the modifier delays.</summary>
public sealed class KeyInjector
{
    public static readonly UIntPtr Magic = new(0x53524147);
    private readonly bool _post;
    private readonly int ModifierDelayMs, TapHoldMs;

    public KeyInjector(bool post = true)
    {
        _post = post;
        ModifierDelayMs = post ? 0 : 40;
        TapHoldMs = post ? 0 : 15;
    }

    private static void Pause(int ms) { if (ms > 0) Thread.Sleep(ms); }

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
    [DllImport("user32.dll")] private static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    private const uint WM_KEYDOWN = 0x0100, WM_KEYUP = 0x0101;

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
            Pause(ModifierDelayMs);
            Send(k.Key, false);
        }
        catch { for (int i = sent - 1; i >= 0; i--) Send(mods[i], true); throw; }
    }

    public void KeyUp(PadKey k, bool shift = false)
    {
        List<Keys> mods = Modifiers(k, shift);
        if (mods.Count == 0) { Send(k.Key, true); return; }
        try { Send(k.Key, true); Pause(ModifierDelayMs); }
        finally { for (int i = mods.Count - 1; i >= 0; i--) Send(mods[i], true); }
    }

    public void Tap(PadKey k, bool shift = false)
    {
        KeyDown(k, shift);
        try { Pause(TapHoldMs); }
        finally { KeyUp(k, shift); }
    }

    private static bool IsExtended(uint vk) =>
        (vk >= 0x21 && vk <= 0x28) || vk == 0x2D || vk == 0x2E || vk == 0x6F || vk == 0xA3 || vk == 0xA5;   // PgUp..Down, Ins, Del, divide, right ctrl/alt

    private void Send(Keys key, bool up)
    {
        uint vk = (uint)key;
        if (_post)
        {
            // the generic VK for the left modifiers (what a window receives for a physical Shift / Control)
            uint wvk = key == Keys.LShiftKey ? 0x10u : key == Keys.LControlKey ? 0x11u : vk;
            long lp = 1 | ((long)MapVirtualKey(vk, 0) << 16);
            if (IsExtended(vk)) lp |= 1L << 24;
            if (up) lp |= (1L << 30) | (1L << 31);
            PostMessage(GetForegroundWindow(), up ? WM_KEYUP : WM_KEYDOWN, (IntPtr)wvk, (IntPtr)lp);
            return;
        }
        uint flags = KEYEVENTF_SCANCODE;
        if (IsExtended(vk)) flags |= KEYEVENTF_EXTENDEDKEY;
        if (up) flags |= KEYEVENTF_KEYUP;
        INPUT inp = new() { type = INPUT_KEYBOARD };
        inp.u.ki = new KEYBDINPUT { wVk = (ushort)vk, wScan = (ushort)MapVirtualKey(vk, 0), dwFlags = flags, dwExtraInfo = Magic };
        SendInput(1, new[] { inp }, Marshal.SizeOf<INPUT>());
    }
}
