namespace ScreenreaderAccess.Console;

public  sealed class Mediator
{
    private readonly AccessibleOutputHandler accessibleOOutput;
    private readonly KeyboardNavigationHandler keyboardNavigation;
    private readonly TextOutputHandler textOutput;

    public Mediator(AccessibleOutputHandler accessibleOutput, KeyboardNavigationHandler keyboardNavigation, TextOutputHandler textOutput)
    {
        this.accessibleOOutput = accessibleOutput;
        this.keyboardNavigation = keyboardNavigation;
        this.textOutput = textOutput;
    }

    public void ProcessLine(string line)
    {
        if (line.Contains(AccessibleOutputHandler.screenReaderMarker))
        {
            this.accessibleOOutput.OutputMessage(line);
        }
        else if (line.Contains(KeyboardNavigationHandler.keyboardNavigationMarker))
        {
            this.keyboardNavigation.ProcessLine(line);
        }
    }

    public void OutputText(string message)
    {
        this.textOutput.OutputLine(message);
    }

    public void OutputTextError(string message)
    {
        this.textOutput.OutputErrorLine(message);
    }
}
