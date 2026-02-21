using ScreenReaderAccess.Console;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading.Channels;

namespace ScreenreaderAccess.Console;

public class KeyboardNavigationHandler
{
    public const string keyboardNavigationMarker = "#KEYNAV";
    private const string keyboardNavigationMoveMarker = "#KEYNAV_MOVE";
    private const string keyboardNavigationClickMarker = "#KEYNAV_CLICK";
    // Add 3 to account for ' - ' between the end of the marker and start of content
    private static readonly int keyNavStripLength = keyboardNavigationMarker.Length + 3;
    private static readonly int keyNavMoveStripLength = keyboardNavigationMoveMarker.Length + 3;

    private readonly object lockObj = new();
    private readonly Channel<string> linesToProcess = Channel.CreateUnbounded<string>(new UnboundedChannelOptions { SingleReader = true, SingleWriter = true});
    private readonly TextOutputHandler log;

    private KeyboardNavigationSet? currentSet = null;
    private ConcurrentDictionary<int, List<KeyboardNavigationElement>> incompleteSets = new();
    
    public KeyboardNavigationHandler(TextOutputHandler logger)
    {
        log = logger;
    }

    public void ProcessLine(string line) => linesToProcess.Writer.TryWrite(line);

    public void ProcessKeyPress(Keys key, KeyModifier modifiers) {
        log.OutputLine($"Processing key press: {key} with modifiers: {modifiers}");
        lock (lockObj) {
            if (currentSet is null) {
                log.OutputLine("No keyboard navigation set initialized");
                return;
            }
            
            if (key == Keys.Up) {
                KeyboardNavigationElement element = currentSet.MovePrevious();
                log.OutputLine($"Moving to previous element: {element.Label}");
                MouseManager.MoveMouse(element.XPosition, element.YPosition);
                return;
            }

            if (key == Keys.Down) {
                KeyboardNavigationElement element = currentSet.MoveNext();
                MouseManager.MoveMouse(element.XPosition, element.YPosition);
                return;
            }

            if (key == Keys.Enter) {
                MouseManager.LeftClick();
                currentSet = null;
                return;
            }
        }
    }

    public async Task ProcessQueueAsync(CancellationToken cancellationToken)
    {
        log.OutputLine("Starting to process keyboard navigation lines...");
        ChannelReader<string> lineReader = linesToProcess.Reader;
        while (!cancellationToken.IsCancellationRequested)
        {
            string line = await lineReader.ReadAsync(cancellationToken);
            if (line is null)
            {
                log.OutputErrorLine("Cannot process null keyboard navigation line");
                continue;
            }
            if (line.Contains(keyboardNavigationClickMarker))
                {
                ProcessKeyNavClick(line[line.Length - 1]);
            }
            else if (line.Contains(keyboardNavigationMoveMarker))
            {
                ProcessKeyNavMoveLine(line.Substring(line.IndexOf(keyboardNavigationMoveMarker) + keyNavMoveStripLength));
            }
            else
            {
                ProcessKeyNavSetLine(line.Substring(line.IndexOf(keyboardNavigationMarker) + keyNavStripLength));
            }
        }
    }

    private void ProcessKeyNavMoveLine(string strippedLine)
    {
        if (!TryParseCoordinates(strippedLine, out int xCoordinate, out int yCoordinate))
        {
            log.OutputErrorLine($"Failed to parse coordinates from {strippedLine}");
            return;
        }

        MouseManager.MoveMouse(xCoordinate, yCoordinate);
    }

    private void ProcessKeyNavClick(char button)
    {
        if (button == 'L')
        {
            MouseManager.LeftClick();
        } else if (button == 'R')
        {
            MouseManager.RightClick();
        } else if (button == 'M')
        {
            MouseManager.MiddleClick();
        } else
        {
            log.OutputErrorLine($"Failed to process mouse click char: {button}");
        }
    }

    private void ProcessKeyNavSetLine(string strippedLine)
    {
        string[] components = strippedLine.Split(' ', 4);
        int numComponents = components.Length;
        if (numComponents < 2 || numComponents > 4)
        {
            log.OutputErrorLine($"Could not parse keyboard navigation line with {numComponents} elements: {strippedLine}");
            return;
        }

        if (!int.TryParse(components[0], out int setId))
        {
            log.OutputErrorLine($"Failed to parse set ID from '{components[0]}'. Input line: {strippedLine}");
            return;
        }

        if (numComponents == 2)
        {
            string marker = components[1];
            if (marker == "START")
            {
                lock (lockObj)
                {
                    log.OutputLine($"Start of navigation set {setId}");
                    currentSet = null;
                }

                incompleteSets[setId] = new();
                return;
            }

            if (marker == "END" && incompleteSets.TryRemove(setId, out var elems))
            {
                lock (lockObj)
                {
                    log.OutputLine($"End of navigation set {setId}");
                    currentSet = new KeyboardNavigationSet(elems);
                    KeyboardNavigationElement elem = currentSet.First;
                    MouseManager.MoveMouse(elem.XPosition, elem.YPosition);
                }

                return;
            }
                
            log.OutputErrorLine($"Could not parse keyboard navigation line: {strippedLine}");
            return;
        }

        if (!TryParseCoordinates(components[2], out int xCoordinate, out int yCoordinate))
        {
            log.OutputErrorLine($"Could not parse coordinates from '{components[2]}'. Input line: {strippedLine}");
            return;
        }

        KeyboardNavigationElement element = new()
        {
            Label = components.Length == 4 ? components[3] : string.Empty,
            XPosition = xCoordinate,
            YPosition = yCoordinate,
        };
        if (incompleteSets.TryGetValue(setId, out var elements))
        {
            log.OutputLine($"Parsed navigation element SetId: {setId}, Label: {element.Label}, X: {xCoordinate}, Y: {yCoordinate}");
            elements.Add(element);
        }
    }

    private bool TryParseCoordinates(string s, out int x, out int y)
    {
        string[] coordinates = s.Split(',');
        if (coordinates.Length != 2 || !Double.TryParse(coordinates[0], out double xCoordinate) || !Double.TryParse(coordinates[1], out double yCoordinate))
        {
            x = 0;
            y = 0;
            return false;
        }

        x = (int)xCoordinate;
        y = (int)yCoordinate;
        return true;
    }

    private class KeyboardNavigationSet {
        private int currentIndex = 0;
        private object lockObj = new();

        private List<KeyboardNavigationElement> elements = new();
  
        public KeyboardNavigationSet(List<KeyboardNavigationElement> elements) {
          this.elements = elements;
        }

        public KeyboardNavigationElement First => elements[0];

        public KeyboardNavigationElement MoveNext()
        {
            lock (lockObj)
            {
                currentIndex = (currentIndex + 1) % elements.Count;
                return elements[currentIndex];
            }
        }

        public KeyboardNavigationElement MovePrevious() {
            lock (lockObj)
            {
                currentIndex = (currentIndex - 1 + elements.Count) % elements.Count;
                return elements[currentIndex];
            }
        }
    }

    private struct KeyboardNavigationElement
    {
        public string Label { get; set; }
        public int XPosition { get; set; }
        public int YPosition { get; set; }
    }
}
