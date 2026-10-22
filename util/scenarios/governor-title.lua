-- Scenario: governor-title. STATUS: unverified (written offline)
-- Fixture: a game with Gathering Storm (governors) and a capital: early-city. A title is normally earned through
--   civics (Medieval Faires / Civil Service etc.), so this grants one governor point directly.
-- Then press: F10 -> "Governors. 1 titles available. <first governor>, 1 of 7"; Enter -> Appoint.
-- Notes: do NOT call PlayerOperations.APPOINT_GOVERNOR by hand (forbidden, see docs/engine-notes.md); appoint through the screen.
local gov = Players[0]:GetGovernors()
if not gov then error("scenario governor-title: no governors (Gathering Storm / Rise and Fall not active)") end
print("scenario governor-title: points before " .. tostring(gov:GetGovernorPoints()) .. ", spent " .. tostring(gov:GetGovernorPointsSpent()))
gov:ChangeGovernorPoints(1)
print("scenario governor-title: points after " .. tostring(gov:GetGovernorPoints()))
