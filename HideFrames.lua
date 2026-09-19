-- DeebPlus: hide the beta "issue reporter" (and anything else you name) and keep it hidden.
-- Matches frame names by pattern, case-insensitive. Toggle: DP.db.hideIssueReporter
--   /dp frames <text>   list top-level frame names containing <text>, so a miss can be fixed
local DP = DeebPlus

local PATTERNS = { "issuereport", "bugreport", "reportissue", "betafeedback", "feedbackframe" }
local extra = {}                      -- DP.db.hideFrames, one name per line

local hooked = {}
local function tame(frame)
	if not frame or hooked[frame] then return end
	hooked[frame] = true
	pcall(frame.Hide, frame)
	if frame.HookScript then
		frame:HookScript("OnShow", function(self)
			if DP.db and DP.db.hideIssueReporter then self:Hide() end
		end)
	end
end

local function matches(name)
	local n = string.lower(name)
	for _, p in ipairs(PATTERNS) do if string.find(n, p, 1, true) then return true end end
	for _, p in ipairs(extra) do if p ~= "" and string.find(n, p, 1, true) then return true end end
	return false
end

local function sweep()
	if not DP.db or not DP.db.hideIssueReporter then return end
	extra = {}
	for line in string.gmatch((DP.db.hideFrames or "") .. "\n", "(.-)\n") do
		line = string.lower(strtrim(line)); if line ~= "" then extra[#extra + 1] = line end
	end
	local f = EnumerateFrames()
	while f do
		local name = f.GetName and f:GetName()
		if name and f:GetParent() == UIParent and matches(name) then tame(f) end
		f = EnumerateFrames(f)
	end
end

local ticker
local function apply()
	if not DP.db then return end
	if DP.db.hideIssueReporter then
		sweep()
		if not ticker then ticker = C_Timer.NewTicker(5, sweep) end   -- frames created late
	end
end

-- /dp frames <text>
DP.listFrames = function(text)
	text = string.lower(text or "")
	local n = 0
	local f = EnumerateFrames()
	while f do
		local name = f.GetName and f:GetName()
		if name and f:GetParent() == UIParent and string.find(string.lower(name), text, 1, true) then
			DP.msg(name .. (f:IsShown() and "  (shown)" or "")); n = n + 1
		end
		f = EnumerateFrames(f)
	end
	if n == 0 then DP.msg("no top-level frame named like '" .. text .. "'") end
end

DP.register("hideFrames", { apply = apply })
