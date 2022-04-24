using static System.Console;

namespace ScreenreaderAccess.Console;

public sealed class TextOutputHandler
{
    public void OutputLine(string message) => WriteLine(message);
    public void OutputErrorLine(string message) => Error.WriteLine(message);
}
