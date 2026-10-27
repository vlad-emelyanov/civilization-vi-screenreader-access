namespace ScreenreaderAccess.Console.Gamepad;

/// <summary>Which device the player used last: true after the pad made the app inject keys, false after a physical key. Read by the speech path.</summary>
public static class InputDevice
{
    private static volatile bool _padIsCurrent;
    public static bool PadIsCurrent => _padIsCurrent;

    /// <summary>Returns true when the value changed.</summary>
    public static bool Set(bool pad)
    {
        bool changed = _padIsCurrent != pad;
        _padIsCurrent = pad;
        return changed;
    }
}
