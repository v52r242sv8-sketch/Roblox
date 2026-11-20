-- Small helpers shared by server and client.

local Config = require(script.Parent.Config)

local Util = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

function Util.FormatNumber(value)
	local n = tonumber(value) or 0
	local negative = n < 0
	if negative then
		n = -n
	end

	local text
	if n < 1000 then
		text = tostring(math.floor(n))
	else
		local index = 1
		while n >= 1000 and index < #SUFFIXES do
			n = n / 1000
			index += 1
		end
		if n >= 100 then
			text = string.format("%.0f", n)
		elseif n >= 10 then
			text = string.format("%.1f", n)
		else
			text = string.format("%.2f", n)
		end
		if string.find(text, "%.") then
			text = string.gsub(text, "0+$", "")
			text = string.gsub(text, "%.$", "")
		end
		text ..= SUFFIXES[index]
	end

	if negative then
		return "-" .. text
	end
	return text
end

function Util.FormatMoney(value)
	return "$" .. Util.FormatNumber(value)
end

function Util.FormatTime(seconds)
	local s = math.max(0, math.floor(seconds))
	local h = math.floor(s / 3600)
	local m = math.floor((s % 3600) / 60)
	local sec = s % 60
	if h > 0 then
		return string.format("%dh %02dm", h, m)
	elseif m > 0 then
		return string.format("%dm %02ds", m, sec)
	end
	return string.format("%ds", sec)
end

function Util.GetRarity(name)
	return Config.Rarities[Config.RarityIndex[name] or 1]
end

function Util.GetMeteorling(id)
	return Config.MeteorlingById[id]
end

-- Income per second of one item, before player multipliers.
function Util.ItemIncome(item)
	local info = Config.MeteorlingById[item.id]
	if not info then
		return 0
	end
	local mult = 1
	if item.mut and Config.MutationByName[item.mut] then
		mult = Config.MutationByName[item.mut].Mult
	end
	return info.Income * mult
end

function Util.BootsCost(level)
	return math.floor(Config.Boots.BaseCost * Config.Boots.CostMult ^ level)
end

function Util.PedestalCost(owned)
	return math.floor(Config.PedestalBaseCost * Config.PedestalCostMult ^ (owned - Config.StartPedestals))
end

function Util.RebirthCost(rebirths)
	return math.floor(Config.Rebirth.BaseCost * Config.Rebirth.CostMult ^ rebirths)
end

function Util.RebirthMultiplier(rebirths)
	return 1 + Config.Rebirth.BonusPerRebirth * rebirths
end

-- Weighted random pick from a { key = weight } table.
function Util.WeightedPick(weights, rng)
	local total = 0
	for _, weight in weights do
		total += weight
	end
	local roll
	if rng then
		roll = rng:NextNumber() * total
	else
		roll = math.random() * total
	end
	local fallback = nil
	for key, weight in weights do
		fallback = key
		roll -= weight
		if roll <= 0 then
			return key
		end
	end
	return fallback
end

function Util.CountKeys(tbl)
	local count = 0
	for _ in tbl do
		count += 1
	end
	return count
end

return Util
