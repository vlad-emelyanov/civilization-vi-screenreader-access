using System.Windows.Forms;

namespace ScreenreaderAccess.Console.Gamepad;

/// <summary>A key to inject: virtual key plus an optional held Left Control.</summary>
public readonly record struct PadKey(Keys Key, bool control = false)
{
    public bool Control => control;
}

/// <summary>Canonical button -> key table.
/// RT held (>= 128) is a Shift modifier: the left stick directions, D-pad up/down (Home/End) and A (Enter) are injected with Left Shift held
/// (Shift+Arrows, Shift+Home/End, Shift+Enter). Never Shift+Tab: D-pad left/right stay Control+Tab / Tab (Shift+Tab opens the Steam overlay).
/// B, X, Y, LB, RB, LT, the right stick and the stick clicks are not modified. A plain RT press sends F17 down, its release F17 up (the mod acts on
/// the KeyUp). If any Shift-modified event went out while RT was held, the F17 KeyUp on release is suppressed (the Down already went out, so nothing
/// happens) and the service treats RT as released (not in the held set: no F17 up on focus loss or exit either).
///  Mirrored in Accessibility/Gamepad.lua and util/keybindings.py; keep one entry per line.</summary>
public static class GamepadMap
{
    public static readonly IReadOnlyDictionary<string, PadKey> Table = new Dictionary<string, PadKey>
    {
        ["A"] = new PadKey(Keys.Enter),
        ["B"] = new PadKey(Keys.Escape),
        ["X"] = new PadKey(Keys.F13),
        ["Y"] = new PadKey(Keys.Space),
        ["LB"] = new PadKey(Keys.F14),
        ["RB"] = new PadKey(Keys.F15),
        ["LT"] = new PadKey(Keys.F16),
        ["RT"] = new PadKey(Keys.F17),
        ["View"] = new PadKey(Keys.F18),
        ["Menu"] = new PadKey(Keys.F19),
        ["LSClick"] = new PadKey(Keys.F20),
        ["RSClick"] = new PadKey(Keys.F21),
        ["RSUp"] = new PadKey(Keys.F13, control: true),
        ["RSDown"] = new PadKey(Keys.F14, control: true),
        ["RSLeft"] = new PadKey(Keys.F15, control: true),
        ["RSRight"] = new PadKey(Keys.F16, control: true),
        ["LUp"] = new PadKey(Keys.Up),
        ["LDown"] = new PadKey(Keys.Down),
        ["LLeft"] = new PadKey(Keys.Left),
        ["LRight"] = new PadKey(Keys.Right),
        ["DUp"] = new PadKey(Keys.Home),
        ["DDown"] = new PadKey(Keys.End),
        ["DLeft"] = new PadKey(Keys.Tab, control: true),
        ["DRight"] = new PadKey(Keys.Tab),
        ["ModeOn"] = new PadKey(Keys.F22),
        ["ModeOff"] = new PadKey(Keys.F23),
    };

    public static PadKey Get(PadButton button) => Table[button.ToString()];
}
