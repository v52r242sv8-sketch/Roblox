-- EventService: server-wide moments that make the whole lobby scream.
--   Meteor Shower: 3x meteors, meteors can already be mutated
--   Golden Comet : one huge mutated meteor with a sky beam, everyone races for it

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)

local EventService = {}
local Services

local showerUntil = 0
local skyToken = 0

local COMET_WEIGHTS = { Epic = 40, Legendary = 35, Mythic = 18, Cosmic = 6, Secret = 1 }

local function tintSky(on)
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if not atmosphere then
		return
	end
	local goal = { Color = Color3.fromRGB(200, 170, 255), Decay = Color3.fromRGB(110, 80, 160) }
	if on then
		goal = { Color = Color3.fromRGB(255, 150, 90), Decay = Color3.fromRGB(200, 60, 60) }
	end
	TweenService:Create(atmosphere, TweenInfo.new(3), goal):Play()
end

function EventService.Init(services)
	Services = services
end

function EventService.IsShower()
	return os.time() < showerUntil
end

function EventService.GetShowerUntil()
	return showerUntil
end

function EventService.StartShower(byName)
	local now = os.time()
	showerUntil = math.max(now, showerUntil) + Config.Events.ShowerDuration
	skyToken += 1
	local token = skyToken
	tintSky(true)

	local sub = "3x meteors • mutated meteors • 2x luck"
	if byName then
		sub = byName .. " summoned it! " .. sub
	end
	Remotes.Banner:FireAllClients({
		Title = "☄️ METEOR SHOWER! ☄️",
		Subtitle = sub,
		Color = Color3.fromRGB(255, 140, 60),
		EndsAt = showerUntil,
	})
	for _, player in Players:GetPlayers() do
		Services.Data.MarkDirty(player)
	end

	task.delay(showerUntil - now + 0.5, function()
		if token == skyToken and not EventService.IsShower() then
			tintSky(false)
		end
	end)
end

function EventService.SpawnComet(byName)
	local zoneIndex = math.random(2, #Config.Zones)
	local zone = Config.Zones[zoneIndex]
	local rarity = Util.WeightedPick(COMET_WEIGHTS)
	local mutation = "Golden"
	if math.random() < 0.15 then
		mutation = "Rainbow"
	end
	local warningTime = 10

	Services.Meteor.SpawnMeteor(zoneIndex, {
		Rarity = rarity,
		Mutation = mutation,
		Special = true,
		Beacon = true,
		BeaconColor = Config.MutationByName[mutation].Color,
		WarningTime = warningTime,
		Lifetime = 90,
		Announce = true,
	})

	local sub = "A " .. string.upper(mutation) .. " " .. rarity .. " comet lands in " .. zone.Name .. "! Follow the light!"
	if byName then
		sub = byName .. " summoned it! " .. sub
	end
	Remotes.Banner:FireAllClients({
		Title = "🌟 " .. string.upper(mutation) .. " COMET INCOMING! 🌟",
		Subtitle = sub,
		Color = Config.MutationByName[mutation].Color,
		EndsAt = os.time() + warningTime,
	})
end

function EventService.Start()
	task.spawn(function()
		while true do
			task.wait(math.random(Config.Events.MinGap, Config.Events.MaxGap))
			if #Players:GetPlayers() > 0 then
				if math.random() < Config.Events.CometChance then
					EventService.SpawnComet(nil)
				else
					EventService.StartShower(nil)
				end
			end
		end
	end)
end

return EventService
