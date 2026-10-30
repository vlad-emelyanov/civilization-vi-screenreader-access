using System.Text.RegularExpressions;
using AccessibleOutput;

namespace ScreenreaderAccess.Console;

public sealed class AccessibleOutputHandler
{
    private readonly AccessibleOutputOptionReader optionReader;
    
    private IAccessibleOutput screenReader;

    public const string screenReaderMarker = "#SCREENREADER";

    // precompiles a regex of sanitization, using | to separate
    private static readonly Dictionary<string, string> sanitizationRegexMap = new Dictionary<string, string>
    {
        { $@"^\w+\: {screenReaderMarker}\[.+?\] - ", string.Empty },
        { $@"^\w+\: {screenReaderMarker} - ", string.Empty },
        { @"\[ICON_\w+\]", " " },
        { @"[-]{2,}\[NEWLINE\]", string.Empty },
        { @"\[NEWLINE\]", ", " },
        { @"\[COLOR:\w+\]", string.Empty },
        { @"\[ENDCOLOR\]", string.Empty }
    };
    private static readonly Regex sanitizationRegex = new Regex(string.Join("|", sanitizationRegexMap.Keys.Select(k => $"({k})")), RegexOptions.Compiled);
    
    private DateTime lastNonInterruptableMessage = DateTime.MinValue;
    private static readonly TimeSpan nonInterruptTime = TimeSpan.FromSeconds(3);

    public AccessibleOutputHandler(AccessibleOutputOptionReader optionReader)
    {
        this.screenReader = new JawsOutput();
        this.optionReader = optionReader;
    }

    public void OutputMessage(string line)
    {
        var options = this.optionReader.GetOptionsFrom(line);
        bool interrupt = !options.NoInterrupt;

        if (!interrupt)
        {
            this.lastNonInterruptableMessage = DateTime.UtcNow;
        }
        else
        {
            // check to see if we're not interrupting a notification; a pad key pressed after it ends the protection (a real key does
            // the same: JAWS silences itself when it hears one, but the pad's keys are posted to the game and JAWS never hears them)
            interrupt = DateTime.UtcNow >= this.lastNonInterruptableMessage.Add(nonInterruptTime)
                || Gamepad.InputDevice.LastPadKeyTicks > this.lastNonInterruptableMessage.Ticks;
        }

        var sanitized = KeyHints.Expand(SanitizeLine(line), Gamepad.InputDevice.PadIsCurrent);
        this.screenReader.Speak(sanitized, interrupt);
    }

    private static string SanitizeLine(string line)
    {
        return sanitizationRegex.Replace(line, match => RegexEvaluate(match));
    }

    private static string RegexEvaluate(Match match)
    {
        // match group 0 is the entire match, whilst later match groups match to which one of the regexes got matched.
        // so by starting at index 1 in groups, we can work out which element to replace it with by using the index of the replacements
        for (int i = 1; i < match.Groups.Count; i++)
        {
            var group = match.Groups[i];
            if (group.Success)
            {
                return sanitizationRegexMap.ElementAt(i - 1).Value;
            }
        }

        throw new ArgumentException("Match found that doesn't have any successful groups");
    }

}