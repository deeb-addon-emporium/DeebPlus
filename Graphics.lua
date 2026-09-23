-- volumeFog 0 makes the game read cleaner. CVar changes need the player to be logged in.
local DP = DeebPlus
local function apply()
	if not DP.db then return end
	local want = DP.db.fogOff and "0" or "1"
	local cur = GetCVar and GetCVar("volumeFog")
	if cur ~= nil and cur ~= want then
		pcall(SetCVar, "volumeFog", want)
	end
	-- always show health and mana numbers on the player and target frames
	if DP.db.statusText then
		pcall(SetCVar, "statusText", "1")
		pcall(SetCVar, "statusTextDisplay", "BOTH")      -- number and percent
	end
end
DP.register("graphics", { apply = apply })
