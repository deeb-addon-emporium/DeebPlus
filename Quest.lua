-- DeebPlus quest + vendor module (ported from AutoQuest). Settings live in DeebPlus.db.
local DP = DeebPlus
local PREFIX = DP.PREFIX

local f = CreateFrame("Frame")

-- state
local function enabledF()   return DP.db and DP.db.questAccept end
local function walkF()      return DP.db and DP.db.questWalk end
local function trivialF()   return DP.db and DP.db.questTrivial end
local function junkF()      return DP.db and DP.db.vendorJunk end
local paused, pauseWhy = false, nil
local chain = 0
local counts = {}                                   -- counts[event] = n, for /aqd
local lastNote = nil

-- A blocked action is switched off rather than retried: the client refuses some calls
-- (protected, hardware event required) and we must not spam the error.
local blocked = {}

-- ---------------------------------------------------------------------------
-- API. Every name is looked up once, never indexed blind, always pcall'd at the call site.
-- ---------------------------------------------------------------------------
local function api(namespace, name)
	local ns = _G[namespace]
	if type(ns) ~= "table" then return nil end
	local fn = ns[name]
	if type(fn) ~= "function" then return nil end
	return fn
end

local function global(name)
	local fn = _G[name]
	if type(fn) ~= "function" then return nil end
	return fn
end

local AcceptQuestFn        = global("AcceptQuest")
local CompleteQuestFn      = global("CompleteQuest")
local GetQuestRewardFn     = global("GetQuestReward")
local GetQuestIDFn         = global("GetQuestID")
local GetNumQuestChoicesFn = global("GetNumQuestChoices")
local GetQuestMoneyToGetFn = global("GetQuestMoneyToGet")
local IsQuestCompletableFn = global("IsQuestCompletable")
local QuestGetAutoAcceptFn = global("QuestGetAutoAccept")
local QuestFlagsPVPFn      = global("QuestFlagsPVP")
local CloseQuestFn         = global("CloseQuest")
-- legacy greeting panel (Vanilla-style quest NPCs)
local GetNumActiveQuestsFn     = global("GetNumActiveQuests")
local GetNumAvailableQuestsFn  = global("GetNumAvailableQuests")
local GetActiveTitleFn         = global("GetActiveTitle")
local GetAvailableQuestInfoFn = global("GetAvailableQuestInfo")
local SelectActiveQuestFn      = global("SelectActiveQuest")
local SelectAvailableQuestFn   = global("SelectAvailableQuest")
-- gossip panel (current-style quest NPCs)
local GetActiveQuestsFn     = api("C_GossipInfo", "GetActiveQuests")
local GetAvailableQuestsFn  = api("C_GossipInfo", "GetAvailableQuests")
local SelectActiveGossipFn  = api("C_GossipInfo", "SelectActiveQuest")
local SelectAvailGossipFn   = api("C_GossipInfo", "SelectAvailableQuest")
local IsQuestTrivialFn      = api("C_QuestLog", "IsQuestTrivial")
local TimerAfter            = api("C_Timer", "After")

local function msg(text) print(PREFIX .. text) end

-- Secret values (12.0) may be stored and formatted but never compared: skip them wholesale.
-- `plain` is for boolean fields, where rejecting booleans (correct for numbers) would be wrong.
local function plain(v)
	return not (issecretvalue and issecretvalue(v))
end

-- The probe comes first, always: comparing a secret value throws, so a guard that tests `v ~= nil`
-- before asking issecretvalue crashes on exactly the input it exists to handle.
local function readable(v)
	if issecretvalue and issecretvalue(v) then return false end
	return v ~= nil
end
local function later(delay, fn)
	if TimerAfter then
		pcall(TimerAfter, delay, fn)
	else
		fn()
	end
end

-- first return of a pcall, or nil
local function call(fn, ...)
	if not fn then return nil end
	local good, a = pcall(fn, ...)
	if good then return a end
	return nil
end

-- several returns of a pcall, or nothing
local function callMulti(fn, ...)
	if not fn then return end
	local good, a, b, c, d, e, f2, g, h = pcall(fn, ...)
	if not good then return end
	return a, b, c, d, e, f2, g, h
end

local function frameShown(name)
	local frame = _G[name]
	if not frame or type(frame.IsVisible) ~= "function" then return nil end
	local good, shown = pcall(frame.IsVisible, frame)
	if not good then return nil end
	return shown and true or false
end

local function frameText(name)
	return frameShown(name) == true and "on" or (frameShown(name) == false and "off" or "?")
end

-- ---------------------------------------------------------------------------
-- Deferred action queue.
-- Quest calls must not run inside Blizzard's own panel dispatch, and they are refused
-- during combat lockdown, so: key actions, run them on the next tick, and hold them while
-- InCombatLockdown() (mirrors the deferral AutoTurnIn uses for the same reason).
-- ---------------------------------------------------------------------------
local queued, queuedTimer = {}, false
local deferFrame = CreateFrame("Frame")

local function runAction(name, action)
	local good, err = pcall(action)
	if good then return end
	if not blocked[name] then
		blocked[name] = true
		msg(string.format("%s was refused by the client (%s) - that action is off now, the rest still works",
			name, tostring(err)))
	end
end

local function flush()
	if InCombatLockdown() then
		pcall(deferFrame.RegisterEvent, deferFrame, "PLAYER_REGEN_ENABLED")
		return
	end
	pcall(deferFrame.UnregisterEvent, deferFrame, "PLAYER_REGEN_ENABLED")

	local actions = queued
	queued = {}
	for name, action in pairs(actions) do runAction(name, action) end
end

local function schedule()
	if queuedTimer then return end
	queuedTimer = true
	later(0, function()
		queuedTimer = false
		flush()
	end)
end

local function queue(name, action)
	if blocked[name] then return false end
	queued[name] = action
	schedule()
	return true
end

deferFrame:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_ENABLED" then schedule() end
end)

-- ---------------------------------------------------------------------------
-- Rules
-- ---------------------------------------------------------------------------
local function usable()
	return enabledF() and not InCombatLockdown()
end

local function trivialBlocked(questID)
	if trivialF() then return false end
	if not IsQuestTrivialFn or not questID then return false end
	return call(IsQuestTrivialFn, questID) == true
end

-- ---------------------------------------------------------------------------
-- Accept
-- ---------------------------------------------------------------------------
local function onQuestDetail()
	if not usable() then return end
	paused, pauseWhy = false, nil      -- a fresh offer means no reward panel is waiting on us

	if QuestGetAutoAcceptFn and call(QuestGetAutoAcceptFn) then
		if CloseQuestFn then queue("close", function()
			if frameShown("QuestFrameDetailPanel") == false then return end
			CloseQuestFn()
		end) end
		return
	end

	local questID = call(GetQuestIDFn)
	if not questID then return end
	if trivialBlocked(questID) then
		lastNote = "detail skipped: trivial quest"
		return
	end
	if QuestFlagsPVPFn and call(QuestFlagsPVPFn) then
		lastNote = "detail skipped: PvP flag, your call"
		return
	end
	if not AcceptQuestFn then return end

	queue("accept", function()
		if frameShown("QuestFrameDetailPanel") == false then return end   -- panel went away
		AcceptQuestFn()
	end)
end

-- ---------------------------------------------------------------------------
-- Turn in
-- ---------------------------------------------------------------------------
local function onQuestProgress()
	if not usable() then return end
	if not IsQuestCompletableFn or call(IsQuestCompletableFn) ~= true then return end
	if not CompleteQuestFn then return end

	queue("complete", function()
		if frameShown("QuestFrameProgressPanel") == false then return end
		CompleteQuestFn()
	end)
end

local function onQuestComplete()
	if not enabledF() then return end

	local choices = GetNumQuestChoicesFn and call(GetNumQuestChoicesFn) or 0
	if choices and choices > 0 then
		-- His reward to pick. Stop the chain so nothing else gets selected behind the panel.
		paused, pauseWhy = true, string.format("%d reward(s) to choose", choices)
		return
	end

	local money = GetQuestMoneyToGetFn and call(GetQuestMoneyToGetFn) or 0
	if money and money > 0 then
		paused, pauseWhy = true, "completion costs money"
		return
	end

	if not usable() or not GetQuestRewardFn then return end
	queue("reward", function()
		if frameShown("QuestFrameRewardPanel") == false then return end
		GetQuestRewardFn(0)                     -- 0 choices: nothing to pick
	end)
end

-- ---------------------------------------------------------------------------
-- Walking the NPC's list (the hands-free part)
-- ---------------------------------------------------------------------------
local MAX_CHAIN = 20

local function chainOpen()
	if not walkF() or paused then return false end
	if not usable() then return false end
	if chain >= MAX_CHAIN then
		lastNote = "chain cap reached, walk again to continue"
		return false
	end
	chain = chain + 1
	return true
end

local function walkGossip()
	if not chainOpen() then return end

	local actives = GetActiveQuestsFn and call(GetActiveQuestsFn)
	if type(actives) == "table" then
		for _, info in ipairs(actives) do
			if type(info) == "table" and info.isComplete and info.questID and SelectActiveGossipFn then
				queue("selectActive", function() SelectActiveGossipFn(info.questID) end)
				return
			end
		end
	end

	local available = GetAvailableQuestsFn and call(GetAvailableQuestsFn)
	if type(available) == "table" then
		for _, info in ipairs(available) do
			if type(info) == "table" and info.questID and info.isIgnored ~= true
				and (trivialF() or not info.isTrivial) and SelectAvailGossipFn then
				queue("selectAvailable", function() SelectAvailGossipFn(info.questID) end)
				return
			end
		end
	end
end

local function walkGreeting()
	if not usable() then return end
	paused, pauseWhy = false, nil     -- one quest panel at a time: no reward is pending here
	if not chainOpen() then return end

	local n = GetNumActiveQuestsFn and call(GetNumActiveQuestsFn) or 0
	for index = 1, (tonumber(n) or 0) do
		local _title, isComplete = callMulti(GetActiveTitleFn, index)
		if isComplete and SelectActiveQuestFn then
			queue("selectActive", function() SelectActiveQuestFn(index) end)
			return
		end
	end

	local m = GetNumAvailableQuestsFn and call(GetNumAvailableQuestsFn) or 0
	for index = 1, (tonumber(m) or 0) do
		local isTrivial = callMulti(GetAvailableQuestInfoFn, index)
		if trivialF() or not isTrivial then
			if SelectAvailableQuestFn then
				queue("selectAvailable", function() SelectAvailableQuestFn(index) end)
			end
			return
		end
	end
end

-- ---------------------------------------------------------------------------
-- Auto-sell junk at a merchant
-- The client ships the sanctioned call for this - C_MerchantFrame.SellAllJunkItems(), the same
-- one its own "Sell All Junk" button confirms into - so that is what runs, rather than a
-- hand-rolled sell loop. It is gated by:
--   * /aq junk (on by default) plus the master switch
--   * the buy tab being selected, never the buyback tab (mirrors the client's CanSellItems())
--   * C_MerchantFrame.GetNumJunkItems() > 0
--   * a veto: one sellable Poor *quest item* in an included bag stops the whole sale.
--     Auto-deleting quest items is not a recoverable mistake worth risking for convenience.
-- Per-bag opt-outs the player set in the bag menu (ExcludeJunkSell, and its backpack variant)
-- are respected by skipping those bags when counting and when vetoing.
-- Criterion is the client's own (ContainerFrameItemButtonMixin:UpdateJunkItem):
-- quality == Poor and not hasNoValue. The vendor price is only used for the summary line.
-- ---------------------------------------------------------------------------
local POOR         = (Enum and Enum.ItemQuality and Enum.ItemQuality.Poor) or 0
local EXCLUDE_JUNK = (Enum and Enum.BagSlotFlags and Enum.BagSlotFlags.ExcludeJunkSell) or 64
local MAX_BAG      = (NUM_BAG_SLOTS or 4) + 1

local GetNumSlotsFn        = api("C_Container", "GetContainerNumSlots")
local GetBagItemInfoFn     = api("C_Container", "GetContainerItemInfo")
local GetBagQuestInfoFn    = api("C_Container", "GetContainerItemQuestInfo")
local GetBagSlotFlagFn     = api("C_Container", "GetBagSlotFlag")
local GetBackpackJunkOffFn = api("C_Container", "GetBackpackSellJunkDisabled")
local GetItemInfoFn        = api("C_Item", "GetItemInfo")
local GetNumJunkItemsFn    = api("C_MerchantFrame", "GetNumJunkItems")
local SellAllJunkFn        = api("C_MerchantFrame", "SellAllJunkItems")
local GetMoneyStringFn     = global("GetMoneyString")

local function money(copper)
	if GetMoneyStringFn then
		local text = call(GetMoneyStringFn, copper)
		if text then return text end
	end
	return tostring(copper) .. "c"
end

local function priceOf(itemID)
	if not GetItemInfoFn then return nil end
	-- pcall adds the status first, so local #12 is return #11 = sellPrice (see §2 of AGENTS).
	local good, _name, _, _, _, _, _, _, _, _, _, sellPrice = pcall(GetItemInfoFn, itemID)
	if not good or type(sellPrice) ~= "number" then return nil end   -- "and"-chains yield false
	return plain(sellPrice) and sellPrice or nil
end

-- The client's per-bag junk opt-out, read the same way its own bag menu writes it.
local function bagIncluded(bag)
	if bag == 0 then
		return call(GetBackpackJunkOffFn) ~= true
	end
	return call(GetBagSlotFlagFn, bag, EXCLUDE_JUNK) ~= true
end

local junkState = { current = 0, value = 0, valueKnown = true, quest = 0 }

-- count = sellable junk, quest = junk the player might need, value = what it is worth
local function junkScan()
	local count, value, quest, valueKnown = 0, 0, 0, true
	for bag = 0, MAX_BAG do
		if bagIncluded(bag) then
			local slots = call(GetNumSlotsFn, bag) or 0
			for slot = 1, tonumber(slots) or 0 do
				local info = call(GetBagItemInfoFn, bag, slot)
				local quality, itemID = info and info.quality, info and info.itemID
				-- The client's own junk test (ContainerFrameItemButtonMixin:UpdateJunkItem):
				-- Poor quality, and the vendor will actually buy it. A secret in either field
				-- means "unknown", and unknown never sells.
				local unsellable = info and (info.hasNoValue == true or not plain(info.hasNoValue))
				local locked = info and (info.isLocked == true or not plain(info.isLocked))
				if readable(quality) and quality == POOR and readable(itemID)
					and not unsellable and not locked then
					local questInfo = call(GetBagQuestInfoFn, bag, slot)
					if type(questInfo) == "table" and questInfo.isQuestItem == true then
						quest = quest + 1
					else
						count = count + 1
						local price = priceOf(itemID)
						if price then
							value = value + price * (readable(info.stackCount) and info.stackCount or 1)
						else
							valueKnown = false
						end
					end
				end
			end
		end
	end
	return count, value, valueKnown, quest
end

local function merchantCanSell()
	local frame = _G.MerchantFrame
	if not frame then return true end                 -- unknown frame: let the API decide
	if type(frame.IsShown) == "function" then
		local good, shown = pcall(frame.IsShown, frame)
		if good and shown ~= true then return false end
	end
	local tab = frame.selectedTab
	if type(tab) == "number" and tab ~= 1 then return false end   -- buyback tab: never sell
	return true
end

local pendingSale = nil

local function verifySale()
	local pending = pendingSale
	if not pending then return end
	pendingSale = nil

	local after = GetNumJunkItemsFn and call(GetNumJunkItemsFn)
	local sold = type(after) == "number" and (pending.before - after) or pending.count

	if type(sold) ~= "number" or sold <= 0 then
		lastNote = "junk sell did nothing"
		msg(string.format("tried to sell %d junk item(s) but nothing left the bags - /aqd has the detail", pending.count))
		return
	end

	local amount = (pending.valueKnown and sold == pending.count) and (" for " .. money(pending.value)) or ""
	lastNote = string.format("sold %d junk", sold)
	msg(string.format("sold %d junk item%s%s", sold, sold == 1 and "" or "s", amount))
end

local function onMerchantShow()
	if not enabledF() or not junkF() then return end
	if not SellAllJunkFn then
		lastNote = "merchant: no SellAllJunkItems API"
		return
	end
	if not GetBagQuestInfoFn then
		-- Without per-item quest detection the veto cannot exist, and a wrong sale destroys
		-- quest progress. Refusing to automate is the only safe failure mode.
		lastNote = "merchant: no quest-info API, refusing to sell"
		return
	end
	if not usable() then
		lastNote = "merchant: in combat, skipped"
		return
	end

	local count, value, valueKnown, quest = junkScan()
	junkState.current, junkState.value, junkState.valueKnown, junkState.quest = count, value, valueKnown, quest

	if quest > 0 then
		lastNote = string.format("junk squelched: %d grey quest item(s)", quest)
		msg(string.format("not auto-selling: %d sellable grey quest item(s) in the bags - move them out and reopen the merchant (/aqd)",
			quest))
		return
	end
	if count == 0 then
		lastNote = "merchant: no junk"
		return
	end

	local before = GetNumJunkItemsFn and call(GetNumJunkItemsFn)
	pendingSale = {
		before = type(before) == "number" and before or count,
		count = count,
		value = value,
		valueKnown = valueKnown,
	}
	lastNote = string.format("junk sell queued (%d)", count)

	queue("junkSell", function()
		if not merchantCanSell() then
			pendingSale = nil                     -- no misleading "nothing left the bags" later
			lastNote = "junk sell skipped: merchant closed or buyback tab"
			return
		end
		SellAllJunkFn()
	end)
	later(2, verifySale)
end


-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------
local handlers = {
	QUEST_DETAIL    = onQuestDetail,
	QUEST_PROGRESS  = onQuestProgress,
	QUEST_COMPLETE  = onQuestComplete,
	GOSSIP_SHOW     = walkGossip,
	QUEST_GREETING  = walkGreeting,
	QUEST_FINISHED  = function() paused, pauseWhy = false, nil end,
	GOSSIP_CLOSED   = function() paused, pauseWhy, chain = false, nil, 0 end,
	MERCHANT_SHOW   = onMerchantShow,
	MERCHANT_CLOSED = function() end,
	PLAYER_LOGIN    = function() chain = 0 end,
}
f:SetScript("OnEvent", function(_, event, ...)
	counts[event] = (counts[event] or 0) + 1
	local handler = handlers[event]
	if handler then pcall(handler, ...) end
end)
for _, event in ipairs({ "PLAYER_LOGIN", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_FINISHED",
	"GOSSIP_SHOW", "GOSSIP_CLOSED", "QUEST_GREETING", "MERCHANT_SHOW", "MERCHANT_CLOSED" }) do
	pcall(f.RegisterEvent, f, event)
end

-- /dpd state dump (was /aqd)
SLASH_DEEBPLUSDBG1 = "/dpd"
SlashCmdList.DEEBPLUSDBG = function()
	local names = {}
	for _, name in ipairs({ "accept", "complete", "reward", "close", "selectActive", "selectAvailable", "junkSell" }) do
		names[#names + 1] = string.format("%s=%s", name, blocked[name] and "REFUSED" or "ok")
	end
	msg(string.format("quest=%s walk=%s trivial=%s junk=%s combat=%s paused=%s chain=%d | %s | last=%s",
		enabledF() and "1" or "0", walkF() and "1" or "0", trivialF() and "yes" or "no", junkF() and "on" or "off",
		InCombatLockdown() and "yes" or "no", pauseWhy or "no", chain, table.concat(names, " "), lastNote or "none"))
end
DP.register("quest", {})
