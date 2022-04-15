using AccessibleOutput;

namespace ScreenreaderAccess.Console
{
    public sealed class AccessibleOutputHandler
    {
        private IAccessibleOutput screenReader;

        private static readonly string screenReaderrPrefix = "PlotToolTip: #SCREENREADER - ";

        public AccessibleOutputHandler()
        {
            this.screenReader = new NvdaOutput();
        }
        
        public void OutputMessage(string message)
        {
            var lines = message.Split('\n');

            foreach (var line in lines)
            {
                if (line.StartsWith(screenReaderrPrefix))
                {
                    this.screenReader.Speak(SanitizeLine(line));
                }
            }
        }

        private static string SanitizeLine(string line)
        {
            return line.Substring(screenReaderrPrefix.Length - 1)
                .Replace("[NEWLINE]", ", ");
        }
    }
}