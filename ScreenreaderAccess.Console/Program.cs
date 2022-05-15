using ScreenreaderAccess.Console;

var accessibleOutputOptionReader = new AccessibleOutputOptionReader();
var accessibleOutput = new AccessibleOutputHandler(accessibleOutputOptionReader);
var textOutput = new TextOutputHandler();
var mediator = new Mediator(accessibleOutput, textOutput);
var logFileWatcher = new LogFileWatcher(mediator);

Console.WriteLine("Initializing Scrren reader...");
accessibleOutput.OutputMessage("Screen reader loaded!");

// this will eventually be configurated
var luaLogFileName = "Lua.log";
var luaLogFileDir = Path.Join(
    Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments),
    "My Games",
    "Sid Meier's Civilization VI",
    "Logs");
var luaLogFilePath = Path.Join(luaLogFileDir, luaLogFileName);

Console.WriteLine("Opening log file...");
var cancellationTokenSource = new CancellationTokenSource();
var cancellationToken = cancellationTokenSource.Token;

try
{
    await logFileWatcher.WaitForLogFileToExist(luaLogFilePath, cancellationToken);
}
catch (Exception e)
{
    Console.WriteLine($"Exception of type {e.GetType().FullName} thrown");
    cancellationTokenSource.Cancel();
    Environment.Exit(1);
}

Console.WriteLine("Log file found. Watching...");

logFileWatcher.WatchLogFile(luaLogFilePath);

Console.ReadKey();