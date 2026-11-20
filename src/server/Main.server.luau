-- Steal a Meteor: server entry point.
-- Builds the map, starts every service and handles players joining/leaving.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)

local Modules = script.Parent:WaitForChild("Modules")
local ServiceFolder = script.Parent:WaitForChild("Services")

local MapBuilder = require(Modules.MapBuilder)

local Services = {}
Services.Map = MapBuilder.Build()

function Services.Notify(player, text, color)
	Remotes.Notify:FireClient(player, text, color)
end

function Services.NotifyAll(text, color)
	Remotes.Notify:FireAllClients(text, color)
end

local ORDER = { "Data", "Player", "Plot", "Meteor", "Combat", "Shop", "Event" }
local FILES = {
	Data = "DataService",
	Player = "PlayerService",
	Plot = "PlotService",
	Meteor = "MeteorService",
	Combat = "CombatService",
	Shop = "ShopService",
	Event = "EventService",
}

for _, name in ORDER do
	Services[name] = require(ServiceFolder:WaitForChild(FILES[name]))
end
for _, name in ORDER do
	Services[name].Init(Services)
end
for _, name in ORDER do
	Services[name].Start()
end

local function giveOfflineEarnings(player, data)
	if data.LastOnline <= 0 then
		return
	end
	local away = math.min(os.time() - data.LastOnline, Config.OfflineCapSeconds)
	if away < 60 then
		return
	end
	local income = Services.Plot.GetIncome(player)
	local earned = math.floor(income * away * Config.OfflineRate)
	if earned > 0 then
		data.Bank += earned
		Services.Notify(
			player,
			"Welcome back! Your Meteorlings earned " .. Util.FormatMoney(earned) .. " while you were away.",
			Color3.fromRGB(120, 255, 160)
		)
	end
end

local function onPlayerAdded(player)
	local profile = Services.Data.Load(player)
	if not player.Parent then
		Services.Data.Remove(player)
		return
	end
	if not profile.CanSave then
		Services.Notify(player, "Saving is unavailable right now. Progress in this session will not be saved.", Color3.fromRGB(255, 160, 80))
	end

	Services.Player.Setup(player)
	Services.Plot.Assign(player)
	giveOfflineEarnings(player, profile.Data)
	Services.Data.MarkDirty(player)

	task.delay(2, function()
		if player.Parent then
			Services.Notify(player, "Grab meteors, bring them home, bonk thieves!", Color3.fromRGB(255, 220, 120))
		end
	end)
end

local function onPlayerRemoving(player)
	Services.Meteor.OnPlayerRemoving(player)
	Services.Plot.Release(player)
	Services.Data.Save(player)
	Services.Data.Remove(player)
	Services.Player.Cleanup(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

game:BindToClose(function()
	Services.Data.SaveAll()
end)
