-- ScreenReader module
--------------------------------------------------------------

local SCREENREADER_LOG_PREFIX: string = "#SCREENREADER - ";

function OutputMessageToScreenReader(message)
    print("Entering outputMessage");
	print(SCREENREADER_LOG_PREFIX .. message);
	print("Done");
end