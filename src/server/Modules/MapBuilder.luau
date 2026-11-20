-- MapBuilder: generates the whole map in code, so the place works from an empty baseplate.
-- Layout (top view, +Z goes "forward"):
--   z = -75..-5   : row of player bases (plots)
--   z =  -5..62   : hub with the spawn
--   z =  62..800  : meteor zones, each further one behind a speed gate

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local MapBuilder = {}

local FONT = Enum.Font.FredokaOne
local W = Config.MapHalfWidth

local PLOT_COLORS = {
	Color3.fromRGB(255, 120, 120),
	Color3.fromRGB(255, 190, 90),
	Color3.fromRGB(120, 220, 120),
	Color3.fromRGB(100, 180, 255),
	Color3.fromRGB(190, 130, 255),
	Color3.fromRGB(255, 130, 210),
}

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

local function billboard(parent, text, size, offset, color, maxDistance)
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

local function setupLighting()
	Lighting.ClockTime = 17.6
	Lighting.Brightness = 2.2
	Lighting.Ambient = Color3.fromRGB(70, 60, 90)
	Lighting.OutdoorAmbient = Color3.fromRGB(120, 110, 150)
	Lighting.EnvironmentDiffuseScale = 0.5
	Lighting.EnvironmentSpecularScale = 0.5

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmosphere.Density = 0.32
	atmosphere.Offset = 0.2
	atmosphere.Color = Color3.fromRGB(200, 170, 255)
	atmosphere.Decay = Color3.fromRGB(110, 80, 160)
	atmosphere.Glare = 0.3
	atmosphere.Haze = 1.2
	atmosphere.Parent = Lighting

	local bloom = Lighting:FindFirstChildOfClass("BloomEffect") or Instance.new("BloomEffect")
	bloom.Intensity = 0.8
	bloom.Size = 30
	bloom.Threshold = 0.9
	bloom.Parent = Lighting

	local color = Lighting:FindFirstChildOfClass("ColorCorrectionEffect") or Instance.new("ColorCorrectionEffect")
	color.Saturation = 0.15
	color.Contrast = 0.08
	color.Parent = Lighting
end

local function buildTree(rng, position, parent)
	local height = rng:NextNumber(7, 11)
	part({
		Name = "Trunk",
		Size = Vector3.new(1.6, height, 1.6),
		Position = position + Vector3.new(0, height / 2, 0),
		Material = Enum.Material.Wood,
		Color = Color3.fromRGB(105, 70, 45),
	}, parent)
	local leaf = rng:NextNumber(7, 11)
	part({
		Name = "Leaves",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(leaf, leaf, leaf),
		Position = position + Vector3.new(0, height + leaf * 0.3, 0),
		Material = Enum.Material.Grass,
		Color = Color3.fromRGB(70 + rng:NextInteger(0, 40), 160 + rng:NextInteger(0, 40), 70),
		CanCollide = false,
	}, parent)
end

local function buildPlot(index, parent)
	local cx = (index - (Config.PlotCount + 1) / 2) * Config.PlotSpacing
	local cz = Config.PlotCenterZ
	local halfX = Config.PlotSize.X / 2
	local halfZ = Config.PlotSize.Z / 2
	local color = PLOT_COLORS[(index - 1) % #PLOT_COLORS + 1]

	local model = Instance.new("Model")
	model.Name = "Plot" .. index
	model:SetAttribute("PlotIndex", index)
	model:SetAttribute("Owner", 0)
	model.Parent = parent

	local floor = part({
		Name = "Floor",
		Size = Vector3.new(Config.PlotSize.X, 0.5, Config.PlotSize.Z),
		Position = Vector3.new(cx, 0.25, cz),
		Material = Enum.Material.SmoothPlastic,
		Color = color:Lerp(Color3.fromRGB(40, 40, 50), 0.55),
	}, model)

	-- Border trim
	part({
		Name = "Trim",
		Size = Vector3.new(Config.PlotSize.X, 0.2, 1),
		Position = Vector3.new(cx, 0.6, cz + halfZ - 0.5),
		Material = Enum.Material.Neon,
		Color = color,
		CanCollide = false,
	}, model)

	-- Walls (back + sides). The front stays open for the laser gate.
	local wallColor = color:Lerp(Color3.fromRGB(30, 30, 40), 0.35)
	part({
		Name = "BackWall",
		Size = Vector3.new(Config.PlotSize.X, 9, 1),
		Position = Vector3.new(cx, 4.5, cz - halfZ),
		Material = Enum.Material.SmoothPlastic,
		Color = wallColor,
	}, model)
	for _, side in { -1, 1 } do
		part({
			Name = "SideWall",
			Size = Vector3.new(1, 6, Config.PlotSize.Z),
			Position = Vector3.new(cx + side * halfX, 3, cz),
			Material = Enum.Material.SmoothPlastic,
			Color = wallColor,
		}, model)
	end

	local laser = part({
		Name = "Laser",
		Size = Vector3.new(Config.PlotSize.X - 1, 8, 0.4),
		Position = Vector3.new(cx, 4, cz + halfZ),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 40, 60),
		Transparency = 1,
		CanCollide = false,
		CanTouch = false,
		CanQuery = false,
	}, model)

	-- Owner sign on the back wall
	local signPart = part({
		Name = "Sign",
		Size = Vector3.new(30, 6, 1),
		Position = Vector3.new(cx, 12, cz - halfZ),
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(25, 25, 35),
	}, model)
	local _, signLabel = billboard(signPart, "Empty Base", UDim2.new(30, 0, 6, 0), Vector3.new(0, 0, 0), color, 300)

	-- Pedestals: 4 columns x 4 rows, filled from the back row
	local pedestals = {}
	local cols = { -21, -7, 7, 21 }
	local rows = { -20, -7, 6, 19 }
	local n = 0
	for _, rz in rows do
		for _, rx in cols do
			n += 1
			local pedestal = flatCylinder({
				Name = "Pedestal" .. n,
				Size = Vector3.new(1.2, 7, 7),
				Position = Vector3.new(cx + rx, 0.5 + 0.6, cz + rz),
				Material = Enum.Material.SmoothPlastic,
				Color = Color3.fromRGB(230, 230, 240),
			}, model)
			pedestal:SetAttribute("Slot", n)
			local ring = flatCylinder({
				Name = "Ring",
				Size = Vector3.new(0.2, 7.6, 7.6),
				Position = Vector3.new(cx + rx, 0.55, cz + rz),
				Material = Enum.Material.Neon,
				Color = color,
				CanCollide = false,
			}, model)
			local lockGui = billboard(
				pedestal,
				"LOCKED",
				UDim2.new(5, 0, 1.4, 0),
				Vector3.new(0, 2, 0),
				Color3.fromRGB(200, 200, 200),
				80
			)
			lockGui.Name = "LockGui"
			lockGui.Enabled = false
			pedestals[n] = { Part = pedestal, Ring = ring, LockGui = lockGui }
		end
	end

	-- Speed pad (back strip): "+1 speed every second"
	local speedPad = part({
		Name = "SpeedPad",
		Size = Vector3.new(22, 0.3, 8),
		Position = Vector3.new(cx, 0.65, cz - halfZ + 5.5),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(60, 200, 255),
		CanCollide = false,
	}, model)
	billboard(
		speedPad,
		"⚡ SPEED PAD ⚡\nstand here: +speed every second",
		UDim2.new(16, 0, 3.5, 0),
		Vector3.new(0, 3.2, 0),
		Color3.fromRGB(150, 230, 255),
		120
	)

	-- Collect pad (front left)
	local collectPad = part({
		Name = "CollectPad",
		Size = Vector3.new(11, 0.3, 8),
		Position = Vector3.new(cx - 17, 0.65, cz + halfZ - 6),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(80, 230, 100),
		CanCollide = false,
	}, model)
	local _, bankLabel = billboard(
		collectPad,
		"💰 $0\nstep to collect",
		UDim2.new(10, 0, 3.5, 0),
		Vector3.new(0, 3.2, 0),
		Color3.fromRGB(170, 255, 170),
		120
	)

	-- Lock pad (front right)
	local lockPad = part({
		Name = "LockPad",
		Size = Vector3.new(9, 0.3, 8),
		Position = Vector3.new(cx + 18, 0.65, cz + halfZ - 6),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 70, 80),
		CanCollide = false,
	}, model)
	local _, lockLabel = billboard(
		lockPad,
		"🔒 LOCK BASE",
		UDim2.new(9, 0, 2.5, 0),
		Vector3.new(0, 3, 0),
		Color3.fromRGB(255, 180, 180),
		120
	)

	-- Where the carry beam points to
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

local function buildGate(zone, parent)
	local gateZ = zone.ZMin - 10
	local curtain = part({
		Name = "Gate_" .. zone.Name,
		Size = Vector3.new(W * 2, 16, 0.6),
		Position = Vector3.new(0, 8, gateZ),
		Material = Enum.Material.ForceField,
		Color = Color3.fromRGB(80, 200, 255),
		Transparency = 0.2,
		CanCollide = false,
		CanTouch = false,
		CanQuery = false,
	}, parent)
	for _, x in { -140, 0, 140 } do
		local anchor = part({
			Name = "GateSign",
			Size = Vector3.new(1, 1, 1),
			Position = Vector3.new(x, 19, gateZ),
			Transparency = 1,
			CanCollide = false,
			CanTouch = false,
			CanQuery = false,
		}, parent)
		billboard(
			anchor,
			"⚡ " .. zone.Speed .. " SPEED ⚡\n" .. zone.Name,
			UDim2.new(26, 0, 7, 0),
			Vector3.new(0, 0, 0),
			Color3.fromRGB(150, 230, 255),
			400
		)
	end
	return curtain
end

local function decorateZone(zoneIndex, zone, rng, parent, info)
	local zMin = zone.ZMin
	local zMax = zone.ZMax
	if zoneIndex == 1 then
		for _ = 1, 16 do
			local x = rng:NextNumber(-W + 10, W - 10)
			local z = rng:NextNumber(zMin, zMax)
			buildTree(rng, Vector3.new(x, 0, z), parent)
		end
	elseif zoneIndex == 2 then
		for _ = 1, 14 do
			local size = rng:NextNumber(4, 10)
			part({
				Name = "Rock",
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(size, size, size),
				Position = Vector3.new(rng:NextNumber(-W + 10, W - 10), size * 0.1, rng:NextNumber(zMin, zMax)),
				Material = Enum.Material.Slate,
				Color = Color3.fromRGB(150, 120, 90),
			}, parent)
		end
		for _ = 1, 10 do
			local d = rng:NextNumber(12, 24)
			flatCylinder({
				Name = "Crater",
				Size = Vector3.new(0.2, d, d),
				Position = Vector3.new(rng:NextNumber(-W + 15, W - 15), 0.1, rng:NextNumber(zMin, zMax)),
				Material = Enum.Material.Sand,
				Color = Color3.fromRGB(180, 140, 90),
				CanCollide = false,
			}, parent)
		end
	elseif zoneIndex == 3 then
		for _ = 1, 12 do
			local d = rng:NextNumber(14, 26)
			local pos = Vector3.new(rng:NextNumber(-W + 20, W - 20), 0.15, rng:NextNumber(zMin + 15, zMax - 10))
			local pool = flatCylinder({
				Name = "Lava",
				Size = Vector3.new(0.3, d, d),
				Position = pos,
				Material = Enum.Material.Neon,
				Color = Color3.fromRGB(255, 100, 20),
				CanCollide = false,
			}, parent)
			local light = Instance.new("PointLight")
			light.Color = Color3.fromRGB(255, 120, 30)
			light.Range = d
			light.Brightness = 2
			light.Parent = pool
			table.insert(info.LavaPools, { Position = pos, Radius = d / 2 })
		end
		for _ = 1, 18 do
			local h = rng:NextNumber(5, 14)
			part({
				Name = "Spike",
				Size = Vector3.new(3, h, 3),
				CFrame = CFrame.new(rng:NextNumber(-W + 10, W - 10), h / 2 - 1, rng:NextNumber(zMin, zMax))
					* CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 6), rng:NextNumber(-0.3, 0.3)),
				Material = Enum.Material.Basalt,
				Color = Color3.fromRGB(40, 30, 30),
			}, parent)
		end
	elseif zoneIndex == 4 then
		for z = zMin, zMax, 40 do
			part({
				Name = "GridLine",
				Size = Vector3.new(W * 2, 0.1, 0.5),
				Position = Vector3.new(0, 0.05, z),
				Material = Enum.Material.Neon,
				Color = Color3.fromRGB(150, 80, 255),
				CanCollide = false,
			}, parent)
		end
		for _ = 1, 20 do
			local size = rng:NextNumber(3, 9)
			part({
				Name = "Orb",
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(size, size, size),
				Position = Vector3.new(rng:NextNumber(-W, W), rng:NextNumber(30, 80), rng:NextNumber(zMin, zMax)),
				Material = Enum.Material.Neon,
				Color = Color3.fromHSV(rng:NextNumber(0.7, 0.9), 0.7, 1),
				CanCollide = false,
				CanQuery = false,
				CanTouch = false,
			}, parent)
		end
		local midZ = (zMin + zMax) / 2
		for i, x in { -130, 0, 130 } do
			local center = Vector3.new(x, 2.5, midZ + (i - 2) * 40)
			local bar = part({
				Name = "Sweeper",
				Size = Vector3.new(70, 2, 2),
				CFrame = CFrame.new(center),
				Material = Enum.Material.Neon,
				Color = Color3.fromRGB(255, 50, 200),
				CanCollide = false,
				CanTouch = false,
				CanQuery = false,
			}, parent)
			part({
				Name = "SweeperHub",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(5, 6, 6),
				CFrame = CFrame.new(center - Vector3.new(0, 1, 0)) * CFrame.Angles(0, 0, math.rad(90)),
				Material = Enum.Material.Metal,
				Color = Color3.fromRGB(60, 60, 80),
			}, parent)
			table.insert(info.Sweepers, { Part = bar, Center = center, Speed = 0.9 + i * 0.25, Angle = i })
		end
	end
end

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
	}

	-- Remove the default baseplate if the place has one
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end

	local firstZ = Config.Zones[1].ZMin - 8
	local backZ = Config.PlotCenterZ - Config.PlotSize.Z / 2 - 25
	part({
		Name = "BaseGround",
		Size = Vector3.new(W * 2, 4, firstZ - backZ),
		Position = Vector3.new(0, -2, (firstZ + backZ) / 2),
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(70, 74, 96),
	}, mapFolder)

	part({
		Name = "Road",
		Size = Vector3.new(W * 2, 0.1, 40),
		Position = Vector3.new(0, 0.05, 22),
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(90, 95, 120),
	}, mapFolder)

	-- Zones
	local rng = Random.new(1337)
	local startZ = firstZ
	for zoneIndex, zone in Config.Zones do
		local endZ = zone.ZMax + 10
		if zoneIndex == #Config.Zones then
			endZ = zone.ZMax + 20
		end
		part({
			Name = "Ground_" .. zone.Name,
			Size = Vector3.new(W * 2, 4, endZ - startZ),
			Position = Vector3.new(0, -2, (startZ + endZ) / 2),
			Material = zone.Material,
			Color = zone.Color,
		}, mapFolder)

		local zoneInfo = { Zone = zone, GateZ = nil }
		if zone.Speed > 0 then
			zoneInfo.Gate = buildGate(zone, mapFolder)
			zoneInfo.GateZ = zone.ZMin - 10
		end
		info.Zones[zoneIndex] = zoneInfo

		local decor = Instance.new("Folder")
		decor.Name = "Decor_" .. zone.Name
		decor.Parent = mapFolder
		decorateZone(zoneIndex, zone, rng, decor, info)

		local signAnchor = part({
			Name = "ZoneSign",
			Size = Vector3.new(1, 1, 1),
			Position = Vector3.new(0, 30, zone.ZMin + 5),
			Transparency = 1,
			CanCollide = false,
			CanTouch = false,
			CanQuery = false,
		}, mapFolder)
		billboard(signAnchor, zone.Name, UDim2.new(40, 0, 8, 0), Vector3.new(0, 0, 0), Color3.new(1, 1, 1), 500)

		startZ = endZ
	end
	info.FarZ = startZ

	-- Invisible boundary walls
	local length = info.FarZ - backZ
	for _, side in { -1, 1 } do
		part({
			Name = "Boundary",
			Size = Vector3.new(2, 120, length),
			Position = Vector3.new(side * (W + 1), 60, (info.FarZ + backZ) / 2),
			Transparency = 1,
		}, mapFolder)
	end
	part({
		Name = "Boundary",
		Size = Vector3.new(W * 2, 120, 2),
		Position = Vector3.new(0, 60, backZ - 1),
		Transparency = 1,
	}, mapFolder)
	part({
		Name = "Boundary",
		Size = Vector3.new(W * 2, 120, 2),
		Position = Vector3.new(0, 60, info.FarZ + 1),
		Transparency = 1,
	}, mapFolder)

	-- Spawn hub
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(14, 1, 14)
	spawn.Position = Vector3.new(0, 0.5, 30)
	spawn.Material = Enum.Material.Neon
	spawn.Color = Color3.fromRGB(80, 200, 255)
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = mapFolder
	info.Spawn = spawn

	local titleAnchor = part({
		Name = "Title",
		Size = Vector3.new(1, 1, 1),
		Position = Vector3.new(0, 22, 40),
		Transparency = 1,
		CanCollide = false,
		CanTouch = false,
		CanQuery = false,
	}, mapFolder)
	billboard(
		titleAnchor,
		"☄️ STEAL A METEOR ☄️",
		UDim2.new(46, 0, 9, 0),
		Vector3.new(0, 0, 0),
		Color3.fromRGB(255, 220, 120),
		300
	)

	-- Plots
	for index = 1, Config.PlotCount do
		info.Plots[index] = buildPlot(index, plotsFolder)
	end

	return info
end

return MapBuilder
