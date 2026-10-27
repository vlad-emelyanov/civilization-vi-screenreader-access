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

        if (modeOff) Inject(new KeyEvent(PadButton.ModeOff, KeyAction.Tap));
        foreach (KeyEvent e in events)
        {
            if (e.Action == KeyAction.Up && !_heldDown.Contains(e.Button)) continue;   // its down was dropped
            Inject(e);
        }
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
        PadKey key = GamepadMap.Get(e.Button);
        switch (e.Action)
        {
            case KeyAction.Down: _injector.KeyDown(key, e.Shift); _heldDown.Add(e.Button); break;
            case KeyAction.Up: _injector.KeyUp(key, e.Shift); _heldDown.Remove(e.Button); break;
            default: _injector.Tap(key, e.Shift); break;
        }
        if (_log) Console.WriteLine($"Gamepad: {e.Button} -> {(e.Shift ? "Shift+" : "")}{key.Key} {(e.Action == KeyAction.Tap ? "tap" : e.Down ? "down" : "up")}");
    }

    public void Dispose()
    {
        _cts.Cancel();
        try { _thread?.Join(500); } catch { }
        ReleaseAllHeld();
        _tracker?.Dispose();
    }
}
