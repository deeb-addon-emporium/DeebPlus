-- DeebPlus low-vendor module (ported from LowVendorHighlight). Toggle: DP.db.lowVendor
local DP = DeebPlus
-- Outlines, inside the bag, the one slot whose item the vendor pays the least for.
--
--   /lvh   toggle the outline on/off
--   /lvhd  print one line of raw probe values (paste it back if the outline looks wrong)
--
-- Scope: your bags only. Items the vendor will not buy are ignored, otherwise the outline
-- would always sit on quest items and keys. Nothing outside our own textures is touched, so
-- nothing here can taint a Blizzard frame or trip combat lockdown.
--
-- API shapes on THIS client (12.1.5 codebase, Camelot/Vanilla rules, build 69893,
-- Interface 16001) - these are the two that actually bite:
--   * C_Item.GetItemInfo(id) returns MULTIPLE values here and sellPrice is the 11th.
--     Blizzard reads it the same way (Blizzard_ItemButton/Shared/ItemButtonTemplate.lua).
--     Reading it as a table silently yields nothing, which is why a table-shaped read must
--     never be the only path. A table-shaped return is still accepted for future builds.
--   * C_Container.GetContainerItemInfo(bag, slot) returns a table: itemID, stackCount,
--     itemName, hyperlink, hasNoValue, ...
--
-- Painting does not depend on any Blizzard refresh hook: buttons are found by walking the
-- container frame's children for anything exposing GetBagID/GetID, and a 0.5 s ticker
-- repaints whenever a bag is open. The hook (when it exists) just makes changes instant.

local PREFIX = DP.PREFIX .. "lowvendor "
local LINE = 2                                    -- outline thickness, px
local R, G, B, A = 1, 0.78, 0.1, 0.95             -- amber
local POLL = 0.5                                  -- seconds between safety-net repaints

local f = CreateFrame("Frame")

local function enabledF() return DP.db and DP.db.lowVendor end
local hooked = false
local priceShape = "?"
local lowest = nil
local stats = { slots = 0, noVendor = 0, pending = 0, frames = 0, buttons = 0 }
local dirty, queued = true, false

local MAX_BAG = (NUM_BAG_SLOTS or 4) + 1          -- 0 = backpack, 1..N = bags, N+1 = reagent bag

local function msg(text) print(PREFIX .. text) end

-- A value we are allowed to look at. Secret values may be stored/formatted but never
-- compared, so they are skipped entirely.
local function readable(v)
	if issecretvalue and issecretvalue(v) then return false end      -- probe first: comparing throws
	if v == nil then return false end
	if type(v) == "boolean" then return false end   -- "and"-chains yield false, not nil
	if issecretvalue and issecretvalue(v) then return false end
	return true
end

-- pcall wrapper: first result, or nil when the call threw.
local function call(fn, ...)
	local good, result = pcall(fn, ...)
	if good then return result end
	return nil
end

-- Namespaced APIs are looked up once, never indexed blind: a missing namespace would throw
-- before pcall could catch it.
local function api(namespace, name)
	local ns = _G[namespace]
	if type(ns) ~= "table" then return nil end
	local fn = ns[name]
	if type(fn) ~= "function" then return nil end
	return fn
end

local GetNumSlots      = api("C_Container", "GetContainerNumSlots")
local GetItemInfoBag   = api("C_Container", "GetContainerItemInfo")
local GetItemInfo      = api("C_Item", "GetItemInfo")
local RequestItemData  = api("C_Item", "RequestLoadItemDataByID")
local NewTicker        = api("C_Timer", "NewTicker")
local TimerAfter       = api("C_Timer", "After")
local GetMoneyStringFn = type(GetMoneyString) == "function" and GetMoneyString or nil

local function later(delay, fn)
	if TimerAfter then
		pcall(TimerAfter, delay, fn)
	else
		fn()
	end
end

local function money(copper)
	if GetMoneyStringFn then
		local text = call(GetMoneyStringFn, copper)
		if text then return text end
	end
	return tostring(copper) .. "c"
end

-- ---------------------------------------------------------------------------
-- Item name + vendor price. Returns nil name when the item is not cached yet.
-- ---------------------------------------------------------------------------
local function itemNameAndPrice(itemID)
	if not GetItemInfo then return nil, nil end

	-- pcall adds the status first, so local #12 is return #11 = sellPrice.
	-- Returns are: name, link, quality, itemLevel, minLevel, type, subType, stack,
	-- equipLoc, texture, sellPrice, ...
	local good, name, _, _, _, _, _, _, _, _, _, sellPrice = pcall(GetItemInfo, itemID)
	if not good or name == nil then return nil, nil end

	if type(name) == "table" then                      -- table-shaped variant, future builds
		priceShape = "table"
		local first = name.itemName or name[1]
		if first == nil then return nil, nil end
		return first, name.sellPrice
	end

	priceShape = "multi"
	return name, sellPrice
end

-- ---------------------------------------------------------------------------
-- The scan: one pass over every bag slot, keeping the cheapest vendor price.
-- ---------------------------------------------------------------------------
local function scan()
	local best = nil
	local slots, noVendor, pending = 0, 0, 0

	for bag = 0, MAX_BAG do
		local count = call(GetNumSlots, bag) or 0
		for slot = 1, count do
			slots = slots + 1
			local info = call(GetItemInfoBag, bag, slot)
			local itemID = info and info.itemID
			if readable(itemID) then
				local name, price = itemNameAndPrice(itemID)
				if name == nil then
					-- not in the local cache yet: ask for it, re-scan when it arrives
					pending = pending + 1
					if RequestItemData then pcall(RequestItemData, itemID) end
				elseif readable(price) and price > 0 then
					if not best or price < best.price then
						best = {
							bag   = bag,
							slot  = slot,
							itemID = itemID,
							price = price,
							count = readable(info.stackCount) and info.stackCount or 1,
							name  = (readable(info.itemName) and info.itemName) or name,
						}
					end
				else
					noVendor = noVendor + 1
				end
			end
		end
	end

	return best, { slots = slots, noVendor = noVendor, pending = pending }
end

local function current()
	if dirty then
		lowest, stats = scan()
		dirty = false
	end
	return lowest
end

-- ---------------------------------------------------------------------------
-- The outline: four colour textures, anchored to the slot icon.
-- ---------------------------------------------------------------------------
local function ensureOutline(button)
	local outline = button.LVH
	if outline then return outline end

	local anchor = button
	if type(button.GetItemButtonIconTexture) == "function" then
		local good, icon = pcall(button.GetItemButtonIconTexture, button)
		if good and icon then anchor = icon end
	end

	local function edge()
		local t = button:CreateTexture(nil, "OVERLAY", nil, 7)
		t:SetColorTexture(R, G, B, A)
		t:Hide()
		return t
	end

	outline = { top = edge(), bottom = edge(), left = edge(), right = edge() }
	outline.top:SetPoint("TOPLEFT", anchor, "TOPLEFT")
	outline.top:SetPoint("TOPRIGHT", anchor, "TOPRIGHT")
	outline.top:SetHeight(LINE)
	outline.bottom:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT")
	outline.bottom:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT")
	outline.bottom:SetHeight(LINE)
	outline.left:SetPoint("TOPLEFT", anchor, "TOPLEFT")
	outline.left:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT")
	outline.left:SetWidth(LINE)
	outline.right:SetPoint("TOPRIGHT", anchor, "TOPRIGHT")
	outline.right:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT")
	outline.right:SetWidth(LINE)

	button.LVH = outline
	return outline
end

local function mark(button, on)
	local outline = button.LVH
	if not on then
		if outline then
			for _, t in pairs(outline) do t:Hide() end
		end
		return
	end
	outline = ensureOutline(button)
	for _, t in pairs(outline) do t:Show() end
end

local function paint(button, best)
	local on = best ~= nil
		and button:GetBagID() == best.bag
		and button:GetID() == best.slot
	mark(button, on == true)
end

-- ---------------------------------------------------------------------------
-- Finding the bag buttons without relying on Blizzard's own iterator.
-- ---------------------------------------------------------------------------
local function collectRoots()
	local roots = {}
	if type(ContainerFrames) == "table" then
		for _, cf in ipairs(ContainerFrames) do
			if cf then roots[#roots + 1] = cf end
		end
	end
	if ContainerFrameCombinedBags then roots[#roots + 1] = ContainerFrameCombinedBags end
	-- 12.x: the utility enumerates every live container frame, combined or split
	if type(ContainerFrameUtil_EnumerateContainerFrames) == "function" then
		local ok, iter, state, init = pcall(ContainerFrameUtil_EnumerateContainerFrames)
		if ok and type(iter) == "function" then
			for _, cf in iter, state, init do
				if type(cf) == "table" then roots[#roots + 1] = cf end
			end
		end
	end
	if #roots == 0 then
		for i = 1, 12 do
			local cf = _G["ContainerFrame" .. i]
			if cf then roots[#roots + 1] = cf end
		end
	end
	return roots
end

local function enumerateItems(frame, best, count)
	if type(frame.EnumerateValidItems) ~= "function" then return count, false end
	local ok, iter, state, init = pcall(frame.EnumerateValidItems, frame)
	if not ok or type(iter) ~= "function" then return count, false end
	local any = false
	for _, button in iter, state, init do
		if type(button) == "table" and type(button.GetBagID) == "function" and type(button.GetID) == "function" then
			any = true
			count = count + 1
			paint(button, best)
		end
	end
	return count, any
end

local function walkButtons(frame, best, depth, count)
	if depth > 4 then return count end
	local children = call(frame.GetChildren, frame)
	if type(children) ~= "table" then return count end
	for _, child in ipairs(children) do
		if type(child.GetBagID) == "function" and type(child.GetID) == "function" then
			count = count + 1
			pcall(paint, child, best)
		end
		count = walkButtons(child, best, depth + 1, count)
	end
	return count
end

local function walkRoot(frame, best, depth, count)
	local n, any = enumerateItems(frame, best, count)
	if any then return n end
	return walkButtons(frame, best, depth, count)
end

local function paintRoots(roots)
	local best = enabledF() and current() or nil
	local count = 0
	for _, root in ipairs(roots) do
		count = walkRoot(root, best, 0, count)
	end
	stats.frames = #roots
	stats.buttons = count
	return count
end

local function anyShown(roots)
	for _, root in ipairs(roots) do
		if root then
			local good, shown = pcall(root.IsShown, root)
			if good and shown then return true end
		end
	end
	return false
end

-- ---------------------------------------------------------------------------
-- Wiring
-- ---------------------------------------------------------------------------
local function repaint()
	local roots = collectRoots()
	paintRoots(roots)
	return roots
end

-- Bag contents settle in bursts; one recompute per burst instead of one per event.
local function refreshSoon()
	if queued then return end
	queued = true
	later(0.2, function()
		queued = false
		dirty = true
		repaint()
	end)
end

local function hookBags()
	if hooked then return true end
	if type(ContainerFrameMixin) ~= "table" then return false end
	hooksecurefunc(ContainerFrameMixin, "UpdateItems", function()
		pcall(function() dirty = true; repaint() end)
	end)
	hooked = true
	return true
end

local function hookBagsRetry(tries)
	if hookBags() then
		dirty = true
		repaint()
		return
	end
	if tries > 0 then
		later(1, function() hookBagsRetry(tries - 1) end)
	end
end

-- Safety net: repaint twice a second while a bag is open, so being unable to hook or
-- missing an event can never leave a stale outline. Nothing runs while bags are closed.
local function startPoll()
	if not NewTicker then return end
	pcall(NewTicker, POLL, function()
		local roots = collectRoots()
		if anyShown(roots) then
			dirty = true
			paintRoots(roots)
		end
	end)
end

-- One line at login so "did it load and what did it pick" needs no typing.
local function reportOnce(tries)
	dirty = true
	local best = current()
	if stats.pending > 0 and tries > 0 then
		later(1, function() reportOnce(tries - 1) end)
		return
	end
	if best then
		msg(string.format("cheapest you can vendor: %s for %s (bag %d, slot %d)",
			best.name, money(best.price), best.bag, best.slot))
	elseif stats.pending > 0 then
		msg(string.format("%d items still loading - /lvhd in a moment", stats.pending))
	else
		msg("nothing vendor-sellable in your bags")
	end
end

f:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		hookBagsRetry(10)
		startPoll()
		later(1, function() reportOnce(3) end)
	elseif event == "PLAYER_ENTERING_WORLD" then
		hookBagsRetry(10)
		startPoll()
	elseif event == "ADDON_LOADED" then
		-- The bag frames can arrive after we load; hook the moment the mixin exists.
		if not hooked and type(ContainerFrameMixin) == "table" then hookBagsRetry(0) end
	else
		refreshSoon()
	end
end)

for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "ADDON_LOADED", "BAG_UPDATE_DELAYED", "GET_ITEM_INFO_RECEIVED" }) do
	pcall(f.RegisterEvent, f, event)
end


SLASH_LOWVENDORHIGHLIGHTDBG1 = "/lvhd"
SlashCmdList.LOWVENDORHIGHLIGHTDBG = function()
	dirty = true
	local best = current()
	repaint()
	local parts = {}

	if best then
		parts[#parts + 1] = string.format("low=%s vp=%s x%d total=%s bag%d/slot%d id=%d",
			best.name, money(best.price), best.count, money(best.price * best.count),
			best.bag, best.slot, best.itemID)
	else
		parts[#parts + 1] = "low=none"
	end

	parts[#parts + 1] = string.format("scanned=%d noVendor=%d pending=%d", stats.slots, stats.noVendor, stats.pending)
	parts[#parts + 1] = string.format("frames=%d buttons=%d", stats.frames, stats.buttons)
	parts[#parts + 1] = "hook=" .. (hooked and "ok" or "MISSING")
	parts[#parts + 1] = "poll=" .. (NewTicker and "on" or "NO-TIMER")
	parts[#parts + 1] = "price=" .. priceShape
	parts[#parts + 1] = "enabled=" .. (enabledF() and "1" or "0")
	parts[#parts + 1] = "bags=" .. tostring(MAX_BAG + 1)
	parts[#parts + 1] = "apis=" .. table.concat({
		GetNumSlots and "slots" or "-",
		GetItemInfoBag and "info" or "-",
		GetItemInfo and "item" or "-",
		RequestItemData and "load" or "-",
	}, "+")

	msg(table.concat(parts, "  "))
end

DP.register("lowVendor", { apply = function() if refreshSoon then refreshSoon() end end })
