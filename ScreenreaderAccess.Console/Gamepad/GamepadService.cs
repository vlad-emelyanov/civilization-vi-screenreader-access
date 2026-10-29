using System.Diagnostics;

namespace ScreenreaderAccess.Console.Gamepad;

using Console = System.Console;

/// <summary>Polling thread (~60 Hz): XInput -> mapper -> injector, only while the game is in the foreground.</summary>
public sealed class GamepadService : IDisposable
{
    private readonly bool _log;
    private readonly XInputReader _reader = new();
    private readonly GamepadMapper _mapper = new();
    private readonly KeyInjector _injector;
    private readonly ForegroundGuard _guard = new();
    private readonly HashSet<PadButton> _heldDown = new();
    private readonly object _lock = new();
    private readonly CancellationTokenSource _cts = new();
    private Thread? _thread;
    private InputDeviceTracker? _tracker;
    private volatile bool _modeOffPending;

    public GamepadService(bool log, bool post = true)
    {
        _log = log;
        _injector = new KeyInjector(post);
        if (!post) Console.WriteLine("Gamepad: keys via SendInput (--gamepad-sendinput; screen readers hear them)");
    }

    public void Start()
    {
        try { _tracker = new InputDeviceTracker(OnPhysicalKey); }
        catch (Exception ex) { Console.WriteLine("Gamepad: keyboard tracking unavailable: " + ex.Message); }
        _thread = new Thread(Run) { Name = "GamepadService", IsBackground = true };
        _thread.Start();
    }

    private void OnPhysicalKey()
    {
        bool off;
        lock (_lock) off = _mapper.OnPhysicalKeyboardKey();
        if (InputDevice.Set(false) && _log) Console.WriteLine("Gamepad: input device -> keyboard");
        if (off) _modeOffPending = true;
    }

    private void Run()
    {
        Stopwatch clock = Stopwatch.StartNew();
        GamepadState prev = default;
        bool connected = false, announcedNone = false;
        long lastErrorAt = -10000;
        while (!_cts.IsCancellationRequested)
        {
            try
            {
                long now = clock.ElapsedMilliseconds;
                if (_reader.TryRead(now, out GamepadState cur))
                {
                    if (!connected) { connected = true; announcedNone = false; prev = default; Console.WriteLine($"Gamepad: connected (slot {_reader.Slot})"); }
                    Step(prev, cur, now);
                    prev = cur;
                }
                else if (connected)
                {
                    connected = false;
                    Console.WriteLine("Gamepad: disconnected");
                    Step(prev, default, now);   // releases whatever was held
                    prev = default;
                }
                else if (!announcedNone)
                {
                    announcedNone = true;
                    Console.WriteLine("Gamepad: no controller found, waiting");
                }
            }
            catch (Exception ex)
            {
                if (clock.ElapsedMilliseconds - lastErrorAt > 5000) { lastErrorAt = clock.ElapsedMilliseconds; Console.WriteLine("Gamepad: error: " + ex.Message); }
            }
            Thread.Sleep(16);
        }
    }

    private void Step(GamepadState prev, GamepadState cur, long now)
    {
        bool fg = _guard.IsGameForeground();
        List<KeyEvent> events = new();
        bool modeOff = false;
        lock (_lock)
        {
            modeOff = fg && _modeOffPending;
            _modeOffPending = false;
            events = _mapper.Update(prev, cur, now);   // always advances (repeat timers, held directions)
            if (!fg)
            {
                events.Clear();
                _mapper.ForceKeyboard();   // events are dropped while away: send ModeOn again on return
            }
        }
        if (!fg)
        {
            ReleaseAllHeld();   // lost the foreground: nothing may stay down; never re-pressed on return
            return;
        }

        if ((modeOff || events.Count > 0) && InputDevice.Set(true) && _log) Console.WriteLine("Gamepad: input device -> controller");
        if (modeOff) Inject(new KeyEvent(PadButton.ModeOff, KeyAction.Tap));
        foreach (KeyEvent e in events)
        {
            if (e.Action == KeyAction.Up && !_heldDown.Contains(e.Button)) continue;   // its down was dropped
            Inject(e);
        }
        if ((cur.Buttons & GamepadState.LeftShoulder) == 0) _heldDown.Remove(PadButton.LB);		// a suppressed F14 / F15 up (bumper used for PageUp / PageDown) leaves nothing to release later
        if ((cur.Buttons & GamepadState.RightShoulder) == 0) _heldDown.Remove(PadButton.RB);
        if (cur.RightTrigger < GamepadMapper.TriggerThreshold) _heldDown.Remove(PadButton.RT);   // a suppressed F17 up (RT used as Shift) leaves nothing to release later
        if (cur.LeftTrigger < GamepadMapper.TriggerThreshold) _heldDown.Remove(PadButton.LT);   // a suppressed F16 up (LT used as the wheel)
    }

    private void ReleaseAllHeld()
    {
        foreach (PadButton b in _heldDown.ToArray())
        {
            try { _injector.KeyUp(GamepadMap.Get(b)); } catch { }
        }
        _heldDown.Clear();
    }

    private void Inject(KeyEvent e)
    {
        PadKey key = GamepadMap.KeyOf(e);
        switch (e.Action)
        {
            case KeyAction.Down: _injector.KeyDown(key, e.Shift); _heldDown.Add(e.Button); break;
            case KeyAction.Up: _injector.KeyUp(key, e.Shift); _heldDown.Remove(e.Button); break;
            default: _injector.Tap(key, e.Shift); break;
        }
        if (_log) Console.WriteLine($"Gamepad: {e.Button}{(e.Button == PadButton.Wheel ? " " + e.Slot : "")} -> {(e.Shift || key.Shift ? "Shift+" : "")}{(key.Control ? "Control+" : "")}{key.Key} {(e.Action == KeyAction.Tap ? "tap" : e.Down ? "down" : "up")}");
    }

    public void Dispose()
    {
        _cts.Cancel();
        try { _thread?.Join(500); } catch { }
        ReleaseAllHeld();
        _tracker?.Dispose();
    }
}
