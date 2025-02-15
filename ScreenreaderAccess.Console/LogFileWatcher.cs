using System.IO;
using System.Text;

namespace ScreenreaderAccess.Console;

public sealed class LogFileWatcher
{
    private Mediator mediator;

    public LogFileWatcher(Mediator mediator)
    {
        this.mediator = mediator;
    }

    public Task WaitForLogFileToExist(string luaLogFilePath, CancellationToken? cancellationToken = null)
    {
        while (cancellationToken?.IsCancellationRequested != true)
        {
            if (File.Exists(luaLogFilePath))
            {
                return Task.CompletedTask;
            }

            Thread.Sleep(10000);
        }

        // this is a catch all for anything that isn't covered by the cancellation token throwing
        return Task.FromException(new ApplicationException($"Unable to load log file {luaLogFilePath}"));
    }

    public async void WatchLogFile(string filePath)
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
                    using FileStream fs = new(filePath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
                    using StreamReader reader = new(fs);
                    fs.Seek(lastReadLength, SeekOrigin.Begin);
                    
                    while (!reader.EndOfStream)
                    {
                        string? line = reader.ReadLine();
                        if (line is null)
                        {
                            break;
                        }

                        this.mediator.ProcessLine(line);
                    }

                    lastReadLength = fs.Position;
                }
            }
            catch (FileNotFoundException)
            {
                this.mediator.OutputText("File no longer found: Waiting for file to exist again...");
                await this.WaitForLogFileToExist(filePath);
                this.mediator.OutputText("Log file found. Watching...");
                initialFileSize = new FileInfo(filePath).Length;
                lastReadLength = initialFileSize - 1024;
                if (lastReadLength < 0) lastReadLength = 0;
            }
            catch (Exception e)
            {
                this.mediator.OutputTextError("Error: " + e.Message);
            }

            Thread.Sleep(200);
        }
    }

}
