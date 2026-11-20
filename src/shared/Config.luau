-- Config: every balance number for Steal a Meteor lives here.
-- Change values here instead of hunting through the scripts.

local Config = {}

Config.GameName = "Steal a Meteor"
Config.DataStoreName = "StealAMeteor_v1"
Config.AutosaveInterval = 90

-- Speed ("+1 speed every second" on your Speed Pad)
Config.StartSpeed = 16
Config.MaxSpeed = 250
Config.PadBaseRate = 1 -- speed per second while standing on your own Speed Pad

-- Speed Boots upgrade: each level adds +1 speed/sec on the pad
Config.Boots = {
	MaxLevel = 12,
	BaseCost = 400,
	CostMult = 3,
}

-- Pedestals (slots on your base)
Config.PhysicalPedestals = 16 -- pedestals that exist on every plot
Config.StartPedestals = 6
Config.MaxBuyablePedestals = 14 -- VIP unlocks the last 2
Config.VipBonusPedestals = 2
Config.PedestalBaseCost = 750
Config.PedestalCostMult = 2.6

-- Rebirth: resets cash, speed and boots; keeps your Meteorlings and Index
Config.Rebirth = {
	BaseCost = 150000,
	CostMult = 6,
	BonusPerRebirth = 0.5, -- +50% income per rebirth
}

-- Index: each discovered Meteorling gives a permanent income bonus
Config.IndexBonusPerEntry = 0.02

-- Offline earnings
Config.OfflineCapSeconds = 2 * 60 * 60
Config.OfflineRate = 0.25

-- Selling
Config.SellHatchedSeconds = 20 -- sell price = income/sec * this
Config.SellMeteorMult = 0.25 -- unhatched meteors sell for less

-- Base lock (laser gate)
Config.Lock = {
	Duration = 45,
	VipDuration = 60,
	Cooldown = 60,
}

-- Hammer ("Bonk")
Config.Bonk = {
	Range = 9,
	BigRange = 14,
	Cooldown = 1.2,
	BigCooldown = 0.8,
	Knockback = 55,
	StunTime = 0.9,
}

-- Rarities, from worst to best
Config.Rarities = {
	{ Name = "Common", Color = Color3.fromRGB(205, 205, 205), HatchTime = 10, Weight = 0.05, Size = 2.6, GrabTime = 0.25 },
	{ Name = "Uncommon", Color = Color3.fromRGB(85, 220, 110), HatchTime = 20, Weight = 0.08, Size = 3.0, GrabTime = 0.3 },
	{ Name = "Rare", Color = Color3.fromRGB(70, 150, 255), HatchTime = 40, Weight = 0.12, Size = 3.5, GrabTime = 0.4 },
	{ Name = "Epic", Color = Color3.fromRGB(170, 85, 255), HatchTime = 75, Weight = 0.17, Size = 4.0, GrabTime = 0.5 },
	{ Name = "Legendary", Color = Color3.fromRGB(255, 170, 30), HatchTime = 150, Weight = 0.22, Size = 4.8, GrabTime = 0.7 },
	{ Name = "Mythic", Color = Color3.fromRGB(255, 60, 110), HatchTime = 300, Weight = 0.28, Size = 5.6, GrabTime = 0.9 },
	{ Name = "Cosmic", Color = Color3.fromRGB(0, 240, 255), HatchTime = 600, Weight = 0.35, Size = 6.6, GrabTime = 1.2 },
	{ Name = "Secret", Color = Color3.fromRGB(20, 20, 30), HatchTime = 900, Weight = 0.42, Size = 7.8, GrabTime = 1.5 },
}

Config.RarityIndex = {}
for i, rarity in Config.Rarities do
	Config.RarityIndex[rarity.Name] = i
end

-- Mutations are rolled when a meteor hatches (luck increases the chance).
-- Listed rarest first: the roll checks them in this order.
Config.Mutations = {
	{ Name = "Void", Mult = 10, Chance = 0.002, Color = Color3.fromRGB(110, 0, 200) },
	{ Name = "Rainbow", Mult = 5, Chance = 0.01, Color = Color3.fromRGB(255, 90, 200) },
	{ Name = "Golden", Mult = 2, Chance = 0.04, Color = Color3.fromRGB(255, 205, 40) },
}

Config.MutationByName = {}
for _, mutation in Config.Mutations do
	Config.MutationByName[mutation.Name] = mutation
end

-- Meteorlings: the creatures that hatch out of meteors.
-- Feature controls the little model detail (Ears, Horns, Wings, Antenna, Crown, Fins).
Config.Meteorlings = {
	{ Id = "Pebblit", Rarity = "Common", Income = 2, Color = Color3.fromRGB(150, 140, 130), Feature = "Ears" },
	{ Id = "Dustbun", Rarity = "Common", Income = 3, Color = Color3.fromRGB(220, 200, 170), Feature = "Ears" },
	{ Id = "Rocklet", Rarity = "Common", Income = 4, Color = Color3.fromRGB(110, 110, 120), Feature = "Horns" },

	{ Id = "Glowmite", Rarity = "Uncommon", Income = 8, Color = Color3.fromRGB(140, 255, 120), Feature = "Antenna" },
	{ Id = "Moonsnail", Rarity = "Uncommon", Income = 11, Color = Color3.fromRGB(200, 220, 255), Feature = "Antenna" },
	{ Id = "Fizzlefly", Rarity = "Uncommon", Income = 14, Color = Color3.fromRGB(255, 240, 120), Feature = "Wings" },

	{ Id = "Craterpup", Rarity = "Rare", Income = 35, Color = Color3.fromRGB(180, 120, 80), Feature = "Ears" },
	{ Id = "Sparkat", Rarity = "Rare", Income = 45, Color = Color3.fromRGB(90, 170, 255), Feature = "Ears" },
	{ Id = "Cometoad", Rarity = "Rare", Income = 60, Color = Color3.fromRGB(60, 200, 160), Feature = "Antenna" },

	{ Id = "Novabun", Rarity = "Epic", Income = 160, Color = Color3.fromRGB(255, 150, 220), Feature = "Ears" },
	{ Id = "Lunamoth", Rarity = "Epic", Income = 210, Color = Color3.fromRGB(190, 160, 255), Feature = "Wings" },
	{ Id = "Orbitron", Rarity = "Epic", Income = 275, Color = Color3.fromRGB(120, 120, 255), Feature = "Antenna" },

	{ Id = "Quasarfox", Rarity = "Legendary", Income = 900, Color = Color3.fromRGB(255, 130, 40), Feature = "Ears" },
	{ Id = "Solflare Drake", Rarity = "Legendary", Income = 1200, Color = Color3.fromRGB(255, 90, 30), Feature = "Wings" },
	{ Id = "Nebulynx", Rarity = "Legendary", Income = 1600, Color = Color3.fromRGB(150, 60, 255), Feature = "Horns" },

	{ Id = "Eclipsoid", Rarity = "Mythic", Income = 6000, Color = Color3.fromRGB(40, 30, 60), Feature = "Crown" },
	{ Id = "Starwhale", Rarity = "Mythic", Income = 8500, Color = Color3.fromRGB(60, 120, 255), Feature = "Fins" },
	{ Id = "Pulsaroo", Rarity = "Mythic", Income = 11000, Color = Color3.fromRGB(255, 60, 140), Feature = "Ears" },

	{ Id = "Galaxeon", Rarity = "Cosmic", Income = 45000, Color = Color3.fromRGB(90, 40, 200), Feature = "Wings" },
	{ Id = "Voidmaw", Rarity = "Cosmic", Income = 65000, Color = Color3.fromRGB(20, 0, 40), Feature = "Horns" },
	{ Id = "Chronostar", Rarity = "Cosmic", Income = 90000, Color = Color3.fromRGB(0, 220, 255), Feature = "Crown" },

	{ Id = "The Singularity", Rarity = "Secret", Income = 500000, Color = Color3.fromRGB(10, 10, 10), Feature = "Crown" },
	{ Id = "Big Bang Bob", Rarity = "Secret", Income = 750000, Color = Color3.fromRGB(255, 255, 255), Feature = "Horns" },
	{ Id = "Mr. Supernova", Rarity = "Secret", Income = 1200000, Color = Color3.fromRGB(255, 220, 80), Feature = "Crown" },
}

Config.MeteorlingById = {}
Config.MeteorlingsByRarity = {}
for _, info in Config.Meteorlings do
	Config.MeteorlingById[info.Id] = info
	Config.MeteorlingsByRarity[info.Rarity] = Config.MeteorlingsByRarity[info.Rarity] or {}
	table.insert(Config.MeteorlingsByRarity[info.Rarity], info)
end

-- Map
Config.MapHalfWidth = 210
Config.PlotSize = Vector3.new(60, 0, 70)
Config.PlotCount = 6
Config.PlotSpacing = 70
Config.PlotCenterZ = -40

-- Zones in front of the bases. Further zone = rarer meteors, higher speed needed.
Config.Zones = {
	{
		Name = "Meadow",
		ZMin = 70,
		ZMax = 220,
		Speed = 0,
		Color = Color3.fromRGB(95, 170, 80),
		Material = Enum.Material.Grass,
		Interval = 4,
		MaxActive = 12,
		Weights = { Common = 70, Uncommon = 25, Rare = 5 },
	},
	{
		Name = "Crater Dunes",
		ZMin = 240,
		ZMax = 400,
		Speed = 40,
		Color = Color3.fromRGB(225, 190, 120),
		Material = Enum.Material.Sand,
		Interval = 6,
		MaxActive = 8,
		Weights = { Uncommon = 40, Rare = 40, Epic = 18, Legendary = 2 },
	},
	{
		Name = "Lava Rift",
		ZMin = 420,
		ZMax = 590,
		Speed = 90,
		Color = Color3.fromRGB(60, 45, 45),
		Material = Enum.Material.Basalt,
		Interval = 9,
		MaxActive = 6,
		Weights = { Epic = 45, Legendary = 40, Mythic = 13, Cosmic = 2 },
	},
	{
		Name = "Cosmic Void",
		ZMin = 610,
		ZMax = 800,
		Speed = 160,
		Color = Color3.fromRGB(35, 20, 70),
		Material = Enum.Material.Glass,
		Interval = 13,
		MaxActive = 4,
		Weights = { Legendary = 35, Mythic = 45, Cosmic = 18, Secret = 2 },
	},
}

-- Meteor behaviour
Config.Meteor = {
	WarningTime = 3, -- seconds the red impact circle shows before the hit
	FallTime = 1.2,
	GroundLifetime = 60, -- seconds an untouched meteor stays on the ground
	DropLifetime = 45, -- seconds a dropped meteor stays before vanishing
	StolenPenalty = 0.1, -- extra slowdown while carrying something stolen
}

-- Server events
Config.Events = {
	MinGap = 300,
	MaxGap = 420,
	ShowerDuration = 60,
	ShowerSpawnMult = 3,
	ShowerMutationMult = 2,
	CometChance = 0.4, -- chance an automatic event is a Golden Comet instead of a shower
}

-- Monetization. Create the passes/products on the Creator Dashboard and paste the IDs here.
-- An ID of 0 means "not set up yet": the button tells the player it is coming soon.
Config.GamePasses = {
	DoubleMoney = { Id = 0, Name = "2x Cash", Description = "Double all income forever.", Price = 199 },
	DoubleSpeed = { Id = 0, Name = "2x Speed Pad", Description = "Your Speed Pad gives twice the speed.", Price = 149 },
	VIP = { Id = 0, Name = "VIP", Description = "+2 pedestals, +25% luck, longer base lock, gold tag.", Price = 299 },
	AutoCollect = { Id = 0, Name = "Auto Collect", Description = "Cash goes straight to your wallet.", Price = 99 },
	BigHammer = { Id = 0, Name = "Mega Hammer", Description = "Bigger bonk range, faster swings.", Price = 129 },
}

Config.Products = {
	SpeedBoost = { Id = 0, Name = "+50 Speed", Description = "Instantly gain 50 speed.", Price = 25 },
	InstantHatch = { Id = 0, Name = "Instant Hatch", Description = "Hatch every meteor on your base now.", Price = 49 },
	Luck = { Id = 0, Name = "2x Luck (15 min)", Description = "Double mutation luck for 15 minutes.", Price = 59 },
	MeteorShower = { Id = 0, Name = "Summon Meteor Shower", Description = "Start a server-wide meteor shower. Everyone sees your name!", Price = 99 },
	GoldenComet = { Id = 0, Name = "Summon Golden Comet", Description = "Drop a guaranteed Golden comet. The whole server will race for it!", Price = 149 },
}

Config.LuckDuration = 15 * 60
Config.VipLuck = 1.25

return Config
