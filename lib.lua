local STORAGE_ROOT = "\109\105\099\104\105\103\117\110\046\120\121\122"
local STORAGE_PATH_ERROR = "Armazenamento indisponível (ERRO UI-01) [Contate a dona]"
local STORAGE_IO_ERROR = "Armazenamento indisponível (ERRO UI-02) [Contate a dona]"

local function resolveStoragePath(path, defaultPath)
	path = tostring(path or defaultPath or STORAGE_ROOT):gsub("\\", "/")
	assert(not path:find("[:%c]") and path:sub(1, 1) ~= "/", STORAGE_PATH_ERROR)
	local parts = {}
	for part in path:gmatch("[^/]+") do
		assert(part ~= "..", STORAGE_PATH_ERROR)
		if part ~= "." then
			parts[#parts + 1] = part
		end
	end
	if parts[1] ~= STORAGE_ROOT then
		table.insert(parts, 1, STORAGE_ROOT)
	end
	return table.concat(parts, "/")
end

local function storageFilePath(folder, name, extension)
	assert(
		type(name) == "string" and name ~= "" and name ~= "." and name ~= ".." and not name:find("[/\\:%c]"),
		STORAGE_PATH_ERROR
	)
	return resolveStoragePath(folder) .. "/" .. name .. extension
end

local function ensureStorageFolder(path)
	path = resolveStoragePath(path)
	if type(makefolder) ~= "function" then
		return
	end
	local current = ""
	for part in path:gmatch("[^/]+") do
		current = current == "" and part or current .. "/" .. part
		if type(isfolder) ~= "function" or not isfolder(current) then
			local success = pcall(makefolder, current)
			assert(success, STORAGE_IO_ERROR)
		end
	end
end

local function migrateStorageConfigs(legacyFolder, folder, markerName)
	folder = resolveStoragePath(folder)
	if
		type(listfiles) ~= "function"
		or type(readfile) ~= "function"
		or type(writefile) ~= "function"
		or type(isfile) ~= "function"
	then
		return
	end
	local marker = storageFilePath(
		folder,
		markerName or "\046\097\105\114\102\108\111\119\045\109\105\103\114\097\116\101\100",
		""
	)
	if isfile(marker) then
		return
	end
	if type(isfolder) == "function" and not isfolder(legacyFolder) then
		return
	end
	local success, files = pcall(listfiles, legacyFolder)
	if not success or type(files) ~= "table" then
		return
	end
	for _, file in ipairs(files) do
		local name = type(file) == "string" and file:match("([^/\\]+)%.json$")
		if name then
			local valid, destination = pcall(storageFilePath, folder, name, ".json")
			if valid and not isfile(destination) then
				local copied = pcall(function()
					local data = readfile(legacyFolder .. "/" .. name .. ".json")
					ensureStorageFolder(folder)
					writefile(destination, data)
				end)
				assert(copied, STORAGE_IO_ERROR)
			end
		end
	end
	ensureStorageFolder(folder)
	local marked = pcall(writefile, marker, "1")
	assert(marked, STORAGE_IO_ERROR)
end

local function uppercasePortuguese(value)
	local letters = {
		["á"] = "Á",
		["à"] = "À",
		["â"] = "Â",
		["ã"] = "Ã",
		["ä"] = "Ä",
		["é"] = "É",
		["ê"] = "Ê",
		["è"] = "È",
		["í"] = "Í",
		["ì"] = "Ì",
		["ó"] = "Ó",
		["ô"] = "Ô",
		["õ"] = "Õ",
		["ò"] = "Ò",
		["ú"] = "Ú",
		["ü"] = "Ü",
		["ù"] = "Ù",
		["ç"] = "Ç",
	}
	local result = string.upper(tostring(value))
	for lower, upper in pairs(letters) do
		result = result:gsub(lower, upper)
	end
	return result
end

local function controlSize(frame, height)
	height = math.max(0, height)
	if frame:GetAttribute("UIIntrinsicHeight") ~= height then
		frame:SetAttribute("UIIntrinsicHeight", height)
	end
	local parent = frame.Parent
	if parent and parent:GetAttribute("UILayoutRow") then
		height = math.max(height, parent:GetAttribute("UIRowHeight") or 0)
	end
	return UDim2.new(frame.Size.X.Scale, frame.Size.X.Offset, 0, height)
end
local Palette = {
	Accent = "#E6E6EB",
	AccentSoft = "#DCDCE2",
	Primary = "#505056",
	Background = "#101011",
	BackgroundDeep = "#121214",
	BackgroundAlt = "#141415",
	Panel = "#141415",
	Surface = "#141415",
	SurfaceRaised = "#18181A",
	Hover = "#28282B",
	Border = "#242427",
	Text = "#E8E8EC",
	Muted = "#828288",
	Subtle = "#828288",
	Success = "#96DCAA",
	Warning = "#F0B06C",
	Danger = "#F07878",
}
local RuntimeFactory = (function()
	return function()
		local environment = getfenv()
		if type(getgenv) == "function" then
			local success, value = pcall(getgenv)
			if success and type(value) == "table" then
				environment = value
			end
		end

		local function firstFunction(...)
			for index = 1, select("#", ...) do
				local value = select(index, ...)
				if type(value) == "function" then
					return value
				end
			end
		end
		local cloneReference = firstFunction(environment.cloneref, cloneref, environment.clonereference, clonereference)
		local parentAPIs, registered = {}, {}
		local function addParentAPI(apiFunction, name)
			if type(apiFunction) == "function" and not registered[apiFunction] then
				registered[apiFunction] = true
				parentAPIs[#parentAPIs + 1] = { Call = apiFunction, Name = name }
			end
		end
		addParentAPI(environment.gethui, "gethui")
		addParentAPI(gethui, "gethui")
		addParentAPI(environment.get_hidden_gui, "get_hidden_gui")
		addParentAPI(get_hidden_gui, "get_hidden_gui")
		local runtime = {}
		local services = {}
		function runtime.Reference(object)
			if cloneReference and typeof(object) == "Instance" then
				local success, reference = pcall(cloneReference, object)
				if success and typeof(reference) == "Instance" and reference.ClassName == object.ClassName then
					return reference
				end
			end
			return object
		end

		function runtime.GetService(name)
			if not services[name] then
				services[name] = runtime.Reference(game:GetService(name))
			end
			return services[name]
		end

		function runtime.GetUIParent()
			for _, api in ipairs(parentAPIs) do
				local success, parent = pcall(api.Call)
				if
					success
					and typeof(parent) == "Instance"
					and (parent:IsA("CoreGui") or parent:IsA("ScreenGui") or parent:IsA("Folder"))
				then
					return parent, api.Name
				end
			end
			local success, studio = pcall(function()
				return runtime.GetService("RunService"):IsStudio()
			end)
			if success and studio then
				local player = runtime.Reference(runtime.GetService("Players").LocalPlayer)
				return player:WaitForChild("PlayerGui"), "PlayerGui (Studio)"
			end
			error(
				"[UI] gethui/get_hidden_gui indisponível ou inválido. A interface não será criada em PlayerGui ou CoreGui automaticamente.",
				0
			)
		end
		return runtime
	end
end)()
local Runtime = RuntimeFactory()
local UIEngine = (function()
	local TweenService = Runtime.GetService("TweenService")
	local UserInputService = Runtime.GetService("UserInputService")
	local GuiService = Runtime.GetService("GuiService")
	local RunService = Runtime.GetService("RunService")
	local HttpService = Runtime.GetService("HttpService")
	local Players = Runtime.GetService("Players")
	local localPlayer = Runtime.Reference(Players.LocalPlayer)
	local NativeLibrary = {}
	NativeLibrary.Flags = {}
	NativeLibrary.Windows = {}
	local function normalizeOptions(source, aliases)
		local entries = {}
		if type(source) == "string" then
			entries.Name = source
		elseif type(source) == "table" then
			for key, value in pairs(source) do
				entries[key] = value
			end
		end
		for alias, canonical in pairs(aliases or {}) do
			if entries[canonical] == nil and entries[alias] ~= nil then
				entries[canonical] = entries[alias]
			end
		end
		if entries.Range then
			entries.Min = entries.Min or entries.Range[1]
			entries.Max = entries.Max or entries.Range[2]
		end
		return entries
	end

	local function registerElement(tab, options, element, frame, kind)
		element._type = kind
		element._frame = frame
		element._listeners = element._listeners or {}
		local window = tab and tab.Window
		if options.Flag then
			NativeLibrary.Flags[options.Flag] = element
			if window then
				local onChanged = options.Callback
				options.Callback = function(...)
					if type(onChanged) == "function" then
						onChanged(...)
					end
					window:_autoSave()
				end
			end
		end

		function element:Destroy()
			if element._destroyed then
				return
			end
			element._destroyed = true
			for index, disconnect in ipairs(element._listeners) do
				disconnect()
			end
			element._listeners = {}
			if options.Flag and NativeLibrary.Flags[options.Flag] == element then
				NativeLibrary.Flags[options.Flag] = nil
			end
			if window then
				window._controlsDirty = true
			end
			if frame then
				frame:Destroy()
			end
		end
		return element
	end
	NativeLibrary.Theme = {
		Background = Color3.fromHex(Palette.Background),
		Surface = Color3.fromHex(Palette.Surface),
		Surface2 = Color3.fromHex(Palette.SurfaceRaised),
		Surface3 = Color3.fromHex(Palette.Hover),
		Stroke = Color3.fromHex(Palette.Border),
		StrokeHover = Color3.fromHex(Palette.Primary),
		Accent = Color3.fromHex(Palette.Accent),
		AccentDark = Color3.fromHex(Palette.BackgroundDeep),
		Text = Color3.fromHex(Palette.Text),
		Muted = Color3.fromHex(Palette.Muted),
		Glow = Color3.fromHex(Palette.AccentSoft),
		Warning = Color3.fromHex(Palette.Warning),
		Success = Color3.fromHex(Palette.Success),
		Error = Color3.fromHex(Palette.Danger),
	}
	NativeLibrary.Assets =
		{ Shadow = "rbxassetid://6014261993", Glow = "rbxassetid://8992230677", Logo = "rbxassetid://97170941541314" }
	local lucideIcons
	local function loadLucideIcons()
		if lucideIcons ~= nil then
			return lucideIcons
		end
		local success, result = pcall(function()
			local iconSource =
				game:HttpGet("https://raw.githubusercontent.com/Footagesus/Icons/refs/heads/main/lucide/dist/Icons.lua")
			return loadstring(iconSource)()
		end)
		if success and type(result) == "table" then
			lucideIcons = result
		else
			lucideIcons = false
		end
		return lucideIcons
	end
	local fontPresets = {
		ValleySans = {
			Regular = "https://raw.githubusercontent.com/HelsinkiTypeStudio/valley-sans/main/fonts/ttf/ValleySans-Regular.ttf",
			Medium = "https://raw.githubusercontent.com/HelsinkiTypeStudio/valley-sans/main/fonts/ttf/ValleySans-Medium.ttf",
			SemiBold = "https://raw.githubusercontent.com/HelsinkiTypeStudio/valley-sans/main/fonts/ttf/ValleySans-SemiBold.ttf",
		},
	}
	local fontWeights = {
		Regular = { 400, Enum.FontWeight.Regular },
		Medium = { 500, Enum.FontWeight.Medium },
		SemiBold = { 600, Enum.FontWeight.SemiBold },
		Bold = { 700, Enum.FontWeight.Bold },
	}
	function NativeLibrary:LoadFont(fontConfig)
		local functionType = "function"
		fontConfig = normalizeOptions(fontConfig, {})
		if
			type(writefile) ~= functionType
			or type(isfile) ~= functionType
			or typeof(getcustomasset) ~= functionType
		then
			return false
		end
		local fontName = fontConfig.Name or "CustomFont"
		local weights = fontConfig.Weights or fontPresets[fontName]
		if type(weights) ~= "table" then
			return false
		end
		local fontFolder = resolveStoragePath(fontConfig.Folder, "fonts")
		local folderReady = pcall(ensureStorageFolder, fontFolder)
		if not folderReady then
			return false
		end
		local fontFaces = {}
		for weightName, fontUrl in pairs(weights) do
			local weightInfo = fontWeights[weightName]
			if weightInfo then
				local fontPath, fontReady = storageFilePath(fontFolder, fontName .. "-" .. weightName, ".ttf"), true
				if not isfile(fontPath) then
					fontReady = pcall(function()
						writefile(fontPath, game:HttpGet(fontUrl))
					end)
				end
				if fontReady then
					table.insert(fontFaces, {
						name = weightName,
						weight = weightInfo[1],
						style = "normal",
						assetId = getcustomasset(fontPath),
					})
				else
				end
			end
		end
		if #fontFaces == 0 then
			return false
		end
		local fontManifestPath = storageFilePath(fontFolder, fontName, ".json")
		local success = pcall(function()
			writefile(fontManifestPath, HttpService:JSONEncode({ name = fontName, faces = fontFaces }))
		end)
		if not success then
			return false
		end
		local fontAsset = getcustomasset(fontManifestPath)
		local function resolveFontWeight(weightName, fallbackFont)
			local weightInfo = fontWeights[weightName]
			if weightInfo and weights[weightName] then
				return Font.new(fontAsset, weightInfo[2])
			end
			return fallbackFont
		end
		NativeLibrary.Fonts.Regular = resolveFontWeight("Regular", NativeLibrary.Fonts.Regular)
		NativeLibrary.Fonts.Medium =
			resolveFontWeight("Medium", resolveFontWeight("Regular", NativeLibrary.Fonts.Medium))
		NativeLibrary.Fonts.Bold = resolveFontWeight("SemiBold", resolveFontWeight("Bold", NativeLibrary.Fonts.Bold))
		return true
	end

	function NativeLibrary:PreloadIcons()
		return loadLucideIcons() ~= false
	end

	local function resolveIcon(icon)
		if typeof(icon) == "table" then
			return icon.Image, icon.RectOffset, icon.RectSize
		end
		if type(icon) ~= "string" then
			return nil
		end
		if
			icon:find("^rbxassetid://")
			or icon:find("^rbxasset://")
			or icon:find("^rbxthumb://")
			or icon:find("^http")
		then
			return icon
		end
		local iconName = icon:gsub("^lucide:", "")
		local iconPack = loadLucideIcons()
		if not iconPack then
			return nil
		end
		local iconData = iconPack.Icons and iconPack.Icons[iconName] or iconPack[iconName]
		if type(iconData) == "table" then
			local image = iconData.Image
			if type(image) == "number" then
				image = "rbxassetid://" .. tostring(image)
			end
			local imageAsset = iconPack.Spritesheets and iconPack.Spritesheets[tostring(image)] or image
			return imageAsset, iconData.ImageRectPosition, iconData.ImageRectSize
		elseif type(iconData) == "string" then
			return iconData
		end
		return nil
	end
	local fontFamily = "rbxasset://fonts/families/BuilderSans.json"
	NativeLibrary.Fonts = {
		Regular = Font.new(fontFamily, Enum.FontWeight.Regular),
		Medium = Font.new(fontFamily, Enum.FontWeight.Medium),
		Bold = Font.new(fontFamily, Enum.FontWeight.SemiBold),
	}
	local nativeTheme = NativeLibrary.Theme
	local nativeAssets = NativeLibrary.Assets
	local nativeFonts = NativeLibrary.Fonts
	local isTouchDevice = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	NativeLibrary.Touch = isTouchDevice
	local cardHeight = isTouchDevice and 54 or 48
	local descriptionCardHeight = isTouchDevice and 70 or 64
	local dropdownOptionHeight = isTouchDevice and 40 or 34
	local chipHeight = isTouchDevice and 34 or 28
	local tweenCache = {}
	local function animate(object, properties, duration, style, direction)
		local parent = object.Parent
		if properties.Size and parent and parent:GetAttribute("UILayoutRow") then
			object.Size = properties.Size
			properties = table.clone(properties)
			properties.Size = nil
			if not next(properties) then
				return nil
			end
		end
		duration = duration or 0.2
		if duration <= 0 then
			for property, value in pairs(properties) do
				object[property] = value
			end
			return nil
		end
		style = style or Enum.EasingStyle.Quart
		direction = direction or Enum.EasingDirection.Out
		local tweenKey = duration .. style.Name .. direction.Name
		local tweenInfo = tweenCache[tweenKey]
		if not tweenInfo then
			tweenInfo = TweenInfo.new(duration, style, direction)
			tweenCache[tweenKey] = tweenInfo
		end
		local tween = TweenService:Create(object, tweenInfo, properties)
		tween:Play()
		return tween
	end

	local function createInstance(className, properties, children)
		local instance = Instance.new(className)
		for property, value in pairs(properties) do
			if property ~= "Parent" then
				instance[property] = value
			end
		end
		if children then
			for index, child in ipairs(children) do
				child.Parent = instance
			end
		end
		if properties.Parent then
			instance.Parent = properties.Parent
		end
		return instance
	end

	local function addCorner(parent, radius)
		local radius = radius or UDim.new(0, 12)
		if radius.Scale == 0 and radius.Offset == 6 then
			radius = UDim.new(0, 8)
		end
		return createInstance("UICorner", { CornerRadius = radius, Parent = parent })
	end

	local function addStroke(parent, color, transparency, thickness)
		return createInstance("UIStroke", {
			Color = color or nativeTheme.Stroke,
			Transparency = transparency or 0,
			Thickness = thickness or 1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Parent = parent,
		})
	end

	local function addPadding(parent, left, right, top, bottom)
		return createInstance("UIPadding", {
			PaddingLeft = UDim.new(0, left or 0),
			PaddingRight = UDim.new(0, right or 0),
			PaddingTop = UDim.new(0, top or 0),
			PaddingBottom = UDim.new(0, bottom or 0),
			Parent = parent,
		})
	end

	local function createLabel(properties)
		local labelProperties = {
			BackgroundTransparency = 1,
			TextColor3 = nativeTheme.Text,
			TextSize = 14,
			FontFace = nativeFonts.Medium,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Center,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}
		for property, value in pairs(properties) do
			labelProperties[property] = value
		end
		return createInstance("TextLabel", labelProperties)
	end

	local function addGlow(parent, size, position, transparency, rotation)
		local imageLabel = createInstance("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = position,
			Size = size,
			BackgroundTransparency = 1,
			Image = nativeAssets.Glow,
			ImageColor3 = nativeTheme.Glow,
			ImageTransparency = transparency,
			ZIndex = 0,
			Parent = parent,
		})
		createInstance("UIGradient", {
			Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), nativeTheme.Accent),
			Rotation = rotation or 90,
			Parent = imageLabel,
		})
		return imageLabel
	end

	local function addEdgeHighlight(parent)
		return createInstance("Frame", {
			Position = UDim2.fromOffset(0, 0),
			Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.93,
			BorderSizePixel = 0,
			ZIndex = 0,
			Parent = parent,
		})
	end

	local function applyIcon(image, icon)
		local imageAsset, imageOffset, imageSize = resolveIcon(icon)
		if not imageAsset then
			return
		end
		image.Image = imageAsset
		image.ImageRectOffset = imageOffset or Vector2.zero
		image.ImageRectSize = imageSize or Vector2.zero
	end

	local function getInterfaceParent()
		return Runtime.GetUIParent()
	end
	local activeTouch, touchPosition = nil, Vector2.zero
	local function getPointerPosition()
		local now = time()
		if activeTouch ~= now then
			activeTouch = now
			touchPosition = GuiService:GetGuiInset()
		end
		return UserInputService:GetMouseLocation() - touchPosition
	end

	local function isPrimaryInput(input)
		return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
	end

	local function isPointerMovement(input)
		return input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch
	end

	local function createIcon(parent, icon, tint, position)
		local iconHolder = createInstance("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = position,
			Size = UDim2.fromOffset(16, 16),
			BackgroundTransparency = 1,
			Parent = parent,
		})
		local iconImage = createInstance("ImageLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ImageColor3 = tint,
			ScaleType = Enum.ScaleType.Fit,
			Parent = iconHolder,
		})
		applyIcon(iconImage, icon)
		return iconHolder, iconImage
	end

	local function createChevron(parent, anchorX, offsetX)
		local chevronHolder = createInstance("Frame", {
			AnchorPoint = Vector2.new(anchorX, 0.5),
			Position = UDim2.new(anchorX, offsetX, 0.5, 0),
			Size = UDim2.fromOffset(18, 18),
			BackgroundTransparency = 1,
			Parent = parent,
		})
		local chevron = {}
		local chevronMask = createInstance("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(16, 16),
			BackgroundTransparency = 1,
			ImageColor3 = nativeTheme.Muted,
			ScaleType = Enum.ScaleType.Fit,
			Parent = chevronHolder,
		})
		applyIcon(chevronMask, "chevron-down")
		if chevronMask.Image ~= "" then
			function chevron:Set(open)
				animate(
					chevronMask,
					{ Rotation = open and 180 or 0, ImageColor3 = open and nativeTheme.Accent or nativeTheme.Muted },
					0.3,
					Enum.EasingStyle.Quint
				)
			end
			return chevron
		end
		chevronMask:Destroy()
		local function createChevronStroke(rotation, anchorY)
			return createLabel({
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(18, 18),
				Text = "›",
				TextSize = 22,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextColor3 = nativeTheme.Muted,
				TextTransparency = anchorY,
				Rotation = rotation,
				Parent = chevronHolder,
			})
		end
		local upperStroke = createChevronStroke(90, 0)
		local lowerStroke = createChevronStroke(270, 1)
		function chevron:Set(open)
			animate(upperStroke, { TextTransparency = open and 1 or 0 }, 0.2)
			animate(
				lowerStroke,
				{ TextTransparency = open and 0 or 1, TextColor3 = open and nativeTheme.Accent or nativeTheme.Muted },
				0.2
			)
		end
		return chevron
	end
	local ripplePool = {}
	local function createRipple(target)
		local pointerPosition = getPointerPosition()
		local rippleDiameter = math.max(target.AbsoluteSize.X, target.AbsoluteSize.Y) * 2.2
		local ripple = table.remove(ripplePool)
		if not ripple then
			ripple = createInstance(
				"Frame",
				{ AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = nativeTheme.Accent, BorderSizePixel = 0 }
			)
			addCorner(ripple, UDim.new(1, 0))
		end
		ripple.Position = UDim2.fromOffset(
			pointerPosition.X - target.AbsolutePosition.X,
			pointerPosition.Y - target.AbsolutePosition.Y
		)
		ripple.Size = UDim2.fromOffset(0, 0)
		ripple.BackgroundTransparency = 0.82
		ripple.ZIndex = target.ZIndex + 1
		ripple.Parent = target
		animate(ripple, { Size = UDim2.fromOffset(rippleDiameter, rippleDiameter), BackgroundTransparency = 1 }, 0.55)
		task.delay(0.55, function()
			ripple.Parent = nil
			if #ripplePool < 4 then
				table.insert(ripplePool, ripple)
			else
				ripple:Destroy()
			end
		end)
	end

	local function addCardGradient(target)
		if not target then
			return
		end
		animate(target, { Color = nativeTheme.Accent, Transparency = 0.2 }, 0.08)
		task.delay(0.12, function()
			animate(target, { Color = nativeTheme.Stroke, Transparency = 0 }, 0.35)
		end)
	end

	local function decorateCard(card, stroke)
		card.MouseEnter:Connect(function()
			animate(stroke, { Color = nativeTheme.StrokeHover }, 0.12)
		end)
		card.MouseLeave:Connect(function()
			animate(stroke, { Color = nativeTheme.Stroke }, 0.25)
		end)
	end
	local keyNames = {
		[Enum.KeyCode.LeftControl] = "LCtrl",
		[Enum.KeyCode.RightControl] = "RCtrl",
		[Enum.KeyCode.LeftShift] = "LShift",
		[Enum.KeyCode.RightShift] = "RShift",
		[Enum.KeyCode.LeftAlt] = "LAlt",
		[Enum.KeyCode.RightAlt] = "RAlt",
		[Enum.KeyCode.Return] = "Enter",
		[Enum.KeyCode.Escape] = "Esc",
		[Enum.KeyCode.Backspace] = "Backspace",
	}
	local function formatKeyName(keyCode)
		if keyCode == nil then
			return "None"
		end
		return keyNames[keyCode] or keyCode.Name
	end

	local function invokeCallback(callback, ...)
		if type(callback) ~= "function" then
			return
		end
		local success, result = pcall(callback, ...)
		if not success then
		end
	end

	local function createRangeAdapter(minimum, maximum, step)
		local count = 0
		local stepText = tostring(step)
		local decimalPosition = stepText:find("%.")
		if decimalPosition then
			count = #stepText - decimalPosition
		end
		local numberFormat = "%." .. count .. "f"
		return {
			snap = function(value)
				value = math.floor(value / step + 0.5) * step
				return math.clamp(value, minimum, maximum)
			end,
			format = function(value)
				return string.format(numberFormat, value)
			end,
		}
	end

	local function createCard(tab, className, height, config)
		local cardProperties = {
			Size = UDim2.new(1, 0, 0, height),
			BackgroundColor3 = nativeTheme.Surface2,
			BorderSizePixel = 0,
			LayoutOrder = tab:_nextOrder(),
			Parent = tab.List,
		}
		if className == "TextButton" then
			cardProperties.AutoButtonColor = false
			cardProperties.Text = ""
		end
		local card = createInstance(className, cardProperties)
		card:SetAttribute("NoDrag", true)
		addCorner(card)
		local stroke = addStroke(card, nativeTheme.Stroke)
		return card, stroke
	end

	local function createCardLabels(parent, title, description, controlWidth)
		local titleLabel, descriptionLabel
		if description then
			local titleOffset = (descriptionCardHeight - 38) / 2
			titleLabel = createLabel({
				Position = UDim2.fromOffset(14, titleOffset),
				Size = UDim2.new(1, -(14 + controlWidth), 0, 18),
				Text = title,
				Parent = parent,
			})
			descriptionLabel = createLabel({
				Position = UDim2.fromOffset(14, titleOffset + 20),
				Size = UDim2.new(1, -(14 + controlWidth), 0, 17),
				Text = description,
				TextSize = 13,
				FontFace = nativeFonts.Regular,
				TextColor3 = nativeTheme.Muted,
				Parent = parent,
			})
		else
			titleLabel = createLabel({
				Position = UDim2.fromOffset(14, 0),
				Size = UDim2.new(1, -(14 + controlWidth), 1, 0),
				Text = title,
				Parent = parent,
			})
		end
		return titleLabel, descriptionLabel
	end

	local function createInteractiveCard(tab, config, aliases, className, controlWidth, fallbackTitle)
		config = normalizeOptions(config, aliases)
		local height = config.Desc and descriptionCardHeight or cardHeight
		local cardFrame, cardStroke = createCard(tab, className or "Frame", height, config)
		decorateCard(cardFrame, cardStroke)
		local titleLabel, descriptionLabel
		if controlWidth then
			titleLabel, descriptionLabel =
				createCardLabels(cardFrame, config.Name or fallbackTitle, config.Desc, controlWidth)
		end
		return config, cardFrame, cardStroke, height, titleLabel, descriptionLabel
	end

	local function reserveControlWidth(titleLabel, descriptionLabel, controlWidth)
		if titleLabel then
			titleLabel.Size = UDim2.new(1, -(14 + controlWidth), titleLabel.Size.Y.Scale, titleLabel.Size.Y.Offset)
		end
		if descriptionLabel then
			descriptionLabel.Size = UDim2.new(1, -(14 + controlWidth), 0, descriptionLabel.Size.Y.Offset)
		end
	end
	local NativeTab = {}
	NativeTab.__index = NativeTab
	function NativeTab:_nextOrder()
		self._order += 1
		return self._order
	end

	function NativeTab:Section(sectionConfig)
		if type(sectionConfig) == "table" then
			sectionConfig = sectionConfig.Name or sectionConfig.Title or ""
		end
		local sectionFrame = createInstance("Frame", {
			Size = UDim2.new(1, 0, 0, 28),
			BackgroundTransparency = 1,
			LayoutOrder = self:_nextOrder(),
			Parent = self.List,
		})
		local textLabel = createLabel({
			Position = UDim2.fromOffset(2, 8),
			Size = UDim2.new(0, 0, 0, 16),
			AutomaticSize = Enum.AutomaticSize.X,
			Text = uppercasePortuguese(sectionConfig),
			TextSize = 12,
			TextColor3 = nativeTheme.Muted,
			TextTruncate = Enum.TextTruncate.None,
			Parent = sectionFrame,
		})
		local sectionDivider = createInstance("Frame", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, 0, 0, 16),
			Size = UDim2.new(1, -12, 0, 1),
			BackgroundColor3 = nativeTheme.Stroke,
			BorderSizePixel = 0,
			Parent = sectionFrame,
		})
		textLabel:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			sectionDivider.Size = UDim2.new(1, -(textLabel.AbsoluteSize.X + 14), 0, 1)
		end)
		task.defer(function()
			sectionDivider.Size = UDim2.new(1, -(textLabel.AbsoluteSize.X + 14), 0, 1)
		end)
		return registerElement(self, {}, {
			Set = function(control, title)
				textLabel.Text = uppercasePortuguese(title)
			end,
		}, sectionFrame, "Section")
	end

	function NativeTab:Divider()
		local dividerFrame = createInstance("Frame", {
			Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = nativeTheme.Stroke,
			BorderSizePixel = 0,
			LayoutOrder = self:_nextOrder(),
			Parent = self.List,
		})
		return registerElement(self, {}, {}, dividerFrame, "Divider")
	end

	function NativeTab:Label(labelConfig)
		labelConfig = normalizeOptions(labelConfig, { Name = "Text", Title = "Text" })
		local label = createLabel({
			Size = UDim2.new(1, 0, 0, 18),
			Text = labelConfig.Text or "",
			TextSize = 13,
			FontFace = nativeFonts.Regular,
			TextColor3 = labelConfig.Color or nativeTheme.Muted,
			LayoutOrder = self:_nextOrder(),
			Parent = self.List,
		})
		addPadding(label, 2)
		local labelControl = {
			Set = function(control, text)
				label.Text = tostring(text)
			end,
			Get = function()
				return label.Text
			end,
		}
		if type(labelConfig.Update) == "function" then
			local updateInterval, updating = math.max(tonumber(labelConfig.UpdateRate) or 1, 0.05), true
			labelControl._listeners = labelControl._listeners or {}
			table.insert(labelControl._listeners, function()
				updating = false
			end)
			task.spawn(function()
				while updating and label.Parent do
					local success, result = pcall(labelConfig.Update)
					if success and result ~= nil then
						label.Text = tostring(result)
					elseif not success then
					end
					task.wait(updateInterval)
				end
			end)
			function labelControl:SetUpdateRate(interval)
				updateInterval = math.max(tonumber(interval) or updateInterval, 0.05)
			end
		end
		return registerElement(self, labelConfig, labelControl, label, "Label")
	end

	function NativeTab:Paragraph(paragraphConfig)
		paragraphConfig = normalizeOptions(paragraphConfig, { Title = "Name" })
		local paragraphFrame = createCard(self, "Frame", 0, paragraphConfig)
		paragraphFrame.AutomaticSize = Enum.AutomaticSize.Y
		addPadding(paragraphFrame, 14, 14, 11, 12)
		createInstance(
			"UIListLayout",
			{ SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4), Parent = paragraphFrame }
		)
		createLabel({
			Size = UDim2.new(1, 0, 0, 14),
			Text = paragraphConfig.Name or "",
			LayoutOrder = 1,
			Parent = paragraphFrame,
		})
		local contentLabel = createLabel({
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Text = paragraphConfig.Content or "",
			TextSize = 13,
			FontFace = nativeFonts.Regular,
			TextColor3 = nativeTheme.Muted,
			TextWrapped = true,
			TextTruncate = Enum.TextTruncate.None,
			TextYAlignment = Enum.TextYAlignment.Top,
			LayoutOrder = 2,
			Parent = paragraphFrame,
		})
		return registerElement(self, paragraphConfig, {
			Set = function(control, content)
				contentLabel.Text = content
			end,
		}, paragraphFrame, "Paragraph")
	end

	function NativeTab:Button(config)
		config = normalizeOptions(config, { Title = "Name", Description = "Desc" })
		local primary = config.Style == "Primary"
		local section = config.Style == "Section"
		local frame, stroke =
			createCard(self, "TextButton", config.Desc and descriptionCardHeight or cardHeight, config)
		frame.ClipsDescendants = true
		frame:SetAttribute("UIRole", section and "SectionHeader" or "ActionButton")
		local hovered = false
		local leading, leadingHolder
		if config.Icon then
			local holder
			holder, leading =
				createIcon(frame, config.Icon, nativeTheme.Text, UDim2.new(0, section and 0 or 14, 0.5, 0))
			leadingHolder = holder
		end
		local title, description = createCardLabels(frame, config.Name or "Button", config.Desc, section and 36 or 56)
		if section then
			title.FontFace = nativeFonts.Bold
			title.TextSize = 16
			local inset = config.Icon and 26 or 0
			title.Position = UDim2.fromOffset(inset, title.Position.Y.Offset)
			title.Size = UDim2.new(1, -inset - 36, title.Size.Y.Scale, title.Size.Y.Offset)
			if description then
				description.Position = UDim2.fromOffset(inset, description.Position.Y.Offset)
				description.Size = UDim2.new(1, -inset - 36, 0, description.Size.Y.Offset)
			end
		elseif leading then
			title.Position += UDim2.fromOffset(26, 0)
			title.Size -= UDim2.fromOffset(26, 0)
			if description then
				description.Position += UDim2.fromOffset(26, 0)
				description.Size -= UDim2.fromOffset(26, 0)
			end
		end
		local indicator, arrow
		if section then
			local holder
			holder, arrow = createIcon(frame, "chevron-right", nativeTheme.Muted, UDim2.new(1, -24, 0.5, 0))
		else
			indicator = createInstance("Frame", {
				Name = "ActionIndicator",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -12, 0.5, 0),
				Size = UDim2.fromOffset(isTouchDevice and 32 or 28, isTouchDevice and 32 or 28),
				BorderSizePixel = 0,
				Parent = frame,
			})
			addCorner(indicator, UDim.new(0, 8))
			local holder
			holder, arrow = createIcon(indicator, "arrow-up-right", nativeTheme.AccentDark, UDim2.new(0.5, -8, 0.5, 0))
		end
		local control = { LeadingIcon = leadingHolder, ActionIndicator = indicator }
		function control:RefreshStyle(animated)
			local monochrome = NativeLibrary.ThemeName == "Mono"
			local accentedPrimary = primary and not monochrome
			local fill = config.Color or (accentedPrimary and nativeTheme.Accent or nativeTheme.Surface3)
			local edge = accentedPrimary and nativeTheme.Accent
				or nativeTheme.StrokeHover:Lerp(nativeTheme.Surface3, 0.75)
			if hovered and not section then
				fill = fill:Lerp(accentedPrimary and nativeTheme.Text or nativeTheme.Accent, 0.06)
				edge = nativeTheme.StrokeHover
			end
			local frameProperties = { BackgroundColor3 = fill, BackgroundTransparency = section and 1 or 0 }
			local strokeProperties = { Color = edge, Transparency = section and 1 or 0 }
			if animated then
				animate(frame, frameProperties, 0.12)
				animate(stroke, strokeProperties, 0.12)
			else
				for property, value in pairs(frameProperties) do
					frame[property] = value
				end
				for property, value in pairs(strokeProperties) do
					stroke[property] = value
				end
			end
			local foreground = accentedPrimary and nativeTheme.AccentDark
				or (config.Danger and nativeTheme.Error or nativeTheme.Text)
			title.TextColor3 = foreground
			if description then
				description.TextColor3 = accentedPrimary and nativeTheme.AccentDark:Lerp(nativeTheme.Accent, 0.28)
					or nativeTheme.Muted
			end
			if leading then
				leading.ImageColor3 = foreground
			end
			if indicator then
				indicator.BackgroundColor3 = monochrome and nativeTheme.Surface2
					or (primary and nativeTheme.AccentDark or nativeTheme.Accent)
				arrow.ImageColor3 = monochrome and nativeTheme.Text
					or (primary and nativeTheme.Accent or nativeTheme.AccentDark)
			else
				arrow.ImageColor3 = hovered and nativeTheme.Text or nativeTheme.Muted
			end
		end

		function control:SetText(text)
			title.Text = text
		end
		control:RefreshStyle()
		frame.MouseEnter:Connect(function()
			hovered = true
			control:RefreshStyle(true)
		end)
		frame.MouseLeave:Connect(function()
			hovered = false
			control:RefreshStyle(true)
		end)
		frame.MouseButton1Click:Connect(function()
			if not section then
				createRipple(frame)
			end
			invokeCallback(config.Callback)
		end)
		return registerElement(self, config, control, frame, "Button")
	end

	function NativeTab:Toggle(toggleConfig)
		local toggleCard, toggleStroke
		toggleConfig, toggleCard, toggleStroke = createInteractiveCard(
			self,
			toggleConfig,
			{ Title = "Name", Description = "Desc", CurrentValue = "Default", Value = "Default" },
			"TextButton",
			56,
			"Toggle"
		)
		local toggleTrack = createInstance("Frame", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -14, 0.5, 0),
			Size = isTouchDevice and UDim2.fromOffset(44, 24) or UDim2.fromOffset(36, 20),
			BackgroundColor3 = nativeTheme.Surface3,
			BorderSizePixel = 0,
			Parent = toggleCard,
		})
		addCorner(toggleTrack, UDim.new(1, 0))
		addStroke(toggleTrack, nativeTheme.Stroke)
		local toggleThumb = createInstance("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 3, 0.5, 0),
			Size = isTouchDevice and UDim2.fromOffset(18, 18) or UDim2.fromOffset(14, 14),
			BackgroundColor3 = nativeTheme.Muted,
			BorderSizePixel = 0,
			Parent = toggleTrack,
		})
		addCorner(toggleThumb, UDim.new(1, 0))
		local toggleGlow = createInstance("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, 24, 1, 24),
			BackgroundTransparency = 1,
			Image = nativeAssets.Glow,
			ImageColor3 = nativeTheme.Accent,
			ImageTransparency = 1,
			ZIndex = 0,
			Parent = toggleTrack,
		})
		local toggleControl = { Value = toggleConfig.Default == true }
		local function updateToggle(animateThumb)
			local checked = toggleControl.Value
			local transitionDuration = animateThumb and 0.25 or 0
			animate(
				toggleTrack,
				{
					BackgroundColor3 = checked and nativeTheme.Surface3:Lerp(nativeTheme.Accent, 0.35)
						or nativeTheme.Surface3,
				},
				transitionDuration
			)
			animate(toggleGlow, { ImageTransparency = checked and 0.75 or 1 }, transitionDuration)
			local thumbSize = isTouchDevice and 18 or 14
			animate(toggleThumb, {
				Position = checked and UDim2.new(0, (isTouchDevice and 44 or 36) - 3 - thumbSize, 0.5, 0)
					or UDim2.new(0, 3, 0.5, 0),
				BackgroundColor3 = checked and nativeTheme.Accent or nativeTheme.Muted,
			}, transitionDuration, Enum.EasingStyle.Back)
			if animateThumb then
				animate(toggleThumb, { Size = UDim2.fromOffset(thumbSize + 4, thumbSize - 2) }, 0.08)
				task.delay(0.08, function()
					animate(toggleThumb, { Size = UDim2.fromOffset(thumbSize, thumbSize) }, 0.2, Enum.EasingStyle.Back)
				end)
			end
		end
		local userChanging = false
		function toggleControl:Set(enabled, skipCallback)
			enabled = enabled == true
			if enabled == toggleControl.Value then
				return
			end
			toggleControl.Value = enabled
			updateToggle(true)
			if not userChanging then
				addCardGradient(toggleStroke)
			end
			if not skipCallback then
				invokeCallback(toggleConfig.Callback, enabled)
			end
		end

		function toggleControl:Get()
			return toggleControl.Value
		end
		function toggleControl:RefreshStyle()
			updateToggle(false)
		end
		updateToggle(false)
		toggleCard.MouseButton1Click:Connect(function()
			userChanging = true
			toggleControl:Set(not toggleControl.Value)
			userChanging = false
		end)
		local registeredToggle = registerElement(self, toggleConfig, toggleControl, toggleCard, "Toggle")
		if toggleControl.Value then
			invokeCallback(toggleConfig.Callback, true)
		end
		return registeredToggle
	end

	function NativeTab:Slider(sliderConfig)
		local frameClass = "Frame"
		sliderConfig = normalizeOptions(
			sliderConfig,
			{ Title = "Name", Description = "Desc", CurrentValue = "Default", Value = "Default", Increment = "Step" }
		)
		local minimum = sliderConfig.Min or 0
		local maximum = sliderConfig.Max or 100
		local step = sliderConfig.Step or 1
		local suffix = sliderConfig.Suffix or ""
		local rangeAdapter = createRangeAdapter(minimum, maximum, step)
		local sliderHeight = descriptionCardHeight + (sliderConfig.Desc and 20 or 0)
		local sliderCard, sliderStroke = createCard(self, frameClass, sliderHeight, sliderConfig)
		decorateCard(sliderCard, sliderStroke)
		local sliderTitle = createLabel({
			Position = UDim2.fromOffset(14, 12),
			Size = UDim2.new(1, -120, 0, 18),
			Text = sliderConfig.Name or "Slider",
			Parent = sliderCard,
		})
		-- Keep the description below the value row and above the slider track.
		local sliderDescription
		if sliderConfig.Desc then
			sliderDescription = createLabel({
				Position = UDim2.fromOffset(14, 32),
				Size = UDim2.new(1, -28, 0, 17),
				Text = sliderConfig.Desc,
				TextSize = 13,
				FontFace = nativeFonts.Regular,
				TextColor3 = nativeTheme.Muted,
				Parent = sliderCard,
			})
		end
		local valueHolder = createInstance(frameClass, {
			Name = "ValueField",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -14, 0, 21),
			Size = UDim2.fromOffset(56, 28),
			BackgroundColor3 = nativeTheme.Surface,
			BorderSizePixel = 0,
			ClipsDescendants = true,
			Parent = sliderCard,
		})
		addCorner(valueHolder, UDim.new(0, 6))
		local valueStroke = addStroke(valueHolder)
		local valueLabel = createLabel({
			Name = "Value",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, -20, 1, 0),
			TextSize = 13,
			TextColor3 = nativeTheme.Accent,
			TextYAlignment = Enum.TextYAlignment.Center,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextTruncate = Enum.TextTruncate.None,
			Parent = valueHolder,
		})
		local textBox = createInstance("TextBox", {
			Name = "ValueInput",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, -20, 1, 0),
			AutomaticSize = Enum.AutomaticSize.None,
			BackgroundTransparency = 1,
			Text = "",
			TextColor3 = nativeTheme.Text,
			TextSize = 13,
			FontFace = nativeFonts.Medium,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
			ClearTextOnFocus = false,
			Visible = false,
			Parent = valueHolder,
		})
		createInstance("UISizeConstraint", { MinSize = Vector2.new(14, 0), Parent = textBox })
		local suffixLabel = createLabel({
			Size = UDim2.new(0, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			Text = suffix,
			TextSize = 13,
			TextColor3 = nativeTheme.Accent,
			TextTruncate = Enum.TextTruncate.None,
			Visible = false,
			Parent = valueHolder,
		})
		local textButton, editingValue =
			createInstance("TextButton", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Text = "",
				AutoButtonColor = false,
				ZIndex = 2,
				Parent = valueHolder,
			}), false
		local function resizeSliderValue()
			local scale = math.max(math.min(self.Window.Scale.Scale, 1), 0.01)
			local suffixWidth = editingValue and suffixLabel.TextBounds.X / scale or 0
			local textWidth = (editingValue and textBox.TextBounds.X or valueLabel.TextBounds.X) / scale
			local width = math.max(56, math.ceil(textWidth + suffixWidth + 20))
			valueHolder.Size = UDim2.fromOffset(width, 28)
			textBox.Position = UDim2.new(0.5, -suffixWidth / 2, 0.5, 0)
			textBox.Size = UDim2.new(1, -20 - suffixWidth, 1, 0)
			suffixLabel.AnchorPoint = Vector2.new(1, 0.5)
			suffixLabel.Position = UDim2.new(1, -10, 0.5, 0)
			if not sliderCard:GetAttribute("UICompact") then
				sliderTitle.Size = UDim2.new(1, -width - sliderTitle.Position.X.Offset - 28, 0, 18)
			end
		end
		valueLabel:GetPropertyChangedSignal("TextBounds"):Connect(function()
			if not editingValue then
				resizeSliderValue(false)
			end
		end)
		textBox:GetPropertyChangedSignal("TextBounds"):Connect(function()
			if editingValue then
				resizeSliderValue()
			end
		end)
		local valueScaleConnection = self.Window.Scale:GetPropertyChangedSignal("Scale"):Connect(resizeSliderValue)
		local sliderTrack = createInstance(frameClass, {
			Position = UDim2.new(0, 14, 0, sliderHeight - 18),
			Size = UDim2.new(1, -28, 0, 5),
			BackgroundColor3 = nativeTheme.Surface3,
			BorderSizePixel = 0,
			Parent = sliderCard,
		})
		addCorner(sliderTrack, UDim.new(1, 0))
		local sliderFill = createInstance(frameClass, {
			Size = UDim2.new(0, 0, 1, 0),
			BackgroundColor3 = nativeTheme.Accent,
			BorderSizePixel = 0,
			Parent = sliderTrack,
		})
		addCorner(sliderFill, UDim.new(1, 0))
		local thumbGlow = createInstance("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0, 0, 0.5, 0),
			Size = UDim2.fromOffset(28, 28),
			BackgroundTransparency = 1,
			Image = nativeAssets.Glow,
			ImageColor3 = nativeTheme.Accent,
			ImageTransparency = 0.85,
			ZIndex = 2,
			Parent = sliderTrack,
		})
		local sliderThumb = createInstance(frameClass, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0, 0, 0.5, 0),
			Size = UDim2.fromOffset(12, 12),
			BackgroundColor3 = nativeTheme.Accent,
			BorderSizePixel = 0,
			ZIndex = 3,
			Parent = sliderTrack,
		})
		addCorner(sliderThumb, UDim.new(1, 0))
		local sliderHitbox = createInstance("TextButton", {
			Position = UDim2.new(0, 8, 0, sliderHeight - (isTouchDevice and 37 or 31)),
			Size = UDim2.new(1, -16, 0, isTouchDevice and 40 or 28),
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
			ZIndex = 4,
			Parent = sliderCard,
		})
		local sliderControl, draggingSlider =
			{ Value = math.clamp(sliderConfig.Default or minimum, minimum, maximum) }, false
		textButton.MouseEnter:Connect(function()
			animate(valueStroke, { Color = nativeTheme.StrokeHover }, 0.12)
		end)
		textButton.MouseLeave:Connect(function()
			if not textBox:IsFocused() then
				animate(valueStroke, { Color = nativeTheme.Stroke }, 0.2)
			end
		end)
		textButton.MouseButton1Click:Connect(function()
			editingValue = true
			textBox.Text = rangeAdapter.format(sliderControl.Value)
			valueLabel.Visible = false
			textBox.Visible = true
			suffixLabel.Visible = suffix ~= ""
			textButton.Visible = false
			animate(valueStroke, { Color = nativeTheme.StrokeHover }, 0.12)
			textBox:CaptureFocus()
			task.defer(resizeSliderValue, false)
		end)
		textBox.FocusLost:Connect(function()
			local parsedValue = tonumber(textBox.Text)
			editingValue = false
			textBox.Visible = false
			suffixLabel.Visible = false
			valueLabel.Visible = true
			textButton.Visible = true
			animate(valueStroke, { Color = nativeTheme.Stroke }, 0.2)
			if parsedValue then
				sliderControl:Set(parsedValue)
			end
			resizeSliderValue(false)
		end)
		sliderHitbox.MouseEnter:Connect(function()
			if not draggingSlider then
				animate(thumbGlow, { ImageTransparency = 0.78, Size = UDim2.fromOffset(34, 34) }, 0.15)
			end
		end)
		sliderHitbox.MouseLeave:Connect(function()
			if not draggingSlider then
				animate(thumbGlow, { ImageTransparency = 0.85, Size = UDim2.fromOffset(28, 28) }, 0.2)
			end
		end)
		local snap = rangeAdapter.snap
		local function getSliderRatio()
			return maximum - minimum == 0 and 0 or (sliderControl.Value - minimum) / (maximum - minimum)
		end

		local function setSliderRatio(ratio, duration, immediate)
			immediate = immediate or Enum.EasingStyle.Linear
			animate(sliderFill, { Size = UDim2.new(ratio, 0, 1, 0) }, duration, immediate)
			animate(sliderThumb, { Position = UDim2.new(ratio, 0, 0.5, 0) }, duration, immediate)
			animate(thumbGlow, { Position = UDim2.new(ratio, 0, 0.5, 0) }, duration, immediate)
		end

		local function tweenSliderRatio(ratio, duration)
			setSliderRatio(getSliderRatio(), ratio, duration)
			valueLabel.Text = rangeAdapter.format(sliderControl.Value) .. suffix
		end

		local function nudgeSliderRatio(targetRatio)
			local currentRatio = getSliderRatio()
			local trackWidth = math.max(sliderTrack.AbsoluteSize.X, 1)
			local stepRatio = (currentRatio >= targetRatio and 1 or -1) * (5 / trackWidth)
			setSliderRatio(math.clamp(currentRatio + stepRatio, 0, 1), 0.22, Enum.EasingStyle.Quint)
			task.delay(0.22, function()
				if not draggingSlider then
					setSliderRatio(getSliderRatio(), 0.18, Enum.EasingStyle.Quint)
				end
			end)
			valueLabel.Text = rangeAdapter.format(sliderControl.Value) .. suffix
		end

		local function updateSlider()
			animate(sliderThumb, { Size = UDim2.fromOffset(14, 12) }, 0.08)
			animate(thumbGlow, { Size = UDim2.fromOffset(32, 32), ImageTransparency = 0.78 }, 0.12)
			task.delay(0.1, function()
				animate(sliderThumb, { Size = UDim2.fromOffset(12, 12) }, 0.25, Enum.EasingStyle.Quint)
				animate(thumbGlow, { Size = UDim2.fromOffset(28, 28), ImageTransparency = 0.85 }, 0.25)
			end)
		end

		function sliderControl:Set(value, skipCallback)
			value = snap(tonumber(value) or minimum)
			if value == sliderControl.Value then
				return
			end
			local ratio = getSliderRatio()
			sliderControl.Value = value
			if draggingSlider then
				tweenSliderRatio(0.05)
			else
				nudgeSliderRatio(ratio)
				updateSlider()
				addCardGradient(sliderStroke)
			end
			if not skipCallback then
				invokeCallback(sliderConfig.Callback, value)
			end
		end

		function sliderControl:Get()
			return sliderControl.Value
		end

		local function updateSliderFromPointer(pointerX)
			local pointerRatio =
				math.clamp((pointerX - sliderTrack.AbsolutePosition.X) / sliderTrack.AbsoluteSize.X, 0, 1)
			sliderControl:Set(minimum + (maximum - minimum) * pointerRatio)
		end
		sliderHitbox.InputBegan:Connect(function(input)
			if isPrimaryInput(input) then
				draggingSlider = true
				animate(sliderThumb, { Size = UDim2.fromOffset(16, 16) }, 0.15, Enum.EasingStyle.Back)
				animate(thumbGlow, { Size = UDim2.fromOffset(44, 44), ImageTransparency = 0.7 }, 0.15)
				updateSliderFromPointer(getPointerPosition().X)
			end
		end)
		self.Window:_listen("Changed", function(input)
			if draggingSlider and isPointerMovement(input) then
				updateSliderFromPointer(getPointerPosition().X)
			end
		end, sliderControl)
		self.Window:_listen("Ended", function(input)
			if draggingSlider and isPrimaryInput(input) then
				draggingSlider = false
				animate(sliderThumb, { Size = UDim2.fromOffset(12, 12) }, 0.2)
				animate(thumbGlow, { Size = UDim2.fromOffset(28, 28), ImageTransparency = 0.85 }, 0.2)
			end
		end, sliderControl)
		sliderControl.Value = snap(sliderControl.Value)
		tweenSliderRatio(0)
		task.defer(resizeSliderValue, true)
		table.insert(sliderControl._listeners, function()
			valueScaleConnection:Disconnect()
		end)
		sliderControl.ValueHolder = valueHolder
		sliderControl.Track = sliderTrack
		sliderControl.HitArea = sliderHitbox
		sliderControl.TitleLabel = sliderTitle
		sliderControl.DescriptionLabel = sliderDescription
		-- Responsive text wrapping changes the card height; keep input below the text.
		function sliderControl.UISetHeaderHeight(height)
			sliderCard.Size = UDim2.new(sliderCard.Size.X.Scale, sliderCard.Size.X.Offset, 0, height)
			sliderTrack.Position = UDim2.new(0, 14, 0, height - 18)
			local compact = sliderCard:GetAttribute("UICompact")
			sliderHitbox.Position = UDim2.new(0, 8, 0, height - (compact and 38 or (isTouchDevice and 37 or 31)))
		end
		sliderControl.ValueLabel = valueLabel
		sliderControl.ValueInput = textBox
		return registerElement(self, sliderConfig, sliderControl, sliderCard, "Slider")
	end

	function NativeTab:Dropdown(dropdownConfig)
		local frameClass = "Frame"
		dropdownConfig = normalizeOptions(dropdownConfig, {
			Title = "Name",
			Description = "Desc",
			CurrentOption = "Default",
			Value = "Default",
			MultipleOptions = "Multi",
			Values = "Options",
		})
		if dropdownConfig.Multi and type(dropdownConfig.Default) ~= "table" and dropdownConfig.Default ~= nil then
			dropdownConfig.Default = { dropdownConfig.Default }
		elseif not dropdownConfig.Multi and type(dropdownConfig.Default) == "table" then
			dropdownConfig.Default = dropdownConfig.Default[1]
		end
		local multiSelect = dropdownConfig.Multi == true
		local optionValues = dropdownConfig.Options or {}
		local dropdownCard, dropdownStroke, dropdownHeight
		dropdownConfig, dropdownCard, dropdownStroke, dropdownHeight =
			createInteractiveCard(self, dropdownConfig, {}, frameClass)
		dropdownCard.ClipsDescendants = true
		local dropdownHeader = createInstance("TextButton", {
			Size = UDim2.new(1, 0, 0, dropdownHeight),
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
			Parent = dropdownCard,
		})
		local titleLabel, descriptionLabel =
			createCardLabels(dropdownHeader, dropdownConfig.Name or "Dropdown", dropdownConfig.Desc, 180)
		local valueHolder = createInstance(frameClass, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(60, chipHeight),
			BackgroundColor3 = nativeTheme.Surface,
			BorderSizePixel = 0,
			ClipsDescendants = true,
			Parent = dropdownHeader,
		})
		addCorner(valueHolder, UDim.new(0, 6))
		local valueStroke = addStroke(valueHolder)
		local selectionLabel = createLabel({
			Position = UDim2.fromOffset(10, 0),
			Size = UDim2.new(1, -34, 1, 0),
			TextColor3 = nativeTheme.Muted,
			TextSize = 13,
			TextTruncate = Enum.TextTruncate.None,
			ClipsDescendants = true,
			Parent = valueHolder,
		})
		local chevron = createChevron(valueHolder, 1, -6)
		local measurementLabel, emptySummary =
			createLabel({
				Size = UDim2.fromOffset(0, chipHeight),
				AutomaticSize = Enum.AutomaticSize.X,
				TextSize = 13,
				Visible = false,
				Parent = valueHolder,
			}), ""
		local function selectionSummary()
			local summary = emptySummary:gsub("<[^>]*>", "")
			measurementLabel.Text = summary
			if measurementLabel.TextBounds.X <= 146 then
				return summary
			end
			while #summary > 1 do
				local lastCharacter = utf8.offset(summary, -1)
				summary = summary:sub(1, lastCharacter - 1)
				measurementLabel.Text = summary .. ".."
				if measurementLabel.TextBounds.X <= 146 then
					return summary .. ".."
				end
			end
			return ".."
		end

		local function resizeDropdownValue(immediate)
			if dropdownCard:GetAttribute("UIStacked") then
				return
			end
			local valueWidth = math.clamp(selectionLabel.TextBounds.X + 10 + 34, 60, 190)
			reserveControlWidth(titleLabel, descriptionLabel, valueWidth + 20)
			if immediate then
				valueHolder.Size = UDim2.fromOffset(valueWidth, chipHeight)
			else
				animate(valueHolder, { Size = UDim2.fromOffset(valueWidth, chipHeight) }, 0.2)
			end
		end
		selectionLabel:GetPropertyChangedSignal("TextBounds"):Connect(function()
			resizeDropdownValue(false)
		end)
		local maxVisibleOptions = tonumber(dropdownConfig.MaxVisibleOptions)
		local optionsProperties = {
			Position = UDim2.new(0, 10, 0, dropdownHeight),
			Size = UDim2.new(1, -20, 0, 0),
			BackgroundTransparency = 1,
			Parent = dropdownCard,
		}
		if maxVisibleOptions then
			maxVisibleOptions = math.max(1, math.floor(maxVisibleOptions))
			optionsProperties.BorderSizePixel = 0
			optionsProperties.CanvasSize = UDim2.new()
			optionsProperties.AutomaticCanvasSize = Enum.AutomaticSize.Y
			optionsProperties.ScrollingDirection = Enum.ScrollingDirection.Y
			optionsProperties.ScrollBarThickness = 3
			optionsProperties.ScrollBarImageColor3 = nativeTheme.StrokeHover
		end
		local optionList = createInstance(maxVisibleOptions and "ScrollingFrame" or frameClass, optionsProperties)
		createInstance(
			"UIListLayout",
			{ SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4), Parent = optionList }
		)
		local dropdownControl = { Open = false }
		local selectedOptions = {}
		local optionControls, searchQuery = {}, ""
		local searchThreshold = dropdownConfig.SearchAfter or 6
		local searchRow = createInstance(frameClass, {
			Size = UDim2.new(1, 0, 0, dropdownOptionHeight),
			BackgroundColor3 = nativeTheme.Surface,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			LayoutOrder = 0,
			Visible = false,
			Parent = optionList,
		})
		addCorner(searchRow, UDim.new(0, 6))
		local searchStroke = addStroke(searchRow, nativeTheme.Stroke, 1)
		local searchInput = createInstance("TextBox", {
			Position = UDim2.fromOffset(12, 0),
			Size = UDim2.new(1, -20, 1, 0),
			BackgroundTransparency = 1,
			Text = "",
			PlaceholderText = "Search",
			PlaceholderColor3 = nativeTheme.Muted,
			TextColor3 = nativeTheme.Text,
			TextSize = 13,
			FontFace = nativeFonts.Regular,
			TextXAlignment = Enum.TextXAlignment.Left,
			ClearTextOnFocus = false,
			TextTransparency = 1,
			Parent = searchRow,
		})
		local function matchesSearch(option)
			return searchQuery == "" or string.find(string.lower(tostring(option)), searchQuery, 1, true) ~= nil
		end
		if multiSelect then
			for index, option in ipairs(dropdownConfig.Default or {}) do
				selectedOptions[option] = true
			end
		elseif dropdownConfig.Default ~= nil then
			selectedOptions[dropdownConfig.Default] = true
		end

		local function getSelection()
			if multiSelect then
				local selection = {}
				for index, option in ipairs(optionValues) do
					if selectedOptions[option] then
						table.insert(selection, option)
					end
				end
				return selection
			end
			for index, option in ipairs(optionValues) do
				if selectedOptions[option] then
					return option
				end
			end
			return nil
		end

		local function updateSelection()
			local selected = getSelection()
			if multiSelect then
				emptySummary = #selected > 0 and table.concat(selected, ", ") or "None"
			else
				emptySummary = selected ~= nil and tostring(selected) or "None"
			end
			selectionLabel.Text = selectionSummary()
			for option, optionControl in pairs(optionControls) do
				local isSelected = selectedOptions[option] == true
				if optionControl.On ~= isSelected then
					optionControl.On = isSelected
					animate(
						optionControl.Label,
						{ TextColor3 = isSelected and nativeTheme.Text or nativeTheme.Muted },
						0.15
					)
					if dropdownControl.Open then
						animate(optionControl.Check, { ImageTransparency = isSelected and 0 or 1 }, 0.15)
						animate(
							optionControl.CheckScale,
							{ Scale = isSelected and 1 or 0.6 },
							isSelected and 0.3 or 0.15,
							isSelected and Enum.EasingStyle.Back or Enum.EasingStyle.Quint
						)
					end
				end
			end
		end

		local function updateOptionVisibility()
			local visibleCount = 0
			for index, option in ipairs(optionValues) do
				if matchesSearch(option) then
					visibleCount += 1
				end
			end
			return visibleCount
		end

		local function updateSearch()
			for option, optionControl in pairs(optionControls) do
				optionControl.Frame.Visible = matchesSearch(option)
			end
		end

		local function updateDropdownHeight()
			local height = dropdownHeight + 8 + (searchRow.Visible and dropdownOptionHeight + 4 or 0)
			for _, label in ipairs(optionValues) do
				if matchesSearch(label) then
					local row = optionControls[label]
					height += (row and row.Frame.Size.Y.Offset or dropdownOptionHeight) + 4
				end
			end
			if maxVisibleOptions then
				height = math.min(
					height,
					dropdownHeight
						+ 8
						+ maxVisibleOptions * (dropdownOptionHeight + 4)
						+ (searchRow.Visible and dropdownOptionHeight + 4 or 0)
				)
				optionList.Size = UDim2.new(1, -20, 0, math.max(0, height - dropdownHeight - 8))
			end
			return height
		end

		local function setDropdownOpen(open)
			dropdownControl.Open = open
			searchRow.Visible = #optionValues > searchThreshold
			if not open then
				searchQuery = ""
				searchInput.Text = ""
				updateSearch()
			end
			animate(
				dropdownCard,
				{ Size = controlSize(dropdownCard, open and updateDropdownHeight() or dropdownHeight) },
				0.3,
				Enum.EasingStyle.Quint
			)
			animate(searchRow, { BackgroundTransparency = open and 0 or 1 }, 0.2)
			animate(searchStroke, { Transparency = open and 0 or 1 }, 0.2)
			animate(searchInput, { TextTransparency = open and 0 or 1 }, 0.2)
			chevron:Set(open)
			animate(valueStroke, { Color = open and nativeTheme.StrokeHover or nativeTheme.Stroke }, 0.2)
			local function styleOption(optionControl)
				if not optionControl.Stroke then
					optionControl.Stroke = addStroke(optionControl.Frame, nativeTheme.Stroke, 1)
				end
				local isHighlighted = open and optionControl.On
				animate(optionControl.Check, { ImageTransparency = isHighlighted and 0 or 1 }, 0.18)
				optionControl.CheckScale.Scale = isHighlighted and 1 or 0.6
				animate(optionControl.Label, { TextTransparency = open and 0 or 1 }, 0.18)
				animate(optionControl.Stroke, { Transparency = open and 0 or 1 }, 0.18)
				animate(optionControl.Frame, { BackgroundTransparency = open and 0 or 1 }, 0.18)
			end
			if open then
				local openGeneration = (dropdownControl._openGeneration or 0) + 1
				dropdownControl._openGeneration = openGeneration
				task.spawn(function()
					local animateFirstOption = true
					for index, option in ipairs(optionValues) do
						local optionControl = optionControls[option]
						if optionControl and optionControl.Frame.Visible then
							if not animateFirstOption then
								task.wait(0.025)
								if dropdownControl._openGeneration ~= openGeneration or not dropdownControl.Open then
									return
								end
							end
							animateFirstOption = false
							styleOption(optionControl)
						end
					end
				end)
			else
				local closeGeneration = (dropdownControl._openGeneration or 0) + 1
				dropdownControl._openGeneration = closeGeneration
				local visibleOptions = {}
				for index, option in ipairs(optionValues) do
					local optionControl = optionControls[option]
					if optionControl and optionControl.Frame.Visible then
						table.insert(visibleOptions, optionControl)
					end
				end
				task.spawn(function()
					for optionIndex = #visibleOptions, 1, -1 do
						styleOption(visibleOptions[optionIndex])
						if optionIndex > 1 then
							task.wait(0.015)
							if dropdownControl._openGeneration ~= closeGeneration or dropdownControl.Open then
								return
							end
						end
					end
				end)
			end
		end

		local function rebuildOptions()
			local optionConnections = {}
			for index, option in ipairs(optionValues) do
				optionConnections[option] = index
			end
			for option, optionControl in pairs(optionControls) do
				if not optionConnections[option] then
					optionControl.Frame:Destroy()
					optionControls[option] = nil
				end
			end
			for index, option in ipairs(optionValues) do
				local optionControl = optionControls[option]
				if optionControl then
					optionControl.Frame.LayoutOrder = index
					continue
				end
				local optionButton = createInstance("TextButton", {
					Size = UDim2.new(1, 0, 0, dropdownOptionHeight),
					BackgroundColor3 = nativeTheme.Surface,
					BackgroundTransparency = 1,
					Text = "",
					AutoButtonColor = false,
					LayoutOrder = index,
					Parent = optionList,
				})
				addCorner(optionButton, UDim.new(0, 6))
				local checkIcon = createInstance("ImageLabel", {
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -10, 0.5, 0),
					Size = UDim2.fromOffset(14, 14),
					BackgroundTransparency = 1,
					ImageColor3 = nativeTheme.Accent,
					ImageTransparency = 1,
					ScaleType = Enum.ScaleType.Fit,
					Parent = optionButton,
				})
				applyIcon(checkIcon, "check")
				local checkScale = createInstance("UIScale", { Scale = 0.6, Parent = checkIcon })
				local optionLabel = createLabel({
					Position = UDim2.fromOffset(12, -1),
					Size = UDim2.new(1, -36, 1, 0),
					Text = tostring(option),
					TextSize = 13,
					TextColor3 = nativeTheme.Muted,
					TextTransparency = 1,
					Parent = optionButton,
				})
				optionButton.MouseEnter:Connect(function()
					animate(optionLabel, { TextColor3 = nativeTheme.Text }, 0.15)
					local optionControl = optionControls[option]
					if optionControl and optionControl.Stroke then
						animate(optionControl.Stroke, { Color = nativeTheme.StrokeHover }, 0.12)
					end
				end)
				optionButton.MouseLeave:Connect(function()
					animate(
						optionLabel,
						{ TextColor3 = selectedOptions[option] and nativeTheme.Text or nativeTheme.Muted },
						0.2
					)
					local optionControl = optionControls[option]
					if optionControl and optionControl.Stroke then
						animate(optionControl.Stroke, { Color = nativeTheme.Stroke }, 0.2)
					end
				end)
				optionButton.MouseButton1Click:Connect(function()
					if selectedOptions[option] then
						selectedOptions[option] = nil
					else
						if not multiSelect then
							selectedOptions = {}
						end
						selectedOptions[option] = true
					end
					updateSelection()
					invokeCallback(dropdownConfig.Callback, getSelection())
					if not multiSelect and selectedOptions[option] then
						setDropdownOpen(false)
					end
				end)
				optionControls[option] = {
					Frame = optionButton,
					Label = optionLabel,
					Check = checkIcon,
					CheckScale = checkScale,
					Stroke = nil,
					On = nil,
				}
			end
			updateSearch()
			if dropdownControl.Open then
				dropdownCard.Size = controlSize(dropdownCard, updateDropdownHeight())
			end
		end

		function dropdownControl:Set(value, skipCallback)
			selectedOptions = {}
			if multiSelect then
				for index, option in ipairs(type(value) == "table" and value or { value }) do
					selectedOptions[option] = true
				end
			elseif value ~= nil then
				selectedOptions[value] = true
			end
			updateSelection()
			addCardGradient(dropdownStroke)
			if not skipCallback then
				invokeCallback(dropdownConfig.Callback, getSelection())
			end
		end

		function dropdownControl:Get()
			return getSelection()
		end

		function dropdownControl:Refresh(options, skipCallback)
			optionValues = options or {}
			if not skipCallback then
				selectedOptions = {}
			end
			rebuildOptions()
			updateSelection()
			if dropdownControl.Open then
				setDropdownOpen(true)
			end
		end

		function dropdownControl:SetOpen(open)
			setDropdownOpen(open == true)
		end
		dropdownHeader.MouseButton1Click:Connect(function()
			setDropdownOpen(not dropdownControl.Open)
		end)
		searchInput:GetPropertyChangedSignal("Text"):Connect(function()
			searchQuery = string.lower(searchInput.Text)
			updateSearch()
			if dropdownControl.Open then
				animate(
					dropdownCard,
					{ Size = controlSize(dropdownCard, updateDropdownHeight()) },
					0.2,
					Enum.EasingStyle.Quint
				)
			end
		end)
		rebuildOptions()
		updateSelection()
		task.defer(resizeDropdownValue, true)
		dropdownControl.TitleLabel = titleLabel
		dropdownControl.DescriptionLabel = descriptionLabel
		dropdownControl.ValueHolder = valueHolder
		dropdownControl.UIResizeValue = resizeDropdownValue
		dropdownControl.UISetHeaderHeight = function(height)
			if dropdownHeight == height then
				return
			end
			dropdownHeight = height
			dropdownHeader.Size = UDim2.new(1, 0, 0, height)
			optionList.Position = UDim2.new(0, 10, 0, height)
			dropdownCard.Size = controlSize(dropdownCard, dropdownControl.Open and updateDropdownHeight() or height)
		end
		dropdownControl.UIOptionRows = optionControls
		dropdownControl.UIReflow = function()
			if dropdownControl.Open then
				dropdownCard.Size = controlSize(dropdownCard, updateDropdownHeight())
			end
		end
		return registerElement(self, dropdownConfig, dropdownControl, dropdownCard, "Dropdown")
	end

	function NativeTab:Input(inputConfig)
		local inputCard, inputStroke, inputHeight, inputTitle, inputDescription
		inputConfig, inputCard, inputStroke, inputHeight, inputTitle, inputDescription =
			createInteractiveCard(self, inputConfig, {
				Title = "Name",
				Description = "Desc",
				PlaceholderText = "Placeholder",
				CurrentValue = "Default",
				Value = "Default",
			}, "Frame", 160, "Input")
		local inputHolder = createInstance("Frame", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(170, 30),
			BackgroundColor3 = nativeTheme.Surface,
			BorderSizePixel = 0,
			Parent = inputCard,
		})
		addCorner(inputHolder, UDim.new(0, 6))
		local inputBorder = addStroke(inputHolder)
		local inputIcon = inputConfig.Icon
		if inputIcon then
			createIcon(inputHolder, inputIcon, nativeTheme.Muted, UDim2.new(0, 8, 0.5, 0))
		end
		local valueInput = createInstance("TextBox", {
			Name = "ValueInput",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, inputIcon and 30 or 8, 0.5, 0),
			Size = UDim2.new(1, inputIcon and -38 or -16, 1, -8),
			TextYAlignment = Enum.TextYAlignment.Center,
			BackgroundTransparency = 1,
			Text = inputConfig.Default or "",
			PlaceholderText = inputConfig.Placeholder or "",
			PlaceholderColor3 = nativeTheme.Muted,
			TextColor3 = nativeTheme.Text,
			TextSize = 14,
			TextScaled = false,
			TextWrapped = false,
			FontFace = nativeFonts.Regular,
			TextXAlignment = Enum.TextXAlignment.Center,
			ClearTextOnFocus = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ClipsDescendants = true,
			Parent = inputHolder,
		})
		local valueMeasure = createLabel({
			Name = "ValueMeasure",
			Size = UDim2.fromOffset(0, 24),
			AutomaticSize = Enum.AutomaticSize.X,
			FontFace = nativeFonts.Regular,
			TextSize = 14,
			TextTruncate = Enum.TextTruncate.None,
			Visible = false,
			Parent = inputHolder,
		})
		inputHolder.ClipsDescendants = true
		local changingInput = false
		local valuePadding = inputIcon and 38 or 16
		local function resizeInputValue(immediate)
			if inputCard:GetAttribute("UIMultiline") then
				valueInput.TextScaled = false
				valueInput.TextTruncate = Enum.TextTruncate.None
				return
			end
			local scale = math.max(self.Window.Scale.Scale, 0.01)
			valueMeasure.Text = valueInput.Text ~= "" and valueInput.Text or valueInput.PlaceholderText
			local textWidth = valueMeasure.TextBounds.X / scale
			local desiredWidth = math.max(90, math.ceil(textWidth + valuePadding + 4) + (changingInput and 8 or 0))
			if inputCard:GetAttribute("UIValueWidth") ~= desiredWidth then
				inputCard:SetAttribute("UIValueWidth", desiredWidth)
			end
			if not inputCard:GetAttribute("UIStacked") then
				local cardWidth = inputCard.AbsoluteSize.X / scale
				local width = math.min(desiredWidth, math.max(1, math.min(240, cardWidth - 130)))
				inputHolder.AnchorPoint = Vector2.new(1, 0.5)
				inputHolder.Position = UDim2.new(1, -10, 0.5, 0)
				inputHolder.Size = UDim2.fromOffset(width, 30)
				if not inputCard:GetAttribute("UICompact") then
					reserveControlWidth(inputTitle, inputDescription, width + 20)
				end
			end
			local availableWidth = math.max(1, inputHolder.AbsoluteSize.X / scale - valuePadding - 2)
			valueInput.TextScaled = false
			valueInput.TextWrapped = false
			valueInput.TextSize = changingInput and 14
				or math.clamp(math.floor(14 * availableWidth / math.max(textWidth, 1)), 12, 14)
			valueInput.TextXAlignment = changingInput and Enum.TextXAlignment.Left or Enum.TextXAlignment.Center
			valueInput.TextTruncate = changingInput and Enum.TextTruncate.None or Enum.TextTruncate.AtEnd
		end
		inputCard:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			resizeInputValue(true)
		end)
		valueInput:GetPropertyChangedSignal("Text"):Connect(function()
			resizeInputValue(false)
		end)
		valueInput:GetPropertyChangedSignal("PlaceholderText"):Connect(function()
			resizeInputValue(false)
		end)
		valueMeasure:GetPropertyChangedSignal("TextBounds"):Connect(resizeInputValue)
		inputHolder:GetPropertyChangedSignal("AbsoluteSize"):Connect(resizeInputValue)
		local inputScaleConnection = self.Window.Scale:GetPropertyChangedSignal("Scale"):Connect(resizeInputValue)
		task.defer(resizeInputValue, true)
		valueInput.Focused:Connect(function()
			changingInput = true
			animate(inputBorder, { Color = nativeTheme.StrokeHover }, 0.15)
			resizeInputValue(false)
		end)
		valueInput.FocusLost:Connect(function(input)
			changingInput = false
			animate(inputBorder, { Color = nativeTheme.Stroke }, 0.15)
			resizeInputValue(false)
			if inputConfig.Numeric then
				local parsedValue = tonumber(valueInput.Text)
				if not parsedValue then
					valueInput.Text = ""
					return
				end
			end
			invokeCallback(inputConfig.Callback, valueInput.Text, input)
		end)
		local control = registerElement(self, inputConfig, {
			Set = function(control, value)
				valueInput.Text = tostring(value)
				addCardGradient(inputStroke)
			end,
			Get = function()
				return valueInput.Text
			end,
		}, inputCard, "Input")
		control.TitleLabel = inputTitle
		control.DescriptionLabel = inputDescription
		control.ValueInput = valueInput
		control.ValueHolder = inputHolder
		control.UIResizeValue = resizeInputValue
		table.insert(control._listeners, function()
			inputScaleConnection:Disconnect()
		end)
		return control
	end

	function NativeTab:Keybind(keybindConfig)
		local keybindCard, keybindStroke, keybindHeight, keybindTitle, keybindDescription
		keybindConfig, keybindCard, keybindStroke, keybindHeight, keybindTitle, keybindDescription =
			createInteractiveCard(
				self,
				keybindConfig,
				{ Title = "Name", Description = "Desc", CurrentKeybind = "Default", Value = "Default" },
				"Frame",
				110,
				"Keybind"
			)
		if type(keybindConfig.Default) == "string" then
			keybindConfig.Default = Enum.KeyCode[keybindConfig.Default]
		end
		local keybindButton = createInstance("TextButton", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(44, chipHeight),
			BackgroundColor3 = nativeTheme.Surface,
			BorderSizePixel = 0,
			Text = "",
			AutoButtonColor = false,
			ClipsDescendants = true,
			Parent = keybindCard,
		})
		addCorner(keybindButton, UDim.new(0, 6))
		local keybindBorder = addStroke(keybindButton)
		local keyLabel = createLabel({
			Size = UDim2.new(1, 0, 1, 0),
			TextSize = 13,
			TextColor3 = nativeTheme.Muted,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextTruncate = Enum.TextTruncate.None,
			Parent = keybindButton,
		})
		local keybindControl = { Value = keybindConfig.Default, Listening = false }
		local function resizeKeybindValue(immediate)
			if keybindCard:GetAttribute("UIStacked") then
				return
			end
			local keyWidth = math.max(keyLabel.TextBounds.X + 20, isTouchDevice and 44 or 36)
			reserveControlWidth(keybindTitle, keybindDescription, keyWidth + 20)
			if immediate then
				keybindButton.Size = UDim2.fromOffset(keyWidth, chipHeight)
			else
				animate(keybindButton, { Size = UDim2.fromOffset(keyWidth, chipHeight) }, 0.2)
			end
		end
		keyLabel:GetPropertyChangedSignal("TextBounds"):Connect(function()
			resizeKeybindValue(false)
		end)
		local function updateKeybind()
			keyLabel.Text = keybindControl.Listening and "..." or formatKeyName(keybindControl.Value)
			animate(
				keybindBorder,
				{ Color = keybindControl.Listening and nativeTheme.StrokeHover or nativeTheme.Stroke },
				0.15
			)
			animate(
				keyLabel,
				{ TextColor3 = keybindControl.Listening and nativeTheme.Accent or nativeTheme.Muted },
				0.15
			)
		end

		function keybindControl:Set(keyCode, skipCallback)
			local listening = keybindControl.Listening
			keybindControl.Value = keyCode
			keybindControl.Listening = false
			updateKeybind()
			if not listening then
				addCardGradient(keybindStroke)
			end
			if not skipCallback then
				invokeCallback(keybindConfig.OnChanged, keyCode)
			end
		end
		keybindButton.MouseButton1Click:Connect(function()
			keybindControl.Listening = not keybindControl.Listening
			updateKeybind()
		end)
		self.Window:_listen("Began", function(input, processed)
			if input.UserInputType ~= Enum.UserInputType.Keyboard then
				return
			end
			if keybindControl.Listening then
				self.Window._consumedKey = input.KeyCode
				self.Window._consumedAt = os.clock()
				if input.KeyCode == Enum.KeyCode.Escape then
					keybindControl.Listening = false
					updateKeybind()
				else
					keybindControl:Set(input.KeyCode)
				end
				return
			end
			if not processed and keybindControl.Value ~= nil and input.KeyCode == keybindControl.Value then
				invokeCallback(keybindConfig.Callback, input.KeyCode)
			end
		end, keybindControl)
		updateKeybind()
		task.defer(resizeKeybindValue, true)
		function keybindControl:Get()
			return keybindControl.Value
		end
		keybindControl.TitleLabel = keybindTitle
		keybindControl.DescriptionLabel = keybindDescription
		keybindControl.ValueHolder = keybindButton
		keybindControl.UIResizeValue = resizeKeybindValue
		return registerElement(self, keybindConfig, keybindControl, keybindCard, "Keybind")
	end

	function NativeTab:ColorPicker(colorConfig)
		local defaultField, frameClass, buttonClass, gradientClass = "Default", "Frame", "TextButton", "UIGradient"
		local colorCard, colorStroke, colorHeight
		colorConfig, colorCard, colorStroke, colorHeight = createInteractiveCard(self, colorConfig, {
			Title = "Name",
			Description = "Desc",
			Color = defaultField,
			CurrentValue = defaultField,
			Value = defaultField,
		}, frameClass)
		colorCard.ClipsDescendants = true
		local colorHeader = createInstance(buttonClass, {
			Size = UDim2.new(1, 0, 0, colorHeight),
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
			Parent = colorCard,
		})
		local colorTitle, colorDescription =
			createCardLabels(colorHeader, colorConfig.Name or "Color", colorConfig.Desc, 90)
		local colorPreview = createInstance(frameClass, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -34, 0.5, 0),
			Size = UDim2.fromOffset(36, 20),
			BorderSizePixel = 0,
			Parent = colorHeader,
		})
		addCorner(colorPreview, UDim.new(0, 6))
		addStroke(colorPreview, nativeTheme.Stroke)
		local chevron = createChevron(colorHeader, 1, -12)
		local colorPanel = createInstance(frameClass, {
			Position = UDim2.fromOffset(14, colorHeight + 2),
			Size = UDim2.new(1, -28, 0, 156),
			BackgroundTransparency = 1,
			Visible = false,
			Parent = colorCard,
		})
		local saturationButton = createInstance(buttonClass, {
			Size = UDim2.new(1, -30, 0, 110),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			Text = "",
			AutoButtonColor = false,
			ClipsDescendants = true,
			Parent = colorPanel,
		})
		addCorner(saturationButton, UDim.new(0, 6))
		local hueGradient = createInstance(
			gradientClass,
			{ Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(1, 0, 0)), Parent = saturationButton }
		)
		local valueOverlay = createInstance(frameClass, {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BorderSizePixel = 0,
			Parent = saturationButton,
		})
		createInstance(gradientClass, {
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) }),
			Rotation = 90,
			Parent = valueOverlay,
		})
		local saturationMarker = createInstance(frameClass, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(10, 10),
			BackgroundTransparency = 1,
			ZIndex = 3,
			Parent = saturationButton,
		})
		addCorner(saturationMarker, UDim.new(1, 0))
		addStroke(saturationMarker, Color3.new(1, 1, 1), 0, 2)
		local hueButton = createInstance(buttonClass, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 0),
			Size = UDim2.fromOffset(14, 110),
			BorderSizePixel = 0,
			Text = "",
			AutoButtonColor = false,
			Parent = colorPanel,
		})
		addCorner(hueButton, UDim.new(0, 6))
		createInstance(gradientClass, {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)),
				ColorSequenceKeypoint.new(0.16666666666666666, Color3.fromRGB(255, 255, 0)),
				ColorSequenceKeypoint.new(0.3333333333333333, Color3.fromRGB(0, 255, 0)),
				ColorSequenceKeypoint.new(0.5, Color3.fromRGB(0, 255, 255)),
				ColorSequenceKeypoint.new(0.6666666666666666, Color3.fromRGB(0, 0, 255)),
				ColorSequenceKeypoint.new(0.8333333333333334, Color3.fromRGB(255, 0, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 0)),
			}),
			Rotation = 90,
			Parent = hueButton,
		})
		local hueMarker = createInstance(frameClass, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0, 0),
			Size = UDim2.fromOffset(18, 5),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			ZIndex = 3,
			Parent = hueButton,
		})
		addCorner(hueMarker, UDim.new(1, 0))
		addStroke(hueMarker, nativeTheme.AccentDark, 0.4)
		local hexHolder = createInstance(frameClass, {
			Position = UDim2.fromOffset(6, 122),
			Size = UDim2.fromOffset(118, 28),
			BackgroundColor3 = nativeTheme.Surface,
			BorderSizePixel = 0,
			Parent = colorPanel,
		})
		addCorner(hexHolder, UDim.new(0, 6))
		local hexBorder = addStroke(hexHolder)
		local hexInput = createInstance("TextBox", {
			Position = UDim2.fromOffset(14, 0),
			Size = UDim2.new(1, -24, 1, 0),
			BackgroundTransparency = 1,
			Text = "",
			TextTruncate = Enum.TextTruncate.None,
			ClipsDescendants = false,
			TextColor3 = nativeTheme.Text,
			TextSize = 13,
			FontFace = nativeFonts.Regular,
			TextXAlignment = Enum.TextXAlignment.Left,
			ClearTextOnFocus = false,
			Parent = hexHolder,
		})
		local hexCaption = createLabel({
			Position = UDim2.fromOffset(134, 122),
			Size = UDim2.new(1, -134, 0, 28),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextSize = 13,
			FontFace = nativeFonts.Regular,
			TextColor3 = nativeTheme.Muted,
			Parent = colorPanel,
		})
		local colorControl = { Open = false }
		local hue, saturation, brightness = Color3.toHSV(colorConfig.Default or nativeTheme.Accent)
		local dragMode
		local function formatHexColor(color)
			return string.format(
				"#%02X%02X%02X",
				math.floor(color.R * 255 + 0.5),
				math.floor(color.G * 255 + 0.5),
				math.floor(color.B * 255 + 0.5)
			)
		end

		local function updateColor(duration)
			local selectedColor = Color3.fromHSV(hue, saturation, brightness)
			colorControl.Value = selectedColor
			colorPreview.BackgroundColor3 = selectedColor
			hueGradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromHSV(hue, 1, 1))
			animate(
				saturationMarker,
				{ Position = UDim2.fromScale(saturation, 1 - brightness) },
				duration,
				Enum.EasingStyle.Linear
			)
			animate(hueMarker, { Position = UDim2.new(0.5, 0, hue, 0) }, duration, Enum.EasingStyle.Linear)
			if not hexInput:IsFocused() then
				hexInput.Text = formatHexColor(selectedColor)
			end
			hexCaption.Text = string.format(
				"RGB %d, %d, %d",
				math.floor(selectedColor.R * 255 + 0.5),
				math.floor(selectedColor.G * 255 + 0.5),
				math.floor(selectedColor.B * 255 + 0.5)
			)
		end

		local function setColor(color, skipCallback)
			updateColor(color)
			if not skipCallback then
				invokeCallback(colorConfig.Callback, colorControl.Value)
			end
		end

		function colorControl:Set(color, skipCallback)
			hue, saturation, brightness = Color3.toHSV(color)
			setColor(0.25, skipCallback)
			addCardGradient(colorStroke)
		end

		function colorControl:Get()
			return colorControl.Value
		end

		local function setColorOpen(open)
			colorControl.Open = open
			animate(
				colorCard,
				{ Size = controlSize(colorCard, open and colorHeight + 168 or colorHeight) },
				0.35,
				Enum.EasingStyle.Quint
			)
			chevron:Set(open)
			if open then
				colorPanel.Visible = true
			else
				task.delay(0.35, function()
					if not colorControl.Open then
						colorPanel.Visible = false
					end
				end)
			end
		end

		function colorControl:SetOpen(open)
			setColorOpen(open == true)
		end
		colorHeader.MouseButton1Click:Connect(function()
			setColorOpen(not colorControl.Open)
		end)
		local function updateSaturation(pointer)
			saturation =
				math.clamp((pointer.X - saturationButton.AbsolutePosition.X) / saturationButton.AbsoluteSize.X, 0, 1)
			brightness = 1
				- math.clamp((pointer.Y - saturationButton.AbsolutePosition.Y) / saturationButton.AbsoluteSize.Y, 0, 1)
			setColor(0.04)
		end

		local function updateHue(pointer)
			hue = math.clamp((pointer.Y - hueButton.AbsolutePosition.Y) / hueButton.AbsoluteSize.Y, 0, 0.999)
			setColor(0.04)
		end
		saturationButton.InputBegan:Connect(function(input)
			if isPrimaryInput(input) then
				dragMode = "sv"
				animate(saturationMarker, { Size = UDim2.fromOffset(14, 14) }, 0.15, Enum.EasingStyle.Back)
				updateSaturation(getPointerPosition())
			end
		end)
		hueButton.InputBegan:Connect(function(input)
			if isPrimaryInput(input) then
				dragMode = "hue"
				animate(hueMarker, { Size = UDim2.fromOffset(20, 7) }, 0.15, Enum.EasingStyle.Back)
				updateHue(getPointerPosition())
			end
		end)
		self.Window:_listen("Changed", function(input)
			if not dragMode or not isPointerMovement(input) then
				return
			end
			local pointerPosition = getPointerPosition()
			if dragMode == "sv" then
				updateSaturation(pointerPosition)
			else
				updateHue(pointerPosition)
			end
		end, colorControl)
		self.Window:_listen("Ended", function(input)
			if dragMode and isPrimaryInput(input) then
				dragMode = nil
				animate(saturationMarker, { Size = UDim2.fromOffset(10, 10) }, 0.2)
				animate(hueMarker, { Size = UDim2.fromOffset(18, 5) }, 0.2)
			end
		end, colorControl)
		hexInput.Focused:Connect(function()
			animate(hexBorder, { Color = nativeTheme.StrokeHover }, 0.15)
		end)
		hexInput.FocusLost:Connect(function()
			animate(hexBorder, { Color = nativeTheme.Stroke }, 0.15)
			local redHex, greenHex, blueHex = hexInput.Text:match("^%s*#?(%x%x)(%x%x)(%x%x)%s*$")
			if redHex then
				colorControl:Set(Color3.fromRGB(tonumber(redHex, 16), tonumber(greenHex, 16), tonumber(blueHex, 16)))
			else
				hexInput.Text = formatHexColor(colorControl.Value)
			end
		end)
		updateColor(0)
		colorControl.TitleLabel = colorTitle
		colorControl.DescriptionLabel = colorDescription
		colorControl.ValueHolder = colorPreview
		colorControl.UISetHeaderHeight = function(height)
			if colorHeight == height then
				return
			end
			colorHeight = height
			colorHeader.Size = UDim2.new(1, 0, 0, height)
			colorPanel.Position = UDim2.fromOffset(14, height + 2)
			colorCard.Size = controlSize(colorCard, colorControl.Open and height + 168 or height)
		end
		return registerElement(self, colorConfig, colorControl, colorCard, "ColorPicker")
	end

	function NativeTab:Stepper(stepperConfig)
		local stepperCard, stepperStroke, stepperHeight, stepperTitle, stepperDescription
		stepperConfig, stepperCard, stepperStroke, stepperHeight, stepperTitle, stepperDescription =
			createInteractiveCard(self, stepperConfig, {
				Title = "Name",
				Description = "Desc",
				CurrentValue = "Default",
				Value = "Default",
				Increment = "Step",
			}, "Frame", 150, "Stepper")
		local minimum = stepperConfig.Min or 0
		local maximum = stepperConfig.Max or 100
		local step = stepperConfig.Step or 1
		local suffix = stepperConfig.Suffix or ""
		local rangeAdapter = createRangeAdapter(minimum, maximum, step)
		local stepperHolder = createInstance("Frame", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(0, chipHeight),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = nativeTheme.Surface,
			BorderSizePixel = 0,
			Parent = stepperCard,
		})
		addCorner(stepperHolder, UDim.new(0, 6))
		local stepperBorder = addStroke(stepperHolder)
		createInstance("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Parent = stepperHolder,
		})
		local function createStepButton(caption, layoutOrder)
			local stepButton = createInstance("TextButton", {
				Size = UDim2.fromOffset(chipHeight, chipHeight),
				BackgroundTransparency = 1,
				Text = caption,
				TextColor3 = nativeTheme.Muted,
				TextSize = 18,
				FontFace = nativeFonts.Medium,
				AutoButtonColor = false,
				LayoutOrder = layoutOrder,
				Parent = stepperHolder,
			})
			stepButton.MouseEnter:Connect(function()
				animate(stepButton, { TextColor3 = nativeTheme.Accent }, 0.12)
			end)
			stepButton.MouseLeave:Connect(function()
				animate(stepButton, { TextColor3 = nativeTheme.Muted }, 0.2)
			end)
			return stepButton
		end
		local decrementButton = createStepButton("−", 1)
		local valueLabel = createLabel({
			Size = UDim2.new(0, 30, 1, 0),
			TextSize = 13,
			TextColor3 = nativeTheme.Accent,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextTruncate = Enum.TextTruncate.None,
			LayoutOrder = 2,
			Parent = stepperHolder,
		})
		local incrementButton = createStepButton("+", 3)
		local function resizeStepperValue(immediate)
			local valueWidth = math.max(valueLabel.TextBounds.X + 12, 30)
			if immediate then
				valueLabel.Size = UDim2.new(0, valueWidth, 1, 0)
			else
				animate(valueLabel, { Size = UDim2.new(0, valueWidth, 1, 0) }, 0.2)
			end
		end
		valueLabel:GetPropertyChangedSignal("TextBounds"):Connect(function()
			resizeStepperValue(false)
		end)
		stepperHolder:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			reserveControlWidth(
				stepperTitle,
				stepperDescription,
				stepperHolder.AbsoluteSize.X / self.Window.Scale.Scale + 20
			)
		end)
		local stepperControl = { Value = math.clamp(stepperConfig.Default or minimum, minimum, maximum) }
		local snapValue, userChanging = rangeAdapter.snap, false
		local function updateStepper()
			valueLabel.Text = rangeAdapter.format(stepperControl.Value) .. suffix
			animate(decrementButton, { TextTransparency = stepperControl.Value <= minimum and 0.6 or 0 }, 0.15)
			animate(incrementButton, { TextTransparency = stepperControl.Value >= maximum and 0.6 or 0 }, 0.15)
		end

		function stepperControl:Set(value, skipCallback)
			value = snapValue(tonumber(value) or minimum)
			if value == stepperControl.Value then
				return
			end
			stepperControl.Value = value
			updateStepper()
			if not userChanging then
				addCardGradient(stepperStroke)
			end
			if not skipCallback then
				invokeCallback(stepperConfig.Callback, value)
			end
		end

		function stepperControl:Get()
			return stepperControl.Value
		end

		local function stepValue(direction)
			userChanging = true
			stepperControl:Set(stepperControl.Value + direction * step)
			userChanging = false
			animate(stepperBorder, { Color = nativeTheme.StrokeHover }, 0.08)
			task.delay(0.12, function()
				animate(stepperBorder, { Color = nativeTheme.Stroke }, 0.2)
			end)
		end

		local function bindStepButton(button, direction)
			local holdingButton = false
			button.InputBegan:Connect(function(input)
				if not isPrimaryInput(input) then
					return
				end
				holdingButton = true
				stepValue(direction)
				task.delay(0.4, function()
					while holdingButton do
						stepValue(direction)
						task.wait(0.07)
					end
				end)
			end)
			button.InputEnded:Connect(function(input)
				if isPrimaryInput(input) then
					holdingButton = false
				end
			end)
			button.MouseLeave:Connect(function()
				holdingButton = false
			end)
		end
		bindStepButton(decrementButton, -1)
		bindStepButton(incrementButton, 1)
		updateStepper()
		task.defer(resizeStepperValue, true)
		return registerElement(self, stepperConfig, stepperControl, stepperCard, "Stepper")
	end

	function NativeTab:Progress(progressConfig)
		progressConfig = normalizeOptions(
			progressConfig,
			{ Title = "Name", Description = "Desc", CurrentValue = "Default", Value = "Default" }
		)
		local progressCard, progressStroke = createCard(
			self,
			"Frame",
			progressConfig.Desc and descriptionCardHeight + 10 or cardHeight + 10,
			progressConfig
		)
		decorateCard(progressCard, progressStroke)
		local titleOffset = progressConfig.Desc and (descriptionCardHeight - 38) / 2 - 2 or 12
		createLabel({
			Position = UDim2.fromOffset(14, titleOffset),
			Size = UDim2.new(1, -110, 0, 18),
			Text = progressConfig.Name or "Progress",
			Parent = progressCard,
		})
		if progressConfig.Desc then
			createLabel({
				Position = UDim2.fromOffset(14, titleOffset + 20),
				Size = UDim2.new(1, -110, 0, 17),
				Text = progressConfig.Desc,
				TextSize = 13,
				FontFace = nativeFonts.Regular,
				TextColor3 = nativeTheme.Muted,
				Parent = progressCard,
			})
		end
		local progressLabel = createLabel({
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -14, 0, titleOffset),
			Size = UDim2.fromOffset(90, 18),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextSize = 13,
			TextColor3 = nativeTheme.Accent,
			Parent = progressCard,
		})
		local progressTrack = createInstance("Frame", {
			Position = UDim2.new(0, 14, 1, -16),
			Size = UDim2.new(1, -28, 0, 5),
			BackgroundColor3 = nativeTheme.Surface3,
			BorderSizePixel = 0,
			Parent = progressCard,
		})
		addCorner(progressTrack, UDim.new(1, 0))
		local progressFill = createInstance("Frame", {
			Size = UDim2.new(0, 0, 1, 0),
			BackgroundColor3 = progressConfig.Color or nativeTheme.Accent,
			BorderSizePixel = 0,
			Parent = progressTrack,
		})
		addCorner(progressFill, UDim.new(1, 0))
		local progressControl = { Value = math.clamp(progressConfig.Default or 0, 0, 1) }
		local format = progressConfig.Format
		local function updateProgress(duration)
			local progress = progressControl.Value
			animate(progressFill, { Size = UDim2.new(progress, 0, 1, 0) }, duration, Enum.EasingStyle.Quint)
			if type(format) == "function" then
				progressLabel.Text = tostring(format(progress))
			else
				progressLabel.Text = string.format("%d%%", math.floor(progress * 100 + 0.5))
			end
		end

		function progressControl:Set(value, skipCallback)
			value = math.clamp(tonumber(value) or 0, 0, 1)
			if value == progressControl.Value then
				return
			end
			progressControl.Value = value
			updateProgress(0.35)
			if not skipCallback then
				invokeCallback(progressConfig.Callback, value)
			end
		end

		function progressControl:Get()
			return progressControl.Value
		end

		function progressControl:SetColor(color)
			progressFill.BackgroundColor3 = color
		end
		updateProgress(0)
		return registerElement(self, progressConfig, progressControl, progressCard, "Progress")
	end

	function NativeTab:ConfigManager(managerConfig)
		managerConfig = normalizeOptions(managerConfig, {})
		local window = self.Window
		local configManager = {}
		self:Section(managerConfig.Name or "Configs")
		local configNameInput = self:Input({
			Name = "Config name",
			Placeholder = window.ConfigName,
			Callback = function(name, submitted)
				if submitted and #name > 0 then
					configManager:Save(name)
				end
			end,
		})
		local configDropdown = self:Dropdown({
			Name = "Saved configs",
			Options = window:ListConfigs(),
			Default = window.ConfigName,
			Callback = function(name)
				if name then
					configNameInput:Set(name)
				end
			end,
		})
		function configManager:Refresh()
			configDropdown:Refresh(window:ListConfigs(), true)
		end

		function configManager:Save(name)
			name = name or configDropdown:Get() or window.ConfigName
			local saved, saveFailure = window:SaveConfig(name)
			configManager:Refresh()
			configDropdown:Set(name, true)
			window:Notify({
				Title = saved and "Config saved" or "Save failed",
				Content = saved and name or tostring(saveFailure),
				Type = saved and "Success" or "Error",
				Duration = 3,
			})
		end

		function configManager:Load(name)
			name = name or configDropdown:Get()
			if not name then
				return
			end
			local loaded, loadFailure = window:LoadConfig(name)
			window:Notify({
				Title = loaded and "Config loaded" or "Load failed",
				Content = loaded and name or tostring(loadFailure),
				Type = loaded and "Success" or "Error",
				Duration = 3,
			})
		end

		function configManager:Delete(name)
			name = name or configDropdown:Get()
			if not name then
				return
			end
			local deleted, deleteFailure = window:DeleteConfig(name)
			configManager:Refresh()
			window:Notify({
				Title = deleted and "Config deleted" or "Delete failed",
				Content = deleted and name or tostring(deleteFailure),
				Type = deleted and "Info" or "Error",
				Duration = 3,
			})
		end
		self:Button({
			Name = "Save",
			Desc = "Writes every flagged element to the selected name",
			Icon = "save",
			Style = "Primary",
			Callback = function()
				local configName = configNameInput:Get()
				configManager:Save(#configName > 0 and configName or nil)
			end,
		})
		self:Button({
			Name = "Load",
			Icon = "folder-open",
			Callback = function()
				configManager:Load()
			end,
		})
		self:Button({
			Name = "Delete",
			Icon = "trash-2",
			Callback = function()
				local selectedConfig = configDropdown:Get()
				if not selectedConfig then
					return
				end
				window:Confirm({
					Title = "Delete config",
					Content = "Remove " .. selectedConfig .. "? This cannot be undone.",
					Icon = "trash-2",
					ConfirmText = "Delete",
					Callback = function()
						configManager:Delete(selectedConfig)
					end,
				})
			end,
		})
		self:Toggle({
			Name = "Auto save",
			Desc = "Save whenever a flagged element changes",
			Default = window._autoSaveEnabled,
			Callback = function(name)
				window._autoSaveEnabled = name
			end,
		})
		return configManager
	end
	for nativeTheme, animate in pairs(table.clone(NativeTab)) do
		if type(animate) == "function" and nativeTheme:sub(1, 1) ~= "_" and nativeTheme:sub(1, 6) ~= "Create" then
			NativeTab["Create" .. nativeTheme] = animate
		end
	end

	local function detectExecutor()
		local executorName
		pcall(function()
			if typeof(identifyexecutor) == "function" then
				executorName = (identifyexecutor())
			elseif typeof(getexecutorname) == "function" then
				executorName = getexecutorname()
			end
		end)
		if type(executorName) == "string" and #executorName > 0 then
			return executorName
		end
		return RunService:IsStudio() and "Studio" or "Unknown"
	end

	local function detectGameName()
		local success, result = pcall(function()
			return Runtime.GetService("MarketplaceService"):GetProductInfo(game.PlaceId)
		end)
		if success and type(result) == "table" and result.Name then
			return result.Name
		end
		return "Unknown game"
	end
	local NOTIFICATION_HEIGHT = 92
	local notificationColors =
		{ Success = nativeTheme.Success, Warning = nativeTheme.Warning, Error = nativeTheme.Error }
	local NativeWindow = {}
	NativeWindow.__index = NativeWindow
	function NativeLibrary.Window(library, windowConfig)
		local guiName, frameClass, groupClass, listLayoutClass, sizeProperty, tableType =
			"\077\105\099\104\105\103\117\110\085\073", "Frame", "CanvasGroup", "UIListLayout", "AbsoluteSize", "table"
		windowConfig = normalizeOptions(
			windowConfig,
			{ Name = "Title", LoadingSubtitle = "Subtitle", ToggleUIKeybind = "Keybind" }
		)
		if type(windowConfig.Keybind) == "string" then
			windowConfig.Keybind = Enum.KeyCode[windowConfig.Keybind]
		end
		local windowSize = windowConfig.Size or UDim2.fromOffset(640, 480)
		local toggleKey = windowConfig.Keybind or Enum.KeyCode.RightControl
		local window = setmetatable({
			Tabs = {},
			CurrentTab = nil,
			Open = true,
			Keybind = toggleKey,
			_connections = {},
			_controls = {},
			_inputListeners = { Began = {}, Changed = {}, Ended = {}, Render = {} },
			_frameSteps = {},
			_destroyed = false,
		}, NativeWindow)
		local function createInputDispatcher(phase)
			return function(...)
				for index, listener in ipairs(window._inputListeners[phase]) do
					listener(...)
				end
			end
		end
		local dispatchRender = createInputDispatcher("Render")
		table.insert(
			window._connections,
			RunService.RenderStepped:Connect(function(deltaTime)
				dispatchRender(deltaTime)
				for index, frameStep in ipairs(window._frameSteps) do
					frameStep(deltaTime)
				end
			end)
		)
		table.insert(window._connections, UserInputService.InputBegan:Connect(createInputDispatcher("Began")))
		table.insert(window._connections, UserInputService.InputChanged:Connect(createInputDispatcher("Changed")))
		table.insert(window._connections, UserInputService.InputEnded:Connect(createInputDispatcher("Ended")))
		local screenGui = createInstance("ScreenGui", {
			Name = windowConfig.Name or guiName,
			IgnoreGuiInset = true,
			ResetOnSpawn = false,
			DisplayOrder = 999,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		})
		window.Gui = screenGui
		local windowRoot = createInstance(frameClass, {
			Name = "Window",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = windowSize,
			BackgroundTransparency = 1,
			Parent = screenGui,
		})
		window.Root = windowRoot
		window._preferredSize = windowSize
		window.Responsive = windowConfig.Responsive ~= false
		local windowScale = createInstance("UIScale", { Parent = windowRoot })
		window.Scale = windowScale
		local windowShadow = createInstance("ImageLabel", {
			Position = UDim2.fromOffset(-25, -25),
			Size = UDim2.new(1, 50, 1, 50),
			BackgroundTransparency = 1,
			Image = nativeAssets.Shadow,
			ImageColor3 = Color3.new(0, 0, 0),
			ImageTransparency = 0.6,
			ScaleType = Enum.ScaleType.Slice,
			SliceCenter = Rect.new(49, 49, 450, 450),
			Parent = windowRoot,
		})
		window.Shadow = windowShadow
		local windowBody = createInstance(groupClass, {
			Name = "Body",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = nativeTheme.Background,
			BorderSizePixel = 0,
			Parent = windowRoot,
		})
		window.Body = windowBody
		addCorner(windowBody, UDim.new(0, 16))
		window.BodyStroke = addStroke(windowBody, nativeTheme.Stroke)
		addEdgeHighlight(windowBody)
		addGlow(windowBody, UDim2.fromOffset(500, 180), UDim2.new(0.5, 0, 1, 8), 0.86, 270)
		addGlow(windowBody, UDim2.fromOffset(130, 60), UDim2.new(0, -10, 1, -10), 0.75, 90)
		addGlow(windowBody, UDim2.fromOffset(520, 240), UDim2.new(1, -14, 0, 10), 0.92, 90)
		local sidebar = createInstance(
			frameClass,
			{ Name = "Sidebar", Size = UDim2.new(0, 170, 1, 0), BackgroundTransparency = 1, Parent = windowBody }
		)
		createInstance(frameClass, {
			Name = "SidebarDivider",
			Position = UDim2.new(0, 170, 0, 28),
			Size = UDim2.new(0, 1, 1, -56),
			BackgroundColor3 = nativeTheme.Stroke,
			BorderSizePixel = 0,
			Parent = windowBody,
		})
		local sidebarHeader = createInstance(
			frameClass,
			{ Name = "Header", Size = UDim2.new(1, 0, 0, 72), BackgroundTransparency = 1, Parent = sidebar }
		)
		local headerLogo = createInstance("ImageLabel", {
			Position = UDim2.fromOffset(22, 27),
			Size = UDim2.fromOffset(30, 28),
			BackgroundTransparency = 1,
			Image = "",
			ImageColor3 = nativeTheme.Accent,
			ScaleType = Enum.ScaleType.Fit,
			Parent = sidebarHeader,
		})
		applyIcon(headerLogo, windowConfig.Icon or nativeAssets.Logo)
		createLabel({
			Position = UDim2.fromOffset(60, 25),
			Size = UDim2.new(1, -70, 0, 20),
			Text = windowConfig.Title or "\077\105\099\104\105\103\117\110",
			TextSize = 20,
			Parent = sidebarHeader,
		})
		createLabel({
			Position = UDim2.fromOffset(60, 45),
			Size = UDim2.new(1, -70, 0, 14),
			Text = windowConfig.Subtitle or "",
			TextSize = 13,
			FontFace = nativeFonts.Regular,
			TextColor3 = nativeTheme.Muted,
			Parent = sidebarHeader,
		})
		local scrollingFrame = createInstance("ScrollingFrame", {
			Name = "Tabs",
			Position = UDim2.fromOffset(0, 80),
			Size = UDim2.new(1, 0, 1, -116),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 0,
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			CanvasSize = UDim2.new(),
			Parent = sidebar,
		})
		window.TabList = scrollingFrame
		addPadding(scrollingFrame, 16, 16, 4, 4)
		createInstance(
			listLayoutClass,
			{ SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4), Parent = scrollingFrame }
		)
		local tabIndicator = createInstance(frameClass, {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromOffset(6, 0),
			Size = UDim2.fromOffset(3, 18),
			BackgroundColor3 = nativeTheme.Accent,
			BorderSizePixel = 0,
			Visible = false,
			ZIndex = 2,
			Parent = sidebar,
		})
		addCorner(tabIndicator, UDim.new(1, 0))
		window.Indicator = tabIndicator
		local y = scrollingFrame.CanvasPosition.Y
		table.insert(window._frameSteps, function()
			local scrollOffset = scrollingFrame.CanvasPosition.Y
			if scrollOffset == y or not window.CurrentTab or not window._introDone then
				return
			end
			y = scrollOffset
			local indicatorY = window:_indicatorY(window.CurrentTab)
			local offset = scrollingFrame.Position.Y.Offset
			local visibleBottom = offset + scrollingFrame.AbsoluteSize.Y / window.Scale.Scale
			tabIndicator.Visible = indicatorY > offset and indicatorY < visibleBottom
			tabIndicator.Position = UDim2.fromOffset(6, indicatorY)
		end)
		local keybindFooter = createInstance(frameClass, {
			Name = "KeybindFooter",
			Position = UDim2.new(0, 22, 1, -36),
			Size = UDim2.new(1, -44, 0, 22),
			BackgroundTransparency = 1,
			Parent = sidebar,
		})
		local keybindChip = createInstance(frameClass, {
			Size = UDim2.fromOffset(0, 22),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = nativeTheme.Surface,
			BorderSizePixel = 0,
			Parent = keybindFooter,
		})
		addCorner(keybindChip, UDim.new(0, 5))
		addStroke(keybindChip)
		addPadding(keybindChip, 7, 7)
		local keybindLabel = createLabel({
			Size = UDim2.new(0, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			Text = formatKeyName(toggleKey),
			TextSize = 11,
			TextColor3 = nativeTheme.Muted,
			TextTruncate = Enum.TextTruncate.None,
			Parent = keybindChip,
		})
		window._keyChipLabel = keybindLabel
		local keybindHint = createLabel({
			Size = UDim2.new(1, 0, 1, 0),
			Text = "Abrir / minimizar",
			TextSize = 12,
			FontFace = nativeFonts.Regular,
			TextColor3 = nativeTheme.Muted,
			Parent = keybindFooter,
		})
		local function updateTabIndicator()
			keybindHint.Position = UDim2.fromOffset(keybindChip.AbsoluteSize.X / window.Scale.Scale + 8, 0)
		end
		keybindChip:GetPropertyChangedSignal(sizeProperty):Connect(updateTabIndicator)
		task.defer(updateTabIndicator)
		local contentRoot = createInstance(frameClass, {
			Name = "Content",
			Position = UDim2.fromOffset(171, 0),
			Size = UDim2.new(1, -171, 1, 0),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			Parent = windowBody,
		})
		window.Content = contentRoot
		window._outLayer = createInstance(groupClass, {
			Name = "TransitionOut",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Visible = false,
			ZIndex = 2,
			Parent = contentRoot,
		})
		window._inLayer = createInstance(groupClass, {
			Name = "TransitionIn",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Visible = false,
			ZIndex = 3,
			Parent = contentRoot,
		})
		local closeButton = createInstance("TextButton", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -14, 0, 14),
			Size = UDim2.fromOffset(34, 34),
			BackgroundColor3 = nativeTheme.Surface2,
			BackgroundTransparency = 1,
			Text = "×",
			TextColor3 = nativeTheme.Muted,
			TextSize = 28,
			FontFace = nativeFonts.Bold,
			AutoButtonColor = false,
			ZIndex = 5,
			Parent = contentRoot,
		})
		addPadding(closeButton, 0, 0, 1, 0)
		addCorner(closeButton, UDim.new(0, 8))
		closeButton.MouseEnter:Connect(function()
			animate(closeButton, { BackgroundTransparency = 0, TextColor3 = nativeTheme.Text }, 0.15)
		end)
		closeButton.MouseLeave:Connect(function()
			animate(closeButton, { BackgroundTransparency = 1, TextColor3 = nativeTheme.Muted }, 0.2)
		end)
		window.CloseButton = closeButton
		closeButton.MouseButton1Click:Connect(function()
			if window.RequestClose then
				window:RequestClose()
			end
		end)
		local notificationHolder = createInstance(frameClass, {
			Name = "Notifications",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -12, 0, 12),
			Size = UDim2.new(0, 240, 1, -24),
			BackgroundTransparency = 1,
			Parent = screenGui,
		})
		window.NotifyHolder = notificationHolder
		window._notifyOrder = 0
		window._toasts = {}
		local notificationLimit = tonumber(windowConfig.MaxNotifications) or 3
		if notificationLimit ~= notificationLimit then
			notificationLimit = 3
		end
		window.MaxNotifications = math.clamp(math.floor(notificationLimit), 1, 3)
		local function resizeNotifications()
			local inset = GuiService:GetGuiInset()
			local top = inset.Y + 12
			local availableHeight = math.max(0, screenGui.AbsoluteSize.Y - top - 12)
			notificationHolder.AnchorPoint = Vector2.new(1, 0)
			local layout = notificationHolder:FindFirstChildOfClass("UIListLayout")
			if layout then
				layout.VerticalAlignment = Enum.VerticalAlignment.Top
				layout.FillDirection = Enum.FillDirection.Vertical
			end
			notificationHolder.Position = UDim2.new(1, -12, 0, top)
			notificationHolder.Size =
				UDim2.fromOffset(math.max(1, math.min(240, screenGui.AbsoluteSize.X - 24)), availableHeight)
			window._notifyLimit = math.min(
				window.MaxNotifications,
				math.max(0, math.floor((availableHeight + 6) / (NOTIFICATION_HEIGHT + 6)))
			)
			while #window._toasts > window._notifyLimit do
				window._toasts[1](true)
			end
		end
		table.insert(window._connections, screenGui:GetPropertyChangedSignal(sizeProperty):Connect(resizeNotifications))
		window._resizeNotifications = resizeNotifications
		resizeNotifications()
		createInstance(listLayoutClass, {
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Top,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			FillDirection = Enum.FillDirection.Vertical,
			Padding = UDim.new(0, 6),
			Parent = notificationHolder,
		})
		window._controlsDirty = true
		table.insert(
			window._connections,
			windowBody.DescendantAdded:Connect(function()
				window._controlsDirty = true
			end)
		)
		table.insert(
			window._connections,
			windowBody.DescendantRemoving:Connect(function()
				window._controlsDirty = true
			end)
		)
		window:_enableDrag()
		window.MaxSize = windowConfig.MaxSize
		window.KeepOnScreen = windowConfig.KeepOnScreen == true
		window:_enableResize(windowConfig.MinSize or Vector2.new(480, 360))
		local configurationSaving = windowConfig.ConfigurationSaving
		if type(configurationSaving) == tableType and configurationSaving.Enabled ~= false then
			window.ConfigFolder = resolveStoragePath(configurationSaving.FolderName, "config")
			migrateStorageConfigs(configurationSaving.FolderName or guiName, window.ConfigFolder)
			window.ConfigName = configurationSaving.FileName or "default"
			window._autoSaveEnabled = true
		else
			window.ConfigFolder = resolveStoragePath("config")
			window.ConfigName = "default"
			window._autoSaveEnabled = false
		end
		table.insert(
			window._connections,
			UserInputService.InputBegan:Connect(function(input, processed)
				if processed then
					return
				end
				if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == window.Keybind then
					task.defer(function()
						local keyConsumed = window._consumedKey == input.KeyCode
							and os.clock() - (window._consumedAt or 0) < 0.2
						window._consumedKey = nil
						if not keyConsumed and not window._destroyed then
							window:Toggle(not window.Open)
						end
					end)
				end
			end)
		)
		pcall(function()
			if typeof(syn) == "table" and typeof(syn.protect_gui) == "function" then
				syn.protect_gui(screenGui)
			end
		end)
		screenGui.Parent = windowConfig.Parent or getInterfaceParent()
		windowScale.Scale = 0.9
		windowBody.GroupTransparency = 1
		windowShadow.ImageTransparency = 1
		window.BodyStroke.Transparency = 1
		windowRoot.Visible = false
		window:_fitToScreen(true)
		table.insert(
			window._connections,
			windowRoot:GetPropertyChangedSignal("Size"):Connect(function()
				local width = windowRoot.Size.X.Offset
				local compact = width < 560 or screenGui.AbsoluteSize.Y < 430
				local sidebarWidth = compact and (width < 420 and 112 or 140) or 170
				if compact ~= window._compactLayout or sidebarWidth ~= window._sidebarWidth then
					window._compactLayout = compact
					window:_layoutResponsive()
				end
			end)
		)
		table.insert(
			window._connections,
			screenGui:GetPropertyChangedSignal(sizeProperty):Connect(function()
				window:_fitToScreen()
				window:_clampToScreen()
			end)
		)
		if
			windowConfig.OpenButton ~= nil and windowConfig.OpenButton ~= false
			or windowConfig.OpenButton == nil and isTouchDevice
		then
			window:_createOpenButton(type(windowConfig.OpenButton) == tableType and windowConfig.OpenButton or {})
		end
		window._introDone = false
		table.insert(NativeLibrary.Windows, window)
		if windowConfig.Home then
			window:_buildHome(type(windowConfig.Home) == tableType and windowConfig.Home or {})
		end
		local loading = windowConfig.Loading
		if type(loading) == tableType then
			windowConfig.LoadingDuration = loading.Duration or windowConfig.LoadingDuration
			windowConfig.LoadingText = loading.Text or loading.Subtitle or windowConfig.LoadingText
			windowConfig.LoadingSteps = loading.Steps or windowConfig.LoadingSteps
			windowConfig.LoadingTitle = loading.Title or windowConfig.LoadingTitle
			loading = loading.Enabled ~= false
		end
		if loading == false then
			task.defer(function()
				window:_playIntro()
			end)
		else
			window:_showLoader(windowConfig)
		end
		return window
	end
	NativeLibrary.CreateWindow = NativeLibrary.Window
	function NativeLibrary:Notify(notificationConfig)
		local activeWindow = NativeLibrary.Windows[#NativeLibrary.Windows]
		if activeWindow then
			return activeWindow:Notify(notificationConfig)
		end
	end

	function NativeLibrary:Confirm(dialogConfig)
		local activeWindow = NativeLibrary.Windows[#NativeLibrary.Windows]
		if activeWindow then
			return activeWindow:Confirm(dialogConfig)
		end
	end

	function NativeLibrary:Dialog(dialogConfig)
		local activeWindow = NativeLibrary.Windows[#NativeLibrary.Windows]
		if activeWindow then
			return activeWindow:Dialog(dialogConfig)
		end
	end

	local function containsPoint(point, object)
		local absolutePosition, absoluteSize = object.AbsolutePosition, object.AbsoluteSize
		return point.X >= absolutePosition.X
			and point.X <= absolutePosition.X + absoluteSize.X
			and point.Y >= absolutePosition.Y
			and point.Y <= absolutePosition.Y + absoluteSize.Y
	end

	local function isControlVisible(control, visibilityField, stopAt)
		local ancestor = control
		while ancestor and ancestor ~= visibilityField and ancestor:IsA("GuiObject") do
			if not ancestor.Visible then
				return false
			end
			local parent = ancestor.Parent
			if
				parent
				and parent ~= visibilityField
				and parent:IsA("GuiObject")
				and (parent.ClipsDescendants or parent:IsA("ScrollingFrame"))
				and not containsPoint(stopAt, parent)
			then
				return false
			end
			ancestor = parent
		end
		return true
	end

	function NativeWindow:_refreshControls()
		local controls = {}
		for index, descendant in ipairs(self.Body:GetDescendants()) do
			if descendant:IsA("GuiButton") or descendant:IsA("TextBox") or descendant:GetAttribute("NoDrag") then
				table.insert(controls, descendant)
			end
		end
		self._controls = controls
		self._controlsDirty = false
	end

	function NativeWindow:_overControl(input)
		if self._dialog then
			return true
		end
		if self._controlsDirty then
			self:_refreshControls()
		end
		for index, control in ipairs(self._controls) do
			if control.Parent and containsPoint(input, control) and isControlVisible(control, self.Body, input) then
				return true
			end
		end
		return false
	end

	function NativeWindow:_enableDrag()
		local activeInput, startPointer, pointerOffset
		local dragging = false
		local function rootPosition()
			local root = self.Root
			return root.AbsolutePosition + root.AbsoluteSize * root.AnchorPoint - self.Gui.AbsolutePosition
		end

		local function pointerPosition(input)
			if input.UserInputType == Enum.UserInputType.Touch then
				return Vector2.new(input.Position.X, input.Position.Y)
			end
			return getPointerPosition()
		end

		local function stopDrag(clamp)
			local moved = dragging
			activeInput, startPointer, pointerOffset = nil, nil, nil
			dragging = false
			if clamp and moved and not self._destroyed then
				self:_clampToScreen()
			end
		end
		table.insert(
			self._connections,
			UserInputService.InputBegan:Connect(function(input, processed)
				if activeInput or processed or not isPrimaryInput(input) then
					return
				end
				if self._destroyed or not self.Open or not self.Gui.Enabled or not self.Root.Visible then
					return
				end
				if UserInputService:GetFocusedTextBox() then
					return
				end
				local pointer = pointerPosition(input)
				if not containsPoint(pointer, self.Body) or self:_overControl(pointer) then
					return
				end
				if input.UserInputType == Enum.UserInputType.Touch then
					local overHandle = false
					for _, handle in ipairs(self.DragHandles or {}) do
						if handle.Parent and handle.Visible and containsPoint(pointer, handle) then
							overHandle = true
							break
						end
					end
					if not overHandle then
						return
					end
				end
				activeInput = input
				startPointer = pointer
				pointerOffset = pointer - rootPosition()
			end)
		)
		table.insert(
			self._connections,
			UserInputService.InputEnded:Connect(function(input)
				if input == activeInput then
					stopDrag(true)
				end
			end)
		)
		table.insert(self._frameSteps, function(delta)
			if not activeInput then
				return
			end
			if
				self._destroyed
				or not self.Open
				or not self.Gui.Enabled
				or not self.Root.Visible
				or UserInputService:GetFocusedTextBox()
				or activeInput.UserInputState == Enum.UserInputState.Cancel
				or activeInput.UserInputState == Enum.UserInputState.End
			then
				stopDrag(true)
				return
			end
			local pointer = pointerPosition(activeInput)
			if not dragging then
				local threshold = activeInput.UserInputType == Enum.UserInputType.Touch and 8 or 3
				if (pointer - startPointer).Magnitude < threshold then
					return
				end
				dragging = true
			end
			local destination = pointer - pointerOffset
			local position = rootPosition():Lerp(destination, 1 - math.exp(-delta * 45))
			self.Root.Position = UDim2.fromOffset(position.X, position.Y)
		end)
	end

	local function revealElement(element, delay, includeRipple)
		if not element.Visible and not includeRipple then
			return
		end
		element.Visible = false
		task.delay(delay, function()
			if not element.Parent then
				return
			end
			local revealScale = createInstance("UIScale", { Scale = 0.94, Parent = element })
			element.Visible = true
			animate(revealScale, { Scale = 1 }, 0.4, Enum.EasingStyle.Back)
			task.delay(0.4, function()
				revealScale:Destroy()
			end)
		end)
	end

	function NativeWindow:_revealCards(tab, animateCards)
		if tab._revealed then
			return
		end
		tab._revealed = true
		local revealCount = 0
		for index, child in ipairs(tab.List:GetChildren()) do
			if child:IsA("GuiObject") then
				revealElement(child, (animateCards or 0) + revealCount * 0.035)
				revealCount += 1
			end
		end
	end

	function NativeWindow:_playIntro(enabled)
		if self._introDone then
			return
		end
		self._introDone = true
		task.delay(1, function()
			self._autoSaveReady = true
		end)
		local root, body, shadow, scale = self.Root, self.Body, self.Shadow, self.Scale
		if self.CurrentTab then
			self:_revealCards(self.CurrentTab, enabled and 0.15 or 0.25)
		end
		root.Visible = true
		if enabled then
			scale.Scale = self._fitScale or 1
			root.Position = UDim2.fromScale(0.5, 0.5)
			animate(body, { GroupTransparency = 0 }, 0.3)
			animate(self.BodyStroke, { Transparency = 0 }, 0.3)
			animate(shadow, { ImageTransparency = 0.6 }, 0.3)
		else
			root.Position = UDim2.new(0.5, 0, 0.5, 24)
			animate(scale, { Scale = self._fitScale or 1 }, 0.5, Enum.EasingStyle.Back)
			animate(root, { Position = UDim2.fromScale(0.5, 0.5) }, 0.5, Enum.EasingStyle.Quint)
			animate(body, { GroupTransparency = 0 }, 0.35)
			animate(self.BodyStroke, { Transparency = 0 }, 0.35)
		end
		if not enabled then
			animate(shadow, { ImageTransparency = 0.6 }, 0.5)
		end
		for index, tab in ipairs(self.Tabs) do
			revealElement(tab._button, 0.1 + index * 0.05, true)
		end
		self.Indicator.Visible = false
		task.delay(0.15 + #self.Tabs * 0.05, function()
			if self.CurrentTab then
				self:_placeIndicator(self.CurrentTab)
			end
		end)
	end

	function NativeWindow:_showLoader(windowConfig)
		local frameClass = "Frame"
		local loadingDuration = windowConfig.LoadingDuration or 1.6
		local gui = self.Gui
		local canvasGroup = createInstance("CanvasGroup", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 16),
			Size = UDim2.fromOffset(300, 132),
			BackgroundColor3 = nativeTheme.Background,
			BorderSizePixel = 0,
			GroupTransparency = 1,
			ZIndex = 10,
			Parent = gui,
		})
		local corner = addCorner(canvasGroup, UDim.new(0, 12))
		local loaderBorder = addStroke(canvasGroup, nativeTheme.Stroke, 1)
		addEdgeHighlight(canvasGroup)
		addGlow(canvasGroup, UDim2.fromOffset(320, 140), UDim2.new(1, -20, 0, -20), 0.85, 90)
		addGlow(canvasGroup, UDim2.fromOffset(240, 100), UDim2.new(0, 10, 1, 10), 0.9, 270)
		local loaderScale = createInstance("UIScale", { Scale = 0.92, Parent = canvasGroup })
		local loaderShadow = createInstance("ImageLabel", {
			Position = UDim2.fromOffset(-25, -25),
			Size = UDim2.new(1, 50, 1, 50),
			BackgroundTransparency = 1,
			Image = nativeAssets.Shadow,
			ImageColor3 = Color3.new(0, 0, 0),
			ImageTransparency = 1,
			ScaleType = Enum.ScaleType.Slice,
			SliceCenter = Rect.new(49, 49, 450, 450),
			ZIndex = 0,
			Parent = canvasGroup,
		})
		local loaderLogoHolder = createInstance(frameClass, {
			Position = UDim2.fromOffset(24, 26),
			Size = UDim2.fromOffset(40, 40),
			BackgroundTransparency = 1,
			Parent = canvasGroup,
		})
		local loaderLogo = createInstance("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.5, 0.5),
			Rotation = -14,
			BackgroundTransparency = 1,
			ImageColor3 = nativeTheme.Accent,
			ImageTransparency = 1,
			ScaleType = Enum.ScaleType.Fit,
			Parent = loaderLogoHolder,
		})
		applyIcon(loaderLogo, windowConfig.Icon or nativeAssets.Logo)
		task.delay(0.15, function()
			animate(
				loaderLogo,
				{ Size = UDim2.fromScale(0.85, 0.85), Rotation = 0, ImageTransparency = 0 },
				0.6,
				Enum.EasingStyle.Back
			)
		end)
		createLabel({
			Position = UDim2.fromOffset(78, 30),
			Size = UDim2.new(1, -100, 0, 22),
			Text = windowConfig.LoadingTitle or windowConfig.Title or "\077\105\099\104\105\103\117\110",
			TextSize = 20,
			Parent = canvasGroup,
		})
		local loadingCaption = createLabel({
			Position = UDim2.fromOffset(78, 52),
			Size = UDim2.new(1, -100, 0, 16),
			Text = windowConfig.LoadingText or windowConfig.Subtitle or "Loading",
			TextSize = 13,
			FontFace = nativeFonts.Regular,
			TextColor3 = nativeTheme.Muted,
			Parent = canvasGroup,
		})
		local loadingTrack = createInstance(frameClass, {
			Position = UDim2.new(0, 24, 1, -30),
			Size = UDim2.new(1, -48, 0, 4),
			BackgroundColor3 = nativeTheme.Surface3,
			BorderSizePixel = 0,
			ClipsDescendants = true,
			Parent = canvasGroup,
		})
		addCorner(loadingTrack, UDim.new(1, 0))
		local loadingFill = createInstance(frameClass, {
			Size = UDim2.fromScale(0, 1),
			BackgroundColor3 = nativeTheme.Accent,
			BorderSizePixel = 0,
			Parent = loadingTrack,
		})
		addCorner(loadingFill, UDim.new(1, 0))
		local loadingShine = createInstance(frameClass, {
			Position = UDim2.fromScale(-0.4, 0),
			Size = UDim2.fromScale(0.4, 1),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.6,
			BorderSizePixel = 0,
			ZIndex = 2,
			Parent = loadingTrack,
		})
		createInstance("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = loadingShine,
		})
		animate(
			canvasGroup,
			{ GroupTransparency = 0, Position = UDim2.fromScale(0.5, 0.5) },
			0.4,
			Enum.EasingStyle.Quint
		)
		animate(loaderScale, { Scale = 1 }, 0.5, Enum.EasingStyle.Back)
		animate(loaderShadow, { ImageTransparency = 0.6 }, 0.4)
		local shineTween = TweenService:Create(
			loadingShine,
			TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1),
			{ Position = UDim2.fromScale(1, 0) }
		)
		shineTween:Play()
		animate(loadingFill, { Size = UDim2.fromScale(0.85, 1) }, loadingDuration * 0.8, Enum.EasingStyle.Quart)
		task.spawn(loadLucideIcons)
		local loadingSteps = windowConfig.LoadingSteps or { "Preparing interface", "Loading icons", "Almost there" }
		for stepIndex, stepLabel in ipairs(loadingSteps) do
			task.delay(loadingDuration * (stepIndex - 1) / #loadingSteps, function()
				if canvasGroup.Parent then
					loadingCaption.Text = stepLabel
				end
			end)
		end
		task.delay(loadingDuration, function()
			animate(loadingFill, { Size = UDim2.fromScale(1, 1) }, 0.25, Enum.EasingStyle.Quint)
			task.delay(0.25, function()
				shineTween:Cancel()
				for index, child in ipairs(canvasGroup:GetChildren()) do
					if child:IsA("TextLabel") then
						animate(child, { TextTransparency = 1 }, 0.15)
					end
				end
				for index, child in ipairs(loaderLogoHolder:GetChildren()) do
					animate(child, { ImageTransparency = 1 }, 0.15)
				end
				animate(loadingTrack, { BackgroundTransparency = 1 }, 0.15)
				animate(loadingFill, { BackgroundTransparency = 1 }, 0.15)
				animate(loadingShine, { BackgroundTransparency = 1 }, 0.1)
				local fitScale = self._fitScale or 1
				local windowSize = self.Root.Size
				animate(canvasGroup, {
					Size = UDim2.fromOffset(windowSize.X.Offset * fitScale, windowSize.Y.Offset * fitScale),
					Position = UDim2.fromScale(0.5, 0.5),
				}, 0.5, Enum.EasingStyle.Quint)
				animate(corner, { CornerRadius = UDim.new(0, 10) }, 0.5, Enum.EasingStyle.Quint)
				animate(loaderScale, { Scale = 1 }, 0.5, Enum.EasingStyle.Quint)
				task.delay(0.28, function()
					self:_playIntro(true)
					animate(canvasGroup, { GroupTransparency = 1 }, 0.25)
					animate(loaderBorder, { Transparency = 1 }, 0.2)
					animate(loaderShadow, { ImageTransparency = 1 }, 0.2)
				end)
				task.delay(0.6, function()
					canvasGroup:Destroy()
				end)
			end)
		end)
	end

	function NativeWindow:_layoutResponsive()
		local compact = self._compactLayout == true
		local width = self.Root.Size.X.Offset
		local sidebarWidth = compact and (width < 420 and 112 or 140) or 170
		self._sidebarWidth = sidebarWidth
		local sidebar = self.Body:FindFirstChild("Sidebar")
		if sidebar then
			sidebar.Size = UDim2.new(0, sidebarWidth, 1, 0)
			local header = sidebar:FindFirstChild("Header")
			local left = header and header:FindFirstChild("Left")
			local titleGroup = left and left:FindFirstChild("Title")
			if titleGroup then
				titleGroup.Position = UDim2.fromOffset(compact and 38 or 60, compact and 18 or 25)
				titleGroup.Size = UDim2.new(1, compact and -44 or -64, 0, compact and 48 or 40)
				for _, label in ipairs(titleGroup:GetChildren()) do
					if label:IsA("TextLabel") then
						local title = label.Name == "Title"
						label.TextWrapped = compact
						label.TextTruncate = compact and Enum.TextTruncate.None or Enum.TextTruncate.AtEnd
						label.TextSize = compact and (title and 12 or 11) or (title and 14 or 13)
						label.Position = UDim2.fromOffset(0, title and 0 or (compact and 30 or 20))
						label.Size = UDim2.new(1, 0, 0, title and (compact and 28 or 20) or 14)
					end
				end
			end
			if left then
				for _, image in ipairs(left:GetChildren()) do
					if image:IsA("ImageLabel") then
						image.Position = UDim2.fromOffset(compact and 8 or 22, compact and 23 or 27)
						image.Size = UDim2.fromOffset(compact and 24 or 30, compact and 24 or 28)
					end
				end
			end
			local footer = sidebar:FindFirstChild("KeybindFooter")
			if footer then
				footer.Position = UDim2.new(0, compact and 10 or 22, 1, -36)
				footer.Size = UDim2.new(1, compact and -20 or -44, 0, 22)
				for _, label in ipairs(footer:GetChildren()) do
					if label:IsA("TextLabel") then
						label.Text = compact and "Menu" or "Abrir / minimizar"
					end
				end
			end
		end
		local divider = self.Body:FindFirstChild("SidebarDivider")
		if divider then
			divider.Position = UDim2.new(0, sidebarWidth, 0, 28)
		end
		self.Content.Position = UDim2.fromOffset(sidebarWidth + 1, 0)
		self.Content.Size = UDim2.new(1, -sidebarWidth - 1, 1, 0)
		local tabPadding = self.TabList and self.TabList:FindFirstChildOfClass("UIPadding")
		if tabPadding then
			tabPadding.PaddingLeft = UDim.new(0, compact and 8 or 16)
			tabPadding.PaddingRight = tabPadding.PaddingLeft
		end
		for _, tab in ipairs(self.Tabs) do
			if tab._label then
				tab._label.TextSize = compact and 12 or 14
				tab._label.TextWrapped = compact
				tab._label.TextTruncate = compact and Enum.TextTruncate.None or Enum.TextTruncate.AtEnd
			end
			if tab._button then
				tab._button.Size = UDim2.new(1, 0, 0, compact and 44 or (isTouchDevice and 40 or 36))
			end
			if tab._heading then
				tab._heading.TextSize = compact and 18 or 22
			end
			local padding = tab.List and tab.List:FindFirstChildOfClass("UIPadding")
			if padding then
				padding.PaddingLeft = UDim.new(0, compact and 12 or 24)
				padding.PaddingRight = padding.PaddingLeft
				padding.PaddingBottom = UDim.new(0, compact and 12 or 24)
			end
			local layout = tab.List and tab.List:FindFirstChildOfClass("UIListLayout")
			if layout then
				layout.Padding = UDim.new(0, compact and 6 or 8)
			end
		end
	end

	function NativeWindow:_fitToScreen(immediate)
		local viewport = self.Gui.AbsoluteSize
		if viewport.X <= 0 or viewport.Y <= 0 then
			return
		end
		local preferred = self._preferredSize or self.Root.Size
		local size = preferred
		if self.Responsive then
			size = UDim2.fromOffset(
				math.clamp(preferred.X.Offset, 320, math.max(320, viewport.X - 24)),
				math.clamp(preferred.Y.Offset, 260, math.max(260, viewport.Y - 24))
			)
		end
		if self.Root.Size ~= size then
			self.Root.Size = size
		end
		self._compactLayout = size.X.Offset < 560 or viewport.Y < 430
		self:_layoutResponsive()
		self._fitScale = math.max(
			0.45,
			math.min(1, (viewport.X - 24) / math.max(size.X.Offset, 1), (viewport.Y - 24) / math.max(size.Y.Offset, 1))
		)
		if self._introDone and self.Open then
			if immediate then
				self.Scale.Scale = self._fitScale
			else
				animate(self.Scale, { Scale = self._fitScale }, 0.2)
			end
		end
	end

	function NativeWindow:_clampToScreen()
		if not self.KeepOnScreen then
			return
		end
		local viewportSize = self.Gui.AbsoluteSize
		local root = self.Root
		local halfSize = root.AbsoluteSize / 2
		local center = root.AbsolutePosition + halfSize - self.Gui.AbsolutePosition
		local clampedCenter = Vector2.new(
			math.clamp(
				center.X,
				math.min(halfSize.X, viewportSize.X / 2),
				math.max(viewportSize.X - halfSize.X, viewportSize.X / 2)
			),
			math.clamp(
				center.Y,
				math.min(halfSize.Y, viewportSize.Y / 2),
				math.max(viewportSize.Y - halfSize.Y, viewportSize.Y / 2)
			)
		)
		if (clampedCenter - center).Magnitude > 0.5 then
			animate(
				root,
				{ Position = UDim2.fromOffset(clampedCenter.X, clampedCenter.Y) },
				0.25,
				Enum.EasingStyle.Quint
			)
		end
	end

	function NativeWindow:_createOpenButton(buttonConfig)
		local gui = self.Gui
		local openButton = createInstance("TextButton", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 14),
			Size = UDim2.fromOffset(0, 40),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = nativeTheme.Background,
			BorderSizePixel = 0,
			Text = "",
			AutoButtonColor = false,
			ZIndex = 30,
			Parent = gui,
		})
		addCorner(openButton, UDim.new(1, 0))
		addStroke(openButton, nativeTheme.Stroke)
		addPadding(openButton, 12, 16)
		local buttonLogo = createInstance("ImageLabel", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 0, 0.5, 0),
			Size = UDim2.fromOffset(20, 20),
			BackgroundTransparency = 1,
			ImageColor3 = nativeTheme.Accent,
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = 31,
			Parent = openButton,
		})
		applyIcon(buttonLogo, buttonConfig.Icon or nativeAssets.Logo)
		createLabel({
			Position = UDim2.fromOffset(28, 0),
			Size = UDim2.new(0, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			Text = buttonConfig.Title or "\077\105\099\104\105\103\117\110",
			TextSize = 13,
			TextTruncate = Enum.TextTruncate.None,
			ZIndex = 31,
			Parent = openButton,
		})
		self.OpenButton = openButton
		local draggingButton, buttonMoved = false, false
		local dragStart = Vector2.zero
		openButton.InputBegan:Connect(function(input)
			if isPrimaryInput(input) then
				draggingButton, buttonMoved = true, false
				dragStart = getPointerPosition() - openButton.AbsolutePosition
			end
		end)
		table.insert(
			self._connections,
			UserInputService.InputChanged:Connect(function(input)
				if not draggingButton then
					return
				end
				if isPointerMovement(input) then
					local dragDelta = getPointerPosition() - dragStart - gui.AbsolutePosition
					if (dragDelta - (openButton.AbsolutePosition - gui.AbsolutePosition)).Magnitude > 3 then
						buttonMoved = true
					end
					openButton.AnchorPoint = Vector2.new(0, 0)
					openButton.Position = UDim2.fromOffset(
						math.clamp(dragDelta.X, 0, math.max(gui.AbsoluteSize.X - openButton.AbsoluteSize.X, 0)),
						math.clamp(dragDelta.Y, 0, math.max(gui.AbsoluteSize.Y - openButton.AbsoluteSize.Y, 0))
					)
				end
			end)
		)
		table.insert(
			self._connections,
			UserInputService.InputEnded:Connect(function(input)
				if draggingButton and isPrimaryInput(input) then
					draggingButton = false
					if not buttonMoved then
						self:Toggle()
					end
				end
			end)
		)
	end

	function NativeWindow:_enableResize(value)
		local maximumSize = self.MaxSize or Vector2.new(math.huge, math.huge)
		local resizeHandle = createInstance("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, 4, 1, 4),
			Size = UDim2.fromOffset(32, 32),
			BackgroundTransparency = 1,
			Active = true,
			ZIndex = 20,
			Parent = self.Root,
		})
		local resizeIcon, resizingWindow =
			createInstance("ImageLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, -16, 0.5, -16),
				Size = UDim2.fromOffset(96, 96),
				BackgroundTransparency = 1,
				Image = "rbxassetid://120997033468887",
				ImageColor3 = nativeTheme.Accent,
				ImageTransparency = 0.8,
				ZIndex = 20,
				Parent = resizeHandle,
			}), false
		local startingSize = self.Root.Size
		local resizeStart = Vector2.zero
		local targetSize
		resizeHandle.InputBegan:Connect(function(input)
			if isPrimaryInput(input) then
				resizingWindow = true
				startingSize = self.Root.Size
				resizeStart = getPointerPosition()
				animate(resizeIcon, { ImageTransparency = 0.35 }, 0.1)
			end
		end)
		resizeHandle.MouseEnter:Connect(function()
			if not resizingWindow then
				animate(resizeIcon, { ImageTransparency = 0.35 }, 0.1)
			end
		end)
		resizeHandle.MouseLeave:Connect(function()
			if not resizingWindow then
				animate(resizeIcon, { ImageTransparency = 0.8 }, 0.17)
			end
		end)
		table.insert(
			self._connections,
			UserInputService.InputEnded:Connect(function(input)
				if resizingWindow and isPrimaryInput(input) then
					resizingWindow = false
					animate(resizeIcon, { ImageTransparency = 0.8 }, 0.17)
					if targetSize then
						self.Root.Size = UDim2.fromOffset(targetSize.X, targetSize.Y)
						self._preferredSize = self.Root.Size
						targetSize = nil
					end
					self:_fitToScreen()
					self:_clampToScreen()
				end
			end)
		)
		table.insert(self._frameSteps, function(deltaTime)
			if not resizingWindow then
				return
			end
			local pointerDelta = (getPointerPosition() - resizeStart) / math.max(self.Scale.Scale, 0.01)
			local maxWidth, maxHeight = maximumSize.X, maximumSize.Y
			if self.Responsive then
				local viewport = self.Gui.AbsoluteSize
				maxWidth = math.min(maxWidth, math.max(320, viewport.X - 24))
				maxHeight = math.min(maxHeight, math.max(260, viewport.Y - 24))
			end
			local minWidth = math.min(maxWidth, self.Responsive and math.max(320, value.X) or value.X)
			local minHeight = math.min(maxHeight, self.Responsive and math.max(260, value.Y) or value.Y)
			targetSize = Vector2.new(
				math.clamp(startingSize.X.Offset + pointerDelta.X * 2, minWidth, maxWidth),
				math.clamp(startingSize.Y.Offset + pointerDelta.Y * 2, minHeight, maxHeight)
			)
			local currentSize = Vector2.new(self.Root.Size.X.Offset, self.Root.Size.Y.Offset)
			local smoothingAlpha = 1 - math.exp(-deltaTime * 35)
			local smoothedSize = currentSize:Lerp(targetSize, smoothingAlpha)
			smoothedSize = Vector2.new(math.floor(smoothedSize.X + 0.5), math.floor(smoothedSize.Y + 0.5))
			if smoothedSize ~= currentSize then
				self.Root.Size = UDim2.fromOffset(smoothedSize.X, smoothedSize.Y)
			end
		end)
	end

	local function configFilePath(window, name)
		return storageFilePath(window.ConfigFolder, name, ".json")
	end

	local function hasFileApi()
		local functionType = "function"
		return type(writefile) == functionType and type(readfile) == functionType and type(isfile) == functionType
	end

	local function ensureConfigFolder(folder)
		ensureStorageFolder(folder)
	end

	local function serializeControl(control)
		local controlType = control._type
		local controlValue = control:Get()
		if controlType == "Keybind" then
			return { Type = controlType, Value = controlValue and controlValue.Name or nil }
		elseif controlType == "ColorPicker" then
			return { Type = controlType, Value = { controlValue.R, controlValue.G, controlValue.B } }
		end
		return { Type = controlType, Value = controlValue }
	end

	local function restoreControl(control, record, skipCallback)
		local controlType = control._type
		local savedValue = record.Value
		if controlType == "Keybind" then
			control:Set(savedValue and Enum.KeyCode[savedValue] or nil, skipCallback)
		elseif controlType == "ColorPicker" then
			if type(savedValue) == "table" then
				control:Set(Color3.new(savedValue[1], savedValue[2], savedValue[3]), skipCallback)
			end
		elseif savedValue ~= nil then
			control:Set(savedValue, skipCallback)
		end
	end

	function NativeWindow:SaveConfig(name)
		name = name or self.ConfigName
		if not hasFileApi() then
			return false, "file API unavailable"
		end
		ensureConfigFolder(self.ConfigFolder)
		local configValues = {}
		for flag, control in pairs(NativeLibrary.Flags) do
			if control._type and type(control.Get) == "function" then
				configValues[flag] = serializeControl(control)
			end
		end
		local success, result = pcall(function()
			writefile(configFilePath(self, name), HttpService:JSONEncode(configValues))
		end)
		if success then
			self.ConfigName = name
		end
		return success, result
	end

	function NativeWindow:LoadConfig(name, skipCallback)
		name = name or self.ConfigName
		if not hasFileApi() then
			return false, "file API unavailable"
		end
		local configPath = configFilePath(self, name)
		if not isfile(configPath) then
			return false, "no config named " .. name
		end
		local success, result = pcall(function()
			return HttpService:JSONDecode(readfile(configPath))
		end)
		if not success or type(result) ~= "table" then
			return false, "config is not valid JSON"
		end
		local _autoSaveEnabled = self._autoSaveEnabled
		self._autoSaveEnabled = false
		for flag, record in pairs(result) do
			local control = NativeLibrary.Flags[flag]
			if
				control
				and type(control.Set) == "function"
				and type(record) == "table"
				and record.Type == control._type
			then
				pcall(restoreControl, control, record, skipCallback == true)
			end
		end
		self._autoSaveEnabled = _autoSaveEnabled
		self._autoSaveReady = true
		self.ConfigName = name
		return true
	end

	function NativeWindow:DeleteConfig(name)
		if not hasFileApi() or type(delfile) ~= "function" then
			return false, "file API unavailable"
		end
		local configPath = configFilePath(self, name)
		if not isfile(configPath) then
			return false, "no config named " .. name
		end
		delfile(configPath)
		return true
	end

	function NativeWindow:ListConfigs()
		local configNames = {}
		self.ConfigFolder = resolveStoragePath(self.ConfigFolder)
		if type(listfiles) ~= "function" or type(isfolder) ~= "function" or not isfolder(self.ConfigFolder) then
			return configNames
		end
		for index, filePath in ipairs(listfiles(self.ConfigFolder)) do
			local configName = filePath:match("([^/\\]+)%.json$")
			if configName then
				table.insert(configNames, configName)
			end
		end
		table.sort(configNames)
		return configNames
	end

	function NativeWindow:_autoSave()
		if not self._autoSaveEnabled or self._destroyed or not self._autoSaveReady then
			return
		end
		if self._autoSavePending then
			return
		end
		self._autoSavePending = true
		task.delay(0.5, function()
			self._autoSavePending = false
			if not self._destroyed then
				self:SaveConfig(self.ConfigName)
			end
		end)
	end

	local function createEmptyPage(parent, icon, message)
		local emptyState = createInstance("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, -10),
			Size = UDim2.fromOffset(200, 70),
			BackgroundTransparency = 1,
			Parent = parent,
		})
		local emptyIcon = createInstance("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 0),
			Size = UDim2.fromOffset(26, 26),
			BackgroundTransparency = 1,
			ImageColor3 = nativeTheme.Muted,
			ImageTransparency = 0.15,
			ScaleType = Enum.ScaleType.Fit,
			Parent = emptyState,
		})
		applyIcon(emptyIcon, icon)
		local emptyLabel = createLabel({
			Position = UDim2.fromOffset(0, 36),
			Size = UDim2.new(1, 0, 0, 16),
			Text = message,
			TextSize = 13,
			FontFace = nativeFonts.Regular,
			TextColor3 = nativeTheme.Muted,
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = emptyState,
		})
		return emptyState, emptyLabel, emptyIcon
	end

	local function createStatisticCard(grid, order, icon, title)
		local statCard = createInstance("Frame", {
			Size = UDim2.new(0.5, -4, 0, 62),
			BackgroundColor3 = nativeTheme.Surface2,
			BorderSizePixel = 0,
			LayoutOrder = order,
			Parent = grid,
		})
		addCorner(statCard)
		addStroke(statCard)
		statCard:SetAttribute("NoDrag", true)
		if icon then
			createIcon(statCard, icon, nativeTheme.Muted, UDim2.new(0, 14, 0, 21))
		end
		createLabel({
			Position = UDim2.fromOffset(icon and 36 or 14, 12),
			Size = UDim2.new(1, -(icon and 50 or 28), 0, 16),
			Text = title,
			TextSize = 12,
			TextColor3 = nativeTheme.Muted,
			Parent = statCard,
		})
		return createLabel({
			Position = UDim2.fromOffset(14, 34),
			Size = UDim2.new(1, -28, 0, 18),
			Text = "…",
			TextSize = 15,
			Parent = statCard,
		})
	end

	local function revealHomeContent(container)
		local revealTargets = {}
		local function collectRevealTargets(container)
			for index, child in ipairs(container:GetChildren()) do
				if child:IsA("TextLabel") or child:IsA("TextButton") or child:IsA("TextBox") then
					table.insert(revealTargets, { child, "TextTransparency", child.TextTransparency })
				elseif child:IsA("ImageLabel") or child:IsA("ImageButton") then
					table.insert(revealTargets, { child, "ImageTransparency", child.ImageTransparency })
				elseif child:IsA("UIStroke") then
					table.insert(revealTargets, { child, "Transparency", child.Transparency })
				elseif child:IsA("Frame") then
					table.insert(revealTargets, { child, "BackgroundTransparency", child.BackgroundTransparency })
				end
				collectRevealTargets(child)
			end
		end
		if container:IsA("Frame") then
			table.insert(revealTargets, { container, "BackgroundTransparency", container.BackgroundTransparency })
		end
		collectRevealTargets(container)
		for index, target in ipairs(revealTargets) do
			target[1][target[2]] = 1
			animate(target[1], { [target[2]] = target[3] }, 0.28)
		end
	end

	local function revealPage(page, delay)
		delay = delay or 0
		page.GroupTransparency = 1
		page.Position = UDim2.fromOffset(0, delay + 14)
		page.Visible = true
		animate(page, { GroupTransparency = 0, Position = UDim2.fromOffset(0, delay) }, 0.32, Enum.EasingStyle.Quint)
	end

	function NativeWindow:_styleDashboardHome(tab, config)
		if tab._dashboard then
			return
		end
		local list = tab.List
		local values = tab._homeStatValues or {}
		local access = tab._accessBadges
		local welcome = access and access.Access.Parent.Parent.Parent
		if not welcome then
			for _, child in ipairs(list:GetChildren()) do
				if child:IsA("Frame") and child:FindFirstChildWhichIsA("ImageLabel") then
					welcome = child
					break
				end
			end
		end
		if not welcome then
			return
		end
		tab._dashboard = true
		tab._homeActions = {}
		tab._dashboardControls = {}
		local system = list:FindFirstChild("SystemInfo")
		if system then
			system.Visible = false
		end

		local function card(name, parent, order, button)
			local frame = createInstance(button and "TextButton" or "Frame", {
				Name = name,
				BackgroundColor3 = nativeTheme.Surface2,
				BackgroundTransparency = 0.06,
				BorderSizePixel = 0,
				LayoutOrder = order or 0,
				Parent = parent,
			})
			if button then
				frame.Text = ""
				frame.AutoButtonColor = false
				frame.Selectable = true
			end
			frame:SetAttribute("NoDrag", true)
			addCorner(frame, UDim.new(0, 12))
			addStroke(frame, nativeTheme.Stroke)
			return frame
		end

		local function label(parent, text, size, muted)
			return createLabel({
				Text = text,
				TextSize = size,
				FontFace = muted and nativeFonts.Regular or nativeFonts.Bold,
				TextColor3 = muted and nativeTheme.Muted or nativeTheme.Text,
				Parent = parent,
			})
		end

		local function moveValue(value, parent, textSize)
			if not value then
				return label(parent, "Indisponível", textSize, true)
			end
			value.Parent = parent
			value.FontFace = nativeFonts.Medium
			value.TextSize = textSize
			return value
		end
		local top = createInstance("Frame", {
			Name = "SessionDashboard",
			Size = UDim2.new(1, 0, 0, 222),
			BackgroundTransparency = 1,
			LayoutOrder = 2,
			Parent = list,
		})
		welcome.Parent = top
		welcome.Name = "WelcomeCard"
		welcome.BackgroundTransparency = 0.06
		local avatar, welcomeText, subtitle
		for _, child in ipairs(welcome:GetChildren()) do
			if child:IsA("ImageLabel") then
				avatar = child
			elseif child:IsA("TextLabel") then
				if not welcomeText then
					welcomeText = child
				else
					subtitle = child
				end
			end
		end
		if avatar then
			avatar.Position = UDim2.fromOffset(14, 16)
			avatar.Size = UDim2.fromOffset(48, 48)
		end
		if welcomeText then
			welcomeText.Text = "Bem-vindo, " .. localPlayer.DisplayName
			welcomeText.TextSize = 17
			welcomeText.FontFace = nativeFonts.Bold
			welcomeText.Position = UDim2.fromOffset(76, 16)
			welcomeText.Size = UDim2.new(1, -90, 0, 24)
		end
		if subtitle then
			subtitle.Position = UDim2.fromOffset(76, 43)
			subtitle.Size = UDim2.new(1, -90, 0, 18)
			subtitle.Text = config.Greeting or "Sua sessão, em um só lugar."
		end
		local badgeRow = welcome:FindFirstChild("AccessBadges")
		local badgeLayout = badgeRow and badgeRow:FindFirstChildWhichIsA("UIListLayout")
		if badgeRow then
			badgeRow.Position = UDim2.fromOffset(14, 76)
		end
		local session = card("GameSessionCard", top)
		local gameImage = createInstance("ImageLabel", {
			Name = "GameThumbnail",
			Position = UDim2.fromOffset(14, 14),
			Size = UDim2.fromOffset(54, 54),
			BackgroundColor3 = nativeTheme.Surface,
			BorderSizePixel = 0,
			Parent = session,
		})
		gameImage:SetAttribute("UIUnthemed", true)
		addCorner(gameImage, UDim.new(0, 10))
		gameImage.Image = tonumber(game.GameId)
				and game.GameId > 0
				and "rbxthumb://type=GameIcon&id=" .. tostring(game.GameId) .. "&w=150&h=150"
			or nativeAssets.Logo
		local gameName = moveValue(values.Game, session, 15)
		gameName.Position = UDim2.fromOffset(80, 14)
		gameName.Size = UDim2.new(1, -94, 0, 24)
		local gameCaption = label(session, "Servidor atual", 12, true)
		gameCaption.Position = UDim2.fromOffset(80, 42)
		gameCaption.Size = UDim2.new(1, -94, 0, 18)
		local playerCount = moveValue(values.Players, session, 12)
		local uptime = moveValue(values.Uptime, session, 12)
		local job = label(session, "", 11, true)
		local jobID = tostring(game.JobId or "")
		job.Text = jobID ~= "" and "ID " .. jobID:sub(1, 8) .. "…" .. jobID:sub(-4) or "ID indisponível"
		local playersIcon = createIcon(session, "users", nativeTheme.Muted, UDim2.fromOffset(14, 87))
		local uptimeIcon = createIcon(session, "timer", nativeTheme.Muted, UDim2.fromOffset(120, 87))
		playerCount.Position = UDim2.fromOffset(36, 76)
		playerCount.Size = UDim2.fromOffset(78, 22)
		uptime.Position = UDim2.fromOffset(142, 76)
		uptime.Size = UDim2.new(1, -156, 0, 22)
		job.Position = UDim2.fromOffset(14, 103)
		job.Size = UDim2.new(1, -28, 0, 16)
		local performance = card("PerformanceCard", top)
		local performanceTitle = label(performance, "Desempenho", 13, false)
		performanceTitle.TextXAlignment = Enum.TextXAlignment.Center
		local ring = createInstance("Frame", { Name = "FPSRing", BackgroundTransparency = 1, Parent = performance })
		local segments = {}
		for index = 1, 48 do
			local angle = math.rad((index - 1) * 7.2 + 10)
			local segment = createInstance("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, math.sin(angle) * 49, 0.5, -math.cos(angle) * 49),
				Size = UDim2.fromOffset(4, 9),
				Rotation = math.deg(angle),
				BackgroundColor3 = nativeTheme.Stroke,
				BorderSizePixel = 0,
				Parent = ring,
			})
			addCorner(segment, UDim.new(1, 0))
			segments[index] = segment
		end
		local fps = moveValue(values.FPS, ring, 26)
		fps.AnchorPoint = Vector2.new(0.5, 0.5)
		fps.Position = UDim2.fromScale(0.5, 0.5)
		fps.Size = UDim2.new(1, -20, 0, 32)
		fps.TextXAlignment = Enum.TextXAlignment.Center
		local fpsCaption = label(performance, "quadros por segundo", 11, true)
		fpsCaption.ZIndex = 3
		fpsCaption.Size = UDim2.new(1, -20, 0, 20)
		fpsCaption.TextXAlignment = Enum.TextXAlignment.Center
		local pingRow = createInstance("Frame", {
			Name = "PingRow",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.new(1, -20, 0, 22),
			Parent = performance,
		})
		createInstance("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 6),
			Parent = pingRow,
		})
		local ping = moveValue(values.Ping, pingRow, 12)
		ping.TextXAlignment = Enum.TextXAlignment.Center
		local pingIcon = createIcon(pingRow, "wifi", nativeTheme.Muted, UDim2.new(0, 0, 0.5, 0))
		pingIcon.LayoutOrder = 1
		ping.LayoutOrder = 2
		ping.Size = UDim2.fromOffset(0, 22)
		ping.AutomaticSize = Enum.AutomaticSize.X
		ping.TextTruncate = Enum.TextTruncate.None
		ping.TextXAlignment = Enum.TextXAlignment.Left
		local community = card("CommunityCard", list, 3)
		community.Size = UDim2.new(1, 0, 0, 216)
		local communityPalette = {
			Blurple = Color3.fromRGB(88, 101, 242),
			Surface = Color3.fromRGB(88, 101, 242),
			SurfaceLow = Color3.fromRGB(48, 55, 142),
			Text = Color3.fromRGB(254, 254, 255),
			Muted = Color3.fromRGB(254, 254, 255),
			Invite = Color3.fromRGB(84, 218, 148),
			InviteHover = Color3.fromRGB(108, 233, 167),
			InvitePressed = Color3.fromRGB(63, 187, 125),
			InviteText = Color3.fromRGB(12, 37, 25),
		}
		community.BackgroundColor3 = Color3.new(1, 1, 1)
		community.BackgroundTransparency = 0
		local communityGradient = createInstance("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, communityPalette.Surface),
				ColorSequenceKeypoint.new(0.55, Color3.fromRGB(69, 78, 198)),
				ColorSequenceKeypoint.new(1, communityPalette.SurfaceLow),
			}),
			Rotation = 18,
			Parent = community,
		})
		local communityBorder = community:FindFirstChildWhichIsA("UIStroke")
		communityBorder.Color = communityPalette.Blurple
		communityBorder.Transparency = 0.12
		local communityGlow = createInstance("ImageLabel", {
			Name = "CommunityGlow",
			Position = UDim2.fromOffset(-22, -20),
			Size = UDim2.new(1, 44, 1, 44),
			BackgroundTransparency = 1,
			Image = nativeAssets.Shadow,
			ImageColor3 = communityPalette.Blurple,
			ImageTransparency = 0.36,
			ScaleType = Enum.ScaleType.Slice,
			SliceCenter = Rect.new(49, 49, 450, 450),
			ZIndex = 0,
			Active = false,
			Selectable = false,
			Parent = community,
		})
		communityGlow:SetAttribute("UIUnthemed", true)
		local communityGroup = createInstance("Frame", {
			Name = "CommunityIdentity",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 20),
			Size = UDim2.new(1, -40, 0, 104),
			Parent = community,
		})
		local communityConstraint =
			createInstance("UISizeConstraint", { MaxSize = Vector2.new(480, 104), Parent = communityGroup })
		local communityIcon = createInstance("ImageLabel", {
			Name = "CommunityAvatar",
			Size = UDim2.fromOffset(72, 72),
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			BackgroundColor3 = communityPalette.SurfaceLow,
			BorderSizePixel = 0,
			Parent = communityGroup,
		})
		communityIcon:SetAttribute("UIUnthemed", true)
		addCorner(communityIcon, UDim.new(0, 12))
		local placeholderIcon =
			createIcon(communityIcon, "messages-square", communityPalette.Text, UDim2.new(0.5, -8, 0.5, 0))
		placeholderIcon:SetAttribute("UIUnthemed", true)
		local communityInfo = createInstance("Frame", {
			Name = "CommunityInfo",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(88, 0),
			Size = UDim2.new(1, -88, 1, 0),
			Parent = communityGroup,
		})
		local communityTitle = label(
			communityInfo,
			"\067\111\109\117\110\105\100\097\100\101\032\077\105\099\104\105\103\117\110",
			24,
			false
		)
		communityTitle.Position = UDim2.fromOffset(0, 0)
		communityTitle.Size = UDim2.new(1, 0, 0, 32)
		communityTitle.TextXAlignment = Enum.TextXAlignment.Center
		communityTitle.RichText = false
		communityTitle.TextColor3 = communityPalette.Text
		local communitySubtitle = label(communityInfo, "Converse com a comunidade no Discord", 13, true)
		communitySubtitle.Position, communitySubtitle.Size = UDim2.fromOffset(0, 36), UDim2.new(1, 0, 0, 20)
		communitySubtitle.TextXAlignment = Enum.TextXAlignment.Center
		communitySubtitle.TextColor3 = communityPalette.Muted
		communitySubtitle.TextWrapped, communitySubtitle.TextTruncate = true, Enum.TextTruncate.None
		local memberCounts = label(communityInfo, "Carregando comunidade…", 14, true)
		memberCounts.Position = UDim2.fromOffset(0, 64)
		memberCounts.Size = UDim2.new(1, 0, 0, 26)
		memberCounts.TextXAlignment = Enum.TextXAlignment.Center
		memberCounts.TextWrapped = true
		memberCounts.TextTruncate = Enum.TextTruncate.None
		memberCounts.TextColor3 = communityPalette.Muted
		local invite = card("CopyDiscordInvite", community, nil, true)
		invite.AnchorPoint = Vector2.new(0.5, 0)
		invite.Position = UDim2.new(0.5, 0, 0, 148)
		invite.Size = UDim2.new(1, -32, 0, 48)
		createInstance("UISizeConstraint", { MaxSize = Vector2.new(220, 48), Parent = invite })
		invite.BackgroundColor3 = communityPalette.Invite
		invite.BackgroundTransparency = 0
		local inviteBorder = invite:FindFirstChildWhichIsA("UIStroke")
		inviteBorder.Color = communityPalette.InviteHover
		inviteBorder.Transparency = 0.4
		local inviteLabel = label(invite, "Copiar convite", 14, false)
		inviteLabel.Size = UDim2.fromScale(1, 1)
		inviteLabel.TextXAlignment = Enum.TextXAlignment.Center
		inviteLabel.TextColor3 = communityPalette.InviteText
		local inviteHovered, inviteFocused, invitePressed = false, false, false
		local function updateInviteState()
			local highlighted = inviteHovered or inviteFocused
			animate(invite, {
				BackgroundColor3 = invitePressed and communityPalette.InvitePressed
					or highlighted and communityPalette.InviteHover
					or communityPalette.Invite,
			}, 0.12)
			animate(
				inviteBorder,
				{ Transparency = inviteFocused and 0 or 0.4, Thickness = inviteFocused and 2 or 1 },
				0.12
			)
		end
		invite.MouseEnter:Connect(function()
			inviteHovered = true
			updateInviteState()
		end)
		invite.MouseLeave:Connect(function()
			inviteHovered = false
			invitePressed = false
			updateInviteState()
		end)
		invite.SelectionGained:Connect(function()
			inviteFocused = true
			updateInviteState()
		end)
		invite.SelectionLost:Connect(function()
			inviteFocused = false
			invitePressed = false
			updateInviteState()
		end)
		invite.InputBegan:Connect(function(input)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				invitePressed = true
				updateInviteState()
			end
		end)
		invite.InputEnded:Connect(function(input)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				invitePressed = false
				updateInviteState()
			end
		end)
		invite.Activated:Connect(function()
			local handler = tab._homeActions.Discord
			if type(handler) == "function" then
				invokeCallback(handler)
			end
		end)
		local actions = createInstance("Frame", {
			Name = "SessionActions",
			Size = UDim2.new(1, 0, 0, 82),
			BackgroundTransparency = 1,
			LayoutOrder = 4,
			Parent = list,
		})
		local definitions = {
			{ Id = "Rejoin", Title = "Reconectar", Desc = "Voltar à sessão atual", Icon = "refresh-cw" },
			{
				Id = "ServerHop",
				Title = "Trocar de servidor",
				Desc = "Encontrar outra sessão",
				Icon = "arrow-left-right",
			},
			{ Id = "CopyJob", Title = "Copiar ID", Desc = "Compartilhar esta sessão", Icon = "copy" },
		}
		for index, definition in ipairs(definitions) do
			local button = card(definition.Id, actions, index, true)
			local actionIcon = createIcon(button, definition.Icon, nativeTheme.Muted, UDim2.fromOffset(14, 14))
			local title = label(button, definition.Title, 13, false)
			title.Position = UDim2.fromOffset(14, 36)
			title.Size = UDim2.new(1, -28, 0, 20)
			local description = label(button, definition.Desc, 11, true)
			description.Position = UDim2.fromOffset(14, 58)
			description.Size = UDim2.new(1, -28, 0, 18)
			button.Activated:Connect(function()
				local handler = tab._homeActions[definition.Id]
				if button.Interactable and type(handler) == "function" then
					invokeCallback(handler)
				end
			end)
			button.MouseEnter:Connect(function()
				animate(button, { BackgroundColor3 = nativeTheme.Surface3 }, 0.12)
			end)
			button.MouseLeave:Connect(function()
				animate(button, { BackgroundColor3 = nativeTheme.Surface2 }, 0.12)
			end)
			tab._dashboardControls[definition.Id] =
				{ Button = button, Title = title, Description = description, Icon = actionIcon }
		end
		local details = createInstance("Frame", {
			Name = "SessionDetails",
			Size = UDim2.new(1, 0, 0, 50),
			BackgroundTransparency = 1,
			LayoutOrder = 5,
			Parent = list,
		})
		local detailValues = {}
		for index, definition in ipairs({
			{ Key = "Executor", Label = "Executor" },
			{ Key = "Time", Label = "Horário" },
			{ Key = "Memory", Label = "Memória Luau" },
		}) do
			local heading = label(details, definition.Label, 10, true)
			heading.Position = UDim2.new((index - 1) / 3, 4, 0, 0)
			heading.Size = UDim2.new(1 / 3, -8, 0, 16)
			local value = moveValue(values[definition.Key], details, 12)
			value.Position = UDim2.new((index - 1) / 3, 4, 0, 19)
			value.Size = UDim2.new(1 / 3, -8, 0, 22)
			detailValues[index] = value
		end

		local function layout()
			if self._destroyed or not list.Parent then
				return
			end
			local scale, ancestor = 1, list
			while ancestor and ancestor ~= self.Gui do
				for _, child in ipairs(ancestor:GetChildren()) do
					if child:IsA("UIScale") and child.Scale > 0 then
						scale *= child.Scale
					end
				end
				ancestor = ancestor.Parent
			end
			local width = list.AbsoluteSize.X / scale
			local padding = list:FindFirstChildWhichIsA("UIPadding")
			if padding then
				width = width * (1 - padding.PaddingLeft.Scale - padding.PaddingRight.Scale)
					- padding.PaddingLeft.Offset
					- padding.PaddingRight.Offset
			end
			width = math.floor(width + 0.5)
			if width <= 0 then
				return
			end
			local compact = width < 430
			local stackCommunity = width < 360
			community.Size = UDim2.new(1, 0, 0, stackCommunity and 280 or 216)
			communityGroup.Size = UDim2.new(1, stackCommunity and -24 or -40, 0, stackCommunity and 184 or 104)
			communityGroup.Position = UDim2.new(0.5, 0, 0, stackCommunity and 16 or 20)
			communityConstraint.MaxSize = Vector2.new(480, stackCommunity and 184 or 104)
			communityIcon.Size = UDim2.fromOffset(stackCommunity and 56 or 72, stackCommunity and 56 or 72)
			communityIcon.AnchorPoint = stackCommunity and Vector2.new(0.5, 0) or Vector2.new(0, 0.5)
			communityIcon.Position = stackCommunity and UDim2.fromScale(0.5, 0) or UDim2.fromScale(0, 0.5)
			communityInfo.Position = UDim2.fromOffset(stackCommunity and 0 or 88, stackCommunity and 68 or 0)
			communityInfo.Size = stackCommunity and UDim2.new(1, 0, 0, 116) or UDim2.new(1, -88, 1, 0)
			communityTitle.TextSize = stackCommunity and 22 or 24
			communitySubtitle.Position = UDim2.fromOffset(0, 36)
			communitySubtitle.Size = UDim2.new(1, 0, 0, stackCommunity and 32 or 20)
			memberCounts.Position = UDim2.fromOffset(0, stackCommunity and 76 or 64)
			invite.Position = UDim2.new(0.5, 0, 0, stackCommunity and 216 or 148)
			local leftWidth = compact and width or width - 174
			local verticalBadges = badgeRow and leftWidth < 330
			local welcomeHeight = verticalBadges and 130 or 106
			if badgeRow then
				badgeRow.Size = UDim2.new(1, -28, 0, verticalBadges and 46 or 22)
				if badgeLayout then
					badgeLayout.FillDirection = verticalBadges and Enum.FillDirection.Vertical
						or Enum.FillDirection.Horizontal
				end
			end
			welcome.Position = UDim2.fromOffset(0, 0)
			welcome.Size = UDim2.new(1, compact and 0 or -174, 0, welcomeHeight)
			session.Position = UDim2.fromOffset(0, welcomeHeight + 10)
			session.Size = UDim2.new(1, compact and 0 or -174, 0, 130)
			local topHeight = welcomeHeight + 140
			if compact then
				performance.AnchorPoint = Vector2.zero
				performance.Position = UDim2.fromOffset(0, topHeight + 10)
				performance.Size = UDim2.new(1, 0, 0, 132)
				topHeight += 142
				ring.Position = UDim2.fromOffset(8, 11)
				ring.Size = UDim2.fromOffset(110, 110)
				performanceTitle.Position = UDim2.fromOffset(128, 20)
				performanceTitle.Size = UDim2.new(1, -142, 0, 24)
				performanceTitle.TextXAlignment = Enum.TextXAlignment.Center
				fpsCaption.Position = UDim2.fromOffset(128, 48)
				fpsCaption.Size = UDim2.new(1, -142, 0, 28)
				fpsCaption.TextWrapped = true
				pingRow.Position = UDim2.new(0.5, 57, 0, 99)
				pingRow.Size = UDim2.new(1, -142, 0, 22)
			else
				performance.AnchorPoint = Vector2.new(1, 0)
				performance.Position = UDim2.fromScale(1, 0)
				performance.Size = UDim2.fromOffset(164, topHeight)
				ring.Position = UDim2.new(0.5, -60, 0, 51)
				ring.Size = UDim2.fromOffset(120, 120)
				performanceTitle.Position = UDim2.fromOffset(10, 19)
				performanceTitle.Size = UDim2.new(1, -20, 0, 24)
				performanceTitle.TextXAlignment = Enum.TextXAlignment.Center
				fpsCaption.Position = UDim2.fromOffset(10, 182)
				fpsCaption.Size = UDim2.new(1, -20, 0, 20)
				fpsCaption.TextWrapped = false
				pingRow.Position = UDim2.new(0.5, 0, 0, topHeight - 29)
				pingRow.Size = UDim2.new(1, -20, 0, 22)
			end
			top.Size = UDim2.new(1, 0, 0, topHeight)
			actions.Size = UDim2.new(1, 0, 0, compact and 196 or 82)
			for index, definition in ipairs(definitions) do
				local control = tab._dashboardControls[definition.Id]
				control.Button.Position = compact and UDim2.fromOffset(0, (index - 1) * 68)
					or UDim2.new((index - 1) / 3, (index - 1) * 8 / 3, 0, 0)
				control.Button.Size = compact and UDim2.new(1, 0, 0, 60) or UDim2.new(1 / 3, -16 / 3, 0, 82)
				control.Icon.Position = compact and UDim2.new(0, 14, 0.5, 0) or UDim2.fromOffset(14, 14)
				control.Title.Position = UDim2.fromOffset(compact and 44 or 14, compact and 3 or 36)
				control.Title.Size = UDim2.new(1, compact and -56 or -28, 0, compact and 26 or 20)
				control.Description.Position = UDim2.fromOffset(compact and 44 or 14, compact and 32 or 58)
				control.Description.Size = UDim2.new(1, compact and -56 or -28, 0, compact and 24 or 18)
				control.Title.TextWrapped, control.Description.TextWrapped = compact, compact
				control.Title.TextTruncate = compact and Enum.TextTruncate.None or Enum.TextTruncate.AtEnd
				control.Description.TextTruncate = control.Title.TextTruncate
			end
		end
		local communityPending, nextCommunityRefresh = false, 0
		local function formatCount(value)
			if type(value) ~= "number" or value ~= value or value < 0 or value == math.huge then
				return "—"
			end
			local text = tostring(math.floor(value))
			return text:reverse():gsub("(%d%d%d)", "%1."):reverse():gsub("^%.", "")
		end

		local function refreshCommunity()
			if communityPending then
				return
			end
			if type(config.CommunityProvider) ~= "function" then
				memberCounts.Text = "Comunidade indisponível"
				return
			end
			communityPending = true
			nextCommunityRefresh = os.clock() + 180
			task.spawn(function()
				local success, data = pcall(config.CommunityProvider)
				communityPending = false
				if self._destroyed or not community.Parent then
					return
				end
				if not success or type(data) ~= "table" then
					data = { Status = "Dados da comunidade indisponíveis" }
				end
				if type(data.Name) == "string" and data.Name ~= "" then
					communityTitle.Text = data.Name
				end
				memberCounts.Text = type(data.Name) == "string"
						and data.Name ~= ""
						and formatCount(data.Online) .. " online   ·   " .. formatCount(data.Members) .. " membros"
					or data.Status
					or "Comunidade indisponível"
				if type(data.Image) == "string" and data.Image ~= "" then
					communityIcon.Image = data.Image
					placeholderIcon.Visible = false
				end
			end)
		end
		tab._refreshCommunity = refreshCommunity
		if self.Scale then
			table.insert(self._connections, self.Scale:GetPropertyChangedSignal("Scale"):Connect(layout))
		end
		local lastFPS, lastTheme
		local function paintGauge()
			local value = tonumber(fps.Text) or 0
			if value == lastFPS and lastTheme == nativeTheme then
				return
			end
			lastFPS, lastTheme = value, nativeTheme
			local filled = math.floor(math.clamp(value / 240, 0, 1) * #segments + 0.5)
			for index, segment in ipairs(segments) do
				segment.BackgroundColor3 = index <= filled and nativeTheme.Accent or nativeTheme.Stroke
			end
		end
		table.insert(self._connections, list:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout))
		table.insert(self._connections, fps:GetPropertyChangedSignal("Text"):Connect(paintGauge))
		local communityMotionTime, lastCommunityMotion = 0, 0
		local communityReducedMotion = false
		local function updateCommunityMotionPreference()
			local ok, reduced = pcall(function()
				return GuiService.ReducedMotionEnabled
			end)
			communityReducedMotion = ok and reduced == true
			if communityReducedMotion then
				communityGradient.Offset, communityGradient.Rotation = Vector2.zero, 18
			end
		end
		updateCommunityMotionPreference()
		local motionSignalOk, motionSignal = pcall(function()
			return GuiService:GetPropertyChangedSignal("ReducedMotionEnabled")
		end)
		if motionSignalOk then
			table.insert(self._connections, motionSignal:Connect(updateCommunityMotionPreference))
		end
		self:_listen("Render", function(delta)
			if self.Open and self.Gui.Enabled and self.CurrentTab == tab then
				local now = os.clock()
				local top = community.AbsolutePosition.Y
				local visible = top + community.AbsoluteSize.Y > list.AbsolutePosition.Y
					and top < list.AbsolutePosition.Y + list.AbsoluteSize.Y
				if visible and not communityReducedMotion then
					communityMotionTime += tonumber(delta) or 0
					if now - lastCommunityMotion >= 1 / 30 then
						lastCommunityMotion = now
						local phase = communityMotionTime * math.pi / 7
						communityGradient.Offset = Vector2.new(math.sin(phase) * 0.18, math.cos(phase) * 0.08)
						communityGradient.Rotation = 18 + math.sin(phase * 0.7) * 12
					end
				end
				paintGauge()
				if os.clock() >= nextCommunityRefresh then
					refreshCommunity()
				end
			end
		end)
		tab._dashboardLayout = layout
		layout()
		paintGauge()
		refreshCommunity()
	end

	function NativeWindow:_buildHome(homeConfig)
		local frameClass, listLayoutClass, dragAttribute, executorLabel = "Frame", "UIListLayout", "NoDrag", "Executor"
		local homeTab =
			self:Tab({ Name = homeConfig.Name or "Home", Desc = homeConfig.Desc, Icon = homeConfig.Icon or "house" })
		local homeList = homeTab.List
		local pages = homeConfig.Pages or homeConfig.Tabs
		local homePages = {}
		local pageButtons
		if type(pages) == "table" and #pages > 0 then
			pageButtons = createInstance(
				frameClass,
				{ Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 1, LayoutOrder = 1, Parent = homeList }
			)
			createInstance(listLayoutClass, {
				FillDirection = Enum.FillDirection.Horizontal,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 6),
				Parent = pageButtons,
			})
		end
		local greeting = homeConfig.Greeting
		if greeting == nil then
			local hour = tonumber(os.date("%H")) or 12
			local greetingPeriod = hour < 12 and "morning" or (hour < 18 and "afternoon" or "evening")
			greeting = "Good " .. greetingPeriod .. "."
		end
		local welcomeCard = createInstance(frameClass, {
			Size = UDim2.new(1, 0, 0, 58),
			BackgroundColor3 = nativeTheme.Surface2,
			BorderSizePixel = 0,
			LayoutOrder = 2,
			Parent = homeList,
		})
		welcomeCard:SetAttribute(dragAttribute, true)
		addCorner(welcomeCard)
		addStroke(welcomeCard)
		local playerAvatar = createInstance("ImageLabel", {
			Position = UDim2.fromOffset(12, 11),
			Size = UDim2.fromOffset(36, 36),
			BackgroundColor3 = nativeTheme.Surface,
			BorderSizePixel = 0,
			Parent = welcomeCard,
		})
		playerAvatar:SetAttribute("UIUnthemed", true)
		addCorner(playerAvatar, UDim.new(0, 8))
		addStroke(playerAvatar)
		task.spawn(function()
			local success, result = pcall(function()
				return Players:GetUserThumbnailAsync(
					localPlayer.UserId,
					Enum.ThumbnailType.HeadShot,
					Enum.ThumbnailSize.Size100x100
				)
			end)
			if self._destroyed or not playerAvatar.Parent then
				return
			end
			if success and type(result) == "string" and result ~= "" then
				playerAvatar.Image = result
			else
				local userId = tonumber(localPlayer.UserId)
				if userId and userId > 0 then
					playerAvatar.Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(userId) .. "&w=150&h=150"
				end
			end
		end)
		createLabel({
			Position = UDim2.fromOffset(58, 11),
			Size = UDim2.new(1, -72, 0, 18),
			Text = (homeConfig.Welcome or "Hello, ") .. localPlayer.DisplayName,
			TextSize = 15,
			Parent = welcomeCard,
		})
		createLabel({
			Position = UDim2.fromOffset(58, 30),
			Size = UDim2.new(1, -72, 0, 16),
			Text = greeting,
			TextSize = 13,
			FontFace = nativeFonts.Regular,
			TextColor3 = nativeTheme.Muted,
			Parent = welcomeCard,
		})
		if type(homeConfig.AccessProvider) == "function" then
			welcomeCard.Size = UDim2.new(1, 0, 0, 90)
			local badgeRow = createInstance("Frame", {
				Name = "AccessBadges",
				Position = UDim2.fromOffset(12, 58),
				Size = UDim2.new(1, -24, 0, 22),
				BackgroundTransparency = 1,
				Parent = welcomeCard,
			})
			createInstance("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 6),
				Parent = badgeRow,
			})
			local function createBadge(name, order)
				local badge = createInstance("Frame", {
					Name = name,
					Size = UDim2.fromOffset(0, 22),
					AutomaticSize = Enum.AutomaticSize.X,
					BackgroundColor3 = nativeTheme.Surface,
					BorderSizePixel = 0,
					LayoutOrder = order,
					Parent = badgeRow,
				})
				addCorner(badge, UDim.new(0, 6))
				addStroke(badge)
				addPadding(badge, 8, 8)
				return createLabel({
					Size = UDim2.new(0, 0, 1, 0),
					AutomaticSize = Enum.AutomaticSize.X,
					Text = "",
					TextSize = 11,
					TextColor3 = nativeTheme.Text,
					TextTruncate = Enum.TextTruncate.None,
					Parent = badge,
				})
			end
			local accessBadge = createBadge("AccessType", 1)
			local expirationBadge = createBadge("AccessExpiration", 2)
			local function refreshAccess()
				if self._destroyed or not expirationBadge.Parent then
					return
				end
				local success, metadata = pcall(homeConfig.AccessProvider)
				if not success or type(metadata) ~= "table" then
					metadata = {}
				end
				if metadata.Reason == "KEYLESS" then
					accessBadge.Text = "Sem chave"
					expirationBadge.Text = "Sem expiração"
					return
				end
				accessBadge.Text = metadata.Premium == true and "Premium" or "Gratuito"
				if metadata.Reason ~= "KEY_VALID" then
					accessBadge.Text = "Acesso indisponível"
					expirationBadge.Text = "Validade indisponível"
					return
				end
				local expiresAt = metadata.ExpiresAt
				if expiresAt == nil then
					expirationBadge.Text = "Permanente"
				elseif type(expiresAt) ~= "number" or expiresAt ~= expiresAt or math.abs(expiresAt) == math.huge then
					expirationBadge.Text = "Validade indisponível"
				else
					local remaining = math.max(0, math.floor(expiresAt - os.time()))
					local days = math.floor(remaining / 86400)
					local hours = math.floor(remaining % 86400 / 3600)
					local minutes = math.floor(remaining % 3600 / 60)
					local seconds = remaining % 60
					if remaining == 0 then
						expirationBadge.Text = "Expirado"
					elseif days > 0 then
						expirationBadge.Text = string.format("Expira em %dd %02dh", days, hours)
					elseif hours > 0 then
						expirationBadge.Text = string.format("Expira em %02dh %02dm", hours, minutes)
					else
						expirationBadge.Text = string.format("Expira em %02dm %02ds", minutes, seconds)
					end
				end
			end
			homeTab._accessBadges = { Access = accessBadge, Expiration = expirationBadge }
			homeTab._refreshAccess = refreshAccess
			refreshAccess()
		end
		local systemInfo = createInstance(frameClass, {
			Name = "SystemInfo",
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			LayoutOrder = 3,
			Parent = homeList,
		})
		createInstance(
			listLayoutClass,
			{ SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8), Parent = systemInfo }
		)
		if homeConfig.Sections ~= false then
			local systemHeader = createInstance(
				frameClass,
				{ Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, LayoutOrder = 1, Parent = systemInfo }
			)
			local systemTitle = createLabel({
				Position = UDim2.fromOffset(2, 6),
				Size = UDim2.new(0, 0, 0, 16),
				AutomaticSize = Enum.AutomaticSize.X,
				Text = uppercasePortuguese(homeConfig.SectionName or "System info"),
				TextSize = 12,
				TextColor3 = nativeTheme.Muted,
				TextTruncate = Enum.TextTruncate.None,
				Parent = systemHeader,
			})
			local headerDivider = createInstance(frameClass, {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, 0, 0, 14),
				Size = UDim2.new(1, -12, 0, 1),
				BackgroundColor3 = nativeTheme.Stroke,
				BorderSizePixel = 0,
				Parent = systemHeader,
			})
			local function resizeSystemHeader()
				headerDivider.Size = UDim2.new(1, -(systemTitle.AbsoluteSize.X + 14), 0, 1)
			end
			systemTitle:GetPropertyChangedSignal("AbsoluteSize"):Connect(resizeSystemHeader)
			task.defer(resizeSystemHeader)
		end
		local statsGrid = createInstance(frameClass, {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			LayoutOrder = 2,
			Parent = systemInfo,
		})
		createInstance("UIGridLayout", {
			CellSize = UDim2.new(0.5, -4, 0, 62),
			CellPadding = UDim2.fromOffset(8, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = statsGrid,
		})
		local statNames = homeConfig.Stats or { "FPS", "Ping", executorLabel, "Game", "Time" }
		local statCards = {}
		for index, statName in ipairs(statNames) do
			statCards[statName] = true
		end
		local statCount = 0
		local function addHomeStatistic(key, icon, title)
			if not statCards[key] then
				return nil
			end
			statCount += 1
			return createStatisticCard(statsGrid, statCount, icon, (homeConfig.Labels or {})[key] or title)
		end
		local fPSValueLabel = addHomeStatistic("FPS", "activity", "FPS")
		local pingValueLabel = addHomeStatistic("Ping", "wifi", "Ping")
		local executorStat = addHomeStatistic(executorLabel, "terminal", executorLabel)
		local gameValueLabel = addHomeStatistic("Game", "gamepad-2", "Game")
		local timeValueLabel = addHomeStatistic("Time", "clock", "Time of day")
		local playersValueLabel = addHomeStatistic("Players", "users", "Players")
		local uptimeValueLabel = addHomeStatistic("Uptime", "timer", "Session")
		if executorStat then
			local executor = detectExecutor()
			executorStat.Text = executor == "Unknown" and "Indisponível" or executor
		end
		if gameValueLabel then
			gameValueLabel.Text = "Carregando..."
			task.spawn(function()
				local name = detectGameName()
				if not self._destroyed and gameValueLabel.Parent then
					gameValueLabel.Text = name == "Unknown game" and "Jogo indisponível" or name
				end
			end)
		end
		local frames, elapsed = 0, 0
		local started = os.clock()
		local memoryLabel = addHomeStatistic("Memory", "cpu", (homeConfig.Labels or {}).Memory or "Luau memory")
		local function refresh()
			if self._destroyed or not homeTab.List.Parent or not homeTab._page.Parent then
				return
			end
			if homeTab._refreshAccess then
				homeTab._refreshAccess()
			end
			if fPSValueLabel then
				fPSValueLabel.Text = elapsed > 0 and tostring(math.floor(frames / elapsed + 0.5)) or "—"
			end
			if pingValueLabel then
				local success, ping = pcall(function()
					return localPlayer:GetNetworkPing()
				end)
				pingValueLabel.Text = success
						and type(ping) == "number"
						and tostring(math.floor(ping * 1000 + 0.5)) .. " ms"
					or "Indisponível"
			end
			if timeValueLabel then
				timeValueLabel.Text = os.date(homeConfig.TimeFormat or "%H:%M")
			end
			if playersValueLabel then
				playersValueLabel.Text = #Players:GetPlayers() .. " / " .. Players.MaxPlayers
			end
			if uptimeValueLabel then
				local seconds = math.floor(os.clock() - started)
				uptimeValueLabel.Text = string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
			end
			if memoryLabel then
				local success, kilobytes = pcall(gcinfo)
				memoryLabel.Text = success
						and type(kilobytes) == "number"
						and string.format("%.1f MB", kilobytes / 1024)
					or "Indisponível"
			end
		end
		homeTab._homeStatValues = {
			FPS = fPSValueLabel,
			Ping = pingValueLabel,
			Executor = executorStat,
			Game = gameValueLabel,
			Time = timeValueLabel,
			Players = playersValueLabel,
			Uptime = uptimeValueLabel,
			Memory = memoryLabel,
		}
		refresh()
		self:_listen("Render", function(delta)
			if self._destroyed or not homeTab.List.Parent or not homeTab._page.Parent then
				return
			end
			if not self.Open or not self.Gui.Enabled or self.CurrentTab ~= homeTab then
				frames, elapsed = 0, 0
				return
			end
			frames += 1
			elapsed += math.max(delta or 0, 0)
			if elapsed >= 1 then
				refresh()
				frames, elapsed = 0, 0
			end
		end)
		table.insert(homePages, {
			Title = homeConfig.SectionName or "Details",
			Icon = homeConfig.TabIcon or "layout-grid",
			Frame = systemInfo,
		})
		if pageButtons then
			for pageIndex, page in ipairs(pages) do
				local pageContent = createInstance(frameClass, {
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundTransparency = 1,
					Visible = false,
					LayoutOrder = 3,
					Parent = homeList,
				})
				createInstance(
					listLayoutClass,
					{ SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8), Parent = pageContent }
				)
				if type(page.Content) == "string" then
					local pageHeader = createInstance(frameClass, {
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						BackgroundColor3 = nativeTheme.Surface2,
						BorderSizePixel = 0,
						LayoutOrder = 1,
						Parent = pageContent,
					})
					pageHeader:SetAttribute(dragAttribute, true)
					addCorner(pageHeader)
					addStroke(pageHeader)
					addPadding(pageHeader, 14, 14, 12, 14)
					createLabel({
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						Text = page.Content,
						TextSize = 13,
						FontFace = nativeFonts.Regular,
						TextColor3 = nativeTheme.Muted,
						TextWrapped = true,
						TextTruncate = Enum.TextTruncate.None,
						TextYAlignment = Enum.TextYAlignment.Top,
						Parent = pageHeader,
					})
				end
				if type(page.Entries) == "table" then
					for entryIndex, entry in ipairs(page.Entries) do
						local entryCard = createInstance(frameClass, {
							Size = UDim2.new(1, 0, 0, 0),
							AutomaticSize = Enum.AutomaticSize.Y,
							BackgroundColor3 = nativeTheme.Surface2,
							BorderSizePixel = 0,
							LayoutOrder = entryIndex,
							Parent = pageContent,
						})
						entryCard:SetAttribute(dragAttribute, true)
						addCorner(entryCard)
						addStroke(entryCard)
						addPadding(entryCard, 14, 14, 12, 14)
						createInstance(
							listLayoutClass,
							{ SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4), Parent = entryCard }
						)
						local entryHeader = createInstance(frameClass, {
							Size = UDim2.new(1, 0, 0, 18),
							BackgroundTransparency = 1,
							LayoutOrder = 1,
							Parent = entryCard,
						})
						createLabel({
							Size = UDim2.new(1, -70, 1, 0),
							Text = entry.Title or entry.Version or "Update",
							TextSize = 14,
							Parent = entryHeader,
						})
						if entry.Date or entry.Tag then
							local entryBadge = createInstance(frameClass, {
								AnchorPoint = Vector2.new(1, 0.5),
								Position = UDim2.new(1, 0, 0.5, 0),
								Size = UDim2.fromOffset(0, 20),
								AutomaticSize = Enum.AutomaticSize.X,
								BackgroundColor3 = nativeTheme.Surface,
								BorderSizePixel = 0,
								Parent = entryHeader,
							})
							addCorner(entryBadge, UDim.new(0, 5))
							addStroke(entryBadge)
							addPadding(entryBadge, 8, 8)
							createLabel({
								Size = UDim2.new(0, 0, 1, 0),
								AutomaticSize = Enum.AutomaticSize.X,
								Text = entry.Tag or entry.Date,
								TextSize = 11,
								TextColor3 = nativeTheme.Muted,
								TextTruncate = Enum.TextTruncate.None,
								Parent = entryBadge,
							})
						end
						local entryContent = entry.Content or entry.Body
						if type(entry.Changes) == "table" then
							entryContent = "• " .. table.concat(entry.Changes, "\n• ")
						end
						if entryContent then
							createLabel({
								Size = UDim2.new(1, 0, 0, 0),
								AutomaticSize = Enum.AutomaticSize.Y,
								Text = entryContent,
								TextSize = 13,
								FontFace = nativeFonts.Regular,
								TextColor3 = nativeTheme.Muted,
								TextWrapped = true,
								TextTruncate = Enum.TextTruncate.None,
								TextYAlignment = Enum.TextYAlignment.Top,
								LayoutOrder = 2,
								Parent = entryCard,
							})
						end
					end
				end
				if type(page.Build) == "function" then
					invokeCallback(page.Build, pageContent)
					for index, child in ipairs(pageContent:GetChildren()) do
						if child:IsA("GuiObject") then
							child:SetAttribute(dragAttribute, true)
						end
					end
				end
				table.insert(
					homePages,
					{ Title = page.Name or page.Title or "Page", Icon = page.Icon, Frame = pageContent }
				)
			end
			local homeButtons = {}
			local function selectHomePage(pageIndex, force)
				local pageChanged = self._homeIndex ~= pageIndex
				self._homeIndex = pageIndex
				welcomeCard.Visible = pageIndex == 1
				if pageIndex == 1 and pageChanged and not force then
					revealHomeContent(welcomeCard)
				end
				for index, page in ipairs(homePages) do
					local isSelected = index == pageIndex
					local pageFrame = page.Frame
					pageFrame.Visible = isSelected
					if isSelected and pageChanged and not force then
						for childIndex, child in ipairs(pageFrame:GetChildren()) do
							if child:IsA("GuiObject") then
								revealHomeContent(child)
							end
						end
					end
					local pageButton = homeButtons[index]
					if pageButton then
						animate(pageButton.Frame, { BackgroundTransparency = isSelected and 0 or 1 }, 0.15)
						animate(pageButton.Stroke, { Transparency = isSelected and 0 or 1 }, 0.15)
						animate(
							pageButton.Label,
							{ TextColor3 = isSelected and nativeTheme.Text or nativeTheme.Muted },
							0.15
						)
						if pageButton.Icon then
							animate(
								pageButton.Icon,
								{ ImageColor3 = isSelected and nativeTheme.Accent or nativeTheme.Muted },
								0.15
							)
						end
					end
				end
			end
			for pageIndex, page in ipairs(homePages) do
				local pageButton = createInstance("TextButton", {
					Size = UDim2.fromOffset(0, 32),
					AutomaticSize = Enum.AutomaticSize.X,
					BackgroundColor3 = nativeTheme.Surface2,
					BackgroundTransparency = 1,
					Text = "",
					AutoButtonColor = false,
					LayoutOrder = pageIndex,
					Parent = pageButtons,
				})
				addCorner(pageButton, UDim.new(0, 7))
				local pageBorder = addStroke(pageButton, nativeTheme.Stroke, 1)
				addPadding(pageButton, 12, 12)
				local buttonIcon
				if page.Icon then
					buttonIcon = createInstance("ImageLabel", {
						AnchorPoint = Vector2.new(0, 0.5),
						Position = UDim2.new(0, 0, 0.5, 0),
						Size = UDim2.fromOffset(14, 14),
						BackgroundTransparency = 1,
						ImageColor3 = nativeTheme.Muted,
						ScaleType = Enum.ScaleType.Fit,
						Parent = pageButton,
					})
					applyIcon(buttonIcon, page.Icon)
				end
				local pageLabel = createLabel({
					Position = UDim2.fromOffset(buttonIcon and 20 or 0, 0),
					Size = UDim2.new(0, 0, 1, 0),
					AutomaticSize = Enum.AutomaticSize.X,
					Text = page.Title,
					TextSize = 13,
					TextColor3 = nativeTheme.Muted,
					TextTruncate = Enum.TextTruncate.None,
					Parent = pageButton,
				})
				homeButtons[pageIndex] =
					{ Frame = pageButton, Stroke = pageBorder, Label = pageLabel, Icon = buttonIcon }
				pageButton.MouseEnter:Connect(function()
					if self._homeIndex ~= pageIndex then
						animate(pageButton, { BackgroundTransparency = 0.4 }, 0.12)
						animate(pageBorder, { Transparency = 0.5 }, 0.12)
					end
				end)
				pageButton.MouseLeave:Connect(function()
					if self._homeIndex ~= pageIndex then
						animate(pageButton, { BackgroundTransparency = 1 }, 0.2)
						animate(pageBorder, { Transparency = 1 }, 0.2)
					end
				end)
				pageButton.MouseButton1Click:Connect(function()
					selectHomePage(pageIndex)
				end)
			end
			selectHomePage(1)
		end
		homeTab._order = 10
		self.Home = homeTab
		return homeTab
	end

	function NativeWindow:Tab(tabConfig, hidden)
		tabConfig = normalizeOptions(tabConfig, { Title = "Name", Description = "Desc" })
		if hidden ~= nil and tabConfig.Icon == nil then
			tabConfig.Icon = hidden
		end
		local tab = setmetatable(
			{ Name = tabConfig.Name or "Tab", Window = self, _order = 0, _iconThemed = tabConfig.IconThemed ~= false },
			NativeTab
		)
		local tabButton = createInstance("TextButton", {
			Size = UDim2.new(1, 0, 0, 38),
			BackgroundColor3 = nativeTheme.Surface2,
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
			LayoutOrder = #self.Tabs + 1,
			Parent = self.TabList,
		})
		addCorner(tabButton)
		local tabBorder = addStroke(tabButton, nativeTheme.Stroke, 1)
		tab._button = tabButton
		local hasIcon = tabConfig.Icon ~= nil
		if hasIcon then
			local tabIcon = createInstance("ImageLabel", {
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 12, 0.5, 0),
				Size = UDim2.fromOffset(16, 16),
				BackgroundTransparency = 1,
				ImageColor3 = tab._iconThemed and nativeTheme.Muted or Color3.new(1, 1, 1),
				ScaleType = Enum.ScaleType.Fit,
				Parent = tabButton,
			})
			applyIcon(tabIcon, tabConfig.Icon)
			tab._icon = tabIcon
		end
		tab._label = createLabel({
			Position = UDim2.fromOffset(hasIcon and 36 or 14, 0),
			Size = UDim2.new(1, -(hasIcon and 44 or 22), 1, 0),
			Text = tab.Name,
			TextColor3 = nativeTheme.Muted,
			Parent = tabButton,
		})
		local tabFrame = createInstance("Frame", {
			Name = tab.Name,
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Visible = false,
			Parent = self.Content,
		})
		tab._page = tabFrame
		tab._heading = createLabel({
			Position = UDim2.fromOffset(24, 20),
			Size = UDim2.new(1, -72, 0, 24),
			Text = tab.Name,
			TextSize = 22,
			Parent = tabFrame,
		})
		if tabConfig.Desc then
			tab._description = createLabel({
				Position = UDim2.fromOffset(24, 44),
				Size = UDim2.new(1, -72, 0, 16),
				Text = tabConfig.Desc,
				TextSize = 13,
				FontFace = nativeFonts.Regular,
				TextColor3 = nativeTheme.Muted,
				Parent = tabFrame,
			})
		end
		local headerHeight = tabConfig.Desc and 70 or 58
		tab._headerHeight = headerHeight
		local tabScroll = createInstance("ScrollingFrame", {
			Position = UDim2.fromOffset(0, headerHeight),
			Size = UDim2.new(1, 0, 1, -headerHeight),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 2,
			ScrollBarImageColor3 = nativeTheme.Accent,
			ScrollBarImageTransparency = 0.5,
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			CanvasSize = UDim2.new(),
			Parent = tabFrame,
		})
		addPadding(tabScroll, 24, 24, 2, 24)
		createInstance(
			"UIListLayout",
			{ SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8), Parent = tabScroll }
		)
		tab.List = tabScroll
		local emptyState, childCount =
			createEmptyPage(tabFrame, tabConfig.Icon or "layout-grid", tabConfig.EmptyText or "Nothing here yet"), 0
		tabScroll.ChildAdded:Connect(function(child)
			if child:IsA("GuiObject") then
				childCount += 1
				emptyState.Visible = false
			end
		end)
		tabScroll.ChildRemoved:Connect(function(child)
			if child:IsA("GuiObject") then
				childCount = math.max(childCount - 1, 0)
				emptyState.Visible = childCount <= 0
			end
		end)
		emptyState.Visible = true
		tabButton.MouseEnter:Connect(function()
			if self.CurrentTab ~= tab then
				animate(tabButton, { BackgroundTransparency = 0.4 }, 0.12)
				animate(tabBorder, { Transparency = 0.5 }, 0.12)
			end
		end)
		tabButton.MouseLeave:Connect(function()
			if self.CurrentTab ~= tab then
				animate(tabButton, { BackgroundTransparency = 1 }, 0.2)
				animate(tabBorder, { Transparency = 1 }, 0.2)
			end
		end)
		tabButton.MouseButton1Click:Connect(function()
			self:SelectTab(tab)
		end)
		tab._stroke = tabBorder
		if not self._introDone then
			tabButton.Visible = false
		end
		table.insert(self.Tabs, tab)
		self:_layoutResponsive()
		if #self.Tabs == 1 then
			task.defer(function()
				self:SelectTab(tab)
			end)
		end
		return tab
	end
	NativeWindow.CreateTab = NativeWindow.Tab
	function NativeWindow:Dialog(dialogConfig)
		local useDefaultButtonStyle = NativeLibrary.ThemeName == "Mono"
		local textTransparencyProperty = "TextTransparency"
		dialogConfig = normalizeOptions(dialogConfig, { Text = "Content", Message = "Content" })
		if self._dialog then
			self._dialog.Close()
		end
		local padding = 18
		local dialogBackdrop = createInstance("TextButton", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
			ZIndex = 40,
			Parent = self.Body,
		})
		local dialogBody = createInstance("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 10),
			Size = UDim2.fromOffset(300, 120),
			BackgroundColor3 = nativeTheme.Background,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 41,
			Parent = dialogBackdrop,
		})
		addCorner(dialogBody, UDim.new(0, 16))
		local dialogBorder = addStroke(dialogBody, nativeTheme.Stroke, 1)
		local dialogScale = createInstance("UIScale", { Scale = 0.94, Parent = dialogBody })
		local dialogElements, iconWidth = {}, 0
		if dialogConfig.Icon then
			local iconContainer, iconImage =
				createIcon(dialogBody, dialogConfig.Icon, nativeTheme.Accent, UDim2.new(0, padding, 0, padding + 9))
			iconImage.ImageTransparency = 1
			iconContainer.ZIndex = 42
			iconImage.ZIndex = 42
			table.insert(dialogElements, { iconImage, "ImageTransparency", 0 })
			iconWidth = 24
		end
		local dialogTitle = createLabel({
			Position = UDim2.fromOffset(padding + iconWidth, padding),
			Size = UDim2.new(1, -(padding * 2 + iconWidth), 0, 18),
			Text = dialogConfig.Title or "Are you sure?",
			TextSize = 15,
			TextTransparency = 1,
			ZIndex = 42,
			Parent = dialogBody,
		})
		table.insert(dialogElements, { dialogTitle, textTransparencyProperty, 0 })
		local descriptionHeight = 0
		if dialogConfig.Content then
			local dialogContent = createLabel({
				Position = UDim2.fromOffset(padding, padding + 24),
				Size = UDim2.new(1, -padding * 2, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Text = dialogConfig.Content,
				TextSize = 13,
				FontFace = nativeFonts.Regular,
				TextColor3 = nativeTheme.Muted,
				TextWrapped = true,
				TextTransparency = 1,
				TextTruncate = Enum.TextTruncate.None,
				TextYAlignment = Enum.TextYAlignment.Top,
				ZIndex = 42,
				Parent = dialogBody,
			})
			table.insert(dialogElements, { dialogContent, textTransparencyProperty, 0 })
			descriptionHeight = math.max(dialogContent.TextBounds.Y, 16) + 6
			dialogContent:GetPropertyChangedSignal("TextBounds"):Connect(function()
				local contentHeight = math.max(dialogContent.TextBounds.Y, 16) + 6
				if contentHeight ~= descriptionHeight then
					descriptionHeight = contentHeight
					dialogBody.Size = UDim2.fromOffset(300, padding + 24 + descriptionHeight + 12 + 34 + padding)
					local buttonRow = dialogBody:FindFirstChild("ButtonRow")
					if buttonRow then
						buttonRow.Position = UDim2.fromOffset(padding, padding + 24 + descriptionHeight + 12)
					end
				end
			end)
		end
		local buttonRow = createInstance("Frame", {
			Name = "ButtonRow",
			Position = UDim2.fromOffset(padding, padding + 24 + descriptionHeight + 12),
			Size = UDim2.new(1, -padding * 2, 0, 34),
			BackgroundTransparency = 1,
			ZIndex = 42,
			Parent = dialogBody,
		})
		createInstance("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 8),
			Parent = buttonRow,
		})
		dialogBody.Size = UDim2.fromOffset(300, padding + 24 + descriptionHeight + 12 + 34 + padding)
		local dialogButtons, dialogClosed = {}, false
		function dialogButtons.Close()
			if dialogClosed then
				return
			end
			dialogClosed = true
			if self._dialog == dialogButtons then
				self._dialog = nil
			end
			animate(dialogBackdrop, { BackgroundTransparency = 1 }, 0.18)
			animate(
				dialogBody,
				{ BackgroundTransparency = 1, Position = UDim2.new(0.5, 0, 0.5, 8) },
				0.18,
				Enum.EasingStyle.Quint
			)
			animate(dialogScale, { Scale = 0.96 }, 0.18, Enum.EasingStyle.Quint)
			animate(dialogBorder, { Transparency = 1 }, 0.12)
			for index, element in ipairs(dialogElements) do
				animate(element[1], { [element[2]] = 1 }, 0.12)
			end
			task.delay(0.2, function()
				dialogBackdrop:Destroy()
			end)
		end
		for buttonIndex, buttonConfig in ipairs(dialogConfig.Buttons or {}) do
			local isPrimary = buttonConfig.Variant == "Primary" and not useDefaultButtonStyle
			local dialogButton = createInstance("TextButton", {
				Size = UDim2.fromOffset(0, 34),
				AutomaticSize = Enum.AutomaticSize.X,
				BackgroundColor3 = isPrimary and nativeTheme.Accent or nativeTheme.Surface2,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Text = "",
				AutoButtonColor = false,
				ClipsDescendants = true,
				LayoutOrder = buttonIndex,
				ZIndex = 43,
				Parent = buttonRow,
			})
			addCorner(dialogButton, UDim.new(0, 7))
			local buttonBorder = addStroke(dialogButton, isPrimary and nativeTheme.Accent or nativeTheme.Stroke, 1)
			addPadding(dialogButton, 14, 14)
			local buttonLabel = createLabel({
				Size = UDim2.new(0, 0, 1, 0),
				AutomaticSize = Enum.AutomaticSize.X,
				Text = buttonConfig.Title or buttonConfig.Name or "OK",
				TextSize = 13,
				TextColor3 = isPrimary and nativeTheme.AccentDark or nativeTheme.Text,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextTransparency = 1,
				ZIndex = 44,
				Parent = dialogButton,
			})
			local shineTransparency = isPrimary and 0.12 or 0
			local hoverTransparency = isPrimary and 0.4 or 0
			table.insert(dialogElements, { dialogButton, "BackgroundTransparency", shineTransparency })
			table.insert(dialogElements, { buttonBorder, "Transparency", hoverTransparency })
			table.insert(dialogElements, { buttonLabel, textTransparencyProperty, 0 })
			dialogButton.MouseEnter:Connect(function()
				if dialogClosed then
					return
				end
				if isPrimary then
					animate(dialogButton, { BackgroundTransparency = 0 }, 0.12)
					animate(buttonBorder, { Transparency = 0 }, 0.12)
				else
					animate(buttonBorder, { Color = nativeTheme.StrokeHover }, 0.12)
				end
			end)
			dialogButton.MouseLeave:Connect(function()
				if dialogClosed then
					return
				end
				if isPrimary then
					animate(dialogButton, { BackgroundTransparency = shineTransparency }, 0.2)
					animate(buttonBorder, { Transparency = hoverTransparency }, 0.2)
				else
					animate(buttonBorder, { Color = nativeTheme.Stroke }, 0.2)
				end
			end)
			dialogButton.MouseButton1Click:Connect(function()
				dialogButtons.Close()
				invokeCallback(buttonConfig.Callback)
			end)
		end
		if dialogConfig.CloseOnBackdrop ~= false then
			dialogBackdrop.MouseButton1Click:Connect(function()
				dialogButtons.Close()
				invokeCallback(dialogConfig.OnCancel)
			end)
		end
		self._dialog = dialogButtons
		animate(dialogBackdrop, { BackgroundTransparency = 0.45 }, 0.25)
		animate(
			dialogBody,
			{ BackgroundTransparency = 0, Position = UDim2.fromScale(0.5, 0.5) },
			0.3,
			Enum.EasingStyle.Quint
		)
		animate(dialogBorder, { Transparency = 0 }, 0.25)
		animate(dialogScale, { Scale = 1 }, 0.4, Enum.EasingStyle.Back)
		for index, element in ipairs(dialogElements) do
			animate(element[1], { [element[2]] = element[3] }, 0.25)
		end
		return dialogButtons
	end

	function NativeWindow:Confirm(dialogConfig)
		dialogConfig = normalizeOptions(dialogConfig, { Text = "Content", Message = "Content" })
		return self:Dialog({
			Title = dialogConfig.Title or "Are you sure?",
			Content = dialogConfig.Content,
			Icon = dialogConfig.Icon,
			OnCancel = dialogConfig.OnCancel,
			Buttons = {
				{ Title = dialogConfig.CancelText or "Cancel", Callback = dialogConfig.OnCancel },
				{
					Title = dialogConfig.ConfirmText or "Confirm",
					Variant = "Primary",
					Callback = dialogConfig.Callback,
				},
			},
		})
	end

	function NativeWindow:_listen(phase, callback, control)
		local listeners = self._inputListeners[phase]
		table.insert(listeners, callback)
		local function disconnectListener()
			for index, listener in ipairs(listeners) do
				if listener == callback then
					table.remove(listeners, index)
					break
				end
			end
		end
		if control then
			control._listeners = control._listeners or {}
			table.insert(control._listeners, disconnectListener)
		end
		return disconnectListener
	end

	function NativeWindow:_indicatorY(tab)
		local tabList = self.TabList
		local windowScale = self.Scale.Scale
		return (tab._button.AbsolutePosition.Y - tabList.AbsolutePosition.Y + tab._button.AbsoluteSize.Y / 2)
				/ windowScale
			+ tabList.Position.Y.Offset
	end

	function NativeWindow:_placeIndicator(tab)
		local indicator = self.Indicator
		local indicatorY = self:_indicatorY(tab)
		if not indicator.Visible then
			indicator.Visible = true
			indicator.Position = UDim2.fromOffset(6, indicatorY)
			indicator.Size = UDim2.fromOffset(3, 0)
		end
		animate(
			indicator,
			{ Position = UDim2.fromOffset(6, indicatorY), Size = UDim2.fromOffset(3, 18) },
			0.35,
			Enum.EasingStyle.Back
		)
	end

	function NativeWindow:SelectTab(tab)
		if self.CurrentTab == tab then
			return
		end
		local currentTab = self.CurrentTab
		self.CurrentTab = tab
		self:_settleTransition()
		local transitionGeneration = (self._transitionGeneration or 0) + 1
		self._transitionGeneration = transitionGeneration
		if currentTab then
			animate(currentTab._button, { BackgroundTransparency = 1 }, 0.2)
			animate(currentTab._stroke, { Transparency = 1 }, 0.2)
			animate(currentTab._label, { TextColor3 = nativeTheme.Muted }, 0.2)
			if currentTab._icon and currentTab._iconThemed then
				animate(currentTab._icon, { ImageColor3 = nativeTheme.Muted }, 0.2)
			end
			local _outLayer = self._outLayer
			currentTab._page.Parent = _outLayer
			self._outPage = currentTab._page
			_outLayer.GroupTransparency = 0
			_outLayer.Position = UDim2.fromOffset(0, 0)
			_outLayer.Visible = true
			animate(_outLayer, { GroupTransparency = 1, Position = UDim2.fromOffset(0, -10) }, 0.18)
			task.delay(0.18, function()
				if self._transitionGeneration == transitionGeneration then
					self:_settleOut()
				end
			end)
		end
		animate(tab._button, { BackgroundTransparency = 0 }, 0.2)
		animate(tab._stroke, { Transparency = 0 }, 0.2)
		animate(tab._label, { TextColor3 = nativeTheme.Text }, 0.2)
		if tab._icon and tab._iconThemed then
			animate(tab._icon, { ImageColor3 = nativeTheme.Accent }, 0.2)
		end
		self:_placeIndicator(tab)
		local _page = tab._page
		_page.Position = UDim2.fromOffset(0, 0)
		_page.Visible = true
		_page.Parent = self._inLayer
		self._inPage = _page
		revealPage(self._inLayer)
		task.delay(0.32, function()
			if self._transitionGeneration == transitionGeneration then
				self:_settleIn()
			end
		end)
	end

	function NativeWindow:_settleOut()
		local _outPage = self._outPage
		if _outPage then
			_outPage.Parent = self.Content
			_outPage.Visible = false
			self._outPage = nil
		end
		self._outLayer.Visible = false
	end

	function NativeWindow:_settleIn()
		local _inPage = self._inPage
		if _inPage then
			_inPage.Parent = self.Content
			_inPage.Position = UDim2.fromOffset(0, 0)
			self._inPage = nil
		end
		self._inLayer.Visible = false
	end

	function NativeWindow:_settleTransition()
		self:_settleOut()
		self:_settleIn()
	end

	function NativeWindow:Toggle(open)
		if not self._introDone then
			return
		end
		if open == nil then
			open = not self.Open
		end
		if open == self.Open then
			return
		end
		self.Open = open
		if open then
			self.Root.Visible = true
			animate(self.Scale, { Scale = self._fitScale or 1 }, 0.4, Enum.EasingStyle.Back)
			animate(self.Body, { GroupTransparency = 0 }, 0.25)
			animate(self.BodyStroke, { Transparency = 0 }, 0.25)
			animate(self.Shadow, { ImageTransparency = 0.6 }, 0.3)
		else
			animate(self.Scale, { Scale = (self._fitScale or 1) * 0.94 }, 0.2, Enum.EasingStyle.Quint)
			animate(self.Body, { GroupTransparency = 1 }, 0.16)
			animate(self.BodyStroke, { Transparency = 1 }, 0.12)
			animate(self.Shadow, { ImageTransparency = 1 }, 0.16)
			task.delay(0.2, function()
				if not self.Open then
					self.Root.Visible = false
				end
			end)
		end
	end

	function NativeWindow:SetKeepOnScreen(enabled)
		self.KeepOnScreen = enabled ~= false
		if self.KeepOnScreen then
			self:_clampToScreen()
		end
	end

	function NativeWindow:SetKeybind(keyCode)
		self.Keybind = keyCode
		self._keyChipLabel.Text = formatKeyName(keyCode)
	end

	function NativeWindow:Notify(notificationConfig)
		local frameClass = "Frame"
		notificationConfig =
			normalizeOptions(notificationConfig, { Text = "Content", Message = "Content", Image = "Icon" })
		if self._destroyed or self._notifyLimit == 0 then
			return { Dismiss = function() end }
		end
		local duration = tonumber(notificationConfig.Duration) or 4
		if duration ~= duration or duration == math.huge or duration == -math.huge then
			duration = 4
		end
		duration = math.max(0.1, duration)
		while #self._toasts >= self._notifyLimit do
			self._toasts[1](true)
		end
		local height = notificationConfig.Content and NOTIFICATION_HEIGHT or 48
		local accentColor = notificationColors[notificationConfig.Type] or nativeTheme.Text
		self._notifyOrder += 1
		local notificationSlot = createInstance(frameClass, {
			Size = UDim2.new(1, 0, 0, 0),
			BackgroundTransparency = 1,
			LayoutOrder = self._notifyOrder,
			Parent = self.NotifyHolder,
		})
		local notificationRoot = createInstance(frameClass, {
			Position = UDim2.fromOffset(320, 0),
			Size = UDim2.new(1, 0, 0, height),
			BackgroundTransparency = 1,
			Parent = notificationSlot,
		})
		local notificationShadow = createInstance("ImageLabel", {
			Position = UDim2.fromOffset(-20, -20),
			Size = UDim2.new(1, 40, 1, 40),
			BackgroundTransparency = 1,
			Image = nativeAssets.Shadow,
			ImageColor3 = Color3.new(0, 0, 0),
			ImageTransparency = 1,
			ScaleType = Enum.ScaleType.Slice,
			SliceCenter = Rect.new(49, 49, 450, 450),
			ZIndex = 0,
			Parent = notificationRoot,
		})
		local notificationBody = createInstance("CanvasGroup", {
			Size = UDim2.new(1, 0, 0, height),
			BackgroundColor3 = nativeTheme.Background,
			BorderSizePixel = 0,
			GroupTransparency = 1,
			Parent = notificationRoot,
		})
		addCorner(notificationBody, UDim.new(0, 10))
		addStroke(notificationBody, nativeTheme.Stroke)
		addEdgeHighlight(notificationBody)
		addGlow(notificationBody, UDim2.fromOffset(200, 90), UDim2.new(1, -10, 0, -10), 0.9, 90)
		local notificationHeader = createInstance(frameClass, {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Parent = notificationBody,
		})
		addPadding(notificationHeader, 10, 10, 10, 18)
		local iconWidth = 0
		if notificationConfig.Icon then
			createIcon(
				notificationHeader,
				notificationConfig.Icon,
				accentColor == nativeTheme.Text and nativeTheme.Accent or accentColor,
				UDim2.new(0, 0, 0, 8)
			)
			iconWidth = 22
		end
		createLabel({
			Position = UDim2.fromOffset(iconWidth, 0),
			Size = UDim2.new(1, -32 - iconWidth, 0, 16),
			Text = notificationConfig.Title or "Notification",
			TextSize = 13,
			TextColor3 = accentColor,
			Parent = notificationHeader,
		})
		local dismissButton = createInstance("TextButton", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 4, 0, -8),
			Size = UDim2.fromOffset(32, 32),
			BackgroundTransparency = 1,
			Text = "×",
			TextColor3 = nativeTheme.Muted,
			TextSize = 22,
			FontFace = nativeFonts.Bold,
			AutoButtonColor = false,
			Parent = notificationHeader,
		})
		dismissButton.MouseEnter:Connect(function()
			animate(dismissButton, { TextColor3 = nativeTheme.Text }, 0.15)
		end)
		dismissButton.MouseLeave:Connect(function()
			animate(dismissButton, { TextColor3 = nativeTheme.Muted }, 0.2)
		end)
		local contentLabel
		if notificationConfig.Content then
			contentLabel = createLabel({
				Position = UDim2.fromOffset(iconWidth, 20),
				Size = UDim2.new(1, -iconWidth, 0, 42),
				Text = notificationConfig.Content,
				TextSize = 12,
				FontFace = nativeFonts.Regular,
				TextColor3 = nativeTheme.Muted,
				TextWrapped = true,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextYAlignment = Enum.TextYAlignment.Top,
				Parent = notificationHeader,
			})
		end
		local progressTrack = createInstance(frameClass, {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 10, 1, -7),
			Size = UDim2.new(1, -20, 0, 2),
			BackgroundColor3 = nativeTheme.Surface3,
			BorderSizePixel = 0,
			Parent = notificationBody,
		})
		addCorner(progressTrack, UDim.new(1, 0))
		local progressFill = createInstance(frameClass, {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = nativeTheme.Accent,
			BorderSizePixel = 0,
			Parent = progressTrack,
		})
		addCorner(progressFill, UDim.new(1, 0))
		local dismissed = false
		local expiryThread
		local dismissNotification
		local function removeNotification()
			dismissed = true
			if expiryThread and coroutine.status(expiryThread) == "suspended" then
				task.cancel(expiryThread)
			end
			expiryThread = nil
			for index, notification in ipairs(self._toasts) do
				if notification == dismissNotification then
					table.remove(self._toasts, index)
					break
				end
			end
			if notificationSlot.Parent then
				notificationSlot.Visible = false
				notificationSlot:Destroy()
			end
		end
		dismissNotification = function(immediate)
			if immediate == true then
				removeNotification()
				return
			end
			if dismissed then
				return
			end
			dismissed = true
			if self._destroyed or not notificationSlot.Parent then
				removeNotification()
				return
			end
			animate(notificationRoot, { Position = UDim2.fromOffset(260, 0) }, 0.2, Enum.EasingStyle.Quint)
			animate(notificationBody, { GroupTransparency = 1 }, 0.15)
			animate(notificationShadow, { ImageTransparency = 1 }, 0.15)
			task.delay(0.2, function()
				if notificationSlot.Parent then
					notificationSlot.ClipsDescendants = true
					animate(notificationSlot, { Size = UDim2.new(1, 0, 0, 0) }, 0.15, Enum.EasingStyle.Quint)
				end
				task.delay(0.15, removeNotification)
			end)
		end
		local function resizeNotification()
			if dismissed or not notificationSlot.Parent then
				return
			end
			height = contentLabel and 50 + math.clamp(contentLabel.TextBounds.Y, 14, 42) or 48
			notificationRoot.Size = UDim2.new(1, 0, 0, height)
			notificationBody.Size = UDim2.new(1, 0, 0, height)
			animate(notificationSlot, { Size = UDim2.new(1, 0, 0, height) }, 0.2, Enum.EasingStyle.Quint)
		end
		if contentLabel then
			contentLabel:GetPropertyChangedSignal("TextBounds"):Connect(resizeNotification)
		end
		table.insert(self._toasts, dismissNotification)
		task.defer(function()
			if not dismissed and notificationSlot.Parent then
				resizeNotification()
			end
		end)
		animate(notificationRoot, { Position = UDim2.fromOffset(0, 0) }, 0.25, Enum.EasingStyle.Quint)
		animate(notificationBody, { GroupTransparency = 0 }, 0.2)
		animate(notificationShadow, { ImageTransparency = 0.6 }, 0.2)
		animate(progressFill, { Size = UDim2.fromScale(0, 1) }, duration, Enum.EasingStyle.Linear)
		expiryThread = task.delay(duration, dismissNotification)
		dismissButton.MouseButton1Click:Connect(dismissNotification)
		return { Dismiss = dismissNotification }
	end

	function NativeWindow:Destroy()
		if self._destroyed then
			return
		end
		self._destroyed = true
		while #self._toasts > 0 do
			self._toasts[1](true)
		end
		for index, window in ipairs(NativeLibrary.Windows) do
			if window == self then
				table.remove(NativeLibrary.Windows, index)
				break
			end
		end
		for index, connection in ipairs(self._connections) do
			connection:Disconnect()
		end
		self._connections = {}
		animate(self.Scale, { Scale = 0.9 }, 0.2)
		animate(self.Body, { GroupTransparency = 1 }, 0.2)
		animate(self.BodyStroke, { Transparency = 1 }, 0.12)
		animate(self.Shadow, { ImageTransparency = 1 }, 0.2)
		task.delay(0.22, function()
			self.Gui:Destroy()
		end)
	end
	NativeLibrary.UIBridge = { ResolveIcon = resolveIcon }
	return NativeLibrary
end)()
local ThemeFactory = (function()
	return function()
		return {
			["Default"] = {
				Name = "Default",
				Warning = Color3.fromRGB(240, 176, 108),
				Success = Color3.fromRGB(150, 220, 170),
				Error = Color3.fromRGB(240, 120, 120),
				Background = Color3.fromRGB(20, 16, 20),
				Surface = Color3.fromRGB(24, 19, 24),
				Surface2 = Color3.fromRGB(28, 22, 28),
				Surface3 = Color3.fromRGB(42, 36, 43),
				Stroke = Color3.fromRGB(40, 32, 41),
				StrokeHover = Color3.fromRGB(88, 70, 90),
				Accent = Color3.fromRGB(235, 199, 246),
				AccentDark = Color3.fromRGB(24, 18, 26),
				Text = Color3.fromRGB(233, 229, 234),
				Muted = Color3.fromRGB(138, 127, 139),
				Glow = Color3.fromRGB(226, 218, 230),
			},
			["Midnight"] = {
				Name = "Midnight",
				Warning = Color3.fromRGB(240, 176, 108),
				Success = Color3.fromRGB(150, 220, 170),
				Error = Color3.fromRGB(240, 120, 120),
				Background = Color3.fromRGB(14, 16, 22),
				Surface = Color3.fromRGB(18, 21, 28),
				Surface2 = Color3.fromRGB(22, 25, 34),
				Surface3 = Color3.fromRGB(36, 41, 54),
				Stroke = Color3.fromRGB(32, 36, 48),
				StrokeHover = Color3.fromRGB(70, 80, 104),
				Accent = Color3.fromRGB(150, 180, 255),
				AccentDark = Color3.fromRGB(12, 16, 28),
				Text = Color3.fromRGB(226, 230, 240),
				Muted = Color3.fromRGB(122, 131, 153),
				Glow = Color3.fromRGB(210, 220, 240),
			},
			["Moss"] = {
				Name = "Moss",
				Warning = Color3.fromRGB(240, 176, 108),
				Success = Color3.fromRGB(150, 220, 170),
				Error = Color3.fromRGB(240, 120, 120),
				Background = Color3.fromRGB(15, 18, 15),
				Surface = Color3.fromRGB(19, 23, 19),
				Surface2 = Color3.fromRGB(23, 28, 23),
				Surface3 = Color3.fromRGB(37, 44, 37),
				Stroke = Color3.fromRGB(33, 40, 33),
				StrokeHover = Color3.fromRGB(72, 88, 72),
				Accent = Color3.fromRGB(176, 222, 170),
				AccentDark = Color3.fromRGB(14, 22, 14),
				Text = Color3.fromRGB(228, 234, 227),
				Muted = Color3.fromRGB(121, 136, 119),
				Glow = Color3.fromRGB(214, 230, 212),
			},
			["Ember"] = {
				Name = "Ember",
				Warning = Color3.fromRGB(240, 176, 108),
				Success = Color3.fromRGB(150, 220, 170),
				Error = Color3.fromRGB(240, 120, 120),
				Background = Color3.fromRGB(20, 16, 13),
				Surface = Color3.fromRGB(25, 20, 16),
				Surface2 = Color3.fromRGB(30, 24, 19),
				Surface3 = Color3.fromRGB(46, 37, 30),
				Stroke = Color3.fromRGB(42, 34, 27),
				StrokeHover = Color3.fromRGB(96, 76, 58),
				Accent = Color3.fromRGB(255, 190, 140),
				AccentDark = Color3.fromRGB(28, 18, 10),
				Text = Color3.fromRGB(240, 232, 226),
				Muted = Color3.fromRGB(146, 129, 113),
				Glow = Color3.fromRGB(240, 222, 208),
			},
			["Rose"] = {
				Name = "Rose",
				Warning = Color3.fromRGB(240, 176, 108),
				Success = Color3.fromRGB(150, 220, 170),
				Error = Color3.fromRGB(240, 120, 120),
				Background = Color3.fromRGB(21, 14, 17),
				Surface = Color3.fromRGB(26, 18, 21),
				Surface2 = Color3.fromRGB(31, 21, 25),
				Surface3 = Color3.fromRGB(48, 34, 40),
				Stroke = Color3.fromRGB(44, 30, 36),
				StrokeHover = Color3.fromRGB(100, 66, 80),
				Accent = Color3.fromRGB(255, 170, 195),
				AccentDark = Color3.fromRGB(30, 12, 18),
				Text = Color3.fromRGB(240, 228, 232),
				Muted = Color3.fromRGB(149, 124, 133),
				Glow = Color3.fromRGB(240, 214, 222),
			},
			["Mono"] = {
				Name = "Mono",
				Warning = Color3.fromRGB(240, 176, 108),
				Success = Color3.fromRGB(150, 220, 170),
				Error = Color3.fromRGB(240, 120, 120),
				Background = Color3.fromRGB(16, 16, 17),
				Surface = Color3.fromRGB(20, 20, 21),
				Surface2 = Color3.fromRGB(24, 24, 26),
				Surface3 = Color3.fromRGB(40, 40, 43),
				Stroke = Color3.fromRGB(36, 36, 39),
				StrokeHover = Color3.fromRGB(80, 80, 86),
				Accent = Color3.fromRGB(230, 230, 235),
				AccentDark = Color3.fromRGB(18, 18, 20),
				Text = Color3.fromRGB(232, 232, 236),
				Muted = Color3.fromRGB(130, 130, 136),
				Glow = Color3.fromRGB(220, 220, 226),
			},
		}
	end
end)()
local AdapterFactory = (function()
	return function(UIEngine, ThemeFactory, Palette, Runtime)
		local Players = Runtime.GetService("Players")
		local HttpService = Runtime.GetService("HttpService")
		local TweenService = Runtime.GetService("TweenService")
		local UserInputService = Runtime.GetService("UserInputService")
		local parent, parentSource = Runtime.GetUIParent()
		local Bridge = assert(
			UIEngine.UIBridge,
			"\077\105\099\104\105\103\117\110\032\098\114\105\100\103\101\032\105\115\032\109\105\115\115\105\110\103"
		)
		local Library = {
			["\065\105\114\102\108\111\119"] = UIEngine,
			Palette = Palette,
			Themes = {},
			Theme = nil,
			TransparencyValue = 0.35,
			_controls = {},
			_connections = {},
			_destroyed = false,
			_parent = parent,
			ParentSource = parentSource,
		}
		local ControlMethods = {}
		local ContainerMethods = {}
		local WindowMethods = {}
		local function connect(signal, callback)
			local connection = signal:Connect(callback)
			Library._connections[connection] = true
			return connection
		end

		local function disconnect(connection)
			if connection then
				Library._connections[connection] = nil
				connection:Disconnect()
			end
		end

		local function new(className, properties, children)
			local object = Instance.new(className)
			for key, value in pairs(properties or {}) do
				if key ~= "Parent" and key ~= "ThemeTag" then
					object[key] = value
				end
			end
			for _, child in ipairs(children or {}) do
				child.Parent = object
			end
			object.Parent = properties and properties.Parent or nil
			return object
		end

		local function call(callback, ...)
			if type(callback) ~= "function" then
				return
			end
			local success, result = pcall(callback, ...)
			if not success then
			end
			return result
		end

		local function color(value, fallback)
			if typeof(value) == "Color3" then
				return value
			end
			if typeof(value) == "ColorSequence" then
				return value.Keypoints[1].Value
			end
			if type(value) == "table" and value.Color then
				return color(value.Color, fallback)
			end
			return fallback
		end

		local function setIcon(image, value, tint)
			if value == nil or value == "" then
				image.Image = ""
				return
			end
			local asset, offset, size
			if type(value) == "string" and value:match("^rbxthumb://") then
				asset = value
			else
				asset, offset, size = Bridge.ResolveIcon(value)
			end
			image.Image = asset or ""
			image.ImageRectOffset = offset or Vector2.zero
			image.ImageRectSize = size or Vector2.zero
			image.ImageColor3 = tint or UIEngine.Theme.Accent
		end

		local function textLabels(frame)
			local labels = {}
			for _, object in ipairs(frame:GetDescendants()) do
				if object:IsA("TextLabel") then
					object.RichText = true
					labels[#labels + 1] = object
				end
			end
			return labels
		end

		local function findTextBox(frame)
			return frame:FindFirstChildWhichIsA("TextBox", true)
		end

		local function isLocked(handle)
			if handle.Locked then
				return true
			end
			local parent = handle._context
			while parent do
				if parent.Locked then
					return true
				end
				parent = parent._context
			end
			return false
		end

		local function optionLabel(value)
			if type(value) == "table" then
				return tostring(value.Title or value.Name or value[1] or "")
			end
			return value ~= nil and tostring(value) or nil
		end

		local function normalizeOptions(values)
			local labels, originals = {}, {}
			for _, value in ipairs(values or {}) do
				local label = optionLabel(value)
				if label then
					labels[#labels + 1] = label
					originals[label] = value
				end
			end
			return labels, originals
		end

		local function toNativeSelection(handle, value)
			if handle.Multi then
				local result = {}
				if value ~= nil then
					local values = type(value) == "table" and not value.Title and value or { value }
					for _, item in ipairs(values) do
						result[#result + 1] = optionLabel(item)
					end
				end
				return result
			end
			return optionLabel(value)
		end

		local function fromNativeSelection(handle, value)
			if handle.Multi then
				local result = {}
				for _, label in ipairs(value or {}) do
					result[#result + 1] = handle._options[label] or label
				end
				return result
			end
			return value ~= nil and (handle._options[value] or value) or nil
		end

		local function syncValue(handle, value)
			if handle.__type == "Dropdown" then
				handle.Value = fromNativeSelection(handle, value)
			elseif handle.__type == "Slider" then
				handle.Value.Default = tonumber(value) or handle.Value.Default
			elseif handle.__type == "Keybind" then
				handle.Value = typeof(value) == "EnumItem" and value.Name or tostring(value or "Unknown")
			elseif handle.__type == "Colorpicker" then
				handle.Default = value
				handle.Value = value
			else
				handle.Value = value
			end
			if handle._checkbox then
				handle._checkbox.BackgroundColor3 = handle.Value and UIEngine.Theme.Accent or UIEngine.Theme.Surface3
				handle._checkmark.ImageTransparency = handle.Value and 0 or 1
			end
		end

		local function nativeValue(handle)
			if handle.__type == "Slider" then
				return handle.Value.Default
			end
			if handle.__type == "Dropdown" then
				return toNativeSelection(handle, handle.Value)
			end
			if handle.__type == "Keybind" then
				return Enum.KeyCode[handle.Value] or Enum.KeyCode.Unknown
			end
			if handle.__type == "Colorpicker" then
				return handle.Default
			end
			return handle.Value
		end

		local function dispatch(handle, value, ...)
			if handle._destroyed or Library._destroyed then
				return
			end
			if isLocked(handle) then
				if handle._native and handle._native.Set and handle.__type ~= "Input" then
					handle._native:Set(nativeValue(handle), true)
				end
				return
			end
			if handle.__type == "Dropdown" and not handle.AllowNone then
				local empty = value == nil or (handle.Multi and #value == 0)
				if empty and handle.Value ~= nil and handle._native then
					handle._native:Set(nativeValue(handle), true)
					return
				end
			end
			syncValue(handle, value)
			local returned = handle.__type == "Slider" and handle.Value.Default or handle.Value
			if handle.__type == "Colorpicker" then
				returned = handle.Default
			end
			return call(handle.Callback, returned, ...)
		end

		local function addLeadingIcon(handle, icon, tint)
			if not icon or not handle.UIElements.Title then
				return
			end
			local title = handle.UIElements.Title
			local desc = handle.UIElements.Desc
			local frame = title.Parent
			local image = new("ImageLabel", {
				Name = "UIControlIcon",
				BackgroundTransparency = 1,
				Size = UDim2.fromOffset(16, 16),
				Position = UDim2.new(0, 14, 0, title.Position.Y.Offset + 1),
				ScaleType = Enum.ScaleType.Fit,
				Parent = frame,
			})
			setIcon(image, icon, tint)
			title.Position += UDim2.fromOffset(24, 0)
			title.Size -= UDim2.fromOffset(24, 0)
			if desc then
				desc.Position += UDim2.fromOffset(24, 0)
				desc.Size -= UDim2.fromOffset(24, 0)
			end
			handle.UIElements.Icon = image
		end

		local function wrapControl(context, kind, config, native, handle)
			handle = handle or {}
			handle.__type = kind
			handle.Title = config.Title or config.Name or kind
			handle.Desc = config.Desc or config.Description or ""
			handle.Flag = config.Flag
			handle.Callback = handle.Callback or config.Callback
			handle.Locked = config.Locked == true
			handle.LockedTitle = config.LockedTitle
			handle._config = config
			handle._native = native
			handle._context = context
			handle._connections = {}
			handle._children = {}
			local frame = native._frame
			local labels = textLabels(frame)
			handle.Instance, handle.Frame, handle.Holder = frame, frame, frame
			handle.UIElements = {
				Main = frame,
				Title = native.TitleLabel or labels[1],
				Desc = native.DescriptionLabel or (config.Desc and labels[2] or nil),
				Container = frame,
			}
			if kind == "Slider" or kind == "Input" then
				handle.UIElements.Desc = native.DescriptionLabel
				handle.UIElements.Value = native.ValueLabel or native.ValueInput
			end
			handle[kind .. "Frame"] = { UIElements = handle.UIElements }
			if kind == "Paragraph" then
				handle.UIElements.Desc = labels[2]
			end
			if kind == "Button" then
				handle.ButtonFrame = { UIElements = handle.UIElements }
			end
			setmetatable(handle, {
				__index = function(self, key)
					if key == "Picking" or key == "Listening" then
						return native.Listening == true
					end
					if key == "Visible" then
						return frame.Visible
					end
					return ControlMethods[key]
				end,
				__newindex = function(self, key, value)
					if key == "Visible" then
						frame.Visible = value == true
					else
						rawset(self, key, value)
					end
				end,
			})
			Library._controls[handle] = true
			context._children[handle] = true
			if config.Flag and context._window then
				context._window.PendingFlags[config.Flag] = handle
			end
			if native.Get then
				syncValue(handle, native:Get())
			end
			if config.Icon and kind ~= "Button" and kind ~= "Input" and kind ~= "Paragraph" then
				addLeadingIcon(handle, config.Icon, config.IconColor)
			end
			if handle.Locked then
				handle:Lock(config.LockedTitle)
			end
			return handle
		end

		local function decorateOptions(handle)
			local native = handle._native
			if not native or not native.UIOptionRows then
				return
			end
			for label, row in pairs(native.UIOptionRows) do
				local entry = handle._options[label]
				local detail = type(entry) == "table" and (entry.Desc or entry.Description) or nil
				local icon = type(entry) == "table" and entry.Icon or nil
				local contentInset = icon and 36 or 12
				row.Label.RichText = true
				row.Label.Position = UDim2.fromOffset(contentInset, detail and 8 or -1)
				row.Label.Size = detail and UDim2.new(1, -contentInset - 28, 0, 17)
					or UDim2.new(1, -contentInset - 28, 1, 0)
				local image = row.Frame:FindFirstChild("UIOptionIcon")
				if icon then
					image = image
						or new("ImageLabel", {
							Name = "UIOptionIcon",
							Size = UDim2.fromOffset(16, 16),
							BackgroundTransparency = 1,
							Position = UDim2.fromOffset(12, detail and 9 or 0),
							AnchorPoint = detail and Vector2.zero or Vector2.new(0, 0.5),
							Parent = row.Frame,
						})
					if not detail then
						image.Position = UDim2.new(0, 12, 0.5, 0)
					end
					setIcon(image, icon, UIEngine.Theme.Accent)
				elseif image then
					image:Destroy()
				end
				local description = row.Frame:FindFirstChild("UIOptionDescription")
				if detail then
					description = description
						or new("TextLabel", {
							Name = "UIOptionDescription",
							BackgroundTransparency = 1,
							FontFace = UIEngine.Fonts.Regular,
							TextColor3 = UIEngine.Theme.Muted,
							TextSize = 12,
							RichText = true,
							TextWrapped = true,
							TextTruncate = Enum.TextTruncate.None,
							TextXAlignment = Enum.TextXAlignment.Left,
							TextYAlignment = Enum.TextYAlignment.Top,
							Parent = row.Frame,
						})
					description.Text = tostring(detail)
					description.Position = UDim2.fromOffset(contentInset, 28)
					description.Size = UDim2.new(1, -contentInset - 28, 0, 30)
					row.Frame.Size = UDim2.new(1, 0, 0, UIEngine.Touch and 64 or 60)
					row.Check.Position = UDim2.new(1, -10, 0, 18)
				else
					if description then
						description:Destroy()
					end
					row.Frame.Size = UDim2.new(1, 0, 0, UIEngine.Touch and 40 or 34)
					row.Check.Position = UDim2.new(1, -10, 0.5, 0)
				end
			end
			native.UIReflow()
		end

		function ControlMethods:SetTitle(title)
			self.Title = tostring(title or "")
			if self._native and self._native.SetText then
				self._native:SetText(self.Title)
			end
			if self.UIElements.Title then
				self.UIElements.Title.Text = self.Title
			end
			return self
		end

		function ControlMethods:SetDesc(description)
			self.Desc = tostring(description or "")
			if self.__type == "Paragraph" and self._native then
				self._native:Set(self.Desc)
			end
			local label = self.UIElements.Desc
			if not label and self.UIElements.Title then
				local title = self.UIElements.Title
				label = new("TextLabel", {
					Name = "Description",
					BackgroundTransparency = 1,
					RichText = true,
					FontFace = UIEngine.Fonts.Regular,
					TextColor3 = UIEngine.Theme.Muted,
					TextSize = 13,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextWrapped = true,
					Position = UDim2.new(0, title.Position.X.Offset, 0, title.Position.Y.Offset + 22),
					Size = UDim2.new(1, -80, 0, 18),
					Parent = title.Parent,
				})
				self.UIElements.Desc = label
				self.Frame.Size = UDim2.new(
					self.Frame.Size.X.Scale,
					self.Frame.Size.X.Offset,
					0,
					math.max(self.Frame.Size.Y.Offset, 64)
				)
			end
			if label then
				label.Text = self.Desc
			end
			return self
		end

		function ControlMethods:SetIcon(icon)
			if self.UIElements.Icon then
				setIcon(self.UIElements.Icon, icon, self._config.IconColor)
			else
				addLeadingIcon(self, icon, self._config.IconColor)
			end
			self._config.Icon = icon
			return self
		end

		function ControlMethods:Get()
			if self.__type == "Slider" then
				return self.Value.Default
			end
			if self.__type == "Colorpicker" then
				return self.Default
			end
			if self.__type == "Input" and self._native then
				syncValue(self, self._native:Get())
			end
			return self.Value
		end

		function ControlMethods:Set(value, skipCallback)
			if self._destroyed or not self._native then
				return self
			end
			if self.__type == "Dropdown" and self.Flag == "Tema" then
				local name = type(value) == "table" and value.Title or value
				if not Library:GetThemes()[name] then
					value = Library:GetCurrentTheme()
				end
			end
			local target = value
			if self.__type == "Dropdown" then
				target = toNativeSelection(self, value)
			end
			if self.__type == "Keybind" then
				target = typeof(value) == "EnumItem" and value or Enum.KeyCode[tostring(value)] or Enum.KeyCode.Unknown
				self._native:Set(target, true)
			elseif self.__type == "Paragraph" then
				return self:SetDesc(value)
			elseif self._native.Set then
				self._native:Set(target, skipCallback == true)
			end
			if self._native.Get then
				syncValue(self, self._native:Get())
			end
			if self._textBox then
				self._textBox.Text = tostring(value or "")
			end
			return self
		end
		ControlMethods.SetValue = ControlMethods.Set
		ControlMethods.Select = ControlMethods.Set
		function ControlMethods:Update(value, transparency)
			self.Transparency = transparency or self.Transparency
			return self:Set(value)
		end

		function ControlMethods:SetVisible(visible)
			if not self._destroyed then
				self.Frame.Visible = visible == true
			end
			return self
		end

		function ControlMethods:Lock(title)
			if self._destroyed then
				return self
			end
			self.Locked = true
			if self._native then
				self._native.Listening = false
			end
			if not self._lockOverlay then
				local overlay = new("TextButton", {
					Name = "Locked",
					Size = UDim2.fromScale(1, 1),
					BackgroundColor3 = UIEngine.Theme.Background,
					BackgroundTransparency = 0.18,
					Text = "",
					AutoButtonColor = false,
					ZIndex = 80,
					Parent = self.UIElements.Header or self.Frame,
				})
				new("UICorner", { CornerRadius = UDim.new(0, 12), Parent = overlay })
				self._lockOverlay = overlay
			end
			self._lockOverlay.Text = title or self.LockedTitle or ""
			self._lockOverlay.FontFace = UIEngine.Fonts.Medium
			self._lockOverlay.TextSize = 12
			self._lockOverlay.TextColor3 = UIEngine.Theme.Muted
			self._lockOverlay.Visible = true
			return self
		end

		function ControlMethods:Unlock()
			self.Locked = false
			if self._lockOverlay then
				self._lockOverlay.Visible = false
			end
			return self
		end

		function ControlMethods:Destroy()
			if self._destroyed then
				return
			end
			self._destroyed = true
			Library._controls[self] = nil
			if self._context then
				self._context._children[self] = nil
			end
			local window = self._context and self._context._window
			if window and self.Flag and window.PendingFlags[self.Flag] == self then
				window.PendingFlags[self.Flag] = nil
			end
			local children = {}
			for child in pairs(self._children or {}) do
				children[#children + 1] = child
			end
			for _, child in ipairs(children) do
				child:Destroy()
			end
			for _, connections in pairs(self._childConnections or {}) do
				for _, connection in ipairs(connections) do
					disconnect(connection)
				end
			end
			self._childConnections = nil
			for _, connection in ipairs(self._connections or {}) do
				disconnect(connection)
			end
			self._connections = {}
			if self._native and self._native.Destroy then
				self._native:Destroy()
			elseif self.Frame then
				self.Frame:Destroy()
			end
			self.Callback = nil
			self._native = nil
			self._context = nil
		end
		ControlMethods.Delete = ControlMethods.Destroy
		ControlMethods.Remove = ControlMethods.Destroy
		ControlMethods.Clear = ControlMethods.Destroy
		local function provider(context, list)
			return setmetatable(
				{ List = list, Window = context._provider.Window, _order = 0 },
				getmetatable(context._provider)
			)
		end

		local function context(parent, nativeProvider, frame)
			local result = {
				_provider = nativeProvider,
				_window = parent._window or parent,
				_context = parent,
				_children = {},
				_connections = {},
				Frame = frame or nativeProvider.List,
				Instance = frame or nativeProvider.List,
				Holder = frame or nativeProvider.List,
				Locked = false,
			}
			result.UIElements = { Main = result.Frame, Container = nativeProvider.List }
			parent._children[result] = true
			return setmetatable(result, {
				__index = function(self, key)
					if key == "Visible" then
						return self.Frame.Visible
					end
					return ContainerMethods[key] or ControlMethods[key]
				end,
				__newindex = function(self, key, value)
					if key == "Visible" then
						self.Frame.Visible = value == true
					else
						rawset(self, key, value)
					end
				end,
			})
		end

		local function adaptControl(handle, kind, config)
			if kind == "Paragraph" or kind == "Label" or config.Type == "Textarea" then
				return
			end
			local frame, native = handle.Frame, handle._native
			local title, description = handle.UIElements.Title, handle.UIElements.Desc
			if not title then
				return
			end
			local window = handle._context._window._native
			local holder = native.ValueHolder
			local function snapshot(object)
				return object
					and {
						Position = object.Position,
						Size = object.Size,
						AnchorPoint = object.AnchorPoint,
						TextSize = object:IsA("TextLabel") and object.TextSize or nil,
					}
			end
			local original = {
				Height = frame.Size.Y.Offset,
				Title = snapshot(title),
				Description = snapshot(description),
				Holder = snapshot(holder),
				Track = snapshot(native.Track),
				Hit = snapshot(native.HitArea),
				Leading = snapshot(native.LeadingIcon),
				Indicator = snapshot(native.ActionIndicator),
			}
			local wasCompact = false
			local wasStacked = false
			local scheduled = false
			local function restore(object, state)
				if not object or not state then
					return
				end
				object.Position, object.Size, object.AnchorPoint = state.Position, state.Size, state.AnchorPoint
				if state.TextSize then
					object.TextSize = state.TextSize
				end
			end

			local function arrange()
				if scheduled or handle._destroyed then
					return
				end
				scheduled = true
				task.defer(function()
					scheduled = false
					if handle._destroyed or not frame.Parent then
						return
					end
					local scale = math.max(window.Scale.Scale, 0.01)
					local width = frame.AbsoluteSize.X / scale
					if width <= 0 then
						return
					end
					local compact = window._compactLayout or width < 360
					local stacked = holder and kind ~= "Slider" and kind ~= "Colorpicker" and compact and width < 300
					if holder and kind == "Input" then
						local inlineWidth = math.min(240, width - 130)
						stacked = width < 300 or (frame:GetAttribute("UIValueWidth") or 90) > inlineWidth
					end
					local wrapped = compact or stacked or config.DisplayTitle ~= nil or config.DisplayDesc ~= nil
					title.TextWrapped = wrapped == true
					title.TextTruncate = wrapped and Enum.TextTruncate.None or Enum.TextTruncate.AtEnd
					if description then
						description.TextWrapped = wrapped == true
						description.TextTruncate = title.TextTruncate
					end
					frame:SetAttribute("UICompact", compact)
					frame:SetAttribute("UIStacked", stacked == true)
					if wasStacked and not stacked then
						restore(holder, original.Holder)
						if native.UIResizeValue then
							native.UIResizeValue(true)
						end
					end
					wasStacked = stacked == true
					if not compact then
						if wasCompact then
							restore(title, original.Title)
							restore(description, original.Description)
							if not stacked then
								restore(holder, original.Holder)
							end
							restore(native.Track, original.Track)
							restore(native.HitArea, original.Hit)
							restore(native.LeadingIcon, original.Leading)
							restore(native.ActionIndicator, original.Indicator)
							if native.UIResizeValue and not stacked then
								native.UIResizeValue(true)
							end
						end
						wasCompact = false
						if not wrapped then
							restore(title, original.Title)
							restore(description, original.Description)
							if native.UIResizeValue then
								native.UIResizeValue(true)
							end
							if native.UISetHeaderHeight then
								native.UISetHeaderHeight(original.Height)
							else
								frame.Size = controlSize(frame, original.Height)
							end
							return
						end
					else
						wasCompact = true
						title.TextSize = 14
						if description then
							description.TextSize = 12
						end
					end
					local row = frame.Parent
					local narrowAction = kind == "Button"
						and frame:GetAttribute("UIRole") == "ActionButton"
						and row
						and row:GetAttribute("UIRowColumns") == true
						and width < 200
					local inset = narrowAction and 12 or original.Title.Position.X.Offset
					local reserved = 12
					if native.LeadingIcon then
						if narrowAction then
							native.LeadingIcon.Position = UDim2.fromOffset(12, 18)
						else
							restore(native.LeadingIcon, original.Leading)
						end
					end
					if native.ActionIndicator then
						if narrowAction then
							native.ActionIndicator.Position = UDim2.new(1, -12, 0, 18)
						else
							native.ActionIndicator.Position = original.Indicator.Position
						end
					end
					if compact and kind == "Button" and not narrowAction then
						reserved = frame:GetAttribute("UIRole") == "SectionHeader" and 36 or 46
					end
					if compact and kind == "Toggle" then
						reserved = handle._checkbox and 42 or 68
					end
					if compact and kind == "Slider" then
						reserved = (holder and holder.Size.X.Offset or 56) + 26
					end
					if holder and not stacked and kind ~= "Slider" then
						reserved = holder.Size.X.Offset + math.abs(holder.Position.X.Offset) + 10
					end
					if not compact and not holder and not narrowAction then
						reserved = math.max(12, -original.Title.Size.X.Offset - inset)
					end
					local labelWidth = math.max(24, width - inset - reserved)
					local titleHeight = math.max(18, math.ceil(title.TextBounds.Y / scale) + 2)
					title.AnchorPoint = original.Title.AnchorPoint
					title.Position, title.Size =
						UDim2.fromOffset(
							inset,
							narrowAction and 36 or (compact and 6 or original.Title.Position.Y.Offset)
						),
						UDim2.new(0, labelWidth, 0, titleHeight)
					local bottom = title.Position.Y.Offset + titleHeight
					if description then
						local descHeight = math.max(14, math.ceil(description.TextBounds.Y / scale) + 2)
						description.Position = UDim2.fromOffset(
							narrowAction and inset or original.Description.Position.X.Offset,
							bottom + 2
						)
						description.Size = UDim2.new(0, labelWidth, 0, descHeight)
						bottom += 2 + descHeight
					end
					local height = math.max(44, bottom + 6)
					if stacked then
						holder.AnchorPoint = Vector2.zero
						holder.Position = UDim2.fromOffset(12, bottom + 6)
						holder.Size = UDim2.new(1, -24, 0, 36)
						height = bottom + 48
						if native.UIResizeValue then
							native.UIResizeValue(true)
						end
					elseif compact and kind == "Slider" then
						holder.Position = UDim2.new(1, -14, 0, title.Position.Y.Offset + titleHeight / 2)
						height = math.max(70, bottom + 44)
						native.Track.Position = UDim2.new(0, 14, 0, height - 18)
						native.HitArea.Position = UDim2.new(0, 8, 0, height - 38)
						native.HitArea.Size = UDim2.new(1, -16, 0, 38)
					elseif not compact and not narrowAction then
						local titleAvailable = original.Title.Size.Y.Scale * original.Height
							+ original.Title.Size.Y.Offset
						height = original.Height
							+ math.max(0, titleHeight - titleAvailable)
							+ (
								description
									and math.max(0, description.Size.Y.Offset - original.Description.Size.Y.Offset)
								or 0
							)
						if original.Title.Size.Y.Scale > 0 and not description then
							title.AnchorPoint = Vector2.new(original.Title.AnchorPoint.X, 0.5)
							title.Position =
								UDim2.new(original.Title.Position.X.Scale, original.Title.Position.X.Offset, 0.5, 0)
						end
					end
					if native.UISetHeaderHeight then
						native.UISetHeaderHeight(height)
					else
						frame.Size = controlSize(frame, height)
					end
					local indicator = frame:FindFirstChild("ActionIndicator")
					if indicator then
						indicator.Size = UDim2.fromOffset(
							compact and 26 or (UIEngine.Touch and 32 or 28),
							compact and 26 or (UIEngine.Touch and 32 or 28)
						)
					end
				end)
			end
			for _, label in ipairs(description and { title, description } or { title }) do
				handle._connections[#handle._connections + 1] =
					connect(label:GetPropertyChangedSignal("TextBounds"), arrange)
			end
			handle._connections[#handle._connections + 1] =
				connect(frame:GetPropertyChangedSignal("AbsoluteSize"), arrange)
			handle._connections[#handle._connections + 1] =
				connect(window.Scale:GetPropertyChangedSignal("Scale"), arrange)
			if holder then
				handle._connections[#handle._connections + 1] =
					connect(holder:GetPropertyChangedSignal("AbsoluteSize"), arrange)
			end
			if kind == "Input" then
				handle._connections[#handle._connections + 1] =
					connect(frame:GetAttributeChangedSignal("UIValueWidth"), arrange)
			end
			arrange()
		end

		local function basic(context, kind, config)
			config = type(config) == "table" and config or { Title = tostring(config or "") }
			assert(
				not Library._destroyed,
				"\077\105\099\104\105\103\117\110\032\119\105\110\100\111\119\032\104\097\115\032\098\101\101\110\032\100\101\115\116\114\111\121\101\100"
			)
			if kind == "Dropdown" and config.Flag == "Tema" and config.Value == nil then
				config = table.clone(config)
				config.Value = Library:GetCurrentTheme()
			end
			if kind == "Keybind" and config.Flag == "KeybindUI" and context._window._onToggleKeyChanged then
				config = table.clone(config)
				config.Value = (context._window._toggleKey or Enum.KeyCode.Z).Name
			end
			local handle =
				{ Callback = config.Callback, __type = kind, Locked = config.Locked == true, _context = context }
			if kind == "Slider" then
				local range = type(config.Value) == "table" and config.Value or {}
				handle.Value =
					{ Min = range.Min or 0, Max = range.Max or 100, Default = range.Default or range.Min or 0 }
			elseif kind == "Dropdown" then
				handle.Multi = config.Multi == true
				handle.AllowNone = config.AllowNone ~= false
				handle.Values = config.Values or {}
				local _, originals = normalizeOptions(handle.Values)
				handle._options = originals
				handle.Value = config.Value
			elseif kind == "Colorpicker" then
				handle.Default = config.Default or Color3.new(1, 1, 1)
			else
				handle.Value = config.Value
			end
			local opts = {
				Name = config.DisplayTitle or config.Title or config.Name or kind,
				Desc = config.DisplayDesc or config.Desc,
				Flag = config.Flag,
				Callback = function(value, ...)
					return dispatch(handle, value, ...)
				end,
			}
			local native
			if kind == "Button" then
				opts.Icon = config.Icon
				opts.Style = config.Style == "Primary" and "Primary" or "Action"
				opts.Color = config.Color
				opts.Danger = config.Style == "Danger"
				opts.Callback = function()
					if not handle._destroyed and not isLocked(handle) then
						return call(handle.Callback)
					end
				end
				native = context._provider:CreateButton(opts)
			elseif kind == "Toggle" then
				opts.CurrentValue = config.Value == true
				native = context._provider:CreateToggle(opts)
			elseif kind == "Slider" then
				opts.Range = { handle.Value.Min, handle.Value.Max }
				opts.CurrentValue = handle.Value.Default
				opts.Increment = config.Step or 1
				native = context._provider:CreateSlider(opts)
			elseif kind == "Dropdown" then
				opts.Options = normalizeOptions(handle.Values)
				opts.CurrentOption = toNativeSelection(handle, config.Value)
				opts.MultipleOptions = handle.Multi
				opts.SearchAfter = config.SearchBarEnabled and 0 or 6
				opts.MaxVisibleOptions = config.MaxVisibleOptions
				native = context._provider:CreateDropdown(opts)
			elseif kind == "Input" then
				opts.Icon = config.InputIcon or config.Icon
				opts.PlaceholderText = config.DisplayPlaceholder or config.Placeholder or ""
				opts.CurrentValue = tostring(config.Value or "")
				native = context._provider:CreateInput(opts)
			elseif kind == "Keybind" then
				opts.CurrentKeybind = config.Value or "Unknown"
				opts.OnChanged = function(value)
					return dispatch(handle, value)
				end
				opts.Callback = config.FireOnBind == false
						and function(value)
							return dispatch(handle, value)
						end
					or nil
				native = context._provider:CreateKeybind(opts)
			elseif kind == "Colorpicker" then
				opts.CurrentValue = handle.Default
				native = context._provider:CreateColorPicker(opts)
			elseif kind == "Paragraph" then
				opts.Content = config.Desc or config.Content or ""
				native = context._provider:CreateParagraph(opts)
			elseif kind == "Label" then
				native =
					context._provider:CreateLabel({ Text = config.Title or config.Text or "", Color = config.Color })
			else
				error(
					"\085\110\115\117\112\112\111\114\116\101\100\032\077\105\099\104\105\103\117\110\032\099\111\109\112\111\110\101\110\116\058\032"
						.. kind
				)
			end
			handle = wrapControl(context, kind, config, native, handle)
			if kind == "Dropdown" then
				decorateOptions(handle)
			elseif kind == "Button" then
				if config.Color then
					native._frame.BackgroundColor3 = config.Color
				end
				if config.Style == "Danger" and handle.UIElements.Title then
					handle.UIElements.Title.TextColor3 = UIEngine.Theme.Error
				end
				if config.Justify == "Center" and handle.UIElements.Title then
					handle.UIElements.Title.TextXAlignment = Enum.TextXAlignment.Center
				end
			elseif kind == "Toggle" and config.Type == "Checkbox" then
				for _, child in ipairs(native._frame:GetChildren()) do
					if child:IsA("Frame") and child.AnchorPoint.X == 1 then
						child.Visible = false
					end
				end
				local box = new("Frame", {
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -16, 0.5, 0),
					Size = UDim2.fromOffset(22, 22),
					BorderSizePixel = 0,
					Parent = native._frame,
				})
				new("UICorner", { CornerRadius = UDim.new(0, 6), Parent = box })
				new("UIStroke", { Color = UIEngine.Theme.Stroke, Parent = box })
				local mark =
					new("ImageLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = box })
				setIcon(mark, "check", UIEngine.Theme.AccentDark)
				handle._checkbox, handle._checkmark = box, mark
				syncValue(handle, native:Get())
			elseif kind == "Input" then
				local box = findTextBox(native._frame)
				handle._textBox = box
				handle.UIElements.Input = box
				if box and config.Type == "Textarea" then
					local holder = box.Parent
					native._frame:SetAttribute("UIMultiline", true)
					native._frame.Size = controlSize(native._frame, 170)
					holder.AnchorPoint = Vector2.zero
					holder.Position = UDim2.fromOffset(14, config.Desc and 65 or 42)
					holder.Size = UDim2.new(1, -28, 1, config.Desc and -79 or -56)
					box.AnchorPoint = Vector2.zero
					box.Size = UDim2.new(1, -16, 1, -12)
					box.Position = UDim2.fromOffset(8, 6)
					box.MultiLine = true
					box.TextScaled = false
					box.TextTruncate = Enum.TextTruncate.None
					box.TextWrapped = true
					box.TextYAlignment = Enum.TextYAlignment.Top
					box.TextXAlignment = Enum.TextXAlignment.Left
					if handle.UIElements.Title then
						handle.UIElements.Title.Position = UDim2.fromOffset(14, 12)
						handle.UIElements.Title.Size = UDim2.new(1, -28, 0, 18)
					end
					if handle.UIElements.Desc then
						handle.UIElements.Desc.Position = UDim2.fromOffset(14, 34)
						handle.UIElements.Desc.Size = UDim2.new(1, -28, 0, 20)
					end
				end
			end
			adaptControl(handle, kind, config)
			return handle
		end
		for _, kind in ipairs({
			"Button",
			"Toggle",
			"Slider",
			"Dropdown",
			"Input",
			"Keybind",
			"Colorpicker",
			"Paragraph",
			"Label",
		}) do
			ContainerMethods[kind] = function(self, config)
				return basic(self, kind, config)
			end
		end
		ContainerMethods.ColorPicker = ContainerMethods.Colorpicker
		function ControlMethods:Refresh(values, keepSelection)
			assert(self.__type == "Dropdown", "Refresh is only available for dropdowns")
			self.Values = values or {}
			local labels, originals = normalizeOptions(self.Values)
			self._options = originals
			if self._native then
				self._native:Refresh(labels, keepSelection ~= false)
				syncValue(self, self._native:Get())
				decorateOptions(self)
			end
			return self
		end

		function ControlMethods:SetOpen(opened)
			if self._native and self._native.SetOpen then
				self._native:SetOpen(opened)
			end
			return self
		end

		local function makeStack(parent, horizontal, rowConfig)
			local frame = new("Frame", {
				Name = horizontal and "HStack" or "VStack",
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = horizontal and Enum.AutomaticSize.None or Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				LayoutOrder = parent._provider:_nextOrder(),
				Parent = parent._provider.List,
			})
			local layout = new("UIListLayout", {
				FillDirection = horizontal and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 8),
				Parent = frame,
			})
			frame:SetAttribute("UILayoutRow", horizontal)
			local stack = context(parent, provider(parent, frame), frame)
			stack.__type = horizontal and "HStack" or "VStack"
			stack._connections = {}
			if horizontal then
				stack._childConnections = {}
				local scheduled = false
				local function arrange()
					if scheduled or stack._destroyed then
						return
					end
					scheduled = true
					task.defer(function()
						scheduled = false
						if stack._destroyed then
							return
						end
						local children, height = {}, 0
						for _, child in ipairs(frame:GetChildren()) do
							if
								child:IsA("GuiObject")
								and child.Visible
								and child:GetAttribute("UIRole") ~= "Spacer"
							then
								children[#children + 1] = child
							end
						end
						local count = #children
						local gap = 8
						local scale = math.max(parent._provider.Window.Scale.Scale, 0.01)
						local minColumnWidth = rowConfig and (rowConfig.MinColumnWidth or 210) or 80
						if not rowConfig then
							for _, child in ipairs(children) do
								if child:GetAttribute("UIRole") ~= "ActionButton" then
									minColumnWidth = 160
									break
								end
							end
						end
						local columns = frame.AbsoluteSize.X / scale
							>= count * minColumnWidth + gap * math.max(0, count - 1)
						frame:SetAttribute("UIRowColumns", columns)
						layout.FillDirection = columns and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical
						layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
						layout.VerticalAlignment = Enum.VerticalAlignment.Top
						local heights = {}
						for index, child in ipairs(children) do
							local natural = child:GetAttribute("UIIntrinsicHeight")
							if natural == nil then
								natural = math.max(child.Size.Y.Offset, child.AbsoluteSize.Y / scale)
							end
							heights[index] = natural
							height = columns and math.max(height, natural) or height + natural
						end
						frame:SetAttribute("UIRowHeight", columns and height or nil)
						for index, child in ipairs(children) do
							local size = columns and UDim2.new(1 / count, -gap * (count - 1) / count, 0, height)
								or UDim2.new(1, 0, 0, heights[index])
							if child.Size ~= size then
								child.Size = size
							end
						end
						if not columns then
							height += gap * math.max(0, count - 1)
						end
						local size = UDim2.new(1, 0, 0, height)
						if frame.Size ~= size then
							frame.Size = size
						end
					end)
				end

				local function watchChild(child)
					if not stack._destroyed and child:IsA("GuiObject") and not stack._childConnections[child] then
						stack._childConnections[child] = {
							connect(child:GetPropertyChangedSignal("Size"), arrange),
							connect(child:GetPropertyChangedSignal("AbsoluteSize"), arrange),
							connect(child:GetAttributeChangedSignal("UIIntrinsicHeight"), arrange),
							connect(child:GetPropertyChangedSignal("Visible"), arrange),
						}
					end
					arrange()
				end
				stack._connections[#stack._connections + 1] = connect(frame.ChildAdded, watchChild)
				stack._connections[#stack._connections + 1] = connect(frame.ChildRemoved, function(child)
					local connections = stack._childConnections and stack._childConnections[child]
					if connections then
						for _, connection in ipairs(connections) do
							disconnect(connection)
						end
						stack._childConnections[child] = nil
					end
					arrange()
				end)
				for _, child in ipairs(frame:GetChildren()) do
					watchChild(child)
				end
				stack._connections[#stack._connections + 1] =
					connect(frame:GetPropertyChangedSignal("AbsoluteSize"), arrange)
				stack._connections[#stack._connections + 1] =
					connect(parent._provider.Window.Scale:GetPropertyChangedSignal("Scale"), arrange)
				arrange()
			end
			return stack
		end

		function ContainerMethods:HStack()
			return makeStack(self, true)
		end

		function ContainerMethods:VStack()
			return makeStack(self, false)
		end

		function ContainerMethods:FormRow(config)
			return makeStack(self, true, config or {})
		end

		function ContainerMethods:Group(config)
			config = config or {}
			local frame = new("Frame", {
				Name = "ControlGroup",
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				LayoutOrder = self._provider:_nextOrder(),
				Parent = self._provider.List,
			})
			new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8), Parent = frame })
			local header = new("TextLabel", {
				Name = "Title",
				Text = config.Title or "",
				FontFace = UIEngine.Fonts.Bold,
				TextSize = 14,
				TextColor3 = UIEngine.Theme.Text,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextWrapped = true,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				LayoutOrder = 1,
				Parent = frame,
			})
			if config.Desc then
				new("TextLabel", {
					Name = "Description",
					Text = config.Desc,
					FontFace = UIEngine.Fonts.Regular,
					TextSize = 12,
					TextColor3 = UIEngine.Theme.Muted,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextWrapped = true,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundTransparency = 1,
					LayoutOrder = 2,
					Parent = frame,
				})
			end
			local list = new("Frame", {
				Name = "Controls",
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				LayoutOrder = 3,
				Parent = frame,
			})
			new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8), Parent = list })
			local group = context(self, provider(self, list), frame)
			group.__type = "Group"
			group.UIElements.Title, group.UIElements.Container = header, list
			return group
		end

		function ContainerMethods:Space(size)
			local frame = new("Frame", {
				Name = "Spacer",
				Size = UDim2.new(1, 0, 0, tonumber(size) or 8),
				Visible = self.__type ~= "HStack",
				BackgroundTransparency = 1,
				LayoutOrder = self._provider:_nextOrder(),
				Parent = self._provider.List,
			})
			frame:SetAttribute("UIRole", "Spacer")
			return wrapControl(self, "Space", {}, { _frame = frame })
		end

		function ContainerMethods:Divider()
			return wrapControl(self, "Divider", {}, self._provider:CreateDivider())
		end

		function ContainerMethods:Section(config)
			config = type(config) == "table" and config or { Title = tostring(config or "") }
			local frame = new("Frame", {
				Name = "Section",
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				LayoutOrder = self._provider:_nextOrder(),
				Parent = self._provider.List,
			})
			new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8), Parent = frame })
			local list = new("Frame", {
				Name = "Controls",
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				LayoutOrder = 2,
				Visible = config.Opened == true,
				Parent = frame,
			})
			new("UIPadding", {
				PaddingLeft = UDim.new(0, 12),
				PaddingTop = UDim.new(0, 4),
				PaddingBottom = UDim.new(0, 12),
				Parent = list,
			})
			new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8), Parent = list })
			local section = context(self, provider(self, list), frame)
			section.__type = "Section"
			section.Title, section.Desc = config.Title or "Section", config.Desc or ""
			section.Opened = config.Opened == true
			section.Locked = config.Locked == true
			section.LockedTitle = config.LockedTitle
			section._connections = {}
			local headerProvider = provider(self, frame)
			local header = headerProvider:CreateButton({
				Name = section.Title,
				Desc = config.Desc,
				Icon = config.Icon,
				Style = "Section",
				Callback = function()
					if not section._destroyed and not isLocked(section) then
						section:SetOpened(not section.Opened)
					end
				end,
			})
			header._frame.LayoutOrder = 1
			section._header = header
			local labels = textLabels(header._frame)
			section.UIElements.Title, section.UIElements.Desc = labels[1], config.Desc and labels[2] or nil
			section.UIElements.Header, section.UIElements.Container = header._frame, list
			section._native = {
				Destroy = function()
					header:Destroy()
					frame:Destroy()
				end,
			}
			local arrow
			for _, child in ipairs(header._frame:GetChildren()) do
				if child:IsA("Frame") and child.Position.X.Scale == 1 then
					arrow = child:FindFirstChildWhichIsA("ImageLabel")
				end
			end

			function section:SetOpened(opened)
				self.Opened = opened == true
				list.Visible = self.Opened
				if arrow then
					arrow.Rotation = self.Opened and 90 or 0
				end
				return self
			end
			section.Open = function(self)
				return self:SetOpened(true)
			end
			section.Close = function(self)
				return self:SetOpened(false)
			end
			section.SetOpen = section.SetOpened
			section:SetOpened(section.Opened)
			if section.Locked then
				section:Lock(config.LockedTitle)
			end
			return section
		end

		function ContainerMethods:Chat(config)
			config = config or {}
			local frame = new("Frame", {
				Name = "AssistantChat",
				Size = UDim2.new(1, 0, 0, 400),
				BackgroundColor3 = UIEngine.Theme.Surface,
				BorderSizePixel = 0,
				LayoutOrder = self._provider:_nextOrder(),
				Parent = self._provider.List,
			})
			frame:SetAttribute("NoDrag", true)
			new("UICorner", { CornerRadius = UDim.new(0, 12), Parent = frame })
			new("UIStroke", { Color = UIEngine.Theme.Stroke, Parent = frame })
			local handle = wrapControl(self, "Chat", config, { _frame = frame })
			handle._window = self._window
			handle._messages, handle._busy = {}, false
			local function text(parent, value, size, muted, bold)
				return new("TextLabel", {
					BackgroundTransparency = 1,
					Text = value,
					TextSize = size,
					FontFace = bold and UIEngine.Fonts.Bold or UIEngine.Fonts.Regular,
					TextColor3 = muted and UIEngine.Theme.Muted or UIEngine.Theme.Text,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextYAlignment = Enum.TextYAlignment.Center,
					TextTruncate = Enum.TextTruncate.AtEnd,
					RichText = false,
					Parent = parent,
				})
			end

			local function corner(parent, radius)
				new("UICorner", { CornerRadius = UDim.new(0, radius), Parent = parent })
			end

			local function bind(owner, signal, callback)
				owner._connections[#owner._connections + 1] = connect(signal, callback)
			end
			local title = text(frame, "Assistente", 16, false, true)
			title.Position, title.Size = UDim2.fromOffset(16, 10), UDim2.new(1, -112, 0, 24)
			local contextLabel = text(frame, "Conversa livre", 11, true)
			contextLabel.Position, contextLabel.Size = UDim2.fromOffset(16, 34), UDim2.new(1, -112, 0, 18)
			local function button(parent, caption, width)
				local result = new("TextButton", {
					Text = caption,
					FontFace = UIEngine.Fonts.Medium,
					TextSize = 12,
					TextColor3 = UIEngine.Theme.Text,
					BackgroundColor3 = UIEngine.Theme.Surface3,
					BorderSizePixel = 0,
					AutoButtonColor = false,
					Selectable = true,
					Size = UDim2.new(0, width, 0, 44),
					Parent = parent,
				})
				result:SetAttribute("NoDrag", true)
				corner(result, 10)
				return result
			end

			local function tintAction(owner, control, surface, foreground)
				control.BackgroundColor3, control.TextColor3 = surface, foreground
				local hovered, focused = false, false
				local function paint()
					local target = hovered or focused
					TweenService:Create(control, TweenInfo.new(0.12), {
						BackgroundColor3 = target and surface:Lerp(Color3.new(1, 1, 1), 0.08) or surface,
					}):Play()
				end
				bind(owner, control.MouseEnter, function()
					hovered = true
					paint()
				end)
				bind(owner, control.MouseLeave, function()
					hovered = false
					paint()
				end)
				bind(owner, control.SelectionGained, function()
					focused = true
					paint()
				end)
				bind(owner, control.SelectionLost, function()
					focused = false
					paint()
				end)
			end
			local copySurface, copyText = Color3.fromRGB(44, 54, 77), Color3.fromRGB(207, 222, 255)
			local chatSurface, chatText = Color3.fromRGB(35, 64, 53), Color3.fromRGB(191, 238, 214)
			local clear = button(frame, "Limpar", 76)
			clear.AnchorPoint, clear.Position = Vector2.new(1, 0), UDim2.new(1, -12, 0, 10)
			local documentRow = new("Frame", {
				Name = "ChatDocument",
				Position = UDim2.fromOffset(12, 62),
				Size = UDim2.new(1, -24, 0, UIEngine.Touch and 54 or 48),
				BackgroundTransparency = 1,
				Visible = false,
				Parent = frame,
			})
			local messages = new("ScrollingFrame", {
				Name = "Messages",
				Position = UDim2.fromOffset(0, 62),
				Size = UDim2.new(1, 0, 1, -174),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ScrollBarThickness = 3,
				ScrollBarImageColor3 = UIEngine.Theme.StrokeHover,
				ScrollingDirection = Enum.ScrollingDirection.Y,
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				CanvasSize = UDim2.new(),
				ClipsDescendants = true,
				Parent = frame,
			})
			local messageLayout = new(
				"UIListLayout",
				{ SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 20), Parent = messages }
			)
			new("UIPadding", {
				PaddingTop = UDim.new(0, 8),
				PaddingBottom = UDim.new(0, 16),
				PaddingLeft = UDim.new(0, 16),
				PaddingRight = UDim.new(0, 16),
				Parent = messages,
			})
			local empty = new("Frame", {
				Name = "EmptyConversation",
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(20, 62),
				Size = UDim2.new(1, -40, 1, -174),
				Parent = frame,
			})
			local emptyTitle = text(empty, "Como posso ajudar?", 19, false, true)
			emptyTitle.AnchorPoint, emptyTitle.Position = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.4)
			emptyTitle.Size, emptyTitle.TextXAlignment = UDim2.new(1, 0, 0, 30), Enum.TextXAlignment.Center
			local emptyDesc = text(empty, "Faça uma pergunta ou use um documento como referência.", 12, true)
			emptyDesc.AnchorPoint, emptyDesc.Position = Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0.4, 24)
			emptyDesc.Size, emptyDesc.TextWrapped = UDim2.new(1, 0, 0, 44), true
			emptyDesc.TextXAlignment, emptyDesc.TextTruncate = Enum.TextXAlignment.Center, Enum.TextTruncate.None
			local composer = new("Frame", {
				Name = "Composer",
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(0, 12, 1, -30),
				Size = UDim2.new(1, -24, 0, 72),
				BackgroundColor3 = UIEngine.Theme.Surface2,
				BorderSizePixel = 0,
				Parent = frame,
			})
			corner(composer, 12)
			local inputBorder = new("UIStroke", { Color = UIEngine.Theme.Stroke, Parent = composer })
			local draftScroll = new("ScrollingFrame", {
				Name = "Draft",
				Position = UDim2.fromOffset(12, 10),
				Size = UDim2.new(1, -76, 1, -20),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				CanvasSize = UDim2.new(),
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				ScrollingDirection = Enum.ScrollingDirection.Y,
				ScrollBarThickness = 2,
				ScrollBarImageColor3 = UIEngine.Theme.StrokeHover,
				Parent = composer,
			})
			local input = new("TextBox", {
				Name = "MessageInput",
				Size = UDim2.new(1, -4, 0, 52),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				ClearTextOnFocus = false,
				Text = "",
				PlaceholderText = "Escreva sua mensagem…",
				MultiLine = true,
				TextWrapped = true,
				TextSize = 14,
				FontFace = UIEngine.Fonts.Regular,
				TextColor3 = UIEngine.Theme.Text,
				PlaceholderColor3 = UIEngine.Theme.Muted,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				Parent = draftScroll,
			})
			input:SetAttribute("NoDrag", true)
			local send = button(composer, "Enviar", 56)
			send.AnchorPoint, send.Position = Vector2.new(1, 0.5), UDim2.new(1, -8, 0.5, 0)
			local hint =
				text(frame, UIEngine.Touch and "Toque em Enviar para conversar" or "Ctrl + Enter para enviar", 10, true)
			hint.AnchorPoint, hint.Position = Vector2.new(0, 1), UDim2.new(0, 16, 1, -6)
			hint.Size = UDim2.new(1, -32, 0, 18)
			local function refreshSend()
				send.Interactable = not handle._busy and input.Text:match("%S") ~= nil
				send.BackgroundTransparency = send.Interactable and 0 or 0.4
			end
			bind(handle, input:GetPropertyChangedSignal("Text"), refreshSend)
			refreshSend()
			local followTail, messageOrder, confirmingClear = true, 0, false
			local function scrollToEnd()
				task.defer(function()
					if handle._destroyed or not followTail then
						return
					end
					messages.CanvasPosition =
						Vector2.new(0, math.max(0, messages.AbsoluteCanvasSize.Y - messages.AbsoluteWindowSize.Y))
				end)
			end
			bind(handle, messages:GetPropertyChangedSignal("CanvasPosition"), function()
				followTail = messages.AbsoluteCanvasSize.Y - messages.AbsoluteWindowSize.Y - messages.CanvasPosition.Y
					< 36
			end)
			bind(handle, messages:GetPropertyChangedSignal("AbsoluteCanvasSize"), scrollToEnd)
			local function layoutChat()
				if handle._destroyed then
					return
				end
				local page = handle._context._window._native.Content
				local scale = handle._context._window._native.Scale
				local height = page.AbsoluteSize.Y / (scale and scale.Scale > 0 and scale.Scale or 1)
				local documentHeight = documentRow.Visible
						and (handle._documents and handle._documents.Frame.Size.Y.Offset or (UIEngine.Touch and 54 or 48))
					or 0
				local offset = 62 + (documentHeight > 0 and documentHeight + 8 or 0)
				local expandedHeight = math.max(0, documentHeight - (UIEngine.Touch and 54 or 48))
				frame.Size =
					UDim2.new(1, 0, 0, math.clamp(height + 24, UIEngine.Touch and 430 or 460, 680) + expandedHeight)
				documentRow.Size = UDim2.new(1, -24, 0, documentHeight)
				messages.Position, messages.Size = UDim2.fromOffset(0, offset), UDim2.new(1, 0, 1, -(offset + 112))
				empty.Position, empty.Size = UDim2.fromOffset(20, offset), UDim2.new(1, -40, 1, -(offset + 112))
			end
			bind(handle, self._window._native.Content:GetPropertyChangedSignal("AbsoluteSize"), layoutChat)
			layoutChat()
			function handle:Documents(options)
				if self._documents then
					return self._documents
				end
				options = table.clone(options or {})
				options.Title, options.Desc = "Documento", nil
				options.SearchBarEnabled = true
				options.MaxVisibleOptions = 4
				local documentsContext = context(self, provider(self._context, documentRow), documentRow)
				self._documents = ContainerMethods.Dropdown(documentsContext, options)
				documentRow.Visible = true
				bind(self, self._documents.Frame:GetPropertyChangedSignal("Size"), layoutChat)
				layoutChat()
				return self._documents
			end

			function handle:SetContext(value)
				contextLabel.Text = tostring(value or "Conversa livre")
				return self
			end

			function handle:SetInput(value)
				input.Text = tostring(value or "")
				return self
			end

			function handle:AddMessage(message)
				if self._destroyed then
					return
				end
				message = message or {}
				messageOrder += 1
				empty.Visible = false
				local isUser = message.Role == "user"
				local row = new("Frame", {
					Name = isUser and "UserMessage" or "AssistantMessage",
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					LayoutOrder = messageOrder,
					Parent = messages,
				})
				local entry = wrapControl(self, "ChatMessage", message, { _frame = row })
				self._messages[#self._messages + 1] = entry
				local body = new("Frame", {
					BackgroundColor3 = UIEngine.Theme.Surface3,
					BackgroundTransparency = isUser and 0 or 1,
					BorderSizePixel = 0,
					AnchorPoint = Vector2.new(isUser and 1 or 0, 0),
					Position = UDim2.fromScale(isUser and 1 or 0, 0),
					Size = UDim2.new(isUser and 0.92 or 1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Parent = row,
				})
				corner(body, 12)
				new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8), Parent = body })
				if isUser then
					new("UIPadding", {
						PaddingTop = UDim.new(0, 12),
						PaddingBottom = UDim.new(0, 12),
						PaddingLeft = UDim.new(0, 12),
						PaddingRight = UDim.new(0, 12),
						Parent = body,
					})
				end
				local messageHeader = new(
					"Frame",
					{ Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, LayoutOrder = 1, Parent = body }
				)
				local author = text(
					messageHeader,
					isUser and "Você" or message.Error and "Pedido encerrado" or "Assistente",
					11,
					true,
					true
				)
				author.Size = UDim2.new(1, message.Duration and -116 or 0, 1, 0)
				if type(message.Duration) == "number" then
					local duration = text(
						messageHeader,
						(message.Error and "Após " or "Resposta em ")
							.. string.format("%.1f s", math.max(0, message.Duration)):gsub("%.", ","),
						10,
						true
					)
					duration.AnchorPoint, duration.Position = Vector2.new(1, 0), UDim2.fromScale(1, 0)
					duration.Size, duration.TextXAlignment = UDim2.new(0, 112, 1, 0), Enum.TextXAlignment.Right
				end
				if isUser then
					author.TextColor3 = UIEngine.Theme.Text
				end
				local rawText = tostring(message.Text or "")
				local content = text(body, rawText, 14, false)
				content.Size, content.AutomaticSize = UDim2.new(1, 0, 0, 0), Enum.AutomaticSize.Y
				content.TextWrapped, content.TextTruncate = true, Enum.TextTruncate.None
				content.TextYAlignment, content.LayoutOrder = Enum.TextYAlignment.Top, 2
				entry.UIElements.Message = content
				if not isUser and not message.Pending then
					local formatted = rawText:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
					formatted = formatted:gsub("%*%*(.-)%*%*", "<b>%1</b>")
					formatted = formatted:gsub("^#+%s+([^\n]+)", "<b>%1</b>"):gsub("\n#+%s+([^\n]+)", "\n<b>%1</b>")
					content.RichText, content.Text = true, formatted
				end
				if type(message.Code) == "string" and message.Code ~= "" then
					local codeFrame = new("Frame", {
						Size = UDim2.new(1, 0, 0, 194),
						BackgroundColor3 = UIEngine.Theme.Surface2,
						BorderSizePixel = 0,
						LayoutOrder = 3,
						Parent = body,
					})
					corner(codeFrame, 10)
					local copyCode = button(codeFrame, "Copiar código", 120)
					tintAction(entry, copyCode, copySurface, copyText)
					copyCode.Position = UDim2.fromOffset(8, 4)
					local codeScroll = new("ScrollingFrame", {
						Position = UDim2.fromOffset(12, 52),
						Size = UDim2.new(1, -24, 1, -64),
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						CanvasSize = UDim2.new(),
						AutomaticCanvasSize = Enum.AutomaticSize.XY,
						ScrollBarThickness = 3,
						ScrollBarImageColor3 = UIEngine.Theme.StrokeHover,
						Parent = codeFrame,
					})
					new("TextBox", {
						Text = message.Code,
						TextEditable = false,
						MultiLine = true,
						ClearTextOnFocus = false,
						BackgroundTransparency = 1,
						Size = UDim2.fromOffset(0, 0),
						AutomaticSize = Enum.AutomaticSize.XY,
						FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json"),
						TextSize = 12,
						TextColor3 = UIEngine.Theme.Text,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextYAlignment = Enum.TextYAlignment.Top,
						Parent = codeScroll,
					})
					bind(entry, copyCode.Activated, function()
						call(message.CopyCode, message.Code)
					end)
				end
				if not isUser and not message.Pending then
					local actions = new(
						"Frame",
						{ Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1, LayoutOrder = 4, Parent = body }
					)
					local copy = button(actions, "Copiar", 0)
					tintAction(entry, copy, copySurface, copyText)
					copy.Size = UDim2.new(0.5, -4, 0, 44)
					local gameChat = button(actions, "Enviar no chat", 0)
					tintAction(entry, gameChat, chatSurface, chatText)
					gameChat.Position, gameChat.Size = UDim2.new(0.5, 4, 0, 0), UDim2.new(0.5, -4, 0, 44)
					bind(entry, copy.Activated, function()
						call(message.Copy, rawText)
					end)
					bind(entry, gameChat.Activated, function()
						call(message.SendToChat, rawText)
					end)
				end
				if isUser or message.Pending then
					followTail = true
				end
				scrollToEnd()
				return entry
			end

			function handle:SetProgress(elapsed)
				if self._destroyed or not self._busy then
					return self
				end
				elapsed = math.max(0, tonumber(elapsed) or 0)
				local step = math.floor(elapsed * 2)
				if step == self._progressStep then
					return self
				end
				self._progressStep = step
				local duration = string.format("%.1f s", elapsed):gsub("%.", ",")
				local dots = string.rep(".", step % 3 + 1)
				hint.Text = "Aguardando a IA" .. dots .. " · " .. duration
				if self._pending and not self._pending._destroyed then
					self._pending.UIElements.Message.Text = "Preparando a resposta" .. dots .. "  " .. duration
				end
				return self
			end

			function handle:SetBusy(value, elapsed, ok)
				if self._destroyed then
					return self
				end
				self._busy = value == true
				self._progressStep = nil
				clear.Interactable = true
				send.Text = self._busy and "…" or "Enviar"
				refreshSend()
				if self._documents then
					pcall(function()
						if self._busy then
							self._documents:Lock()
						else
							self._documents:Unlock()
						end
					end)
				end
				hint.Text = self._busy and "Preparando a resposta…"
					or UIEngine.Touch and "Toque em Enviar para conversar"
					or "Ctrl + Enter para enviar"
				if self._busy and not self._pending then
					local ok, pending = pcall(self.AddMessage, self, { Text = "Pensando…", Pending = true })
					if ok then
						self._pending = pending
					end
				elseif not self._busy and self._pending then
					local index = table.find(self._messages, self._pending)
					if index then
						table.remove(self._messages, index)
					end
					pcall(self._pending.Destroy, self._pending)
					self._pending = nil
				end
				if self._busy then
					self:SetProgress(0)
				elseif type(elapsed) == "number" then
					hint.Text = (ok == false and "Pedido encerrado em " or "Resposta recebida em ")
						.. string.format("%.1f s", math.max(0, elapsed)):gsub("%.", ",")
				end
				return self
			end

			function handle:Clear()
				if self._destroyed then
					return self
				end
				self:SetBusy(false)
				for _, entry in ipairs(self._messages) do
					entry:Destroy()
				end
				table.clear(self._messages)
				self._pending, messageOrder, confirmingClear = nil, 0, false
				clear.Text, empty.Visible, followTail = "Limpar", true, true
				messages.CanvasPosition = Vector2.zero
				return self
			end

			local function submit()
				if handle._destroyed or handle._busy then
					return
				end
				local value = input.Text:match("^%s*(.-)%s*$")
				if value == "" then
					return
				end
				call(config.OnSend, value)
			end
			bind(handle, send.Activated, submit)
			bind(handle, UserInputService.InputBegan, function(event)
				if
					UserInputService:GetFocusedTextBox() == input
					and event.KeyCode == Enum.KeyCode.Return
					and (
						UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
						or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
					)
				then
					submit()
				end
			end)
			bind(handle, input.Focused, function()
				inputBorder.Color = UIEngine.Theme.StrokeHover
			end)
			bind(handle, input.FocusLost, function()
				inputBorder.Color = UIEngine.Theme.Stroke
			end)
			bind(handle, clear.Activated, function()
				if #handle._messages == 0 then
					return
				end
				if confirmingClear then
					call(config.OnClear)
					handle:Clear()
				else
					confirmingClear, clear.Text = true, "Confirmar"
					task.delay(4, function()
						if not handle._destroyed then
							confirmingClear, clear.Text = false, "Limpar"
						end
					end)
				end
			end)
			return handle
		end

		function ContainerMethods:Code(config)
			config = type(config) == "table" and config or { Code = tostring(config or "") }
			local frame = new("Frame", {
				Name = "Code",
				Size = UDim2.new(1, 0, 0, 190),
				BackgroundColor3 = UIEngine.Theme.Surface2,
				BorderSizePixel = 0,
				LayoutOrder = self._provider:_nextOrder(),
				Parent = self._provider.List,
			})
			frame:SetAttribute("NoDrag", true)
			new("UICorner", { CornerRadius = UDim.new(0, 12), Parent = frame })
			new("UIStroke", { Color = UIEngine.Theme.Stroke, Parent = frame })
			local scroll = new("ScrollingFrame", {
				Size = UDim2.new(1, -24, 1, -48),
				Position = UDim2.fromOffset(12, 36),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ScrollBarThickness = 3,
				ScrollBarImageColor3 = UIEngine.Theme.Accent,
				AutomaticCanvasSize = Enum.AutomaticSize.XY,
				CanvasSize = UDim2.new(),
				Parent = frame,
			})
			local box = new("TextBox", {
				Text = tostring(config.Code or ""),
				RichText = false,
				MultiLine = true,
				TextEditable = false,
				ClearTextOnFocus = false,
				BackgroundTransparency = 1,
				AutomaticSize = Enum.AutomaticSize.XY,
				Size = UDim2.fromOffset(0, 0),
				FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json"),
				TextSize = 12,
				TextColor3 = UIEngine.Theme.Text,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				Parent = scroll,
			})
			local copy = new("TextButton", {
				Text = "Copiar código",
				Size = UDim2.fromOffset(104, 25),
				Position = UDim2.fromOffset(12, 6),
				BackgroundColor3 = UIEngine.Theme.Surface,
				TextColor3 = UIEngine.Theme.Text,
				FontFace = UIEngine.Fonts.Medium,
				TextSize = 12,
				BorderSizePixel = 0,
				AutoButtonColor = false,
				Parent = frame,
			})
			new("UICorner", { CornerRadius = UDim.new(0, 8), Parent = copy })
			local handle = wrapControl(self, "Code", config, { _frame = frame })
			handle.Code = tostring(config.Code or "")
			function handle:SetCode(value)
				self.Code = tostring(value or "")
				box.Text = self.Code
				return self
			end
			handle.Set = handle.SetCode
			handle._connections[#handle._connections + 1] = connect(copy.Activated, function()
				if type(setclipboard) == "function" then
					setclipboard(handle.Code)
				end
			end)
			return handle
		end
		local createParagraph = ContainerMethods.Paragraph
		function ContainerMethods:Paragraph(config)
			config = type(config) == "table" and config or { Desc = tostring(config or "") }
			local handle = createParagraph(self, config)
			local frame = handle.Frame
			if config.Color then
				frame.BackgroundColor3 = config.Color
			end
			if config.Image then
				local title, desc = handle.UIElements.Title, handle.UIElements.Desc
				local imageSize = typeof(config.ImageSize) == "UDim2" and config.ImageSize or UDim2.fromOffset(28, 28)
				local width = imageSize.X.Offset > 0 and imageSize.X.Offset or 28
				local group = new("Frame", {
					Name = "ParagraphContent",
					Size = UDim2.new(1, 0, 0, 0),
					BackgroundTransparency = 1,
					LayoutOrder = 1,
					Parent = frame,
				})
				local content = new("Frame", {
					Name = "TitleFrame",
					Position = UDim2.fromOffset(width + 12, 0),
					Size = UDim2.new(1, -width - 12, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundTransparency = 1,
					Parent = group,
				})
				new(
					"UIListLayout",
					{ SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4), Parent = content }
				)
				title.Parent = content
				if desc then
					desc.Parent = content
				end
				local image = new("ImageLabel", {
					Name = "Icon",
					BackgroundTransparency = 1,
					Size = imageSize,
					ScaleType = Enum.ScaleType.Fit,
					Parent = group,
				})
				setIcon(image, config.Image, UIEngine.Theme.Accent)
				local function resize()
					if handle._destroyed then
						return
					end
					group.Size = UDim2.new(1, 0, 0, math.max(imageSize.Y.Offset, content.AbsoluteSize.Y))
				end
				handle._connections[#handle._connections + 1] =
					connect(content:GetPropertyChangedSignal("AbsoluteSize"), resize)
				task.defer(resize)
				handle.UIElements.Icon, handle.UIElements.Container = image, group
			end
			if type(config.Buttons) == "table" and #config.Buttons > 0 then
				local paragraphContext = context(self, provider(self, frame), frame)
				self._children[paragraphContext] = nil
				paragraphContext._context = handle
				handle._children[paragraphContext] = true
				local row = paragraphContext:HStack()
				row.Frame.LayoutOrder = 3
				for _, button in ipairs(config.Buttons) do
					row:Button(button)
				end
			end
			return handle
		end

		local function ensureFolder(path)
			ensureStorageFolder(path)
		end

		local function createConfigManager(window, folder)
			local manager = { Folder = folder, Path = resolveStoragePath(folder) .. "/config/", Configs = {} }
			local function read(path)
				path = resolveStoragePath(path)
				if type(readfile) ~= "function" or (type(isfile) == "function" and not isfile(path)) then
					return nil
				end
				local success, data = pcall(function()
					return HttpService:JSONDecode(readfile(path))
				end)
				return success and type(data) == "table" and data or nil
			end

			local function save(path, data)
				path = resolveStoragePath(path)
				assert(type(writefile) == "function", "Este executor não oferece gravação de arquivos")
				ensureFolder(path:match("^(.*)/"))
				writefile(path, HttpService:JSONEncode(data))
			end

			local function serialize(control)
				local value = control:Get()
				if control.__type == "Colorpicker" and typeof(value) == "Color3" then
					value = value:ToHex()
				end
				return { __type = control.__type, value = value, transparency = control.Transparency }
			end

			function manager:SetPath(path)
				self.Path = resolveStoragePath(path) .. "/"
				for name, config in pairs(self.Configs) do
					config.Path = storageFilePath(self.Path, name, ".json")
				end
				ensureFolder(self.Path)
				return true
			end

			function manager:AllConfigs()
				self.Path = resolveStoragePath(self.Path) .. "/"
				local result = {}
				if type(listfiles) ~= "function" then
					return result
				end
				if type(isfolder) == "function" and not isfolder(self.Path) then
					ensureFolder(self.Path)
					return result
				end
				local success, files = pcall(listfiles, self.Path)
				if not success then
					return result
				end
				for _, filename in ipairs(files) do
					local name = filename:match("([^/\\]+)%.json$")
					if name then
						result[#result + 1] = name
					end
				end
				table.sort(result)
				return result
			end

			function manager:CreateConfig(name, autoLoad)
				assert(
					type(name) == "string" and name ~= "" and not name:find("[/\\]"),
					"Nome de configuração inválido"
				)
				local cached = self.Configs[name]
				if cached then
					return cached
				end
				local config = {
					Path = storageFilePath(self.Path, name, ".json"),
					Elements = {},
					CustomData = {},
					AutoLoad = autoLoad == true,
					Version = 1.2,
				}
				local saved = read(config.Path)
				if saved then
					config.AutoLoad = saved.__autoload == true
					config.CustomData = saved.__custom or {}
				end

				function config:Register(flag, control)
					self.Elements[flag] = control
				end

				function config:Set(key, value)
					self.CustomData[key] = value
				end

				function config:Get(key)
					return self.CustomData[key]
				end

				function config:SetAsCurrent()
					window.CurrentConfig = self
				end

				function config:GetData()
					return { elements = self.Elements, custom = self.CustomData, autoload = self.AutoLoad }
				end

				function config:SetAutoLoad(enabled)
					if enabled then
						for _, otherName in ipairs(manager:AllConfigs()) do
							local path = manager.Path .. otherName .. ".json"
							local other = read(path)
							if other and other.__autoload then
								other.__autoload = false
								save(path, other)
							end
							if manager.Configs[otherName] then
								manager.Configs[otherName].AutoLoad = false
							end
						end
					end
					self.AutoLoad = enabled == true
					local data = read(self.Path)
					if data then
						data.__autoload = self.AutoLoad
						save(self.Path, data)
					end
				end

				function config:Save()
					local old = read(self.Path) or {}
					local data = {
						__version = self.Version,
						__elements = old.__elements or {},
						__autoload = self.AutoLoad,
						__custom = self.CustomData,
					}
					for flag, control in pairs(window.PendingFlags) do
						self:Register(flag, control)
					end
					for flag, control in pairs(self.Elements) do
						if not control._destroyed then
							data.__elements[flag] = serialize(control)
						end
					end
					save(self.Path, data)
					return data
				end

				function config:Load(skipCallbacks)
					local data = read(self.Path)
					if not data then
						return false, "Configuração ausente ou JSON inválido"
					end
					for flag, control in pairs(window.PendingFlags) do
						self:Register(flag, control)
					end
					local elements = data.__elements or data
					for flag, record in pairs(elements) do
						local control = self.Elements[flag]
						if control and not control._destroyed and type(record) == "table" then
							local value = record.value
							if control.__type == "Colorpicker" and type(value) == "string" then
								value = Color3.fromHex(value)
							end
							control:Set(value, skipCallbacks == true)
							if not skipCallbacks and (control.__type == "Input" or control.__type == "Keybind") then
								call(control.Callback, control:Get())
							end
							control.Transparency = record.transparency
						end
					end
					self.CustomData = data.__custom or {}
					return self.CustomData
				end

				function config:Delete()
					if type(delfile) ~= "function" then
						return false, "Este executor não permite apagar arquivos"
					end
					local success, message = pcall(delfile, resolveStoragePath(self.Path))
					if not success then
						return false, tostring(message)
					end
					manager.Configs[name] = nil
					if window.CurrentConfig == self then
						window.CurrentConfig = nil
					end
					return true
				end
				self.Configs[name] = config
				config:SetAsCurrent()
				return config
			end

			function manager:Config(...)
				return self:CreateConfig(...)
			end

			function manager:GetConfig(name)
				return self.Configs[name]
			end

			function manager:DeleteConfig(name)
				return self:CreateConfig(name):Delete()
			end

			function manager:GetAutoLoadConfigs()
				local result = {}
				for _, name in ipairs(self:AllConfigs()) do
					local data = read(self.Path .. name .. ".json")
					if data and data.__autoload then
						result[#result + 1] = name
					end
				end
				return result
			end

			function manager:Setup()
				for _, name in ipairs(self:AllConfigs()) do
					self:CreateConfig(name)
				end
				return self
			end
			ensureFolder(manager.Path)
			migrateStorageConfigs("WindUI/" .. tostring(folder) .. "/config", manager.Path, ".windui-migrated")
			return manager
		end

		function Library:Gradient(stops, extra)
			local colors, transparencies = {}, {}
			for position, value in pairs(stops or {}) do
				local time = math.clamp(tonumber(position) / 100, 0, 1)
				local hex = type(value) == "table" and (value.Color or value[1]) or value
				local opacity = type(value) == "table" and (value.Transparency or value[2]) or 0
				colors[#colors + 1] =
					ColorSequenceKeypoint.new(time, typeof(hex) == "Color3" and hex or Color3.fromHex(hex))
				transparencies[#transparencies + 1] = NumberSequenceKeypoint.new(time, opacity or 0)
			end
			table.sort(colors, function(leftKeypoint, rightKeypoint)
				return leftKeypoint.Time < rightKeypoint.Time
			end)
			table.sort(transparencies, function(leftKeypoint, rightKeypoint)
				return leftKeypoint.Time < rightKeypoint.Time
			end)
			if #colors == 1 then
				colors[#colors + 1] = ColorSequenceKeypoint.new(1, colors[1].Value)
				transparencies[#transparencies + 1] = NumberSequenceKeypoint.new(1, transparencies[1].Value)
			end
			local gradient = { Color = ColorSequence.new(colors), Transparency = NumberSequence.new(transparencies) }
			for key, value in pairs(extra or {}) do
				gradient[key] = value
			end
			return gradient
		end
		Library.Themes = ThemeFactory(Library)
		local function nativeTheme(theme)
			local current = UIEngine.Theme
			return {
				Background = color(theme.Background, current.Background),
				Surface = color(theme.Surface or theme.Dialog or theme.Button, current.Surface),
				Surface2 = color(theme.Surface2 or theme.ElementBackground or theme.Button, current.Surface2),
				Surface3 = color(theme.Surface3 or theme.Hover or theme.Button, current.Surface3),
				Stroke = color(theme.Stroke or theme.Outline, current.Stroke),
				StrokeHover = color(theme.StrokeHover or theme.Primary or theme.Accent, current.StrokeHover),
				Accent = color(theme.Accent, current.Accent),
				AccentDark = color(theme.AccentDark or theme.Black, Color3.fromRGB(8, 8, 8)),
				Text = color(theme.Text, current.Text),
				Muted = color(theme.Muted or theme.Placeholder or theme.Icon, current.Muted),
				Glow = color(theme.Glow, current.Glow or current.Accent),
				Success = color(theme.Success, current.Success),
				Warning = color(theme.Warning, current.Warning),
				Error = color(theme.Danger or theme.Error, current.Error),
			}
		end

		function Library:AddTheme(theme)
			assert(type(theme) == "table" and type(theme.Name) == "string", "Tema inválido")
			self.Themes[theme.Name] = theme
			return theme
		end

		function Library:GetThemes()
			return self.Themes
		end

		function Library:GetCurrentTheme()
			return self.Theme and self.Theme.Name
		end
		local backgroundProperties = { "BackgroundColor3" }
		local themeProperties = {
			UIStroke = { "Color" },
			TextLabel = { "BackgroundColor3", "TextColor3" },
			TextButton = { "BackgroundColor3", "TextColor3" },
			TextBox = { "BackgroundColor3", "TextColor3", "PlaceholderColor3" },
			ImageLabel = { "BackgroundColor3", "ImageColor3" },
			ImageButton = { "BackgroundColor3", "ImageColor3" },
		}
		function Library:SetTheme(name)
			if name == "\065\105\114\102\108\111\119" then
				name = "Default"
			end
			if name == "Monokai Pro" then
				name = "Mono"
			end
			local theme = type(name) == "table" and name or self.Themes[name]
			if not theme then
				return false
			end
			local old = table.clone(UIEngine.Theme)
			local nextTheme = nativeTheme(theme)
			local background = type(theme.Background) == "table" and theme.Background or nil
			local gradientColor = background and background.Color or nil
			local gradientTransparency = gradientColor and background.Transparency or nil
			local gradientRotation = gradientColor and (background.Rotation or 0) or nil
			local samePalette = true
			for role, value in pairs(nextTheme) do
				if old[role] ~= value then
					samePalette = false
					break
				end
			end
			if
				samePalette
				and UIEngine.ThemeName == theme.Name
				and self._themeGradientColor == gradientColor
				and self._themeGradientTransparency == gradientTransparency
				and self._themeGradientRotation == gradientRotation
			then
				self.Theme = theme
				return theme
			end
			local replacements = {}
			for role, previous in pairs(old) do
				local reds = replacements[previous.R]
				if not reds then
					reds = {}
					replacements[previous.R] = reds
				end
				local greens = reds[previous.G]
				if not greens then
					greens = {}
					reds[previous.G] = greens
				end
				if greens[previous.B] == nil then
					greens[previous.B] = nextTheme[role]
				end
			end
			for key, value in pairs(nextTheme) do
				UIEngine.Theme[key] = value
			end
			self.Theme = theme
			UIEngine.ThemeName = theme.Name
			if self.ScreenGui then
				for _, object in ipairs(self.ScreenGui:GetDescendants()) do
					local properties = themeProperties[object.ClassName]
					if not properties and object:IsA("GuiObject") then
						properties = backgroundProperties
					end
					if properties then
						for _, property in ipairs(properties) do
							if property ~= "ImageColor3" or not object:GetAttribute("UIUnthemed") then
								local value = object[property]
								if typeof(value) == "Color3" then
									local reds = replacements[value.R]
									local greens = reds and reds[value.G]
									local replacement = greens and greens[value.B]
									if replacement and replacement ~= value then
										object[property] = replacement
									end
								end
							end
						end
					end
				end
				local window = self.Window
				if window and window._native then
					local function refreshActions(context)
						local native = context._header or context._native
						if native and native.RefreshStyle and not native._destroyed then
							native:RefreshStyle()
						end
						for child in pairs(context._children or {}) do
							refreshActions(child)
						end
					end
					refreshActions(window)
					local body = window._native.Body
					local gradient = body:FindFirstChild("UIThemeGradient")
					if type(theme.Background) == "table" and theme.Background.Color then
						gradient = gradient or new("UIGradient", { Name = "UIThemeGradient", Parent = body })
						gradient.Color = theme.Background.Color
						gradient.Transparency = theme.Background.Transparency or NumberSequence.new(0)
						gradient.Rotation = theme.Background.Rotation or 0
						body.BackgroundColor3 = Color3.new(1, 1, 1)
					elseif gradient then
						gradient:Destroy()
						body.BackgroundColor3 = UIEngine.Theme.Background
					end
				end
			end
			self._themeGradientColor = gradientColor
			self._themeGradientTransparency = gradientTransparency
			self._themeGradientRotation = gradientRotation
			return theme
		end

		function Library:SetFont(family)
			if type(family) ~= "string" then
				return false
			end
			local success = pcall(function()
				UIEngine.Fonts.Regular = Font.new(family, Enum.FontWeight.Regular)
				UIEngine.Fonts.Medium = Font.new(family, Enum.FontWeight.Medium)
				UIEngine.Fonts.Bold = Font.new(family, Enum.FontWeight.Bold)
			end)
			return success
		end

		function Library:SetParent(parent)
			assert(typeof(parent) == "Instance", "SetParent espera uma Instance")
			self._parent = parent
			if self.ScreenGui then
				self.ScreenGui.Parent = parent
			end
			return true
		end

		function Library:GetParent()
			return self.ScreenGui and self.ScreenGui.Parent or self._parent
		end

		function Library:SetNotificationLower()
			self._notificationsLower = false
			if self.Window then
				self.Window._native:_resizeNotifications()
			end
		end

		function Library:Notify(config)
			if self.Window and not self._destroyed then
				local result = self.Window._native:Notify(config)
				textLabels(self.ScreenGui)
				return result
			end
			self._pendingNotifications = self._pendingNotifications or {}
			self._pendingNotifications[#self._pendingNotifications + 1] = config
		end
		Library.Creator = {
			New = new,
			Icons = {
				Image = function(config)
					local frame =
						new("Frame", { Size = config.Size or UDim2.fromOffset(16, 16), BackgroundTransparency = 1 })
					local image = new("ImageLabel", {
						Size = UDim2.fromScale(1, 1),
						BackgroundTransparency = 1,
						ScaleType = Enum.ScaleType.Fit,
						Parent = frame,
					})
					setIcon(image, config.Icon, config.Color or UIEngine.Theme.Accent)
					return { IconFrame = frame }
				end,
			},
			Tween = function(object, duration, properties, style, direction)
				return TweenService:Create(
					object,
					TweenInfo.new(
						duration or 0.2,
						style or Enum.EasingStyle.Quad,
						direction or Enum.EasingDirection.Out
					),
					properties
				)
			end,
			AddSignal = connect,
		}
		function WindowMethods:OnOpen(callback)
			self._onOpen = callback
			return self
		end

		function WindowMethods:OnClose(callback)
			self._onClose = callback
			return self
		end

		function WindowMethods:OnDestroy(callback)
			self._onDestroy = callback
			return self
		end

		function WindowMethods:Open()
			self._native:Toggle(true)
			return self
		end

		function WindowMethods:Close()
			self._native:Toggle(false)
			return self
		end

		function WindowMethods:Toggle(open)
			self._native:Toggle(open)
			return self
		end

		function WindowMethods:SetSize(size)
			self._native.Root.Size = size
			self._native._preferredSize = size
			self._native:_fitToScreen(true)
			self._native:_clampToScreen()
			return self
		end

		function WindowMethods:SetToTheCenter()
			self._native:_fitToScreen(true)
			self._native.Root.AnchorPoint = Vector2.new(0.5, 0.5)
			self._native.Root.Position = UDim2.fromScale(0.5, 0.5)
			TweenService:Create(self._native.Root, TweenInfo.new(0), {
				Position = UDim2.fromScale(0.5, 0.5),
			}):Play()
			return self
		end

		function WindowMethods:ToggleTransparency(enabled)
			self._native.Body.BackgroundTransparency = enabled and Library.TransparencyValue or 0
			return self
		end

		function WindowMethods:SetTheme(name)
			return Library:SetTheme(name)
		end

		function WindowMethods:SetCurrentConfig(config)
			self.CurrentConfig = config
		end

		function WindowMethods:WaitForChild(...)
			return self._native.Root:WaitForChild(...)
		end

		function WindowMethods:Dialog(config)
			local result = self._native:Dialog(config)
			textLabels(self._native.Gui)
			return result
		end

		function WindowMethods:RequestClose()
			if self._destroyed then
				return
			end
			if self._closeConfirmation and self._native._dialog == self._closeConfirmation then
				return self._closeConfirmation
			end
			self._closeConfirmation = self:Dialog({
				Title = "Fechar interface?",
				Content = "Tem certeza de que deseja fechar? Será necessário executar o script novamente para abrir a interface.",
				CloseOnBackdrop = false,
				Buttons = {
					{
						Title = "Cancelar",
						Callback = function()
							self._closeConfirmation = nil
						end,
					},
					{
						Title = "Fechar",
						Variant = "Primary",
						Callback = function()
							self._closeConfirmation = nil
							self:Destroy()
						end,
					},
				},
			})
			return self._closeConfirmation
		end

		function WindowMethods:Notify(config)
			return Library:Notify(config)
		end

		function WindowMethods:SetToggleKey(key)
			self._native:SetKeybind(key)
			return self
		end

		function WindowMethods:UpdateToggleKeyDisplay(key)
			local keyCode = typeof(key) == "EnumItem" and key or Enum.KeyCode[tostring(key)]
			if not keyCode or keyCode == Enum.KeyCode.Unknown then
				return self
			end
			self._toggleKey = keyCode
			if not self._capturingToggleKey then
				self._native._keyChipLabel.Text = keyCode.Name
			end
			return self
		end

		function WindowMethods:ConfigureToggleKey(key, onChanged, onCaptureChanged)
			self._onToggleKeyChanged = onChanged
			self._onToggleKeyCapture = onCaptureChanged
			self._native:SetKeybind(Enum.KeyCode.Unknown)
			return self:UpdateToggleKeyDisplay(key)
		end

		function WindowMethods:_setToggleKeyCapture(capturing)
			if capturing == self._capturingToggleKey then
				return
			end
			self._capturingToggleKey = capturing
			self._native._keyChipLabel.Text = capturing and "Pressione uma tecla"
				or (self._toggleKey or Enum.KeyCode.Z).Name
			call(self._onToggleKeyCapture, capturing)
		end

		function WindowMethods:CreateTopbarButton(title, icon, callback, order, _, tint, iconSize)
			local button = new("TextButton", {
				Name = title,
				Size = UDim2.fromOffset(28, 28),
				BackgroundTransparency = 1,
				Text = "",
				AutoButtonColor = false,
				LayoutOrder = order or 1,
				Parent = self.UIElements.Topbar.Right,
			})
			button:SetAttribute("NoDrag", true)
			local image = new("ImageLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(iconSize or 16, iconSize or 16),
				BackgroundTransparency = 1,
				Parent = button,
			})
			setIcon(image, icon, tint)
			connect(button.Activated, function()
				call(callback)
			end)
			return button
		end

		function WindowMethods:CreateWebsiteCard(config)
			config = config or {}
			local window = self
			if self.UIElements.WebsiteCard then
				if type(config.Callback) == "function" then
					self._websiteCardCallback = config.Callback
				end
				return self.UIElements.WebsiteCard
			end
			self._websiteCardCallback = config.Callback
				or function()
					local copied = type(setclipboard) == "function"
						and pcall(
							setclipboard,
							"\104\116\116\112\115\058\047\047\109\105\099\104\105\103\117\110\046\120\121\122"
						)
					if copied then
						window:Notify({
							Title = "Website copiado",
							Content = "\104\116\116\112\115\058\047\047\109\105\099\104\105\103\117\110\046\120\121\122",
							Duration = 3,
						})
					end
					return copied == true
				end
			local topbar = self.UIElements.Topbar
			local actions = topbar.Right
			local card = new("TextButton", {
				Name = "WebsiteCard",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -160, 0, 32),
				Size = UDim2.fromOffset(190, 30),
				BackgroundColor3 = UIEngine.Theme.Surface2,
				BorderSizePixel = 0,
				Text = "",
				AutoButtonColor = false,
				ZIndex = 8,
				Parent = topbar,
			})
			card:SetAttribute("NoDrag", true)
			new("UICorner", { CornerRadius = UDim.new(0, 8), Parent = card })
			local border = new("UIStroke", { Color = UIEngine.Theme.Stroke, Thickness = 1, Parent = card })
			local icon = new("ImageLabel", {
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 10, 0.5, 0),
				Size = UDim2.fromOffset(15, 15),
				BackgroundTransparency = 1,
				ZIndex = 9,
				Parent = card,
			})
			setIcon(icon, "globe", UIEngine.Theme.Muted)
			local caption = new("TextLabel", {
				Position = UDim2.fromOffset(34, 0),
				Size = UDim2.new(1, -44, 1, 0),
				BackgroundTransparency = 1,
				Text = config.Title
					or "\087\101\098\115\105\116\101\058\032\109\105\099\104\105\103\117\110\046\120\121\122",
				TextColor3 = UIEngine.Theme.Text,
				FontFace = UIEngine.Fonts.Medium,
				TextSize = 12,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Center,
				TextTruncate = Enum.TextTruncate.AtEnd,
				ZIndex = 9,
				Parent = card,
			})
			self.UIElements.WebsiteCard = card
			local scheduled = false
			local function layout()
				if scheduled or window._destroyed then
					return
				end
				scheduled = true
				task.defer(function()
					scheduled = false
					if window._destroyed or not card.Parent then
						return
					end
					local scale = math.max(window._native.Scale.Scale, 0.01)
					local width = topbar.AbsoluteSize.X / scale
					if width <= 0 then
						return
					end
					local actionsWidth = actions.AbsoluteSize.X / scale
					local cardWidth =
						math.min(math.max(172, math.ceil(caption.TextBounds.X / scale + 44)), math.max(44, width - 48))
					local separateActions = width < actionsWidth + 160
					local actionsOffset = separateActions and 44 or 0
					actions.AnchorPoint = Vector2.new(1, 0)
					actions.Position = UDim2.new(1, -12, 0, 4)
					actions.Size = UDim2.new(0, 0, 0, 40)
					local stacked = separateActions or width < actionsWidth + cardWidth + 96 + 60
					local extra = (stacked and 40 or 0) + actionsOffset
					local active = window._native.CurrentTab
					local headerHeight = active
							and (active._headerHeight or active._websiteListPosition and active._websiteListPosition.Y.Offset or active.List and active.List.Position.Y.Offset)
						or 58
					card.Size = UDim2.fromOffset(cardWidth, 30)
					card.AnchorPoint = Vector2.new(stacked and 0 or 1, 0.5)
					card.Position = stacked and UDim2.fromOffset(24, headerHeight + actionsOffset + 12)
						or UDim2.new(1, -actionsWidth - 24, 0, 32)
					topbar.Size = UDim2.new(1, 0, 0, stacked and headerHeight + extra or 48)
					for _, tab in ipairs(window._native.Tabs) do
						if not tab._heading and tab._page then
							for _, child in ipairs(tab._page:GetChildren()) do
								if child:IsA("TextLabel") then
									if child.Position.Y.Offset == 20 then
										tab._heading = child
									end
									if child.Position.Y.Offset == 44 then
										tab._description = child
									end
								end
							end
						end
						if tab._heading then
							local titleWidth = math.max(
								0,
								width - 48 - (separateActions and 0 or actionsWidth) - (stacked and 0 or cardWidth + 12)
							)
							tab._heading.Position = UDim2.fromOffset(24, 20 + actionsOffset)
							if tab._description then
								tab._description.Position = UDim2.fromOffset(24, 44 + actionsOffset)
							end
							tab._heading.Size = UDim2.fromOffset(titleWidth, 24)
							if tab._description then
								tab._description.Size = UDim2.fromOffset(titleWidth, 16)
							end
						end
						if tab.List then
							if not tab._websiteListPosition then
								tab._websiteListPosition = tab.List.Position
								tab._websiteListSize = tab.List.Size
							end
							local position, size = tab._websiteListPosition, tab._websiteListSize
							tab.List.Position = UDim2.new(
								position.X.Scale,
								position.X.Offset,
								position.Y.Scale,
								position.Y.Offset + extra
							)
							tab.List.Size = UDim2.new(size.X.Scale, size.X.Offset, size.Y.Scale, size.Y.Offset - extra)
						end
					end
				end)
			end
			self._layoutWebsiteCard = layout
			connect(topbar:GetPropertyChangedSignal("AbsoluteSize"), layout)
			connect(actions:GetPropertyChangedSignal("AbsoluteSize"), layout)
			connect(caption:GetPropertyChangedSignal("TextBounds"), layout)
			connect(self._native.Scale:GetPropertyChangedSignal("Scale"), layout)
			connect(self._native.Content.ChildAdded, layout)
			self.TabModule:OnChange(layout)
			local hovered = false
			connect(card.MouseEnter, function()
				hovered = true
				border.Color = UIEngine.Theme.StrokeHover
				card.BackgroundColor3 = UIEngine.Theme.Surface3
			end)
			connect(card.MouseLeave, function()
				hovered = false
				border.Color = UIEngine.Theme.Stroke
				card.BackgroundColor3 = UIEngine.Theme.Surface2
			end)
			local feedback = 0
			connect(card.Activated, function()
				if window._destroyed then
					return
				end
				local copied = call(window._websiteCardCallback)
				if copied ~= true then
					return
				end
				feedback += 1
				local generation = feedback
				setIcon(icon, "check", UIEngine.Theme.Success)
				border.Color = UIEngine.Theme.Success
				task.delay(1.2, function()
					if window._destroyed or not icon.Parent or generation ~= feedback then
						return
					end
					setIcon(icon, "globe", UIEngine.Theme.Muted)
					border.Color = hovered and UIEngine.Theme.StrokeHover or UIEngine.Theme.Stroke
				end)
			end)
			layout()
			return card
		end

		function WindowMethods:Section(config)
			config = type(config) == "table" and config or { Title = tostring(config or "") }
			self._sidebarOrder += 1
			local group = new("Frame", {
				Name = config.Title or "SidebarSection",
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				LayoutOrder = self._sidebarOrder,
				Parent = self._native.TabList,
			})
			new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4), Parent = group })
			local header = new("TextButton", {
				Name = "Header",
				Size = UDim2.new(1, 0, 0, 30),
				BackgroundTransparency = 1,
				Text = "",
				FontFace = UIEngine.Fonts.Bold,
				TextSize = 12,
				TextColor3 = UIEngine.Theme.Text,
				TextXAlignment = Enum.TextXAlignment.Left,
				AutoButtonColor = false,
				LayoutOrder = 1,
				Parent = group,
			})
			local title = new("TextLabel", {
				Name = "Title",
				Text = config.Title or "",
				Size = UDim2.new(1, -20, 1, 0),
				BackgroundTransparency = 1,
				FontFace = UIEngine.Fonts.Bold,
				TextSize = 12,
				TextColor3 = UIEngine.Theme.Text,
				TextXAlignment = Enum.TextXAlignment.Left,
				RichText = true,
				Parent = header,
			})
			header:SetAttribute("NoDrag", true)
			local icon = new("ImageLabel", {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -2, 0.5, 0),
				Size = UDim2.fromOffset(14, 14),
				BackgroundTransparency = 1,
				Parent = header,
			})
			setIcon(icon, "chevron-right", UIEngine.Theme.Muted)
			local list = new("Frame", {
				Name = "Tabs",
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				LayoutOrder = 2,
				Visible = config.Opened == true,
				Parent = group,
			})
			new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4), Parent = list })
			local section = {
				Title = config.Title,
				Frame = group,
				Instance = group,
				Holder = group,
				_list = list,
				_context = self,
				_window = self,
				_children = {},
				_connections = {},
				UIElements = { Main = group, Title = title, Header = header, Container = list },
				Locked = config.Locked == true,
				Opened = config.Opened == true,
			}
			setmetatable(section, { __index = ControlMethods })
			function section:SetOpened(opened)
				self.Opened = opened == true
				list.Visible = self.Opened
				icon.Rotation = self.Opened and 90 or 0
				return self
			end
			section.Open = function(self)
				return self:SetOpened(true)
			end
			section.Close = function(self)
				return self:SetOpened(false)
			end
			section.SetOpen = section.SetOpened
			section:SetOpened(section.Opened)
			section._connections[#section._connections + 1] = connect(header.Activated, function()
				if not section.Locked then
					section:SetOpened(not section.Opened)
				end
			end)
			self._children[section] = true
			self._sidebarSection = section
			return section
		end

		function WindowMethods:Tab(config)
			config = config or {}
			local iconThemed = config.IconThemed
			if iconThemed == nil then
				iconThemed = not (
					type(config.Icon) == "string"
					and (
						config.Icon:match("^rbxassetid://")
						or config.Icon:match("^rbxasset://")
						or config.Icon:match("^rbxthumb://")
						or config.Icon:match("^https?://")
					)
				)
			end
			local native = self._native:CreateTab({
				Name = config.Title or config.Name,
				Desc = config.Desc,
				Icon = config.Icon,
				IconThemed = iconThemed,
				EmptyText = config.CustomEmptyPage and config.CustomEmptyPage.Desc or "Preparando os controles",
			})
			return self:_wrapTab(native, config, iconThemed)
		end

		function WindowMethods:_wrapTab(native, config, iconThemed)
			if native._icon then
				native._icon:SetAttribute("UIUnthemed", not iconThemed)
			end
			local parent = self._sidebarSection
			if parent then
				native._button.Parent = parent._list
			end
			self._sidebarOrder += 1
			native._button.LayoutOrder = parent and #self.TabModule.Tabs + 1 or self._sidebarOrder
			local tab = context(self, native, native._page)
			tab.Title, tab.Name = config.Title or config.Name, config.Title or config.Name
			tab.Index = #self.TabModule.Tabs + 1
			tab._nativeTab = native
			tab._sidebarSection = parent
			tab.UIElements.Button, tab.UIElements.TabButton = native._button, native._button
			tab.UIElements.Title = native._label
			tab.Locked = config.Locked == true
			self.TabModule.Tabs[tab.Index] = tab
			self.TabModule.Containers[tab.Index] = native._page
			self._tabsByNative[native] = tab
			if self._layoutWebsiteCard then
				self._layoutWebsiteCard()
			end

			function tab:Select()
				self._window._native:SelectTab(self._nativeTab)
				return self
			end

			function tab:SetTitle(title)
				self.Title = tostring(title)
				self.Name = self.Title
				native._label.Text = self.Title
				return self
			end
			if tab.Locked then
				native._button.Interactable = false
				native._label.TextTransparency = 0.6
			end
			return tab
		end

		function WindowMethods:CreateHomeTab(config)
			if self.HomeTab then
				return self.HomeTab
			end
			config = config or {}
			config.Name = config.Title or config.Name or "Início"
			config.Icon = config.Icon or "house"
			config.Welcome = config.Welcome or "Olá, "
			local hour = tonumber(os.date("%H")) or 12
			config.Greeting = config.Greeting
				or (hour < 12 and "Bom dia." or hour < 18 and "Boa tarde." or "Boa noite.")
			config.SectionName = config.SectionName or "Informações do sistema"
			config.Labels = config.Labels
				or {
					FPS = "FPS",
					Ping = "Ping",
					Executor = "Executor",
					Game = "Jogo",
					Time = "Horário",
					Players = "Jogadores",
					Uptime = "Tempo de sessão",
					Memory = "Memória Luau",
				}
			local native = self._native:_buildHome(config)
			if config.Dashboard then
				self._native:_styleDashboardHome(native, config)
			end
			local tab = self:_wrapTab(native, { Title = config.Name, Icon = config.Icon }, true)
			self.HomeTab = tab
			return tab
		end

		function WindowMethods:SetHomeActions(actions)
			local home = self.HomeTab and self.HomeTab._nativeTab
			if not home or not home._dashboard then
				return false
			end
			home._homeActions = actions or {}
			return true
		end

		function WindowMethods:SetHomeActionState(id, busy, description)
			local home = self.HomeTab and self.HomeTab._nativeTab
			local control = home and home._dashboardControls and home._dashboardControls[id]
			if not control then
				return false
			end
			control.Button.Interactable = busy ~= true
			control.Button.Active = busy ~= true
			control.Button.BackgroundTransparency = busy and 0.35 or 0.06
			if description then
				control.Description.Text = description
			end
			return true
		end

		function WindowMethods:SelectDefaultTab()
			if self.HomeTab and not self._destroyed then
				self.HomeTab:Select()
			end
			return self
		end

		function WindowMethods:Destroy(external)
			if self._destroyed then
				return
			end
			self:_setToggleKeyCapture(false)
			self._destroyed = true
			Library._destroyed = true
			local children = {}
			for child in pairs(self._children) do
				children[#children + 1] = child
			end
			for _, child in ipairs(children) do
				child:Destroy()
			end
			local controls = {}
			for control in pairs(Library._controls) do
				controls[#controls + 1] = control
			end
			for _, control in ipairs(controls) do
				control:Destroy()
			end
			for connection in pairs(Library._connections) do
				connection:Disconnect()
			end
			Library._connections = {}
			if external then
				self._native._destroyed = true
				for _, connection in ipairs(self._native._connections) do
					connection:Disconnect()
				end
				self._native._connections = {}
				for index, window in ipairs(UIEngine.Windows) do
					if window == self._native then
						table.remove(UIEngine.Windows, index)
						break
					end
				end
			else
				self._native:Destroy()
			end
			self.PendingFlags = {}
			Library.ScreenGui = nil
			call(self._onDestroy)
		end

		function Library:Destroy()
			if self.Window then
				return self.Window:Destroy()
			end
		end

		function Library:CreateWindow(config)
			assert(not self.Window, "Só é possível criar uma janela de UI por instância")
			config = config or {}
			self:SetTheme(config.Theme or self:GetCurrentTheme() or "Dark")
			UIEngine.Assets.Logo = config.Icon or "rbxassetid://97170941541314"
			local native = UIEngine:CreateWindow({
				Name = config.Title or "Interface",
				LoadingSubtitle = config.Author,
				Icon = UIEngine.Assets.Logo,
				Size = config.Size,
				MinSize = config.MinSize,
				MaxSize = config.MaxSize,
				ToggleUIKeybind = Enum.KeyCode.Unknown,
				KeepOnScreen = config.KeepOnScreen == true,
				Responsive = config.Responsive ~= false,
				OpenButton = false,
				Loading = false,
				Parent = self._parent,
				MaxNotifications = config.MaxNotifications or 3,
				ConfigurationSaving = { Enabled = false },
			})
			native.Gui.Enabled = false
			self.ScreenGui = native.Gui
			native.Body.Name = "Main"
			local sidebar = native.Body:FindFirstChild("Sidebar")
			local header = sidebar:FindFirstChild("Header")
			local originalLabels = textLabels(header)
			local left = new(
				"Frame",
				{ Name = "Left", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = header }
			)
			local titleGroup = new("Frame", {
				Name = "Title",
				Position = UDim2.fromOffset(60, 25),
				Size = UDim2.new(1, -64, 0, 40),
				BackgroundTransparency = 1,
				Parent = left,
			})
			for index, label in ipairs(originalLabels) do
				label.Name = index == 1 and "Title" or "Author"
				label.Parent = titleGroup
				label.Position = UDim2.fromOffset(0, index == 1 and 0 or 20)
				label.Size = UDim2.new(1, 0, 0, index == 1 and 20 or 14)
				label.TextTruncate = Enum.TextTruncate.None
			end
			for _, image in ipairs(header:GetChildren()) do
				if image:IsA("ImageLabel") then
					image.Parent = left
					image.ImageColor3 = Color3.new(1, 1, 1)
				end
			end
			local topbar = new("Frame", {
				Name = "UITopbar",
				Size = UDim2.new(1, 0, 0, 48),
				BackgroundTransparency = 1,
				Parent = native.Content,
			})
			native.DragHandles = { header, topbar }
			local right = new("Frame", {
				Name = "Right",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -12, 0.5, 0),
				Size = UDim2.new(0, 0, 1, 0),
				AutomaticSize = Enum.AutomaticSize.X,
				BackgroundTransparency = 1,
				Parent = topbar,
			})
			new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Right,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 4),
				Parent = right,
			})
			local window = {
				_native = native,
				_children = {},
				_tabsByNative = {},
				_sidebarOrder = 0,
				PendingFlags = {},
				Title = config.Title,
				Folder = config.Folder,
				UIElements = { Main = native.Root, Header = header, Topbar = topbar, Content = native.Content },
				WindUI = self,
				["\065\105\114\102\108\111\119"] = UIEngine,
				TabModule = { Tabs = {}, Containers = {}, _listeners = {} },
			}
			window._window = window
			setmetatable(window, {
				__index = function(object, key)
					if key == "CurrentTab" then
						return object._currentIndex
					end
					if key == "Closed" then
						return not native.Open
					end
					if key == "Destroyed" then
						return object._destroyed == true
					end
					return WindowMethods[key]
				end,
				__newindex = function(object, key, value)
					if key == "CurrentTab" then
						rawset(object, "_currentIndex", value)
						if value == nil then
							native:_settleTransition()
							local previous = native.CurrentTab
							if previous then
								previous._button.BackgroundTransparency = 1
								previous._stroke.Transparency = 1
								previous._label.TextColor3 = UIEngine.Theme.Muted
								if previous._icon and previous._iconThemed then
									previous._icon.ImageColor3 = UIEngine.Theme.Muted
								end
							end
							native.Indicator.Visible = false
							native.CurrentTab = nil
						end
					else
						rawset(object, key, value)
					end
				end,
			})
			function window.TabModule:OnChange(callback)
				self._listeners[#self._listeners + 1] = callback
				return window
			end

			function window.TabModule:Select(index)
				local tab = self.Tabs[index]
				if tab then
					native:SelectTab(tab._nativeTab)
				end
			end
			local nativeSelect = native.SelectTab
			native.SelectTab = function(object, selected)
				local tab = window._tabsByNative[selected]
				if window._destroyed or (tab and tab.Locked) then
					return
				end
				if tab and tab._sidebarSection then
					tab._sidebarSection:SetOpened(true)
				end
				nativeSelect(object, selected)
				if window._layoutWebsiteCard then
					window._layoutWebsiteCard()
				end
				if tab then
					rawset(window, "_currentIndex", tab.Index)
					window.TabModule.SelectedTab = tab.Index
					for _, item in ipairs(window.TabModule.Tabs) do
						item.Selected = item == tab
					end
					for _, callback in ipairs(window.TabModule._listeners) do
						call(callback, tab.Index)
					end
				end
			end
			local nativeToggle = native.Toggle
			window._notifiedOpen = false
			local function notifyVisibility()
				if window._destroyed then
					return
				end
				local opened = native.Open and native.Gui.Enabled
				if not opened and window._capturingToggleKey then
					window:_setToggleKeyCapture(false)
				end
				if opened == window._notifiedOpen then
					return
				end
				window._notifiedOpen = opened
				call(opened and window._onOpen or window._onClose)
			end
			native.Toggle = function(object, open)
				if window._destroyed then
					return
				end
				nativeToggle(object, open)
				notifyVisibility()
			end
			connect(native.Gui:GetPropertyChangedSignal("Enabled"), notifyVisibility)
			connect(native.Gui.Destroying, function()
				if not window._destroyed then
					window:Destroy(true)
				end
			end)
			window.ConfigManager = createConfigManager(window, config.Folder or "Interface")
			self.Window = window
			window._capturingToggleKey = false
			window:UpdateToggleKeyDisplay(Enum.KeyCode.Z)
			local keyChip = native._keyChipLabel.Parent
			local keyPicker = new("TextButton", {
				Name = "ToggleKeyInput",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Text = "",
				AutoButtonColor = false,
				ZIndex = 5,
				Parent = keyChip,
			})
			keyPicker:SetAttribute("NoDrag", true)
			window.UIElements.ToggleKeyInput = keyPicker
			connect(keyPicker.Activated, function()
				window:_setToggleKeyCapture(not window._capturingToggleKey)
			end)
			connect(UserInputService.InputBegan, function(input)
				if
					window._destroyed
					or not window._capturingToggleKey
					or input.UserInputType ~= Enum.UserInputType.Keyboard
				then
					return
				end
				local keyCode = input.KeyCode
				if keyCode == Enum.KeyCode.Unknown then
					return
				end
				native._consumedKey, native._consumedAt = keyCode, os.clock()
				if keyCode ~= Enum.KeyCode.Escape then
					local accepted = true
					if window._onToggleKeyChanged then
						accepted = call(window._onToggleKeyChanged, keyCode.Name)
					else
						native:SetKeybind(keyCode)
					end
					if accepted ~= false then
						window:UpdateToggleKeyDisplay(keyCode)
					end
				end
				window._capturingToggleKey = false
				native._keyChipLabel.Text = (window._toggleKey or Enum.KeyCode.Z).Name
				task.defer(function()
					if not window._destroyed then
						call(window._onToggleKeyCapture, false)
					end
				end)
			end)
			native.RequestClose = function()
				return window:RequestClose()
			end
			local closeButton = native.CloseButton
			closeButton.Name = "Fechar"
			closeButton.Text = ""
			closeButton.AnchorPoint = Vector2.zero
			closeButton.Position = UDim2.fromOffset(0, 0)
			closeButton.Size = UDim2.fromOffset(28, 28)
			closeButton.LayoutOrder = 992
			closeButton:SetAttribute("NoDrag", true)
			closeButton.Parent = right
			local closePadding = closeButton:FindFirstChildOfClass("UIPadding")
			if closePadding then
				closePadding:Destroy()
			end
			for _, rotation in ipairs({ 45, -45 }) do
				new("Frame", {
					Name = "Glyph",
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromOffset(12, 2),
					Rotation = rotation,
					BorderSizePixel = 0,
					BackgroundColor3 = UIEngine.Theme.Muted,
					ZIndex = closeButton.ZIndex + 1,
					Parent = closeButton,
				})
			end
			window.UIElements.CloseButton = closeButton
			local minimize = window:CreateTopbarButton("Minimizar", "", function()
				window:Close()
			end, 991)
			window.UIElements.MinimizeButton = minimize
			new("Frame", {
				Name = "Glyph",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(12, 2),
				BorderSizePixel = 0,
				BackgroundColor3 = UIEngine.Theme.Muted,
				ZIndex = minimize.ZIndex + 1,
				Parent = minimize,
			})
			window:SetToTheCenter()
			window:CreateWebsiteCard()
			self:SetNotificationLower(false)
			for _, notification in ipairs(self._pendingNotifications or {}) do
				self:Notify(notification)
			end
			self._pendingNotifications = nil
			return window
		end
		Library:SetTheme("Mono")
		return Library
	end
end)()
return AdapterFactory(UIEngine, ThemeFactory, Palette, Runtime)
