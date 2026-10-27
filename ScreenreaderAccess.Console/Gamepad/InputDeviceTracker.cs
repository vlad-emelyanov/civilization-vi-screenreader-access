using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace ScreenreaderAccess.Console.Gamepad;

/// <summary>WH_KEYBOARD_LL hook on its own message-loop thread: reports physical (non-injected, non-ours) key downs. Never swallows keys.</summary>
public sealed class InputDeviceTracker : IDisposable
{
    private const int WH_KEYBOARD_LL = 13, WM_KEYDOWN = 0x100, WM_SYSKEYDOWN = 0x104, LLKHF_INJECTED = 0x10;

    [StructLayout(LayoutKind.Sequential)]
    private struct KBDLLHOOKSTRUCT { public uint vkCode, scanCode, flags, time; public UIntPtr dwExtraInfo; }
    private delegate IntPtr HookProc(int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true)] private static extern IntPtr SetWindowsHookEx(int id, HookProc proc, IntPtr hMod, uint threadId);
    [DllImport("user32.dll")] private static extern bool UnhookWindowsHookEx(IntPtr hook);
    [DllImport("user32.dll")] private static extern IntPtr CallNextHookEx(IntPtr hook, int nCode, IntPtr wParam, IntPtr lParam);
    [DllImport("kernel32.dll")] private static extern IntPtr GetModuleHandle(string? name);

    private readonly Action _onPhysicalKey;
    private readonly HookProc _proc;   // field: keeps the delegate alive
    private readonly Thread _thread;
    private readonly ManualResetEventSlim _ready = new(false);
    private IntPtr _hook;
    private ApplicationContext? _context;

    public InputDeviceTracker(Action onPhysicalKey)
    {
        _onPhysicalKey = onPhysicalKey;
        _proc = Callback;
        _thread = new Thread(Run) { Name = "InputDeviceTracker", IsBackground = true };
        _thread.SetApartmentState(ApartmentState.STA);
        _thread.Start();
        _ready.Wait(2000);
        if (_hook == IntPtr.Zero) throw new InvalidOperationException("Keyboard hook could not be installed.");
    }

    private void Run()
    {
        try
        {
            _hook = SetWindowsHookEx(WH_KEYBOARD_LL, _proc, GetModuleHandle(null), 0);
        }
        finally { _ready.Set(); }
        if (_hook == IntPtr.Zero) return;
        _context = new ApplicationContext();
        Application.Run(_context);
        UnhookWindowsHookEx(_hook);
        _hook = IntPtr.Zero;
    }

    private IntPtr Callback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        try
        {
            if (nCode >= 0 && ((int)wParam == WM_KEYDOWN || (int)wParam == WM_SYSKEYDOWN))
            {
                KBDLLHOOKSTRUCT k = Marshal.PtrToStructure<KBDLLHOOKSTRUCT>(lParam);
                if ((k.flags & LLKHF_INJECTED) == 0 && k.dwExtraInfo != KeyInjector.Magic)
                    _onPhysicalKey();
            }
        }
        catch { /* a hook must never throw */ }
        return CallNextHookEx(_hook, nCode, wParam, lParam);
    }

    public void Dispose()
    {
        try { _context?.ExitThread(); } catch { }
        _thread.Join(500);
    }
}
