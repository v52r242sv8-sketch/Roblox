-- MapBuilder: generates the whole world in code (terrain, sky, bases, zones, decor),
-- so the place works from an empty file.
-- Layout (top view, +Z goes "forward"):
--   z = -75..-5   : row of player bases (plots)
--   z =  -5..62   : hub with the spawn and the road
--   z =  62..820  : meteor zones, each further one behind a speed gate

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local MapBuilder = {}

local FONT = Enum.Font.FredokaOne
local W = Config.MapHalfWidth
local terrain = workspace.Terrain

local PLOT_COLORS = {
	Color3.fromRGB(255, 110, 120),
	Color3.fromRGB(255, 185, 80),
	Color3.fromRGB(110, 225, 120),
	Color3.fromRGB(90, 180, 255),
	Color3.fromRGB(185, 120, 255),
	Color3.fromRGB(255, 125, 210),
}

-- Helpers -------------------------------------------------------------------------

local function part(props, parent)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		p[key] = value
	end
	p.Parent = parent
	return p
end

local function deco(props, parent)
	-- Decoration that never blocks raycasts or touches
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

-- Sky, light, terrain --------------------------------------------------------------

local function setupLighting()
	-- Bright sunny cartoon look (the style of today's top Roblox games)
	Lighting.ClockTime = 14.3
	Lighting.GeographicLatitude = 25
	Lighting.Brightness = 3
	Lighting.Ambient = Color3.fromRGB(105, 105, 125)
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 150, 170)
	Lighting.ExposureCompensation = 0
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 1
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.2

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
	sky.StarCount = 3000
	sky.CelestialBodiesShown = true
	sky.SunAngularSize = 14

	local atmosphere = effect("Atmosphere")
	atmosphere.Density = 0.22
	atmosphere.Offset = 0.25
	atmosphere.Color = Color3.fromRGB(205, 225, 255)
	atmosphere.Decay = Color3.fromRGB(110, 130, 170)
	atmosphere.Glare = 0
	atmosphere.Haze = 0.4

	-- Only neon glows, nothing else gets washed out
	local bloom = effect("BloomEffect")
	bloom.Intensity = 0.4
	bloom.Size = 24
	bloom.Threshold = 1.4

	local rays = effect("SunRaysEffect")
	rays.Intensity = 0.05
	rays.Spread = 0.5

	local color = effect("ColorCorrectionEffect")
	color.Saturation = 0.18
	color.Contrast = 0.08
	color.Brightness = 0
	color.TintColor = Color3.fromRGB(255, 255, 255)

	local clouds = terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds")
	clouds.Cover = 0.45
	clouds.Density = 0.5
	clouds.Color = Color3.fromRGB(255, 255, 255)
	clouds.Parent = terrain
end

local function fill(x0, x1, z0, z1, material, depth)
	depth = depth or 12
	terrain:FillBlock(
		CFrame.new((x0 + x1) / 2, -depth / 2, (z0 + z1) / 2),
		Vector3.new(math.abs(x1 - x0), depth, math.abs(z1 - z0)),
		material
	)
end

local function setupTerrainColors()
	terrain:SetMaterialColor(Enum.Material.Grass, Color3.fromRGB(95, 195, 80))
	terrain:SetMaterialColor(Enum.Material.Sand, Color3.fromRGB(240, 205, 135))
	terrain:SetMaterialColor(Enum.Material.Basalt, Color3.fromRGB(70, 58, 60))
	terrain:SetMaterialColor(Enum.Material.CrackedLava, Color3.fromRGB(255, 110, 30))
	terrain:SetMaterialColor(Enum.Material.Slate, Color3.fromRGB(80, 55, 140))
	terrain:SetMaterialColor(Enum.Material.Concrete, Color3.fromRGB(150, 155, 175))
	terrain:SetMaterialColor(Enum.Material.Asphalt, Color3.fromRGB(70, 72, 88))
	terrain:SetMaterialColor(Enum.Material.Rock, Color3.fromRGB(120, 125, 140))
	terrain:SetMaterialColor(Enum.Material.Snow, Color3.fromRGB(225, 225, 255))
end

-- Ring of mountains around the playfield so the horizon is not empty
local function buildMountains(backZ, farZ)
	local rng = Random.new(77)
	local function mountain(position, radius)
		terrain:FillBall(position, radius, Enum.Material.Rock)
		if radius > 55 then
			terrain:FillBall(position + Vector3.new(0, radius * 0.75, 0), radius * 0.32, Enum.Material.Snow)
		end
	end
	-- Centers are pushed out by the radius so terrain never covers the playfield
	for z = backZ - 40, farZ + 40, 55 do
		for _, side in { -1, 1 } do
			local radius = rng:NextNumber(45, 85)
			mountain(Vector3.new(side * (W + radius + rng:NextNumber(4, 20)), rng:NextNumber(-20, 10), z), radius)
		end
	end
	for x = -W - 60, W + 60, 55 do
		local radius = rng:NextNumber(50, 90)
		mountain(Vector3.new(x, rng:NextNumber(-20, 10), farZ + radius + 4), radius)
		local backRadius = radius * 0.8
		mountain(Vector3.new(x, rng:NextNumber(-25, 5), backZ - backRadius - 4), backRadius)
	end
end

-- Decor pieces -----------------------------------------------------------------------

local function buildTree(rng, position, parent)
	local height = rng:NextNumber(8, 13)
	deco({
		Name = "Trunk",
		Size = Vector3.new(1.8, height, 1.8),
		CFrame = CFrame.new(position + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, rng:NextNumber(0, 6), rng:NextNumber(-0.08, 0.08)),
		Material = Enum.Material.Wood,
		Color = Color3.fromRGB(95, 62, 42),
		CanQuery = true,
	}, parent).CanQuery = true
	local leafColor = Color3.fromRGB(55 + rng:NextInteger(0, 30), 130 + rng:NextInteger(0, 50), 70 + rng:NextInteger(0, 30))
	for i = 1, 4 do
		local size = rng:NextNumber(5, 8.5)
		local offset = Vector3.new(rng:NextNumber(-2.5, 2.5), height + rng:NextNumber(-1, 3) + i * 0.4, rng:NextNumber(-2.5, 2.5))
		deco({
			Name = "Leaves",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(size, size, size),
			Position = position + offset,
			Material = Enum.Material.Grass,
			Color = leafColor:Lerp(Color3.fromRGB(150, 220, 120), rng:NextNumber(0, 0.25)),
			CanCollide = false,
		}, parent)
	end
end

local function buildMushroom(rng, position, parent, withLight)
	local color = Color3.fromHSV(rng:NextNumber(0.45, 0.95), 0.6, 1)
	local h = rng:NextNumber(1.2, 2.6)
	deco({
		Name = "Stem",
		Size = Vector3.new(0.5, h, 0.5),
		Position = position + Vector3.new(0, h / 2, 0),
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(235, 230, 210),
		CanCollide = false,
	}, parent)
	local cap = deco({
		Name = "Cap",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(h * 1.1, h * 1.1, h * 1.1),
		Position = position + Vector3.new(0, h + 0.1, 0),
		Material = Enum.Material.Neon,
		Color = color,
		CanCollide = false,
		CastShadow = false,
	}, parent)
	if withLight then
		light(cap, color, 12, 1.2)
	end
end

local function buildCrystal(rng, position, parent, color, scale, withLight)
	local cluster = Instance.new("Model")
	cluster.Name = "Crystal"
	for _ = 1, rng:NextInteger(3, 5) do
		local h = rng:NextNumber(3, 7) * scale
		local w = h * rng:NextNumber(0.22, 0.32)
		deco({
			Name = "Shard",
			Size = Vector3.new(w, h, w),
			CFrame = CFrame.new(position + Vector3.new(rng:NextNumber(-1, 1) * scale, h * 0.35, rng:NextNumber(-1, 1) * scale))
				* CFrame.Angles(rng:NextNumber(-0.45, 0.45), rng:NextNumber(0, 6), rng:NextNumber(-0.45, 0.45)),
			Material = Enum.Material.Neon,
			Color = color:Lerp(Color3.new(1, 1, 1), rng:NextNumber(0, 0.3)),
			Transparency = 0.1,
			CastShadow = false,
		}, cluster)
	end
	cluster.Parent = parent
	if withLight then
		local anchor = cluster:FindFirstChildWhichIsA("BasePart")
		if anchor then
			light(anchor, color, 18 * scale, 2)
		end
	end
	return cluster
end

local function buildLamp(position, parent, color)
	deco({
		Name = "LampPole",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(10, 0.6, 0.6),
		CFrame = CFrame.new(position + Vector3.new(0, 5, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Material = Enum.Material.Metal,
		Color = Color3.fromRGB(40, 40, 55),
	}, parent).CanCollide = true
	local bulb = deco({
		Name = "LampBulb",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1.6, 1.6, 1.6),
		Position = position + Vector3.new(0, 10.4, 0),
		Material = Enum.Material.Neon,
		Color = color,
		CanCollide = false,
		CastShadow = false,
	}, parent)
	light(bulb, color, 26, 1.6)
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
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(230, 60, 60),
	}, CFrame.new(0, 4.6, -0.75) * CFrame.Angles(0, math.rad(90), 0))
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
	local gui, text = billboard(torso, "🎯 BONK DUMMY\nequip Hammer [1] and click", UDim2.fromOffset(220, 56), Vector3.new(0, 5.5, 0), Color3.fromRGB(255, 230, 120), 80)
	gui.Name = "DummyGui"
	model.Parent = parent
	return { Model = model, Pivot = pivot, Base = pivot.CFrame, Torso = torso, Label = text, Hits = 0 }
end

-- Plots ------------------------------------------------------------------------------

local function buildPlot(index, parent)
	local cx = (index - (Config.PlotCount + 1) / 2) * Config.PlotSpacing
	local cz = Config.PlotCenterZ
	local halfX = Config.PlotSize.X / 2
	local halfZ = Config.PlotSize.Z / 2
	local color = PLOT_COLORS[(index - 1) % #PLOT_COLORS + 1]
	local dark = Color3.fromRGB(30, 28, 44)

	local model = Instance.new("Model")
	model.Name = "Plot" .. index
	model:SetAttribute("PlotIndex", index)
	model:SetAttribute("Owner", 0)
	model.Parent = parent

	local floor = part({
		Name = "Floor",
		Size = Vector3.new(Config.PlotSize.X, 0.5, Config.PlotSize.Z),
		Position = Vector3.new(cx, 0.25, cz),
		Material = Enum.Material.WoodPlanks,
		Color = color:Lerp(Color3.fromRGB(70, 55, 50), 0.6),
	}, model)

	-- Neon outline around the floor
	for _, edge in {
		{ Vector3.new(Config.PlotSize.X, 0.25, 0.6), Vector3.new(cx, 0.6, cz + halfZ - 0.3) },
		{ Vector3.new(Config.PlotSize.X, 0.25, 0.6), Vector3.new(cx, 0.6, cz - halfZ + 0.3) },
		{ Vector3.new(0.6, 0.25, Config.PlotSize.Z), Vector3.new(cx - halfX + 0.3, 0.6, cz) },
		{ Vector3.new(0.6, 0.25, Config.PlotSize.Z), Vector3.new(cx + halfX - 0.3, 0.6, cz) },
	} do
		deco({
			Name = "Trim",
			Size = edge[1],
			Position = edge[2],
			Material = Enum.Material.Neon,
			Color = color,
			CanCollide = false,
			CastShadow = false,
		}, model)
	end

	-- Walls: back + sides, with neon caps and corner pillars
	part({
		Name = "BackWall",
		Size = Vector3.new(Config.PlotSize.X, 10, 1.4),
		Position = Vector3.new(cx, 5, cz - halfZ),
		Material = Enum.Material.Brick,
		Color = color:Lerp(dark, 0.55),
	}, model)
	deco({
		Name = "WallCap",
		Size = Vector3.new(Config.PlotSize.X, 0.5, 1.8),
		Position = Vector3.new(cx, 10.2, cz - halfZ),
		Material = Enum.Material.Neon,
		Color = color,
		CastShadow = false,
	}, model)
	for _, side in { -1, 1 } do
		part({
			Name = "SideWall",
			Size = Vector3.new(1.4, 6, Config.PlotSize.Z),
			Position = Vector3.new(cx + side * halfX, 3, cz),
			Material = Enum.Material.Brick,
			Color = color:Lerp(dark, 0.55),
		}, model)
		deco({
			Name = "WallCap",
			Size = Vector3.new(1.8, 0.4, Config.PlotSize.Z),
			Position = Vector3.new(cx + side * halfX, 6.2, cz),
			Material = Enum.Material.Neon,
			Color = color,
			CastShadow = false,
		}, model)
		-- Gate pillars at the open front
		local pillar = part({
			Name = "Pillar",
			Size = Vector3.new(2.6, 12, 2.6),
			Position = Vector3.new(cx + side * (halfX - 0.5), 6, cz + halfZ),
			Material = Enum.Material.Marble,
			Color = Color3.fromRGB(235, 235, 245),
		}, model)
		local orb = deco({
			Name = "PillarOrb",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(2.2, 2.2, 2.2),
			Position = pillar.Position + Vector3.new(0, 7.2, 0),
			Material = Enum.Material.Neon,
			Color = color,
			CanCollide = false,
			CastShadow = false,
		}, model)
		light(orb, color, 22, 1.8)
	end

	local laser = deco({
		Name = "Laser",
		Size = Vector3.new(Config.PlotSize.X - 3, 9, 0.35),
		Position = Vector3.new(cx, 4.5, cz + halfZ),
		Material = Enum.Material.ForceField,
		Color = Color3.fromRGB(255, 40, 70),
		Transparency = 1,
		CanCollide = false,
		CastShadow = false,
	}, model)

	-- Owner sign floating above the back wall
	local signPart = deco({
		Name = "Sign",
		Size = Vector3.new(24, 5, 0.8),
		Position = Vector3.new(cx, 14.5, cz - halfZ),
		Material = Enum.Material.SmoothPlastic,
		Color = dark,
		CanCollide = false,
	}, model)
	deco({
		Name = "SignFrame",
		Size = Vector3.new(25, 6, 0.5),
		Position = signPart.Position - Vector3.new(0, 0, 0.3),
		Material = Enum.Material.Neon,
		Color = color,
		CanCollide = false,
		CastShadow = false,
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
	signLabel.Text = "Empty Base"
	signLabel.TextColor3 = Color3.new(1, 1, 1)
	signLabel.TextStrokeTransparency = 0
	signLabel.Parent = signGui
	-- The front face of a part points to -Z; the sign must face the playfield (+Z)
	signPart.CFrame = CFrame.lookAt(signPart.Position, signPart.Position + Vector3.new(0, 0, 1))

	-- Pedestals: 4 columns x 4 rows, filled from the back row
	local pedestals = {}
	local cols = { -21, -7, 7, 21 }
	local rows = { -20, -7, 6, 19 }
	local n = 0
	for _, rz in rows do
		for _, rx in cols do
			n += 1
			local base = Vector3.new(cx + rx, 0.5, cz + rz)
			flatCylinder({
				Name = "PedestalBase",
				Size = Vector3.new(0.5, 7.6, 7.6),
				Position = base + Vector3.new(0, 0.25, 0),
				Material = Enum.Material.Marble,
				Color = Color3.fromRGB(200, 200, 215),
			}, model)
			local pedestal = flatCylinder({
				Name = "Pedestal" .. n,
				Size = Vector3.new(1.2, 6.4, 6.4),
				Position = base + Vector3.new(0, 0.6, 0),
				Material = Enum.Material.Marble,
				Color = Color3.fromRGB(240, 240, 248),
			}, model)
			pedestal:SetAttribute("Slot", n)
			local ring = flatCylinder({
				Name = "Ring",
				Size = Vector3.new(0.15, 6.9, 6.9),
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
				Color3.fromRGB(210, 210, 220),
				70
			)
			lockGui.Name = "LockGui"
			lockGui.Enabled = false
			pedestals[n] = { Part = pedestal, Ring = ring, LockGui = lockGui }
		end
	end

	-- Speed pad: "+speed every second"
	local speedPad = part({
		Name = "SpeedPad",
		Size = Vector3.new(22, 0.3, 8),
		Position = Vector3.new(cx, 0.65, cz - halfZ + 5.6),
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(50, 190, 255),
		CanCollide = false,
		CastShadow = false,
	}, model)
	for i = -2, 2 do
		deco({
			Name = "Chevron",
			Size = Vector3.new(1, 0.35, 5),
			CFrame = CFrame.new(cx + i * 4, 0.7, cz - halfZ + 5.6) * CFrame.Angles(0, math.rad(45), 0),
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(200, 245, 255),
			CanCollide = false,
			CastShadow = false,
		}, model)
	end
	sparkleEmitter(speedPad, Color3.fromRGB(120, 220, 255), 12, 0.5, 4)
	light(speedPad, Color3.fromRGB(80, 200, 255), 16, 1.5)
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
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(70, 225, 100),
		CanCollide = false,
		CastShadow = false,
	}, model)
	sparkleEmitter(collectPad, Color3.fromRGB(255, 225, 90), 6, 0.6, 3)
	light(collectPad, Color3.fromRGB(90, 255, 120), 14, 1.3)
	local _, bankLabel = billboard(
		collectPad,
		"💰 $0\nstep to collect",
		UDim2.fromOffset(200, 64),
		Vector3.new(0, 3.4, 0),
		Color3.fromRGB(180, 255, 180),
		110
	)

	-- Lock pad (front right)
	local lockPad = part({
		Name = "LockPad",
		Size = Vector3.new(9, 0.3, 8),
		Position = Vector3.new(cx + 18, 0.65, cz + halfZ - 6),
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(255, 60, 80),
		CanCollide = false,
		CastShadow = false,
	}, model)
	light(lockPad, Color3.fromRGB(255, 70, 90), 12, 1.2)
	local _, lockLabel = billboard(
		lockPad,
		"🔒 LOCK BASE",
		UDim2.fromOffset(170, 40),
		Vector3.new(0, 3.2, 0),
		Color3.fromRGB(255, 190, 190),
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

-- Zones ----------------------------------------------------------------------------

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
		Size = Vector3.new(W * 2, 18, 0.5),
		Position = Vector3.new(0, 9, gateZ),
		Material = Enum.Material.ForceField,
		Color = glow,
		Transparency = 0.1,
		CanCollide = false,
		CastShadow = false,
	}, parent)
	deco({
		Name = "GateLine",
		Size = Vector3.new(W * 2, 0.3, 1.2),
		Position = Vector3.new(0, 0.15, gateZ),
		Material = Enum.Material.Neon,
		Color = glow,
		CanCollide = false,
		CastShadow = false,
	}, parent)
	for _, x in { -150, -50, 50, 150 } do
		local pylon = part({
			Name = "GatePylon",
			Size = Vector3.new(3, 22, 3),
			Position = Vector3.new(x, 11, gateZ),
			Material = Enum.Material.Metal,
			Color = Color3.fromRGB(45, 45, 60),
		}, parent)
		local top = deco({
			Name = "PylonTop",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(3.4, 3.4, 3.4),
			Position = pylon.Position + Vector3.new(0, 12.5, 0),
			Material = Enum.Material.Neon,
			Color = glow,
			CanCollide = false,
			CastShadow = false,
		}, parent)
		light(top, glow, 30, 2)
	end
	for _, x in { -100, 100 } do
		local anchor = deco({
			Name = "GateSign",
			Size = Vector3.new(1, 1, 1),
			Position = Vector3.new(x, 22, gateZ),
			Transparency = 1,
			CanCollide = false,
		}, parent)
		billboard(
			anchor,
			"⚡ " .. zone.Speed .. " SPEED ⚡\n" .. string.upper(zone.Name),
			UDim2.new(30, 0, 8, 0),
			Vector3.new(0, 0, 0),
			glow,
			450
		)
	end
end

local function decorateZone(zoneIndex, zone, rng, parent, info)
	local zMin = zone.ZMin
	local zMax = zone.ZMax
	local function randomX(margin)
		return rng:NextNumber(-W + margin, W - margin)
	end
	if zoneIndex == 1 then
		for _ = 1, 18 do
			buildTree(rng, Vector3.new(randomX(10), 0, rng:NextNumber(zMin, zMax)), parent)
		end
		for i = 1, 40 do
			buildMushroom(rng, Vector3.new(randomX(6), 0, rng:NextNumber(zMin - 5, zMax)), parent, i % 4 == 0)
		end
		for _ = 1, 10 do
			local size = rng:NextNumber(3, 6)
			deco({
				Name = "Boulder",
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(size, size, size),
				Position = Vector3.new(randomX(10), size * 0.15, rng:NextNumber(zMin, zMax)),
				Material = Enum.Material.Slate,
				Color = Color3.fromRGB(110, 110, 125),
			}, parent).CanCollide = true
		end
	elseif zoneIndex == 2 then
		for _ = 1, 14 do
			local size = rng:NextNumber(4, 10)
			deco({
				Name = "Rock",
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(size, size, size),
				Position = Vector3.new(randomX(10), size * 0.1, rng:NextNumber(zMin, zMax)),
				Material = Enum.Material.Sandstone,
				Color = Color3.fromRGB(175, 130, 90),
			}, parent).CanCollide = true
		end
		for i = 1, 12 do
			local position = Vector3.new(randomX(15), 0, rng:NextNumber(zMin, zMax))
			terrain:FillCylinder(CFrame.new(position - Vector3.new(0, 1.5, 0)), 3, rng:NextNumber(8, 13), Enum.Material.Basalt)
			buildCrystal(rng, position, parent, Color3.fromRGB(255, 190, 80):Lerp(Color3.fromRGB(80, 200, 255), rng:NextNumber()), 0.8, i % 3 == 0)
		end
	elseif zoneIndex == 3 then
		for _ = 1, 12 do
			local d = rng:NextNumber(14, 26)
			local pos = Vector3.new(randomX(20), 0.15, rng:NextNumber(zMin + 15, zMax - 10))
			terrain:FillCylinder(CFrame.new(pos - Vector3.new(0, 1.8, 0)), 3.5, d / 2 + 4, Enum.Material.CrackedLava)
			local pool = flatCylinder({
				Name = "Lava",
				Size = Vector3.new(0.3, d, d),
				Position = pos,
				Material = Enum.Material.Neon,
				Color = Color3.fromRGB(255, 100, 20),
				CanCollide = false,
				CanQuery = false,
				CastShadow = false,
			}, parent)
			light(pool, Color3.fromRGB(255, 120, 30), d * 1.2, 2.5)
			local embers = sparkleEmitter(pool, Color3.fromRGB(255, 140, 40), 6, 0.5, 5)
			embers.EmissionDirection = Enum.NormalId.Right
			table.insert(info.LavaPools, { Position = pos, Radius = d / 2 })
		end
		for _ = 1, 22 do
			local h = rng:NextNumber(6, 16)
			deco({
				Name = "Spike",
				Size = Vector3.new(3.5, h, 3.5),
				CFrame = CFrame.new(randomX(10), h / 2 - 1.5, rng:NextNumber(zMin, zMax))
					* CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 6), rng:NextNumber(-0.3, 0.3)),
				Material = Enum.Material.Basalt,
				Color = Color3.fromRGB(40, 32, 34),
			}, parent).CanCollide = true
		end
	elseif zoneIndex == 4 then
		for z = zMin, zMax, 30 do
			deco({
				Name = "GridLine",
				Size = Vector3.new(W * 2, 0.12, 0.45),
				Position = Vector3.new(0, 0.06, z),
				Material = Enum.Material.Neon,
				Color = Color3.fromRGB(150, 80, 255),
				CanCollide = false,
				CastShadow = false,
			}, parent)
		end
		for x = -W, W, 30 do
			deco({
				Name = "GridLine",
				Size = Vector3.new(0.45, 0.12, zMax - zMin + 20),
				Position = Vector3.new(x, 0.06, (zMin + zMax) / 2),
				Material = Enum.Material.Neon,
				Color = Color3.fromRGB(110, 60, 220),
				CanCollide = false,
				CastShadow = false,
			}, parent)
		end
		for i = 1, 14 do
			buildCrystal(rng, Vector3.new(randomX(12), 0, rng:NextNumber(zMin, zMax)), parent, Color3.fromRGB(180, 90, 255), 1.6, i % 2 == 0)
		end
		for _ = 1, 24 do
			local size = rng:NextNumber(3, 10)
			deco({
				Name = "Orb",
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(size, size, size),
				Position = Vector3.new(rng:NextNumber(-W, W), rng:NextNumber(35, 90), rng:NextNumber(zMin, zMax)),
				Material = Enum.Material.Neon,
				Color = Color3.fromHSV(rng:NextNumber(0.7, 0.92), 0.65, 1),
				CanCollide = false,
				CastShadow = false,
			}, parent)
		end
		local midZ = (zMin + zMax) / 2
		for i, x in { -130, 0, 130 } do
			local center = Vector3.new(x, 2.5, midZ + (i - 2) * 40)
			local bar = deco({
				Name = "Sweeper",
				Size = Vector3.new(70, 2, 2),
				CFrame = CFrame.new(center),
				Material = Enum.Material.Neon,
				Color = Color3.fromRGB(255, 50, 200),
				CanCollide = false,
				CastShadow = false,
			}, parent)
			light(bar, Color3.fromRGB(255, 60, 200), 20, 1.5)
			deco({
				Name = "SweeperHub",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(5, 6, 6),
				CFrame = CFrame.new(center - Vector3.new(0, 1, 0)) * CFrame.Angles(0, 0, math.rad(90)),
				Material = Enum.Material.Metal,
				Color = Color3.fromRGB(60, 60, 80),
			}, parent).CanCollide = true
			table.insert(info.Sweepers, { Part = bar, Center = center, Speed = 0.9 + i * 0.25, Angle = i })
		end
	end
end

-- Build ----------------------------------------------------------------------------

function MapBuilder.Build()
	setupLighting()
	setupTerrainColors()

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
	}

	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end

	local firstZ = Config.Zones[1].ZMin - 8
	local backZ = Config.PlotCenterZ - Config.PlotSize.Z / 2 - 25

	-- Rocky apron outside the playfield so there is no void between the field and the mountains
	local farGuess = Config.Zones[#Config.Zones].ZMax + 20
	fill(-W - 260, W + 260, backZ - 220, farGuess + 220, Enum.Material.Rock, 16)

	-- Base area + road (terrain, top surface at y = 0)
	fill(-W, W, backZ, firstZ, Enum.Material.Concrete)
	fill(-W, W, 4, 42, Enum.Material.Asphalt)
	for x = -W + 20, W - 20, 40 do
		deco({
			Name = "RoadStripe",
			Size = Vector3.new(14, 0.1, 0.8),
			Position = Vector3.new(x, 0.05, 23),
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(255, 220, 120),
			CanCollide = false,
			CastShadow = false,
		}, mapFolder)
	end
	for x = -W + 35, W - 35, 70 do
		buildLamp(Vector3.new(x, 0, 2), mapFolder, Color3.fromRGB(255, 215, 150))
		buildLamp(Vector3.new(x, 0, 46), mapFolder, Color3.fromRGB(150, 210, 255))
	end

	-- Zones
	local rng = Random.new(1337)
	local startZ = firstZ
	for zoneIndex, zone in Config.Zones do
		local endZ = zone.ZMax + 10
		if zoneIndex == #Config.Zones then
			endZ = zone.ZMax + 20
		end
		local material = zone.Material
		if zone.Material == Enum.Material.Glass then
			material = Enum.Material.Slate
		end
		fill(-W, W, startZ, endZ, material)

		local zoneInfo = { Zone = zone, GateZ = nil }
		if zone.Speed > 0 then
			buildGate(zoneIndex, zone, mapFolder)
			zoneInfo.GateZ = zone.ZMin - 10
		end
		info.Zones[zoneIndex] = zoneInfo

		local decor = Instance.new("Folder")
		decor.Name = "Decor_" .. zone.Name
		decor.Parent = mapFolder
		decorateZone(zoneIndex, zone, rng, decor, info)

		local signAnchor = deco({
			Name = "ZoneSign",
			Size = Vector3.new(1, 1, 1),
			Position = Vector3.new(0, 34, zone.ZMin + 6),
			Transparency = 1,
			CanCollide = false,
		}, mapFolder)
		billboard(
			signAnchor,
			string.upper(zone.Name),
			UDim2.new(46, 0, 8, 0),
			Vector3.new(0, 0, 0),
			ZONE_GLOW[zoneIndex] or Color3.new(1, 1, 1),
			500
		)

		startZ = endZ
	end
	info.FarZ = startZ

	buildMountains(backZ, info.FarZ)

	-- Invisible boundary walls
	local length = info.FarZ - backZ
	for _, side in { -1, 1 } do
		part({
			Name = "Boundary",
			Size = Vector3.new(2, 160, length),
			Position = Vector3.new(side * (W + 1), 80, (info.FarZ + backZ) / 2),
			Transparency = 1,
		}, mapFolder)
	end
	part({
		Name = "Boundary",
		Size = Vector3.new(W * 2, 160, 2),
		Position = Vector3.new(0, 80, backZ - 1),
		Transparency = 1,
	}, mapFolder)
	part({
		Name = "Boundary",
		Size = Vector3.new(W * 2, 160, 2),
		Position = Vector3.new(0, 80, info.FarZ + 1),
		Transparency = 1,
	}, mapFolder)

	-- Spawn hub
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(14, 0.6, 14)
	spawn.Position = Vector3.new(0, 0.3, 30)
	spawn.Material = Enum.Material.Neon
	spawn.Color = Color3.fromRGB(80, 200, 255)
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Transparency = 0.3
	spawn.Parent = mapFolder
	info.Spawn = spawn

	-- Training dummies next to the spawn, facing the player spawn area
	info.Dummies = {}
	for _, x in { -26, 26 } do
		table.insert(info.Dummies, buildDummy(Vector3.new(x, 0, 30), mapFolder))
	end

	local titleAnchor = deco({
		Name = "Title",
		Size = Vector3.new(1, 1, 1),
		Position = Vector3.new(0, 26, 44),
		Transparency = 1,
		CanCollide = false,
	}, mapFolder)
	billboard(
		titleAnchor,
		"☄️ STEAL A METEOR ☄️",
		UDim2.new(50, 0, 9, 0),
		Vector3.new(0, 0, 0),
		Color3.fromRGB(255, 225, 110),
		320,
		Color3.fromRGB(120, 40, 0)
	)

	-- Plots
	for index = 1, Config.PlotCount do
		info.Plots[index] = buildPlot(index, plotsFolder)
	end

	return info
end

return MapBuilder
