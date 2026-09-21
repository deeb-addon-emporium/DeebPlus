-- DeebPlus error catcher: Lua errors go to a quiet list instead of Blizzard's popup.
-- One short chat line per new error; /dp errors opens a window with a copyable text box.
-- Toggle: DP.db.errorCatcher (turning it on sets scriptErrors=0 so the popup stays away;
-- turning it off restores scriptErrors=1).
local DP = DeebPlus

local errors = {}          -- { msg=, stack=, count=, time= }
local seen = {}            -- msg -> index
local idx = 1

local win = CreateFrame("Frame", "DeebPlusErrors", UIParent, "BasicFrameTemplateWithInset")
win:SetSize(560, 340); win:SetPoint("CENTER"); win:SetFrameStrata("DIALOG")
win:SetMovable(true); win:EnableMouse(true); win:RegisterForDrag("LeftButton")
win:SetScript("OnDragStart", win.StartMoving); win:SetScript("OnDragStop", win.StopMovingOrSizing)
if win.TitleText then win.TitleText:SetText("DeebPlus errors") end
tinsert(UISpecialFrames, "DeebPlusErrors")
win:Hide()

local scroll = CreateFrame("ScrollFrame", "DeebPlusErrorsScroll", win, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 12, -32); scroll:SetPoint("BOTTOMRIGHT", -32, 40)
local box = CreateFrame("EditBox", "DeebPlusErrorsBox", scroll)
box:SetMultiLine(true); box:SetAutoFocus(false); box:SetFontObject(ChatFontNormal)
box:SetWidth(500); box:SetMaxLetters(0)
box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
box:SetScript("OnTextChanged", function(self, user) if user then self:SetText(self.current or "") end end)  -- read-only
scroll:SetScrollChild(box)

local counter = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
counter:SetPoint("BOTTOM", 0, 14)

local function render()
	local e = errors[idx]
	if not e then box.current = "no errors this session"; box:SetText(box.current); counter:SetText("0 / 0"); return end
	box.current = string.format("Message: %s\nTime: %s\nCount: %d\n\nStack:\n%s", e.msg, e.time, e.count, e.stack or "")
	box:SetText(box.current)
	counter:SetText(string.format("%d / %d", idx, #errors))
end

local function mk(text, x, fn)
	local b = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
	b:SetSize(80, 22); b:SetPoint("BOTTOMLEFT", x, 10); b:SetText(text); b:SetScript("OnClick", fn)
	return b
end
mk("Copy", 12, function() box:SetFocus(); box:HighlightText(); DP.msg("text selected - press Ctrl+C") end)
mk("<", 100, function() if idx > 1 then idx = idx - 1; render() end end)
mk(">", 186, function() if idx < #errors then idx = idx + 1; render() end end)
mk("Clear", 272, function() errors = {}; seen = {}; idx = 1; render() end)
mk("Reload UI", 460, function() ReloadUI() end)

local function catch(msg)
	msg = tostring(msg)
	local i = seen[msg]
	if i then
		errors[i].count = errors[i].count + 1
		errors[i].time = date("%H:%M:%S")
	else
		errors[#errors + 1] = { msg = msg, stack = debugstack(3, 12, 6), count = 1, time = date("%H:%M:%S") }
		seen[msg] = #errors
		idx = #errors
		local short = string.gsub(msg, "^Interface/AddOns/", "")
		if #short > 110 then short = string.sub(short, 1, 110) .. "..." end
		DP.msg("|cffff6060Lua error|r (" .. #errors .. "): " .. short .. "  - /dp errors")
	end
	if win:IsShown() then render() end
end

local installed, prevHandler = false, nil
local function apply()
	if not DP.db then return end
	if DP.db.errorCatcher then
		if not installed then
			prevHandler = geterrorhandler()
			seterrorhandler(function(m) pcall(catch, m) end)
			installed = true
		end
		pcall(SetCVar, "scriptErrors", "0")
	elseif installed then
		if prevHandler then seterrorhandler(prevHandler) end
		installed = false
		pcall(SetCVar, "scriptErrors", "1")
	end
end

-- "has been blocked from an action" popups: record which addon and which function
local blk = CreateFrame("Frame")
blk:RegisterEvent("ADDON_ACTION_BLOCKED")
blk:RegisterEvent("ADDON_ACTION_FORBIDDEN")
blk:SetScript("OnEvent", function(_, event, addon, func)
	pcall(catch, string.format("%s: %s called %s (protected)", event == "ADDON_ACTION_FORBIDDEN" and "FORBIDDEN" or "BLOCKED", tostring(addon), tostring(func)))
end)

DP.showErrors = function() render(); win:Show() end
DP.register("errors", { apply = apply })
