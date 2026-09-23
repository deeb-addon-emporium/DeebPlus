-- DeebPlus auto ammo: at any vendor that sells ammo, top up to a target amount, matching the
-- ranged weapon you have equipped (bow/crossbow = arrows, gun = bullets). Only above level 4.
-- Buys the best ammo you can use (highest required level that is still <= your level).
-- If you carry a quiver or ammo pouch it fills THAT: every slot to a full stack. With no
-- quiver it falls back to DP.db.ammoTarget (default 1000).
-- Settings: DP.db.autoAmmo (on/off), DP.db.ammoTarget
local DP = DeebPlus

local CLASS_PROJECTILE = (Enum and Enum.ItemClass and Enum.ItemClass.Projectile) or 6
local SUB_ARROW, SUB_BULLET = 2, 3
local CLASS_WEAPON = (Enum and Enum.ItemClass and Enum.ItemClass.Weapon) or 2
local WEAPON_BOW, WEAPON_GUN, WEAPON_CROSSBOW = 2, 3, 18
local RANGED_SLOT, AMMO_SLOT = 18, 0

local function facts(item)
	local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	if not fn or not item then return end
	local ok, name, _, _, _, minLevel, _, _, _, _, _, price, classID, subClassID = pcall(fn, item)
	if not ok or not name then return end
	return name, minLevel or 0, classID, subClassID, price
end

-- which ammo type does the equipped ranged weapon need? nil if none
local function neededAmmo()
	local link = GetInventoryItemLink("player", RANGED_SLOT)
	if not link then return nil end
	local _, _, classID, sub = facts(link)
	if classID ~= CLASS_WEAPON then return nil end
	if sub == WEAPON_BOW or sub == WEAPON_CROSSBOW then return SUB_ARROW, "arrows" end
	if sub == WEAPON_GUN then return SUB_BULLET, "bullets" end
	return nil
end

local GetNumSlots     = C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
local GetFreeSlots    = C_Container and C_Container.GetContainerNumFreeSlots or GetContainerNumFreeSlots
local GetSlotInfo     = C_Container and C_Container.GetContainerItemInfo
local FAMILY_QUIVER, FAMILY_POUCH = 1, 2

-- the quiver / ammo pouch bag id for this ammo type, or nil
local function ammoBag(sub)
	local wantFamily = (sub == SUB_ARROW) and FAMILY_QUIVER or FAMILY_POUCH
	for bag = 1, (NUM_BAG_SLOTS or 4) do
		local ok, free, family = pcall(GetFreeSlots, bag)
		if ok and family and family ~= 0 and bit.band(family, wantFamily) ~= 0 then return bag end
	end
	return nil
end

-- how many of this ammo (by name) are in the bag, and how many slots it has
local function bagAmmo(bag, name)
	local count, slots = 0, GetNumSlots(bag) or 0
	for s = 1, slots do
		local info = GetSlotInfo and GetSlotInfo(bag, s)
		if info and info.itemName == name and info.stackCount and not (issecretvalue and issecretvalue(info.stackCount)) then
			count = count + info.stackCount
		end
	end
	return count, slots
end

local function ammoCount()
	local n = 0
	local ok, c = pcall(GetInventoryItemCount, "player", AMMO_SLOT)
	if ok and type(c) == "number" and not (issecretvalue and issecretvalue(c)) then n = c end
	return n
end

local function onMerchant()
	if not DP.db or not DP.db.autoAmmo then return end
	local lvl = UnitLevel("player") or 0
	if lvl <= 4 then return end
	local sub, word = neededAmmo()
	if not sub then return end
	-- find the best ammo the vendor sells first, so the quiver fill knows which item to count
	local n = GetMerchantNumItems and GetMerchantNumItems() or 0
	local best, bestLvl, bestIdx, bestName
	for i = 1, n do
		local link = GetMerchantItemLink(i)
		local name, minLevel, classID, sc = facts(link)
		if name and classID == CLASS_PROJECTILE and sc == sub and minLevel <= lvl then
			if not best or minLevel > bestLvl then best, bestLvl, bestIdx, bestName = link, minLevel, i, name end
		end
	end
	if not bestIdx then return end
	local maxStack = select(8, (function() local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo; return fn(best) end)()) or 200
	local have, target
	local bag = ammoBag(sub)
	if bag then
		local inBag, slots = bagAmmo(bag, bestName)
		have, target = inBag, slots * maxStack          -- fill the quiver: every slot a full stack
	else
		have, target = ammoCount(), tonumber(DP.db.ammoTarget) or 1000
	end
	if have >= target then return end
	local want = target - have
	local _, _, price, quantity = GetMerchantItemInfo(bestIdx)      -- quantity = items per purchase (stack sold as)
	local per = (quantity and quantity > 0) and quantity or 1
	local maxStack = select(8, facts(best)) or 200
	local unitPrice = (price or 0) / per
	local affordable = unitPrice > 0 and math.floor(GetMoney() / unitPrice) or want
	local toBuy = math.min(want, affordable)
	if toBuy <= 0 then DP.msg("ammo: cannot afford " .. bestName); return end
	-- BuyMerchantItem takes a count of items (not stacks) on this client family; buy in chunks
	local bought = 0
	local chunk = 200
	while bought < toBuy do
		local k = math.min(chunk, toBuy - bought)
		local ok = pcall(BuyMerchantItem, bestIdx, k)
		if not ok then break end
		bought = bought + k
	end
	if bought > 0 then
		DP.msg(string.format("bought %d %s (%s) - %d held, target %d", bought, word, bestName, have + bought, target))
	end
end

local f = CreateFrame("Frame")
f:RegisterEvent("MERCHANT_SHOW")
f:SetScript("OnEvent", function() C_Timer.After(0.4, function() pcall(onMerchant) end) end)

DP.ammoCmd = function(rest)
	local n = tonumber(rest)
	if n then DP.db.ammoTarget = n; DP.msg("ammo target " .. n) else DP.msg("ammo target is " .. tostring(DP.db.ammoTarget or 1000) .. "  -  /dp ammo <number>") end
end

DP.register("ammo", {})
