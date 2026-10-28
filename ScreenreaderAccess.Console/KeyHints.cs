using System.Text;

namespace ScreenreaderAccess.Console;

/// <summary>Expands the [KEY:keyboard] / [KEY:keyboard|button] tokens the mod puts into spoken text (Lua SRKey).
/// Keyboard: the keyboard text. Pad: the button (a known short name is spoken in words, anything else verbatim),
/// else the default button of the keyboard key (what GamepadMap injects), else the keyboard text.</summary>
public static class KeyHints
{
    private const string Open = "[KEY:";
    private const string PadOpen = "[PAD:";
    private const string KbOpen = "[KB:";

    private static readonly Dictionary<string, string> ButtonNames = new(StringComparer.Ordinal)
    {
        ["A"] = "A", ["B"] = "B", ["X"] = "X", ["Y"] = "Y",
        ["LB"] = "left bumper", ["RB"] = "right bumper", ["LT"] = "left trigger", ["RT"] = "right trigger",
        ["View"] = "View button", ["Menu"] = "Menu button",
        ["LSClick"] = "left stick click", ["RSClick"] = "right stick click",
        ["RSUp"] = "right stick up", ["RSDown"] = "right stick down", ["RSLeft"] = "right stick left", ["RSRight"] = "right stick right",
        ["LUp"] = "left stick up", ["LDown"] = "left stick down", ["LLeft"] = "left stick left", ["LRight"] = "left stick right",
        ["LStick"] = "left stick", ["RStick"] = "right stick",
        ["DUp"] = "D-pad up", ["DDown"] = "D-pad down", ["DLeft"] = "D-pad left", ["DRight"] = "D-pad right",
    };

    private static readonly Dictionary<string, string> Defaults = new(StringComparer.OrdinalIgnoreCase)
    {
        ["Enter"] = "A", ["Escape"] = "B", ["Space"] = "Y",
        ["Tab"] = "D-pad right", ["Control+Tab"] = "D-pad left", ["Home"] = "D-pad up", ["End"] = "D-pad down",
        ["Up"] = "left stick up", ["Down"] = "left stick down", ["Left"] = "left stick left", ["Right"] = "left stick right",
        ["Arrows"] = "left stick", ["arrow keys"] = "left stick",
        ["Up and Down"] = "left stick up and down", ["Up/Down"] = "left stick up and down",
        ["Left and Right"] = "left stick left and right", ["Left/Right"] = "left stick left and right",
        ["Left or Right"] = "left stick left or right", ["Up or Down"] = "left stick up or down",
        ["F13"] = "X", ["F14"] = "left bumper", ["F15"] = "right bumper", ["F16"] = "left trigger", ["F17"] = "right trigger",
        ["F18"] = "View button", ["F19"] = "Menu button", ["F20"] = "left stick click", ["F21"] = "right stick click",
    };

    private static readonly HashSet<string> ShiftKeys = new(StringComparer.OrdinalIgnoreCase)
        { "Enter", "Home", "End", "Up", "Down", "Left", "Right", "Arrows", "arrow keys" };

    /// <summary>Also handles [PAD:text] (Lua SRPadHint): pad = the text itself, keyboard = removed. [KB:text] (Lua SRKbHint) is the mirror: keyboard = the text, pad = removed. The text holds no ']'.</summary>
    public static string Expand(string text, bool pad)
    {
        if (string.IsNullOrEmpty(text)) return text;
        if (text.Contains(PadOpen, StringComparison.Ordinal)) text = ExpandPad(text, PadOpen, pad);
        if (text.Contains(KbOpen, StringComparison.Ordinal)) text = ExpandPad(text, KbOpen, !pad);
        if (!text.Contains(Open, StringComparison.Ordinal)) return text;
        StringBuilder sb = new();
        int pos = 0;
        while (pos < text.Length)
        {
            int start = text.IndexOf(Open, pos, StringComparison.Ordinal);
            if (start < 0) break;
            int end = text.IndexOf(']', start + Open.Length);
            if (end < 0) break;   // unclosed: the rest stays as is
            sb.Append(text, pos, start - pos);
            string body = text.Substring(start + Open.Length, end - start - Open.Length);
            int bar = body.IndexOf('|');
            string kb = bar < 0 ? body : body.Substring(0, bar);
            string? button = bar < 0 ? null : body.Substring(bar + 1);
            if (kb.Length == 0)
                sb.Append(text, start, end - start + 1);   // malformed: left as is
            else
                sb.Append(pad ? PadText(kb, button) : kb);
            pos = end + 1;
        }
        sb.Append(text, pos, text.Length - pos);
        return sb.ToString();
    }

    /// <summary>Keeps (keep) or removes every [open...] token; [KB:text] (Lua SRKbHint) is the mirror of [PAD:text]: kept for the keyboard only.</summary>
    private static string ExpandPad(string text, string open, bool keep)
    {
        StringBuilder sb = new();
        int pos = 0;
        while (pos < text.Length)
        {
            int start = text.IndexOf(open, pos, StringComparison.Ordinal);
            if (start < 0) break;
            int end = text.IndexOf(']', start + open.Length);
            if (end < 0) break;   // unclosed: the rest stays as is
            sb.Append(text, pos, start - pos);
            if (keep) sb.Append(text, start + open.Length, end - start - open.Length);
            pos = end + 1;
        }
        sb.Append(text, pos, text.Length - pos);
        return sb.ToString();
    }

    private static string PadText(string kb, string? button)
    {
        if (!string.IsNullOrEmpty(button)) return ButtonNames.TryGetValue(button, out string? name) ? name : button;
        if (Defaults.TryGetValue(kb, out string? d)) return d;
        const string shift = "Shift+";
        if (kb.StartsWith(shift, StringComparison.OrdinalIgnoreCase))
        {
            string k = kb.Substring(shift.Length);
            if (ShiftKeys.Contains(k) && Defaults.TryGetValue(k, out string? dk)) return "right trigger plus " + dk;
        }
        return kb;
    }
}
