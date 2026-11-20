-- UI: the whole HUD built in code.
-- Glossy buttons with hover/press animations, animated panels with background blur,
-- 3D Meteorlings in the Index and in the hatch card, notification badges, toasts, banners.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)
local Visuals = require(Shared.Visuals)

local player = Players.LocalPlayer

local UI = {}

local FONT = Enum.Font.FredokaOne
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local PANEL_TOP = Color3.fromRGB(46, 40, 78)
local PANEL_BOTTOM = Color3.fromRGB(24, 20, 44)
local GREEN = Color3.fromRGB(70, 210, 100)
local RED = Color3.fromRGB(240, 80, 90)
local GOLD = Color3.fromRGB(255, 200, 60)
local GREY = Color3.fromRGB(110, 110, 130)

local PRODUCT_ORDER = { "SpeedBoost", "InstantHatch", "Luck", "MeteorShower", "GoldenComet" }
local PRODUCT_ICONS = { SpeedBoost = "⚡", InstantHatch = "🐣", Luck = "🍀", MeteorShower = "☄️", GoldenComet = "🌟" }
local PASS_ORDER = { "DoubleMoney", "DoubleSpeed", "VIP", "AutoCollect", "BigHammer" }
local PASS_ICONS = { DoubleMoney = "💰", DoubleSpeed = "👟", VIP = "⭐", AutoCollect = "🧲", BigHammer = "🔨" }

local TWEEN_FAST = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_POP = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local state = nil
local gui
local scales = {}
local refs = {}
local panels = {}
local openPanel = nil
local blur
local toastOrder = 0
local clickSound, hoverSound
local hatchToken = 0
local currentHatchId = nil

-- Base helpers ------------------------------------------------------------------

local function create(className, props, children)
	local inst = Instance.new(className)
	local parent = props.Parent
	for key, value in props do
		if key ~= "Parent" then
			inst[key] = value
		end
	end
	if children then
		for _, child in children do
			child.Parent = inst
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function corner(radius)
	return create("UICorner", { CornerRadius = UDim.new(0, radius or 12) })
end

local function round()
	return create("UICorner", { CornerRadius = UDim.new(1, 0) })
end

local function stroke(color, thickness, transparency)
	return create("UIStroke", {
		Color = color or BLACK,
		Thickness = thickness or 2,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

local function gradient(top, bottom, rotation)
	return create("UIGradient", { Color = ColorSequence.new(top, bottom), Rotation = rotation or 90 })
end

local function textStroke(thickness)
	return create("UIStroke", {
		Color = BLACK,
		Thickness = thickness or 2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
	})
end

local function label(props, outline)
	local defaults = {
		BackgroundTransparency = 1,
		Font = FONT,
		TextScaled = true,
		TextColor3 = WHITE,
	}
	for key, value in props do
		defaults[key] = value
	end
	local children = nil
	if outline ~= false then
		children = { textStroke(outline or 2) }
	end
	return create("TextLabel", defaults, children)
end

local function scaled(frame)
	local s = create("UIScale", { Parent = frame })
	table.insert(scales, s)
	return frame
end

local function updateScale()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local size = camera.ViewportSize
	local value = math.clamp(math.min(size.X / 1280, size.Y / 760), 0.5, 1.2)
	for _, s in scales do
		s.Scale = value
	end
end

local function playClick()
	if clickSound then
		clickSound:Play()
	end
end

-- Glossy button: wrapper (shadow + button) with hover / press scale animation.
-- Returns wrapper, button.
local function fancyButton(props, color)
	color = color or GREEN
	local wrapper = create("Frame", {
		Name = props.Name or "ButtonWrap",
		AnchorPoint = props.AnchorPoint or Vector2.new(0, 0),
		Position = props.Position or UDim2.new(),
		Size = props.Size or UDim2.fromOffset(140, 50),
		LayoutOrder = props.LayoutOrder or 0,
		BackgroundTransparency = 1,
		Parent = props.Parent,
	})
	local pop = create("UIScale", { Name = "Pop", Parent = wrapper })
	create("Frame", {
		Name = "Shadow",
		Position = UDim2.fromOffset(0, 5),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = BLACK,
		BackgroundTransparency = 0.55,
		Parent = wrapper,
	}, { corner(14) })
	local btn = create("TextButton", {
		Name = "Button",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		AutoButtonColor = false,
		Font = FONT,
		Text = props.Text or "",
		TextScaled = true,
		TextColor3 = WHITE,
		Parent = wrapper,
	}, {
		corner(14),
		stroke(BLACK, 3),
		textStroke(2),
		gradient(color:Lerp(WHITE, 0.3), color:Lerp(BLACK, 0.15)),
		create("UIPadding", {
			PaddingLeft = UDim.new(0, 8),
			PaddingRight = UDim.new(0, 8),
			PaddingTop = UDim.new(0, 6),
			PaddingBottom = UDim.new(0, 6),
		}),
	})
	-- Glossy shine on the top half
	create("Frame", {
		Name = "Shine",
		Position = UDim2.new(0, -4, 0, -3),
		Size = UDim2.new(1, 8, 0.45, 0),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.8,
		Parent = btn,
	}, { corner(10) })

	btn.MouseEnter:Connect(function()
		TweenService:Create(pop, TWEEN_FAST, { Scale = 1.06 }):Play()
		if hoverSound then
			hoverSound:Play()
		end
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(pop, TWEEN_FAST, { Scale = 1 }):Play()
	end)
	btn.MouseButton1Down:Connect(function()
		TweenService:Create(pop, TWEEN_FAST, { Scale = 0.92 }):Play()
	end)
	btn.MouseButton1Up:Connect(function()
		TweenService:Create(pop, TWEEN_POP, { Scale = 1 }):Play()
	end)
	btn:SetAttribute("Color", color)
	return wrapper, btn
end

local function setButtonColor(btn, color)
	local grad = btn:FindFirstChildOfClass("UIGradient")
	if grad then
		grad.Color = ColorSequence.new(color:Lerp(WHITE, 0.3), color:Lerp(BLACK, 0.15))
	end
end

local function setButton(btn, text, enabled, color)
	btn.Text = text
	if enabled then
		setButtonColor(btn, color or btn:GetAttribute("Color") or GREEN)
	else
		setButtonColor(btn, GREY)
	end
end

local function request(action)
	playClick()
	local ok, response = pcall(function()
		return Remotes.Request:InvokeServer(action)
	end)
	if ok and type(response) == "table" then
		local color = RED
		if response.Ok then
			color = GREEN
		end
		UI.Toast(response.Message, color)
	end
end

local function promptPurchase(kind, key)
	playClick()
	local entry
	if kind == "Pass" then
		entry = Config.GamePasses[key]
	else
		entry = Config.Products[key]
	end
	if not entry or entry.Id == 0 then
		UI.Toast("Coming soon!", GOLD)
		return
	end
	if kind == "Pass" then
		MarketplaceService:PromptGamePassPurchase(player, entry.Id)
	else
		MarketplaceService:PromptProductPurchase(player, entry.Id)
	end
end

-- 3D Meteorling inside a ViewportFrame
local function viewportModel(parent, id)
	local viewport = create("ViewportFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(170, 165, 200),
		LightColor = WHITE,
		LightDirection = Vector3.new(-1, -1.2, 1),
		Parent = parent,
	})
	local model = Visuals.CreatureModel({ id = id, hatched = true }, false, true)
	model:PivotTo(CFrame.new())
	model.Parent = viewport
	local extents = model:GetExtentsSize()
	local radius = math.max(extents.X, extents.Y, extents.Z)
	local camera = Instance.new("Camera")
	camera.FieldOfView = 35
	local eye = Vector3.new(radius * 0.55, radius * 0.25, -radius * 1.75)
	camera.CFrame = CFrame.lookAt(eye, Vector3.new(0, radius * 0.08, 0))
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	return viewport, model
end

-- Blur behind open panels
local function setBlur(on)
	if not blur then
		return
	end
	local size = 0
	if on then
		size = 14
	end
	TweenService:Create(blur, TweenInfo.new(0.25), { Size = size }):Play()
end

-- Top bar -------------------------------------------------------------------------

local function buildTopBar()
	local top = scaled(create("Frame", {
		Name = "TopBar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(380, 130),
		BackgroundTransparency = 1,
		Parent = gui,
	}))
	refs.TopBar = top

	-- Cash pill
	create("Frame", {
		Name = "CashShadow",
		Position = UDim2.fromOffset(0, 5),
		Size = UDim2.new(1, 0, 0, 74),
		BackgroundColor3 = BLACK,
		BackgroundTransparency = 0.55,
		Parent = top,
	}, { corner(37) })
	local cash = create("Frame", {
		Name = "Cash",
		Size = UDim2.new(1, 0, 0, 74),
		BackgroundColor3 = WHITE,
		Parent = top,
	}, {
		corner(37),
		stroke(Color3.fromRGB(90, 55, 0), 3),
		gradient(Color3.fromRGB(255, 232, 120), Color3.fromRGB(245, 160, 30)),
	})
	create("Frame", {
		Name = "Shine",
		Position = UDim2.new(0, 12, 0, 4),
		Size = UDim2.new(1, -24, 0, 26),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.7,
		Parent = cash,
	}, { corner(13) })
	local coin = create("Frame", {
		Name = "Coin",
		Position = UDim2.fromOffset(8, 7),
		Size = UDim2.fromOffset(60, 60),
		BackgroundColor3 = WHITE,
		Parent = cash,
	}, {
		round(),
		stroke(Color3.fromRGB(120, 70, 0), 3),
		gradient(Color3.fromRGB(255, 240, 150), Color3.fromRGB(230, 140, 20)),
	})
	label({ Size = UDim2.fromScale(1, 1), Text = "$", Parent = coin }, 3)
	refs.Coin = coin
	refs.Money = label({
		Name = "Money",
		Position = UDim2.new(0, 76, 0, 4),
		Size = UDim2.new(1, -92, 0, 42),
		Text = "$0",
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = cash,
	}, 3)
	refs.Income = label({
		Name = "Income",
		Position = UDim2.new(0, 78, 0, 44),
		Size = UDim2.new(1, -92, 0, 24),
		Text = "+$0/s",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(255, 255, 220),
		Parent = cash,
	}, 2)

	-- Speed bar
	local speed = create("Frame", {
		Name = "Speed",
		Position = UDim2.new(0, 24, 0, 86),
		Size = UDim2.new(1, -48, 0, 36),
		BackgroundColor3 = Color3.fromRGB(20, 18, 40),
		BackgroundTransparency = 0.1,
		ClipsDescendants = true,
		Parent = top,
	}, {
		round(),
		stroke(BLACK, 3),
	})
	local fill = create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0.05, 1),
		BackgroundColor3 = WHITE,
		Parent = speed,
	}, {
		round(),
		gradient(Color3.fromRGB(70, 220, 255), Color3.fromRGB(170, 90, 255), 0),
	})
	-- Moving shine across the fill
	local shimmer = create("UIGradient", {
		Color = ColorSequence.new(WHITE),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.42, 1),
			NumberSequenceKeypoint.new(0.5, 0.45),
			NumberSequenceKeypoint.new(0.58, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Offset = Vector2.new(-1, 0),
	})
	create("Frame", {
		Name = "Shimmer",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		Parent = fill,
	}, { round(), shimmer })
	TweenService:Create(shimmer, TweenInfo.new(1.6, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), {
		Offset = Vector2.new(1, 0),
	}):Play()
	refs.SpeedFill = fill
	refs.Speed = label({
		Name = "SpeedText",
		Position = UDim2.new(0, 10, 0, 4),
		Size = UDim2.new(1, -20, 1, -8),
		Text = "⚡ 16 Speed",
		ZIndex = 3,
		Parent = speed,
	}, 2)
end

-- Left menu -------------------------------------------------------------------

local function badge(parent)
	local b = create("Frame", {
		Name = "Badge",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -6, 0, 6),
		Size = UDim2.fromOffset(28, 28),
		BackgroundColor3 = RED,
		Visible = false,
		ZIndex = 5,
		Parent = parent,
	}, {
		round(),
		stroke(WHITE, 2),
	})
	label({ Size = UDim2.fromScale(1, 1), Text = "!", ZIndex = 6, Parent = b }, 1)
	local s = create("UIScale", { Parent = b })
	TweenService:Create(s, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		Scale = 1.2,
	}):Play()
	return b
end

local function buildMenu()
	local menu = scaled(create("Frame", {
		Name = "Menu",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(96, 340),
		BackgroundTransparency = 1,
		Parent = gui,
	}, {
		create("UIListLayout", {
			Padding = UDim.new(0, 14),
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Center,
		}),
	}))

	local entries = {
		{ Name = "Shop", Icon = "🛒", Color = Color3.fromRGB(60, 205, 95) },
		{ Name = "Index", Icon = "📖", Color = Color3.fromRGB(70, 145, 255) },
		{ Name = "Rebirth", Icon = "🌟", Color = Color3.fromRGB(175, 90, 255) },
	}
	refs.Badges = {}
	for i, entry in entries do
		local wrapper, btn = fancyButton({
			Name = entry.Name,
			LayoutOrder = i,
			Size = UDim2.fromOffset(92, 92),
			Text = "",
			Parent = menu,
		}, entry.Color)
		label({
			Position = UDim2.new(0, 0, 0, -2),
			Size = UDim2.new(1, 0, 0.66, 0),
			Text = entry.Icon,
			Parent = btn,
		}, false)
		label({
			Position = UDim2.new(0, 0, 0.62, 0),
			Size = UDim2.new(1, 0, 0.36, 0),
			Text = entry.Name,
			Parent = btn,
		}, 2)
		refs.Badges[entry.Name] = badge(wrapper)
		btn.MouseButton1Click:Connect(function()
			playClick()
			UI.TogglePanel(entry.Name)
		end)
	end
end

-- Panels ----------------------------------------------------------------------

local function makePanel(name, title, color)
	local panel = scaled(create("Frame", {
		Name = name .. "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.53),
		Size = UDim2.fromOffset(640, 460),
		BackgroundColor3 = WHITE,
		Visible = false,
		Parent = gui,
	}, {
		corner(24),
		stroke(BLACK, 4),
		gradient(PANEL_TOP, PANEL_BOTTOM),
	}))
	local pop = create("UIScale", { Name = "Pop", Parent = panel })

	local header = create("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 64),
		BackgroundColor3 = WHITE,
		Parent = panel,
	}, {
		corner(24),
		gradient(color:Lerp(WHITE, 0.25), color:Lerp(BLACK, 0.1)),
	})
	-- Square off the bottom corners of the header
	create("Frame", {
		Position = UDim2.new(0, 0, 1, -24),
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Parent = header,
	}, { gradient(color:Lerp(WHITE, 0.12), color:Lerp(BLACK, 0.1)) })
	label({
		Position = UDim2.new(0, 22, 0, 10),
		Size = UDim2.new(1, -110, 1, -20),
		Text = title,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = header,
	}, 3)
	local _, close = fancyButton({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, -2),
		Size = UDim2.fromOffset(48, 48),
		Text = "✕",
		Parent = header,
	}, RED)
	close.MouseButton1Click:Connect(function()
		playClick()
		UI.TogglePanel(name)
	end)

	local content = create("Frame", {
		Name = "Content",
		Position = UDim2.new(0, 16, 0, 76),
		Size = UDim2.new(1, -32, 1, -90),
		BackgroundTransparency = 1,
		Parent = panel,
	})
	panels[name] = { Frame = panel, Pop = pop }
	return content
end

local function scrolling(parent)
	return create("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = Color3.fromRGB(180, 160, 255),
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = parent,
	}, {
		create("UIPadding", {
			PaddingLeft = UDim.new(0, 4),
			PaddingRight = UDim.new(0, 14),
			PaddingTop = UDim.new(0, 6),
			PaddingBottom = UDim.new(0, 12),
		}),
	})
end

local function sectionHeader(parent, order, text)
	label({
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 32),
		Text = text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(255, 220, 120),
		Parent = parent,
	}, 2)
end

local function shopRow(parent, order, icon, iconColor, title, description, buttonColor, onClick)
	local row = create("Frame", {
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 82),
		BackgroundColor3 = WHITE,
		Parent = parent,
	}, {
		corner(16),
		stroke(BLACK, 2, 0.3),
		gradient(Color3.fromRGB(66, 58, 104), Color3.fromRGB(44, 38, 72)),
	})
	local iconFrame = create("Frame", {
		Position = UDim2.fromOffset(10, 11),
		Size = UDim2.fromOffset(60, 60),
		BackgroundColor3 = WHITE,
		Parent = row,
	}, {
		corner(14),
		stroke(BLACK, 2),
		gradient(iconColor:Lerp(WHITE, 0.3), iconColor:Lerp(BLACK, 0.2)),
	})
	label({ Size = UDim2.fromScale(1, 1), Text = icon, Parent = iconFrame }, false)
	local titleLabel = label({
		Position = UDim2.new(0, 82, 0, 10),
		Size = UDim2.new(1, -250, 0, 30),
		Text = title,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	}, 2)
	local descLabel = label({
		Position = UDim2.new(0, 82, 0, 44),
		Size = UDim2.new(1, -250, 0, 24),
		Text = description,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(200, 195, 230),
		Parent = row,
	}, false)
	local _, btn = fancyButton({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, -2),
		Size = UDim2.fromOffset(150, 54),
		Text = "...",
		Parent = row,
	}, buttonColor)
	btn.MouseButton1Click:Connect(onClick)
	return { Title = titleLabel, Desc = descLabel, Button = btn }
end

local function buildShop()
	local content = makePanel("Shop", "🛒 Shop", Color3.fromRGB(60, 205, 95))
	local scroll = scrolling(content)
	create("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroll })

	local order = 0
	local function nextOrder()
		order += 1
		return order
	end

	sectionHeader(scroll, nextOrder(), "⬆️ Upgrades")
	refs.BootsRow = shopRow(scroll, nextOrder(), "👟", Color3.fromRGB(70, 200, 255), "Speed Boots", "", GREEN, function()
		request("BuyBoots")
	end)
	refs.PedestalRow = shopRow(scroll, nextOrder(), "🏛️", Color3.fromRGB(220, 220, 240), "Extra Pedestal", "", GREEN, function()
		request("BuyPedestal")
	end)

	sectionHeader(scroll, nextOrder(), "🚀 Boosts")
	for _, key in PRODUCT_ORDER do
		local product = Config.Products[key]
		local row = shopRow(
			scroll,
			nextOrder(),
			PRODUCT_ICONS[key] or "⭐",
			Color3.fromRGB(255, 160, 60),
			product.Name,
			product.Description,
			Color3.fromRGB(0, 180, 110),
			function()
				promptPurchase("Product", key)
			end
		)
		row.Button.Text = "R$ " .. product.Price
	end

	sectionHeader(scroll, nextOrder(), "💎 Game Passes")
	refs.PassRows = {}
	for _, key in PASS_ORDER do
		local pass = Config.GamePasses[key]
		local row = shopRow(
			scroll,
			nextOrder(),
			PASS_ICONS[key] or "⭐",
			GOLD,
			pass.Name,
			pass.Description,
			Color3.fromRGB(255, 165, 30),
			function()
				if state and state.Passes and state.Passes[key] then
					return
				end
				promptPurchase("Pass", key)
			end
		)
		row.Button.Text = "R$ " .. pass.Price
		refs.PassRows[key] = row
	end
end

local function buildIndex()
	local content = makePanel("Index", "📖 Meteorling Index", Color3.fromRGB(70, 145, 255))
	refs.IndexHeader = label({
		Size = UDim2.new(1, 0, 0, 30),
		Text = "Discovered 0/" .. #Config.Meteorlings,
		TextColor3 = Color3.fromRGB(180, 220, 255),
		Parent = content,
	}, 2)
	local holder = create("Frame", {
		Position = UDim2.new(0, 0, 0, 38),
		Size = UDim2.new(1, 0, 1, -38),
		BackgroundTransparency = 1,
		Parent = content,
	})
	local scroll = scrolling(holder)
	create("UIGridLayout", {
		CellSize = UDim2.fromOffset(134, 168),
		CellPadding = UDim2.fromOffset(10, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = scroll,
	})

	refs.IndexCards = {}
	for i, info in Config.Meteorlings do
		local rarity = Util.GetRarity(info.Rarity)
		local card = create("Frame", {
			LayoutOrder = i,
			BackgroundColor3 = WHITE,
			Parent = scroll,
		}, {
			corner(16),
			stroke(rarity.Color, 3),
			gradient(rarity.Color:Lerp(PANEL_TOP, 0.55), PANEL_BOTTOM),
		})
		local view = create("Frame", {
			Position = UDim2.fromOffset(6, 6),
			Size = UDim2.new(1, -12, 0, 96),
			BackgroundTransparency = 1,
			Parent = card,
		})
		local viewport = viewportModel(view, info.Id)
		viewport.ImageColor3 = BLACK
		viewport.ImageTransparency = 0.25
		local name = label({
			Position = UDim2.new(0, 4, 0, 104),
			Size = UDim2.new(1, -8, 0, 22),
			Text = "???",
			Parent = card,
		}, 2)
		label({
			Position = UDim2.new(0, 4, 0, 126),
			Size = UDim2.new(1, -8, 0, 18),
			Text = info.Rarity,
			TextColor3 = rarity.Color,
			Parent = card,
		}, 2)
		local income = label({
			Position = UDim2.new(0, 4, 0, 145),
			Size = UDim2.new(1, -8, 0, 17),
			Text = "",
			TextColor3 = Color3.fromRGB(140, 255, 140),
			Parent = card,
		}, 2)
		refs.IndexCards[info.Id] = { Viewport = viewport, Name = name, Income = income, Info = info }
	end
end

local function buildRebirth()
	local content = makePanel("Rebirth", "🌟 Rebirth", Color3.fromRGB(175, 90, 255))
	local star = label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.fromOffset(90, 80),
		Text = "🌟",
		Parent = content,
	}, false)
	TweenService:Create(star, TweenInfo.new(2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		Rotation = 12,
	}):Play()
	refs.RebirthCount = label({
		Position = UDim2.new(0, 0, 0, 80),
		Size = UDim2.new(1, 0, 0, 40),
		Text = "Rebirths: 0",
		Parent = content,
	}, 3)
	refs.RebirthMult = label({
		Position = UDim2.new(0, 0, 0, 124),
		Size = UDim2.new(1, 0, 0, 32),
		Text = "Income x1 → x1.5",
		TextColor3 = Color3.fromRGB(140, 255, 140),
		Parent = content,
	}, 2)
	refs.RebirthCost = label({
		Position = UDim2.new(0, 0, 0, 160),
		Size = UDim2.new(1, 0, 0, 30),
		Text = "Cost: $0",
		TextColor3 = Color3.fromRGB(255, 220, 120),
		Parent = content,
	}, 2)
	local bar = create("Frame", {
		Position = UDim2.new(0.1, 0, 0, 198),
		Size = UDim2.new(0.8, 0, 0, 28),
		BackgroundColor3 = Color3.fromRGB(20, 18, 40),
		ClipsDescendants = true,
		Parent = content,
	}, { round(), stroke(BLACK, 3) })
	refs.RebirthFill = create("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = WHITE,
		Parent = bar,
	}, { round(), gradient(Color3.fromRGB(220, 150, 255), Color3.fromRGB(140, 60, 240), 0) })
	refs.RebirthPercent = label({
		Size = UDim2.fromScale(1, 1),
		Text = "0%",
		ZIndex = 2,
		Parent = bar,
	}, 2)
	label({
		Position = UDim2.new(0, 0, 0, 234),
		Size = UDim2.new(1, 0, 0, 44),
		Text = "Resets cash, speed and boots.\nKeeps your Meteorlings and Index!",
		TextColor3 = Color3.fromRGB(200, 195, 230),
		Parent = content,
	}, false)
	local _, btn = fancyButton({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.fromOffset(280, 70),
		Text = "REBIRTH",
		Parent = content,
	}, Color3.fromRGB(175, 90, 255))
	refs.RebirthButton = btn
	btn.MouseButton1Click:Connect(function()
		request("Rebirth")
	end)
end

-- Overlays: toasts, banner, timers, carry, popups, hatch card -----------------

local function pill(props, color)
	local frame = create("Frame", {
		Name = props.Name,
		AnchorPoint = props.AnchorPoint or Vector2.new(0, 0),
		Position = props.Position or UDim2.new(),
		Size = props.Size,
		LayoutOrder = props.LayoutOrder or 0,
		BackgroundColor3 = WHITE,
		Visible = props.Visible ~= false,
		Parent = props.Parent,
	}, {
		round(),
		stroke(BLACK, 3),
		gradient(color:Lerp(PANEL_TOP, 0.55), PANEL_BOTTOM),
	})
	local text = label({
		Position = UDim2.new(0, 14, 0, 4),
		Size = UDim2.new(1, -28, 1, -8),
		Text = props.Text or "",
		TextColor3 = props.TextColor or WHITE,
		Parent = frame,
	}, 2)
	return frame, text
end

local function buildOverlay()
	refs.Toasts = scaled(create("Frame", {
		Name = "Toasts",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 150),
		Size = UDim2.fromOffset(560, 260),
		BackgroundTransparency = 1,
		Parent = gui,
	}, {
		create("UIListLayout", {
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
		}),
	}))

	-- Event banner
	local banner = scaled(create("Frame", {
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.2, 0),
		Size = UDim2.fromOffset(760, 130),
		BackgroundColor3 = WHITE,
		Visible = false,
		Parent = gui,
	}, {
		corner(26),
		stroke(BLACK, 4),
	}))
	refs.BannerGradient = gradient(Color3.fromRGB(255, 150, 60), Color3.fromRGB(120, 40, 160))
	refs.BannerGradient.Parent = banner
	refs.BannerPop = create("UIScale", { Name = "Pop", Parent = banner })
	refs.Banner = banner
	refs.BannerTitle = label({
		Position = UDim2.new(0, 16, 0, 8),
		Size = UDim2.new(1, -32, 0, 58),
		Text = "",
		Parent = banner,
	}, 3)
	refs.BannerSub = label({
		Position = UDim2.new(0, 16, 0, 68),
		Size = UDim2.new(1, -32, 0, 28),
		Text = "",
		TextColor3 = Color3.fromRGB(255, 245, 230),
		Parent = banner,
	}, 2)
	refs.BannerTimer = label({
		Position = UDim2.new(0, 16, 0, 98),
		Size = UDim2.new(1, -32, 0, 24),
		Text = "",
		TextColor3 = Color3.fromRGB(255, 230, 130),
		Parent = banner,
	}, 2)

	-- Boost timers (top right)
	refs.Timers = scaled(create("Frame", {
		Name = "Timers",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 64),
		Size = UDim2.fromOffset(250, 120),
		BackgroundTransparency = 1,
		Parent = gui,
	}, {
		create("UIListLayout", {
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
		}),
	}))
	refs.ShowerTimer, refs.ShowerText = pill({
		Name = "Shower",
		Size = UDim2.fromOffset(240, 40),
		LayoutOrder = 1,
		Visible = false,
		TextColor = Color3.fromRGB(255, 190, 110),
		Parent = refs.Timers,
	}, Color3.fromRGB(255, 140, 60))
	refs.LuckTimer, refs.LuckText = pill({
		Name = "Luck",
		Size = UDim2.fromOffset(240, 40),
		LayoutOrder = 2,
		Visible = false,
		TextColor = Color3.fromRGB(150, 255, 160),
		Parent = refs.Timers,
	}, Color3.fromRGB(80, 230, 110))

	-- Carry status
	local carry, carryText = pill({
		Name = "Carry",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -100),
		Size = UDim2.fromOffset(600, 50),
		Visible = false,
		Parent = gui,
	}, Color3.fromRGB(90, 255, 140))
	scaled(carry)
	refs.Carry = carry
	refs.CarryText = carryText
	local carryPulse = create("UIScale", { Name = "Pulse", Parent = carryText })
	TweenService:Create(carryPulse, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		Scale = 1.05,
	}):Play()

	-- Big text popup
	refs.Popup = scaled(label({
		Name = "Popup",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.38),
		Size = UDim2.fromOffset(720, 90),
		Text = "",
		Visible = false,
		Parent = gui,
	}, 4))
	refs.PopupPop = create("UIScale", { Name = "Pop", Parent = refs.Popup })

	-- Hatch card with a spinning 3D Meteorling
	local hatch = scaled(create("Frame", {
		Name = "HatchCard",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(340, 400),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	}))
	refs.HatchPop = create("UIScale", { Name = "Pop", Parent = hatch })
	local rays = create("Frame", {
		Name = "Rays",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.fromOffset(440, 440),
		BackgroundTransparency = 1,
		Parent = hatch,
	})
	for i = 0, 7 do
		create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0, 46, 1, 0),
			Rotation = i * 22.5,
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.75,
			BorderSizePixel = 0,
			Parent = rays,
		}, {
			create("UIGradient", {
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(0.5, 0),
					NumberSequenceKeypoint.new(1, 1),
				}),
				Rotation = 90,
			}),
		})
	end
	refs.HatchRays = rays
	local card = create("Frame", {
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 30),
		Size = UDim2.fromOffset(300, 360),
		BackgroundColor3 = WHITE,
		Parent = hatch,
	}, {
		corner(24),
		stroke(BLACK, 4),
	})
	refs.HatchGradient = gradient(PANEL_TOP, PANEL_BOTTOM)
	refs.HatchGradient.Parent = card
	refs.HatchTitle = label({
		Position = UDim2.new(0, 10, 0, 8),
		Size = UDim2.new(1, -20, 0, 40),
		Text = "HATCHED!",
		Parent = card,
	}, 3)
	refs.HatchView = create("Frame", {
		Position = UDim2.new(0, 20, 0, 50),
		Size = UDim2.new(1, -40, 0, 190),
		BackgroundTransparency = 1,
		Parent = card,
	})
	refs.HatchName = label({
		Position = UDim2.new(0, 10, 0, 244),
		Size = UDim2.new(1, -20, 0, 38),
		Text = "",
		Parent = card,
	}, 3)
	refs.HatchRarity = label({
		Position = UDim2.new(0, 10, 0, 284),
		Size = UDim2.new(1, -20, 0, 28),
		Text = "",
		Parent = card,
	}, 2)
	refs.HatchIncome = label({
		Position = UDim2.new(0, 10, 0, 316),
		Size = UDim2.new(1, -20, 0, 28),
		Text = "",
		TextColor3 = Color3.fromRGB(140, 255, 140),
		Parent = card,
	}, 2)
	local newBadge, newText = pill({
		Name = "NewBadge",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -10, 0, 30),
		Size = UDim2.fromOffset(110, 44),
		Text = "NEW!",
		Visible = false,
		Parent = hatch,
	}, RED)
	newBadge.Rotation = 12
	newText.TextColor3 = Color3.fromRGB(255, 255, 140)
	refs.HatchNew = newBadge
	refs.HatchNewPop = create("UIScale", { Parent = newBadge })
	refs.Hatch = hatch

	-- Coin burst layer
	refs.Coins = create("Frame", {
		Name = "Coins",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	refs.CoinPop = create("UIScale", { Parent = refs.Coin })

	refs.Flash = create("Frame", {
		Name = "Flash",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = RED,
		BackgroundTransparency = 1,
		Active = false,
		Parent = gui,
	})
end

-- Public API -----------------------------------------------------------------------

function UI.Toast(text, color)
	if not refs.Toasts then
		return
	end
	toastOrder += 1
	color = color or WHITE
	local holder = create("Frame", {
		LayoutOrder = toastOrder,
		Size = UDim2.fromOffset(540, 38),
		BackgroundTransparency = 1,
		Parent = refs.Toasts,
	})
	local toast = create("Frame", {
		Position = UDim2.fromOffset(0, -20),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 1,
		Parent = holder,
	}, {
		round(),
		gradient(Color3.fromRGB(46, 40, 80), Color3.fromRGB(24, 20, 44)),
	})
	local accent = create("Frame", {
		Position = UDim2.fromOffset(9, 9),
		Size = UDim2.fromOffset(20, 20),
		BackgroundColor3 = color,
		BackgroundTransparency = 1,
		Parent = toast,
	}, { round() })
	local textLabel = label({
		Position = UDim2.fromOffset(38, 4),
		Size = UDim2.new(1, -50, 1, -8),
		Text = text,
		TextColor3 = color,
		TextTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = toast,
	}, 2)
	local outline = textLabel:FindFirstChildOfClass("UIStroke")
	if outline then
		outline.Transparency = 1
		TweenService:Create(outline, TWEEN_POP, { Transparency = 0 }):Play()
	end
	TweenService:Create(toast, TWEEN_POP, { Position = UDim2.fromOffset(0, 0), BackgroundTransparency = 0.12 }):Play()
	TweenService:Create(accent, TWEEN_POP, { BackgroundTransparency = 0 }):Play()
	TweenService:Create(textLabel, TWEEN_POP, { TextTransparency = 0 }):Play()

	local holders = {}
	for _, child in refs.Toasts:GetChildren() do
		if child:IsA("Frame") then
			table.insert(holders, child)
		end
	end
	table.sort(holders, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	while #holders > 5 do
		table.remove(holders, 1):Destroy()
	end

	task.delay(3.5, function()
		if not holder.Parent then
			return
		end
		local info = TweenInfo.new(0.35)
		TweenService:Create(toast, info, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(accent, info, { BackgroundTransparency = 1 }):Play()
		if outline then
			TweenService:Create(outline, info, { Transparency = 1 }):Play()
		end
		local fade = TweenService:Create(textLabel, info, { TextTransparency = 1 })
		fade:Play()
		fade.Completed:Wait()
		holder:Destroy()
	end)
end

local bannerToken = 0
function UI.Banner(data)
	bannerToken += 1
	local token = bannerToken
	local color = data.Color or Color3.fromRGB(255, 150, 60)
	refs.BannerTitle.Text = data.Title or ""
	refs.BannerSub.Text = data.Subtitle or ""
	refs.BannerGradient.Color = ColorSequence.new(color:Lerp(WHITE, 0.15), color:Lerp(Color3.fromRGB(60, 20, 90), 0.6))
	refs.Banner.Visible = true
	refs.BannerPop.Scale = 0.4
	TweenService:Create(refs.BannerPop, TweenInfo.new(0.5, Enum.EasingStyle.Back), { Scale = 1 }):Play()

	task.spawn(function()
		local shownUntil = os.clock() + 8
		while token == bannerToken and os.clock() < shownUntil do
			local left = (data.EndsAt or 0) - workspace:GetServerTimeNow()
			if left > 0 then
				refs.BannerTimer.Text = "⏱ " .. Util.FormatTime(left)
			else
				refs.BannerTimer.Text = ""
			end
			task.wait(0.25)
		end
		if token == bannerToken then
			local shrink = TweenService:Create(refs.BannerPop, TweenInfo.new(0.25), { Scale = 0 })
			shrink:Play()
			shrink.Completed:Wait()
			if token == bannerToken then
				refs.Banner.Visible = false
			end
		end
	end)
end

local popupToken = 0
function UI.Popup(text, color)
	popupToken += 1
	local token = popupToken
	local popup = refs.Popup
	popup.Text = text
	popup.TextColor3 = color or WHITE
	popup.TextTransparency = 0
	local outline = popup:FindFirstChildOfClass("UIStroke")
	if outline then
		outline.Transparency = 0
	end
	popup.Visible = true
	refs.PopupPop.Scale = 0.3
	TweenService:Create(refs.PopupPop, TweenInfo.new(0.45, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	task.delay(1.8, function()
		if token ~= popupToken then
			return
		end
		local info = TweenInfo.new(0.4)
		if outline then
			TweenService:Create(outline, info, { Transparency = 1 }):Play()
		end
		local fade = TweenService:Create(popup, info, { TextTransparency = 1 })
		fade:Play()
		fade.Completed:Wait()
		if token == popupToken then
			popup.Visible = false
		end
	end)
end

function UI.HatchCard(id, rarityName, mutation)
	hatchToken += 1
	local token = hatchToken
	currentHatchId = id
	local rarity = Util.GetRarity(rarityName)
	local info = Config.MeteorlingById[id]

	refs.HatchView:ClearAllChildren()
	local _, model = viewportModel(refs.HatchView, id)
	refs.HatchName.Text = id
	refs.HatchRarity.Text = rarityName
	refs.HatchRarity.TextColor3 = rarity.Color
	local income = 0
	if info then
		income = info.Income
	end
	local title = "HATCHED!"
	refs.HatchTitle.TextColor3 = WHITE
	if mutation and Config.MutationByName[mutation] then
		local m = Config.MutationByName[mutation]
		income *= m.Mult
		title = string.upper(mutation) .. " HATCH!"
		refs.HatchTitle.TextColor3 = m.Color
	end
	refs.HatchTitle.Text = title
	refs.HatchIncome.Text = Util.FormatMoney(income) .. "/s"
	refs.HatchGradient.Color = ColorSequence.new(rarity.Color:Lerp(PANEL_TOP, 0.45), PANEL_BOTTOM)
	refs.HatchNew.Visible = false
	refs.Hatch.Visible = true
	refs.HatchPop.Scale = 0.2
	TweenService:Create(refs.HatchPop, TweenInfo.new(0.55, Enum.EasingStyle.Back), { Scale = 1 }):Play()

	-- Spin the model and the light rays
	local started = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		if token ~= hatchToken or not model.Parent then
			connection:Disconnect()
			return
		end
		local t = os.clock() - started
		model:PivotTo(CFrame.new(0, math.abs(math.sin(t * 4)) * 0.3, 0) * CFrame.Angles(0, t * 1.6, 0))
		refs.HatchRays.Rotation = t * 25
	end)

	task.delay(3.2, function()
		if token ~= hatchToken then
			return
		end
		local shrink = TweenService:Create(
			refs.HatchPop,
			TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In),
			{ Scale = 0 }
		)
		shrink:Play()
		shrink.Completed:Wait()
		if token == hatchToken then
			refs.Hatch.Visible = false
			currentHatchId = nil
		end
	end)
end

-- Shows the NEW! badge if the hatch card for this id is on screen. Returns true if it did.
function UI.MarkNew(id)
	if currentHatchId == id and refs.Hatch.Visible then
		refs.HatchNew.Visible = true
		refs.HatchNewPop.Scale = 0
		TweenService:Create(refs.HatchNewPop, TweenInfo.new(0.4, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		return true
	end
	return false
end

function UI.Flash(color)
	refs.Flash.BackgroundColor3 = color or RED
	refs.Flash.BackgroundTransparency = 0.6
	TweenService:Create(refs.Flash, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
end

-- Floating "+$123" near the top bar
function UI.FloatText(text, color, fromSpeed)
	local yOffset = 40
	if fromSpeed then
		yOffset = 104
	end
	local float = label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, math.random(-70, 70), 0, yOffset),
		Size = UDim2.fromOffset(240, 40),
		Text = text,
		TextColor3 = color or WHITE,
		ZIndex = 20,
		Parent = refs.TopBar,
	}, 3)
	local s = create("UIScale", { Scale = 0.4, Parent = float })
	TweenService:Create(s, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	local outline = float:FindFirstChildOfClass("UIStroke")
	local info = TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	if outline then
		TweenService:Create(outline, info, { Transparency = 1 }):Play()
	end
	local tween = TweenService:Create(float, info, {
		Position = float.Position + UDim2.fromOffset(0, 70),
		TextTransparency = 1,
	})
	tween:Play()
	tween.Completed:Connect(function()
		float:Destroy()
	end)
end

-- Coins fly from the middle of the screen into the cash counter
function UI.CoinBurst()
	local layer = refs.Coins
	local camera = workspace.CurrentCamera
	if not layer or not camera or not refs.Coin then
		return
	end
	local target = refs.Coin.AbsolutePosition + refs.Coin.AbsoluteSize / 2
	local center = camera.ViewportSize / 2
	for i = 1, 8 do
		local coin = create("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(center.X + math.random(-120, 120), center.Y + math.random(-60, 80)),
			Size = UDim2.fromOffset(34, 34),
			BackgroundColor3 = GOLD,
			Text = "$",
			Font = FONT,
			TextScaled = true,
			TextColor3 = Color3.fromRGB(120, 70, 0),
			Parent = layer,
		}, { round(), stroke(Color3.fromRGB(120, 70, 0), 2) })
		local tween = TweenService:Create(
			coin,
			TweenInfo.new(0.55 + i * 0.04, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Position = UDim2.fromOffset(target.X, target.Y), Size = UDim2.fromOffset(16, 16) }
		)
		tween:Play()
		tween.Completed:Connect(function()
			coin:Destroy()
		end)
	end
	task.delay(0.6, function()
		refs.CoinPop.Scale = 1.3
		TweenService:Create(refs.CoinPop, TWEEN_POP, { Scale = 1 }):Play()
	end)
end

function UI.TogglePanel(name)
	for panelName, panel in panels do
		if panelName == name and not panel.Frame.Visible then
			panel.Frame.Visible = true
			panel.Pop.Scale = 0.6
			TweenService:Create(panel.Pop, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
			openPanel = panelName
		elseif panel.Frame.Visible then
			panel.Frame.Visible = false
			if openPanel == panelName then
				openPanel = nil
			end
		end
	end
	setBlur(openPanel ~= nil)
end

-- State ---------------------------------------------------------------------------

function UI.Update(newState)
	state = newState

	refs.Money.Text = Util.FormatMoney(state.Money)
	local incomeText = "+" .. Util.FormatMoney(state.Income) .. "/s"
	if state.Bank >= 1 and not state.Passes.AutoCollect then
		incomeText ..= "  •  " .. Util.FormatMoney(state.Bank) .. " at base"
	end
	refs.Income.Text = incomeText

	local speedText = "⚡ " .. state.Speed .. " Speed   +" .. state.PadRate .. "/s on pad"
	if state.Speed >= state.MaxSpeed then
		speedText = "⚡ " .. state.Speed .. " Speed   MAX!"
	end
	refs.Speed.Text = speedText
	TweenService:Create(refs.SpeedFill, TWEEN_FAST, {
		Size = UDim2.fromScale(math.clamp(state.Speed / state.MaxSpeed, 0.05, 1), 1),
	}):Play()

	-- Shop
	local boots = refs.BootsRow
	boots.Title.Text = "Speed Boots  Lv " .. state.Boots .. "/" .. state.BootsMax
	local canBoots = state.BootsCost ~= nil and state.Money >= state.BootsCost
	if state.BootsCost then
		boots.Desc.Text = "Speed Pad +" .. state.PadRate .. "/s  →  more per level"
		setButton(boots.Button, Util.FormatMoney(state.BootsCost), canBoots)
	else
		boots.Desc.Text = "Speed Pad +" .. state.PadRate .. "/s"
		setButton(boots.Button, "MAX", false)
	end

	local pedestal = refs.PedestalRow
	pedestal.Title.Text = "Extra Pedestal  " .. state.Pedestals .. "/" .. state.MaxBuyable
	pedestal.Desc.Text = "Slots used: " .. state.Used .. "/" .. state.PedestalsTotal
	local canPedestal = state.PedestalCost ~= nil and state.Money >= state.PedestalCost
	if state.PedestalCost then
		setButton(pedestal.Button, Util.FormatMoney(state.PedestalCost), canPedestal)
	else
		setButton(pedestal.Button, "MAX", false)
	end

	for key, row in refs.PassRows do
		if state.Passes[key] then
			setButton(row.Button, "OWNED ✓", false)
		end
	end

	-- Index
	refs.IndexHeader.Text = "Discovered "
		.. state.IndexCount
		.. "/"
		.. #Config.Meteorlings
		.. "   •   +"
		.. math.floor(state.IndexCount * Config.IndexBonusPerEntry * 100)
		.. "% income"
	for id, card in refs.IndexCards do
		if state.Index[id] then
			card.Viewport.ImageColor3 = WHITE
			card.Viewport.ImageTransparency = 0
			card.Name.Text = id
			card.Income.Text = Util.FormatMoney(card.Info.Income) .. "/s"
		else
			card.Viewport.ImageColor3 = BLACK
			card.Viewport.ImageTransparency = 0.25
			card.Name.Text = "???"
			card.Income.Text = ""
		end
	end

	-- Rebirth
	local canRebirth = state.Money >= state.RebirthCost
	local progress = math.clamp(state.Money / state.RebirthCost, 0, 1)
	refs.RebirthCount.Text = "Rebirths: " .. state.Rebirths
	refs.RebirthMult.Text = "Income bonus x" .. state.RebirthMult .. "  →  x" .. state.NextRebirthMult
	refs.RebirthCost.Text = "Cost: " .. Util.FormatMoney(state.RebirthCost)
	refs.RebirthFill.Size = UDim2.fromScale(math.max(progress, 0.03), 1)
	refs.RebirthPercent.Text = math.floor(progress * 100) .. "%"
	setButton(refs.RebirthButton, "REBIRTH", canRebirth, Color3.fromRGB(175, 90, 255))

	-- "!" badges when something is affordable
	refs.Badges.Shop.Visible = canBoots or canPedestal
	refs.Badges.Rebirth.Visible = canRebirth
end

function UI.UpdateCarry()
	local id = player:GetAttribute("Carrying")
	if not id then
		refs.Carry.Visible = false
		return
	end
	local info = Config.MeteorlingById[id]
	local rarity = Util.GetRarity(info and info.Rarity or "Common")
	if player:GetAttribute("CarryStolen") then
		refs.CarryText.Text = "😈 STOLEN " .. id .. "! Run home before they bonk you!"
	else
		refs.CarryText.Text = "☄️ " .. rarity.Name .. " Meteor! Follow the beam home!"
	end
	refs.CarryText.TextColor3 = rarity.Color
	if rarity.Name == "Secret" then
		refs.CarryText.TextColor3 = WHITE
	end
	local grad = refs.Carry:FindFirstChildOfClass("UIGradient")
	if grad then
		grad.Color = ColorSequence.new(rarity.Color:Lerp(PANEL_TOP, 0.55), PANEL_BOTTOM)
	end
	refs.Carry.Visible = true
end

local function timerLoop()
	while true do
		task.wait(0.5)
		if state then
			local now = workspace:GetServerTimeNow()
			local showerLeft = (state.ShowerUntil or 0) - now
			refs.ShowerTimer.Visible = showerLeft > 0
			if showerLeft > 0 then
				refs.ShowerText.Text = "☄️ Shower " .. Util.FormatTime(showerLeft)
			end
			local luckLeft = (state.LuckUntil or 0) - now
			refs.LuckTimer.Visible = luckLeft > 0
			if luckLeft > 0 then
				refs.LuckText.Text = "🍀 2x Luck " .. Util.FormatTime(luckLeft)
			end
		end
	end
end

function UI.Init()
	gui = create("ScreenGui", {
		Name = "MeteorHUD",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})

	clickSound = create("Sound", {
		Name = "Click",
		SoundId = "rbxasset://sounds/electronicpingshort.wav",
		Volume = 0.35,
		Parent = SoundService,
	})
	hoverSound = create("Sound", {
		Name = "Hover",
		SoundId = "rbxasset://sounds/clickfast.wav",
		Volume = 0.15,
		Parent = SoundService,
	})

	local camera = workspace.CurrentCamera
	if camera then
		blur = create("BlurEffect", { Name = "PanelBlur", Size = 0, Parent = camera })
	end

	buildTopBar()
	buildMenu()
	buildShop()
	buildIndex()
	buildRebirth()
	buildOverlay()

	updateScale()
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	end

	player:GetAttributeChangedSignal("Carrying"):Connect(UI.UpdateCarry)
	player:GetAttributeChangedSignal("CarryStolen"):Connect(UI.UpdateCarry)
	UI.UpdateCarry()

	task.spawn(timerLoop)
end

return UI
