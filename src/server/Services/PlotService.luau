-- PlotService: player bases. Pedestals, hatching, income, the Speed/Collect/Lock pads
-- and stealing from other bases.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)

local Visuals = require(script.Parent.Parent.Modules.Visuals)

local PlotService = {}
local Services

local plots = {}
local plotOf = {} -- [player] = plot
local padTimers = {} -- [player] = accumulated whole-speed popups

local function slotKey(i)
	return tostring(i)
end

local function insidePlot(plot, position, margin)
	margin = margin or 0
	local rel = position - plot.Center
	return math.abs(rel.X) <= plot.HalfX + margin and math.abs(rel.Z) <= plot.HalfZ + margin and rel.Y < 30
end
PlotService.InsidePlot = insidePlot

local function onPad(pad, position)
	local rel = position - pad.Position
	return math.abs(rel.X) <= pad.Size.X / 2 + 0.5 and math.abs(rel.Z) <= pad.Size.Z / 2 + 0.5 and rel.Y < 8
end

local function setText(label, text)
	if label.Text ~= text then
		label.Text = text
	end
end

function PlotService.Init(services)
	Services = services
	plots = Services.Map.Plots
end

function PlotService.GetPlot(player)
	return plotOf[player]
end

function PlotService.IsLocked(plot)
	return os.time() < plot.LockedUntil
end

-- Ownership ------------------------------------------------------------------

function PlotService.Assign(player)
	for _, plot in plots do
		if plot.Owner == nil then
			plot.Owner = player
			plotOf[player] = plot
			plot.Model:SetAttribute("Owner", player.UserId)
			plot.SignLabel.Text = player.DisplayName .. "'s Base"
			plot.LockedUntil = 0
			plot.LockCooldownUntil = 0
			PlotService.RefreshPedestals(player)
			if player.Character then
				player.Character:PivotTo(plot.SpawnCFrame)
			end
			return plot
		end
	end
	warn("[PlotService] No free plot for " .. player.Name .. ". Set Max Players to " .. Config.PlotCount)
	Services.Notify(player, "All bases are taken! Try another server.", Color3.fromRGB(255, 90, 90))
	return nil
end

function PlotService.Release(player)
	local plot = plotOf[player]
	if not plot then
		return
	end
	plotOf[player] = nil
	for i = 1, Config.PhysicalPedestals do
		if plot.Rendered[i] then
			plot.Rendered[i]:Destroy()
			plot.Rendered[i] = nil
		end
		plot.Reserved[i] = nil
		local pedestal = plot.Pedestals[i]
		pedestal.LockGui.Enabled = false
		pedestal.Part.Color = Color3.fromRGB(230, 230, 240)
	end
	plot.Owner = nil
	plot.Model:SetAttribute("Owner", 0)
	plot.SignLabel.Text = "Empty Base"
	plot.BankLabel.Text = "💰 $0\nstep to collect"
	plot.LockedUntil = 0
	plot.Laser.Transparency = 1
	padTimers[player] = nil
end

-- Pedestals ------------------------------------------------------------------

function PlotService.RenderPedestal(plot, i)
	local old = plot.Rendered[i]
	if old then
		old:Destroy()
		plot.Rendered[i] = nil
	end
	local owner = plot.Owner
	if not owner then
		return
	end
	local data = Services.Data.Get(owner)
	if not data then
		return
	end
	local item = data.Items[slotKey(i)]
	if not item then
		return
	end

	local pedestal = plot.Pedestals[i].Part
	local top = pedestal.Position.Y + pedestal.Size.X / 2

	if plot.Reserved[i] then
		-- Someone is running away with this one
		local marker = Instance.new("Model")
		marker.Name = "StolenMarker"
		local anchor = Visuals.Make("Part", {
			Name = "Root",
			Size = Vector3.new(1, 1, 1),
			Position = Vector3.new(pedestal.Position.X, top + 2, pedestal.Position.Z),
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			Transparency = 1,
		}, marker)
		local gui = Visuals.Make("BillboardGui", {
			Size = UDim2.new(7, 0, 2, 0),
			LightInfluence = 0,
			MaxDistance = 150,
		}, anchor)
		Visuals.Label(gui, {
			Size = UDim2.fromScale(1, 1),
			Text = "🚨 STOLEN! 🚨",
			TextColor3 = Color3.fromRGB(255, 70, 70),
		})
		marker.Parent = plot.ItemsFolder
		plot.Rendered[i] = marker
		return
	end

	local model = Visuals.ItemModel(item, true)
	local root = model.PrimaryPart
	local position = Vector3.new(pedestal.Position.X, top + root.Size.Y / 2 + 0.3, pedestal.Position.Z)
	local cf = CFrame.lookAt(position, position + Vector3.new(0, 0, 1))
	model:PivotTo(cf) -- moves every part, even before the model is in the workspace
	root:SetAttribute("BaseCF", cf)
	if item.hatched then
		CollectionService:AddTag(root, "Bob")
	end

	local info = Config.MeteorlingById[item.id]
	local rarityIndex = Config.RarityIndex[info.Rarity]

	local sellPrice = PlotService.SellPrice(item)
	local sellPrompt = Instance.new("ProximityPrompt")
	sellPrompt.Name = "SellPrompt"
	sellPrompt.ActionText = "Sell " .. Util.FormatMoney(sellPrice)
	sellPrompt.ObjectText = item.id
	sellPrompt.HoldDuration = 1
	sellPrompt.MaxActivationDistance = 9
	sellPrompt.RequiresLineOfSight = false
	sellPrompt:SetAttribute("Kind", "Sell")
	sellPrompt.Parent = root

	local stealPrompt = Instance.new("ProximityPrompt")
	stealPrompt.Name = "StealPrompt"
	stealPrompt.ActionText = "Steal"
	stealPrompt.ObjectText = info.Rarity .. " " .. item.id
	stealPrompt.HoldDuration = 0.6 + rarityIndex * 0.2
	stealPrompt.MaxActivationDistance = 9
	stealPrompt.RequiresLineOfSight = false
	stealPrompt:SetAttribute("Kind", "Steal")
	stealPrompt.Parent = root

	sellPrompt.Triggered:Connect(function(player)
		if plot.Rendered[i] == model then
			PlotService.Sell(player, plot, i)
		end
	end)
	stealPrompt.Triggered:Connect(function(player)
		if plot.Rendered[i] == model then
			PlotService.StartSteal(player, plot, i)
		end
	end)

	model.Parent = plot.ItemsFolder
	plot.Rendered[i] = model
end

function PlotService.RefreshPedestals(player)
	local plot = plotOf[player]
	if not plot then
		return
	end
	local unlocked = Services.Player.GetPedestalCount(player)
	for i = 1, Config.PhysicalPedestals do
		local pedestal = plot.Pedestals[i]
		local isUnlocked = i <= unlocked
		pedestal.LockGui.Enabled = not isUnlocked
		if isUnlocked then
			pedestal.Part.Color = Color3.fromRGB(230, 230, 240)
			pedestal.Ring.Transparency = 0
		else
			pedestal.Part.Color = Color3.fromRGB(90, 90, 100)
			pedestal.Ring.Transparency = 0.8
		end
		PlotService.RenderPedestal(plot, i)
	end
end

function PlotService.SellPrice(item)
	local price = Util.ItemIncome(item) * Config.SellHatchedSeconds
	if not item.hatched then
		price *= Config.SellMeteorMult
	end
	return math.floor(price)
end

function PlotService.Sell(player, plot, i)
	if plot.Owner ~= player or plot.Reserved[i] then
		return
	end
	local data = Services.Data.Get(player)
	local item = data and data.Items[slotKey(i)]
	if not item then
		return
	end
	local price = PlotService.SellPrice(item)
	data.Items[slotKey(i)] = nil
	data.Money += price
	PlotService.RenderPedestal(plot, i)
	Services.Notify(player, "Sold " .. item.id .. " for " .. Util.FormatMoney(price), Color3.fromRGB(120, 255, 120))
	Remotes.Effect:FireClient(player, "Collect", price)
	Services.Data.MarkDirty(player)
end

function PlotService.FreeSlot(player)
	local plot = plotOf[player]
	local data = Services.Data.Get(player)
	if not plot or not data then
		return nil
	end
	for i = 1, Services.Player.GetPedestalCount(player) do
		if data.Items[slotKey(i)] == nil and not plot.Reserved[i] then
			return i
		end
	end
	return nil
end

local function discover(player, data, item)
	if data.Index[item.id] then
		return
	end
	data.Index[item.id] = true
	local info = Config.MeteorlingById[item.id]
	Remotes.Effect:FireClient(player, "Discovered", item.id, info.Rarity)
	Services.Notify(
		player,
		"NEW Index entry: " .. item.id .. "! (+" .. math.floor(Config.IndexBonusPerEntry * 100) .. "% income)",
		Util.GetRarity(info.Rarity).Color
	)
end

-- Called by MeteorService when a carrying player walks into their own base.
function PlotService.Deposit(player, carry)
	local plot = plotOf[player]
	local data = Services.Data.Get(player)
	if not plot or not data then
		return false
	end
	local slot = PlotService.FreeSlot(player)
	if not slot then
		return false
	end

	local item = carry.Item
	if carry.StolenFrom then
		local owner = carry.StolenFrom
		local ownerPlot = carry.Plot
		local ownerData = Services.Data.Get(owner)
		if not ownerData or ownerPlot.Owner ~= owner then
			return false
		end
		ownerData.Items[slotKey(carry.Pedestal)] = nil
		ownerPlot.Reserved[carry.Pedestal] = nil
		PlotService.RenderPedestal(ownerPlot, carry.Pedestal)
		Services.Data.MarkDirty(owner)
		data.Stats.Stolen += 1
		Services.Notify(owner, player.DisplayName .. " stole your " .. item.id .. "!", Color3.fromRGB(255, 80, 80))
		Services.Notify(player, "You stole " .. item.id .. "!", Color3.fromRGB(255, 200, 80))
	end

	if not item.hatched and not item.hatchAt then
		local rarity = Util.GetRarity(Config.MeteorlingById[item.id].Rarity)
		item.hatchAt = os.time() + rarity.HatchTime
	end
	data.Items[slotKey(slot)] = item
	if item.hatched then
		discover(player, data, item)
	end
	PlotService.RenderPedestal(plot, slot)
	Remotes.Effect:FireClient(player, "Deposit")
	Services.Data.MarkDirty(player)
	return true
end

-- Steal flow ---------------------------------------------------------------

function PlotService.StartSteal(thief, plot, i)
	local owner = plot.Owner
	if not owner or owner == thief or plot.Reserved[i] then
		return
	end
	if not plotOf[thief] then
		return
	end
	if Services.Meteor.GetCarry(thief) then
		Services.Notify(thief, "Your hands are full!", Color3.fromRGB(255, 180, 80))
		return
	end
	if PlotService.IsLocked(plot) then
		Services.Notify(thief, "This base is locked!", Color3.fromRGB(255, 90, 90))
		return
	end
	local root = Services.Player.GetAliveParts(thief)
	if not root then
		return
	end
	local data = Services.Data.Get(owner)
	local item = data and data.Items[slotKey(i)]
	if not item then
		return
	end

	plot.Reserved[i] = thief
	PlotService.RenderPedestal(plot, i)
	local ok = Services.Meteor.Carry(thief, table.clone(item), {
		StolenFrom = owner,
		Pedestal = i,
		Plot = plot,
	})
	if not ok then
		plot.Reserved[i] = nil
		PlotService.RenderPedestal(plot, i)
		return
	end
	Services.Notify(owner, thief.DisplayName .. " is stealing your " .. item.id .. "! Bonk them!", Color3.fromRGB(255, 60, 60))
	Remotes.Effect:FireClient(owner, "Alarm")
end

-- The thief dropped the item (bonked, died, left): it flies back home.
function PlotService.ReturnStolen(carry)
	local plot = carry.Plot
	if not plot or plot.Owner ~= carry.StolenFrom then
		return
	end
	plot.Reserved[carry.Pedestal] = nil
	PlotService.RenderPedestal(plot, carry.Pedestal)
	Services.Notify(carry.StolenFrom, "Your " .. carry.Item.id .. " is back home!", Color3.fromRGB(120, 220, 255))
end

-- Hatching & income --------------------------------------------------------

local function rollMutation(luck)
	local roll = math.random()
	for _, mutation in Config.Mutations do
		if roll < mutation.Chance * luck then
			return mutation.Name
		end
	end
	return nil
end
PlotService.RollMutation = rollMutation

function PlotService.InstantHatch(player)
	local data = Services.Data.Get(player)
	if not data then
		return
	end
	local now = os.time()
	for _, item in data.Items do
		if not item.hatched then
			item.hatchAt = now
		end
	end
end

function PlotService.GetIncome(player)
	local data = Services.Data.Get(player)
	local plot = plotOf[player]
	if not data then
		return 0
	end
	local total = 0
	for key, item in data.Items do
		local reserved = plot and plot.Reserved[tonumber(key)]
		if item.hatched and not reserved then
			total += Util.ItemIncome(item)
		end
	end
	return total * Services.Player.GetIncomeMultiplier(player)
end

local function hatchTick(player, plot, data)
	local now = os.time()
	for key, item in data.Items do
		local i = tonumber(key)
		if not item.hatched and item.hatchAt and item.hatchAt <= now and not plot.Reserved[i] then
			item.hatched = true
			if not item.mut then
				item.mut = rollMutation(Services.Player.GetLuck(player))
			end
			data.Stats.Hatched += 1
			local info = Config.MeteorlingById[item.id]
			local text = "Hatched: " .. item.id .. " (" .. info.Rarity .. ")"
			if item.mut then
				text = "Hatched: " .. string.upper(item.mut) .. " " .. item.id .. "!"
			end
			Services.Notify(player, text, Util.GetRarity(info.Rarity).Color)
			Remotes.Effect:FireClient(player, "Hatch", item.id, info.Rarity, item.mut)
			discover(player, data, item)
			PlotService.RenderPedestal(plot, i)
		end
	end
end

local function incomeTick(player, plot, data)
	local income = PlotService.GetIncome(player)
	if income > 0 then
		if Services.Player.HasPass(player, "AutoCollect") then
			data.Money += income
		else
			data.Bank += income
		end
	end
	setText(plot.BankLabel, "💰 " .. Util.FormatMoney(data.Bank) .. "\nstep to collect")
	Services.Data.MarkDirty(player)
end

local function padTick(player, plot, data, dt)
	local root = Services.Player.GetAliveParts(player)
	local now = os.time()

	if root then
		local position = root.Position

		-- Speed pad: +speed every second
		if onPad(plot.SpeedPad, position) and data.Speed < Config.MaxSpeed then
			local before = math.floor(data.Speed)
			data.Speed = math.min(Config.MaxSpeed, data.Speed + Services.Player.GetPadRate(player) * dt)
			local after = math.floor(data.Speed)
			if after > before then
				padTimers[player] = (padTimers[player] or 0) + (after - before)
				Services.Player.ApplyWalkSpeed(player)
				Services.Data.MarkDirty(player)
			end
		end

		-- Collect pad
		if onPad(plot.CollectPad, position) and data.Bank >= 1 then
			local amount = data.Bank
			data.Money += amount
			data.Bank = 0
			setText(plot.BankLabel, "💰 $0\nstep to collect")
			Remotes.Effect:FireClient(player, "Collect", amount)
			Services.Data.MarkDirty(player)
		end

		-- Lock pad
		if onPad(plot.LockPad, position) and now >= plot.LockCooldownUntil then
			local duration = Config.Lock.Duration
			if Services.Player.HasPass(player, "VIP") then
				duration = Config.Lock.VipDuration
			end
			plot.LockedUntil = now + duration
			plot.LockCooldownUntil = plot.LockedUntil + Config.Lock.Cooldown
			Services.Notify(player, "Base locked for " .. duration .. "s!", Color3.fromRGB(255, 120, 120))
		end
	end

	-- Laser gate + lock label
	local locked = now < plot.LockedUntil
	if locked then
		plot.Laser.Transparency = 0.35
		setText(plot.LockLabel, "🔒 LOCKED " .. (plot.LockedUntil - now) .. "s")
		for _, other in Players:GetPlayers() do
			if other ~= player then
				local otherRoot = Services.Player.GetAliveParts(other)
				if otherRoot and insidePlot(plot, otherRoot.Position, 0) then
					local outside = Vector3.new(otherRoot.Position.X, otherRoot.Position.Y + 1, plot.Center.Z + plot.HalfZ + 7)
					otherRoot.CFrame = CFrame.new(outside) * otherRoot.CFrame.Rotation
					Services.Notify(other, "Laser gate! This base is locked.", Color3.fromRGB(255, 90, 90))
				end
			end
		end
	else
		plot.Laser.Transparency = 1
		if now < plot.LockCooldownUntil then
			setText(plot.LockLabel, "⏳ " .. (plot.LockCooldownUntil - now) .. "s")
		else
			setText(plot.LockLabel, "🔒 LOCK BASE")
		end
	end
end

function PlotService.Start()
	-- 1 second: hatching + income + speed popups
	task.spawn(function()
		while true do
			task.wait(1)
			for player, plot in plotOf do
				local data = Services.Data.Get(player)
				if data and player.Parent then
					hatchTick(player, plot, data)
					incomeTick(player, plot, data)
					local gained = padTimers[player]
					if gained and gained > 0 then
						padTimers[player] = 0
						Remotes.Effect:FireClient(player, "Speed", gained)
					end
				end
			end
		end
	end)

	-- Fast loop: pads and lasers
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < 0.2 then
			return
		end
		local step = accumulator
		accumulator = 0
		for player, plot in plotOf do
			local data = Services.Data.Get(player)
			if data and player.Parent then
				padTick(player, plot, data, step)
			end
		end
	end)
end

return PlotService
