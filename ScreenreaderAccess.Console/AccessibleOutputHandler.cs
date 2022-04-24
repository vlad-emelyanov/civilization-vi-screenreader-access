using System.Text.RegularExpressions;
using AccessibleOutput;

namespace ScreenreaderAccess.Console;

public sealed class AccessibleOutputHandler
{
    private IAccessibleOutput screenReader;

    private static readonly string screenReaderMarker = "#SCREENREADER - ";

    // precompiles a regex of sanitization, using | to separate
    private static readonly Dictionary<string, string> sanitizationRegexMap = new Dictionary<string, string>
    {
        { $@"^\w+\: {screenReaderMarker}", string.Empty },
        { @"\[ICON_\w+\]", " " },
        { @"[-]{2,}\[NEWLINE\]", string.Empty },
        { @"\[NEWLINE\]", ", " },
        { @"\[COLOR:\w+\]", string.Empty },
        { @"\[ENDCOLOR\]", string.Empty }
    };
    private static readonly Regex sanitizationRegex = new Regex(string.Join("|", sanitizationRegexMap.Keys.Select(k => $"({k})")), RegexOptions.Compiled);
    private static readonly Regex moduleRegex = new Regex(@"^(\w+):", RegexOptions.Compiled);

    private HashSet<string> modulesNotToInterrupt = new HashSet<string>
        {
            "StatusMessagePanel"
        };

    public AccessibleOutputHandler()
    {
        this.screenReader = new NvdaOutput();
    }

    public void OutputMessage(string message)
    {
        var lines = message.Split('\n');

        foreach (var line in lines)
        {
            if (line.Contains(screenReaderMarker))
            {
                bool interrupt = DetermineWhetherToInterrupt(line);
                this.screenReader.Speak(SanitizeLine(line), interrupt);
            }
        }
    }

    private bool DetermineWhetherToInterrupt(string line)
    {
        bool interrupt = true;
        var moduleMatch = moduleRegex.Match(line);
        if (moduleMatch.Success)
        {
            var module = moduleMatch.Groups[1].Value;
            interrupt = !modulesNotToInterrupt.Contains(module);
        }

        return interrupt;
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