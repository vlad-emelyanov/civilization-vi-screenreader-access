using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace ScreenreaderAccess.Console;

using Console = System.Console;

public static class Program
{
    private static readonly IReadOnlyDictionary<Keys, KeyModifier> keys = new Dictionary<Keys, KeyModifier>()
    {
        [Keys.Up] = KeyModifier.None,
        [Keys.Down] = KeyModifier.None,
        [Keys.Enter] = KeyModifier.None,
    };

    public static async Task<int> Main()
    {
        Console.WriteLine("Initializing Screen reader...");
        AccessibleOutputOptionReader accessibleOutputOptionReader = new();
        AccessibleOutputHandler accessibleOutput = new(accessibleOutputOptionReader);
        accessibleOutput.OutputMessage("Screen reader loaded!");
        
        TextOutputHandler textOutput = new();
        KeyboardNavigationHandler keyboardNavigation = new(textOutput);

        using HotKeyManager hotKeyManager = new();
        hotKeyManager.HotKeyPressed += (object? sender, HotKeyEventArgs e) =>
        {
            try
            {
                keyboardNavigation.ProcessKeyPress(e.Key, e.Modifiers);
            }
            catch (Exception ex)
            {
                Console.WriteLine(ex.ToString());
            }
        };

        hotKeyManager.RegisterHotKeys(keys);

        Mediator mediator = new(accessibleOutput, keyboardNavigation, textOutput);
        LogFileWatcher logFileWatcher = new(mediator);

        string luaLogFileName = "Lua.log";
        string luaLogFileDir = Path.Join(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            @"Firaxis Games\Sid Meier's Civilization VI\Logs");
        string luaLogFilePath = Path.Join(luaLogFileDir, luaLogFileName);

        using CancellationTokenSource cancellationTokenSource = new();
        CancellationToken cancellationToken = cancellationTokenSource.Token;
        Console.WriteLine("Press 'X' to cancel at any time.");
        Task keyCancelTask = Task.Run(async () =>
        {
            while (!cancellationToken.IsCancellationRequested)
            {
                if (!Console.KeyAvailable)
                {
                    await Task.Delay(100, cancellationToken);
                    continue;
                }

                if (Console.ReadKey(true).Key == ConsoleKey.X)
                {
                    cancellationTokenSource.Cancel();
                    break;
                }
            }
        });

        Console.WriteLine("Opening log file...");
        await logFileWatcher.WaitForLogFileToExist(luaLogFilePath, cancellationToken);

        Console.WriteLine("Log file found. Watching...");
        Task[] tasks = new[]
        {
            logFileWatcher.WatchLogFile(luaLogFilePath, cancellationToken),
            keyboardNavigation.ProcessQueueAsync(cancellationToken),
            keyCancelTask,
        };

        await Task.WhenAny(tasks);
    cancellationTokenSource.Cancel();
        try
        {
            await Task.WhenAll(tasks);
        }
        catch (OperationCanceledException)
        {
            // Ignore
        }
    return 0;
    }
}
