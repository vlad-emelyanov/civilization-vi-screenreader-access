-- ScreenReader module
--------------------------------------------------------------

local SCREENREADER_LOG_PREFIX: string = "#SCREENREADER - ";
local SCREENREADER_NO_INTERRUPT_LOG_PREFIX: string = "#SCREENREADER[NOINTERRUPT] - ";

function OutputMessageToScreenReader(message: string, nointerrupt: boolean)
	if nointerrupt then
		print(SCREENREADER_NO_INTERRUPT_LOG_PREFIX .. message);
	else
		print(SCREENREADER_LOG_PREFIX .. message);
	end
end