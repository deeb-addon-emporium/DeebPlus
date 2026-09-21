-- DeebPlus quest XP memory. At the level cap the server reports every quest's XP as 0, and
-- nothing on the client has the real number. But a character UNDER the cap does see it. So:
-- whenever any of your characters sees a quest with XP > 0 (in the log, or offered), remember
-- it account-wide. When the game says 0, show what was remembered and who saw it.
-- Toggle: DP.db.questXP.  /dp xp <quest id or part of a name> prints what is remembered.
local DP = DeebPlus

local function store()
	DP.db.questXPSeen = DP.db.questXPSeen or {}
	return DP.db.questXPSeen
end

local function me() return (UnitName("player") or "?") .. " at " .. (UnitLevel("player") or 0) end

local function remember(questID, xp, name)
	if not questID or type(xp) ~= "number" or xp <= 0 then return end
	if issecretvalue and issecretvalue(xp) then return end
	local t = store()
	local old = t[questID]
	-- a lower-level sighting is the truer number (over-level sightings are reduced)
	if old and old.lvl <= (UnitLevel("player") or 99) and old.xp >= xp then return end
	t[questID] = { xp = xp, lvl = UnitLevel("player") or 0, who = UnitName("player") or "?", name = name or (old and old.name) }
end

-- sweep the quest log
local function sweepLog()
	if not DP.db or not DP.db.questXP then return end
	if not C_QuestLog or not C_QuestLog.GetNumQuestLogEntries then return end
	local n = C_QuestLog.GetNumQuestLogEntries() or 0
	for i = 1, n do
		local info = C_QuestLog.GetInfo(i)
		if info and not info.isHeader and info.questID then
			local ok, xp = pcall(GetQuestLogRewardXP, info.questID)
			if ok then remember(info.questID, xp, info.title) end
		end
	end
end

-- the quest being offered right now
local function sweepOffer()
	if not DP.db or not DP.db.questXP then return end
	local id = GetQuestID and GetQuestID()
	local ok, xp = pcall(GetRewardXP)
	if id and ok then remember(id, xp, GetTitleText and GetTitleText()) end
end

local f = CreateFrame("Frame")
for _, e in ipairs({ "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_DETAIL", "QUEST_COMPLETE", "PLAYER_ENTERING_WORLD" }) do
	pcall(f.RegisterEvent, f, e)
end
local pendingSweep = false
f:SetScript("OnEvent", function(_, event)
	if event == "QUEST_DETAIL" or event == "QUEST_COMPLETE" then pcall(sweepOffer); return end
	if pendingSweep then return end
	pendingSweep = true
	C_Timer.After(0.5, function() pendingSweep = false; pcall(sweepLog) end)
end)

-- ---- show it where the game shows 0 ----
local line
local function ensureLine(parent)
	if line and line:GetParent() == parent then return line end
	if line then line:Hide() end
	line = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	line:SetJustifyH("LEFT")
	return line
end

local function showFor(questID, anchor)
	if not line then return end
	line:Hide()
	if not DP.db or not DP.db.questXP or not questID then return end
	local ok, xp = pcall(GetQuestLogRewardXP, questID)
	if ok and type(xp) == "number" and xp > 0 then return end   -- the game already shows it
	local seen = store()[questID]
	if not seen then return end
	line:ClearAllPoints()
	line:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 4)
	line:SetText(string.format("|cffffd080XP %s|r  |cff808080seen on %s at %d|r", BreakUpLargeNumbers and BreakUpLargeNumbers(seen.xp) or seen.xp, seen.who, seen.lvl))
	line:Show()
end

local hooked = false
local function apply()
	if hooked or type(QuestInfo_Display) ~= "function" then return end
	hooked = true
	hooksecurefunc("QuestInfo_Display", function(template, parentFrame)
		local rewards = QuestInfoRewardsFrame
		if not rewards or not parentFrame then return end
		local questID
		if QuestInfoFrame and QuestInfoFrame.questLog then
			questID = C_QuestLog and C_QuestLog.GetSelectedQuest and C_QuestLog.GetSelectedQuest()
		else
			questID = GetQuestID and GetQuestID()
		end
		ensureLine(rewards)
		showFor(questID, rewards)
	end)
end

DP.questXPLookup = function(text)
	text = string.lower(strtrim(text or ""))
	local t = store(); local n = 0
	for id, s in pairs(t) do
		if tostring(id) == text or (s.name and string.find(string.lower(s.name), text, 1, true)) then
			DP.msg(string.format("%s (%d): %d XP, seen on %s at %d", s.name or "?", id, s.xp, s.who, s.lvl)); n = n + 1
			if n >= 15 then break end
		end
	end
	if n == 0 then DP.msg("nothing remembered for '" .. text .. "'. " .. (next(t) and "" or "No sightings yet: log in on a character under the cap and open its quest log.")) end
end

DP.register("questXP", { apply = apply })
