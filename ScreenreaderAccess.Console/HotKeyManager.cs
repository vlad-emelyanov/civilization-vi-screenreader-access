using System.Collections.Concurrent;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace ScreenreaderAccess.Console;

public sealed class HotKeyManager : IDisposable
{
    public event EventHandler<HotKeyEventArgs>? HotKeyPressed;

    private readonly Thread _messageLoopThread;
    private readonly ManualResetEventSlim _windowReadyEvent;
    private readonly object _syncRoot;

    private MessageWindow? _window;
    private IntPtr _windowHandle;

    private bool _isDisposed;
    private bool _hasRegisteredOnce;

    private readonly ConcurrentQueue<IWorkItem> _workQueue;

    private const int WM_HOTKEY = 0x0312;
    private const int WM_APP = 0x8000;
    private const int WM_PROCESS_QUEUE = WM_APP + 1;

    private static readonly IntPtr HWND_MESSAGE = new IntPtr(-3);

    public HotKeyManager()
    {
        _syncRoot = new object();
        _windowReadyEvent = new ManualResetEventSlim(false);

        _workQueue = new ConcurrentQueue<IWorkItem>();
        
        _windowHandle = IntPtr.Zero;

        _messageLoopThread = new Thread(MessageLoopThreadStart);
        _messageLoopThread.Name = "HotKeyManager.MessageLoopThread";
        _messageLoopThread.IsBackground = true;
        _messageLoopThread.SetApartmentState(ApartmentState.STA);
        _messageLoopThread.Start();

        _windowReadyEvent.Wait();
    }

    public void RegisterHotKeys(IReadOnlyDictionary<Keys, KeyModifier> keys)
    {
        if (keys == null)
        {
            throw new ArgumentNullException(nameof(keys));
        }

        if (keys.Count == 0)
        {
           throw new ArgumentException("At least one hotkey must be specified.", nameof(keys));
        }

        lock (_syncRoot)
        {
            if (_isDisposed)
            {
                throw new ObjectDisposedException(nameof(HotKeyManager));
            }

            if (_hasRegisteredOnce)
            {
                throw new InvalidOperationException("Hotkeys have already been registered for this HotKeyManager instance.");
            }

            if (_window == null || _windowHandle == IntPtr.Zero)
            {
                throw new InvalidOperationException("HotKeyManager message window was not initialized correctly.");
            }

            RegisterAllWorkItem work = new(_windowHandle, keys, this);
            EnqueueAndWait(work);

            if (work.Error is not null)
            {
                // Fail if any registrations failed.
                throw work.Error;
            }

            if (work.RegisteredIds is null)
            {
                throw new Exception("HotKeyManager failed to register hotkeys for an unknown reason.");
            }

            _window.TrackRegisteredIds(work.RegisteredIds);
            _hasRegisteredOnce = true;
        }
    }

    public void Dispose()
    {
        lock (_syncRoot)
        {
            if (_isDisposed)
            {
                return;
            }

            _isDisposed = true;

            if (_window is not null && _windowHandle != IntPtr.Zero)
            {
                ShutdownWorkItem shutdown = new(_windowHandle, _window);
                EnqueueAndWait(shutdown);
            }
        }

        try
        {
            if (_messageLoopThread.IsAlive)
            {
                _messageLoopThread.Join(500);
            }
        }
        catch
        {
            // Ignore shutdown/join failures.
        }

        _windowReadyEvent.Dispose();
    }

    private void MessageLoopThreadStart()
    {
        Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);

        MessageWindow window = new(this);
        _window = window;
        _windowHandle = window.Handle;

        _windowReadyEvent.Set();

        Application.Run(new ApplicationContext());
    }

    private void RaiseHotKeyPressed(HotKeyEventArgs e)
    {
        EventHandler<HotKeyEventArgs>? handler = HotKeyPressed;
        if (handler is not null)
        {
            handler(this, e);
        }
    }

    private void EnqueueAndWait(IWorkItem workItem)
    {
        _workQueue.Enqueue(workItem);

        bool posted = PostMessage(_windowHandle, WM_PROCESS_QUEUE, IntPtr.Zero, IntPtr.Zero);
        if (!posted)
        {
            int error = Marshal.GetLastWin32Error();
            throw new Win32Exception(error, "PostMessage failed while attempting to process HotKeyManager work queue.");
        }

        workItem.Wait();
    }

    private sealed class MessageWindow : NativeWindow
    {
        private readonly HotKeyManager _owner;
        private readonly List<int> _registeredIds;

        public MessageWindow(HotKeyManager owner)
        {
            _owner = owner ?? throw new ArgumentNullException(nameof(owner));
            _registeredIds = new List<int>();

            CreateParams cp = new();
            cp.Caption = string.Empty;
            cp.X = 0;
            cp.Y = 0;
            cp.Height = 0;
            cp.Width = 0;
            cp.Style = 0;
            cp.ExStyle = 0;
            cp.Parent = HWND_MESSAGE;

            CreateHandle(cp);
        }

        public void TrackRegisteredIds(IEnumerable<int> ids)
        {
            _registeredIds.AddRange(ids);
        }

        public void UnregisterAll(IntPtr hwnd)
        {
            foreach (int id in _registeredIds)
            {
                UnregisterHotKey(hwnd, id);
            }

            _registeredIds.Clear();
        }

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == WM_HOTKEY)
            {
                HotKeyEventArgs e = new(m.LParam);
                _owner.RaiseHotKeyPressed(e);
            }
            else if (m.Msg == WM_PROCESS_QUEUE)
            {
                while (_owner._workQueue.TryDequeue(out IWorkItem? item) && item is not null)
                {
                    item.Execute();
                }
            }

            base.WndProc(ref m);
        }
    }

    private interface IWorkItem
    {
        void Execute();
        void Wait();
    }

    private sealed class RegisterAllWorkItem : IWorkItem
    {
        private readonly ManualResetEventSlim _done;
        private readonly IntPtr _hwnd;
        private readonly IReadOnlyDictionary<Keys, KeyModifier> _registrations;
        private readonly HotKeyManager _owner;

        public List<int>? RegisteredIds { get; private set; }
        public Exception? Error { get; private set; }

        public RegisterAllWorkItem(
            IntPtr hwnd,
            IReadOnlyDictionary<Keys, KeyModifier> registrations,
            HotKeyManager owner)
        {
            _done = new ManualResetEventSlim(false);
            _hwnd = hwnd;
            _registrations = registrations ?? throw new ArgumentNullException(nameof(registrations));
            _owner = owner ?? throw new ArgumentNullException(nameof(owner));
        }

        public void Execute()
        {
            int id = 0;
            List<int> registeredIds = new List<int>(_registrations.Count);

            try
            {
                foreach ((Keys key, KeyModifier modifier) in _registrations)
                {
                    bool ok = RegisterHotKey(_hwnd, id++, (uint)modifier, (uint)key);
                    if (!ok)
                    {
                        int error = Marshal.GetLastWin32Error();

                        // Roll back anything that succeeded before failing.
                        Rollback(_hwnd, registeredIds);

                        Error = new Win32Exception(
                            error,
                            $"RegisterHotKey failed for Key={key}, Modifier={modifier}, Id={id}. Rollback completed.");
                        return;
                    }

                    registeredIds.Add(id);
                }

                RegisteredIds = registeredIds;
            }
            catch (Exception ex)
            {
                // Attempt rollback on unexpected errors too.
                try
                {
                    Rollback(_hwnd, registeredIds);
                }
                catch
                {
                    // Ignore rollback exceptions; original exception should surface.
                }

                Error = ex;
            }
            finally
            {
                _done.Set();
            }
        }

        private static void Rollback(IntPtr hwnd, List<int> registeredIds)
        {
            foreach (int id in registeredIds)
            {
                UnregisterHotKey(hwnd, id);
            }
        }

        public void Wait()
        {
            _done.Wait();
            _done.Dispose();
        }
    }

    private sealed class ShutdownWorkItem : IWorkItem
    {
        private readonly ManualResetEventSlim _done;
        private readonly IntPtr _hwnd;
        private readonly MessageWindow _window;

        public ShutdownWorkItem(IntPtr hwnd, MessageWindow window)
        {
            _done = new ManualResetEventSlim(false);
            _hwnd = hwnd;
            _window = window;
        }

        public void Execute()
        {
            try
            {
                _window.UnregisterAll(_hwnd);
                _window.DestroyHandle();
                Application.ExitThread();
            }
            finally
            {
                _done.Set();
            }
        }

        public void Wait()
        {
            _done.Wait();
            _done.Dispose();
        }
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool PostMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);
}

public sealed class HotKeyEventArgs : EventArgs
{
    public readonly Keys Key;
    public readonly KeyModifier Modifiers;

    public HotKeyEventArgs(Keys key, KeyModifier modifiers)
    {
        Key = key;
        Modifiers = modifiers;
    }

    public HotKeyEventArgs(IntPtr hotKeyParam)
    {
        uint param = unchecked((uint)hotKeyParam.ToInt64());
        ushort modifiers = (ushort)(param & 0x0000FFFF);
        ushort vk = (ushort)((param >> 16) & 0x0000FFFF);

        Key = (Keys)vk;
        Modifiers = (KeyModifier)modifiers;
    }
}

[Flags]
public enum KeyModifier
{
    None = 0,
    Alt = 1,
    Control = 2,
    Shift = 4,
    Windows = 8,
    NoRepeat = 0x4000
}
