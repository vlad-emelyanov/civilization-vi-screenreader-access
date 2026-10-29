using System.Windows.Forms;

namespace ScreenreaderAccess.Console.Gamepad;

/// <summary>A key to inject: virtual key plus an optional held Left Control (and Left Shift: the wheel's keys).</summary>
public readonly record struct PadKey(Keys Key, bool control = false, bool shift = false)
{
    public bool Control => control;
    public bool Shift => shift;
}

/// <summary>Canonical button -> key table.
/// RT held (>= 128) is a Shift modifier: the left stick directions, D-pad up/down (Home/End) and A (Enter) are injected with Left Shift held
/// (Shift+Arrows, Shift+Home/End, Shift+Enter). Never Shift+Tab: D-pad left/right stay Control+Tab / Tab (Shift+Tab opens the Steam overlay).
/// While LB or RB is held (group jump), the left stick up / down and D-pad up / down are PageUp / PageDown instead (with the same repeat, no Shift),
/// and the held bumper's F14 / F15 KeyUp is then not sent (the same rule as RT used as Shift).
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
        ["PageUp"] = new PadKey(Keys.PageUp),
        ["PageDown"] = new PadKey(Keys.PageDown),
        ["ModeOn"] = new PadKey(Keys.F22),
        ["ModeOff"] = new PadKey(Keys.F23),
    };

    public static PadKey Get(PadButton button) => Table[button.ToString()];

    /// <summary>The wheel (held LT + left stick, see GamepadMapper.WheelSlot): slot 0..23 clockwise from straight up is Shift+F13..F24 (0..11)
    /// and Control+Shift+F13..F24 (12..23). Mirrored in Accessibility/Gamepad.lua (Gamepad.WheelOf); with Shift the F-keys are never buttons there.</summary>
    public const int WheelSlots = 24;

    public static PadKey WheelKey(int slot) => new((Keys)((int)Keys.F13 + slot % 12), control: slot >= 12, shift: true);

    public static PadKey KeyOf(KeyEvent e) => e.Button == PadButton.Wheel ? WheelKey(e.Slot) : Get(e.Button);
}
