-- Scenario: governor-title. STATUS: verified 2026-10-22
-- Fixture: early-t60 (Gathering Storm, capital, Moksha already established). Any game with governors works.
-- Then press: F10 -> "Governors. 1 title available. Moksha, The Cardinal, in Rome, established, can promote, 1 of 7"; Escape closes.
-- Notes: grants one governor point directly (ChangeGovernorPoints exists in GameCore_Tuner; adds 1 on every run). Do NOT call
--   PlayerOperations.APPOINT_GOVERNOR by hand (forbidden, docs/engine-notes.md); appoint through the screen.
local gov = Players[0]:GetGovernors()
if not gov then error("scenario governor-title: no governors (Gathering Storm / Rise and Fall not active)") end
print("scenario governor-title: points before " .. tostring(gov:GetGovernorPoints()) .. ", spent " .. tostring(gov:GetGovernorPointsSpent()))
gov:ChangeGovernorPoints(1)
print("scenario governor-title: points after " .. tostring(gov:GetGovernorPoints()))
