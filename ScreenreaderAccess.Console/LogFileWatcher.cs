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

    public async Task WaitForLogFileToExist(string luaLogFilePath, CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            if (File.Exists(luaLogFilePath))
            {
                return;
            }

            await Task.Delay(10000, cancellationToken);
        }
    }

    public async Task WatchLogFile(string filePath, CancellationToken cancellationToken)
    {
        var initialFileSize = new FileInfo(filePath).Length;
        var lastReadLength = initialFileSize - 1024;
        if (lastReadLength < 0) lastReadLength = 0;

        while (!cancellationToken.IsCancellationRequested)
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
                await this.WaitForLogFileToExist(filePath, cancellationToken);
                this.mediator.OutputText("Log file found. Watching...");
                initialFileSize = new FileInfo(filePath).Length;
                lastReadLength = initialFileSize - 1024;
                if (lastReadLength < 0) lastReadLength = 0;
            }
            catch (Exception e)
            {
                this.mediator.OutputTextError("Error: " + e.Message);
            }

            await Task.Delay(200, cancellationToken);
        }
    }

}
