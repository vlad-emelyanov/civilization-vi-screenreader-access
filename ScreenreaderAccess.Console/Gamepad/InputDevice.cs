namespace ScreenreaderAccess.Console.Gamepad;

/// <summary>Which device the player used last: true after the pad made the app inject keys, false after a physical key. Read by the speech path.</summary>
public static class InputDevice
{
    private static volatile bool _padIsCurrent;
    public static bool PadIsCurrent => _padIsCurrent;

    private static long _lastPadKeyTicks;

    /// <summary>When the pad last sent a key the player pressed (UTC ticks; 0 = never). The speech path lets the next message
    /// interrupt again after it, as JAWS does on its own for a key it hears (posted pad keys bypass JAWS's keyboard hook).</summary>
    public static long LastPadKeyTicks => Interlocked.Read(ref _lastPadKeyTicks);

    public static void NotePadKey() => Interlocked.Exchange(ref _lastPadKeyTicks, DateTime.UtcNow.Ticks);

    /// <summary>Returns true when the value changed.</summary>
    public static bool Set(bool pad)
    {
        bool changed = _padIsCurrent != pad;
        _padIsCurrent = pad;
        return changed;
    }
}
