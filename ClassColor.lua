-- DeebPlus class-coloured health bars on the default unit frames (player, target, focus,
-- target-of-target, party, and the compact/raid-style frames via Blizzard's own CVar).
-- Only players get coloured; NPCs keep Blizzard's colour. Toggle: DP.db.classColorHP
local DP = DeebPlus

local function classColor(unit)
	if not unit or not UnitExists(unit) or not UnitIsPlayer(unit) then return nil end
	local _, class = UnitClass(unit)
	if not class then return nil end
	local c
	if C_ClassColor and C_ClassColor.GetClassColor then c = C_ClassColor.GetClassColor(class) end
	c = c or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]) or (CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[class])
	if not c then return nil end
	return c.r, c.g, c.b
end

local function paint(bar, unit)
	if not bar or type(bar.SetStatusBarColor) ~= "function" then return end
	if not DP.db or not DP.db.classColorHP then return end
	unit = unit or bar.unit
	local r, g, b = classColor(unit)
	if not r then return end
	-- modern bars ship a coloured texture; desaturate so our tint reads true
	if type(bar.SetStatusBarDesaturated) == "function" then pcall(bar.SetStatusBarDesaturated, bar, true) end
	local tex = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
	if tex and tex.SetDesaturated then pcall(tex.SetDesaturated, tex, true) end
	bar:SetStatusBarColor(r, g, b)
end

-- every default health bar we know how to find, old and new layouts
local function healthBars()
	local out = {}
	local function add(bar, unit) if bar then out[#out + 1] = { bar = bar, unit = unit } end end
	local function content(frame, main)
		local c = frame and frame[frame:GetName() .. "Content"]
		local m = c and c[frame:GetName() .. "ContentMain"]
		return m and m.HealthBarsContainer and m.HealthBarsContainer.HealthBar
	end
	add(content(PlayerFrame) or PlayerFrameHealthBar or (PlayerFrame and PlayerFrame.healthbar), "player")
	add(content(TargetFrame) or TargetFrameHealthBar or (TargetFrame and TargetFrame.healthbar), "target")
	add(content(FocusFrame) or FocusFrameHealthBar or (FocusFrame and FocusFrame.healthbar), "focus")
	add(TargetFrameToT and (TargetFrameToT.HealthBar or TargetFrameToT.healthbar or _G.TargetFrameToTHealthBar), "targettarget")
	for i = 1, 4 do
		local pf = _G["PartyMemberFrame" .. i] or (PartyFrame and PartyFrame.MemberFrames and PartyFrame.MemberFrames[i])
		add(pf and (pf.HealthBarContainer and pf.HealthBarContainer.HealthBar or pf.healthbar or _G["PartyMemberFrame" .. i .. "HealthBar"]), "party" .. i)
	end
	return out
end

local function repaintAll()
	for _, e in ipairs(healthBars()) do paint(e.bar, e.unit) end
end

local hooked = false
local function apply()
	if not DP.db then return end
	-- raid-style / compact frames: Blizzard does it natively behind this CVar
	pcall(SetCVar, "raidFramesDisplayClassColor", DP.db.classColorHP and "1" or "0")
	if DP.db.classColorHP then repaintAll() end
	if hooked then return end
	hooked = true
	if type(UnitFrameHealthBar_Update) == "function" then
		hooksecurefunc("UnitFrameHealthBar_Update", function(bar, unit) paint(bar, unit) end)
	end
	if type(HealthBar_OnValueChanged) == "function" then
		hooksecurefunc("HealthBar_OnValueChanged", function(bar) paint(bar, bar and bar.unit) end)
	end
	if type(UnitFrameHealthBar_OnValueChanged) == "function" then
		hooksecurefunc("UnitFrameHealthBar_OnValueChanged", function(bar) paint(bar, bar and bar.unit) end)
	end
	if type(TargetFrame_Update) == "function" then
		hooksecurefunc("TargetFrame_Update", function() repaintAll() end)
	end
	local f = CreateFrame("Frame")
	for _, ev in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "GROUP_ROSTER_UPDATE", "UNIT_TARGET", "UNIT_HEALTH", "UNIT_MAXHEALTH", "PORTRAITS_UPDATED" }) do
		pcall(f.RegisterEvent, f, ev)
	end
	f:SetScript("OnEvent", function() if DP.db.classColorHP then repaintAll() end end)
end

DP.register("classColor", { apply = apply })
