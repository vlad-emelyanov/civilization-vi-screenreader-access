namespace ScreenreaderAccess.Console.Gamepad;

public enum InputSource { Keyboard, Gamepad }

/// <summary>Pure logic: controller state changes -> key events. No Win32, time is a parameter.</summary>
public sealed class GamepadMapper
{
    public const int StickThreshold = 16384;   // 50 % deflection
    public const int TriggerThreshold = 128;   // 50 %
    public const int WheelThreshold = 24000;   // ~73 %: the wheel only reads a clearly pointed stick (a stick springing back keeps the slot)
    public const double WheelHysteresisDeg = 4;   // the pointed slot changes only this far past the border between two slots

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

    private bool _rtShiftUsed, _aShift, _lbPageUsed, _rbPageUsed;
    private bool _wheelUsed, _leftLatched;   // LT was a wheel this press (no F16 up) / the left stick stays silent until it is centred again
    private int? _wheelSlot;

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

        bool rtNow = cur.RightTrigger >= TriggerThreshold;
        bool rtWas = prev.RightTrigger >= TriggerThreshold;
        if (rtNow && !rtWas) _rtShiftUsed = false;
        bool bumperNow = (cur.Buttons & (GamepadState.LeftShoulder | GamepadState.RightShoulder)) != 0;
        if ((cur.Buttons & GamepadState.LeftShoulder) != 0 && (prev.Buttons & GamepadState.LeftShoulder) == 0) _lbPageUsed = false;
        if ((cur.Buttons & GamepadState.RightShoulder) != 0 && (prev.Buttons & GamepadState.RightShoulder) == 0) _rbPageUsed = false;

        foreach ((ushort mask, PadButton b) in ToggleButtons)
        {
            bool was = (prev.Buttons & mask) != 0, now = (cur.Buttons & mask) != 0;
            if (b == PadButton.A)
            {
                if (now && !was) _aShift = rtNow;
                Edge(events, b, was, now, _aShift);
                if (!now) _aShift = false;
            }
            else if (!now && was && ((b == PadButton.LB && _lbPageUsed) || (b == PadButton.RB && _rbPageUsed))) { }   // that bumper was a modifier for PageUp / PageDown: no KeyUp
            else Edge(events, b, was, now);
        }
        bool ltNow = cur.LeftTrigger >= TriggerThreshold, ltWas = prev.LeftTrigger >= TriggerThreshold;
        if (ltNow && !ltWas) { _wheelUsed = false; _wheelSlot = null; events.Add(new KeyEvent(PadButton.LT, KeyAction.Down)); }
        else if (!ltNow && ltWas && !_wheelUsed) events.Add(new KeyEvent(PadButton.LT, KeyAction.Up));
        if (ltNow)
        {
            // the wheel: the left stick's direction picks a slot, one tap per change; no arrows meanwhile
            int? slot = WheelSlot(cur.LX, cur.LY, _wheelSlot);
            if (slot is not null && slot != _wheelSlot)
            {
                _wheelSlot = slot;
                _wheelUsed = _leftLatched = true;
                events.Add(new KeyEvent(PadButton.Wheel, KeyAction.Tap, Slot: slot.Value));
            }
        }
        if (rtNow && !rtWas) events.Add(new KeyEvent(PadButton.RT, KeyAction.Down));
        else if (!rtNow && rtWas && !_rtShiftUsed) events.Add(new KeyEvent(PadButton.RT, KeyAction.Up));

        PadButton? leftDir = StickDir(cur.LX, cur.LY, PadButton.LUp, PadButton.LDown, PadButton.LLeft, PadButton.LRight);
        if (leftDir is null) _leftLatched = false;
        if (ltNow || _leftLatched) leftDir = null;   // the wheel has the stick; after it, the stick must come back to the centre first
        Direction(events, _left, leftDir, nowMs, rtNow, bumperNow);
        Direction(events, _dpad, DPadDir(cur.Buttons), nowMs, rtNow, bumperNow);
        Direction(events, _right, StickDir(cur.RX, cur.RY, PadButton.RSUp, PadButton.RSDown, PadButton.RSLeft, PadButton.RSRight), nowMs, false);
        if (events.Exists(e => e.Shift)) _rtShiftUsed = true;
        if (events.Exists(e => e.Button is PadButton.PageUp or PadButton.PageDown))
        {
            if ((cur.Buttons & GamepadState.LeftShoulder) != 0) _lbPageUsed = true;   // every bumper held while paging is a modifier now
            if ((cur.Buttons & GamepadState.RightShoulder) != 0) _rbPageUsed = true;
        }

        if (Source == InputSource.Keyboard && events.Exists(e => e.Action != KeyAction.Up))
        {
            events.Insert(0, new KeyEvent(PadButton.ModeOn, KeyAction.Tap));
            Source = InputSource.Gamepad;
        }
        return events;
    }

    private static void Edge(List<KeyEvent> events, PadButton b, bool was, bool now, bool shift = false)
    {
        if (now && !was) events.Add(new KeyEvent(b, KeyAction.Down, shift));
        else if (!now && was) events.Add(new KeyEvent(b, KeyAction.Up, shift));
    }

    private static PadButton? StickDir(short x, short y, PadButton up, PadButton down, PadButton left, PadButton right)
    {
        int ax = Math.Abs((int)x), ay = Math.Abs((int)y);
        if (Math.Max(ax, ay) < StickThreshold) return null;
        if (ay > ax) return y > 0 ? up : down;   // dominant axis only; a tie goes horizontal
        return x > 0 ? right : left;
    }

    /// <summary>Pure. The wheel slot (0..23, clockwise from straight up, 15 degrees each) the stick points at, or <paramref name="current"/>
    /// when it is not pointed far enough (centred or springing back). Hysteresis: the current slot is kept until the stick is
    /// <see cref="WheelHysteresisDeg"/> past its border.</summary>
    public static int? WheelSlot(short x, short y, int? current)
    {
        double mag = Math.Sqrt((double)x * x + (double)y * y);
        if (mag < WheelThreshold) return current;
        double deg = Math.Atan2(x, y) * 180.0 / Math.PI;   // 0 = up, 90 = right
        if (deg < 0) deg += 360;
        const double width = 360.0 / GamepadMap.WheelSlots;
        if (current is not null)
        {
            double diff = Math.Abs(deg - current.Value * width) % 360;
            if (diff > 180) diff = 360 - diff;
            if (diff <= width / 2 + WheelHysteresisDeg) return current;
        }
        return (int)Math.Round(deg / width) % GamepadMap.WheelSlots;
    }

    private static PadButton? DPadDir(ushort buttons)
    {
        if ((buttons & GamepadState.DPadUp) != 0) return PadButton.DUp;
        if ((buttons & GamepadState.DPadDown) != 0) return PadButton.DDown;
        if ((buttons & GamepadState.DPadLeft) != 0) return PadButton.DLeft;
        if ((buttons & GamepadState.DPadRight) != 0) return PadButton.DRight;
        return null;
    }

    // Shift applies to the left stick (all four) and D-pad up/down only; D-pad left/right stay plain (Shift+Tab opens the Steam overlay).
    private static bool CanShift(PadButton b) => b is PadButton.LUp or PadButton.LDown or PadButton.LLeft or PadButton.LRight or PadButton.DUp or PadButton.DDown;

    // A held bumper turns up / down (left stick and D-pad) into PageUp / PageDown: the group jump of the lists.
    private static PadButton PageOf(PadButton b) => b switch
    {
        PadButton.LUp or PadButton.DUp => PadButton.PageUp,
        PadButton.LDown or PadButton.DDown => PadButton.PageDown,
        _ => b,
    };

    private static void Direction(List<KeyEvent> events, Repeater r, PadButton? dir, long now, bool shiftHeld, bool bumperHeld = false)
    {
        if (dir is null) { r.Current = null; return; }
        if (r.Current != dir)
        {
            r.Current = dir;
            r.NextAt = now + r.FirstMs;
            events.Add(Make(dir.Value, shiftHeld, bumperHeld));
        }
        else if (now >= r.NextAt)
        {
            r.NextAt += r.EveryMs;
            if (r.NextAt <= now) r.NextAt = now + r.EveryMs;   // fell behind: no burst
            events.Add(Make(dir.Value, shiftHeld, bumperHeld));
        }
    }

    private static KeyEvent Make(PadButton dir, bool shiftHeld, bool bumperHeld)
    {
        PadButton page = bumperHeld ? PageOf(dir) : dir;
        if (page != dir) return new KeyEvent(page, KeyAction.Tap);
        return new KeyEvent(dir, KeyAction.Tap, shiftHeld && CanShift(dir));
    }
}
