using System.Windows.Forms;
using ScreenreaderAccess.Console.Gamepad;

namespace ScreenreaderAccess.Console.Tests;

public class GamepadMapperTests
{
    private static GamepadState S(short lx = 0, short ly = 0, short rx = 0, short ry = 0, ushort buttons = 0, byte lt = 0, byte rt = 0)
        => new(buttons, lt, rt, lx, ly, rx, ry);

    private static string Fmt(List<KeyEvent> e) => string.Join(",", e.Select(x => $"{x.Button}:{x.Action}"));

    // Steps the mapper every 10 ms with a constant state and collects the times of taps for one button.
    private static List<long> TapTimes(GamepadMapper m, GamepadState s, PadButton b, int upToMs)
    {
        List<long> times = new();
        GamepadState prev = default;
        for (long t = 0; t <= upToMs; t += 10)
        {
            foreach (KeyEvent e in m.Update(prev, s, t)) if (e.Button == b && e.Action == KeyAction.Tap) times.Add(t);
            prev = s;
        }
        return times;
    }

    [Fact]
    public void PressA_IsEnterDownThenUp_WithModeOnFirst()
    {
        GamepadMapper m = new();
        Assert.Equal("ModeOn:Tap,A:Down", Fmt(m.Update(default, S(buttons: GamepadState.BtnA), 0)));
        Assert.Equal("A:Up", Fmt(m.Update(S(buttons: GamepadState.BtnA), default, 20)));
        Assert.Equal(Keys.Enter, GamepadMap.Get(PadButton.A).Key);
    }

    [Fact]
    public void HeldButton_DoesNotRepeat()
    {
        GamepadMapper m = new();
        GamepadState s = S(buttons: GamepadState.BtnB);
        m.Update(default, s, 0);
        for (long t = 10; t < 2000; t += 10) Assert.Empty(m.Update(s, s, t));
    }

    [Fact]
    public void LeftStickRight_TapsThenRepeats()
        => Assert.Equal(new long[] { 0, 350, 460, 570 }, TapTimes(new GamepadMapper(), S(lx: 30000), PadButton.LRight, 600));

    [Fact]
    public void RightStick_UsesSlowerRepeat()
        => Assert.Equal(new long[] { 0, 500, 850, 1200 }, TapTimes(new GamepadMapper(), S(ry: 30000), PadButton.RSUp, 1200));

    [Fact]
    public void DPad_RepeatsLikeLeftStick()
        => Assert.Equal(new long[] { 0, 350, 460 }, TapTimes(new GamepadMapper(), S(buttons: GamepadState.DPadDown), PadButton.DDown, 500));

    [Fact]
    public void Stick_DominantAxisOnly_NoDiagonals()
        => Assert.Equal("ModeOn:Tap,LUp:Tap", Fmt(new GamepadMapper().Update(default, S(lx: 20000, ly: 25000), 0)));

    [Fact]
    public void Stick_BelowHalfDeflection_IsNothing()
        => Assert.Empty(new GamepadMapper().Update(default, S(lx: 16000), 0));

    [Fact]
    public void LeavingDirection_StopsRepeat()
    {
        GamepadMapper m = new();
        GamepadState s = S(lx: 30000);
        m.Update(default, s, 0);
        m.Update(s, default, 100);
        Assert.Empty(m.Update(default, default, 400));
    }

    [Fact]
    public void StickAndDPad_RepeatIndependently()
    {
        GamepadMapper m = new();
        GamepadState s = S(lx: 30000, buttons: GamepadState.DPadUp);
        Assert.Equal("ModeOn:Tap,LRight:Tap,DUp:Tap", Fmt(m.Update(default, s, 0)));
        for (long t = 10; t < 350; t += 10) m.Update(s, s, t);
        Assert.Equal("LRight:Tap,DUp:Tap", Fmt(m.Update(s, s, 350)));
    }

    [Fact]
    public void Triggers_AreButtonsAtHalf()
    {
        GamepadMapper m = new();
        Assert.Empty(m.Update(default, S(lt: 127), 0));
        Assert.Equal("ModeOn:Tap,LT:Down", Fmt(m.Update(S(lt: 127), S(lt: 128), 10)));
        Assert.Equal("LT:Up", Fmt(m.Update(S(lt: 128), S(lt: 10), 20)));
    }

    [Fact]
    public void ModeSwitching_OnAndOff()
    {
        GamepadMapper m = new();
        Assert.False(m.OnPhysicalKeyboardKey());          // already keyboard
        m.Update(default, S(buttons: GamepadState.BtnX), 0);
        Assert.Equal(InputSource.Gamepad, m.Source);
        Assert.True(m.OnPhysicalKeyboardKey());           // ModeOff needed
        Assert.False(m.OnPhysicalKeyboardKey());
        Assert.Equal("ModeOn:Tap,Y:Down", Fmt(m.Update(default, S(buttons: GamepadState.BtnY), 50)));
    }

    [Fact]
    public void ReleaseWhileKeyboard_DoesNotSendModeOn()
    {
        GamepadMapper m = new();
        m.Update(default, S(buttons: GamepadState.BtnA), 0);
        m.OnPhysicalKeyboardKey();
        Assert.Equal("A:Up", Fmt(m.Update(S(buttons: GamepadState.BtnA), default, 10)));
    }

    [Fact]
    public void Map_MatchesDesign()
    {
        PadKey k = GamepadMap.Table["RSUp"];
        Assert.Equal(Keys.F13, k.Key);
        Assert.True(k.Control);
        Assert.Equal(26, GamepadMap.Table.Count);
    }

    [Fact]
    public void EveryButtonName_IsInTheMap()
    {
        foreach (PadButton b in Enum.GetValues<PadButton>()) Assert.True(GamepadMap.Table.ContainsKey(b.ToString()), b.ToString());
    }

    private static string FmtS(List<KeyEvent> e) => string.Join(",", e.Select(x => $"{x.Button}:{x.Action}{(x.Shift ? "+S" : "")}"));

    [Fact]
    public void RtHeld_StickRight_IsShiftTap_ThenF17UpOnRelease()
    {
        GamepadMapper m = new();
        GamepadState rt = S(rt: 255), rtRight = S(lx: 30000, rt: 255);
        Assert.Equal("ModeOn:Tap,RT:Down", FmtS(m.Update(default, rt, 0)));
        Assert.Equal("LRight:Tap+S", FmtS(m.Update(rt, rtRight, 20)));
        Assert.Empty(m.Update(rtRight, rt, 40));
        Assert.Equal("RT:Up", FmtS(m.Update(rt, default, 60)));
    }

    [Fact]
    public void RtTapAlone_IsF17DownAndUp()
    {
        GamepadMapper m = new();
        Assert.Equal("ModeOn:Tap,RT:Down", FmtS(m.Update(default, S(rt: 255), 0)));
        Assert.Equal("RT:Up", FmtS(m.Update(S(rt: 255), default, 50)));
    }

    [Fact]
    public void RtHeld_DPadRight_StaysPlainTab_DPadDownIsShifted()
    {
        GamepadMapper m = new();
        GamepadState rt = S(rt: 255);
        m.Update(default, rt, 0);
        GamepadState right = S(rt: 255, buttons: GamepadState.DPadRight);
        Assert.Equal("DRight:Tap", FmtS(m.Update(rt, right, 20)));
        Assert.Equal("DDown:Tap+S", FmtS(m.Update(right, S(rt: 255, buttons: GamepadState.DPadDown), 40)));
    }

    [Fact]
    public void RtHeld_A_IsShiftEnter_UpKeepsShift()
    {
        GamepadMapper m = new();
        GamepadState rt = S(rt: 255), rtA = S(rt: 255, buttons: GamepadState.BtnA);
        m.Update(default, rt, 0);
        Assert.Equal("A:Down+S", FmtS(m.Update(rt, rtA, 20)));
        Assert.Equal("A:Up+S", FmtS(m.Update(rtA, default, 40)));   // RT released first or together: Up still shifted
    }
}
