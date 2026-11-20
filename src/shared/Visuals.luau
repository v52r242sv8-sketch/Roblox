-- Visuals: builds every model in code (meteors, Meteorlings, hammer, warning circles).
-- Shared so the client can render the same models inside ViewportFrames (Index, hatch popup).

local CollectionService = game:GetService("CollectionService")

local Config = require(script.Parent.Config)
local Util = require(script.Parent.Util)

local Visuals = {}

local FONT = Enum.Font.FredokaOne
local WHITE = Color3.new(1, 1, 1)

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"

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

-- A part welded to the root. The CFrame is set BEFORE welding:
-- setting CFrame on an already welded part would move the whole assembly.
local function attachedPart(root, props, cframe)
	local part = make("Part", props)
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.CastShadow = props.CastShadow ~= false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CFrame = cframe
	part.Parent = root.Parent
	make("WeldConstraint", { Part0 = root, Part1 = part }, part)
	return part
end

local function ball(root, size, color, material, cframe, extra)
	local props = {
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(size, size, size),
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
	}
	if extra then
		for key, value in extra do
			props[key] = value
		end
	end
	return attachedPart(root, props, cframe)
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
		TextColor3 = WHITE,
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

local function sparkles(parent, color, rate, size)
	return make("ParticleEmitter", {
		Name = "Sparkles",
		Color = ColorSequence.new(color),
		LightEmission = 1,
		LightInfluence = 0,
		Rate = rate,
		Lifetime = NumberRange.new(0.8, 1.6),
		Speed = NumberRange.new(1, 3),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, 2, 0),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new(0, 0.4),
		Texture = SPARKLE,
	}, parent)
end

local function addMutationLook(model, root, item, plain)
	if not item.mut then
		return
	end
	local mutation = Config.MutationByName[item.mut]
	if not mutation then
		return
	end
	if plain then
		return
	end
	make("Highlight", {
		FillColor = mutation.Color,
		FillTransparency = 0.6,
		OutlineColor = mutation.Color,
		OutlineTransparency = 0,
		DepthMode = Enum.HighlightDepthMode.Occluded,
	}, model)
	sparkles(root, mutation.Color, 14, 0.6)
end

-- Billboard above an item: name, rarity, mutation, income or hatch timer.
local function itemBillboard(root, item, height, showIncome)
	local info = Config.MeteorlingById[item.id]
	local rarity = Util.GetRarity(info.Rarity)

	local gui = make("BillboardGui", {
		Name = "ItemGui",
		Size = UDim2.new(8, 0, 3.4, 0),
		StudsOffsetWorldSpace = Vector3.new(0, height / 2 + 2.4, 0),
		MaxDistance = 120,
		LightInfluence = 0,
	}, root)

	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0.02, 0),
	}, gui)

	if item.mut then
		local mutation = Config.MutationByName[item.mut]
		label(gui, {
			Name = "Mutation",
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0.22, 0),
			Text = "✦ " .. string.upper(item.mut) .. " x" .. tostring(mutation and mutation.Mult or 1) .. " ✦",
			TextColor3 = mutation and mutation.Color or WHITE,
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
		rarityLabel.TextColor3 = WHITE
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

-- Meteor -----------------------------------------------------------------------

-- An unhatched meteor: a molten glowing core showing through cracks in a rocky shell.
-- plain = true builds only the parts (for ViewportFrames).
function Visuals.MeteorModel(item, showIncome, plain)
	local info = Config.MeteorlingById[item.id]
	local rarity = Util.GetRarity(info.Rarity)
	local size = rarity.Size

	local model = Instance.new("Model")
	model.Name = "Meteor"
	local root = newRoot(model, {
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(size * 0.82, size * 0.82, size * 0.82),
		Material = Enum.Material.Neon,
		Color = rarity.Color,
		CastShadow = false,
	})

	-- Rock plates: big enough to cover most of the core, gaps leak light
	local rng = Random.new(#item.id * 31 + math.floor(size * 10))
	local rockColor = Color3.fromRGB(48, 42, 44)
	local directions = {
		Vector3.new(1, 0, 0),
		Vector3.new(-1, 0, 0),
		Vector3.new(0, 1, 0),
		Vector3.new(0, -1, 0),
		Vector3.new(0, 0, 1),
		Vector3.new(0, 0, -1),
		Vector3.new(0.7, 0.7, 0),
		Vector3.new(-0.7, 0.7, 0),
		Vector3.new(0, 0.7, 0.7),
		Vector3.new(0, -0.7, -0.7),
		Vector3.new(0.7, -0.7, 0),
		Vector3.new(-0.7, 0, 0.7),
	}
	for i, direction in directions do
		local dir = direction.Unit
		local plate = Vector3.new(size * rng:NextNumber(0.42, 0.55), size * 0.18, size * rng:NextNumber(0.42, 0.55))
		local position = dir * size * 0.36
		local up = Vector3.new(0, 1, 0)
		if math.abs(dir.Y) > 0.9 then
			up = Vector3.new(1, 0, 0)
		end
		local cf = CFrame.lookAt(position, position + dir, up) * CFrame.Angles(math.rad(90), rng:NextNumber(0, math.pi), 0)
		attachedPart(root, {
			Name = "Rock" .. i,
			Size = plate,
			Material = Enum.Material.Basalt,
			Color = rockColor:Lerp(rarity.Color, 0.08),
		}, cf)
	end

	if not plain then
		make("PointLight", {
			Color = rarity.Color,
			Range = math.min(40, size * 4),
			Brightness = 3,
			Shadows = false,
		}, root)
		make("ParticleEmitter", {
			Name = "Embers",
			Color = ColorSequence.new(rarity.Color, Color3.fromRGB(255, 150, 60)),
			LightEmission = 1,
			LightInfluence = 0,
			Rate = 5 + Config.RarityIndex[rarity.Name] * 2,
			Lifetime = NumberRange.new(0.8, 1.6),
			Speed = NumberRange.new(1, 3),
			SpreadAngle = Vector2.new(60, 60),
			Acceleration = Vector3.new(0, 6, 0),
			EmissionDirection = Enum.NormalId.Top,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 0.12), NumberSequenceKeypoint.new(1, 0) }),
			Texture = SPARKLE,
		}, root)
		make("ParticleEmitter", {
			Name = "Heat",
			Color = ColorSequence.new(rarity.Color),
			LightEmission = 0.8,
			LightInfluence = 0,
			Rate = 4,
			Lifetime = NumberRange.new(0.6, 1),
			Speed = NumberRange.new(0.5, 1),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 0.9), NumberSequenceKeypoint.new(1, size * 1.4) }),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.85),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Texture = FIRE,
			ZOffset = -1,
		}, root)
		if rarity.Name == "Secret" or rarity.Name == "Cosmic" then
			make("Highlight", {
				FillTransparency = 1,
				OutlineColor = rarity.Name == "Secret" and WHITE or rarity.Color,
				DepthMode = Enum.HighlightDepthMode.Occluded,
			}, model)
		end
		addMutationLook(model, root, item, plain)
		itemBillboard(root, item, size, showIncome)
		CollectionService:AddTag(root, "Spin")
	end
	return model
end

-- Meteorlings ------------------------------------------------------------------

local FEATURES = {}

function FEATURES.Ears(root, s, color, accent)
	for _, side in { -1, 1 } do
		local ear = attachedPart(root, {
			Size = Vector3.new(0.55 * s, 1.15 * s, 0.4 * s),
			Color = color,
			Material = Enum.Material.SmoothPlastic,
		}, root.CFrame * CFrame.new(side * 0.72 * s, 1.55 * s, 0.1 * s) * CFrame.Angles(0, 0, -side * 0.35))
		attachedPart(root, {
			Size = Vector3.new(0.3 * s, 0.75 * s, 0.1 * s),
			Color = accent,
			Material = Enum.Material.Neon,
			CastShadow = false,
		}, ear.CFrame * CFrame.new(0, -0.05 * s, -0.2 * s))
	end
end

function FEATURES.Horns(root, s, _color, accent)
	for _, side in { -1, 1 } do
		local base = attachedPart(root, {
			Size = Vector3.new(0.42 * s, 0.6 * s, 0.42 * s),
			Color = accent,
			Material = Enum.Material.Neon,
			CastShadow = false,
		}, root.CFrame * CFrame.new(side * 0.6 * s, 1.35 * s, -0.25 * s) * CFrame.Angles(-0.25, 0, -side * 0.45))
		attachedPart(root, {
			Size = Vector3.new(0.26 * s, 0.6 * s, 0.26 * s),
			Color = accent:Lerp(WHITE, 0.4),
			Material = Enum.Material.Neon,
			CastShadow = false,
		}, base.CFrame * CFrame.new(0, 0.5 * s, 0) * CFrame.Angles(0, 0, -side * 0.35))
	end
end

function FEATURES.Wings(root, s, color, accent)
	for _, side in { -1, 1 } do
		local wing = attachedPart(root, {
			Size = Vector3.new(2 * s, 0.12 * s, 1.2 * s),
			Color = accent,
			Material = Enum.Material.Neon,
			Transparency = 0.25,
			CastShadow = false,
		}, root.CFrame * CFrame.new(side * 1.9 * s, 0.45 * s, 0.45 * s) * CFrame.Angles(0.15, side * 0.25, side * 0.5))
		attachedPart(root, {
			Size = Vector3.new(1.6 * s, 0.2 * s, 0.35 * s),
			Color = color,
			Material = Enum.Material.SmoothPlastic,
		}, wing.CFrame * CFrame.new(0, 0.05 * s, -0.5 * s))
	end
end

function FEATURES.Antenna(root, s, _color, accent)
	for _, side in { -1, 1 } do
		local stalk = attachedPart(root, {
			Size = Vector3.new(0.12 * s, 1.1 * s, 0.12 * s),
			Color = Color3.fromRGB(40, 40, 50),
			Material = Enum.Material.SmoothPlastic,
		}, root.CFrame * CFrame.new(side * 0.45 * s, 1.75 * s, 0) * CFrame.Angles(0, 0, -side * 0.3))
		ball(root, 0.5 * s, accent, Enum.Material.Neon, stalk.CFrame * CFrame.new(0, 0.6 * s, 0), { CastShadow = false })
	end
end

function FEATURES.Crown(root, s)
	local gold = Color3.fromRGB(255, 205, 50)
	attachedPart(root, {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.35 * s, 1.5 * s, 1.5 * s),
		Color = gold,
		Material = Enum.Material.Metal,
		Reflectance = 0.2,
	}, root.CFrame * CFrame.new(0, 1.45 * s, 0) * CFrame.Angles(0, 0, math.rad(90)))
	for i = 0, 4 do
		local angle = (i / 5) * math.pi * 2
		local spike = CFrame.new(math.cos(angle) * 0.6 * s, 1.85 * s, math.sin(angle) * 0.6 * s)
		attachedPart(root, {
			Size = Vector3.new(0.22 * s, 0.6 * s, 0.22 * s),
			Color = gold,
			Material = Enum.Material.Metal,
			Reflectance = 0.2,
		}, root.CFrame * spike * CFrame.Angles(0, -angle, 0))
		ball(root, 0.2 * s, Color3.fromRGB(255, 80, 120), Enum.Material.Neon, root.CFrame * spike * CFrame.new(0, 0.35 * s, 0), {
			CastShadow = false,
		})
	end
end

function FEATURES.Fins(root, s, color, accent)
	attachedPart(root, {
		Size = Vector3.new(0.2 * s, 1.2 * s, 1.3 * s),
		Color = accent,
		Material = Enum.Material.Neon,
		CastShadow = false,
	}, root.CFrame * CFrame.new(0, 1.45 * s, 0.35 * s) * CFrame.Angles(0.5, 0, 0))
	attachedPart(root, {
		Size = Vector3.new(2 * s, 0.22 * s, 1 * s),
		Color = color,
		Material = Enum.Material.SmoothPlastic,
	}, root.CFrame * CFrame.new(0, 0.25 * s, 1.75 * s) * CFrame.Angles(0.25, 0, 0))
end

-- A hatched Meteorling: round glossy body, big shiny eyes, blush, feet, a signature feature.
function Visuals.CreatureModel(item, showIncome, plain)
	local info = Config.MeteorlingById[item.id]
	local rarity = Util.GetRarity(info.Rarity)
	local rarityIndex = Config.RarityIndex[info.Rarity]
	local s = 0.85 + rarityIndex * 0.17
	local bodySize = 3 * s
	local bodyColor = info.Color

	local model = Instance.new("Model")
	model.Name = "Meteorling"
	local root = newRoot(model, {
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(bodySize, bodySize, bodySize),
		Material = Enum.Material.SmoothPlastic,
		Color = bodyColor,
		Reflectance = 0.05,
	})

	-- Belly
	ball(root, 1.7 * s, bodyColor:Lerp(WHITE, 0.4), nil, root.CFrame * CFrame.new(0, -0.5 * s, -0.62 * s))

	-- Eyes
	for _, side in { -1, 1 } do
		local eye = ball(root, 0.95 * s, WHITE, nil, root.CFrame * CFrame.new(side * 0.55 * s, 0.38 * s, -1.18 * s))
		local pupil = ball(root, 0.55 * s, Color3.fromRGB(20, 18, 30), nil, eye.CFrame * CFrame.new(0, -0.03 * s, -0.27 * s))
		ball(root, 0.2 * s, WHITE, Enum.Material.Neon, pupil.CFrame * CFrame.new(0.12 * s, 0.13 * s, -0.2 * s), {
			CastShadow = false,
		})
		-- Blush
		ball(root, 0.42 * s, Color3.fromRGB(255, 120, 150), nil, root.CFrame * CFrame.new(side * 0.95 * s, -0.12 * s, -1.08 * s), {
			Transparency = 0.35,
			CastShadow = false,
		})
		-- Feet
		attachedPart(root, {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.5 * s, 0.9 * s, 0.9 * s),
			Color = bodyColor:Lerp(Color3.new(0, 0, 0), 0.25),
			Material = Enum.Material.SmoothPlastic,
		}, root.CFrame * CFrame.new(side * 0.6 * s, -1.35 * s, -0.35 * s) * CFrame.Angles(0, 0, math.rad(90)))
		-- Little arms
		ball(root, 0.6 * s, bodyColor:Lerp(Color3.new(0, 0, 0), 0.1), nil, root.CFrame * CFrame.new(side * 1.4 * s, -0.35 * s, -0.4 * s))
	end

	-- Mouth
	attachedPart(root, {
		Size = Vector3.new(0.45 * s, 0.14 * s, 0.1 * s),
		Color = Color3.fromRGB(70, 20, 40),
		Material = Enum.Material.SmoothPlastic,
	}, root.CFrame * CFrame.new(0, -0.18 * s, -1.47 * s) * CFrame.Angles(-0.25, 0, 0))

	local feature = FEATURES[info.Feature]
	if feature then
		feature(root, s, bodyColor, rarity.Color)
	end

	if not plain then
		if rarityIndex >= 4 then
			-- Magic aura bubble
			ball(root, bodySize * 1.25, rarity.Color, Enum.Material.ForceField, root.CFrame, { CastShadow = false })
		end
		if rarityIndex >= 5 then
			make("PointLight", { Color = rarity.Color, Range = 12 + rarityIndex * 2, Brightness = 1.5 }, root)
		end
		if rarityIndex >= 6 then
			sparkles(root, rarity.Color, 8, 0.45)
		end
		addMutationLook(model, root, item, plain)
		itemBillboard(root, item, bodySize + 1.5 * s, showIncome)
	end
	return model
end

function Visuals.ItemModel(item, showIncome, plain)
	if item.hatched then
		return Visuals.CreatureModel(item, showIncome, plain)
	end
	return Visuals.MeteorModel(item, showIncome, plain)
end

-- Effects ------------------------------------------------------------------------

-- Impact target: red ring + inner disc that the client shrinks as a countdown.
function Visuals.WarningCircle(diameter, color)
	local circle = make("Part", {
		Name = "ImpactWarning",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.25, diameter, diameter),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 40, 40),
		Transparency = 0.45,
		Anchored = true,
		CanCollide = false,
		CanTouch = false,
		CanQuery = false,
		CastShadow = false,
	})
	local inner = make("Part", {
		Name = "Inner",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, diameter, diameter),
		Material = Enum.Material.Neon,
		Color = color,
		Transparency = 0.2,
		Anchored = true,
		CanCollide = false,
		CanTouch = false,
		CanQuery = false,
		CastShadow = false,
	}, circle)
	make("PointLight", { Color = Color3.fromRGB(255, 60, 60), Range = diameter, Brightness = 2 }, circle)
	return circle, inner
end

-- Tall light beam marking a special meteor (Golden Comet).
function Visuals.Beacon(position, color)
	local beacon = make("Part", {
		Name = "Beacon",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(600, 4, 4),
		CFrame = CFrame.new(position + Vector3.new(0, 300, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Material = Enum.Material.Neon,
		Color = color,
		Transparency = 0.4,
		Anchored = true,
		CanCollide = false,
		CanTouch = false,
		CanQuery = false,
		CastShadow = false,
	})
	make("ParticleEmitter", {
		Color = ColorSequence.new(color),
		LightEmission = 1,
		Rate = 40,
		Lifetime = NumberRange.new(2, 3),
		Speed = NumberRange.new(0, 0),
		Size = NumberSequence.new(1.2, 0),
		Texture = SPARKLE,
		EmissionDirection = Enum.NormalId.Right,
	}, beacon)
	return beacon
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
		Size = Vector3.new(0.45, 4 * scale, 0.45),
		Material = Enum.Material.Wood,
		Color = Color3.fromRGB(110, 70, 40),
		CanCollide = false,
		Massless = true,
	}, tool)

	local function piece(props, offset)
		local p = make("Part", props)
		p.CanCollide = false
		p.Massless = true
		p.CFrame = handle.CFrame * offset
		p.Parent = tool
		make("WeldConstraint", { Part0 = handle, Part1 = p }, p)
		return p
	end

	piece({
		Name = "Head",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2.6 * scale, 1.5 * scale, 1.5 * scale),
		Material = Enum.Material.SmoothPlastic,
		Color = headColor,
	}, CFrame.new(0, 2 * scale, 0))
	for _, side in { -1, 1 } do
		piece({
			Name = "Band",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.25 * scale, 1.6 * scale, 1.6 * scale),
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(255, 240, 200),
		}, CFrame.new(side * 1.05 * scale, 2 * scale, 0))
	end
	piece({
		Name = "Grip",
		Size = Vector3.new(0.55, 1.2 * scale, 0.55),
		Material = Enum.Material.Fabric,
		Color = Color3.fromRGB(40, 40, 50),
	}, CFrame.new(0, -1.3 * scale, 0))

	make("Sound", { Name = "Swing", SoundId = "rbxasset://sounds/swordslash.wav", Volume = 0.6 }, handle)
	make("Sound", { Name = "Hit", SoundId = "rbxasset://sounds/hit.wav", Volume = 0.9 }, handle)
	return tool
end

return Visuals
