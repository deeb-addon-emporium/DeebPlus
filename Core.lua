-- DeebPlus core: one settings table, one message helper, module registry.
DeebPlus = DeebPlus or {}
local DP = DeebPlus

DP.PREFIX = "|cff80c0ffDeebPlus|r: "
function DP.msg(t) print(DP.PREFIX .. t) end

-- defaults; every module reads DP.db.<key>
DP.defaults = {
	questAccept = true,       -- accept quests and turn them in
	questWalk = true,         -- walk the NPC's list for you
	questTrivial = false,     -- accept gray quests too
	vendorJunk = true,        -- sell gray junk at merchants
	autoRepair = true,        -- repair everything at any repair vendor
	fogOff = true,            -- volumeFog 0
	tooltipCursor = true,     -- tooltip follows the mouse
	fsr = true,               -- five second rule bar on the mana bar
	lowVendor = true,         -- outline the cheapest-to-vendor bag slot
	threatPlates = true,      -- threat % on stock nameplates
	errorCatcher = true,      -- Lua errors to a quiet list + /dp errors, no popup
	hideIssueReporter = true, -- keep the beta issue reporter off screen
	classColorHP = true,      -- class-coloured health bars on the default frames
	gossipSkip = true,        -- auto-pick "browse your goods" / "train me" on NPC menus
	chatFilter = true,        -- drop chat lines with banned phrases (friends exempt)
	banPhrases = "Asmon\nAsmon Layer",
	minimap = true,
	minimapAngle = 210,
}

DP.modules = {}               -- name -> { apply = function() end }
function DP.register(name, mod) DP.modules[name] = mod end

-- called after a setting changes so live modules can react
function DP.apply(name)
	if name then
		local m = DP.modules[name]
		if m and m.apply then pcall(m.apply) end
		return
	end
	for _, m in pairs(DP.modules) do if m.apply then pcall(m.apply) end end
end

function DP.set(key, value)
	DP.db[key] = value
	DP.apply()
	if DP.refreshConfig then DP.refreshConfig() end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
	if type(DeebPlusDB) ~= "table" then DeebPlusDB = {} end
	for k, v in pairs(DP.defaults) do
		if DeebPlusDB[k] == nil then DeebPlusDB[k] = v end
	end
	DP.db = DeebPlusDB
	DP.apply()
	C_Timer.After(2, function() DP.msg("loaded - /dp for settings") end)
end)
