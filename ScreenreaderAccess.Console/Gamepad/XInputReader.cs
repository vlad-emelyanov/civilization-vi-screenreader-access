using System.Runtime.InteropServices;

namespace ScreenreaderAccess.Console.Gamepad;

/// <summary>Reads the first connected XInput pad (slots 0..3). An empty slot is re-checked only every 2 s.</summary>
public sealed class XInputReader
{
    [StructLayout(LayoutKind.Sequential)]
    private struct XINPUT_GAMEPAD { public ushort wButtons; public byte bLeftTrigger, bRightTrigger; public short sThumbLX, sThumbLY, sThumbRX, sThumbRY; }
    [StructLayout(LayoutKind.Sequential)]
    private struct XINPUT_STATE { public uint dwPacketNumber; public XINPUT_GAMEPAD Gamepad; }

    [DllImport("xinput1_4.dll", EntryPoint = "XInputGetState")] private static extern uint GetState14(uint index, out XINPUT_STATE state);
    [DllImport("xinput9_1_0.dll", EntryPoint = "XInputGetState")] private static extern uint GetState910(uint index, out XINPUT_STATE state);

    private const uint ERROR_SUCCESS = 0;
    private const long RecheckMs = 2000;

    private bool _use910;
    private int _slot = -1;
    private long _lastScan = -RecheckMs;   // not long.MinValue: nowMs - MinValue overflows negative and the first scan never happens

    public int Slot => _slot;

    private uint Get(uint i, out XINPUT_STATE s)
    {
        if (!_use910)
        {
            try { return GetState14(i, out s); }
            catch (DllNotFoundException) { _use910 = true; }
            catch (EntryPointNotFoundException) { _use910 = true; }
        }
        try { return GetState910(i, out s); }
        catch (Exception) { s = default; return 1167; }   // no XInput at all: behave as "no controller"
    }

    /// <summary>True with a snapshot when a pad is connected. <paramref name="nowMs"/> is a monotonic clock.</summary>
    public bool TryRead(long nowMs, out GamepadState state)
    {
        state = default;
        if (_slot >= 0)
        {
            if (Get((uint)_slot, out XINPUT_STATE s) == ERROR_SUCCESS) { state = Convert(s); return true; }
            _slot = -1;
            _lastScan = nowMs;
            return false;
        }
        if (nowMs - _lastScan < RecheckMs) return false;
        _lastScan = nowMs;
        for (uint i = 0; i < 4; i++)
        {
            if (Get(i, out XINPUT_STATE s) == ERROR_SUCCESS)
            {
                _slot = (int)i;
                state = Convert(s);
                return true;
            }
        }
        return false;
    }

    public bool TryRead(out GamepadState state) => TryRead(Environment.TickCount64, out state);

    private static GamepadState Convert(XINPUT_STATE s) =>
        new(s.Gamepad.wButtons, s.Gamepad.bLeftTrigger, s.Gamepad.bRightTrigger,
            s.Gamepad.sThumbLX, s.Gamepad.sThumbLY, s.Gamepad.sThumbRX, s.Gamepad.sThumbRY);
}
