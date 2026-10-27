namespace ScreenreaderAccess.Console.Gamepad;

/// <summary>Logical controller buttons; names match the keys of <see cref="GamepadMap.Table"/>.</summary>
public enum PadButton
{
    A, B, X, Y, LB, RB, LT, RT, View, Menu, LSClick, RSClick,
    RSUp, RSDown, RSLeft, RSRight, LUp, LDown, LLeft, LRight, DUp, DDown, DLeft, DRight,
    ModeOn, ModeOff,
}

public enum KeyAction { Down, Up, Tap }

public readonly record struct KeyEvent(PadButton Button, KeyAction Action)
{
    public bool Down => Action == KeyAction.Down;
}

/// <summary>Raw snapshot. Buttons use the XInput bitmask.</summary>
public readonly record struct GamepadState(ushort Buttons, byte LeftTrigger, byte RightTrigger, short LX, short LY, short RX, short RY)
{
    public const ushort DPadUp = 0x0001, DPadDown = 0x0002, DPadLeft = 0x0004, DPadRight = 0x0008,
        Start = 0x0010, Back = 0x0020, LeftThumb = 0x0040, RightThumb = 0x0080,
        LeftShoulder = 0x0100, RightShoulder = 0x0200, BtnA = 0x1000, BtnB = 0x2000, BtnX = 0x4000, BtnY = 0x8000;
}
