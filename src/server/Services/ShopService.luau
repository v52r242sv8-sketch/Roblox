-- ShopService: in-game cash purchases (boots, pedestals, rebirth) and Robux purchases.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)

local ShopService = {}
local Services

local lastRequest = {} -- [player] = os.clock()

local function result(ok, message)
	return { Ok = ok, Message = message }
end

local ACTIONS = {}

function ACTIONS.BuyBoots(player, data)
	if data.Boots >= Config.Boots.MaxLevel then
		return result(false, "Boots are maxed!")
	end
	local cost = Util.BootsCost(data.Boots)
	if data.Money < cost then
		return result(false, "Not enough cash!")
	end
	data.Money -= cost
	data.Boots += 1
	return result(true, "Speed Boots level " .. data.Boots .. "! Pad now gives +" .. Services.Player.GetPadRate(player) .. "/s")
end

function ACTIONS.BuyPedestal(player, data)
	if data.Pedestals >= Config.MaxBuyablePedestals then
		return result(false, "All pedestals unlocked!")
	end
	local cost = Util.PedestalCost(data.Pedestals)
	if data.Money < cost then
		return result(false, "Not enough cash!")
	end
	data.Money -= cost
	data.Pedestals += 1
	Services.Plot.RefreshPedestals(player)
	return result(true, "New pedestal unlocked!")
end

function ACTIONS.Rebirth(player, data)
	local cost = Util.RebirthCost(data.Rebirths)
	if data.Money < cost then
		return result(false, "You need " .. Util.FormatMoney(cost) .. " to rebirth!")
	end
	data.Money = 0
	data.Bank = 0
	data.Speed = Config.StartSpeed
	data.Boots = 0
	data.Rebirths += 1
	data.Stats.Rebirths += 1
	Services.Player.ApplyWalkSpeed(player)
	Services.NotifyAll(
		player.DisplayName .. " just rebirthed! (Rebirth " .. data.Rebirths .. ")",
		Color3.fromRGB(200, 140, 255)
	)
	Remotes.Effect:FireClient(player, "Rebirth")
	return result(true, "Rebirth complete! Income x" .. Util.RebirthMultiplier(data.Rebirths))
end

-- Robux products ---------------------------------------------------------------

local GRANTS = {}

function GRANTS.SpeedBoost(player, data)
	data.Speed = math.min(Config.MaxSpeed, data.Speed + 50)
	Services.Player.ApplyWalkSpeed(player)
end

function GRANTS.InstantHatch(player)
	Services.Plot.InstantHatch(player)
end

function GRANTS.Luck(_player, data)
	data.LuckUntil = math.max(os.time(), data.LuckUntil) + Config.LuckDuration
end

function GRANTS.MeteorShower(player)
	Services.Event.StartShower(player.DisplayName)
end

function GRANTS.GoldenComet(player)
	Services.Event.SpawnComet(player.DisplayName)
end

local function productKeyFor(productId)
	for key, product in Config.Products do
		if product.Id ~= 0 and product.Id == productId then
			return key
		end
	end
	return nil
end

local function processReceipt(receipt)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local data = Services.Data.Get(player)
	if not data then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if table.find(data.Receipts, receipt.PurchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local key = productKeyFor(receipt.ProductId)
	if not key or not GRANTS[key] then
		warn("[ShopService] Unknown product " .. tostring(receipt.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local ok, err = pcall(GRANTS[key], player, data)
	if not ok then
		warn("[ShopService] Grant failed: " .. tostring(err))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	table.insert(data.Receipts, receipt.PurchaseId)
	while #data.Receipts > 50 do
		table.remove(data.Receipts, 1)
	end
	Services.Data.MarkDirty(player)
	Services.Data.Save(player)
	Services.Notify(player, "Purchase complete: " .. Config.Products[key].Name, Color3.fromRGB(255, 220, 90))
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function ShopService.Init(services)
	Services = services
end

function ShopService.Start()
	MarketplaceService.ProcessReceipt = processReceipt

	Remotes.Request.OnServerInvoke = function(player, action)
		local now = os.clock()
		if now - (lastRequest[player] or 0) < 0.15 then
			return result(false, "Slow down!")
		end
		lastRequest[player] = now

		local handler = ACTIONS[action]
		local data = Services.Data.Get(player)
		if type(action) ~= "string" or not handler or not data then
			return result(false, "Unknown action")
		end
		local response = handler(player, data)
		Services.Data.MarkDirty(player)
		return response
	end

	Players.PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
	end)
end

return ShopService
