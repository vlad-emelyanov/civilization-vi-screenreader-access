using System.Diagnostics;
using System.Runtime.InteropServices;

namespace ScreenreaderAccess.Console.Gamepad;

public sealed class ForegroundGuard
{
    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);

    private bool _result;
    private long _checkedAt = long.MinValue;

    public bool IsGameForeground()
    {
        long now = Environment.TickCount64;
        if (now - _checkedAt < 250) return _result;
        _checkedAt = now;
        _result = false;
        try
        {
            IntPtr hwnd = GetForegroundWindow();
            if (hwnd != IntPtr.Zero)
            {
                GetWindowThreadProcessId(hwnd, out uint pid);
                if (pid != 0)
                {
                    using Process p = Process.GetProcessById((int)pid);
                    _result = p.ProcessName.StartsWith("CivilizationVI", StringComparison.OrdinalIgnoreCase);
                }
            }
        }
        catch { /* process gone: not the game */ }
        return _result;
    }
}
