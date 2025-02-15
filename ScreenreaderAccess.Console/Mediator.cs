namespace ScreenreaderAccess.Console;

public  sealed class Mediator
{
    private readonly AccessibleOutputHandler accessibleOOutput;
    private readonly TextOutputHandler textOutput;

    public Mediator(AccessibleOutputHandler accessibleOutput, TextOutputHandler textOutput)
    {
        this.accessibleOOutput = accessibleOutput;
        this.textOutput = textOutput;
    }

    public void ProcessLine(string line)
    {
        if (line.Contains(AccessibleOutputHandler.screenReaderMarker))
        {
            this.accessibleOOutput.OutputMessage(line);
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
