using System.Text;

namespace ScreenreaderAccess.Console
{
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

                                this.mediator.Output(text);
                            }
                        }
                    }
                }
                catch (FileNotFoundException)
                {
                    this.mediator.OutputText("File no longer found: Waiting for file to exist again...");
                    await this.WaitForLogFileToExist(filePath);
                    this.mediator.OutputText("Log file found. Watching...");
                }
                catch (Exception e)
                {
                    this.mediator.OutputTextError("Error: " + e.Message);
                }

                Thread.Sleep(200);
            }
        }

    }
}
