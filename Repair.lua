-- DeebPlus auto repair: at any merchant that can repair, repair everything and say what it cost.
-- Skips if you cannot afford it. Toggle: DP.db.autoRepair
local DP = DeebPlus

local function money(c)
	if GetMoneyString then return GetMoneyString(c) end
	return tostring(c) .. "c"
end

local function onMerchant()
	if not DP.db or not DP.db.autoRepair then return end
	if not CanMerchantRepair or not CanMerchantRepair() then return end
	local ok, cost, canRepair = pcall(GetRepairAllCost)
	if not ok or not canRepair or not cost or cost <= 0 then return end
	if GetMoney() < cost then
		DP.msg("repair costs " .. money(cost) .. " - not enough gold")
		return
	end
	local done = pcall(RepairAllItems)
	if done then DP.msg("repaired for " .. money(cost)) end
end

local f = CreateFrame("Frame")
f:RegisterEvent("MERCHANT_SHOW")
f:SetScript("OnEvent", function() C_Timer.After(0.2, function() pcall(onMerchant) end) end)

DP.register("repair", {})
