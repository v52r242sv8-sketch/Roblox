-- Visuals: builds every model in code (meteors, Meteorlings, hammer, effects),
-- so the game needs no imported assets.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)

local Visuals = {}

local FONT = Enum.Font.FredokaOne

local function make(className, props, parent)
	local inst = Instance.new(className)
	for key, value in props do
		inst[key] = value
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end
Visuals.Make = make

local function weld(part0, part1)
	return make("WeldConstraint", { Part0 = part0, Part1 = part1 }, part1)
end

-- A part that is welded to a root and follows it around.
-- The CFrame must be set BEFORE welding: setting CFrame on a welded part moves the whole assembly.
local function attachedPart(root, props, cframe)
	local part = make("Part", props)
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CFrame = cframe
	part.Parent = root.Parent
	weld(root, part)
	return part
end

local function newRoot(model, props)
	local root = make("Part", props)
	root.Name = "Root"
	root.Anchored = true
	root.CanCollide = false
	root.CanTouch = false
	root.CanQuery = true
	root.TopSurface = Enum.SurfaceType.Smooth
	root.BottomSurface = Enum.SurfaceType.Smooth
	root.Parent = model
	model.PrimaryPart = root
	return root
end

local function label(parent, props)
	local lbl = make("TextLabel", {
		BackgroundTransparency = 1,
		Font = FONT,
		TextScaled = true,
		TextColor3 = Color3.new(1, 1, 1),
		TextStrokeTransparency = 0,
		TextStrokeColor3 = Color3.new(0, 0, 0),
	})
	for key, value in props do
		lbl[key] = value
	end
	lbl.Parent = parent
	return lbl
end
Visuals.Label = label

local function addMutationLook(model, root, item)
	if not item.mut then
		return
	end
	local mutation = Config.MutationByName[item.mut]
	if not mutation then
		return
	end
	make("Highlight", {
		FillColor = mutation.Color,
		FillTransparency = 0.55,
		OutlineColor = mutation.Color,
		OutlineTransparency = 0,
		DepthMode = Enum.HighlightDepthMode.Occluded,
	}, model)
	make("ParticleEmitter", {
		Color = ColorSequence.new(mutation.Color),
		LightEmission = 1,
		Rate = 10,
		Lifetime = NumberRange.new(0.8, 1.4),
		Speed = NumberRange.new(1, 3),
		SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) }),
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
	}, root)
end

-- Billboard above an item: name, rarity, mutation, income or hatch timer.
local function itemBillboard(root, item, height, showIncome)
	local info = Config.MeteorlingById[item.id]
	local rarity = Util.GetRarity(info.Rarity)

	local gui = make("BillboardGui", {
		Name = "ItemGui",
		Size = UDim2.new(8, 0, 3.4, 0),
		StudsOffsetWorldSpace = Vector3.new(0, height / 2 + 2.2, 0),
		MaxDistance = 140,
		LightInfluence = 0,
		AlwaysOnTop = false,
	}, root)

	local list = make("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
	list.Parent = gui

	if item.mut then
		local mutation = Config.MutationByName[item.mut]
		label(gui, {
			Name = "Mutation",
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0.22, 0),
			Text = string.upper(item.mut) .. " x" .. tostring(mutation and mutation.Mult or 1),
			TextColor3 = mutation and mutation.Color or Color3.new(1, 1, 1),
		})
	end

	local nameText = item.id
	if not item.hatched then
		nameText = rarity.Name .. " Meteor"
	end
	label(gui, {
		Name = "Title",
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0.3, 0),
		Text = nameText,
	})

	local rarityLabel = label(gui, {
		Name = "Rarity",
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0.22, 0),
		Text = rarity.Name,
		TextColor3 = rarity.Color,
	})
	if rarity.Name == "Secret" then
		rarityLabel.TextColor3 = Color3.new(1, 1, 1)
		rarityLabel.TextStrokeColor3 = Color3.fromRGB(255, 0, 200)
	end

	if showIncome then
		if item.hatched then
			label(gui, {
				Name = "Income",
				LayoutOrder = 4,
				Size = UDim2.new(1, 0, 0.26, 0),
				Text = Util.FormatMoney(Util.ItemIncome(item)) .. "/s",
				TextColor3 = Color3.fromRGB(120, 255, 120),
			})
		elseif item.hatchAt then
			local timer = label(gui, {
				Name = "Timer",
				LayoutOrder = 4,
				Size = UDim2.new(1, 0, 0.26, 0),
				Text = "Hatching...",
				TextColor3 = Color3.fromRGB(255, 230, 120),
			})
			timer:SetAttribute("HatchAt", item.hatchAt)
			CollectionService:AddTag(timer, "HatchTimer")
		end
	end
	return gui
end

-- An unhatched meteor: glowing core with a rocky shell.
function Visuals.MeteorModel(item, showIncome)
	local info = Config.MeteorlingById[item.id]
	local rarity = Util.GetRarity(info.Rarity)
	local size = rarity.Size

	local model = Instance.new("Model")
	model.Name = "Meteor"
	local root = newRoot(model, {
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(size, size, size),
		Material = Enum.Material.Neon,
		Color = rarity.Color,
	})

	local rng = Random.new()
	for i = 1, 6 do
		local angle = CFrame.Angles(rng:NextNumber(0, math.pi * 2), rng:NextNumber(0, math.pi * 2), 0)
		attachedPart(root, {
			Name = "Rock" .. i,
			Size = Vector3.new(size * 0.5, size * 0.32, size * 0.5),
			Material = Enum.Material.Basalt,
			Color = Color3.fromRGB(55, 48, 48),
		}, root.CFrame * angle * CFrame.new(0, size * 0.4, 0))
	end

	make("PointLight", {
		Color = rarity.Color,
		Range = math.min(60, size * 4),
		Brightness = 2.5,
	}, root)

	make("ParticleEmitter", {
		Name = "Embers",
		Color = ColorSequence.new(rarity.Color),
		LightEmission = 1,
		Rate = 6 + Config.RarityIndex[rarity.Name] * 3,
		Lifetime = NumberRange.new(0.6, 1.2),
		Speed = NumberRange.new(2, 5),
		SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 0.18), NumberSequenceKeypoint.new(1, 0) }),
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
	}, root)

	if rarity.Name == "Secret" then
		make("Highlight", {
			FillTransparency = 1,
			OutlineColor = Color3.new(1, 1, 1),
			DepthMode = Enum.HighlightDepthMode.Occluded,
		}, model)
	end

	addMutationLook(model, root, item)
	itemBillboard(root, item, size, showIncome)
	return model
end

local FEATURES = {}

function FEATURES.Ears(root, s, color, accent)
	for _, side in { -1, 1 } do
		local ear = attachedPart(root, {
			Size = Vector3.new(0.5 * s, 1.1 * s, 0.35 * s),
			Color = color,
			Material = Enum.Material.SmoothPlastic,
		}, root.CFrame * CFrame.new(side * 0.7 * s, 1.55 * s, 0) * CFrame.Angles(0, 0, -side * 0.35))
		local inner = attachedPart(root, {
			Size = Vector3.new(0.3 * s, 0.7 * s, 0.1 * s),
			Color = accent,
			Material = Enum.Material.Neon,
		}, ear.CFrame * CFrame.new(0, 0, -0.2 * s))
	end
end

function FEATURES.Horns(root, s, _color, accent)
	for _, side in { -1, 1 } do
		local horn = attachedPart(root, {
			Size = Vector3.new(0.35 * s, 1.0 * s, 0.35 * s),
			Color = accent,
			Material = Enum.Material.Neon,
		}, root.CFrame * CFrame.new(side * 0.65 * s, 1.45 * s, -0.2 * s) * CFrame.Angles(-0.3, 0, -side * 0.5))
	end
end

function FEATURES.Wings(root, s, color, accent)
	for _, side in { -1, 1 } do
		local wing = attachedPart(root, {
			Size = Vector3.new(1.8 * s, 0.15 * s, 1.1 * s),
			Color = accent,
			Material = Enum.Material.Neon,
			Transparency = 0.2,
		}, root.CFrame * CFrame.new(side * 1.9 * s, 0.4 * s, 0.4 * s) * CFrame.Angles(0, 0, side * 0.45))
		local edge = attachedPart(root, {
			Size = Vector3.new(1.4 * s, 0.18 * s, 0.4 * s),
			Color = color,
			Material = Enum.Material.SmoothPlastic,
		}, wing.CFrame * CFrame.new(0, 0.05 * s, -0.45 * s))
	end
end

function FEATURES.Antenna(root, s, _color, accent)
	for _, side in { -1, 1 } do
		local stalk = attachedPart(root, {
			Size = Vector3.new(0.12 * s, 1.1 * s, 0.12 * s),
			Color = Color3.fromRGB(40, 40, 40),
			Material = Enum.Material.SmoothPlastic,
		}, root.CFrame * CFrame.new(side * 0.45 * s, 1.75 * s, 0) * CFrame.Angles(0, 0, -side * 0.3))
		local bulb = attachedPart(root, {
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.45 * s, 0.45 * s, 0.45 * s),
			Color = accent,
			Material = Enum.Material.Neon,
		}, stalk.CFrame * CFrame.new(0, 0.6 * s, 0))
	end
end

function FEATURES.Crown(root, s)
	local gold = Color3.fromRGB(255, 205, 50)
	local band = attachedPart(root, {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.35 * s, 1.5 * s, 1.5 * s),
		Color = gold,
		Material = Enum.Material.Metal,
	}, root.CFrame * CFrame.new(0, 1.45 * s, 0) * CFrame.Angles(0, 0, math.rad(90)))
	for i = 0, 4 do
		local angle = (i / 5) * math.pi * 2
		local spike = attachedPart(root, {
			Size = Vector3.new(0.22 * s, 0.6 * s, 0.22 * s),
			Color = gold,
			Material = Enum.Material.Neon,
		}, root.CFrame * CFrame.new(math.cos(angle) * 0.6 * s, 1.85 * s, math.sin(angle) * 0.6 * s))
	end
end

function FEATURES.Fins(root, s, color, accent)
	local fin = attachedPart(root, {
		Size = Vector3.new(0.2 * s, 1.1 * s, 1.2 * s),
		Color = accent,
		Material = Enum.Material.Neon,
	}, root.CFrame * CFrame.new(0, 1.5 * s, 0.3 * s) * CFrame.Angles(0.5, 0, 0))
	local tail = attachedPart(root, {
		Size = Vector3.new(1.8 * s, 0.2 * s, 0.9 * s),
		Color = color,
		Material = Enum.Material.SmoothPlastic,
	}, root.CFrame * CFrame.new(0, 0.2 * s, 1.75 * s))
end

-- A hatched Meteorling: round body, big eyes, one signature feature.
function Visuals.CreatureModel(item, showIncome)
	local info = Config.MeteorlingById[item.id]
	local rarity = Util.GetRarity(info.Rarity)
	local rarityIndex = Config.RarityIndex[info.Rarity]
	local s = 0.85 + rarityIndex * 0.17
	local bodySize = 3 * s

	local model = Instance.new("Model")
	model.Name = "Meteorling"
	local root = newRoot(model, {
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(bodySize, bodySize, bodySize),
		Material = Enum.Material.SmoothPlastic,
		Color = info.Color,
	})

	-- Ball parts must have a uniform size
	attachedPart(root, {
		Name = "Belly",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1.6 * s, 1.6 * s, 1.6 * s),
		Color = info.Color:Lerp(Color3.new(1, 1, 1), 0.35),
		Material = Enum.Material.SmoothPlastic,
	}, root.CFrame * CFrame.new(0, -0.55 * s, -0.6 * s))

	for _, side in { -1, 1 } do
		local eye = attachedPart(root, {
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.85 * s, 0.85 * s, 0.85 * s),
			Color = Color3.new(1, 1, 1),
			Material = Enum.Material.SmoothPlastic,
		}, root.CFrame * CFrame.new(side * 0.55 * s, 0.4 * s, -1.2 * s))
		local pupil = attachedPart(root, {
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.45 * s, 0.45 * s, 0.45 * s),
			Color = Color3.new(0.05, 0.05, 0.08),
			Material = Enum.Material.SmoothPlastic,
		}, eye.CFrame * CFrame.new(0, 0, -0.28 * s))
		local shine = attachedPart(root, {
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.15 * s, 0.15 * s, 0.15 * s),
			Color = Color3.new(1, 1, 1),
			Material = Enum.Material.Neon,
		}, pupil.CFrame * CFrame.new(0.1 * s, 0.1 * s, -0.15 * s))
	end

	local feature = FEATURES[info.Feature]
	if feature then
		feature(root, s, info.Color, rarity.Color)
	end

	if rarityIndex >= 5 then
		make("PointLight", { Color = rarity.Color, Range = 14 + rarityIndex * 2, Brightness = 1.5 }, root)
	end
	if rarityIndex >= 6 then
		make("ParticleEmitter", {
			Color = ColorSequence.new(rarity.Color),
			LightEmission = 1,
			Rate = 8,
			Lifetime = NumberRange.new(1, 1.6),
			Speed = NumberRange.new(0.5, 1.5),
			SpreadAngle = Vector2.new(180, 180),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0) }),
			Texture = "rbxasset://textures/particles/sparkles_main.dds",
		}, root)
	end

	addMutationLook(model, root, item)
	itemBillboard(root, item, bodySize + 1.5 * s, showIncome)
	return model
end

function Visuals.ItemModel(item, showIncome)
	if item.hatched then
		return Visuals.CreatureModel(item, showIncome)
	end
	return Visuals.MeteorModel(item, showIncome)
end

-- Red pulsing circle that shows where a meteor is about to land.
function Visuals.WarningCircle(diameter, color)
	local circle = make("Part", {
		Name = "ImpactWarning",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, diameter, diameter),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 40, 40),
		Transparency = 0.35,
		Anchored = true,
		CanCollide = false,
		CanTouch = false,
		CanQuery = false,
	})
	local inner = make("Part", {
		Name = "Inner",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.35, diameter * 0.35, diameter * 0.35),
		Material = Enum.Material.Neon,
		Color = color,
		Anchored = true,
		CanCollide = false,
		CanTouch = false,
		CanQuery = false,
	}, circle)
	inner:SetAttribute("Follow", true)
	return circle, inner
end

-- Tall light beam marking a special meteor (Golden Comet).
function Visuals.Beacon(position, color)
	return make("Part", {
		Name = "Beacon",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(500, 3, 3),
		CFrame = CFrame.new(position + Vector3.new(0, 250, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Material = Enum.Material.Neon,
		Color = color,
		Transparency = 0.45,
		Anchored = true,
		CanCollide = false,
		CanTouch = false,
		CanQuery = false,
	})
end

function Visuals.HammerTool(big)
	local tool = Instance.new("Tool")
	tool.Name = "Hammer"
	tool.ToolTip = "Bonk players to make them drop what they carry!"
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.Grip = CFrame.new(0, -1.2, 0)

	local scale = 1
	local headColor = Color3.fromRGB(255, 120, 40)
	if big then
		scale = 1.5
		headColor = Color3.fromRGB(255, 210, 40)
	end

	local handle = make("Part", {
		Name = "Handle",
		Size = Vector3.new(0.5, 4 * scale, 0.5),
		Material = Enum.Material.Wood,
		Color = Color3.fromRGB(110, 70, 40),
		CanCollide = false,
		Massless = true,
	}, tool)

	local head = make("Part", {
		Name = "Head",
		Size = Vector3.new(2.4 * scale, 1.4 * scale, 1.4 * scale),
		Material = Enum.Material.Neon,
		Color = headColor,
		CanCollide = false,
		Massless = true,
	})
	head.CFrame = handle.CFrame * CFrame.new(0, 2 * scale, 0)
	head.Parent = tool
	make("WeldConstraint", { Part0 = handle, Part1 = head }, head)

	make("Sound", {
		Name = "Swing",
		SoundId = "rbxasset://sounds/swordslash.wav",
		Volume = 0.6,
	}, handle)
	make("Sound", {
		Name = "Hit",
		SoundId = "rbxasset://sounds/hit.wav",
		Volume = 0.9,
	}, handle)

	return tool
end

return Visuals
