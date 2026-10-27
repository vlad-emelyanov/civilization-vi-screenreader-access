namespace ScreenreaderAccess.Console.Tests;

public class KeyHintsTests
{
    [Theory]
    [InlineData("Press [KEY:Tab] now", "Press Tab now")]
    [InlineData("[KEY:C|X] opens", "C opens")]
    [InlineData("no token", "no token")]
    public void Keyboard_SpeaksKeyboardText(string input, string expected)
        => Assert.Equal(expected, KeyHints.Expand(input, false));

    [Theory]
    [InlineData("[KEY:Enter]", "A")]
    [InlineData("[KEY:escape]", "B")]
    [InlineData("[KEY:Space]", "Y")]
    [InlineData("[KEY:Tab]", "D-pad right")]
    [InlineData("[KEY:Control+Tab]", "D-pad left")]
    [InlineData("[KEY:Home]", "D-pad up")]
    [InlineData("[KEY:End]", "D-pad down")]
    [InlineData("[KEY:Up]", "left stick up")]
    [InlineData("[KEY:Arrows]", "left stick")]
    [InlineData("[KEY:arrow keys]", "left stick")]
    [InlineData("[KEY:Up and Down]", "left stick up and down")]
    [InlineData("[KEY:Left/Right]", "left stick left and right")]
    [InlineData("[KEY:Left or Right]", "left stick left or right")]
    [InlineData("[KEY:up or down]", "left stick up or down")]
    [InlineData("[KEY:F17]", "right trigger")]
    [InlineData("[KEY:F21]", "right stick click")]
    public void Pad_DefaultButtons(string input, string expected)
        => Assert.Equal(expected, KeyHints.Expand(input, true));

    [Theory]
    [InlineData("[KEY:C|X]", "X")]
    [InlineData("[KEY:V|LB]", "left bumper")]
    [InlineData("[KEY:V|RSClick]", "right stick click")]
    [InlineData("[KEY:V|DLeft]", "D-pad left")]
    [InlineData("[KEY:V|View]", "View button")]
    [InlineData("[KEY:Enter|B]", "B")]
    public void Pad_ExplicitButtonNames(string input, string expected)
        => Assert.Equal(expected, KeyHints.Expand(input, true));

    [Fact]
    public void Pad_FreeTextButtonIsSpokenVerbatim()
        => Assert.Equal("hold the right trigger", KeyHints.Expand("[KEY:Shift+Enter|hold the right trigger]", true));

    [Theory]
    [InlineData("[KEY:Shift+Enter]", "right trigger plus A")]
    [InlineData("[KEY:Shift+Home]", "right trigger plus D-pad up")]
    [InlineData("[KEY:Shift+Arrows]", "right trigger plus left stick")]
    [InlineData("[KEY:Shift+Up]", "right trigger plus left stick up")]
    public void Pad_ShiftCombos(string input, string expected)
        => Assert.Equal(expected, KeyHints.Expand(input, true));

    [Fact]
    public void Pad_TabAndControlTabDiffer()
        => Assert.Equal("D-pad right or D-pad left", KeyHints.Expand("[KEY:Tab] or [KEY:Control+Tab]", true));

    [Theory]
    [InlineData("[KEY:Q]", "Q")]
    [InlineData("[KEY:Shift+Q]", "Shift+Q")]
    [InlineData("[KEY:Shift+Tab]", "Shift+Tab")]
    public void Pad_UnknownKeysStayKeyboardText(string input, string expected)
        => Assert.Equal(expected, KeyHints.Expand(input, true));

    [Fact]
    public void TwoTokensInOneLine()
    {
        const string t = "[KEY:Enter] to accept, [KEY:Escape] to cancel";
        Assert.Equal("A to accept, B to cancel", KeyHints.Expand(t, true));
        Assert.Equal("Enter to accept, Escape to cancel", KeyHints.Expand(t, false));
    }

    [Theory]
    [InlineData("press [KEY:Enter")]
    [InlineData("press [KEY:] now")]
    [InlineData("press [KEY:|X] now")]
    public void MalformedTokensAreLeftAsIs(string input)
    {
        Assert.Equal(input, KeyHints.Expand(input, true));
        Assert.Equal(input, KeyHints.Expand(input, false));
    }

    [Fact]
    public void ValidTokenBeforeUnclosedOne()
        => Assert.Equal("A then [KEY:Esc", KeyHints.Expand("[KEY:Enter] then [KEY:Esc", true));
}
