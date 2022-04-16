-- ScreenReader module
--------------------------------------------------------------

local SCREENREADER_LOG_PREFIX: string = "#SCREENREADER - ";

function OutputMessageToScreenReader(message)
	print(SCREENREADER_LOG_PREFIX .. message);
end