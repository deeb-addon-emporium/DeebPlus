-- DeebPlus target kill XP: a small purple number right of the target's level on the target
-- frame, the XP one solo kill of it is worth. Vanilla formula; hidden at the level cap.
--   base = mobLevel*5 + 45; higher mob: base*(1 + 0.05*diff); lower mob: base*(1 - diff/ZD),
--   ZD = grey threshold for your level; elites x2. Hidden when it would be grey (0).
local DP = DeebPlus

local function zeroDiff(L)
	if L <= 7 then return 5 elseif L <= 9 then return 6 elseif L <= 11 then return 7
	elseif L <= 15 then return 8 elseif L <= 19 then return 9 elseif L <= 29 then return 11
	elseif L <= 39 then return 12 elseif L <= 44 then return 13 elseif L <= 49 then return 14
	elseif L <= 54 then return 15 elseif L <= 59 then return 16 else return 17 end
end

local function killXP(unit)
	local pl = UnitLevel("player")
	local ml = UnitLevel(unit)
	if type(ml) ~= "number" or (issecretvalue and issecretvalue(ml)) then return nil end
	if ml <= 0 then ml = pl + 10 end                     -- "??" boss level
	local base = ml * 5 + 45
	local xp
	if ml >= pl then xp = base * (1 + 0.05 * (ml - pl))
	else
		local zd = zeroDiff(pl)
		if pl - ml >= zd then return 0 end
		xp = base * (1 - (pl - ml) / zd)
	end
	local c = UnitClassification(unit)
	if c == "elite" or c == "rareelite" or c == "worldboss" then xp = xp * 2 end
	return math.floor(xp + 0.5)
end

local text
local function levelText()
	local tf = TargetFrame
	if not tf then return end
	local m = tf.TargetFrameContent and tf.TargetFrameContent.TargetFrameContentMain
	return (m and m.LevelText) or _G.TargetFrameTextureFrameLevelText or (tf.levelText)
end

local function refresh()
	if not text then
		local lt = levelText()
		if not lt then return end
		text = lt:GetParent():CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		text:SetPoint("LEFT", lt, "RIGHT", 3, 0)
		text:SetTextColor(0.75, 0.45, 1)
	end
	if not DP.db or not DP.db.targetXP then text:Hide(); return end
	local cap = GetMaxPlayerLevel and GetMaxPlayerLevel() or 60
	if (UnitLevel("player") or 0) >= cap then text:Hide(); return end
	if not UnitExists("target") or UnitIsPlayer("target") or not UnitCanAttack("player", "target") or UnitIsDeadOrGhost("target") then text:Hide(); return end
	local xp = killXP("target")
	if not xp or xp <= 0 then text:Hide(); return end
	text:SetText(tostring(xp) .. "xp")
	text:Show()
end

local f = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_TARGET_CHANGED", "PLAYER_LEVEL_UP", "UNIT_FACTION", "PLAYER_ENTERING_WORLD", "UNIT_CLASSIFICATION_CHANGED" }) do pcall(f.RegisterEvent, f, e) end
f:SetScript("OnEvent", function() C_Timer.After(0, function() pcall(refresh) end) end)
if TargetFrame_Update then hooksecurefunc("TargetFrame_Update", function() pcall(refresh) end) end

DP.register("targetXP", { apply = function() pcall(refresh) end })
