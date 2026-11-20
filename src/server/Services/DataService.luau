-- DataService: loads/saves player data with DataStoreService and pushes a state
-- snapshot to each client whenever something changes.
-- In Studio, turn on "Enable Studio Access to API Services" to test saving;
-- without it the game still runs, it just does not save.

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)

local DataService = {}
local Services

local store = nil
local profiles = {} -- [player] = { Data = table, CanSave = bool, Dirty = bool }

local DEFAULT_DATA = {
	Money = 0,
	Bank = 0,
	Speed = Config.StartSpeed,
	Boots = 0,
	Pedestals = Config.StartPedestals,
	Rebirths = 0,
	Items = {}, -- ["slot"] = { id = string, mut = string?, hatchAt = number?, hatched = bool? }
	Index = {}, -- [meteorlingId] = true
	LuckUntil = 0,
	Receipts = {},
	LastOnline = 0,
	Stats = { Stolen = 0, Hatched = 0, Rebirths = 0 },
}

local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value do
		copy[k] = deepCopy(v)
	end
	return copy
end

local function reconcile(data, template)
	for key, value in template do
		if data[key] == nil then
			data[key] = deepCopy(value)
		elseif type(value) == "table" and type(data[key]) == "table" and next(value) ~= nil then
			reconcile(data[key], value)
		end
	end
	return data
end

local function keyFor(player)
	return "player_" .. player.UserId
end

function DataService.Init(services)
	Services = services
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.DataStoreName)
	end)
	if ok then
		store = result
	else
		warn("[DataService] DataStore unavailable, progress will not save:", result)
	end
end

function DataService.Start()
	-- Autosave
	task.spawn(function()
		while true do
			task.wait(Config.AutosaveInterval)
			for player in profiles do
				task.spawn(DataService.Save, player)
			end
		end
	end)

	-- Push snapshots to clients
	task.spawn(function()
		while true do
			task.wait(0.25)
			for player, profile in profiles do
				if profile.Dirty and player.Parent then
					profile.Dirty = false
					DataService.SendSnapshot(player)
				end
			end
		end
	end)
end

function DataService.Load(player)
	local data = nil
	local loaded = false
	if store then
		for attempt = 1, 3 do
			local ok, result = pcall(function()
				return store:GetAsync(keyFor(player))
			end)
			if ok then
				data = result
				loaded = true
				break
			end
			warn(string.format("[DataService] Load attempt %d failed for %s: %s", attempt, player.Name, tostring(result)))
			task.wait(1.5)
		end
	end

	if type(data) ~= "table" then
		data = {}
	end
	reconcile(data, DEFAULT_DATA)

	local profile = {
		Data = data,
		CanSave = loaded,
		Dirty = true,
	}
	profiles[player] = profile
	return profile
end

function DataService.Get(player)
	local profile = profiles[player]
	if profile then
		return profile.Data
	end
	return nil
end

function DataService.MarkDirty(player)
	local profile = profiles[player]
	if profile then
		profile.Dirty = true
	end
end

function DataService.Save(player)
	local profile = profiles[player]
	if not profile or not profile.CanSave or not store then
		return false
	end
	profile.Data.LastOnline = os.time()
	local ok, err = pcall(function()
		store:SetAsync(keyFor(player), profile.Data, { player.UserId })
	end)
	if not ok then
		warn("[DataService] Save failed for " .. player.Name .. ": " .. tostring(err))
	end
	return ok
end

function DataService.Remove(player)
	profiles[player] = nil
end

function DataService.AllPlayers()
	local list = {}
	for player in profiles do
		table.insert(list, player)
	end
	return list
end

function DataService.SetupLeaderstats(player)
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"
	local cash = Instance.new("StringValue")
	cash.Name = "Cash"
	cash.Value = "$0"
	cash.Parent = folder
	local speed = Instance.new("IntValue")
	speed.Name = "Speed"
	speed.Parent = folder
	local rebirths = Instance.new("IntValue")
	rebirths.Name = "Rebirths"
	rebirths.Parent = folder
	folder.Parent = player
end

function DataService.SendSnapshot(player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	local PlayerService = Services.Player
	local PlotService = Services.Plot

	local bootsCost = nil
	if data.Boots < Config.Boots.MaxLevel then
		bootsCost = Util.BootsCost(data.Boots)
	end
	local pedestalCost = nil
	if data.Pedestals < Config.MaxBuyablePedestals then
		pedestalCost = Util.PedestalCost(data.Pedestals)
	end

	local passes = {}
	for key in Config.GamePasses do
		passes[key] = PlayerService.HasPass(player, key)
	end

	local snapshot = {
		Money = data.Money,
		Bank = data.Bank,
		Income = PlotService.GetIncome(player),
		Speed = math.floor(data.Speed),
		MaxSpeed = Config.MaxSpeed,
		PadRate = PlayerService.GetPadRate(player),
		Boots = data.Boots,
		BootsMax = Config.Boots.MaxLevel,
		BootsCost = bootsCost,
		Pedestals = data.Pedestals,
		PedestalsTotal = PlayerService.GetPedestalCount(player),
		PedestalCost = pedestalCost,
		MaxBuyable = Config.MaxBuyablePedestals,
		Used = Util.CountKeys(data.Items),
		Rebirths = data.Rebirths,
		RebirthCost = Util.RebirthCost(data.Rebirths),
		Mult = PlayerService.GetIncomeMultiplier(player),
		RebirthMult = Util.RebirthMultiplier(data.Rebirths),
		NextRebirthMult = Util.RebirthMultiplier(data.Rebirths + 1),
		Index = data.Index,
		IndexCount = Util.CountKeys(data.Index),
		Passes = passes,
		LuckUntil = data.LuckUntil,
		Luck = PlayerService.GetLuck(player),
		ShowerUntil = Services.Event.GetShowerUntil(),
	}
	Remotes.Sync:FireClient(player, snapshot)

	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		leaderstats.Cash.Value = Util.FormatMoney(data.Money)
		leaderstats.Speed.Value = math.floor(data.Speed)
		leaderstats.Rebirths.Value = data.Rebirths
	end
end

function DataService.SaveAll()
	local pending = 0
	for player in profiles do
		pending += 1
		task.spawn(function()
			DataService.Save(player)
			pending -= 1
		end)
	end
	local started = os.clock()
	while pending > 0 and os.clock() - started < 25 do
		task.wait(0.1)
	end
end

return DataService
