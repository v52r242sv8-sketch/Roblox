-- MapBuilder: generates the whole world in code.
-- Bright cartoon style: checkered floors and tall checkered walls, built from parts.
-- Layout (top view, +Z goes "forward"):
--   z = -100..-5  : courtyard with 6 player gardens (bases)
--   z =   -5..62  : hub plaza with the spawn and training dummies
--   z =   62..820 : the meteor corridor, 4 zones, each behind a speed gate

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local MapBuilder = {}

local FONT = Enum.Font.FredokaOne
local W = Config.MapHalfWidth
local L = Config.LaneHalfWidth
local WALL_HEIGHT = 40
local terrain = workspace.Terrain

local PLOT_COLORS = {
	Color3.fromRGB(255, 110, 120),
	Color3.fromRGB(255, 185, 60),
	Color3.fromRGB(90, 210, 110),
	Color3.fromRGB(80, 170, 255),
	Color3.fromRGB(180, 115, 255),
	Color3.fromRGB(255, 120, 205),
}

-- Helpers -------------------------------------------------------------------------

local function part(props, parent)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		p[key] = value
	end
	p.Parent = parent
	return p
end

local function deco(props, parent)
	props.CanQuery = false
	props.CanTouch = false
	return part(props, parent)
end

local function light(parent, color, range, brightness)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness or 1.5
	l.Shadows = false
	l.Parent = parent
	return l
end

local function billboard(parent, text, size, offset, color, maxDistance, strokeColor)
	local gui = Instance.new("BillboardGui")
	gui.Size = size
	gui.StudsOffsetWorldSpace = offset
	gui.LightInfluence = 0
	gui.MaxDistance = maxDistance or 250
	gui.Parent = parent
	local lbl = Instance.new("TextLabel")
	lbl.Name = "Text"
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Font = FONT
	lbl.TextScaled = true
	lbl.Text = text
	lbl.TextColor3 = color or Color3.new(1, 1, 1)
	lbl.TextStrokeTransparency = 0
	lbl.TextStrokeColor3 = strokeColor or Color3.new(0, 0, 0)
	lbl.Parent = gui
	return gui, lbl
end

local function flatCylinder(props, parent)
	-- Cylinders point along X; rotate so the flat face looks up.
	local position = props.Position
	props.Position = nil
	local p = part(props, parent)
	p.Shape = Enum.PartType.Cylinder
	p.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	return p
end

local function sparkleEmitter(parent, color, rate, size, speed)
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(color)
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Rate = rate
	e.Lifetime = NumberRange.new(1, 2)
	e.Speed = NumberRange.new(speed or 2, (speed or 2) * 2)
	e.SpreadAngle = Vector2.new(25, 25)
	e.EmissionDirection = Enum.NormalId.Top
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Parent = parent
	return e
end

-- Checkered floor: one base slab (top at y = 0) + every other tile in the second color.
local function checkerFloor(x0, x1, z0, z1, colors, tile, parent, name)
	part({
		Name = name or "Floor",
		Size = Vector3.new(x1 - x0, 4, z1 - z0),
		Position = Vector3.new((x0 + x1) / 2, -2, (z0 + z1) / 2),
		Color = colors[1],
	}, parent)
	local cols = math.floor((x1 - x0) / tile)
	local rows = math.floor((z1 - z0) / tile)
	local offsetX = ((x1 - x0) - cols * tile) / 2
	local offsetZ = ((z1 - z0) - rows * tile) / 2
	for cx = 0, cols - 1 do
		for cz = 0, rows - 1 do
			if (cx + cz) % 2 == 0 then
				deco({
					Name = "Tile",
					Size = Vector3.new(tile, 0.1, tile),
					Position = Vector3.new(x0 + offsetX + (cx + 0.5) * tile, 0.05, z0 + offsetZ + (cz + 0.5) * tile),
					Color = colors[2],
					CanCollide = false,
					CastShadow = false,
				}, parent)
			end
		end
	end
end

-- Checkered wall along Z. inwardSign points to the side that faces the players.
local function checkerWallZ(x, z0, z1, colors, parent, inwardSign)
	local thickness = 4
	part({
		Name = "Wall",
		Size = Vector3.new(thickness, WALL_HEIGHT, z1 - z0),
		Position = Vector3.new(x, WALL_HEIGHT / 2, (z0 + z1) / 2),
		Color = colors[1],
	}, parent)
	local cell = 10
	local cols = math.floor((z1 - z0) / cell)
	local rows = math.floor(WALL_HEIGHT / cell)
	for c = 0, cols - 1 do
		for r = 0, rows - 1 do
			if (c + r) % 2 == 0 then
				deco({
					Name = "WallTile",
					Size = Vector3.new(0.2, cell, cell),
					Position = Vector3.new(x + inwardSign * (thickness / 2 + 0.05), (r + 0.5) * cell, z0 + (c + 0.5) * cell),
					Color = colors[2],
					CanCollide = false,
					CastShadow = false,
				}, parent)
			end
		end
	end
	deco({
		Name = "WallTop",
		Size = Vector3.new(thickness + 1, 1.2, z1 - z0),
		Position = Vector3.new(x, WALL_HEIGHT + 0.6, (z0 + z1) / 2),
		Color = colors[2]:Lerp(Color3.new(1, 1, 1), 0.35),
	}, parent)
end

-- Checkered wall along X
local function checkerWallX(z, x0, x1, colors, parent, inwardSign)
	local thickness = 4
	part({
		Name = "Wall",
		Size = Vector3.new(x1 - x0, WALL_HEIGHT, thickness),
		Position = Vector3.new((x0 + x1) / 2, WALL_HEIGHT / 2, z),
		Color = colors[1],
	}, parent)
	local cell = 10
	local cols = math.floor((x1 - x0) / cell)
	local rows = math.floor(WALL_HEIGHT / cell)
	for c = 0, cols - 1 do
		for r = 0, rows - 1 do
			if (c + r) % 2 == 0 then
				deco({
					Name = "WallTile",
					Size = Vector3.new(cell, cell, 0.2),
					Position = Vector3.new(x0 + (c + 0.5) * cell, (r + 0.5) * cell, z + inwardSign * (thickness / 2 + 0.05)),
					Color = colors[2],
					CanCollide = false,
					CastShadow = false,
				}, parent)
			end
		end
	end
	deco({
		Name = "WallTop",
		Size = Vector3.new(x1 - x0, 1.2, thickness + 1),
		Position = Vector3.new((x0 + x1) / 2, WALL_HEIGHT + 0.6, z),
		Color = colors[2]:Lerp(Color3.new(1, 1, 1), 0.35),
	}, parent)
end

-- Sky & light -----------------------------------------------------------------------

local function setupLighting()
	-- Bright sunny cartoon look
	Lighting.ClockTime = 13.5
	Lighting.GeographicLatitude = 20
	Lighting.Brightness = 3
	Lighting.Ambient = Color3.fromRGB(120, 120, 135)
	Lighting.OutdoorAmbient = Color3.fromRGB(165, 165, 180)
	Lighting.ExposureCompensation = 0
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 0.6
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.3

	local function effect(className)
		local existing = Lighting:FindFirstChildOfClass(className)
		if existing then
			return existing
		end
		local inst = Instance.new(className)
		inst.Parent = Lighting
		return inst
	end

	local depth = Lighting:FindFirstChildOfClass("DepthOfFieldEffect")
	if depth then
		depth:Destroy()
	end

	local sky = effect("Sky")
	sky.CelestialBodiesShown = true
	sky.SunAngularSize = 14

	local atmosphere = effect("Atmosphere")
	atmosphere.Density = 0.18
	atmosphere.Offset = 0.25
	atmosphere.Color = Color3.fromRGB(205, 225, 255)
	atmosphere.Decay = Color3.fromRGB(110, 130, 170)
	atmosphere.Glare = 0
	atmosphere.Haze = 0.3

	local bloom = effect("BloomEffect")
	bloom.Intensity = 0.35
	bloom.Size = 24
	bloom.Threshold = 1.4

	local rays = effect("SunRaysEffect")
	rays.Intensity = 0.04
	rays.Spread = 0.5

	local color = effect("ColorCorrectionEffect")
	color.Saturation = 0.2
	color.Contrast = 0.06
	color.Brightness = 0.02
	color.TintColor = Color3.fromRGB(255, 255, 255)

	local clouds = terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds")
	clouds.Cover = 0.45
	clouds.Density = 0.5
	clouds.Color = Color3.fromRGB(255, 255, 255)
	clouds.Parent = terrain
end

-- Decor pieces -----------------------------------------------------------------------

local function buildTree(rng, position, parent)
	local height = rng:NextNumber(7, 11)
	deco({
		Name = "Trunk",
		Size = Vector3.new(1.8, height, 1.8),
		Position = position + Vector3.new(0, height / 2, 0),
		Material = Enum.Material.Wood,
		Color = Color3.fromRGB(120, 78, 48),
	}, parent).CanCollide = true
	local leafColor = Color3.fromRGB(60 + rng:NextInteger(0, 30), 170 + rng:NextInteger(0, 40), 60)
	for i = 1, 3 do
		local size = rng:NextNumber(5, 8)
		deco({
			Name = "Leaves",
			Size = Vector3.new(size, size * 0.8, size),
			CFrame = CFrame.new(position + Vector3.new(rng:NextNumber(-2, 2), height + i * 1.2, rng:NextNumber(-2, 2)))
				* CFrame.Angles(0, rng:NextNumber(0, 6), 0),
			Color = leafColor:Lerp(Color3.fromRGB(170, 235, 110), rng:NextNumber(0, 0.3)),
			CanCollide = false,
		}, parent)
	end
end

local function buildFlower(rng, position, parent)
	local color = Color3.fromHSV(rng:NextNumber(), 0.6, 1)
	deco({
		Name = "Stem",
		Size = Vector3.new(0.25, 1.4, 0.25),
		Position = position + Vector3.new(0, 0.7, 0),
		Color = Color3.fromRGB(60, 150, 50),
		CanCollide = false,
	}, parent)
	deco({
		Name = "Petals",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1, 1, 1),
		Position = position + Vector3.new(0, 1.5, 0),
		Color = color,
		CanCollide = false,
		CastShadow = false,
	}, parent)
end

local function buildBush(rng, position, parent, color)
	for _ = 1, 3 do
		local size = rng:NextNumber(2.5, 4)
		deco({
			Name = "Bush",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(size, size, size),
			Position = position + Vector3.new(rng:NextNumber(-1.5, 1.5), size * 0.3, rng:NextNumber(-1.5, 1.5)),
			Color = color or Color3.fromRGB(70, 175, 70),
			CanCollide = false,
		}, parent)
	end
end

local function buildCactus(rng, position, parent)
	local h = rng:NextNumber(5, 9)
	local green = Color3.fromRGB(70, 170, 80)
	local trunk = deco({ Name = "Cactus", Size = Vector3.new(1.8, h, 1.8), Position = position + Vector3.new(0, h / 2, 0), Color = green }, parent)
	trunk.CanCollide = true
	for _, side in { -1, 1 } do
		local armH = rng:NextNumber(1.5, 3)
		deco({
			Name = "Arm",
			Size = Vector3.new(1.4, 1.2, 1.2),
			Position = position + Vector3.new(side * 1.5, h * 0.5, 0),
			Color = green,
		}, parent)
		deco({
			Name = "Arm",
			Size = Vector3.new(1.2, armH, 1.2),
			Position = position + Vector3.new(side * 2.1, h * 0.5 + armH / 2, 0),
			Color = green,
		}, parent)
	end
end

local function buildPyramid(position, parent, color)
	for i = 0, 4 do
		local size = 22 - i * 4.4
		part({
			Name = "Step",
			Size = Vector3.new(size, 2.2, size),
			Position = position + Vector3.new(0, 1.1 + i * 2.2, 0),
			Material = Enum.Material.Sandstone,
			Color = color,
		}, parent)
	end
end

local function buildCrystal(rng, position, parent, color, scale)
	for _ = 1, rng:NextInteger(3, 5) do
		local h = rng:NextNumber(3, 7) * scale
		local w = h * rng:NextNumber(0.22, 0.32)
		deco({
			Name = "Shard",
			Size = Vector3.new(w, h, w),
			CFrame = CFrame.new(position + Vector3.new(rng:NextNumber(-1, 1) * scale, h * 0.35, rng:NextNumber(-1, 1) * scale))
				* CFrame.Angles(rng:NextNumber(-0.45, 0.45), rng:NextNumber(0, 6), rng:NextNumber(-0.45, 0.45)),
			Material = Enum.Material.Glass,
			Color = color:Lerp(Color3.new(1, 1, 1), rng:NextNumber(0, 0.3)),
			Transparency = 0.15,
		}, parent)
	end
end

local function buildLamp(position, parent, color)
	deco({
		Name = "LampPole",
		Size = Vector3.new(0.7, 10, 0.7),
		Position = position + Vector3.new(0, 5, 0),
		Material = Enum.Material.Metal,
		Color = Color3.fromRGB(60, 60, 75),
	}, parent).CanCollide = true
	local bulb = deco({
		Name = "LampBulb",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1.8, 1.8, 1.8),
		Position = position + Vector3.new(0, 10.6, 0),
		Material = Enum.Material.Neon,
		Color = color,
		CanCollide = false,
		CastShadow = false,
	}, parent)
	light(bulb, color, 18, 1)
end

-- Training dummy: test your hammer without other players -------------------------

local function buildDummy(position, parent)
	local model = Instance.new("Model")
	model.Name = "BonkDummy"
	local pivot = part({
		Name = "Pivot",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.8, 5, 5),
		CFrame = CFrame.new(position + Vector3.new(0, 0.4, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Material = Enum.Material.Wood,
		Color = Color3.fromRGB(120, 80, 50),
	}, model)
	local root = pivot.CFrame * CFrame.Angles(0, 0, math.rad(-90))
	local function piece(props, offset)
		local p = Instance.new("Part")
		for key, value in props do
			p[key] = value
		end
		p.Anchored = false
		p.CanCollide = false
		p.CanQuery = false
		p.Massless = true
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.CFrame = root * offset
		p.Parent = model
		local w = Instance.new("WeldConstraint")
		w.Part0 = pivot
		w.Part1 = p
		w.Parent = p
		return p
	end
	piece({ Name = "Pole", Size = Vector3.new(0.5, 3, 0.5), Material = Enum.Material.Wood, Color = Color3.fromRGB(110, 75, 45) }, CFrame.new(0, 1.8, 0))
	local torso = piece({
		Name = "Torso",
		Size = Vector3.new(2.4, 2.8, 1.4),
		Material = Enum.Material.Fabric,
		Color = Color3.fromRGB(235, 200, 140),
	}, CFrame.new(0, 4.6, 0))
	piece({
		Name = "Target",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, 1.8, 1.8),
		Color = Color3.fromRGB(230, 60, 60),
	}, CFrame.new(0, 4.6, 0.75) * CFrame.Angles(0, math.rad(90), 0))
	piece({
		Name = "Head",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(2, 2, 2),
		Material = Enum.Material.Fabric,
		Color = Color3.fromRGB(235, 200, 140),
	}, CFrame.new(0, 6.9, 0))
	for _, side in { -1, 1 } do
		piece({
			Name = "Arm",
			Size = Vector3.new(2.2, 0.6, 0.6),
			Material = Enum.Material.Fabric,
			Color = Color3.fromRGB(220, 185, 125),
		}, CFrame.new(side * 2.2, 5.3, 0) * CFrame.Angles(0, 0, side * 0.3))
	end
	local gui, text = billboard(
		torso,
		"🎯 BONK DUMMY\nequip Hammer [1] and click",
		UDim2.fromOffset(220, 56),
		Vector3.new(0, 5.5, 0),
		Color3.fromRGB(255, 230, 120),
		80
	)
	gui.Name = "DummyGui"
	model.Parent = parent
	return { Model = model, Pivot = pivot, Base = pivot.CFrame, Torso = torso, Label = text, Hits = 0 }
end

-- Gardens (player bases) ---------------------------------------------------------------

local function buildPlot(index, parent)
	local cx = (index - (Config.PlotCount + 1) / 2) * Config.PlotSpacing
	local cz = Config.PlotCenterZ
	local halfX = Config.PlotSize.X / 2
	local halfZ = Config.PlotSize.Z / 2
	local color = PLOT_COLORS[(index - 1) % #PLOT_COLORS + 1]
	local rng = Random.new(index * 97)

	local model = Instance.new("Model")
	model.Name = "Plot" .. index
	model:SetAttribute("PlotIndex", index)
	model:SetAttribute("Owner", 0)
	model.Parent = parent

	-- Lawn: checkered grass, slightly raised
	local floor = part({
		Name = "Floor",
		Size = Vector3.new(Config.PlotSize.X, 0.5, Config.PlotSize.Z),
		Position = Vector3.new(cx, 0.25, cz),
		Color = Color3.fromRGB(110, 210, 80),
	}, model)
	local tile = 10
	for tx = 0, 5 do
		for tz = 0, 6 do
			if (tx + tz) % 2 == 0 then
				deco({
					Name = "LawnTile",
					Size = Vector3.new(tile, 0.08, tile),
					Position = Vector3.new(cx - halfX + (tx + 0.5) * tile, 0.54, cz - halfZ + (tz + 0.5) * tile),
					Color = Color3.fromRGB(95, 192, 68),
					CanCollide = false,
					CastShadow = false,
				}, model)
			end
		end
	end

	-- Stone path from the gate to the Speed Pad
	for z = cz - halfZ + 10, cz + halfZ - 2, 4 do
		deco({
			Name = "PathStone",
			Size = Vector3.new(5.5, 0.15, 3.4),
			Position = Vector3.new(cx, 0.6, z),
			Material = Enum.Material.Slate,
			Color = Color3.fromRGB(215, 210, 200),
			CanCollide = false,
		}, model)
	end

	-- White picket fence (back + sides)
	local fenceColor = Color3.fromRGB(250, 250, 250)
	local function rail(size, position)
		part({ Name = "FenceRail", Size = size, Position = position, Color = fenceColor }, model)
	end
	local function post(position)
		deco({
			Name = "FencePost",
			Size = Vector3.new(0.6, 4.2, 0.6),
			Position = position + Vector3.new(0, 2.1, 0),
			Color = fenceColor,
		}, model)
	end
	rail(Vector3.new(Config.PlotSize.X, 0.5, 0.4), Vector3.new(cx, 1.6, cz - halfZ))
	rail(Vector3.new(Config.PlotSize.X, 0.5, 0.4), Vector3.new(cx, 3, cz - halfZ))
	for x = -halfX, halfX, 3 do
		post(Vector3.new(cx + x, 0.5, cz - halfZ))
	end
	for _, side in { -1, 1 } do
		rail(Vector3.new(0.4, 0.5, Config.PlotSize.Z), Vector3.new(cx + side * halfX, 1.6, cz))
		rail(Vector3.new(0.4, 0.5, Config.PlotSize.Z), Vector3.new(cx + side * halfX, 3, cz))
		for z = -halfZ, halfZ - 3, 3 do
			post(Vector3.new(cx + side * halfX, 0.5, cz + z))
		end
		-- Flowers and bushes along the fence
		for z = -halfZ + 6, halfZ - 14, 9 do
			buildFlower(rng, Vector3.new(cx + side * (halfX - 1.8), 0.5, cz + z), model)
		end
		buildBush(rng, Vector3.new(cx + side * (halfX - 3), 0.5, cz - halfZ + 3), model)
	end

	-- Entrance arch with the owner sign
	local wood = Color3.fromRGB(150, 100, 60)
	for _, side in { -1, 1 } do
		part({
			Name = "ArchPost",
			Size = Vector3.new(2, 14, 2),
			Position = Vector3.new(cx + side * 9, 7, cz + halfZ),
			Material = Enum.Material.Wood,
			Color = wood,
		}, model)
	end
	local signPart = part({
		Name = "Sign",
		Size = Vector3.new(22, 4.5, 1),
		Position = Vector3.new(cx, 14.5, cz + halfZ),
		Material = Enum.Material.Wood,
		Color = color,
		CanCollide = false,
	}, model)
	-- The Front face points to -Z by default; turn it toward the plaza (+Z)
	signPart.CFrame = CFrame.lookAt(signPart.Position, signPart.Position + Vector3.new(0, 0, 1))
	deco({
		Name = "SignFrame",
		Size = Vector3.new(23.5, 5.6, 0.8),
		Position = signPart.Position - Vector3.new(0, 0, 0.3),
		Material = Enum.Material.Wood,
		Color = wood,
		CanCollide = false,
	}, model)
	local signGui = Instance.new("SurfaceGui")
	signGui.Face = Enum.NormalId.Front
	signGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	signGui.PixelsPerStud = 40
	signGui.LightInfluence = 0
	signGui.Parent = signPart
	local signLabel = Instance.new("TextLabel")
	signLabel.Size = UDim2.fromScale(1, 1)
	signLabel.BackgroundTransparency = 1
	signLabel.Font = FONT
	signLabel.TextScaled = true
	signLabel.Text = "Empty Garden"
	signLabel.TextColor3 = Color3.new(1, 1, 1)
	signLabel.TextStrokeTransparency = 0
	signLabel.Parent = signGui

	local laser = deco({
		Name = "Laser",
		Size = Vector3.new(Config.PlotSize.X - 1, 9, 0.35),
		Position = Vector3.new(cx, 4.5, cz + halfZ),
		Material = Enum.Material.ForceField,
		Color = Color3.fromRGB(255, 40, 70),
		Transparency = 1,
		CanCollide = false,
		CastShadow = false,
	}, model)

	-- Pedestals: 4 columns x 4 rows on both sides of the path, filled from the back
	local pedestals = {}
	local cols = { -21, -10, 10, 21 }
	local rows = { -20, -7, 6, 19 }
	local n = 0
	for _, rz in rows do
		for _, rx in cols do
			n += 1
			local base = Vector3.new(cx + rx, 0.5, cz + rz)
			flatCylinder({
				Name = "PedestalBase",
				Size = Vector3.new(0.5, 7.4, 7.4),
				Position = base + Vector3.new(0, 0.25, 0),
				Material = Enum.Material.Slate,
				Color = Color3.fromRGB(200, 195, 185),
			}, model)
			local pedestal = flatCylinder({
				Name = "Pedestal" .. n,
				Size = Vector3.new(1.2, 6.2, 6.2),
				Position = base + Vector3.new(0, 0.6, 0),
				Material = Enum.Material.Marble,
				Color = Color3.fromRGB(245, 245, 250),
			}, model)
			pedestal:SetAttribute("Slot", n)
			local ring = flatCylinder({
				Name = "Ring",
				Size = Vector3.new(0.15, 6.7, 6.7),
				Position = base + Vector3.new(0, 1.15, 0),
				Material = Enum.Material.Neon,
				Color = color,
				CanCollide = false,
				CastShadow = false,
			}, model)
			ring.CanQuery = false
			local lockGui = billboard(
				pedestal,
				"🔒 Buy in Shop",
				UDim2.fromOffset(130, 30),
				Vector3.new(0, 2.2, 0),
				Color3.fromRGB(230, 230, 240),
				70
			)
			lockGui.Name = "LockGui"
			lockGui.Enabled = false
			pedestals[n] = { Part = pedestal, Ring = ring, LockGui = lockGui }
		end
	end

	-- Speed pad (back of the garden)
	local speedPad = part({
		Name = "SpeedPad",
		Size = Vector3.new(22, 0.3, 8),
		Position = Vector3.new(cx, 0.65, cz - halfZ + 5.6),
		Color = Color3.fromRGB(60, 190, 255),
		CanCollide = false,
	}, model)
	for i = -2, 2 do
		deco({
			Name = "Chevron",
			Size = Vector3.new(1, 0.35, 5),
			CFrame = CFrame.new(cx + i * 4, 0.72, cz - halfZ + 5.6) * CFrame.Angles(0, math.rad(45), 0),
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(220, 250, 255),
			CanCollide = false,
			CastShadow = false,
		}, model)
	end
	sparkleEmitter(speedPad, Color3.fromRGB(120, 220, 255), 10, 0.5, 4)
	billboard(
		speedPad,
		"⚡ SPEED PAD ⚡\n+speed every second",
		UDim2.fromOffset(220, 64),
		Vector3.new(0, 3.4, 0),
		Color3.fromRGB(170, 235, 255),
		110
	)

	-- Collect pad (front left)
	local collectPad = part({
		Name = "CollectPad",
		Size = Vector3.new(11, 0.3, 8),
		Position = Vector3.new(cx - 17, 0.65, cz + halfZ - 6),
		Color = Color3.fromRGB(80, 225, 100),
		CanCollide = false,
	}, model)
	sparkleEmitter(collectPad, Color3.fromRGB(255, 225, 90), 6, 0.6, 3)
	local _, bankLabel = billboard(
		collectPad,
		"💰 $0\nstep to collect",
		UDim2.fromOffset(200, 64),
		Vector3.new(0, 3.4, 0),
		Color3.fromRGB(190, 255, 190),
		110
	)

	-- Lock pad (front right)
	local lockPad = part({
		Name = "LockPad",
		Size = Vector3.new(9, 0.3, 8),
		Position = Vector3.new(cx + 18, 0.65, cz + halfZ - 6),
		Color = Color3.fromRGB(255, 70, 90),
		CanCollide = false,
	}, model)
	local _, lockLabel = billboard(
		lockPad,
		"🔒 LOCK BASE",
		UDim2.fromOffset(170, 40),
		Vector3.new(0, 3.2, 0),
		Color3.fromRGB(255, 200, 200),
		110
	)

	local depositAttachment = Instance.new("Attachment")
	depositAttachment.Name = "DepositPoint"
	depositAttachment.Position = Vector3.new(0, 3, 0)
	depositAttachment.Parent = floor

	local itemsFolder = Instance.new("Folder")
	itemsFolder.Name = "Items"
	itemsFolder.Parent = model

	local spawnPos = Vector3.new(cx, 4, cz + halfZ - 14)

	return {
		Index = index,
		Model = model,
		Floor = floor,
		Center = Vector3.new(cx, 0, cz),
		HalfX = halfX,
		HalfZ = halfZ,
		Color = color,
		Pedestals = pedestals,
		SpeedPad = speedPad,
		CollectPad = collectPad,
		LockPad = lockPad,
		Laser = laser,
		SignLabel = signLabel,
		BankLabel = bankLabel,
		LockLabel = lockLabel,
		ItemsFolder = itemsFolder,
		SpawnCFrame = CFrame.lookAt(spawnPos, spawnPos + Vector3.new(0, 0, 1)),
		Owner = nil,
		Rendered = {},
		Reserved = {},
		LockedUntil = 0,
		LockCooldownUntil = 0,
	}
end

-- Corridor zones ---------------------------------------------------------------------

local ZONE_GLOW = {
	Color3.fromRGB(120, 255, 140),
	Color3.fromRGB(255, 200, 90),
	Color3.fromRGB(255, 110, 40),
	Color3.fromRGB(190, 110, 255),
}

local function buildGate(zoneIndex, zone, parent)
	local gateZ = zone.ZMin - 10
	local glow = ZONE_GLOW[zoneIndex] or Color3.fromRGB(80, 200, 255)
	deco({
		Name = "Gate_" .. zone.Name,
		Size = Vector3.new(L * 2, 22, 0.5),
		Position = Vector3.new(0, 11, gateZ),
		Material = Enum.Material.ForceField,
		Color = glow,
		Transparency = 0.1,
		CanCollide = false,
		CastShadow = false,
	}, parent)
	deco({
		Name = "GateLine",
		Size = Vector3.new(L * 2, 0.3, 1.5),
		Position = Vector3.new(0, 0.15, gateZ),
		Material = Enum.Material.Neon,
		Color = glow,
		CanCollide = false,
		CastShadow = false,
	}, parent)
	deco({
		Name = "GateBeam",
		Size = Vector3.new(L * 2 + 8, 4, 4),
		Position = Vector3.new(0, 26, gateZ),
		Color = glow:Lerp(Color3.new(1, 1, 1), 0.2),
	}, parent)
	local anchor = deco({
		Name = "GateSign",
		Size = Vector3.new(1, 1, 1),
		Position = Vector3.new(0, 33, gateZ),
		Transparency = 1,
		CanCollide = false,
	}, parent)
	billboard(
		anchor,
		"⚡ " .. zone.Speed .. " SPEED ⚡\n" .. string.upper(zone.Name) .. " • Guardian: " .. zone.Guardian.Speed .. " speed",
		UDim2.fromOffset(440, 110),
		Vector3.new(0, 0, 0),
		glow,
		500
	)
end

local function nearWall(rng)
	local side = 1
	if rng:NextNumber() < 0.5 then
		side = -1
	end
	return side * rng:NextNumber(L - 9, L - 4)
end

local function decorateZone(zoneIndex, zone, rng, parent, info)
	local zMin = zone.ZMin
	local zMax = zone.ZMax
	if zoneIndex == 1 then
		for _ = 1, 14 do
			buildTree(rng, Vector3.new(nearWall(rng), 0, rng:NextNumber(zMin, zMax)), parent)
		end
		for _ = 1, 30 do
			buildFlower(rng, Vector3.new(nearWall(rng), 0, rng:NextNumber(zMin - 5, zMax)), parent)
		end
		for _ = 1, 8 do
			buildBush(rng, Vector3.new(nearWall(rng), 0, rng:NextNumber(zMin, zMax)), parent)
		end
	elseif zoneIndex == 2 then
		buildPyramid(Vector3.new(-L + 14, 0, zMin + 40), parent, zone.Wall[1])
		buildPyramid(Vector3.new(L - 14, 0, zMax - 40), parent, zone.Wall[2])
		for _ = 1, 12 do
			buildCactus(rng, Vector3.new(nearWall(rng), 0, rng:NextNumber(zMin, zMax)), parent)
		end
		for _ = 1, 6 do
			buildCrystal(rng, Vector3.new(nearWall(rng), 0, rng:NextNumber(zMin, zMax)), parent, Color3.fromRGB(255, 190, 80), 0.9)
		end
	elseif zoneIndex == 3 then
		for _ = 1, 9 do
			local d = rng:NextNumber(12, 18)
			local pos = Vector3.new(rng:NextNumber(-L + 12, L - 12), 0.12, rng:NextNumber(zMin + 15, zMax - 10))
			local pool = flatCylinder({
				Name = "Lava",
				Size = Vector3.new(0.25, d, d),
				Position = pos,
				Material = Enum.Material.Neon,
				Color = Color3.fromRGB(255, 110, 20),
				CanCollide = false,
				CanQuery = false,
				CastShadow = false,
			}, parent)
			local embers = sparkleEmitter(pool, Color3.fromRGB(255, 150, 40), 6, 0.5, 5)
			embers.EmissionDirection = Enum.NormalId.Right
			table.insert(info.LavaPools, { Position = pos, Radius = d / 2 })
		end
		for _ = 1, 16 do
			local h = rng:NextNumber(6, 14)
			deco({
				Name = "Spike",
				Size = Vector3.new(3.5, h, 3.5),
				CFrame = CFrame.new(nearWall(rng), h / 2 - 1.5, rng:NextNumber(zMin, zMax))
					* CFrame.Angles(rng:NextNumber(-0.25, 0.25), rng:NextNumber(0, 6), rng:NextNumber(-0.25, 0.25)),
				Material = Enum.Material.Basalt,
				Color = Color3.fromRGB(60, 45, 45),
			}, parent).CanCollide = true
		end
	elseif zoneIndex == 4 then
		for _ = 1, 12 do
			buildCrystal(rng, Vector3.new(nearWall(rng), 0, rng:NextNumber(zMin, zMax)), parent, Color3.fromRGB(200, 120, 255), 1.5)
		end
		for _ = 1, 16 do
			local size = rng:NextNumber(3, 8)
			deco({
				Name = "Orb",
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(size, size, size),
				Position = Vector3.new(rng:NextNumber(-L, L), rng:NextNumber(45, 80), rng:NextNumber(zMin, zMax)),
				Material = Enum.Material.Neon,
				Color = Color3.fromHSV(rng:NextNumber(0.7, 0.92), 0.6, 1),
				CanCollide = false,
				CastShadow = false,
			}, parent)
		end
		local midZ = (zMin + zMax) / 2
		for i, offset in { -65, 0, 65 } do
			local center = Vector3.new(0, 2.5, midZ + offset)
			local bar = deco({
				Name = "Sweeper",
				Size = Vector3.new(56, 2, 2),
				CFrame = CFrame.new(center),
				Material = Enum.Material.Neon,
				Color = Color3.fromRGB(255, 60, 200),
				CanCollide = false,
				CastShadow = false,
			}, parent)
			deco({
				Name = "SweeperHub",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(5, 6, 6),
				CFrame = CFrame.new(center - Vector3.new(0, 1, 0)) * CFrame.Angles(0, 0, math.rad(90)),
				Material = Enum.Material.Metal,
				Color = Color3.fromRGB(70, 70, 90),
			}, parent).CanCollide = true
			table.insert(info.Sweepers, { Part = bar, Center = center, Speed = 0.8 + i * 0.25, Angle = i })
		end
	end
end

-- Build ----------------------------------------------------------------------------

function MapBuilder.Build()
	setupLighting()

	local mapFolder = Instance.new("Folder")
	mapFolder.Name = "Map"
	mapFolder.Parent = workspace

	local meteorFolder = Instance.new("Folder")
	meteorFolder.Name = "Meteors"
	meteorFolder.Parent = workspace

	local plotsFolder = Instance.new("Folder")
	plotsFolder.Name = "Plots"
	plotsFolder.Parent = workspace

	local info = {
		Folder = mapFolder,
		MeteorFolder = meteorFolder,
		Plots = {},
		Zones = {},
		LavaPools = {},
		Sweepers = {},
		Dummies = {},
		Lane = L,
	}

	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end

	local corridorStart = Config.Zones[1].ZMin - 8
	local backZ = Config.PlotCenterZ - Config.PlotSize.Z / 2 - 25
	local wallColors = { Color3.fromRGB(150, 205, 255), Color3.fromRGB(125, 185, 245) }

	-- Courtyard (gardens) + hub plaza
	local yard = Instance.new("Folder")
	yard.Name = "Courtyard"
	yard.Parent = mapFolder
	checkerFloor(-W, W, backZ, -5, { Color3.fromRGB(135, 225, 95), Color3.fromRGB(118, 208, 82) }, 12, yard, "YardFloor")
	checkerFloor(-W, W, -5, corridorStart, { Color3.fromRGB(235, 235, 245), Color3.fromRGB(212, 214, 230) }, 12, yard, "Plaza")
	for z = 10, corridorStart, 5 do
		deco({
			Name = "PathStone",
			Size = Vector3.new(10, 0.12, 3.5),
			Position = Vector3.new(0, 0.06, z),
			Material = Enum.Material.Slate,
			Color = Color3.fromRGB(190, 185, 175),
			CanCollide = false,
		}, yard)
	end
	checkerWallX(backZ, -W, W, wallColors, yard, 1)
	checkerWallZ(-W, backZ, corridorStart, wallColors, yard, 1)
	checkerWallZ(W, backZ, corridorStart, wallColors, yard, -1)
	checkerWallX(corridorStart, -W, -L - 4, wallColors, yard, -1)
	checkerWallX(corridorStart, L + 4, W, wallColors, yard, -1)
	for x = -W + 35, W - 35, 70 do
		buildLamp(Vector3.new(x, 0, 2), yard, Color3.fromRGB(255, 225, 150))
	end
	local rng = Random.new(1337)
	for _ = 1, 14 do
		local x = rng:NextNumber(-W + 8, W - 8)
		if math.abs(x) > 40 then
			buildBush(rng, Vector3.new(x, 0, rng:NextNumber(48, corridorStart - 4)), yard)
		end
	end

	-- Corridor entrance beam
	deco({
		Name = "EntranceBeam",
		Size = Vector3.new(L * 2 + 10, 5, 5),
		Position = Vector3.new(0, WALL_HEIGHT - 2, corridorStart),
		Color = Color3.fromRGB(255, 210, 80),
	}, mapFolder)

	-- Corridor zones
	local startZ = corridorStart
	for zoneIndex, zone in Config.Zones do
		local endZ = zone.ZMax + 10
		if zoneIndex == #Config.Zones then
			endZ = zone.ZMax + 20
		end
		local folder = Instance.new("Folder")
		folder.Name = "Zone_" .. zone.Name
		folder.Parent = mapFolder

		checkerFloor(-L, L, startZ, endZ, zone.Floor, 10, folder, "Floor_" .. zone.Name)
		checkerWallZ(-L - 2, startZ, endZ, zone.Wall, folder, 1)
		checkerWallZ(L + 2, startZ, endZ, zone.Wall, folder, -1)

		local zoneInfo = { Zone = zone, GateZ = nil }
		if zone.Speed > 0 then
			buildGate(zoneIndex, zone, folder)
			zoneInfo.GateZ = zone.ZMin - 10
		end
		info.Zones[zoneIndex] = zoneInfo
		decorateZone(zoneIndex, zone, rng, folder, info)

		local signAnchor = deco({
			Name = "ZoneSign",
			Size = Vector3.new(1, 1, 1),
			Position = Vector3.new(0, 18, zone.ZMin + 12),
			Transparency = 1,
			CanCollide = false,
		}, folder)
		billboard(signAnchor, string.upper(zone.Name), UDim2.fromOffset(360, 70), Vector3.new(0, 0, 0), ZONE_GLOW[zoneIndex] or Color3.new(1, 1, 1), 300)
		startZ = endZ
	end
	info.FarZ = startZ
	checkerWallX(info.FarZ, -L - 4, L + 4, Config.Zones[#Config.Zones].Wall, mapFolder, -1)

	-- Spawn hub
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(14, 0.6, 14)
	spawn.Position = Vector3.new(0, 0.3, 30)
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Color = Color3.fromRGB(90, 200, 255)
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = mapFolder
	info.Spawn = spawn

	for _, x in { -26, 26 } do
		table.insert(info.Dummies, buildDummy(Vector3.new(x, 0, 30), mapFolder))
	end

	local titleAnchor = deco({
		Name = "Title",
		Size = Vector3.new(1, 1, 1),
		Position = Vector3.new(0, WALL_HEIGHT + 12, corridorStart),
		Transparency = 1,
		CanCollide = false,
	}, mapFolder)
	billboard(
		titleAnchor,
		"☄️ STEAL A METEOR ☄️",
		UDim2.fromOffset(560, 100),
		Vector3.new(0, 0, 0),
		Color3.fromRGB(255, 225, 110),
		400,
		Color3.fromRGB(120, 40, 0)
	)

	-- Gardens
	for index = 1, Config.PlotCount do
		info.Plots[index] = buildPlot(index, plotsFolder)
	end

	return info
end

return MapBuilder
