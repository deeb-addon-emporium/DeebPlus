-- DeebPlus gossip skip: when an NPC opens a menu whose only point is "let me browse your goods"
-- (or "train me"), pick it for you. Toggle: DP.db.gossipSkip
-- Rules, so it never picks something you did not mean:
--   * never in combat, never when a modifier key is held (shift/ctrl/alt = "let me see the menu")
--   * never when the menu also offers quests (the quest module owns that)
--   * picks a vendor option (icon "vendor") if there is exactly one; else a trainer option if
--     there is exactly one; else, if the menu has exactly ONE option total and it is not a
--     gossip that could start something (binder, flightmaster, battlemaster...), picks that.
local DP = DeebPlus

local GetOptions   = C_GossipInfo and C_GossipInfo.GetOptions
local SelectOption = C_GossipInfo and C_GossipInfo.SelectOption
local GetAvail     = C_GossipInfo and C_GossipInfo.GetAvailableQuests
local GetActive    = C_GossipInfo and C_GossipInfo.GetActiveQuests

local RISKY = { binder = true, taxi = true, battlemaster = true, arenamaster = true, petition = true, tabard = true, banker = true, unlearn = true }

local function pickOption()
	if not DP.db or not DP.db.gossipSkip then return end
	if InCombatLockdown() then return end
	if IsShiftKeyDown() or IsControlKeyDown() or IsAltKeyDown() then return end
	if not GetOptions or not SelectOption then return end
	local avail = GetAvail and GetAvail() or {}
	local active = GetActive and GetActive() or {}
	if (#avail > 0) or (#active > 0) then return end
	local ok, options = pcall(GetOptions)
	if not ok or type(options) ~= "table" or #options == 0 then return end

	local vendor, trainer, nVendor, nTrainer = nil, nil, 0, 0
	for _, o in ipairs(options) do
		local icon = string.lower(tostring(o.icon or ""))
		local name = string.lower(tostring(o.name or ""))
		if icon == "vendor" or string.find(name, "browse your goods", 1, true) or string.find(name, "let me browse", 1, true) then
			nVendor = nVendor + 1; vendor = o
		elseif icon == "trainer" or string.find(name, "train me", 1, true) or string.find(name, "training", 1, true) then
			nTrainer = nTrainer + 1; trainer = o
		end
	end
	local pick
	if nVendor == 1 then pick = vendor
	elseif nTrainer == 1 and nVendor == 0 then pick = trainer
	elseif #options == 1 then
		local icon = string.lower(tostring(options[1].icon or ""))
		if not RISKY[icon] then pick = options[1] end
	end
	if not pick then return end
	local id = pick.gossipOptionID or pick.index
	if id == nil then return end
	C_Timer.After(0, function()
		if InCombatLockdown() then return end
		pcall(SelectOption, id)
	end)
end

local f = CreateFrame("Frame")
f:RegisterEvent("GOSSIP_SHOW")
f:SetScript("OnEvent", function() pcall(pickOption) end)

DP.register("gossip", {})
