using System.Diagnostics;

namespace ScreenreaderAccess.Console.Gamepad;

using Console = System.Console;

/// <summary>Polling thread (~60 Hz): XInput -> mapper -> injector, only while the game is in the foreground.</summary>
public sealed class GamepadService : IDisposable
{
    private readonly bool _log;
    private readonly XInputReader _reader = new();
    private readonly GamepadMapper _mapper = new();
    private readonly KeyInjector _injector = new();
    private readonly ForegroundGuard _guard = new();
    private readonly HashSet<PadButton> _heldDown = new();
    private readonly object _lock = new();
    private readonly CancellationTokenSource _cts = new();
    private Thread? _thread;
    private InputDeviceTracker? _tracker;
    private volatile bool _modeOffPending;

    public GamepadService(bool log) { _log = log; }

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
        if (off) _modeOffPending = true;
    }

    private void Run()
    {
        Stopwatch clock = Stopwatch.StartNew();
        GamepadState prev = default;
        bool connected = false, announcedNone = false;
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
            catch (Exception ex) { Console.WriteLine("Gamepad: error: " + ex.Message); }
            Thread.Sleep(16);
        }
    }

    private void Step(GamepadState prev, GamepadState cur, long now)
    {
        bool fg = _guard.IsGameForeground();
        List<KeyEvent> events;
        lock (_lock)
        {
            events = _mapper.Update(prev, cur, now);
            if (!fg) _mapper.ForceKeyboard();   // events are dropped while away: send ModeOn again on return
        }
        if (!fg) return;

        // A down we injected whose release happened while away: release it now, never re-press.
        foreach (PadButton b in _heldDown.ToArray())
            if (!IsHeld(b, cur) && !events.Exists(e => e.Button == b && e.Action == KeyAction.Up))
                Inject(new KeyEvent(b, KeyAction.Up));

        if (_modeOffPending)
        {
            _modeOffPending = false;
            Inject(new KeyEvent(PadButton.ModeOff, KeyAction.Tap));
        }
        foreach (KeyEvent e in events)
        {
            if (e.Action == KeyAction.Up && !_heldDown.Contains(e.Button)) continue;   // its down was dropped
            Inject(e);
        }
    }

    private static bool IsHeld(PadButton b, GamepadState s) => b switch
    {
        PadButton.A => (s.Buttons & GamepadState.BtnA) != 0,
        PadButton.B => (s.Buttons & GamepadState.BtnB) != 0,
        PadButton.X => (s.Buttons & GamepadState.BtnX) != 0,
        PadButton.Y => (s.Buttons & GamepadState.BtnY) != 0,
        PadButton.LB => (s.Buttons & GamepadState.LeftShoulder) != 0,
        PadButton.RB => (s.Buttons & GamepadState.RightShoulder) != 0,
        PadButton.View => (s.Buttons & GamepadState.Back) != 0,
        PadButton.Menu => (s.Buttons & GamepadState.Start) != 0,
        PadButton.LSClick => (s.Buttons & GamepadState.LeftThumb) != 0,
        PadButton.RSClick => (s.Buttons & GamepadState.RightThumb) != 0,
        PadButton.LT => s.LeftTrigger >= GamepadMapper.TriggerThreshold,
        PadButton.RT => s.RightTrigger >= GamepadMapper.TriggerThreshold,
        _ => false,
    };

    private void Inject(KeyEvent e)
    {
        PadKey key = GamepadMap.Get(e.Button);
        switch (e.Action)
        {
            case KeyAction.Down: _injector.KeyDown(key); _heldDown.Add(e.Button); break;
            case KeyAction.Up: _injector.KeyUp(key); _heldDown.Remove(e.Button); break;
            default: _injector.Tap(key); break;
        }
        if (_log) Console.WriteLine($"Gamepad: {e.Button} -> {key.Key} {(e.Action == KeyAction.Tap ? "tap" : e.Down ? "down" : "up")}");
    }

    public void Dispose()
    {
        _cts.Cancel();
        try { _thread?.Join(500); } catch { }
        _tracker?.Dispose();
    }
}
