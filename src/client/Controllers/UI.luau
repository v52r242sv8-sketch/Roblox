-- UI: the whole HUD built in code. Cash, speed, side menu, Shop / Index / Rebirth
-- panels, toasts, event banner and popups. Works on PC and mobile (auto scale).

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)

local player = Players.LocalPlayer

local UI = {}

local FONT = Enum.Font.FredokaOne
local WHITE = Color3.new(1, 1, 1)
local DARK = Color3.fromRGB(24, 22, 38)
local GREEN = Color3.fromRGB(70, 210, 100)
local RED = Color3.fromRGB(240, 80, 80)

local PRODUCT_ORDER = { "SpeedBoost", "InstantHatch", "Luck", "MeteorShower", "GoldenComet" }
local PASS_ORDER = { "DoubleMoney", "DoubleSpeed", "VIP", "AutoCollect", "BigHammer" }

local state = nil
local gui
local scales = {}
local refs = {}
local panels = {}
local toastOrder = 0
local clickSound

-- Helpers ---------------------------------------------------------------------

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

local function stroke(color, thickness)
	return create("UIStroke", {
		Color = color or Color3.new(0, 0, 0),
		Thickness = thickness or 2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

local function gradient(top, bottom)
	return create("UIGradient", { Color = ColorSequence.new(top, bottom), Rotation = 90 })
end

local function label(props)
	local defaults = {
		BackgroundTransparency = 1,
		Font = FONT,
		TextScaled = true,
		TextColor3 = WHITE,
		TextStrokeTransparency = 0.3,
	}
	for key, value in props do
		defaults[key] = value
	end
	return create("TextLabel", defaults)
end

local function button(props, color)
	local defaults = {
		BackgroundColor3 = color or GREEN,
		Font = FONT,
		TextScaled = true,
		TextColor3 = WHITE,
		TextStrokeTransparency = 0.3,
		AutoButtonColor = true,
	}
	for key, value in props do
		defaults[key] = value
	end
	local btn = create("TextButton", defaults, {
		corner(10),
		stroke(Color3.new(0, 0, 0), 2),
		create("UIPadding", {
			PaddingLeft = UDim.new(0, 6),
			PaddingRight = UDim.new(0, 6),
			PaddingTop = UDim.new(0, 4),
			PaddingBottom = UDim.new(0, 4),
		}),
	})
	return btn
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
		UI.Toast("Coming soon!", Color3.fromRGB(255, 200, 90))
		return
	end
	if kind == "Pass" then
		MarketplaceService:PromptGamePassPurchase(player, entry.Id)
	else
		MarketplaceService:PromptProductPurchase(player, entry.Id)
	end
end

-- Top bar ---------------------------------------------------------------------

local function buildTopBar()
	local top = scaled(create("Frame", {
		Name = "TopBar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.fromOffset(340, 124),
		BackgroundTransparency = 1,
		Parent = gui,
	}))

	local cash = create("Frame", {
		Name = "Cash",
		Size = UDim2.new(1, 0, 0, 72),
		BackgroundColor3 = WHITE,
		Parent = top,
	}, {
		corner(16),
		stroke(Color3.fromRGB(60, 40, 0), 3),
		gradient(Color3.fromRGB(255, 225, 110), Color3.fromRGB(240, 160, 30)),
	})
	refs.Money = label({
		Name = "Money",
		Position = UDim2.new(0, 10, 0, 4),
		Size = UDim2.new(1, -20, 0, 42),
		Text = "$0",
		TextStrokeTransparency = 0,
		Parent = cash,
	})
	refs.Income = label({
		Name = "Income",
		Position = UDim2.new(0, 10, 0, 44),
		Size = UDim2.new(1, -20, 0, 24),
		Text = "+$0/s",
		TextColor3 = Color3.fromRGB(255, 255, 230),
		Parent = cash,
	})

	local speed = create("Frame", {
		Name = "Speed",
		Position = UDim2.new(0, 0, 0, 80),
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = DARK,
		BackgroundTransparency = 0.15,
		ClipsDescendants = true,
		Parent = top,
	}, {
		corner(12),
		stroke(Color3.fromRGB(60, 200, 255), 2),
	})
	refs.SpeedFill = create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Color3.fromRGB(60, 200, 255),
		BackgroundTransparency = 0.35,
		Parent = speed,
	}, { corner(12) })
	refs.Speed = label({
		Name = "SpeedText",
		Position = UDim2.new(0, 8, 0, 4),
		Size = UDim2.new(1, -16, 1, -8),
		Text = "⚡ 16 Speed",
		ZIndex = 2,
		Parent = speed,
	})
	refs.TopBar = top
end

-- Left menu -------------------------------------------------------------------

local function buildMenu()
	local menu = scaled(create("Frame", {
		Name = "Menu",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		Size = UDim2.fromOffset(92, 300),
		BackgroundTransparency = 1,
		Parent = gui,
	}, {
		create("UIListLayout", {
			Padding = UDim.new(0, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Center,
		}),
	}))

	local entries = {
		{ Name = "Shop", Icon = "🛒", Color = Color3.fromRGB(70, 200, 100) },
		{ Name = "Index", Icon = "📖", Color = Color3.fromRGB(70, 150, 255) },
		{ Name = "Rebirth", Icon = "🌟", Color = Color3.fromRGB(170, 90, 255) },
	}
	for i, entry in entries do
		local btn = create("TextButton", {
			Name = entry.Name,
			LayoutOrder = i,
			Size = UDim2.fromOffset(88, 88),
			BackgroundColor3 = WHITE,
			Text = "",
			AutoButtonColor = true,
			Parent = menu,
		}, {
			corner(18),
			stroke(Color3.new(0, 0, 0), 3),
			gradient(entry.Color:Lerp(WHITE, 0.25), entry.Color),
		})
		label({
			Size = UDim2.new(1, 0, 0.62, 0),
			Text = entry.Icon,
			TextStrokeTransparency = 1,
			Parent = btn,
		})
		label({
			Position = UDim2.new(0, 4, 0.6, 0),
			Size = UDim2.new(1, -8, 0.34, 0),
			Text = entry.Name,
			TextStrokeTransparency = 0,
			Parent = btn,
		})
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
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(600, 440),
		BackgroundColor3 = DARK,
		Visible = false,
		Parent = gui,
	}, {
		corner(20),
		stroke(color, 4),
	}))
	local header = create("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 56),
		BackgroundColor3 = WHITE,
		Parent = panel,
	}, {
		corner(20),
		gradient(color:Lerp(WHITE, 0.2), color),
	})
	label({
		Position = UDim2.new(0, 20, 0, 8),
		Size = UDim2.new(1, -100, 1, -16),
		Text = title,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextStrokeTransparency = 0,
		Parent = header,
	})
	local close = button({
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(44, 44),
		Text = "X",
		Parent = header,
	}, RED)
	close.MouseButton1Click:Connect(function()
		playClick()
		panel.Visible = false
	end)
	local content = create("Frame", {
		Name = "Content",
		Position = UDim2.new(0, 14, 0, 66),
		Size = UDim2.new(1, -28, 1, -80),
		BackgroundTransparency = 1,
		Parent = panel,
	})
	panels[name] = panel
	return content
end

local function scrolling(parent)
	return create("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = parent,
	})
end

local function sectionHeader(parent, order, text)
	label({
		LayoutOrder = order,
		Size = UDim2.new(1, -12, 0, 30),
		Text = text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(255, 220, 120),
		Parent = parent,
	})
end

local function shopRow(parent, order, title, description, buttonColor, onClick)
	local row = create("Frame", {
		LayoutOrder = order,
		Size = UDim2.new(1, -12, 0, 70),
		BackgroundColor3 = Color3.fromRGB(40, 36, 62),
		Parent = parent,
	}, {
		corner(12),
	})
	local titleLabel = label({
		Position = UDim2.new(0, 12, 0, 6),
		Size = UDim2.new(1, -170, 0, 30),
		Text = title,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})
	local descLabel = label({
		Position = UDim2.new(0, 12, 0, 38),
		Size = UDim2.new(1, -170, 0, 24),
		Text = description,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(200, 200, 220),
		TextStrokeTransparency = 1,
		Parent = row,
	})
	local btn = button({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(140, 50),
		Text = "...",
		Parent = row,
	}, buttonColor)
	btn.MouseButton1Click:Connect(onClick)
	return { Title = titleLabel, Desc = descLabel, Button = btn }
end

local function buildShop()
	local content = makePanel("Shop", "🛒 Shop", Color3.fromRGB(70, 200, 100))
	local scroll = scrolling(content)
	create("UIListLayout", {
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = scroll,
	})

	local order = 0
	local function nextOrder()
		order += 1
		return order
	end

	sectionHeader(scroll, nextOrder(), "Upgrades (cash)")
	refs.BootsRow = shopRow(scroll, nextOrder(), "Speed Boots", "", GREEN, function()
		request("BuyBoots")
	end)
	refs.PedestalRow = shopRow(scroll, nextOrder(), "Extra Pedestal", "", GREEN, function()
		request("BuyPedestal")
	end)

	sectionHeader(scroll, nextOrder(), "Boosts (Robux)")
	for _, key in PRODUCT_ORDER do
		local product = Config.Products[key]
		local row = shopRow(scroll, nextOrder(), product.Name, product.Description, Color3.fromRGB(0, 170, 90), function()
			promptPurchase("Product", key)
		end)
		row.Button.Text = "R$ " .. product.Price
	end

	sectionHeader(scroll, nextOrder(), "Game Passes (forever)")
	refs.PassRows = {}
	for _, key in PASS_ORDER do
		local pass = Config.GamePasses[key]
		local row = shopRow(scroll, nextOrder(), pass.Name, pass.Description, Color3.fromRGB(255, 170, 40), function()
			if state and state.Passes and state.Passes[key] then
				return
			end
			promptPurchase("Pass", key)
		end)
		row.Button.Text = "R$ " .. pass.Price
		refs.PassRows[key] = row
	end
end

local function buildIndex()
	local content = makePanel("Index", "📖 Meteorling Index", Color3.fromRGB(70, 150, 255))
	refs.IndexHeader = label({
		Size = UDim2.new(1, 0, 0, 30),
		Text = "Discovered 0/" .. #Config.Meteorlings,
		TextColor3 = Color3.fromRGB(180, 220, 255),
		Parent = content,
	})
	local holder = create("Frame", {
		Position = UDim2.new(0, 0, 0, 36),
		Size = UDim2.new(1, 0, 1, -36),
		BackgroundTransparency = 1,
		Parent = content,
	})
	local scroll = scrolling(holder)
	create("UIGridLayout", {
		CellSize = UDim2.fromOffset(126, 136),
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = scroll,
	})

	refs.IndexCards = {}
	for i, info in Config.Meteorlings do
		local rarity = Util.GetRarity(info.Rarity)
		local card = create("Frame", {
			LayoutOrder = i,
			BackgroundColor3 = Color3.fromRGB(40, 36, 62),
			Parent = scroll,
		}, {
			corner(12),
			stroke(rarity.Color, 2),
		})
		local circle = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 8),
			Size = UDim2.fromOffset(56, 56),
			BackgroundColor3 = Color3.fromRGB(10, 10, 14),
			Parent = card,
		}, {
			create("UICorner", { CornerRadius = UDim.new(1, 0) }),
			stroke(Color3.new(0, 0, 0), 2),
		})
		local name = label({
			Position = UDim2.new(0, 4, 0, 68),
			Size = UDim2.new(1, -8, 0, 22),
			Text = "???",
			Parent = card,
		})
		label({
			Position = UDim2.new(0, 4, 0, 90),
			Size = UDim2.new(1, -8, 0, 18),
			Text = info.Rarity,
			TextColor3 = rarity.Color,
			Parent = card,
		})
		local income = label({
			Position = UDim2.new(0, 4, 0, 110),
			Size = UDim2.new(1, -8, 0, 18),
			Text = "",
			TextColor3 = Color3.fromRGB(140, 255, 140),
			Parent = card,
		})
		refs.IndexCards[info.Id] = { Circle = circle, Name = name, Income = income, Info = info }
	end
end

local function buildRebirth()
	local content = makePanel("Rebirth", "🌟 Rebirth", Color3.fromRGB(170, 90, 255))
	refs.RebirthCount = label({
		Size = UDim2.new(1, 0, 0, 44),
		Text = "Rebirths: 0",
		Parent = content,
	})
	refs.RebirthMult = label({
		Position = UDim2.new(0, 0, 0, 52),
		Size = UDim2.new(1, 0, 0, 36),
		Text = "Income x1 → x1.5",
		TextColor3 = Color3.fromRGB(140, 255, 140),
		Parent = content,
	})
	refs.RebirthCost = label({
		Position = UDim2.new(0, 0, 0, 96),
		Size = UDim2.new(1, 0, 0, 34),
		Text = "Cost: $0",
		TextColor3 = Color3.fromRGB(255, 220, 120),
		Parent = content,
	})
	local bar = create("Frame", {
		Position = UDim2.new(0.1, 0, 0, 140),
		Size = UDim2.new(0.8, 0, 0, 26),
		BackgroundColor3 = Color3.fromRGB(40, 36, 62),
		ClipsDescendants = true,
		Parent = content,
	}, { corner(10) })
	refs.RebirthFill = create("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Color3.fromRGB(170, 90, 255),
		Parent = bar,
	}, { corner(10) })
	label({
		Position = UDim2.new(0, 0, 0, 176),
		Size = UDim2.new(1, 0, 0, 50),
		Text = "Resets cash, speed and boots.\nKeeps your Meteorlings and Index!",
		TextColor3 = Color3.fromRGB(200, 200, 220),
		TextStrokeTransparency = 1,
		Parent = content,
	})
	refs.RebirthButton = button({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -6),
		Size = UDim2.fromOffset(260, 66),
		Text = "REBIRTH",
		Parent = content,
	}, Color3.fromRGB(170, 90, 255))
	refs.RebirthButton.MouseButton1Click:Connect(function()
		request("Rebirth")
	end)
end

-- Toasts, banner, popups, timers ---------------------------------------------

local function buildOverlay()
	refs.Toasts = scaled(create("Frame", {
		Name = "Toasts",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 140),
		Size = UDim2.fromOffset(560, 240),
		BackgroundTransparency = 1,
		Parent = gui,
	}, {
		create("UIListLayout", {
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
		}),
	}))

	refs.Banner = scaled(create("Frame", {
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.22, 0),
		Size = UDim2.fromOffset(720, 120),
		BackgroundColor3 = DARK,
		BackgroundTransparency = 0.15,
		Visible = false,
		Parent = gui,
	}, {
		corner(20),
		stroke(Color3.fromRGB(255, 160, 60), 4),
	}))
	refs.BannerTitle = label({
		Position = UDim2.new(0, 12, 0, 8),
		Size = UDim2.new(1, -24, 0, 54),
		Text = "",
		TextStrokeTransparency = 0,
		Parent = refs.Banner,
	})
	refs.BannerSub = label({
		Position = UDim2.new(0, 12, 0, 64),
		Size = UDim2.new(1, -24, 0, 26),
		Text = "",
		TextColor3 = Color3.fromRGB(230, 230, 240),
		Parent = refs.Banner,
	})
	refs.BannerTimer = label({
		Position = UDim2.new(0, 12, 0, 92),
		Size = UDim2.new(1, -24, 0, 22),
		Text = "",
		TextColor3 = Color3.fromRGB(255, 220, 120),
		Parent = refs.Banner,
	})

	refs.Timers = scaled(create("Frame", {
		Name = "Timers",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 60),
		Size = UDim2.fromOffset(240, 120),
		BackgroundTransparency = 1,
		Parent = gui,
	}, {
		create("UIListLayout", {
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
		}),
	}))
	local function timerLabel(order, color)
		return label({
			LayoutOrder = order,
			Size = UDim2.fromOffset(240, 34),
			BackgroundColor3 = DARK,
			BackgroundTransparency = 0.25,
			Text = "",
			TextColor3 = color,
			Visible = false,
			Parent = refs.Timers,
		})
	end
	refs.ShowerTimer = timerLabel(1, Color3.fromRGB(255, 160, 80))
	refs.LuckTimer = timerLabel(2, Color3.fromRGB(120, 255, 140))
	for _, timer in { refs.ShowerTimer, refs.LuckTimer } do
		corner(10).Parent = timer
	end

	refs.Carry = scaled(label({
		Name = "Carry",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -96),
		Size = UDim2.fromOffset(560, 44),
		BackgroundColor3 = DARK,
		BackgroundTransparency = 0.2,
		Text = "",
		Visible = false,
		Parent = gui,
	}))
	corner(12).Parent = refs.Carry

	refs.Popup = scaled(label({
		Name = "Popup",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.fromOffset(700, 90),
		Text = "",
		TextStrokeTransparency = 0,
		Visible = false,
		Parent = gui,
	}))

	refs.Flash = create("Frame", {
		Name = "Flash",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = RED,
		BackgroundTransparency = 1,
		ZIndex = 50,
		Active = false,
		Parent = gui,
	})
end

function UI.Toast(text, color)
	if not refs.Toasts then
		return
	end
	toastOrder += 1
	local toast = label({
		LayoutOrder = toastOrder,
		Size = UDim2.fromOffset(540, 34),
		BackgroundColor3 = DARK,
		BackgroundTransparency = 0.25,
		Text = text,
		TextColor3 = color or WHITE,
		TextStrokeTransparency = 0,
		Parent = refs.Toasts,
	})
	corner(10).Parent = toast
	create("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), Parent = toast })

	local toasts = {}
	for _, child in refs.Toasts:GetChildren() do
		if child:IsA("TextLabel") then
			table.insert(toasts, child)
		end
	end
	table.sort(toasts, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	while #toasts > 5 do
		table.remove(toasts, 1):Destroy()
	end

	task.delay(3.5, function()
		if toast.Parent then
			local fade = TweenService:Create(toast, TweenInfo.new(0.4), { TextTransparency = 1, BackgroundTransparency = 1, TextStrokeTransparency = 1 })
			fade:Play()
			fade.Completed:Wait()
			toast:Destroy()
		end
	end)
end

local bannerToken = 0
function UI.Banner(data)
	bannerToken += 1
	local token = bannerToken
	local banner = refs.Banner
	refs.BannerTitle.Text = data.Title or ""
	refs.BannerTitle.TextColor3 = data.Color or WHITE
	refs.BannerSub.Text = data.Subtitle or ""
	banner:FindFirstChildOfClass("UIStroke").Color = data.Color or WHITE
	banner.Visible = true
	banner.Size = UDim2.fromOffset(720 * 0.6, 120 * 0.6)
	TweenService:Create(banner, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Size = UDim2.fromOffset(720, 120) }):Play()

	task.spawn(function()
		local shownUntil = os.clock() + 8
		while token == bannerToken and os.clock() < shownUntil do
			local left = (data.EndsAt or 0) - workspace:GetServerTimeNow()
			if left > 0 then
				refs.BannerTimer.Text = Util.FormatTime(left)
			else
				refs.BannerTimer.Text = ""
			end
			task.wait(0.25)
		end
		if token == bannerToken then
			banner.Visible = false
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
	popup.TextStrokeTransparency = 0
	popup.Visible = true
	popup.Size = UDim2.fromOffset(200, 30)
	TweenService:Create(popup, TweenInfo.new(0.4, Enum.EasingStyle.Back), { Size = UDim2.fromOffset(700, 90) }):Play()
	task.delay(2.2, function()
		if token ~= popupToken then
			return
		end
		local fade = TweenService:Create(popup, TweenInfo.new(0.5), { TextTransparency = 1, TextStrokeTransparency = 1 })
		fade:Play()
		fade.Completed:Wait()
		if token == popupToken then
			popup.Visible = false
		end
	end)
end

function UI.Flash(color)
	refs.Flash.BackgroundColor3 = color or RED
	refs.Flash.BackgroundTransparency = 0.55
	TweenService:Create(refs.Flash, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
end

-- Floating "+$123" text near the top bar
function UI.FloatText(text, color, fromSpeed)
	local yOffset = 40
	if fromSpeed then
		yOffset = 100
	end
	local float = label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, math.random(-60, 60), 0, yOffset),
		Size = UDim2.fromOffset(220, 36),
		Text = text,
		TextColor3 = color or WHITE,
		TextStrokeTransparency = 0,
		ZIndex = 20,
		Parent = refs.TopBar,
	})
	local tween = TweenService:Create(float, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = float.Position + UDim2.fromOffset(0, 60),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})
	tween:Play()
	tween.Completed:Connect(function()
		float:Destroy()
	end)
end

function UI.TogglePanel(name)
	for panelName, panel in panels do
		if panelName == name then
			panel.Visible = not panel.Visible
		else
			panel.Visible = false
		end
	end
end

-- State updates ---------------------------------------------------------------

local function setButton(btn, text, enabled, color)
	btn.Text = text
	btn.AutoButtonColor = enabled
	if enabled then
		btn.BackgroundColor3 = color or GREEN
	else
		btn.BackgroundColor3 = Color3.fromRGB(90, 90, 105)
	end
end

function UI.Update(newState)
	state = newState

	refs.Money.Text = Util.FormatMoney(state.Money)
	local incomeText = "+" .. Util.FormatMoney(state.Income) .. "/s"
	if state.Bank >= 1 and not state.Passes.AutoCollect then
		incomeText ..= "   (" .. Util.FormatMoney(state.Bank) .. " at base)"
	end
	refs.Income.Text = incomeText

	local speedText = "⚡ " .. state.Speed .. " Speed   (+" .. state.PadRate .. "/s on pad)"
	if state.Speed >= state.MaxSpeed then
		speedText = "⚡ " .. state.Speed .. " Speed   MAX!"
	end
	refs.Speed.Text = speedText
	refs.SpeedFill.Size = UDim2.fromScale(math.clamp(state.Speed / state.MaxSpeed, 0, 1), 1)

	-- Shop
	local boots = refs.BootsRow
	boots.Title.Text = "Speed Boots  Lv " .. state.Boots .. "/" .. state.BootsMax
	if state.BootsCost then
		boots.Desc.Text = "Speed Pad: +" .. state.PadRate .. "/s  →  more per level"
		setButton(boots.Button, Util.FormatMoney(state.BootsCost), state.Money >= state.BootsCost)
	else
		boots.Desc.Text = "Speed Pad: +" .. state.PadRate .. "/s"
		setButton(boots.Button, "MAX", false)
	end

	local pedestal = refs.PedestalRow
	pedestal.Title.Text = "Extra Pedestal  " .. state.Pedestals .. "/" .. state.MaxBuyable
	pedestal.Desc.Text = "Slots used: " .. state.Used .. "/" .. state.PedestalsTotal
	if state.PedestalCost then
		setButton(pedestal.Button, Util.FormatMoney(state.PedestalCost), state.Money >= state.PedestalCost)
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
			card.Circle.BackgroundColor3 = card.Info.Color
			card.Name.Text = id
			card.Income.Text = Util.FormatMoney(card.Info.Income) .. "/s"
		else
			card.Circle.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
			card.Name.Text = "???"
			card.Income.Text = ""
		end
	end

	-- Rebirth
	refs.RebirthCount.Text = "Rebirths: " .. state.Rebirths
	refs.RebirthMult.Text = "Rebirth bonus: x" .. state.RebirthMult .. "  →  x" .. state.NextRebirthMult
	refs.RebirthCost.Text = "Cost: " .. Util.FormatMoney(state.RebirthCost)
	refs.RebirthFill.Size = UDim2.fromScale(math.clamp(state.Money / state.RebirthCost, 0, 1), 1)
	setButton(refs.RebirthButton, "REBIRTH", state.Money >= state.RebirthCost, Color3.fromRGB(170, 90, 255))
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
		refs.Carry.Text = "😈 STOLEN " .. id .. "! Run home before they bonk you!"
	else
		refs.Carry.Text = "☄️ " .. rarity.Name .. " Meteor! Follow the beam to your base!"
	end
	refs.Carry.TextColor3 = rarity.Color
	if rarity.Name == "Secret" then
		refs.Carry.TextColor3 = WHITE
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
				refs.ShowerTimer.Text = "☄️ Shower " .. Util.FormatTime(showerLeft)
			end
			local luckLeft = (state.LuckUntil or 0) - now
			refs.LuckTimer.Visible = luckLeft > 0
			if luckLeft > 0 then
				refs.LuckTimer.Text = "🍀 2x Luck " .. Util.FormatTime(luckLeft)
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
		Volume = 0.4,
		Parent = SoundService,
	})

	buildTopBar()
	buildMenu()
	buildShop()
	buildIndex()
	buildRebirth()
	buildOverlay()

	updateScale()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	end

	player:GetAttributeChangedSignal("Carrying"):Connect(UI.UpdateCarry)
	player:GetAttributeChangedSignal("CarryStolen"):Connect(UI.UpdateCarry)
	UI.UpdateCarry()

	task.spawn(timerLoop)
end

return UI
