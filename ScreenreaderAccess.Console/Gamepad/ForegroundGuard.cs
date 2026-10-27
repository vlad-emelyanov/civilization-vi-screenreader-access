using System.Diagnostics;
using System.Runtime.InteropServices;

namespace ScreenreaderAccess.Console.Gamepad;

public sealed class ForegroundGuard
{
    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);

    private IntPtr _lastHwnd;
    private bool _result;
    private long _checkedAt = long.MinValue;

    public bool IsGameForeground()
    {
        IntPtr hwnd = GetForegroundWindow();   // every call: only the process lookup is cached
        if (hwnd == IntPtr.Zero) return false;
        long now = Environment.TickCount64;
        if (hwnd == _lastHwnd && now - _checkedAt < 2000) return _result;
        _lastHwnd = hwnd;
        _checkedAt = now;
        _result = false;
        try
        {
            GetWindowThreadProcessId(hwnd, out uint pid);
            if (pid != 0)
            {
                using Process p = Process.GetProcessById((int)pid);
                _result = p.ProcessName.StartsWith("CivilizationVI", StringComparison.OrdinalIgnoreCase);
            }
        }
        catch { /* process gone: not the game */ }
        return _result;
    }
}
