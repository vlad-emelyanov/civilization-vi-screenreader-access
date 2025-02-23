using System;
using System.Runtime.InteropServices;
using System.Threading;

namespace ScreenReaderAccess.Console;

public static class MouseManager
{
    // SendInput constants
    private const int INPUT_MOUSE = 0;
    private const uint MOUSEEVENTF_MOVE = 0x0001;
    private const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    private const uint MOUSEEVENTF_LEFTUP = 0x0004;
    private const uint MOUSEEVENTF_RIGHTDOWN = 0x0008;
    private const uint MOUSEEVENTF_RIGHTUP = 0x0010;
    private const uint MOUSEEVENTF_MIDDLEDOWN = 0x0020;
    private const uint MOUSEEVENTF_MIDDLEUP = 0x0040;

    /// <summary>
    /// Moves the mouse cursor to the specified screen coordinates by generating
    /// a sequence of small relative moves.
    /// </summary>
    /// <param name="x">Target screen X in pixels.</param>
    /// <param name="y">Target screen Y in pixels.</param>
    public static void MoveMouse(int x, int y)
    {
        System.Console.WriteLine($"Moving mouse to ({x}, {y})");
        if (!GetCursorPos(out POINT start))
            throw new InvalidOperationException("Failed to get cursor position.");

        System.Console.WriteLine($"Start mouse position: ({start.X}, {start.Y})");
        int steps = 0;
        int startTime = DateTime.Now.Millisecond;
        while (start.X != x || start.Y != y)
        {
            steps += MoveMouseAprox(start.X, start.Y, x, y, 0);
            if (!GetCursorPos(out start))
                throw new InvalidOperationException("Failed to get cursor position.");
        }

        int duration = DateTime.Now.Millisecond - startTime;
        System.Console.WriteLine($"End mouse position: {start.X},{start.Y} in {steps} steps and {duration}ms");
    }

    /// <summary>
    /// Simulates a left mouse click using SendInput.
    /// </summary>
    public static void LeftClick()
    {
        SendMouseButton(MOUSEEVENTF_LEFTDOWN);
        SendMouseButton(MOUSEEVENTF_LEFTUP);
    }

    /// <summary>
    /// Simulates a right mouse click using SendInput.
    /// </summary>
    public static void RightClick()
    {
        SendMouseButton(MOUSEEVENTF_RIGHTDOWN);
        SendMouseButton(MOUSEEVENTF_RIGHTUP);
    }

    /// <summary>
    /// Simulates a middle mouse click using SendInput.
    /// </summary>
    public static void MiddleClick()
    {
        SendMouseButton(MOUSEEVENTF_MIDDLEDOWN);
        SendMouseButton(MOUSEEVENTF_MIDDLEUP);
    }

    /// <summary>
    /// Simulates a double left mouse click.
    /// </summary>
    public static void DoubleClick()
    {
        LeftClick();
        LeftClick();
    }

    /// <summary>
    /// Moves the mouse to a specified location and performs a left click.
    /// </summary>
    public static void MoveAndClick(int x, int y)
    {
        MoveMouse(x, y);
        LeftClick();
    }

    private static int MoveMouseAprox(int x0, int y0, int x1, int y1, int delayMs)
    {
        int steps = 0;
        while (x0 != x1 || y0 != y1)
        {
            steps++;
            int xStep = ComputeStep(x0, x1);
            int yStep = ComputeStep(y0, y1);
            x0 += xStep;
            y0 += yStep;
            SendRelativeMove(xStep, yStep);
            if (delayMs > 0) Thread.Sleep(delayMs);
        }

        return steps;
    }

    private static int ComputeStep(int start, int end)
    {
        const int far = 20;
        const int medium = 8;
        const int close = 3;
        
        int delta = Math.Abs(end - start);
        int sign = start < end ? 1 : -1;
        if (delta == 0) 
            return 0;
        if (delta < close)
            return sign * 1;
        if (delta < medium)
            return sign * close;
        if (delta < far)
            return sign * medium;
        return sign * far;
    }

    private static void SendRelativeMove(int dx, int dy)
    {
        // dx/dy here are pixel deltas (relative)
        INPUT[] inputs = new INPUT[1];
        inputs[0] = new INPUT
        {
            type = INPUT_MOUSE,
            U = new InputUnion
            {
                mi = new MOUSEINPUT
                {
                    dx = dx,
                    dy = dy,
                    mouseData = 0,
                    dwFlags = MOUSEEVENTF_MOVE,
                    time = 0,
                    dwExtraInfo = UIntPtr.Zero
                }
            }
        };

        uint sent = SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<INPUT>());
        if (sent != inputs.Length)
        {
            int err = Marshal.GetLastWin32Error();
            throw new InvalidOperationException($"SendInput(relative move) failed. Win32Error={err}");
        }
    }

    private static void SendMouseButton(uint flags)
    {
        INPUT[] inputs = new INPUT[1];
        inputs[0] = new INPUT
        {
            type = INPUT_MOUSE,
            U = new InputUnion
            {
                mi = new MOUSEINPUT
                {
                    dx = 0,
                    dy = 0,
                    mouseData = 0,
                    dwFlags = flags,
                    time = 0,
                    dwExtraInfo = UIntPtr.Zero
                }
            }
        };

        uint sent = SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<INPUT>());
        if (sent != inputs.Length)
        {
            int err = Marshal.GetLastWin32Error();
            throw new InvalidOperationException($"SendInput(mouse button) failed. Win32Error={err}");
        }
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetCursorPos(out POINT lpPoint);

    [StructLayout(LayoutKind.Sequential)]
    private struct POINT
    {
        public int X;
        public int Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct INPUT
    {
        public int type;
        public InputUnion U;
    }

    [StructLayout(LayoutKind.Explicit)]
    private struct InputUnion
    {
        [FieldOffset(0)] public MOUSEINPUT mi;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MOUSEINPUT
    {
        public int dx;
        public int dy;
        public uint mouseData;
        public uint dwFlags;
        public uint time;
        public UIntPtr dwExtraInfo;
    }
}
