using System.Text;
using AccessibleOutput;

Console.WriteLine("Initializing Scrren reader...");
var screenReader = new NvdaOutput();
screenReader.Speak("Screen reader loaded!");

var luaLogFileName = "Lua.log";
var luaLogFileDir = Path.Join(
    Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments),
    "My Games",
    "Sid Meier's Civilization VI",
    "Logs");
var luaLogFilePath = Path.Join(luaLogFileDir, luaLogFileName);
Console.WriteLine("Opening log file...");
WaitForLogFileToExist(luaLogFilePath);
Console.WriteLine("Log file found. Watching...");

string screenReaderrPrefix = "PlotToolTip: #SCREENREADER - ";
Action<string> onTextAdded = (text) =>
{
    var lines = text.Split('\n');
    foreach (var line in lines)
    {
        if (line.StartsWith(screenReaderrPrefix))
        {
            var processedLine = line.Substring(screenReaderrPrefix.Length - 1);
            processedLine = processedLine
                .Replace("[NEWLINE]", ", ");
            screenReader.Speak(processedLine);
        }
    }
};

StartWatchingFile(luaLogFilePath, onTextAdded);

Console.ReadKey();

static void WaitForLogFileToExist(string luaLogFilePath)
{
    while (true)
    {
        if (File.Exists(luaLogFilePath))
        {
            break;
        }

        Thread.Sleep(10000);
    }
}

static void StartWatchingFile(string filePath, Action<string> onLineAdded)
{
    var initialFileSize = new FileInfo(filePath).Length;
    var lastReadLength = initialFileSize - 1024;
    if (lastReadLength < 0) lastReadLength = 0;

    while (true)
    {
        try
        {
            var fileSize = new FileInfo(filePath).Length;
            if (fileSize > lastReadLength)
            {
                using (var fs = new FileStream(filePath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
                {
                    fs.Seek(lastReadLength, SeekOrigin.Begin);
                    var buffer = new byte[1024];

                    while (true)
                    {
                        var bytesRead = fs.Read(buffer, 0, buffer.Length);
                        lastReadLength += bytesRead;

                        if (bytesRead == 0)
                            break;

                        var text = ASCIIEncoding.ASCII.GetString(buffer, 0, bytesRead);

                        onLineAdded?.Invoke(text);
                    }
                }
            }
        }
        catch (Exception e)
        {
            Console.WriteLine("Error: " + e.Message);
        }

        Thread.Sleep(200);
    }
}