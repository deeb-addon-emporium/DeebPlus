-- DeebPlus chat filter: drop any chat line containing a banned phrase, unless the sender is
-- on your friends list (character friends or Battle.net friends). Phrases: DP.db.banPhrases,
-- one per line, matched case-insensitively as plain text.
local DP = DeebPlus

local EVENTS = {
	"CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_CHANNEL", "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE",
	"CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
	"CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
	"CHAT_MSG_WHISPER", "CHAT_MSG_BN_WHISPER",
}

local phrases = {}          -- lowercase, plain

function DP.rebuildPhrases()
	phrases = {}
	local text = DP.db and DP.db.banPhrases or ""
	for line in string.gmatch(text .. "\n", "(.-)\n") do
		line = string.lower(strtrim(line))
		if line ~= "" then phrases[#phrases + 1] = line end
	end
end

local function isFriend(sender, guid)
	if not sender or sender == "" then return false end
	local name = string.match(sender, "^([^%-]+)") or sender
	-- character friends
	if C_FriendList and C_FriendList.IsFriend and guid then
		local ok, r = pcall(C_FriendList.IsFriend, guid); if ok and r then return true end
	end
	if C_FriendList and C_FriendList.GetFriendInfo then
		local ok, info = pcall(C_FriendList.GetFriendInfo, name); if ok and info then return true end
	end
	-- Battle.net friends (any game account of theirs)
	if guid and C_BattleNet and C_BattleNet.GetGameAccountInfoByGUID then
		local ok, acct = pcall(C_BattleNet.GetGameAccountInfoByGUID, guid)
		if ok and acct then return true end
	end
	if guid and BNGetGameAccountInfoByGUID then
		local ok, id = pcall(BNGetGameAccountInfoByGUID, guid); if ok and id then return true end
	end
	return false
end

local function shouldDrop(msg, sender, guid)
	if not DP.db or not DP.db.chatFilter then return false end
	if #phrases == 0 or type(msg) ~= "string" then return false end
	local lower = string.lower(msg)
	local hit = false
	for _, p in ipairs(phrases) do
		if string.find(lower, p, 1, true) then hit = true; break end
	end
	if not hit then return false end
	if isFriend(sender, guid) then return false end
	return true
end

-- args: self, event, msg, sender, lang, channel, target, flags, zoneID, chanNum, chanName, unused, lineID, guid
local function filter(_, _, msg, sender, _, _, _, _, _, _, _, _, _, guid)
	if shouldDrop(msg, sender, guid) then return true end
	return false
end

local applied = false
local function apply()
	DP.rebuildPhrases()
	if applied or not ChatFrame_AddMessageEventFilter then return end
	for _, e in ipairs(EVENTS) do ChatFrame_AddMessageEventFilter(e, filter) end
	applied = true
end

DP.register("chatFilter", { apply = apply })
