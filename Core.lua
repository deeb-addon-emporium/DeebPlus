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
	autoRepair = true,
	autoAmmo = true,          -- top up arrows/bullets at vendors, above level 4
	ammoTarget = 1000,        -- repair everything at any repair vendor
	fogOff = true,
	statusText = true,        -- always show HP/mana numbers on unit frames            -- volumeFog 0
	tooltipCursor = true,     -- tooltip follows the mouse
	fsr = true,               -- five second rule bar on the mana bar
	lowVendor = true,         -- outline the cheapest-to-vendor bag slot
	threatPlates = true,      -- threat % on stock nameplates
	questXP = true,           -- remember quest XP seen under the cap, show it at the cap
	errorCatcher = true,      -- Lua errors to a quiet list + /dp errors, no popup
	hideIssueReporter = true, -- keep the beta issue reporter off screen
	targetXP = true,          -- kill XP next to the target's level, below the cap
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
	-- Settings have come up empty once (2026-09-21) for no reason we could find. Every character
	-- keeps a mirror; if the account copy has no save stamp but the mirror does, restore it and say so.
	if not DeebPlusDB._saved and type(DeebPlusMirror) == "table" and DeebPlusMirror._saved then
		for k, v in pairs(DeebPlusMirror) do DeebPlusDB[k] = v end
		C_Timer.After(4, function() DP.msg("|cffff8080settings came up empty|r - restored from this character's mirror (saved " .. date("%H:%M %d %b", DeebPlusMirror._saved) .. ")") end)
	elseif not DeebPlusDB._saved then
		C_Timer.After(4, function() DP.msg("fresh settings (first run, or they were reset)") end)
	end
	for k, v in pairs(DP.defaults) do
		if DeebPlusDB[k] == nil then DeebPlusDB[k] = v end
	end
	DP.db = DeebPlusDB
	DeebPlusDB._saved = time()
	DP.apply()
	C_Timer.After(2, function() DP.msg("loaded - /dp for settings") end)
end)

-- mirror the account settings into this character's own file at logout
local lf = CreateFrame("Frame")
lf:RegisterEvent("PLAYER_LOGOUT")
lf:SetScript("OnEvent", function()
	if type(DeebPlusDB) ~= "table" then return end
	DeebPlusDB._saved = time()
	DeebPlusMirror = {}
	for k, v in pairs(DeebPlusDB) do DeebPlusMirror[k] = v end
end)
