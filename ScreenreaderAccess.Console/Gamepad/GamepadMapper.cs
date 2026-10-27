namespace ScreenreaderAccess.Console.Gamepad;

public enum InputSource { Keyboard, Gamepad }

/// <summary>Pure logic: controller state changes -> key events. No Win32, time is a parameter.</summary>
public sealed class GamepadMapper
{
    public const int StickThreshold = 16384;   // 50 % deflection
    public const int TriggerThreshold = 128;   // 50 %

    private sealed class Repeater
    {
        public readonly int FirstMs, EveryMs;
        public PadButton? Current;
        public long NextAt;
        public Repeater(int first, int every) { FirstMs = first; EveryMs = every; }
    }

    private static readonly (ushort Mask, PadButton Button)[] ToggleButtons =
    {
        (GamepadState.BtnA, PadButton.A), (GamepadState.BtnB, PadButton.B), (GamepadState.BtnX, PadButton.X), (GamepadState.BtnY, PadButton.Y),
        (GamepadState.LeftShoulder, PadButton.LB), (GamepadState.RightShoulder, PadButton.RB),
        (GamepadState.Back, PadButton.View), (GamepadState.Start, PadButton.Menu),
        (GamepadState.LeftThumb, PadButton.LSClick), (GamepadState.RightThumb, PadButton.RSClick),
    };

    private readonly Repeater _left = new(350, 110), _dpad = new(350, 110), _right = new(500, 350);

    public InputSource Source { get; private set; } = InputSource.Keyboard;

    /// <summary>Forget the mode without sending anything (used while the game is not in the foreground).</summary>
    public void ForceKeyboard() => Source = InputSource.Keyboard;

    /// <summary>A physical keyboard key went down. True when a ModeOff tap must be sent.</summary>
    public bool OnPhysicalKeyboardKey()
    {
        bool wasPad = Source == InputSource.Gamepad;
        Source = InputSource.Keyboard;
        return wasPad;
    }

    public List<KeyEvent> Update(GamepadState prev, GamepadState cur, long nowMs)
    {
        List<KeyEvent> events = new();

        foreach ((ushort mask, PadButton b) in ToggleButtons)
            Edge(events, b, (prev.Buttons & mask) != 0, (cur.Buttons & mask) != 0);
        Edge(events, PadButton.LT, prev.LeftTrigger >= TriggerThreshold, cur.LeftTrigger >= TriggerThreshold);
        Edge(events, PadButton.RT, prev.RightTrigger >= TriggerThreshold, cur.RightTrigger >= TriggerThreshold);

        Direction(events, _left, StickDir(cur.LX, cur.LY, PadButton.LUp, PadButton.LDown, PadButton.LLeft, PadButton.LRight), nowMs);
        Direction(events, _dpad, DPadDir(cur.Buttons), nowMs);
        Direction(events, _right, StickDir(cur.RX, cur.RY, PadButton.RSUp, PadButton.RSDown, PadButton.RSLeft, PadButton.RSRight), nowMs);

        if (Source == InputSource.Keyboard && events.Exists(e => e.Action != KeyAction.Up))
        {
            events.Insert(0, new KeyEvent(PadButton.ModeOn, KeyAction.Tap));
            Source = InputSource.Gamepad;
        }
        return events;
    }

    private static void Edge(List<KeyEvent> events, PadButton b, bool was, bool now)
    {
        if (now && !was) events.Add(new KeyEvent(b, KeyAction.Down));
        else if (!now && was) events.Add(new KeyEvent(b, KeyAction.Up));
    }

    private static PadButton? StickDir(short x, short y, PadButton up, PadButton down, PadButton left, PadButton right)
    {
        int ax = Math.Abs((int)x), ay = Math.Abs((int)y);
        if (Math.Max(ax, ay) < StickThreshold) return null;
        if (ay > ax) return y > 0 ? up : down;   // dominant axis only; a tie goes horizontal
        return x > 0 ? right : left;
    }

    private static PadButton? DPadDir(ushort buttons)
    {
        if ((buttons & GamepadState.DPadUp) != 0) return PadButton.DUp;
        if ((buttons & GamepadState.DPadDown) != 0) return PadButton.DDown;
        if ((buttons & GamepadState.DPadLeft) != 0) return PadButton.DLeft;
        if ((buttons & GamepadState.DPadRight) != 0) return PadButton.DRight;
        return null;
    }

    private static void Direction(List<KeyEvent> events, Repeater r, PadButton? dir, long now)
    {
        if (dir is null) { r.Current = null; return; }
        if (r.Current != dir)
        {
            r.Current = dir;
            r.NextAt = now + r.FirstMs;
            events.Add(new KeyEvent(dir.Value, KeyAction.Tap));
        }
        else if (now >= r.NextAt)
        {
            r.NextAt += r.EveryMs;
            if (r.NextAt <= now) r.NextAt = now + r.EveryMs;   // fell behind: no burst
            events.Add(new KeyEvent(dir.Value, KeyAction.Tap));
        }
    }
}
