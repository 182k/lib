local STORAGE_ROOT = "\109\105\099\104\105\103\117\110\046\120\121\122"
local STORAGE_PATH_ERROR = "Armazenamento indisponível (ERRO UI-01) [Contate a dona]"
local STORAGE_IO_ERROR = "Armazenamento indisponível (ERRO UI-02) [Contate a dona]"

-- A failed control must not prevent the other interface resources from being released.
local function releaseInterfaceResource(callback, ...)
	local ok, failure = pcall(callback, ...)
	if not ok then warn("Michigun: falha ao liberar interface: " .. tostring(failure)) end
	return ok
end

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

local uppercaseLetters = {
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
local function uppercasePortuguese(value)
	local result = string.upper(tostring(value))
	result = string.gsub(result, "\195[\128-\191]", uppercaseLetters)
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
	Accent = "#E6E6E6",
	AccentSoft = "#DCDCDC",
	Primary = "#505050",
	Background = "#101010",
	BackgroundDeep = "#121212",
	BackgroundAlt = "#141414",
	Panel = "#141414",
	Surface = "#141414",
	SurfaceRaised = "#181818",
	Hover = "#282828",
	Border = "#242424",
	Text = "#E8E8E8",
	Muted = "#828282",
	Subtle = "#828282",
	Success = "#C8C8C8",
	Warning = "#DCDCDC",
	Danger = "#F0F0F0",
}
local RuntimeFactory = (function()
	return function()
		local environment
		if type(getgenv) == "function" then
			local success, value = pcall(getgenv)
			if success and type(value) == "table" then
				environment = value
			end
		end
		if not environment then
			environment = getfenv()
		end

		local function firstFunction(...)
			for index = 1, select("#", ...) do
				local value = select(index, ...)
				if type(value) == "function" then
					return value
				end
			end
			return nil
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
	NativeLibrary.Navigation = table.freeze({Accent = Color3.fromRGB(208, 208, 208), Fill = Color3.fromRGB(35, 35, 35), Edge = Color3.fromRGB(94, 94, 94), Foreground = Color3.fromRGB(232, 232, 232)})
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
		{ Shadow = "rbxassetid://6014261993", Glow = "rbxassetid://8992230677", Logo = "rbxassetid://115139843331828" }
	-- Roblox assets published by icons.rest; embedded to avoid runtime code downloads.
	local IconsRestPack = { Icons = {
		["a-arrow-down"] = "rbxassetid://87834851353233",
		["a-arrow-up"] = "rbxassetid://89385437396694",
		["accessibility"] = "rbxassetid://109960743825561",
		["activity"] = "rbxassetid://137527339160230",
		["activity-square"] = "rbxassetid://126953951117387",
		["airplay"] = "rbxassetid://92171397431531",
		["air-vent"] = "rbxassetid://111625153433818",
		["a-large-small"] = "rbxassetid://73183249747960",
		["alarm-check"] = "rbxassetid://130501077167542",
		["alarm-clock"] = "rbxassetid://118636480109240",
		["alarm-clock-check"] = "rbxassetid://70976944787280",
		["alarm-clock-minus"] = "rbxassetid://70856300954858",
		["alarm-clock-off"] = "rbxassetid://110132709107464",
		["alarm-clock-plus"] = "rbxassetid://96736786697131",
		["alarm-minus"] = "rbxassetid://77271404005062",
		["alarm-plus"] = "rbxassetid://128528043300240",
		["alarm-smoke"] = "rbxassetid://76581519928624",
		["album"] = "rbxassetid://112445622428637",
		["alert-circle"] = "rbxassetid://74115333842618",
		["alert-octagon"] = "rbxassetid://138910404523272",
		["alert-triangle"] = "rbxassetid://112102474509324",
		["align-center"] = "rbxassetid://120408521883501",
		["align-center-horizontal"] = "rbxassetid://108597166812858",
		["align-center-vertical"] = "rbxassetid://121154206034694",
		["align-end-horizontal"] = "rbxassetid://99069601868832",
		["align-end-vertical"] = "rbxassetid://117942349521535",
		["align-horizontal-distribute-center"] = "rbxassetid://77482483036009",
		["align-horizontal-distribute-end"] = "rbxassetid://134639979863642",
		["align-horizontal-distribute-start"] = "rbxassetid://134435692726811",
		["align-horizontal-justify-center"] = "rbxassetid://92390581039957",
		["align-horizontal-justify-end"] = "rbxassetid://104340168067575",
		["align-horizontal-justify-start"] = "rbxassetid://78939447794797",
		["align-horizontal-space-around"] = "rbxassetid://80515421591545",
		["align-horizontal-space-between"] = "rbxassetid://114038806348167",
		["align-justify"] = "rbxassetid://92373371786861",
		["align-left"] = "rbxassetid://136554315335959",
		["align-right"] = "rbxassetid://135067010612236",
		["align-start-horizontal"] = "rbxassetid://96834758740744",
		["align-start-vertical"] = "rbxassetid://123458513293976",
		["align-vertical-distribute-center"] = "rbxassetid://90818078154247",
		["align-vertical-distribute-end"] = "rbxassetid://136782098795781",
		["align-vertical-distribute-start"] = "rbxassetid://134480830300767",
		["align-vertical-justify-center"] = "rbxassetid://130298876730417",
		["align-vertical-justify-end"] = "rbxassetid://100777246465864",
		["align-vertical-justify-start"] = "rbxassetid://123693071723398",
		["align-vertical-space-around"] = "rbxassetid://124225977511288",
		["align-vertical-space-between"] = "rbxassetid://81499787439793",
		["ambulance"] = "rbxassetid://103392162911629",
		["ampersand"] = "rbxassetid://76900943277226",
		["ampersands"] = "rbxassetid://86469233094518",
		["anchor"] = "rbxassetid://127378493192461",
		["angry"] = "rbxassetid://79345553086407",
		["annoyed"] = "rbxassetid://104846682265434",
		["antenna"] = "rbxassetid://112766612909532",
		["anvil"] = "rbxassetid://86432599455606",
		["aperture"] = "rbxassetid://139684165362622",
		["apple"] = "rbxassetid://93203750625654",
		["app-window"] = "rbxassetid://87635787215081",
		["app-window-mac"] = "rbxassetid://108549782746996",
		["archive"] = "rbxassetid://137249944163344",
		["archive-restore"] = "rbxassetid://96820254661076",
		["archive-x"] = "rbxassetid://134784309661522",
		["area-chart"] = "rbxassetid://107486186614989",
		["armchair"] = "rbxassetid://104852764227195",
		["arrow-big-down"] = "rbxassetid://134387593103194",
		["arrow-big-down-dash"] = "rbxassetid://125189777214718",
		["arrow-big-left"] = "rbxassetid://79012356613282",
		["arrow-big-left-dash"] = "rbxassetid://132879301629314",
		["arrow-big-right"] = "rbxassetid://90405262165720",
		["arrow-big-right-dash"] = "rbxassetid://121488142481379",
		["arrow-big-up"] = "rbxassetid://95689861013321",
		["arrow-big-up-dash"] = "rbxassetid://106976910180035",
		["arrow-down"] = "rbxassetid://134161790366779",
		["arrow-down-0-1"] = "rbxassetid://140381370510884",
		["arrow-down-1-0"] = "rbxassetid://130494621181478",
		["arrow-down-a-z"] = "rbxassetid://103554859233661",
		["arrow-down-circle"] = "rbxassetid://131404694292521",
		["arrow-down-from-line"] = "rbxassetid://81443516391691",
		["arrow-down-left"] = "rbxassetid://102509297349411",
		["arrow-down-left-from-circle"] = "rbxassetid://73012719459961",
		["arrow-down-left-square"] = "rbxassetid://90976696713068",
		["arrow-down-narrow-wide"] = "rbxassetid://71046418862578",
		["arrow-down-right"] = "rbxassetid://72764732196403",
		["arrow-down-right-from-circle"] = "rbxassetid://97668995487103",
		["arrow-down-right-square"] = "rbxassetid://128499661363473",
		["arrow-down-square"] = "rbxassetid://138838216140198",
		["arrow-down-to-dot"] = "rbxassetid://88868273845458",
		["arrow-down-to-line"] = "rbxassetid://137644743820952",
		["arrow-down-up"] = "rbxassetid://117405374619280",
		["arrow-down-wide-narrow"] = "rbxassetid://75826372885867",
		["arrow-down-z-a"] = "rbxassetid://118359795316087",
		["arrow-left"] = "rbxassetid://90293255250749",
		["arrow-left-circle"] = "rbxassetid://130847257582775",
		["arrow-left-from-line"] = "rbxassetid://77381869318221",
		["arrow-left-right"] = "rbxassetid://112517617090898",
		["arrow-left-square"] = "rbxassetid://135104418905606",
		["arrow-left-to-line"] = "rbxassetid://130252021035812",
		["arrow-right"] = "rbxassetid://134908902120212",
		["arrow-right-circle"] = "rbxassetid://94365145580321",
		["arrow-right-from-line"] = "rbxassetid://107378199607331",
		["arrow-right-left"] = "rbxassetid://111890422557630",
		["arrow-right-square"] = "rbxassetid://115337431423227",
		["arrow-right-to-line"] = "rbxassetid://103829994761864",
		["arrows-up-from-line"] = "rbxassetid://140178313470659",
		["arrow-up"] = "rbxassetid://104406213770080",
		["arrow-up-0-1"] = "rbxassetid://139178256421912",
		["arrow-up-1-0"] = "rbxassetid://97298977768167",
		["arrow-up-a-z"] = "rbxassetid://97443044644659",
		["arrow-up-circle"] = "rbxassetid://75833692771331",
		["arrow-up-down"] = "rbxassetid://73746166761985",
		["arrow-up-from-dot"] = "rbxassetid://103317134268223",
		["arrow-up-from-line"] = "rbxassetid://101711387260955",
		["arrow-up-left"] = "rbxassetid://103783370700580",
		["arrow-up-left-from-circle"] = "rbxassetid://96382098119619",
		["arrow-up-left-square"] = "rbxassetid://101543880954604",
		["arrow-up-narrow-wide"] = "rbxassetid://122289869517959",
		["arrow-up-right"] = "rbxassetid://115214649052675",
		["arrow-up-right-from-circle"] = "rbxassetid://102906718956851",
		["arrow-up-right-square"] = "rbxassetid://113196521639031",
		["arrow-up-square"] = "rbxassetid://112280252781879",
		["arrow-up-to-line"] = "rbxassetid://135365442561417",
		["arrow-up-wide-narrow"] = "rbxassetid://79052928363256",
		["arrow-up-z-a"] = "rbxassetid://93443333447390",
		["asterisk"] = "rbxassetid://107247711733329",
		["atom"] = "rbxassetid://119051552929078",
		["at-sign"] = "rbxassetid://94614469252449",
		["audio-lines"] = "rbxassetid://133487746892141",
		["audio-waveform"] = "rbxassetid://135412900878575",
		["award"] = "rbxassetid://82039875682356",
		["axe"] = "rbxassetid://84931585672806",
		["axis-3d"] = "rbxassetid://83328523632480",
		["baby"] = "rbxassetid://75683742350958",
		["backpack"] = "rbxassetid://76143965140765",
		["badge"] = "rbxassetid://78791133479661",
		["badge-alert"] = "rbxassetid://92904571921902",
		["badge-cent"] = "rbxassetid://110902979965426",
		["badge-check"] = "rbxassetid://76305757263548",
		["badge-dollar-sign"] = "rbxassetid://123225256208806",
		["badge-euro"] = "rbxassetid://82107326159074",
		["badge-help"] = "rbxassetid://83944903318576",
		["badge-indian-rupee"] = "rbxassetid://105958255216505",
		["badge-info"] = "rbxassetid://109792483526167",
		["badge-japanese-yen"] = "rbxassetid://96156476341857",
		["badge-minus"] = "rbxassetid://79191240000290",
		["badge-percent"] = "rbxassetid://129993801535784",
		["badge-plus"] = "rbxassetid://73308743105191",
		["badge-pound-sterling"] = "rbxassetid://104904198937382",
		["badge-russian-ruble"] = "rbxassetid://91738909980749",
		["badge-swiss-franc"] = "rbxassetid://102826901242684",
		["badge-x"] = "rbxassetid://117187082865205",
		["baggage-claim"] = "rbxassetid://119346910227968",
		["ban"] = "rbxassetid://109685306480139",
		["banana"] = "rbxassetid://128374499714074",
		["banknote"] = "rbxassetid://113703117675594",
		["bar-chart"] = "rbxassetid://121570259716677",
		["bar-chart-2"] = "rbxassetid://121452498735866",
		["bar-chart-3"] = "rbxassetid://130626786024244",
		["bar-chart-4"] = "rbxassetid://96221317327213",
		["bar-chart-big"] = "rbxassetid://119295298711810",
		["bar-chart-horizontal"] = "rbxassetid://109235174327898",
		["bar-chart-horizontal-big"] = "rbxassetid://139737497124066",
		["barcode"] = "rbxassetid://78580529416152",
		["baseline"] = "rbxassetid://116347038683714",
		["bath"] = "rbxassetid://89008182357290",
		["battery"] = "rbxassetid://102599812606554",
		["battery-charging"] = "rbxassetid://91402957855599",
		["battery-full"] = "rbxassetid://108407180588179",
		["battery-low"] = "rbxassetid://132416805088817",
		["battery-medium"] = "rbxassetid://139407584675024",
		["battery-warning"] = "rbxassetid://119084304752903",
		["beaker"] = "rbxassetid://100026072450383",
		["bean"] = "rbxassetid://108654318985558",
		["bean-off"] = "rbxassetid://75755103997845",
		["bed"] = "rbxassetid://71982795501399",
		["bed-double"] = "rbxassetid://97693190540435",
		["bed-single"] = "rbxassetid://80557330573152",
		["beef"] = "rbxassetid://93001452038647",
		["beer"] = "rbxassetid://71718925718592",
		["beer-off"] = "rbxassetid://135309228180602",
		["bell"] = "rbxassetid://84691420588185",
		["bell-dot"] = "rbxassetid://100564215426004",
		["bell-electric"] = "rbxassetid://120584905231603",
		["bell-minus"] = "rbxassetid://117849268875449",
		["bell-off"] = "rbxassetid://115540031372596",
		["bell-plus"] = "rbxassetid://85655293455454",
		["bell-ring"] = "rbxassetid://71006419366158",
		["between-horizontal-end"] = "rbxassetid://97454674221809",
		["between-horizontal-start"] = "rbxassetid://122308710081740",
		["between-vertical-end"] = "rbxassetid://73288142609772",
		["between-vertical-start"] = "rbxassetid://96319480553759",
		["bike"] = "rbxassetid://139392597724277",
		["binary"] = "rbxassetid://73887562333653",
		["biohazard"] = "rbxassetid://137351193301090",
		["bird"] = "rbxassetid://78301366757596",
		["bitcoin"] = "rbxassetid://87905951788220",
		["blend"] = "rbxassetid://99774242136996",
		["blinds"] = "rbxassetid://97128563480198",
		["blocks"] = "rbxassetid://116361302503360",
		["bluetooth"] = "rbxassetid://140648462080543",
		["bluetooth-connected"] = "rbxassetid://108047104997672",
		["bluetooth-off"] = "rbxassetid://85384277884353",
		["bluetooth-searching"] = "rbxassetid://88887842293685",
		["bold"] = "rbxassetid://114571598098097",
		["bolt"] = "rbxassetid://134172358414310",
		["bomb"] = "rbxassetid://85112456002145",
		["bone"] = "rbxassetid://110911138031483",
		["book"] = "rbxassetid://74111869099427",
		["book-a"] = "rbxassetid://130683776374615",
		["book-audio"] = "rbxassetid://84765914852101",
		["book-check"] = "rbxassetid://116693733550590",
		["book-copy"] = "rbxassetid://103556293898971",
		["book-dashed"] = "rbxassetid://90144560974060",
		["book-down"] = "rbxassetid://102612840928328",
		["book-headphones"] = "rbxassetid://101847018803943",
		["book-heart"] = "rbxassetid://79225550955168",
		["book-image"] = "rbxassetid://97175021450327",
		["book-key"] = "rbxassetid://78825638323167",
		["book-lock"] = "rbxassetid://136914298397858",
		["bookmark"] = "rbxassetid://137439152875860",
		["bookmark-check"] = "rbxassetid://103743627936816",
		["book-marked"] = "rbxassetid://130311722822005",
		["bookmark-minus"] = "rbxassetid://106761186502279",
		["bookmark-plus"] = "rbxassetid://108572239011289",
		["bookmark-x"] = "rbxassetid://115354177404954",
		["book-minus"] = "rbxassetid://111140800790677",
		["book-open"] = "rbxassetid://84762150530577",
		["book-open-check"] = "rbxassetid://100175521109916",
		["book-open-text"] = "rbxassetid://83251408532985",
		["book-plus"] = "rbxassetid://135397977794739",
		["book-text"] = "rbxassetid://96481772943887",
		["book-type"] = "rbxassetid://80135728169729",
		["book-up"] = "rbxassetid://92592832226795",
		["book-up-2"] = "rbxassetid://74123009075829",
		["book-user"] = "rbxassetid://80586093636888",
		["book-x"] = "rbxassetid://75485266769989",
		["boom-box"] = "rbxassetid://88874304172044",
		["bot"] = "rbxassetid://70979486241131",
		["bot-message-square"] = "rbxassetid://79709292282995",
		["box"] = "rbxassetid://117371753006597",
		["boxes"] = "rbxassetid://95055252135506",
		["box-select"] = "rbxassetid://106969329058115",
		["braces"] = "rbxassetid://92263187057993",
		["brackets"] = "rbxassetid://87406077670628",
		["brain"] = "rbxassetid://116902501990569",
		["brain-circuit"] = "rbxassetid://130830898675113",
		["brain-cog"] = "rbxassetid://76347059769903",
		["brick-wall"] = "rbxassetid://94677898150825",
		["briefcase"] = "rbxassetid://78701740878808",
		["briefcase-business"] = "rbxassetid://83989706459460",
		["briefcase-medical"] = "rbxassetid://101696204417639",
		["bring-to-front"] = "rbxassetid://105016868447258",
		["brush"] = "rbxassetid://113475652218451",
		["bug"] = "rbxassetid://75649814233484",
		["bug-off"] = "rbxassetid://72963988065933",
		["bug-play"] = "rbxassetid://109066688101101",
		["building"] = "rbxassetid://128630485814878",
		["building-2"] = "rbxassetid://97744948701888",
		["bus"] = "rbxassetid://115040051931434",
		["bus-front"] = "rbxassetid://89834398235413",
		["cable"] = "rbxassetid://122718774070506",
		["cable-car"] = "rbxassetid://75378206085314",
		["cake"] = "rbxassetid://88535465840262",
		["cake-slice"] = "rbxassetid://99501344714989",
		["calculator"] = "rbxassetid://107281102048400",
		["calendar"] = "rbxassetid://126460151885084",
		["calendar-check"] = "rbxassetid://116665691227418",
		["calendar-check-2"] = "rbxassetid://128139765113287",
		["calendar-clock"] = "rbxassetid://91678408267921",
		["calendar-days"] = "rbxassetid://83005303274935",
		["calendar-fold"] = "rbxassetid://120622111767156",
		["calendar-heart"] = "rbxassetid://101728896191412",
		["calendar-minus"] = "rbxassetid://97111317408323",
		["calendar-minus-2"] = "rbxassetid://114139960753026",
		["calendar-off"] = "rbxassetid://72690038281381",
		["calendar-plus"] = "rbxassetid://113126930241503",
		["calendar-plus-2"] = "rbxassetid://95708816339251",
		["calendar-range"] = "rbxassetid://85814519406070",
		["calendar-search"] = "rbxassetid://94105486063910",
		["calendar-x"] = "rbxassetid://117555084312063",
		["calendar-x-2"] = "rbxassetid://137455674513711",
		["camera"] = "rbxassetid://114084146151777",
		["camera-off"] = "rbxassetid://101456706369049",
		["candlestick-chart"] = "rbxassetid://99842864833044",
		["candy"] = "rbxassetid://113164012451432",
		["candy-cane"] = "rbxassetid://125416183674924",
		["candy-off"] = "rbxassetid://122702931937344",
		["captions"] = "rbxassetid://105023593632540",
		["captions-off"] = "rbxassetid://75480095441780",
		["car"] = "rbxassetid://91451724283877",
		["caravan"] = "rbxassetid://78521421981947",
		["car-front"] = "rbxassetid://79993076477613",
		["carrot"] = "rbxassetid://71122235024925",
		["car-taxi-front"] = "rbxassetid://75623233937291",
		["case-lower"] = "rbxassetid://95359311197985",
		["case-sensitive"] = "rbxassetid://133603526051277",
		["case-upper"] = "rbxassetid://77340278207531",
		["cassette-tape"] = "rbxassetid://113140472253110",
		["cast"] = "rbxassetid://119573692041871",
		["castle"] = "rbxassetid://104598700669384",
		["cat"] = "rbxassetid://118339348494810",
		["cctv"] = "rbxassetid://84978679477516",
		["check"] = "rbxassetid://86817768619372",
		["check-check"] = "rbxassetid://101885204738917",
		["check-circle"] = "rbxassetid://105979545056636",
		["check-circle-2"] = "rbxassetid://76928915955542",
		["check-square"] = "rbxassetid://135686334400788",
		["check-square-2"] = "rbxassetid://84113739446686",
		["chef-hat"] = "rbxassetid://94153362248387",
		["cherry"] = "rbxassetid://116326418543667",
		["chevron-down"] = "rbxassetid://71457658246709",
		["chevron-down-circle"] = "rbxassetid://130642617728982",
		["chevron-down-square"] = "rbxassetid://84683053234548",
		["chevron-first"] = "rbxassetid://70831710633364",
		["chevron-last"] = "rbxassetid://102556054621077",
		["chevron-left"] = "rbxassetid://102314312897830",
		["chevron-left-circle"] = "rbxassetid://70732746220332",
		["chevron-left-square"] = "rbxassetid://78492542000164",
		["chevron-right"] = "rbxassetid://101007429951147",
		["chevron-right-circle"] = "rbxassetid://87038574131735",
		["chevron-right-square"] = "rbxassetid://119136642030742",
		["chevrons-down"] = "rbxassetid://84492998086101",
		["chevrons-down-up"] = "rbxassetid://82103880591342",
		["chevrons-left"] = "rbxassetid://87881912126351",
		["chevrons-left-right"] = "rbxassetid://132331219761704",
		["chevrons-right"] = "rbxassetid://134353805354361",
		["chevrons-right-left"] = "rbxassetid://96783734429291",
		["chevrons-up"] = "rbxassetid://88461690106632",
		["chevrons-up-down"] = "rbxassetid://71880540200693",
		["chevron-up"] = "rbxassetid://98648581502859",
		["chevron-up-circle"] = "rbxassetid://111681831848531",
		["circle-arrow-down"] = "rbxassetid://129076838165145",
		["circle-arrow-left"] = "rbxassetid://88796613571531",
		["circle-arrow-out-down-left"] = "rbxassetid://107231337431973",
		["circle-arrow-out-down-right"] = "rbxassetid://70490689174861",
		["circle-arrow-out-up-left"] = "rbxassetid://79479678307645",
		["circle-arrow-out-up-right"] = "rbxassetid://127093834620465",
		["circle-arrow-right"] = "rbxassetid://97664127355280",
		["circle-arrow-up"] = "rbxassetid://72634350793509",
		["circle-check"] = "rbxassetid://88244323237265",
		["circle-check-big"] = "rbxassetid://105847305799404",
		["circle-chevron-down"] = "rbxassetid://88531529614731",
		["circle-chevron-left"] = "rbxassetid://109806050128867",
		["circle-chevron-right"] = "rbxassetid://130159833971034",
		["circle-chevron-up"] = "rbxassetid://126990996679640",
		["circle-dashed"] = "rbxassetid://122032109800866",
		["circle-divide"] = "rbxassetid://136980096833105",
		["circle-dollar-sign"] = "rbxassetid://102720278203768",
		["circle-dot"] = "rbxassetid://122878673716704",
		["circle-dot-dashed"] = "rbxassetid://107222591318022",
		["circle-ellipsis"] = "rbxassetid://72989868902667",
		["circle-equal"] = "rbxassetid://83415595687523",
		["circle-fading-plus"] = "rbxassetid://97734885169321",
		["circle-gauge"] = "rbxassetid://79712667314679",
		["circle-help"] = "rbxassetid://132353516577418",
		["circle-minus"] = "rbxassetid://98163850412523",
		["circle-off"] = "rbxassetid://95467094528299",
		["circle-parking"] = "rbxassetid://117482323268433",
		["circle-parking-off"] = "rbxassetid://80459013698184",
		["circle-pause"] = "rbxassetid://88794740338426",
		["circle-percent"] = "rbxassetid://125429815212970",
		["circle-play"] = "rbxassetid://84481789029543",
		["circle-plus"] = "rbxassetid://117262167984222",
		["circle-power"] = "rbxassetid://127349877206105",
		["circle-slash"] = "rbxassetid://98431785453122",
		["circle-slash-2"] = "rbxassetid://79541029224240",
		["circle-stop"] = "rbxassetid://109423106908446",
		["circle-user"] = "rbxassetid://87167719100614",
		["circle-user-round"] = "rbxassetid://113831490904568",
		["circle-x"] = "rbxassetid://106305483906363",
		["circuit-board"] = "rbxassetid://124136951218642",
		["citrus"] = "rbxassetid://79624448772527",
		["clapperboard"] = "rbxassetid://132343838416956",
		["clipboard"] = "rbxassetid://105021692319787",
		["clipboard-check"] = "rbxassetid://90432969741774",
		["clipboard-copy"] = "rbxassetid://85387882337161",
		["clipboard-edit"] = "rbxassetid://131193135046966",
		["clipboard-list"] = "rbxassetid://129402512748462",
		["clipboard-minus"] = "rbxassetid://94779294031183",
		["clipboard-paste"] = "rbxassetid://79192963603923",
		["clipboard-pen"] = "rbxassetid://99195778697194",
		["clipboard-pen-line"] = "rbxassetid://103555830963651",
		["clipboard-plus"] = "rbxassetid://74352366953056",
		["clipboard-signature"] = "rbxassetid://120750772696869",
		["clipboard-type"] = "rbxassetid://132835545998943",
		["clipboard-x"] = "rbxassetid://132658738057667",
		["clock"] = "rbxassetid://136533241128438",
		["clock-1"] = "rbxassetid://71498600757409",
		["clock-10"] = "rbxassetid://123641121766955",
		["clock-11"] = "rbxassetid://85845500811663",
		["clock-12"] = "rbxassetid://133878455420257",
		["clock-2"] = "rbxassetid://102975079908275",
		["clock-3"] = "rbxassetid://119663119982527",
		["clock-4"] = "rbxassetid://108792000100666",
		["clock-5"] = "rbxassetid://97840714155038",
		["clock-6"] = "rbxassetid://102025123837297",
		["clock-7"] = "rbxassetid://110824271252901",
		["clock-8"] = "rbxassetid://123515589399454",
		["clock-9"] = "rbxassetid://126662391246112",
		["cloud"] = "rbxassetid://136524873450824",
		["cloud-cog"] = "rbxassetid://108438517119798",
		["cloud-download"] = "rbxassetid://78768373704516",
		["cloud-drizzle"] = "rbxassetid://80789072164434",
		["cloud-fog"] = "rbxassetid://110403642693501",
		["cloud-hail"] = "rbxassetid://95998880244047",
		["cloud-lightning"] = "rbxassetid://118391347029403",
		["cloud-moon"] = "rbxassetid://120156057895579",
		["cloud-moon-rain"] = "rbxassetid://101513348432910",
		["cloud-off"] = "rbxassetid://111796785870393",
		["cloud-rain"] = "rbxassetid://130177212410873",
		["cloud-rain-wind"] = "rbxassetid://87893934921731",
		["cloud-snow"] = "rbxassetid://104971371973617",
		["cloud-sun"] = "rbxassetid://140109651313859",
		["cloud-sun-rain"] = "rbxassetid://132138781511885",
		["cloud-upload"] = "rbxassetid://86452290950086",
		["cloudy"] = "rbxassetid://132267475821363",
		["clover"] = "rbxassetid://128291338532394",
		["club"] = "rbxassetid://83110975306436",
		["code"] = "rbxassetid://75851496262862",
		["code-2"] = "rbxassetid://79541605299928",
		["codepen"] = "rbxassetid://131077252082543",
		["codesandbox"] = "rbxassetid://139298967633423",
		["code-xml"] = "rbxassetid://106124864132557",
		["coffee"] = "rbxassetid://125329933348791",
		["cog"] = "rbxassetid://123222732420633",
		["coins"] = "rbxassetid://117341212186115",
		["columns"] = "rbxassetid://96838631255058",
		["columns-2"] = "rbxassetid://110924811097991",
		["columns-3"] = "rbxassetid://88214025452433",
		["columns-4"] = "rbxassetid://100379574150921",
		["combine"] = "rbxassetid://103133480717944",
		["command"] = "rbxassetid://90385430770591",
		["compass"] = "rbxassetid://73836660434977",
		["component"] = "rbxassetid://106556990975641",
		["computer"] = "rbxassetid://72888027377165",
		["concierge-bell"] = "rbxassetid://134373387272639",
		["cone"] = "rbxassetid://80255197365555",
		["construction"] = "rbxassetid://77845797691565",
		["contact"] = "rbxassetid://102372888309353",
		["contact-2"] = "rbxassetid://100454539997812",
		["contact-round"] = "rbxassetid://117599766367773",
		["container"] = "rbxassetid://135116917100753",
		["contrast"] = "rbxassetid://71154426791470",
		["cookie"] = "rbxassetid://96083862569395",
		["cooking-pot"] = "rbxassetid://100393801714299",
		["copy"] = "rbxassetid://116378866141355",
		["copy-check"] = "rbxassetid://92397569046734",
		["copyleft"] = "rbxassetid://103019482632984",
		["copy-minus"] = "rbxassetid://75815893695780",
		["copy-plus"] = "rbxassetid://138173295478363",
		["copyright"] = "rbxassetid://82044483134605",
		["copy-slash"] = "rbxassetid://74395410823283",
		["copy-x"] = "rbxassetid://98741265066436",
		["corner-down-left"] = "rbxassetid://105689000447775",
		["corner-down-right"] = "rbxassetid://82061714010896",
		["corner-left-down"] = "rbxassetid://133517193053100",
		["corner-left-up"] = "rbxassetid://78035789940893",
		["corner-right-down"] = "rbxassetid://135390474501786",
		["corner-right-up"] = "rbxassetid://122661540167291",
		["corner-up-left"] = "rbxassetid://72973602941956",
		["corner-up-right"] = "rbxassetid://108297458644964",
		["cpu"] = "rbxassetid://105237370909681",
		["creative-commons"] = "rbxassetid://111243376462256",
		["credit-card"] = "rbxassetid://124946887228472",
		["croissant"] = "rbxassetid://77683374738482",
		["crop"] = "rbxassetid://121481502611712",
		["cross"] = "rbxassetid://93673591064028",
		["crosshair"] = "rbxassetid://83752373575368",
		["crown"] = "rbxassetid://92253403464658",
		["cuboid"] = "rbxassetid://117329818290748",
		["cup-soda"] = "rbxassetid://132120247880161",
		["currency"] = "rbxassetid://96706001818192",
		["cylinder"] = "rbxassetid://99158693669056",
		["database"] = "rbxassetid://99154172590159",
		["diamond"] = "rbxassetid://136889727768904",
		["diamond-percent"] = "rbxassetid://138695404542126",
		["dice-1"] = "rbxassetid://133629376866649",
		["dice-2"] = "rbxassetid://137517882571271",
		["dice-3"] = "rbxassetid://128612626459042",
		["dice-4"] = "rbxassetid://73117400593570",
		["dice-5"] = "rbxassetid://107643287892749",
		["dice-6"] = "rbxassetid://112067139297943",
		["dices"] = "rbxassetid://116678154854810",
		["diff"] = "rbxassetid://122850860032588",
		["disc"] = "rbxassetid://77318106935130",
		["disc-2"] = "rbxassetid://135460247355994",
		["disc-3"] = "rbxassetid://118087373340436",
		["disc-album"] = "rbxassetid://101298984360789",
		["divide"] = "rbxassetid://134571770296218",
		["divide-circle"] = "rbxassetid://115849848955050",
		["divide-square"] = "rbxassetid://78617148972524",
		["dna"] = "rbxassetid://131581201333424",
		["dna-off"] = "rbxassetid://90101733367858",
		["dock"] = "rbxassetid://96133720652582",
		["dog"] = "rbxassetid://123749328846346",
		["dollar-sign"] = "rbxassetid://74567340201672",
		["donut"] = "rbxassetid://123909563150383",
		["door-closed"] = "rbxassetid://118483980594708",
		["door-open"] = "rbxassetid://124230332524625",
		["dot"] = "rbxassetid://105006331197983",
		["download"] = "rbxassetid://109698732019071",
		["download-cloud"] = "rbxassetid://122841052352556",
		["drafting-compass"] = "rbxassetid://110585086142082",
		["drama"] = "rbxassetid://138828515077300",
		["dribbble"] = "rbxassetid://112906380564504",
		["drill"] = "rbxassetid://113833078477512",
		["droplet"] = "rbxassetid://91586468475195",
		["droplets"] = "rbxassetid://117720354071548",
		["drum"] = "rbxassetid://121019656655547",
		["drumstick"] = "rbxassetid://106711459328737",
		["dumbbell"] = "rbxassetid://130873531670678",
		["ear"] = "rbxassetid://92631431780796",
		["ear-off"] = "rbxassetid://81480882487332",
		["earth"] = "rbxassetid://75025349205767",
		["earth-lock"] = "rbxassetid://103673515494330",
		["eclipse"] = "rbxassetid://113566298471092",
		["egg"] = "rbxassetid://103880404435578",
		["egg-fried"] = "rbxassetid://137654273789326",
		["egg-off"] = "rbxassetid://99146230558760",
		["ellipsis"] = "rbxassetid://95127553964880",
		["ellipsis-vertical"] = "rbxassetid://95771045694204",
		["equal"] = "rbxassetid://79273099065269",
		["eraser"] = "rbxassetid://71210100060694",
		["euro"] = "rbxassetid://139202392240827",
		["expand"] = "rbxassetid://107643532357936",
		["external-link"] = "rbxassetid://78664150174274",
		["eye"] = "rbxassetid://127234874352422",
		["eye-off"] = "rbxassetid://85207295981701",
		["facebook"] = "rbxassetid://98822363427090",
		["factory"] = "rbxassetid://79319339232812",
		["fan"] = "rbxassetid://76323281744636",
		["fast-forward"] = "rbxassetid://131011550754955",
		["feather"] = "rbxassetid://103991922506350",
		["fence"] = "rbxassetid://90935998613863",
		["ferris-wheel"] = "rbxassetid://94538249337586",
		["figma"] = "rbxassetid://103020132259719",
		["file"] = "rbxassetid://108499043987115",
		["file-archive"] = "rbxassetid://78133118745021",
		["file-audio"] = "rbxassetid://101306436065858",
		["file-audio-2"] = "rbxassetid://103353018363480",
		["file-axis-3d"] = "rbxassetid://136107008496948",
		["file-badge"] = "rbxassetid://135829024450190",
		["file-badge-2"] = "rbxassetid://87916835926622",
		["file-bar-chart"] = "rbxassetid://92900624303400",
		["file-bar-chart-2"] = "rbxassetid://133337118425916",
		["file-box"] = "rbxassetid://102441183584476",
		["file-check"] = "rbxassetid://91719007832323",
		["file-check-2"] = "rbxassetid://120611252466724",
		["file-clock"] = "rbxassetid://101240345040794",
		["file-code"] = "rbxassetid://93918366472395",
		["file-code-2"] = "rbxassetid://77999709917415",
		["file-cog"] = "rbxassetid://130835463141181",
		["file-diff"] = "rbxassetid://132890714271689",
		["file-digit"] = "rbxassetid://108016195781167",
		["file-down"] = "rbxassetid://79495546108963",
		["file-edit"] = "rbxassetid://82156880342025",
		["file-heart"] = "rbxassetid://138364329637312",
		["file-image"] = "rbxassetid://83675710276234",
		["file-input"] = "rbxassetid://78561929224193",
		["file-json"] = "rbxassetid://98868866618869",
		["file-json-2"] = "rbxassetid://92610524789574",
		["file-key"] = "rbxassetid://83249504215614",
		["file-key-2"] = "rbxassetid://103006369640378",
		["file-line-chart"] = "rbxassetid://84182680444173",
		["file-lock"] = "rbxassetid://140186307068344",
		["file-lock-2"] = "rbxassetid://126656887901996",
		["file-minus"] = "rbxassetid://138371877961417",
		["file-minus-2"] = "rbxassetid://107551117550330",
		["file-music"] = "rbxassetid://107180630571772",
		["file-output"] = "rbxassetid://109566424197143",
		["file-pen"] = "rbxassetid://134577965177665",
		["file-pen-line"] = "rbxassetid://90852962587361",
		["file-pie-chart"] = "rbxassetid://94554256943610",
		["file-plus"] = "rbxassetid://74194167957081",
		["file-plus-2"] = "rbxassetid://111571245681686",
		["file-question"] = "rbxassetid://128415338385227",
		["files"] = "rbxassetid://78685849153126",
		["file-scan"] = "rbxassetid://132590981389921",
		["file-search"] = "rbxassetid://131130928074464",
		["file-search-2"] = "rbxassetid://139930116408040",
		["file-signature"] = "rbxassetid://87096324580559",
		["file-sliders"] = "rbxassetid://133181135528313",
		["file-spreadsheet"] = "rbxassetid://117808207510717",
		["file-stack"] = "rbxassetid://132187715148899",
		["file-symlink"] = "rbxassetid://122206323516270",
		["file-terminal"] = "rbxassetid://91847143440556",
		["file-text"] = "rbxassetid://92774566080911",
		["file-type"] = "rbxassetid://139551268989315",
		["file-type-2"] = "rbxassetid://91173675777316",
		["file-up"] = "rbxassetid://99191463679083",
		["file-video"] = "rbxassetid://105252283775469",
		["file-video-2"] = "rbxassetid://130213998083954",
		["file-volume"] = "rbxassetid://119603558694315",
		["file-volume-2"] = "rbxassetid://139949156797892",
		["file-warning"] = "rbxassetid://89824347717079",
		["file-x"] = "rbxassetid://117124390222574",
		["file-x-2"] = "rbxassetid://136449417648465",
		["film"] = "rbxassetid://120941801045330",
		["filter"] = "rbxassetid://100930784445785",
		["filter-x"] = "rbxassetid://85838104400923",
		["fingerprint"] = "rbxassetid://109514257830136",
		["fire-extinguisher"] = "rbxassetid://84862159260845",
		["fish"] = "rbxassetid://114555142566431",
		["fish-off"] = "rbxassetid://99443044829026",
		["fish-symbol"] = "rbxassetid://123702927226939",
		["flag"] = "rbxassetid://121835250831612",
		["flag-off"] = "rbxassetid://90046025355940",
		["flag-triangle-left"] = "rbxassetid://73117581559482",
		["flag-triangle-right"] = "rbxassetid://106524126597496",
		["flame"] = "rbxassetid://125012650497883",
		["flame-kindling"] = "rbxassetid://136834319064926",
		["flashlight"] = "rbxassetid://110881718712443",
		["flashlight-off"] = "rbxassetid://117038550056668",
		["flask-conical"] = "rbxassetid://115528123394259",
		["flask-conical-off"] = "rbxassetid://102385597737770",
		["flask-round"] = "rbxassetid://118701306736141",
		["flip-horizontal"] = "rbxassetid://76347241876815",
		["flip-horizontal-2"] = "rbxassetid://107329750779249",
		["flip-vertical"] = "rbxassetid://121575310281690",
		["flip-vertical-2"] = "rbxassetid://77578710261033",
		["flower"] = "rbxassetid://98459040977090",
		["flower-2"] = "rbxassetid://79478214327919",
		["focus"] = "rbxassetid://116191961683883",
		["folder"] = "rbxassetid://77937190465422",
		["folder-archive"] = "rbxassetid://96956679126324",
		["folder-check"] = "rbxassetid://95477621394824",
		["folder-clock"] = "rbxassetid://137926892639070",
		["folder-closed"] = "rbxassetid://86427718056887",
		["folder-cog"] = "rbxassetid://127866486547434",
		["folder-dot"] = "rbxassetid://129773010201383",
		["folder-down"] = "rbxassetid://82793534945672",
		["folder-edit"] = "rbxassetid://102495189191583",
		["folder-git"] = "rbxassetid://104507928948019",
		["folder-git-2"] = "rbxassetid://85014883332248",
		["folder-heart"] = "rbxassetid://110088173047332",
		["folder-input"] = "rbxassetid://132837435930621",
		["folder-kanban"] = "rbxassetid://138103158509024",
		["folder-key"] = "rbxassetid://130401922270021",
		["folder-lock"] = "rbxassetid://111493727654155",
		["folder-minus"] = "rbxassetid://97790081587083",
		["folder-open"] = "rbxassetid://112237915867403",
		["folder-open-dot"] = "rbxassetid://90332268376865",
		["folder-output"] = "rbxassetid://125946013402264",
		["folder-pen"] = "rbxassetid://81838874164795",
		["folder-plus"] = "rbxassetid://71462957431660",
		["folder-root"] = "rbxassetid://80403663819762",
		["folders"] = "rbxassetid://97828544806816",
		["folder-search"] = "rbxassetid://109602276944932",
		["folder-search-2"] = "rbxassetid://74614286288240",
		["folder-symlink"] = "rbxassetid://89907141903257",
		["folder-sync"] = "rbxassetid://137088423628527",
		["folder-tree"] = "rbxassetid://78199416535568",
		["folder-up"] = "rbxassetid://85416900334449",
		["folder-x"] = "rbxassetid://103887939759350",
		["fold-horizontal"] = "rbxassetid://133102230855922",
		["fold-vertical"] = "rbxassetid://128556601978376",
		["footprints"] = "rbxassetid://80792036653047",
		["forklift"] = "rbxassetid://117529645336183",
		["form-input"] = "rbxassetid://73368443063193",
		["forward"] = "rbxassetid://78301309129142",
		["frame"] = "rbxassetid://81913255681858",
		["framer"] = "rbxassetid://117525065607897",
		["frown"] = "rbxassetid://88589722723911",
		["fuel"] = "rbxassetid://112915457104961",
		["fullscreen"] = "rbxassetid://92176335589571",
		["function-square"] = "rbxassetid://77009803117016",
		["gallery-horizontal"] = "rbxassetid://113964455804231",
		["gallery-horizontal-end"] = "rbxassetid://125589356860308",
		["gallery-thumbnails"] = "rbxassetid://123093292028306",
		["gallery-vertical"] = "rbxassetid://109130466006021",
		["gallery-vertical-end"] = "rbxassetid://122352399696695",
		["gamepad"] = "rbxassetid://81482768981191",
		["gamepad-2"] = "rbxassetid://99293705721130",
		["gantt-chart"] = "rbxassetid://122456724985241",
		["gantt-chart-square"] = "rbxassetid://73571197135748",
		["gauge"] = "rbxassetid://128279962545721",
		["gauge-circle"] = "rbxassetid://110231832967256",
		["gavel"] = "rbxassetid://118993398179839",
		["gem"] = "rbxassetid://125353572203968",
		["ghost"] = "rbxassetid://132705178126217",
		["gift"] = "rbxassetid://87706885156127",
		["git-branch"] = "rbxassetid://101518089376526",
		["git-branch-plus"] = "rbxassetid://127909649257701",
		["git-commit-horizontal"] = "rbxassetid://91306319670540",
		["git-commit-vertical"] = "rbxassetid://101185915909200",
		["git-compare"] = "rbxassetid://134611228556653",
		["git-compare-arrows"] = "rbxassetid://134203912676625",
		["git-fork"] = "rbxassetid://138214272765755",
		["git-graph"] = "rbxassetid://126789259203618",
		["github"] = "rbxassetid://140138081031269",
		["gitlab"] = "rbxassetid://109316577965403",
		["git-merge"] = "rbxassetid://118868315103570",
		["git-pull-request"] = "rbxassetid://117991178843732",
		["git-pull-request-arrow"] = "rbxassetid://133155768650667",
		["git-pull-request-closed"] = "rbxassetid://74188383635944",
		["git-pull-request-create"] = "rbxassetid://108540858735398",
		["git-pull-request-create-arrow"] = "rbxassetid://75317536980451",
		["git-pull-request-draft"] = "rbxassetid://127220095778670",
		["glasses"] = "rbxassetid://77027406085123",
		["glass-water"] = "rbxassetid://125170765146614",
		["globe"] = "rbxassetid://125685532120024",
		["globe-2"] = "rbxassetid://112945472486319",
		["globe-lock"] = "rbxassetid://96469366281710",
		["goal"] = "rbxassetid://90015442702200",
		["grab"] = "rbxassetid://117741873625250",
		["graduation-cap"] = "rbxassetid://140187510907091",
		["grape"] = "rbxassetid://73195418744413",
		["grid-2x2"] = "rbxassetid://134599229810680",
		["grid-3x3"] = "rbxassetid://108197747587523",
		["grip"] = "rbxassetid://88188569450143",
		["grip-horizontal"] = "rbxassetid://72027364608348",
		["grip-vertical"] = "rbxassetid://136050395759142",
		["group"] = "rbxassetid://79946652686375",
		["guitar"] = "rbxassetid://135654565391445",
		["ham"] = "rbxassetid://134057117057030",
		["hammer"] = "rbxassetid://73956316105509",
		["hand"] = "rbxassetid://83088528355903",
		["hand-coins"] = "rbxassetid://85922324710029",
		["hand-heart"] = "rbxassetid://124155721578457",
		["hand-helping"] = "rbxassetid://95094264299544",
		["hand-metal"] = "rbxassetid://105555696144202",
		["hand-platter"] = "rbxassetid://101356141176839",
		["handshake"] = "rbxassetid://121760224402586",
		["hard-drive"] = "rbxassetid://115211376876196",
		["hard-drive-download"] = "rbxassetid://115854711953657",
		["hard-drive-upload"] = "rbxassetid://112990104477043",
		["hard-hat"] = "rbxassetid://105207891316460",
		["hash"] = "rbxassetid://128945191245705",
		["haze"] = "rbxassetid://86624380139587",
		["hdmi-port"] = "rbxassetid://123935181216786",
		["heading"] = "rbxassetid://115666667306834",
		["heading-1"] = "rbxassetid://82056941503516",
		["heading-2"] = "rbxassetid://109194333144049",
		["heading-3"] = "rbxassetid://86456694536830",
		["heading-4"] = "rbxassetid://108808532352504",
		["heading-5"] = "rbxassetid://84468448396475",
		["heading-6"] = "rbxassetid://70885434512827",
		["headphones"] = "rbxassetid://89990513082092",
		["headset"] = "rbxassetid://77155289443816",
		["heart"] = "rbxassetid://88525382655929",
		["heart-crack"] = "rbxassetid://78532998725036",
		["heart-handshake"] = "rbxassetid://88807882205984",
		["heart-off"] = "rbxassetid://121500734414824",
		["heart-pulse"] = "rbxassetid://101116623654468",
		["heater"] = "rbxassetid://75867015789217",
		["help-circle"] = "rbxassetid://71693802872044",
		["helping-hand"] = "rbxassetid://82838882533396",
		["hexagon"] = "rbxassetid://111932983587355",
		["highlighter"] = "rbxassetid://124195908160173",
		["history"] = "rbxassetid://70375455140492",
		["home"] = "rbxassetid://109841253338329",
		["hop"] = "rbxassetid://87886892027508",
		["hop-off"] = "rbxassetid://124047203843704",
		["hospital"] = "rbxassetid://100542468114469",
		["hotel"] = "rbxassetid://88463240253197",
		["hourglass"] = "rbxassetid://135654740495171",
		["ice-cream"] = "rbxassetid://95314536020685",
		["ice-cream-2"] = "rbxassetid://93935347717656",
		["ice-cream-bowl"] = "rbxassetid://116507918255217",
		["ice-cream-cone"] = "rbxassetid://72823870951577",
		["image"] = "rbxassetid://114022611279795",
		["image-down"] = "rbxassetid://91697762317652",
		["image-minus"] = "rbxassetid://111691180013117",
		["image-off"] = "rbxassetid://113890586559666",
		["image-plus"] = "rbxassetid://131640557457656",
		["images"] = "rbxassetid://87539822715105",
		["image-up"] = "rbxassetid://95362531246536",
		["import"] = "rbxassetid://87776530532335",
		["inbox"] = "rbxassetid://131993988107472",
		["indent"] = "rbxassetid://111431763044113",
		["indent-decrease"] = "rbxassetid://77902371540680",
		["indent-increase"] = "rbxassetid://116043459584133",
		["indian-rupee"] = "rbxassetid://121515804799242",
		["infinity"] = "rbxassetid://77975814002740",
		["info"] = "rbxassetid://120620848266512",
		["inspection-panel"] = "rbxassetid://93487140703578",
		["instagram"] = "rbxassetid://88504800931130",
		["italic"] = "rbxassetid://96844815325902",
		["iteration-ccw"] = "rbxassetid://114475186061127",
		["iteration-cw"] = "rbxassetid://130833288197698",
		["japanese-yen"] = "rbxassetid://108845518454015",
		["joystick"] = "rbxassetid://75024649968329",
		["kanban"] = "rbxassetid://132557744047883",
		["kanban-square"] = "rbxassetid://124564901729634",
		["kanban-square-dashed"] = "rbxassetid://134205902924289",
		["key"] = "rbxassetid://83474888140571",
		["keyboard"] = "rbxassetid://121978468376124",
		["keyboard-music"] = "rbxassetid://74763240290099",
		["key-round"] = "rbxassetid://116918931002434",
		["key-square"] = "rbxassetid://79693131186843",
		["lamp"] = "rbxassetid://123765123149989",
		["lamp-ceiling"] = "rbxassetid://120174084956571",
		["lamp-desk"] = "rbxassetid://125995036157694",
		["lamp-floor"] = "rbxassetid://102217348025530",
		["lamp-wall-down"] = "rbxassetid://134067530649420",
		["lamp-wall-up"] = "rbxassetid://101034120941267",
		["landmark"] = "rbxassetid://130189940998950",
		["land-plot"] = "rbxassetid://114974071140535",
		["languages"] = "rbxassetid://130065428637597",
		["laptop"] = "rbxassetid://103798905446648",
		["laptop-2"] = "rbxassetid://106021728338003",
		["laptop-minimal"] = "rbxassetid://91920768368168",
		["lasso"] = "rbxassetid://110262485516329",
		["lasso-select"] = "rbxassetid://112600066891219",
		["laugh"] = "rbxassetid://115974660887808",
		["layers"] = "rbxassetid://114499998778667",
		["layers-2"] = "rbxassetid://87219208863328",
		["layers-3"] = "rbxassetid://114549653986465",
		["layout"] = "rbxassetid://75056433029964",
		["layout-dashboard"] = "rbxassetid://70433574792490",
		["layout-grid"] = "rbxassetid://89644754139307",
		["layout-list"] = "rbxassetid://72384664085473",
		["layout-panel-left"] = "rbxassetid://117264898598467",
		["layout-panel-top"] = "rbxassetid://135570881026156",
		["layout-template"] = "rbxassetid://78078135578383",
		["leaf"] = "rbxassetid://70846801126940",
		["leafy-green"] = "rbxassetid://94770162749325",
		["library"] = "rbxassetid://114050057679028",
		["library-big"] = "rbxassetid://135791941822287",
		["library-square"] = "rbxassetid://132158761398954",
		["life-buoy"] = "rbxassetid://99147024142900",
		["ligature"] = "rbxassetid://75804099923602",
		["lightbulb"] = "rbxassetid://98419938500979",
		["lightbulb-off"] = "rbxassetid://126746194476977",
		["line-chart"] = "rbxassetid://115214641333880",
		["link"] = "rbxassetid://86131768436965",
		["link-2"] = "rbxassetid://107339085791087",
		["link-2-off"] = "rbxassetid://74994782779018",
		["linkedin"] = "rbxassetid://102928864661994",
		["list"] = "rbxassetid://101699539545687",
		["list-checks"] = "rbxassetid://133109875194066",
		["list-collapse"] = "rbxassetid://103651151660786",
		["list-end"] = "rbxassetid://116487672075047",
		["list-filter"] = "rbxassetid://83186010624431",
		["list-minus"] = "rbxassetid://119184210915074",
		["list-music"] = "rbxassetid://88988800995482",
		["list-ordered"] = "rbxassetid://100068475590931",
		["list-plus"] = "rbxassetid://124010335412192",
		["list-restart"] = "rbxassetid://91193864293753",
		["list-start"] = "rbxassetid://131366235513143",
		["list-todo"] = "rbxassetid://83287488939815",
		["list-tree"] = "rbxassetid://127759805921507",
		["list-video"] = "rbxassetid://117978552190904",
		["list-x"] = "rbxassetid://115746075160943",
		["loader"] = "rbxassetid://132295854994374",
		["loader-2"] = "rbxassetid://128780061297692",
		["loader-circle"] = "rbxassetid://71250150569964",
		["locate"] = "rbxassetid://106821189831430",
		["locate-fixed"] = "rbxassetid://80648116191645",
		["locate-off"] = "rbxassetid://121088730454886",
		["lock"] = "rbxassetid://119765975153029",
		["lock-keyhole"] = "rbxassetid://135504457058301",
		["lock-keyhole-open"] = "rbxassetid://132192657766903",
		["lock-open"] = "rbxassetid://71186154315213",
		["log-in"] = "rbxassetid://82241120685313",
		["log-out"] = "rbxassetid://140299936053191",
		["lollipop"] = "rbxassetid://102239398934579",
		["luggage"] = "rbxassetid://140614046877100",
		["magnet"] = "rbxassetid://97474941633274",
		["mail"] = "rbxassetid://77537514051485",
		["mailbox"] = "rbxassetid://104064071799815",
		["mail-check"] = "rbxassetid://90824179551389",
		["mail-minus"] = "rbxassetid://104189493909738",
		["mail-open"] = "rbxassetid://74874447671108",
		["mail-plus"] = "rbxassetid://130540869833539",
		["mail-question"] = "rbxassetid://128924135790205",
		["mails"] = "rbxassetid://120925930542398",
		["mail-search"] = "rbxassetid://108269769085404",
		["mail-warning"] = "rbxassetid://126275145590627",
		["mail-x"] = "rbxassetid://97229750262408",
		["map"] = "rbxassetid://131325044235094",
		["map-pin"] = "rbxassetid://137091405832737",
		["map-pinned"] = "rbxassetid://78894827751778",
		["map-pin-off"] = "rbxassetid://130126969919710",
		["martini"] = "rbxassetid://108853683970464",
		["maximize"] = "rbxassetid://116546384863431",
		["maximize-2"] = "rbxassetid://130049637400171",
		["medal"] = "rbxassetid://97534791863003",
		["megaphone"] = "rbxassetid://139746713205639",
		["megaphone-off"] = "rbxassetid://130364738220291",
		["meh"] = "rbxassetid://117127044934876",
		["memory-stick"] = "rbxassetid://82464660673318",
		["menu"] = "rbxassetid://83047518441184",
		["menu-square"] = "rbxassetid://84168857053009",
		["merge"] = "rbxassetid://96640473379848",
		["message-circle"] = "rbxassetid://74163263000218",
		["message-circle-code"] = "rbxassetid://124462142601421",
		["message-circle-dashed"] = "rbxassetid://78559601215727",
		["message-circle-heart"] = "rbxassetid://122100978068245",
		["message-circle-more"] = "rbxassetid://72969556529414",
		["message-circle-off"] = "rbxassetid://106640802525475",
		["message-circle-plus"] = "rbxassetid://97202853233666",
		["message-circle-question"] = "rbxassetid://85003442346058",
		["message-circle-reply"] = "rbxassetid://96024981688039",
		["message-circle-warning"] = "rbxassetid://112239075926369",
		["message-circle-x"] = "rbxassetid://104081317224904",
		["message-square"] = "rbxassetid://86432989388834",
		["message-square-code"] = "rbxassetid://139338315973052",
		["message-square-dashed"] = "rbxassetid://127422492651127",
		["message-square-diff"] = "rbxassetid://120745701209397",
		["message-square-dot"] = "rbxassetid://131246995114947",
		["message-square-heart"] = "rbxassetid://137436561363370",
		["message-square-more"] = "rbxassetid://76812000893936",
		["message-square-off"] = "rbxassetid://97376166485199",
		["message-square-plus"] = "rbxassetid://77957118386462",
		["message-square-quote"] = "rbxassetid://97203851012575",
		["message-square-reply"] = "rbxassetid://138540430807955",
		["message-square-share"] = "rbxassetid://94526690702300",
		["message-square-text"] = "rbxassetid://128095657789286",
		["message-square-warning"] = "rbxassetid://83694786088101",
		["message-square-x"] = "rbxassetid://83972010967159",
		["messages-square"] = "rbxassetid://112345482432498",
		["mic"] = "rbxassetid://125870172276779",
		["mic-2"] = "rbxassetid://79774423165436",
		["mic-off"] = "rbxassetid://84064988822624",
		["microscope"] = "rbxassetid://134078584568005",
		["microwave"] = "rbxassetid://109575331253451",
		["mic-vocal"] = "rbxassetid://116345765074785",
		["milestone"] = "rbxassetid://88614752388873",
		["milk"] = "rbxassetid://119818923307142",
		["milk-off"] = "rbxassetid://72925919409773",
		["minimize"] = "rbxassetid://95555494586098",
		["minimize-2"] = "rbxassetid://96294437144715",
		["minus"] = "rbxassetid://95070996149109",
		["minus-circle"] = "rbxassetid://103303552772654",
		["minus-square"] = "rbxassetid://96983863580751",
		["monitor"] = "rbxassetid://70520152532392",
		["monitor-check"] = "rbxassetid://112341875921743",
		["monitor-dot"] = "rbxassetid://132673547251589",
		["monitor-down"] = "rbxassetid://132502390896673",
		["monitor-off"] = "rbxassetid://95048101284680",
		["monitor-pause"] = "rbxassetid://99458637542686",
		["monitor-play"] = "rbxassetid://107640137618506",
		["monitor-smartphone"] = "rbxassetid://81757216234228",
		["monitor-speaker"] = "rbxassetid://131099454095944",
		["monitor-stop"] = "rbxassetid://99235976282671",
		["monitor-up"] = "rbxassetid://116018518624879",
		["monitor-x"] = "rbxassetid://102604336229610",
		["moon"] = "rbxassetid://98353636264918",
		["moon-star"] = "rbxassetid://137086737657962",
		["more-horizontal"] = "rbxassetid://101330725759187",
		["more-vertical"] = "rbxassetid://76302166494262",
		["mountain"] = "rbxassetid://90592200130155",
		["mountain-snow"] = "rbxassetid://111710418991773",
		["mouse"] = "rbxassetid://122014945028597",
		["mouse-pointer"] = "rbxassetid://113428527051320",
		["mouse-pointer-2"] = "rbxassetid://84070353881242",
		["mouse-pointer-click"] = "rbxassetid://81854854241463",
		["mouse-pointer-square"] = "rbxassetid://112337311970951",
		["mouse-pointer-square-dashed"] = "rbxassetid://80677641664079",
		["move"] = "rbxassetid://77028714324861",
		["move-3d"] = "rbxassetid://82487420092874",
		["move-diagonal"] = "rbxassetid://111179404262244",
		["move-diagonal-2"] = "rbxassetid://128492050787735",
		["move-down"] = "rbxassetid://85099736811132",
		["move-down-left"] = "rbxassetid://138054515129112",
		["move-down-right"] = "rbxassetid://116621809745618",
		["move-horizontal"] = "rbxassetid://136107424781093",
		["move-left"] = "rbxassetid://89444723083105",
		["move-right"] = "rbxassetid://133586722586273",
		["move-up"] = "rbxassetid://76410952730524",
		["move-up-left"] = "rbxassetid://102293680652367",
		["move-up-right"] = "rbxassetid://88087592569369",
		["move-vertical"] = "rbxassetid://92087242547029",
		["m-square"] = "rbxassetid://97856747717836",
		["music"] = "rbxassetid://132132095360900",
		["music-2"] = "rbxassetid://121112248614371",
		["music-3"] = "rbxassetid://75731760539974",
		["music-4"] = "rbxassetid://122935411241955",
		["navigation"] = "rbxassetid://76549947719521",
		["navigation-2"] = "rbxassetid://127270865325663",
		["navigation-2-off"] = "rbxassetid://74005663669130",
		["navigation-off"] = "rbxassetid://96787422854853",
		["network"] = "rbxassetid://110230147673946",
		["newspaper"] = "rbxassetid://115179113478597",
		["nfc"] = "rbxassetid://119131457808272",
		["notebook"] = "rbxassetid://93996170225525",
		["notebook-pen"] = "rbxassetid://70494109504383",
		["notebook-tabs"] = "rbxassetid://113749031276097",
		["notebook-text"] = "rbxassetid://86811328922423",
		["notepad-text"] = "rbxassetid://104957079697866",
		["notepad-text-dashed"] = "rbxassetid://113624610966525",
		["nut"] = "rbxassetid://77621843968987",
		["nut-off"] = "rbxassetid://84877157781266",
		["octagon"] = "rbxassetid://103646759535962",
		["octagon-alert"] = "rbxassetid://101226496664732",
		["octagon-pause"] = "rbxassetid://127095623629829",
		["octagon-x"] = "rbxassetid://103912968479362",
		["option"] = "rbxassetid://77581357923982",
		["orbit"] = "rbxassetid://79200159961573",
		["outdent"] = "rbxassetid://136657573552804",
		["package"] = "rbxassetid://106101842173393",
		["package-2"] = "rbxassetid://76736374924338",
		["package-check"] = "rbxassetid://100671298334773",
		["package-minus"] = "rbxassetid://72114807005321",
		["package-open"] = "rbxassetid://86470175749466",
		["package-plus"] = "rbxassetid://74357376952178",
		["package-search"] = "rbxassetid://108965513580143",
		["package-x"] = "rbxassetid://80178189812476",
		["paintbrush"] = "rbxassetid://113234034461805",
		["paintbrush-2"] = "rbxassetid://116925836096427",
		["paint-bucket"] = "rbxassetid://116536780343642",
		["paint-roller"] = "rbxassetid://76545833297923",
		["palette"] = "rbxassetid://127369887384101",
		["palmtree"] = "rbxassetid://85651135388680",
		["panel-bottom"] = "rbxassetid://86537618399617",
		["panel-bottom-close"] = "rbxassetid://91281796987492",
		["panel-bottom-dashed"] = "rbxassetid://130167117027190",
		["panel-bottom-inactive"] = "rbxassetid://97483023786802",
		["panel-bottom-open"] = "rbxassetid://86549932703136",
		["panel-left"] = "rbxassetid://125599129725759",
		["panel-left-close"] = "rbxassetid://106532774300164",
		["panel-left-dashed"] = "rbxassetid://115976249358122",
		["panel-left-inactive"] = "rbxassetid://102689057283340",
		["panel-left-open"] = "rbxassetid://126704485649345",
		["panel-right"] = "rbxassetid://83386566029978",
		["panel-right-close"] = "rbxassetid://133236216519470",
		["panel-right-dashed"] = "rbxassetid://138321632890167",
		["panel-right-inactive"] = "rbxassetid://95197732140314",
		["panel-right-open"] = "rbxassetid://107436518875633",
		["panels-left-bottom"] = "rbxassetid://100709335124708",
		["panels-right-bottom"] = "rbxassetid://118563843738058",
		["panels-top-left"] = "rbxassetid://119230493302275",
		["panel-top"] = "rbxassetid://80001561556081",
		["panel-top-close"] = "rbxassetid://124467779594157",
		["panel-top-dashed"] = "rbxassetid://79452019243803",
		["panel-top-inactive"] = "rbxassetid://135806161551683",
		["panel-top-open"] = "rbxassetid://88468571469051",
		["paperclip"] = "rbxassetid://101144735754292",
		["parentheses"] = "rbxassetid://117743859847736",
		["parking-circle"] = "rbxassetid://132958171449207",
		["parking-circle-off"] = "rbxassetid://90293787674695",
		["parking-meter"] = "rbxassetid://95540023655686",
		["parking-square"] = "rbxassetid://119709845027214",
		["parking-square-off"] = "rbxassetid://111516007201199",
		["party-popper"] = "rbxassetid://92886643958723",
		["pause"] = "rbxassetid://79610666871575",
		["pause-circle"] = "rbxassetid://121009275520669",
		["pause-octagon"] = "rbxassetid://75691149975017",
		["paw-print"] = "rbxassetid://97578437331341",
		["pc-case"] = "rbxassetid://134071343822649",
		["pen"] = "rbxassetid://101486948449510",
		["pencil"] = "rbxassetid://113132794872298",
		["pencil-line"] = "rbxassetid://97622550721067",
		["pencil-ruler"] = "rbxassetid://83914055949508",
		["pen-line"] = "rbxassetid://108991407462745",
		["pen-square"] = "rbxassetid://124290018373176",
		["pentagon"] = "rbxassetid://133006808893408",
		["pen-tool"] = "rbxassetid://126917951709518",
		["percent"] = "rbxassetid://138143948353522",
		["percent-circle"] = "rbxassetid://120133426400204",
		["percent-diamond"] = "rbxassetid://116484660741674",
		["percent-square"] = "rbxassetid://123104718284792",
		["person-standing"] = "rbxassetid://101118444346965",
		["phone"] = "rbxassetid://110402416146068",
		["phone-call"] = "rbxassetid://83844308787978",
		["phone-forwarded"] = "rbxassetid://121647613341736",
		["phone-incoming"] = "rbxassetid://80024725665109",
		["phone-missed"] = "rbxassetid://79555645036339",
		["phone-off"] = "rbxassetid://124218610436691",
		["phone-outgoing"] = "rbxassetid://107942094735434",
		["pi"] = "rbxassetid://94324814221349",
		["piano"] = "rbxassetid://119387553084830",
		["pickaxe"] = "rbxassetid://111300940329486",
		["picture-in-picture"] = "rbxassetid://131356651374909",
		["picture-in-picture-2"] = "rbxassetid://82685697007608",
		["pie-chart"] = "rbxassetid://102602815840153",
		["piggy-bank"] = "rbxassetid://137519559090410",
		["pilcrow"] = "rbxassetid://73426591830540",
		["pilcrow-square"] = "rbxassetid://104294263901485",
		["pill"] = "rbxassetid://102063979166015",
		["pin"] = "rbxassetid://84152083728286",
		["pin-off"] = "rbxassetid://79775551915820",
		["pipette"] = "rbxassetid://104047428948587",
		["pi-square"] = "rbxassetid://104995627137456",
		["pizza"] = "rbxassetid://137422469806542",
		["plane"] = "rbxassetid://123931033451986",
		["plane-landing"] = "rbxassetid://127564654216931",
		["plane-takeoff"] = "rbxassetid://71424495151201",
		["play"] = "rbxassetid://76386816441302",
		["play-circle"] = "rbxassetid://94679908148591",
		["play-square"] = "rbxassetid://88949301532557",
		["plug"] = "rbxassetid://92495517782055",
		["plug-2"] = "rbxassetid://90278231790155",
		["plug-zap"] = "rbxassetid://120081085677067",
		["plug-zap-2"] = "rbxassetid://114634662672913",
		["plus"] = "rbxassetid://101123124881873",
		["plus-circle"] = "rbxassetid://120968869021626",
		["plus-square"] = "rbxassetid://110356023190006",
		["pocket"] = "rbxassetid://84604104357709",
		["pocket-knife"] = "rbxassetid://75327579226876",
		["podcast"] = "rbxassetid://107827753005302",
		["pointer"] = "rbxassetid://98931495397575",
		["pointer-off"] = "rbxassetid://121208450103912",
		["popcorn"] = "rbxassetid://131831744800890",
		["popsicle"] = "rbxassetid://104185203372496",
		["pound-sterling"] = "rbxassetid://104324833143828",
		["power"] = "rbxassetid://89331085993646",
		["power-circle"] = "rbxassetid://116376776686511",
		["power-off"] = "rbxassetid://71082730746769",
		["power-square"] = "rbxassetid://119684962977179",
		["presentation"] = "rbxassetid://116401163910084",
		["printer"] = "rbxassetid://71465784501775",
		["projector"] = "rbxassetid://73231680903652",
		["proportions"] = "rbxassetid://78144579158638",
		["puzzle"] = "rbxassetid://117598556369229",
		["pyramid"] = "rbxassetid://132485249599747",
		["qr-code"] = "rbxassetid://113440393569209",
		["quote"] = "rbxassetid://131322529504476",
		["rabbit"] = "rbxassetid://114280087699339",
		["radar"] = "rbxassetid://132868138496209",
		["radiation"] = "rbxassetid://100877813176471",
		["radical"] = "rbxassetid://108409175619446",
		["radio"] = "rbxassetid://99420757373028",
		["radio-receiver"] = "rbxassetid://121282639721016",
		["radio-tower"] = "rbxassetid://88833838205757",
		["radius"] = "rbxassetid://74995747675698",
		["rail-symbol"] = "rbxassetid://97316226200213",
		["rainbow"] = "rbxassetid://103765621191575",
		["rat"] = "rbxassetid://87357329634876",
		["ratio"] = "rbxassetid://93282099315884",
		["receipt"] = "rbxassetid://92008292109070",
		["receipt-cent"] = "rbxassetid://112492211580771",
		["receipt-euro"] = "rbxassetid://133191175020669",
		["receipt-indian-rupee"] = "rbxassetid://133266746153788",
		["receipt-japanese-yen"] = "rbxassetid://124042872765776",
		["receipt-pound-sterling"] = "rbxassetid://100101322122623",
		["receipt-russian-ruble"] = "rbxassetid://121506664677675",
		["receipt-swiss-franc"] = "rbxassetid://99002246681862",
		["receipt-text"] = "rbxassetid://100006409297382",
		["rectangle-ellipsis"] = "rbxassetid://107119201863591",
		["rectangle-horizontal"] = "rbxassetid://138840515431449",
		["rectangle-vertical"] = "rbxassetid://105899574411289",
		["recycle"] = "rbxassetid://113939163175897",
		["redo"] = "rbxassetid://109330889951617",
		["redo-2"] = "rbxassetid://139377644547969",
		["redo-dot"] = "rbxassetid://103006780441917",
		["refresh-ccw"] = "rbxassetid://112330254035751",
		["refresh-ccw-dot"] = "rbxassetid://82338761134697",
		["refresh-cw"] = "rbxassetid://106497040962250",
		["refresh-cw-off"] = "rbxassetid://70915551154203",
		["refrigerator"] = "rbxassetid://112780018998815",
		["regex"] = "rbxassetid://134026857287988",
		["remove-formatting"] = "rbxassetid://138608399804923",
		["repeat"] = "rbxassetid://88751041821881",
		["repeat-1"] = "rbxassetid://83172378763568",
		["repeat-2"] = "rbxassetid://103267027937654",
		["replace"] = "rbxassetid://107047557421203",
		["replace-all"] = "rbxassetid://100838712445846",
		["reply"] = "rbxassetid://92729212112550",
		["reply-all"] = "rbxassetid://89383445888953",
		["rewind"] = "rbxassetid://112118266859844",
		["ribbon"] = "rbxassetid://138074895056157",
		["rocket"] = "rbxassetid://109537053598807",
		["rocking-chair"] = "rbxassetid://78801538856684",
		["roller-coaster"] = "rbxassetid://97027135474963",
		["rotate-3d"] = "rbxassetid://97818595741565",
		["rotate-ccw"] = "rbxassetid://75086444429266",
		["rotate-ccw-square"] = "rbxassetid://109860100695153",
		["rotate-cw"] = "rbxassetid://83145058297547",
		["rotate-cw-square"] = "rbxassetid://125618900116298",
		["route"] = "rbxassetid://92054788599928",
		["route-off"] = "rbxassetid://84281383994516",
		["router"] = "rbxassetid://137822323057124",
		["rows"] = "rbxassetid://137919453076186",
		["rows-2"] = "rbxassetid://95783038014917",
		["rows-3"] = "rbxassetid://120887473789104",
		["rows-4"] = "rbxassetid://116714271746099",
		["rss"] = "rbxassetid://133733106949535",
		["ruler"] = "rbxassetid://84633402845324",
		["russian-ruble"] = "rbxassetid://126835196314974",
		["sailboat"] = "rbxassetid://95990070790702",
		["salad"] = "rbxassetid://126822773594847",
		["sandwich"] = "rbxassetid://125331738014611",
		["satellite"] = "rbxassetid://76405829153460",
		["satellite-dish"] = "rbxassetid://80919601328215",
		["save"] = "rbxassetid://122894934359450",
		["save-all"] = "rbxassetid://130108174247404",
		["scale"] = "rbxassetid://104058148891720",
		["scale-3d"] = "rbxassetid://98514591753294",
		["scaling"] = "rbxassetid://101030566996452",
		["scan"] = "rbxassetid://125367266780285",
		["scan-barcode"] = "rbxassetid://97414347978098",
		["scan-eye"] = "rbxassetid://109514269737059",
		["scan-face"] = "rbxassetid://98379048258175",
		["scan-line"] = "rbxassetid://74491678843147",
		["scan-search"] = "rbxassetid://133304136560518",
		["scan-text"] = "rbxassetid://135056446730766",
		["scatter-chart"] = "rbxassetid://74267179296978",
		["school"] = "rbxassetid://127958337382355",
		["school-2"] = "rbxassetid://85807427737192",
		["scissors"] = "rbxassetid://105992192896067",
		["scissors-line-dashed"] = "rbxassetid://136613376152055",
		["scissors-square"] = "rbxassetid://74695197837525",
		["scissors-square-dashed-bottom"] = "rbxassetid://107920465612561",
		["screen-share"] = "rbxassetid://77511025094385",
		["screen-share-off"] = "rbxassetid://121685614490746",
		["scroll"] = "rbxassetid://120140373437385",
		["scroll-text"] = "rbxassetid://93551675076113",
		["search"] = "rbxassetid://72296609649861",
		["search-check"] = "rbxassetid://135876289053244",
		["search-code"] = "rbxassetid://96217854889522",
		["search-slash"] = "rbxassetid://103651057689299",
		["search-x"] = "rbxassetid://107116182495739",
		["send"] = "rbxassetid://94849431195865",
		["send-horizontal"] = "rbxassetid://71350661970492",
		["send-to-back"] = "rbxassetid://128357510439179",
		["separator-horizontal"] = "rbxassetid://138451510103519",
		["separator-vertical"] = "rbxassetid://136594330269338",
		["server"] = "rbxassetid://105706502741449",
		["server-cog"] = "rbxassetid://100022312079887",
		["server-crash"] = "rbxassetid://87758222542375",
		["server-off"] = "rbxassetid://80255747106695",
		["settings"] = "rbxassetid://106205298246017",
		["settings-2"] = "rbxassetid://109485777305919",
		["shapes"] = "rbxassetid://72318824907864",
		["share"] = "rbxassetid://78225483239202",
		["share-2"] = "rbxassetid://139712792470775",
		["sheet"] = "rbxassetid://74805372511449",
		["shell"] = "rbxassetid://103995324275618",
		["shield"] = "rbxassetid://106509993556171",
		["shield-alert"] = "rbxassetid://91754324662625",
		["shield-ban"] = "rbxassetid://124352578023288",
		["shield-check"] = "rbxassetid://71867984579031",
		["shield-ellipsis"] = "rbxassetid://93065391097116",
		["shield-half"] = "rbxassetid://123735656472960",
		["shield-minus"] = "rbxassetid://80388855203128",
		["shield-off"] = "rbxassetid://98525250043109",
		["shield-plus"] = "rbxassetid://121205118266112",
		["shield-question"] = "rbxassetid://114815120818758",
		["shield-x"] = "rbxassetid://75826463279777",
		["ship"] = "rbxassetid://98574156558498",
		["ship-wheel"] = "rbxassetid://130141263234416",
		["shirt"] = "rbxassetid://128162112866809",
		["shopping-bag"] = "rbxassetid://121389568871142",
		["shopping-basket"] = "rbxassetid://110161824939086",
		["shopping-cart"] = "rbxassetid://79435149356304",
		["shovel"] = "rbxassetid://96637119542790",
		["shower-head"] = "rbxassetid://114908638980660",
		["shrink"] = "rbxassetid://115135316516120",
		["shrub"] = "rbxassetid://79864992147519",
		["shuffle"] = "rbxassetid://103735725549548",
		["sigma"] = "rbxassetid://74383416855806",
		["sigma-square"] = "rbxassetid://132360260153111",
		["signal"] = "rbxassetid://126197135689656",
		["signal-high"] = "rbxassetid://93347669262895",
		["signal-low"] = "rbxassetid://84665611291998",
		["signal-medium"] = "rbxassetid://75062813653519",
		["signal-zero"] = "rbxassetid://109850227743382",
		["signpost"] = "rbxassetid://97962937781200",
		["signpost-big"] = "rbxassetid://87216549939239",
		["siren"] = "rbxassetid://81845882921662",
		["skip-back"] = "rbxassetid://137660494219613",
		["skip-forward"] = "rbxassetid://121822124041513",
		["skull"] = "rbxassetid://101060850237115",
		["slack"] = "rbxassetid://107723459729315",
		["slash"] = "rbxassetid://77878973734361",
		["slice"] = "rbxassetid://140518011325498",
		["sliders"] = "rbxassetid://105166722651208",
		["sliders-horizontal"] = "rbxassetid://125396339381135",
		["sliders-vertical"] = "rbxassetid://75780544616650",
		["smartphone"] = "rbxassetid://74962751233767",
		["smartphone-charging"] = "rbxassetid://86644420255103",
		["smartphone-nfc"] = "rbxassetid://121578015636822",
		["smile"] = "rbxassetid://129431925610335",
		["smile-plus"] = "rbxassetid://83315367165388",
		["snail"] = "rbxassetid://104438747965017",
		["snowflake"] = "rbxassetid://70879271596915",
		["sofa"] = "rbxassetid://87577807512220",
		["soup"] = "rbxassetid://123867447658880",
		["space"] = "rbxassetid://86056382889566",
		["spade"] = "rbxassetid://121221766194945",
		["sparkle"] = "rbxassetid://83114431765537",
		["sparkles"] = "rbxassetid://105634041692696",
		["speaker"] = "rbxassetid://117894179084666",
		["speech"] = "rbxassetid://86788645272110",
		["spell-check"] = "rbxassetid://139048235918692",
		["spell-check-2"] = "rbxassetid://77691901804556",
		["spline"] = "rbxassetid://127621289965723",
		["split"] = "rbxassetid://124184087776521",
		["split-square-horizontal"] = "rbxassetid://71187946462875",
		["split-square-vertical"] = "rbxassetid://77254227779817",
		["spray-can"] = "rbxassetid://97652569554326",
		["sprout"] = "rbxassetid://100976494216154",
		["square"] = "rbxassetid://135105418501265",
		["square-activity"] = "rbxassetid://123457120309378",
		["square-arrow-down"] = "rbxassetid://116832660638208",
		["square-arrow-down-left"] = "rbxassetid://90743878595626",
		["square-arrow-down-right"] = "rbxassetid://111115470362134",
		["square-arrow-left"] = "rbxassetid://118414350090559",
		["square-arrow-out-down-left"] = "rbxassetid://118423572451505",
		["square-arrow-out-down-right"] = "rbxassetid://82860326458804",
		["square-arrow-out-up-left"] = "rbxassetid://107517171610982",
		["square-arrow-out-up-right"] = "rbxassetid://96480170164917",
		["square-arrow-right"] = "rbxassetid://137471464720012",
		["square-arrow-up"] = "rbxassetid://130005030476582",
		["square-arrow-up-left"] = "rbxassetid://103366812234876",
		["square-arrow-up-right"] = "rbxassetid://80186154045078",
		["square-asterisk"] = "rbxassetid://85576779554554",
		["square-bottom-dashed-scissors"] = "rbxassetid://105977668655594",
		["square-check"] = "rbxassetid://122631573561562",
		["square-check-big"] = "rbxassetid://139404784607168",
		["square-chevron-down"] = "rbxassetid://120680078209607",
		["square-chevron-left"] = "rbxassetid://75397936728579",
		["square-chevron-right"] = "rbxassetid://76189118488226",
		["square-chevron-up"] = "rbxassetid://97181506287521",
		["square-code"] = "rbxassetid://76845656194464",
		["square-dashed-bottom"] = "rbxassetid://133040895929365",
		["square-dashed-bottom-code"] = "rbxassetid://103061363625640",
		["square-dashed-kanban"] = "rbxassetid://114545633956348",
		["square-dashed-mouse-pointer"] = "rbxassetid://123670726680392",
		["square-divide"] = "rbxassetid://107353979642451",
		["square-dot"] = "rbxassetid://110899495515389",
		["square-equal"] = "rbxassetid://124042600382551",
		["square-function"] = "rbxassetid://83985860709793",
		["square-gantt-chart"] = "rbxassetid://107284369076219",
		["square-kanban"] = "rbxassetid://97476877950543",
		["square-library"] = "rbxassetid://81887890003221",
		["square-m"] = "rbxassetid://135912337332436",
		["square-menu"] = "rbxassetid://135438142591878",
		["square-minus"] = "rbxassetid://78721357781624",
		["square-mouse-pointer"] = "rbxassetid://127552100194692",
		["square-parking"] = "rbxassetid://91463654971693",
		["square-parking-off"] = "rbxassetid://111927816549509",
		["square-pen"] = "rbxassetid://71257379947442",
		["square-percent"] = "rbxassetid://113289006657504",
		["square-pi"] = "rbxassetid://132511605174622",
		["square-pilcrow"] = "rbxassetid://87094629814766",
		["square-play"] = "rbxassetid://138697695062525",
		["square-plus"] = "rbxassetid://91942389112860",
		["square-power"] = "rbxassetid://120703265040347",
		["square-radical"] = "rbxassetid://134223878880054",
		["square-scissors"] = "rbxassetid://78779074277571",
		["square-sigma"] = "rbxassetid://94523643558062",
		["square-slash"] = "rbxassetid://78987954134223",
		["square-split-horizontal"] = "rbxassetid://125857047694996",
		["square-split-vertical"] = "rbxassetid://126418050285776",
		["square-stack"] = "rbxassetid://94687061933604",
		["square-terminal"] = "rbxassetid://75828907654568",
		["square-user"] = "rbxassetid://140235161621168",
		["square-user-round"] = "rbxassetid://81288587564855",
		["square-x"] = "rbxassetid://76206131996728",
		["squircle"] = "rbxassetid://99439828273252",
		["squirrel"] = "rbxassetid://120668151944533",
		["stamp"] = "rbxassetid://85130810524517",
		["star"] = "rbxassetid://72669221096319",
		["star-half"] = "rbxassetid://80822269649856",
		["star-off"] = "rbxassetid://120003686620511",
		["step-back"] = "rbxassetid://120706787286328",
		["step-forward"] = "rbxassetid://91046009066136",
		["stethoscope"] = "rbxassetid://78571774060105",
		["sticker"] = "rbxassetid://139865196874378",
		["sticky-note"] = "rbxassetid://98432110278865",
		["stop-circle"] = "rbxassetid://97489143368359",
		["store"] = "rbxassetid://121962391563311",
		["stretch-horizontal"] = "rbxassetid://78770748920269",
		["stretch-vertical"] = "rbxassetid://85907320465911",
		["strikethrough"] = "rbxassetid://90568214674515",
		["subscript"] = "rbxassetid://82653949184992",
		["subtitles"] = "rbxassetid://134234590631375",
		["sun"] = "rbxassetid://139232691165198",
		["sun-dim"] = "rbxassetid://131075444152110",
		["sun-medium"] = "rbxassetid://112704797109150",
		["sun-moon"] = "rbxassetid://121221641564933",
		["sunrise"] = "rbxassetid://116733420530374",
		["sunset"] = "rbxassetid://101740056345650",
		["sun-snow"] = "rbxassetid://83004210487318",
		["superscript"] = "rbxassetid://93191189359166",
		["swatch-book"] = "rbxassetid://70990631477660",
		["swiss-franc"] = "rbxassetid://72116456510352",
		["switch-camera"] = "rbxassetid://124033626341331",
		["sword"] = "rbxassetid://121406454377051",
		["swords"] = "rbxassetid://99199363807265",
		["syringe"] = "rbxassetid://86444160764731",
		["table"] = "rbxassetid://100826532869925",
		["table-2"] = "rbxassetid://129391889722576",
		["table-cells-merge"] = "rbxassetid://118490713113220",
		["table-cells-split"] = "rbxassetid://113945031629733",
		["table-columns-split"] = "rbxassetid://79195518284331",
		["table-properties"] = "rbxassetid://135976623395143",
		["table-rows-split"] = "rbxassetid://126696533672175",
		["tablet"] = "rbxassetid://90619723471983",
		["tablets"] = "rbxassetid://88043022962639",
		["tablet-smartphone"] = "rbxassetid://78186066591210",
		["tag"] = "rbxassetid://75425807137911",
		["tags"] = "rbxassetid://103166221753217",
		["tally-1"] = "rbxassetid://90000711698807",
		["tally-2"] = "rbxassetid://99935651880614",
		["tally-3"] = "rbxassetid://98958831676946",
		["tally-4"] = "rbxassetid://128656473677471",
		["tally-5"] = "rbxassetid://101955254503648",
		["tangent"] = "rbxassetid://103123484115035",
		["target"] = "rbxassetid://121091323240554",
		["telescope"] = "rbxassetid://103588488639070",
		["tent"] = "rbxassetid://91768489962137",
		["tent-tree"] = "rbxassetid://85050403463582",
		["terminal"] = "rbxassetid://102379915564176",
		["terminal-square"] = "rbxassetid://89706340938367",
		["test-tube"] = "rbxassetid://139701481278358",
		["test-tube-2"] = "rbxassetid://118913572969135",
		["test-tube-diagonal"] = "rbxassetid://121621592892259",
		["test-tubes"] = "rbxassetid://117323642962952",
		["text"] = "rbxassetid://99369759989955",
		["text-cursor"] = "rbxassetid://103697482936876",
		["text-cursor-input"] = "rbxassetid://84912489891242",
		["text-quote"] = "rbxassetid://102573021965795",
		["text-search"] = "rbxassetid://114489224126711",
		["text-select"] = "rbxassetid://99310852917353",
		["theater"] = "rbxassetid://89919220874053",
		["thermometer"] = "rbxassetid://90545345642681",
		["thermometer-snowflake"] = "rbxassetid://138010690931368",
		["thermometer-sun"] = "rbxassetid://82795165216031",
		["thumbs-down"] = "rbxassetid://73778874448741",
		["thumbs-up"] = "rbxassetid://96046658888813",
		["ticket"] = "rbxassetid://126875062984266",
		["ticket-check"] = "rbxassetid://117888043623314",
		["ticket-minus"] = "rbxassetid://89176175166723",
		["ticket-percent"] = "rbxassetid://88410626824232",
		["ticket-plus"] = "rbxassetid://83968600419805",
		["ticket-slash"] = "rbxassetid://79392492298521",
		["ticket-x"] = "rbxassetid://86658718829072",
		["timer"] = "rbxassetid://120164083411828",
		["timer-off"] = "rbxassetid://116991705734594",
		["timer-reset"] = "rbxassetid://79948324123231",
		["toggle-left"] = "rbxassetid://105639191695402",
		["toggle-right"] = "rbxassetid://129483325318573",
		["tornado"] = "rbxassetid://93796857097422",
		["torus"] = "rbxassetid://78822043673501",
		["touchpad"] = "rbxassetid://112333029100357",
		["touchpad-off"] = "rbxassetid://86546394503986",
		["tower-control"] = "rbxassetid://128131047012652",
		["toy-brick"] = "rbxassetid://81793486260595",
		["tractor"] = "rbxassetid://87948191954230",
		["traffic-cone"] = "rbxassetid://87190332091101",
		["train-front"] = "rbxassetid://91480038985820",
		["train-front-tunnel"] = "rbxassetid://77194453402235",
		["train-track"] = "rbxassetid://105798879242186",
		["tram-front"] = "rbxassetid://80023103356955",
		["trash"] = "rbxassetid://94712995845562",
		["trash-2"] = "rbxassetid://126010725826757",
		["tree-deciduous"] = "rbxassetid://109951315210525",
		["tree-palm"] = "rbxassetid://111070569131758",
		["tree-pine"] = "rbxassetid://71580980892868",
		["trees"] = "rbxassetid://79707751200645",
		["trello"] = "rbxassetid://90438659765426",
		["trending-down"] = "rbxassetid://122658819043338",
		["trending-up"] = "rbxassetid://86000419326493",
		["triangle"] = "rbxassetid://134878256295114",
		["triangle-alert"] = "rbxassetid://91165848022002",
		["triangle-right"] = "rbxassetid://105796120965583",
		["trophy"] = "rbxassetid://113055182645565",
		["truck"] = "rbxassetid://125468675952181",
		["turtle"] = "rbxassetid://73899487161474",
		["tv"] = "rbxassetid://130308429701946",
		["tv-2"] = "rbxassetid://129500347007411",
		["twitch"] = "rbxassetid://90697389361633",
		["twitter"] = "rbxassetid://90424880717042",
		["type"] = "rbxassetid://70694319369829",
		["umbrella"] = "rbxassetid://108749598923776",
		["umbrella-off"] = "rbxassetid://111820268638089",
		["underline"] = "rbxassetid://127096081441525",
		["undo"] = "rbxassetid://111464695038355",
		["undo-2"] = "rbxassetid://87358323292564",
		["undo-dot"] = "rbxassetid://102793353935041",
		["unfold-horizontal"] = "rbxassetid://85781955020909",
		["unfold-vertical"] = "rbxassetid://122887666597646",
		["ungroup"] = "rbxassetid://76318446818069",
		["university"] = "rbxassetid://102146636224428",
		["unlink"] = "rbxassetid://102194562745333",
		["unlink-2"] = "rbxassetid://108239607794680",
		["unlock"] = "rbxassetid://110263656507369",
		["unlock-keyhole"] = "rbxassetid://126931549237422",
		["unplug"] = "rbxassetid://123150141199349",
		["upload"] = "rbxassetid://118488857289315",
		["upload-cloud"] = "rbxassetid://121807815408739",
		["usb"] = "rbxassetid://75949167692936",
		["user"] = "rbxassetid://114567720540659",
		["user-2"] = "rbxassetid://92481398073007",
		["user-check"] = "rbxassetid://75620511859505",
		["user-check-2"] = "rbxassetid://73224920504446",
		["user-circle"] = "rbxassetid://111917761312899",
		["user-circle-2"] = "rbxassetid://96888447186214",
		["user-cog"] = "rbxassetid://87518742987519",
		["user-cog-2"] = "rbxassetid://115462370853742",
		["user-minus"] = "rbxassetid://94865546608687",
		["user-minus-2"] = "rbxassetid://93808234717021",
		["user-plus"] = "rbxassetid://101184880550364",
		["user-plus-2"] = "rbxassetid://104764183758140",
		["user-round"] = "rbxassetid://119713822992150",
		["user-round-check"] = "rbxassetid://99288072031664",
		["user-round-cog"] = "rbxassetid://127120627937146",
		["user-round-minus"] = "rbxassetid://129866427748569",
		["user-round-plus"] = "rbxassetid://101991526004413",
		["user-round-search"] = "rbxassetid://114857943818454",
		["user-round-x"] = "rbxassetid://89227016198055",
		["users"] = "rbxassetid://85332511060401",
		["users-2"] = "rbxassetid://138651149526372",
		["user-search"] = "rbxassetid://110388873642450",
		["user-square"] = "rbxassetid://136305896243658",
		["user-square-2"] = "rbxassetid://71391894371551",
		["users-round"] = "rbxassetid://103880524805720",
		["user-x"] = "rbxassetid://138436637971548",
		["user-x-2"] = "rbxassetid://96976557144947",
		["utensils"] = "rbxassetid://122537080261787",
		["utensils-crossed"] = "rbxassetid://100229317932246",
		["utility-pole"] = "rbxassetid://137834357386674",
		["variable"] = "rbxassetid://73932604072578",
		["vault"] = "rbxassetid://107415856993701",
		["vegan"] = "rbxassetid://127691293819852",
		["venetian-mask"] = "rbxassetid://84202958608655",
		["vibrate"] = "rbxassetid://140427675871522",
		["vibrate-off"] = "rbxassetid://102494346080496",
		["video"] = "rbxassetid://99411215690870",
		["video-off"] = "rbxassetid://81634790888002",
		["videotape"] = "rbxassetid://92799250697204",
		["view"] = "rbxassetid://102821349715124",
		["voicemail"] = "rbxassetid://121299677348672",
		["volume"] = "rbxassetid://127607149758269",
		["volume-1"] = "rbxassetid://115207748957226",
		["volume-2"] = "rbxassetid://129861259578431",
		["volume-x"] = "rbxassetid://106700331106145",
		["vote"] = "rbxassetid://137637654521705",
		["wallet"] = "rbxassetid://132318555862654",
		["wallet-2"] = "rbxassetid://120839431200970",
		["wallet-cards"] = "rbxassetid://86866924072285",
		["wallet-minimal"] = "rbxassetid://77655892701714",
		["wallpaper"] = "rbxassetid://76631821212930",
		["wand"] = "rbxassetid://95424916372879",
		["wand-2"] = "rbxassetid://84750107238092",
		["wand-sparkles"] = "rbxassetid://115623066336607",
		["warehouse"] = "rbxassetid://126757874656976",
		["washing-machine"] = "rbxassetid://72331434583186",
		["watch"] = "rbxassetid://103181426780078",
		["waves"] = "rbxassetid://98840358372718",
		["waypoints"] = "rbxassetid://101997233404191",
		["webcam"] = "rbxassetid://90027890284611",
		["webhook"] = "rbxassetid://110638252405523",
		["webhook-off"] = "rbxassetid://71995352392407",
		["weight"] = "rbxassetid://79312026690586",
		["wheat"] = "rbxassetid://115823998996262",
		["wheat-off"] = "rbxassetid://110571881208127",
		["whole-word"] = "rbxassetid://110504483563993",
		["wifi"] = "rbxassetid://104941258142372",
		["wifi-off"] = "rbxassetid://120795495190257",
		["wind"] = "rbxassetid://86165302601843",
		["wine"] = "rbxassetid://101623153529226",
		["wine-off"] = "rbxassetid://131814228138093",
		["workflow"] = "rbxassetid://78971198932745",
		["worm"] = "rbxassetid://98855303743824",
		["wrap-text"] = "rbxassetid://70866394776130",
		["wrench"] = "rbxassetid://85345725497834",
		["x"] = "rbxassetid://116396312853810",
		["x-circle"] = "rbxassetid://111132030834422",
		["x-octagon"] = "rbxassetid://105062643930018",
		["x-square"] = "rbxassetid://115678228554812",
		["youtube"] = "rbxassetid://134880265650906",
		["zap"] = "rbxassetid://109718589733073",
		["zap-off"] = "rbxassetid://115642996489807",
		["zoom-in"] = "rbxassetid://135570550221809",
		["zoom-out"] = "rbxassetid://100181096350591",
	} }
	local function loadLucideIcons()
		return IconsRestPack
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
		local iconName = icon:gsub("^iconsrest:", ""):gsub("^lucide:", "")
		if iconName == "house" then iconName = "home" end
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
	local cardHeight = isTouchDevice and 48 or 40
	local descriptionCardHeight = isTouchDevice and 64 or 56
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
		radius = radius or UDim.new(0, 16)
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
		if not target or target:GetAttribute("UIJoinedControl") then
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
			error(result, 0)
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
		local joined = tab.List:GetAttribute("UIJoinedControls") == true
		local cardProperties = {
			Size = UDim2.new(1, 0, 0, height),
			BackgroundColor3 = nativeTheme.Surface2,
			BackgroundTransparency = joined and 1 or 0,
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
		if joined then
			stroke.Transparency = 1
			stroke:SetAttribute("UIJoinedControl", true)
		end
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
		local premium = section and config.Premium == true
		local frame, stroke =
			createCard(self, "TextButton", config.Desc and descriptionCardHeight or cardHeight, config)
		frame.ClipsDescendants = true
		frame:SetAttribute("UIRole", section and "SectionHeader" or "ActionButton")
		local hovered = false
		local leading, leadingHolder
		if config.Icon then
			local holder
			holder, leading =
				createIcon(frame, config.Icon, nativeTheme.Text, UDim2.new(0, section and 12 or 14, 0.5, 0))
			leadingHolder = holder
		end
		local title, description = createCardLabels(frame, config.Name or "Button", config.Desc, section and 36 or 56)
		if section then
			title.FontFace = nativeFonts.Bold
			title.TextSize = 16
			local inset = config.Icon and 38 or 12
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
		if premium then
			title.Size -= UDim2.fromOffset(68, 0)

			local badge = createLabel({
				Name = "PremiumBadge",
				AnchorPoint = Vector2.new(0, 0.5),
				Size = UDim2.fromOffset(60, 18),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				FontFace = nativeFonts.Medium,
				Text = "Premium",
				TextSize = isTouchDevice and 12 or 11,
				TextColor3 = Color3.fromRGB(238, 207, 104),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextYAlignment = Enum.TextYAlignment.Center,
				TextTruncate = Enum.TextTruncate.None,
				RichText = false,
				Active = false,
				Parent = frame,
			})
			local function positionPremium()
				local scale = math.max(math.min(self.Window.Scale.Scale, 1), 0.01)
				local width = math.min(title.TextBounds.X, title.AbsoluteSize.X) / scale
				badge.Position = title.Position + UDim2.new(0, width + 8, title.Size.Y.Scale / 2, title.Size.Y.Offset / 2)
			end
			title:GetPropertyChangedSignal("TextBounds"):Connect(positionPremium)
			title:GetPropertyChangedSignal("AbsoluteSize"):Connect(positionPremium)
			positionPremium()
		end
		local indicator, arrow
		if section then
			local _holder
			_holder, arrow = createIcon(frame, "chevron-right", nativeTheme.Muted, UDim2.new(1, -24, 0.5, 0))
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
			local _holder
			_holder, arrow = createIcon(indicator, "arrow-up-right", nativeTheme.AccentDark, UDim2.new(0.5, -8, 0.5, 0))
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
			local window = self.Window
			if window then window._feedbackButton = function()
				local previous = control._feedbackOriginal or title.Text
				control._feedbackOriginal = previous
				title.Text = "Copiado ✓"
				task.delay(1.2, function() if title.Parent and title.Text == "Copiado ✓" then title.Text = previous; control._feedbackOriginal = nil end end)
			end end
			invokeCallback(config.Callback)
			if window then window._feedbackButton = nil end
		end)
		return registerElement(self, config, control, frame, "Button")
	end

	function NativeTab:Toggle(toggleConfig)
		local toggleCard, toggleStroke, _height, title, description
		toggleConfig, toggleCard, toggleStroke, _height, title, description = createInteractiveCard(
			self, toggleConfig, {Title = "Name", Description = "Desc", CurrentValue = "Default", Value = "Default"},
			"TextButton", 68, "Toggle"
		)
		toggleCard:SetAttribute("UIRole", "Toggle")
		toggleCard:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0, 6)
		toggleStroke.Transparency = 0.65
		local trackWidth, thumbSize = isTouchDevice and 46 or 42, isTouchDevice and 18 or 16
		local toggleTrack = createInstance("Frame", {
			Name = "Switch", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0),
			Size = UDim2.fromOffset(trackWidth, thumbSize + 8), BackgroundColor3 = nativeTheme.Surface,
			BorderSizePixel = 0, Parent = toggleCard,
		})
		addCorner(toggleTrack, UDim.new(0, 6))
		local trackStroke = addStroke(toggleTrack, nativeTheme.Stroke)
		local toggleThumb = createInstance("Frame", {
			Name = "Thumb", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 4, 0.5, 0),
			Size = UDim2.fromOffset(thumbSize, thumbSize), BackgroundColor3 = nativeTheme.Muted,
			BorderSizePixel = 0, Parent = toggleTrack,
		})
		addCorner(toggleThumb, UDim.new(0, 4))
		local tick = createInstance("Frame", {
			Name = "Grip", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(2, 6), BackgroundColor3 = NativeLibrary.Navigation.Fill,
			BorderSizePixel = 0, Parent = toggleThumb,
		})
		local toggleControl = {Value = toggleConfig.Default == true, TitleLabel = title, DescriptionLabel = description}
		local function updateToggle(animated)
			local checked = toggleControl.Value
			local duration = animated and 0.16 or 0
			animate(toggleTrack, {BackgroundColor3 = checked and NativeLibrary.Navigation.Fill or nativeTheme.Surface}, duration)
			animate(trackStroke, {Color = checked and NativeLibrary.Navigation.Edge or nativeTheme.Stroke, Transparency = checked and 0.1 or 0.35}, duration)
			animate(toggleThumb, {
				Position = UDim2.new(0, checked and trackWidth - 4 - thumbSize or 4, 0.5, 0),
				BackgroundColor3 = checked and NativeLibrary.Navigation.Foreground or nativeTheme.Muted,
			}, duration)
			animate(tick, {BackgroundTransparency = checked and 0 or 0.5}, duration)
		end
		function toggleControl:Set(enabled, skipCallback)
			enabled = enabled == true
			if self._destroyed or enabled == self.Value then return end
			self.Value = enabled
			updateToggle(true)
			if not skipCallback then invokeCallback(toggleConfig.Callback, enabled) end
		end
		function toggleControl:Get() return self.Value end
		function toggleControl:RefreshStyle() updateToggle(false) end
		updateToggle(false)
		toggleCard.MouseButton1Click:Connect(function() toggleControl:Set(not toggleControl.Value) end)
		local registeredToggle = registerElement(self, toggleConfig, toggleControl, toggleCard, "Toggle")
		if toggleControl.Value then invokeCallback(toggleConfig.Callback, true) end
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
			Position = UDim2.fromOffset(14, 18),
			Size = UDim2.new(1, -120, 0, 18),
			Text = sliderConfig.Name or "Slider",
			Parent = sliderCard,
		})
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
			Size = UDim2.fromOffset(56, 24),
			BackgroundColor3 = nativeTheme.Surface,
			BorderSizePixel = 0,
			ClipsDescendants = true,
			Parent = sliderCard,
		})
		addCorner(valueHolder, UDim.new(0, 5))
		local valueStroke = addStroke(valueHolder)
		valueStroke.Transparency = 0.55
		valueHolder.BackgroundTransparency = 0.35
		local valueLabel = createLabel({
			Name = "Value",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, -20, 1, 0),
			TextSize = 13,
			TextColor3 = nativeTheme.Text,
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
			TextColor3 = nativeTheme.Text,
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
			valueHolder.Size = UDim2.fromOffset(width, 24)
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
			Size = UDim2.new(1, -28, 0, 3),
			BackgroundColor3 = nativeTheme.Surface3,
			BorderSizePixel = 0,
			Parent = sliderCard,
		})
		addCorner(sliderTrack, UDim.new(1, 0))
		local sliderFill = createInstance(frameClass, {
			Size = UDim2.new(0, 0, 1, 0),
			BackgroundColor3 = Color3.fromRGB(194, 198, 202),
			BorderSizePixel = 0,
			Parent = sliderTrack,
		})
		addCorner(sliderFill, UDim.new(1, 0))
		local thumbGlow = createInstance("Frame", {
			Name = "ThumbHalo",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0, 0, 0.5, 0),
			Size = UDim2.fromOffset(24, 24),
			BackgroundColor3 = Color3.fromRGB(220, 224, 228),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 2,
			Parent = sliderTrack,
		})
		addCorner(thumbGlow, UDim.new(1, 0))
		local sliderThumb = createInstance(frameClass, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0, 0, 0.5, 0),
			Size = UDim2.fromOffset(8, 16),
			BackgroundColor3 = Color3.fromRGB(194, 198, 202),
			BorderSizePixel = 0,
			ZIndex = 3,
			Parent = sliderTrack,
		})
		addCorner(sliderThumb, UDim.new(0, 3))
		addStroke(sliderThumb, Color3.fromRGB(240, 242, 244)).Transparency = 0.65
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
				animate(thumbGlow, { BackgroundTransparency = 0.92, Size = UDim2.fromOffset(26, 26) }, 0.15)
			end
		end)
		sliderHitbox.MouseLeave:Connect(function()
			if not draggingSlider then
				animate(thumbGlow, { BackgroundTransparency = 1, Size = UDim2.fromOffset(24, 24) }, 0.2)
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
			animate(sliderThumb, { Size = UDim2.fromOffset(10, 18) }, 0.08)
			animate(thumbGlow, { Size = UDim2.fromOffset(26, 26), BackgroundTransparency = 0.92 }, 0.12)
			task.delay(0.1, function()
				animate(sliderThumb, { Size = UDim2.fromOffset(8, 16) }, 0.25, Enum.EasingStyle.Quint)
				animate(thumbGlow, { Size = UDim2.fromOffset(24, 24), BackgroundTransparency = 1 }, 0.25)
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
				animate(sliderThumb, { Size = UDim2.fromOffset(10, 20) }, 0.15, Enum.EasingStyle.Back)
				animate(thumbGlow, { Size = UDim2.fromOffset(30, 30), BackgroundTransparency = 0.87 }, 0.15)
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
				animate(sliderThumb, { Size = UDim2.fromOffset(8, 16) }, 0.2)
				animate(thumbGlow, { Size = UDim2.fromOffset(24, 24), BackgroundTransparency = 1 }, 0.2)
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
		if dropdownConfig.AttachmentPicker then
			dropdownHeight = isTouchDevice and 44 or 34
			dropdownCard.Size = controlSize(dropdownCard, dropdownHeight)
		end
		dropdownCard.ClipsDescendants = true
		dropdownCard:SetAttribute("UIRole", "Dropdown")
		dropdownCard:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0, 6)
		dropdownStroke.Transparency = 0.65
		local dropdownHeader = createInstance("TextButton", {
			Name = "DropdownHeader",
			Size = UDim2.new(1, 0, 0, dropdownHeight),
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
			Parent = dropdownCard,
		})
		local titleLabel, descriptionLabel =
			createCardLabels(dropdownHeader, dropdownConfig.Name or "Dropdown", dropdownConfig.Desc, 180)
		local valueHolder = createInstance(frameClass, {
			Name = "Selection",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(60, chipHeight),
			BackgroundColor3 = nativeTheme.Surface,
			BorderSizePixel = 0,
			ClipsDescendants = true,
			Parent = dropdownHeader,
		})
		addCorner(valueHolder, UDim.new(0, 4))
		local valueStroke = addStroke(valueHolder)
		valueStroke.Transparency = 0.45
		local selectionLabel = createLabel({
			Position = UDim2.fromOffset(10, 0),
			Size = UDim2.new(1, -34, 1, 0),
			TextColor3 = nativeTheme.Muted,
			TextSize = 13,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ClipsDescendants = true,
			Parent = valueHolder,
		})
		local chevron = createChevron(valueHolder, 1, -6)
		if dropdownConfig.AttachmentPicker then
			selectionLabel.Position, selectionLabel.Size = UDim2.fromOffset(34, 0), UDim2.new(1, -60, 1, 0)
			createInstance("ImageLabel", {
				Image = "rbxassetid://101144735754292", ImageColor3 = nativeTheme.Muted,
				BackgroundTransparency = 1, Position = UDim2.new(0, 10, 0.5, -8),
				Size = UDim2.fromOffset(16, 16), Parent = valueHolder,
			})
		end
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
			if dropdownConfig.AttachmentPicker then
				return summary == "Sem documento" and "Anexar documento" or summary
			end
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
			if dropdownConfig.AttachmentPicker then
				titleLabel.Visible = false
				valueHolder.Size = UDim2.new(1, -12, 1, -4)
				valueHolder.Position = UDim2.new(1, -6, 0.5, 0)
				return
			end
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
			Name = "Options",
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

		local function styleOption(row, animated)
			local selected = row.On == true
			local visible = dropdownControl.Open
			local duration = animated and 0.16 or 0
			animate(row.Frame, {
				BackgroundColor3 = selected and NativeLibrary.Navigation.Fill or nativeTheme.Surface,
				BackgroundTransparency = visible and (selected and 0.08 or (row.Hovered and 0.25 or 0.75)) or 1,
			}, duration)
			animate(row.Label, {
				TextColor3 = selected and NativeLibrary.Navigation.Foreground or (row.Hovered and nativeTheme.Text or nativeTheme.Muted),
				TextTransparency = visible and (row.Disabled and 0.55 or 0) or 1,
			}, duration)
			animate(row.Stroke, {Color = NativeLibrary.Navigation.Edge, Transparency = visible and selected and 0.4 or 1}, duration)
			animate(row.Check, {ImageTransparency = visible and selected and 0 or 1}, duration)
			animate(row.Mark, {BackgroundTransparency = visible and selected and 0 or 1}, duration)
		end
		local function updateSelection()
			local exclusive = dropdownConfig.ExclusiveOption
			local exclusiveSelected = exclusive ~= nil and selectedOptions[exclusive] == true
			if exclusiveSelected then
				for option in pairs(selectedOptions) do
					if option ~= exclusive then selectedOptions[option] = nil end
				end
			end
			local selected = getSelection()
			if multiSelect then emptySummary = #selected > 0 and table.concat(selected, ", ") or "Selecionar"
			else emptySummary = selected ~= nil and tostring(selected) or "Selecionar" end
			selectionLabel.Text = selectionSummary()
			for option, row in pairs(optionControls) do
				row.Disabled = exclusiveSelected and option ~= exclusive
				row.Frame.Active = not row.Disabled
				row.On = selectedOptions[option] == true
				styleOption(row, true)
			end
		end

		local function _updateOptionVisibility()
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
			if dropdownControl._destroyed then return end
			dropdownControl.Open = open
			searchRow.Visible = #optionValues > searchThreshold
			if not open then
				searchQuery = ""
				searchInput.Text = ""
				updateSearch()
			end
			animate(dropdownCard, {Size = controlSize(dropdownCard, open and updateDropdownHeight() or dropdownHeight)}, 0.22)
			animate(searchRow, {BackgroundTransparency = open and 0 or 1}, 0.16)
			animate(searchStroke, {Transparency = open and 0.55 or 1}, 0.16)
			animate(searchInput, {TextTransparency = open and 0 or 1}, 0.16)
			chevron:Set(open)
			animate(valueHolder, {BackgroundColor3 = open and NativeLibrary.Navigation.Fill or nativeTheme.Surface}, 0.16)
			animate(valueStroke, {Color = open and NativeLibrary.Navigation.Edge or nativeTheme.Stroke}, 0.16)
			animate(selectionLabel, {TextColor3 = open and NativeLibrary.Navigation.Foreground or nativeTheme.Text}, 0.16)
			for _, row in pairs(optionControls) do styleOption(row, true) end
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
				addCorner(optionButton, UDim.new(0, 4))
				local selectedMark = createInstance("Frame", {
					Name = "SelectedMark", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 3, 0.5, 0),
					Size = UDim2.fromOffset(2, 14), BackgroundColor3 = NativeLibrary.Navigation.Accent,
					BackgroundTransparency = 1, BorderSizePixel = 0, Parent = optionButton,
				})
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
				local checkScale = createInstance("UIScale", { Scale = 1, Parent = checkIcon })
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
					local row = optionControls[option]
					if not row or row.Disabled then return end
					row.Hovered = true
					styleOption(row, true)
				end)
				optionButton.MouseLeave:Connect(function()
					local row = optionControls[option]
					if not row then return end
					row.Hovered = false
					styleOption(row, true)
				end)
				optionButton.MouseButton1Click:Connect(function()
					if optionControls[option] and optionControls[option].Disabled then return end
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
					Stroke = addStroke(optionButton, NativeLibrary.Navigation.Edge, 1),
					Mark = selectedMark,
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
		local inputCard, inputStroke, _inputHeight, inputTitle, inputDescription
		inputConfig, inputCard, inputStroke, _inputHeight, inputTitle, inputDescription =
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
		local keybindCard, keybindStroke, _keybindHeight, keybindTitle, keybindDescription
		keybindConfig, keybindCard, keybindStroke, _keybindHeight, keybindTitle, keybindDescription =
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
		local stepperCard, stepperStroke, _stepperHeight, stepperTitle, stepperDescription
		stepperConfig, stepperCard, stepperStroke, _stepperHeight, stepperTitle, stepperDescription =
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
			Desc = "Salva as opções atuais com o nome escolhido.",
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
			Desc = "Salva suas alterações automaticamente.",
			Default = window._autoSaveEnabled,
			Callback = function(name)
				window._autoSaveEnabled = name
			end,
		})
		return configManager
	end
	for methodName, method in pairs(table.clone(NativeTab)) do
		if type(method) == "function" and methodName:sub(1, 1) ~= "_" and methodName:sub(1, 6) ~= "Create" then
			NativeTab["Create" .. methodName] = method
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

	NativeLibrary.DetectExecutor = detectExecutor

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
	local NativeWindow = {}
	NativeWindow.__index = NativeWindow
	-- Keep overflow discoverable on touch without a per-frame observer.
	local function createScrollCue(window, scroll, parent, text)
		if not isTouchDevice then return nil end
		local cue = createLabel({
			Name = "ScrollCue", Text = text, TextSize = 12,
			TextColor3 = nativeTheme.Muted:Lerp(nativeTheme.Text, 0.5),
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.new(0, 8, 1, -24), Size = UDim2.new(1, -16, 0, 24),
			Visible = false, Parent = parent,
		})
		local function update()
			local remaining = scroll.AbsoluteCanvasSize.Y - scroll.AbsoluteWindowSize.Y - scroll.CanvasPosition.Y
			cue.Visible = remaining > 1
		end
		for _, property in ipairs({ "AbsoluteCanvasSize", "AbsoluteWindowSize", "CanvasPosition" }) do
			table.insert(window._connections, scroll:GetPropertyChangedSignal(property):Connect(update))
		end
		update()
		return cue
	end
	-- Mirror only a small GUI that follows mouse movement, never the game's whole HUD.
	local function attachGameCursor(window, screenGui, windowRoot, parent)
		if not UserInputService.MouseEnabled then return end
		local overlay = createInstance("ScreenGui", {
			Name = "MichigunCursor", IgnoreGuiInset = true, ResetOnSpawn = false,
			DisplayOrder = screenGui.DisplayOrder + 1, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = parent,
		})
		local fallback = createInstance("ImageLabel", {
			Name = "Pointer", BackgroundTransparency = 1, Active = false,
			Image = "rbxasset://textures/Cursors/KeyboardMouse/ArrowFarCursor.png",
			Size = UDim2.fromOffset(32, 32), Visible = false, Parent = overlay,
		})
		local source, mirror, changed
		local samples = setmetatable({}, { __mode = "k" })
		local lastMouse
		local elapsed = 0
		local function clearMirror()
			if changed then changed:Disconnect(); changed = nil end
			if mirror then mirror:Destroy(); mirror = nil end
			source = nil
		end
		local function visible(object)
			local current = object
			while current and current ~= localPlayer.PlayerGui do
				if current:IsA("GuiObject") and not current.Visible then return false end
				if current:IsA("ScreenGui") and not current.Enabled then return false end
				current = current.Parent
			end
			return current ~= nil
		end
		local function useCursor(candidate)
			clearMirror()
			local ok, copy = pcall(candidate.Clone, candidate)
			if not ok or not copy then return end
			for _, child in ipairs(copy:GetDescendants()) do
				if child:IsA("LuaSourceContainer") or child:IsA("UIScale") or child:IsA("UIConstraint") then child:Destroy()
				elseif child:IsA("GuiObject") then
					child.Active, child.Selectable = false, false
					if child:IsA("GuiButton") then child.Interactable = false end
				end
			end
			source, mirror = candidate, copy
			copy.Active, copy.Selectable, copy.AnchorPoint = false, false, Vector2.zero
			if copy:IsA("GuiButton") then copy.Interactable = false end
			copy.Parent = overlay
			changed = candidate.Changed:Connect(function(property)
				if property == "Position" or property == "Size" or property == "AnchorPoint" or property == "Parent" or property == "ZIndex" then return end
				pcall(function() copy[property] = candidate[property] end)
			end)
		end
		table.insert(window._frameSteps, function(deltaTime)
			local point = UserInputService:GetMouseLocation()
			local position, size = windowRoot.AbsolutePosition, windowRoot.AbsoluteSize
			local over = window.Open and screenGui.Enabled and windowRoot.Visible and point.X >= position.X and point.Y >= position.Y
				and point.X <= position.X + size.X and point.Y <= position.Y + size.Y
			local needed = over and not UserInputService.MouseIconEnabled
			fallback.Visible = false
			if mirror then mirror.Visible = false end
			if not needed then return end
			elapsed += deltaTime
			if source and (not source.Parent or not visible(source)) then clearMirror() end
			if not source and elapsed >= 0.1 then
				elapsed = 0
				local inset = GuiService:GetGuiInset()
				local mouseDelta = lastMouse and point - lastMouse
				local seen = {}
				for _, query in ipairs({ point, point - inset }) do
					for _, candidate in ipairs(localPlayer.PlayerGui:GetGuiObjectsAtPosition(query.X, query.Y)) do
						if seen[candidate] then continue end
						seen[candidate] = true
						local candidateSize = candidate.AbsoluteSize
						-- UI detection bounds, not a game range or timing limit.
						if candidateSize.X > 96 or candidateSize.Y > 96 or candidate.Active or candidate:IsA("TextBox") then continue end
						local previous = samples[candidate]
						samples[candidate] = candidate.AbsolutePosition
						if previous and mouseDelta and mouseDelta.Magnitude >= 2
							and (candidate.AbsolutePosition - previous - mouseDelta).Magnitude <= 1 and visible(candidate) then
							useCursor(candidate)
							break
						end
					end
					if source then break end
				end
				lastMouse = point
			end
			if source and mirror then
				local owner = source:FindFirstAncestorOfClass("ScreenGui")
				local inset = owner and not owner.IgnoreGuiInset and GuiService:GetGuiInset() or Vector2.zero
				local location = source.AbsolutePosition + inset
				mirror.Position = UDim2.fromOffset(location.X, location.Y)
				mirror.Size = UDim2.fromOffset(source.AbsoluteSize.X, source.AbsoluteSize.Y)
				mirror.Visible = true
			else
				fallback.Position = UDim2.fromOffset(point.X - 16, point.Y - 16)
				fallback.Visible = true
			end
		end)
		table.insert(window._connections, { Disconnect = function() clearMirror(); overlay:Destroy() end })
	end

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
		local interfaceParent = windowConfig.Parent or getInterfaceParent()
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
		attachGameCursor(window, screenGui, windowRoot, interfaceParent)
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
		windowBody.BackgroundTransparency = 0
		window.BodyStroke = addStroke(windowBody, nativeTheme.Stroke)
		window.BodyStroke.LineJoinMode = Enum.LineJoinMode.Miter
		addEdgeHighlight(windowBody)
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
			ScrollBarThickness = isTouchDevice and 5 or 0,
			ScrollBarImageColor3 = nativeTheme.Text,
			ScrollBarImageTransparency = 0.15,
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			CanvasSize = UDim2.new(),
			Parent = sidebar,
		})
		window.TabList = scrollingFrame
		scrollingFrame:SetAttribute("NoDrag", true)
		scrollingFrame.AutomaticCanvasSize = Enum.AutomaticSize.X
		scrollingFrame.ScrollingDirection = Enum.ScrollingDirection.X
		scrollingFrame.ScrollBarThickness = 2
		window.TabStrip = createInstance("ScrollingFrame", {
			Name = "TabStrip", Position = UDim2.fromOffset(0, 94), Size = UDim2.new(1, 0, 0, 38),
			BackgroundColor3 = nativeTheme.Surface, BackgroundTransparency = 0.35, BorderSizePixel = 0, ScrollBarThickness = 2,
			AutomaticCanvasSize = Enum.AutomaticSize.None, CanvasSize = UDim2.new(),
			ScrollingDirection = Enum.ScrollingDirection.X, Parent = sidebar,
		})
		window.TabStrip:SetAttribute("NoDrag", true)
		-- Início and the game tab also need room for their centered border stroke.
		addPadding(scrollingFrame, 2, 2, 1, 3)
		createInstance(
			listLayoutClass,
			{ FillDirection = Enum.FillDirection.Horizontal, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6), Parent = scrollingFrame }
		)
		local tabIndicator = createInstance(frameClass, {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromOffset(6, 0),
			Size = UDim2.fromOffset(0, 0),
			BackgroundTransparency = 1,
			BackgroundColor3 = NativeLibrary.Navigation.Accent,
			BorderSizePixel = 0,
			Visible = false,
			ZIndex = 2,
			Parent = sidebar,
		})
		addCorner(tabIndicator, UDim.new(1, 0))
		window.Indicator = tabIndicator
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
				UDim2.fromOffset(math.max(1, math.min(280, screenGui.AbsoluteSize.X - 24)), availableHeight)
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
		screenGui.Parent = interfaceParent
		windowScale.Scale = 1
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
				local sidebarWidth = isTouchDevice and math.clamp(math.floor(width * 0.28), 112, 168)
			or (compact and (width < 420 and 112 or 184) or 224)
				if isTouchDevice or compact ~= window._compactLayout or sidebarWidth ~= window._sidebarWidth then
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
		return nil
	end

	function NativeLibrary:Confirm(dialogConfig)
		local activeWindow = NativeLibrary.Windows[#NativeLibrary.Windows]
		if activeWindow then
			return activeWindow:Confirm(dialogConfig)
		end
		return nil
	end

	function NativeLibrary:Dialog(dialogConfig)
		local activeWindow = NativeLibrary.Windows[#NativeLibrary.Windows]
		if activeWindow then
			return activeWindow:Dialog(dialogConfig)
		end
		return nil
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
			scale.Scale = self._fitScale or 1
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
			if not self._destroyed and self.CurrentTab then
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
		local rowHeight = isTouchDevice and (self.Root.Size.Y.Offset < 340 and 40 or 44) or 34
		local categoryTop = 52
		local stripTop = categoryTop + rowHeight + 8
		local contentTop = self._showTabStrip == false and stripTop or stripTop + rowHeight + 8
		self._sidebarWidth = 0
		local nav = self.Body:FindFirstChild("Sidebar")
		if nav then
			nav.Position = UDim2.fromOffset(12, 0)
			nav.Size = UDim2.new(1, -24, 0, stripTop + rowHeight + 4)
			local header = nav:FindFirstChild("Header")
			local left = header and header:FindFirstChild("Left")
			if header then header.Size = UDim2.new(1, 0, 0, 48) end
			if left then
				left.Size = UDim2.new(1, 0, 1, 0)
				local title = left:FindFirstChild("Title")
				if title then
					title.Position = UDim2.fromOffset(40, 7)
					local titleWidth = isTouchDevice and compact and math.clamp(self.Root.Size.X.Offset - 210, 40, 120) or (compact and 120 or 180)
					title.Size = UDim2.fromOffset(titleWidth, 34)
					for _, label in ipairs(title:GetChildren()) do
						if label:IsA("TextLabel") then
							local primary = label.Name == "Title"
							label.Position = UDim2.fromOffset(0, primary and 0 or 20)
							label.Size = UDim2.new(1, 0, 0, primary and 20 or 14)
							label.TextSize = primary and (isTouchDevice and compact and (self.Root.Size.X.Offset < 320 and 12 or 14) or 16) or 11
							label.TextWrapped = false
							label.TextTruncate = Enum.TextTruncate.AtEnd
						end
					end
				end
				for _, image in ipairs(left:GetChildren()) do
					if image:IsA("ImageLabel") then
						image.Position = UDim2.fromOffset(0, 8)
						image.Size = UDim2.fromOffset(32, 32)
					end
				end
			end
			local footer = nav:FindFirstChild("KeybindFooter")
			if footer then footer.Visible = false end
		end
		local divider = self.Body:FindFirstChild("SidebarDivider")
		if divider then
			divider.Visible = self._showTabStrip ~= false
			divider.Position = UDim2.fromOffset(12, stripTop - 3)
			divider.Size = UDim2.new(1, -24, 0, 1)
			divider.BackgroundTransparency = 0.65
		end
		if self._navScrollCue then self._navScrollCue.Visible = false end
		self.TabList.Position = UDim2.fromOffset(0, categoryTop)
		self.TabList.Size = UDim2.new(1, 0, 0, rowHeight + 4)
		if self.TabStrip then
			self.TabStrip.Position = UDim2.fromOffset(0, stripTop)
			self.TabStrip.Size = UDim2.new(1, 0, 0, rowHeight + 4)
		end
		for _, tab in ipairs(self.Tabs) do
			if tab._button then tab._button.Size = UDim2.fromOffset(tab._button.Size.X.Offset, rowHeight) end
		end
		for _, group in ipairs(self.TabList:GetChildren()) do
			if group:IsA("Frame") and group:FindFirstChild("Header") then
				group.Size = UDim2.fromOffset(group.Size.X.Offset, rowHeight)
				group.Header.Size = UDim2.new(1, 0, 1, 0)
			end
		end
		self.Content.Position = UDim2.fromOffset(12, contentTop)
		local footer = self.Body:FindFirstChild("KeybindBottomFooter")
		if footer then footer.Visible = true end
		local footerSpace = footer and footer.Size.Y.Offset + 12 or 0
		self.Content.Size = UDim2.new(1, -24, 1, -contentTop - 12 - footerSpace)
		for _, tab in ipairs(self.Tabs) do
			if tab._heading then tab._heading.FontFace = nativeFonts.Bold;tab._heading.TextSize = 22 end
		end
	end

	local function availableWindowSize(viewport)
		return Vector2.new(math.max(1, viewport.X - 24), math.max(1, viewport.Y - 24))
	end

	function NativeWindow:_fitToScreen(immediate)
		local viewport = self.Gui.AbsoluteSize
		if viewport.X <= 0 or viewport.Y <= 0 then
			return
		end
		local preferred = self._preferredSize or self.Root.Size
		local available = availableWindowSize(viewport)
		local size = preferred
		if self.Responsive and isTouchDevice and not self._manualSize then
			size = UDim2.fromOffset(math.min(preferred.X.Offset, available.X), available.Y)
		elseif self.Responsive and isTouchDevice then
			size = UDim2.fromOffset(
				math.clamp(preferred.X.Offset, 1, available.X),
				math.clamp(preferred.Y.Offset, 1, available.Y)
			)
		elseif self.Responsive then
			size = UDim2.fromOffset(
				math.clamp(preferred.X.Offset, 320, math.max(320, available.X)),
				math.clamp(preferred.Y.Offset, 260, math.max(260, available.Y))
			)
		end
		if self.Root.Size ~= size then
			self.Root.Size = size
		end
		self._compactLayout = size.X.Offset < 560 or viewport.Y < 430
		self:_layoutResponsive()
		self._fitScale = math.min(1, available.X / math.max(size.X.Offset, 1), available.Y / math.max(size.Y.Offset, 1))
		if self._introDone and self.Open then
			if immediate then
				self.Scale.Scale = self._fitScale
			else
				self.Scale.Scale = self._fitScale
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
			Size = UDim2.fromOffset(isTouchDevice and 44 or 32, isTouchDevice and 44 or 32),
			BackgroundTransparency = 1,
			Active = true,
			ZIndex = 20,
			Parent = self.Root,
		})
		resizeHandle.Name = "ResizeHandle"
		resizeHandle:SetAttribute("NoDrag", true)
		local resizingWindow = false
		local resizeIcon = createInstance("ImageLabel", {
			Name = "ResizeCorner", AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, -10, 0.5, -10), Size = UDim2.fromOffset(64, 64),
			BackgroundTransparency = 1, Image = "rbxassetid://120997033468887",
			ImageColor3 = nativeTheme.Muted, ImageTransparency = 0.45, ZIndex = 20, Parent = resizeHandle,
		})
		local function setResizeActive(active)
			animate(resizeIcon, {ImageTransparency = active and 0.1 or 0.45}, 0.12)
		end
		local startingSize = self.Root.Size
		local resizeStart = Vector2.zero
		local targetSize
		resizeHandle.InputBegan:Connect(function(input)
			if isPrimaryInput(input) then
				resizingWindow = true
				startingSize = self.Root.Size
				resizeStart = getPointerPosition()
				setResizeActive(true)
			end
		end)
		resizeHandle.MouseEnter:Connect(function()
			if not resizingWindow then
				setResizeActive(true)
			end
		end)
		resizeHandle.MouseLeave:Connect(function()
			if not resizingWindow then
				setResizeActive(false)
			end
		end)
		table.insert(
			self._connections,
			UserInputService.InputEnded:Connect(function(input)
				if resizingWindow and isPrimaryInput(input) then
					resizingWindow = false
					setResizeActive(false)
					if targetSize then
						self.Root.Size = UDim2.fromOffset(targetSize.X, targetSize.Y)
						self._preferredSize = self.Root.Size
						self._manualSize = true
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
				local available = availableWindowSize(viewport)
				maxWidth = math.min(maxWidth, isTouchDevice and available.X or math.max(320, available.X))
				maxHeight = math.min(maxHeight, isTouchDevice and available.Y or math.max(260, available.Y))
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

	function NativeWindow:_buildDashboardHome(config)
		local tab = self:Tab({Name = config.Name or "Início", Icon = config.Icon or "house"})
		tab._dashboard, tab._homeActions, tab._dashboardControls = true, {}, {}
		if tab._heading then tab._heading.Visible = false end
		local list = tab.List
		list.Position, list.Size = UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1)
		local padding = list:FindFirstChildOfClass("UIPadding")
		if padding then
			padding.PaddingTop, padding.PaddingBottom = UDim.new(0, 24), UDim.new(0, 24)
			padding.PaddingLeft, padding.PaddingRight = UDim.new(0, 20), UDim.new(0, 20)
		end
		local layout = list:FindFirstChildOfClass("UIListLayout")
		if layout then layout.Padding = UDim.new(0, 18) end
		local function text(parent, name, value, size, muted)
			return createLabel({Name = name, Text = value, TextSize = size,
				FontFace = muted and nativeFonts.Regular or nativeFonts.Bold,
				TextColor3 = muted and nativeTheme.Muted or nativeTheme.Text, Parent = parent})
		end
		local hero = createInstance("Frame", {Name = "HomeHero", Size = UDim2.new(1, 0, 0, 122), BackgroundTransparency = 1, LayoutOrder = 1, Parent = list})
		local title = text(hero, "Welcome", "Olá, " .. localPlayer.DisplayName .. ".", 32, false)
		title.Position, title.Size = UDim2.fromOffset(0, 30), UDim2.new(1, 0, 0, 42)
		local hint = text(hero, "Hint", "Suas funções estão nas categorias acima.", 13, true)
		hint.Position, hint.Size = UDim2.fromOffset(0, 84), UDim2.new(1, 0, 0, 20)
		local keyChip = createInstance("Frame", {Name = "AccessKeyPreview", AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(0, 22), AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = nativeTheme.Surface2, BackgroundTransparency = 0.15, BorderSizePixel = 0, Visible = false, Parent = hero})
		addCorner(keyChip, UDim.new(0, 4))
		addStroke(keyChip, nativeTheme.Stroke, 0.65)
		addPadding(keyChip, 9, 9)
		local keyText = text(keyChip, "Preview", "", 11, true)
		keyText.Size, keyText.AutomaticSize = UDim2.new(0, 0, 1, 0), Enum.AutomaticSize.X
		keyText.FontFace = Font.fromEnum(Enum.Font.Code)
		local function refreshKeyPreview()
			if self._destroyed or not keyChip.Parent then return end
			local ok, data = false, nil
			if type(config.AccessProvider) == "function" then ok, data = pcall(config.AccessProvider) end
			local preview = ok and type(data) == "table" and data.KeyPreview
			keyChip.Visible = type(preview) == "string" and preview ~= ""
			keyText.Text = keyChip.Visible and ("Chave · " .. preview) or ""
		end
		tab._refreshAccess = refreshKeyPreview
		refreshKeyPreview()
		local gameCard = createInstance("TextButton", {Name = "CurrentGame", Text = "", AutoButtonColor = false,
			Size = UDim2.new(1, 0, 0, 76), BackgroundColor3 = nativeTheme.Surface2, BackgroundTransparency = 0.12,
			BorderSizePixel = 0, LayoutOrder = 2, Parent = list})
		gameCard:SetAttribute("NoDrag", true)
		addStroke(gameCard, nativeTheme.Stroke, 0.5)
		local logo = createInstance("ImageLabel", {Name = "GameIcon", Position = UDim2.fromOffset(16, 14), Size = UDim2.fromOffset(48, 48),
			BackgroundTransparency = 1, Image = tonumber(game.GameId) and game.GameId > 0 and "rbxthumb://type=GameIcon&id=" .. tostring(game.GameId) .. "&w=150&h=150" or nativeAssets.Logo, Parent = gameCard})
		logo:SetAttribute("UIUnthemed", true)
		local gameName = text(gameCard, "GameName", config.GameName or "Roblox", 15, false)
		gameName.Position, gameName.Size = UDim2.fromOffset(72, 15), UDim2.new(1, -116, 0, 22)
		local gameHint = text(gameCard, "GameHint", config.Supported and "Abrir funções do jogo" or "Explore as funções gerais", 12, true)
		gameHint.Position, gameHint.Size = UDim2.fromOffset(72, 41), UDim2.new(1, -116, 0, 18)
		local arrow = createIcon(gameCard, "arrow-up-right", nativeTheme.Muted, UDim2.new(1, -30, 0.5, -8))
		arrow.Visible = config.Supported == true
		gameCard.Interactable = config.Supported == true
		gameCard.Activated:Connect(function()
			if not gameCard.Interactable then return end
			for _, candidate in ipairs(self.Tabs) do
				if candidate ~= tab and candidate._standalone then self:SelectTab(candidate);return end
			end
		end)
		local heading = text(list, "ActionsHeading", "ATALHOS DA SESSÃO", 11, true)
		heading.LayoutOrder, heading.Size = 3, UDim2.new(1, 0, 0, 16)
		local actions = createInstance("Frame", {Name = "HomeActions", BackgroundTransparency = 1, LayoutOrder = 4, Size = UDim2.new(1, 0, 0, 64), Parent = list})
		local grid = createInstance("UIGridLayout", {Name = "ActionGrid", SortOrder = Enum.SortOrder.LayoutOrder, CellPadding = UDim2.fromOffset(8, 8), HorizontalAlignment = Enum.HorizontalAlignment.Center, Parent = actions})
		local definitions = {
			{Id = "Rejoin", Title = "Reconectar", Desc = "Entrar novamente", Icon = "refresh-cw"},
			{Id = "ServerHop", Title = "Outro servidor", Desc = "Buscar outra sessão", Icon = "arrow-left-right"},
			{Id = "Discord", Title = "Comunidade", Desc = "Copiar convite", Icon = "rbxthumb://type=Asset&id=115249452401470&w=420&h=420"},
		}
		for index, definition in ipairs(definitions) do
			local contentOffset = definition.Id == "Discord" and 0 or 10
			local button = createInstance("TextButton", {Name = definition.Id, Text = "", AutoButtonColor = false,
				BackgroundColor3 = nativeTheme.Surface2, BackgroundTransparency = 0.5, BorderSizePixel = 0, LayoutOrder = index, Parent = actions})
			button:SetAttribute("NoDrag", true)
			addStroke(button, nativeTheme.Stroke, 0.65)
			local icon = createIcon(button, definition.Icon, nativeTheme.Muted, UDim2.new(0.5, 0, 0, 10 + contentOffset))
			icon.AnchorPoint = Vector2.new(0.5, 0)
			icon.Size = UDim2.fromOffset(24, 24)
			createIcon(button, "chevron-right", nativeTheme.Muted, UDim2.new(1, -28, 0, 14))
			local caption = text(button, "Title", definition.Title, 12, false)
			caption.Position, caption.Size = UDim2.fromOffset(14, 40 + contentOffset), UDim2.new(1, -28, 0, 20)
			caption.TextXAlignment = Enum.TextXAlignment.Center
			local status = text(button, "Status", definition.Desc, 11, true)
			status.Position, status.Size = UDim2.fromOffset(14, 64 + contentOffset), UDim2.new(1, -28, 0, 18)
			status.TextXAlignment = Enum.TextXAlignment.Center
			button.MouseEnter:Connect(function() if button.Interactable then animate(button, {BackgroundTransparency = 0.18}, 0.12) end end)
			button.MouseLeave:Connect(function() animate(button, {BackgroundTransparency = 0.5}, 0.12) end)
			button.Activated:Connect(function()
				local handler = tab._homeActions[definition.Id]
				if button.Interactable and type(handler) == "function" then invokeCallback(handler) end
			end)
			tab._dashboardControls[definition.Id] = {Button = button, Title = caption, Description = status, DefaultDescription = definition.Desc, Icon = icon}
		end
		local community = tab._dashboardControls.Discord
		community.Icon:SetAttribute("UIUnthemed", true)
		for _, image in ipairs(community.Icon:GetDescendants()) do
			if image:IsA("ImageLabel") then image:SetAttribute("UIUnthemed", true);image.ImageColor3 = Color3.new(1, 1, 1) end
		end
		community.Title.Position = UDim2.fromOffset(14, 36)
		community.Description.Position, community.Description.Size = UDim2.fromOffset(14, 56), UDim2.new(1, -28, 0, 14)
		local members = text(community.Button, "Members", "—", 15, false)
		members.Position, members.Size = UDim2.fromOffset(14, 76), UDim2.new(0.5, -16, 0, 20)
		local online = text(community.Button, "Online", "—", 15, false)
		online.Position, online.Size = UDim2.new(0.5, 4, 0, 76), UDim2.new(0.5, -16, 0, 20)
		local totalLabel = text(community.Button, "MembersCaption", "membros", 10, true)
		totalLabel.Position, totalLabel.Size = UDim2.fromOffset(14, 96), UDim2.new(0.5, -16, 0, 14)
		local onlineLabel = text(community.Button, "OnlineCaption", "online", 10, true)
		onlineLabel.Position, onlineLabel.Size = UDim2.new(0.5, 4, 0, 96), UDim2.new(0.5, -16, 0, 14)
		for _, label in ipairs({members, online, totalLabel, onlineLabel}) do label.TextXAlignment = Enum.TextXAlignment.Center end
		onlineLabel.TextColor3 = nativeTheme.Muted
		local nextCommunityRefresh, communityPending = 0, false
		local function count(value)
			if type(value) ~= "number" or value ~= value or value < 0 or value == math.huge then return "—" end
			return tostring(math.floor(value)):reverse():gsub("(%d%d%d)", "%1."):reverse():gsub("^%.", "")
		end
		local function refreshCommunity()
			if self._destroyed or not community.Button.Parent or communityPending or os.clock() < nextCommunityRefresh or type(config.CommunityProvider) ~= "function" then return end
			communityPending = true
			nextCommunityRefresh = os.clock() + 180
			task.spawn(function()
				local ok, data = pcall(config.CommunityProvider)
				communityPending = false
				if self._destroyed or not community.Button.Parent then return end
				if ok and type(data) == "table" then
					members.Text, online.Text = count(data.Members), count(data.Online)
				end
				task.delay(180, function()
					if not self._destroyed and self.Open and self.Gui.Enabled and self.CurrentTab == tab then refreshCommunity() end
				end)
			end)
		end
		tab._refreshCommunity = refreshCommunity
		refreshCommunity()
		local function arrange()
			if self._destroyed or not actions.Parent then return end
			local scale = self.Scale and math.max(self.Scale.Scale, 0.01) or 1
			local width = actions.AbsoluteSize.X / scale
			local gap, height = 8, 112
			local columns = math.clamp(math.floor((width + gap) / 160), 1, #definitions)
			grid.FillDirectionMaxCells = columns
			grid.CellSize = UDim2.fromOffset(math.max(1, math.min(220, math.floor((width - gap * (columns - 1)) / columns))), height)
			actions.Size = UDim2.new(1, 0, 0, math.ceil(#definitions / columns) * (height + gap) - gap)
			title.TextSize = width < 400 and 25 or 32
		end
		table.insert(self._connections, actions:GetPropertyChangedSignal("AbsoluteSize"):Connect(arrange))
		table.insert(self._connections, self.Scale:GetPropertyChangedSignal("Scale"):Connect(arrange))
		tab._dashboardLayout = arrange
		task.defer(arrange)
		return tab
	end

	function NativeWindow:_buildHome(homeConfig)
		if homeConfig.Dashboard then return self:_buildDashboardHome(homeConfig) end
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
				local expiresAt: any = metadata.ExpiresAt
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
			Size = UDim2.fromOffset(math.clamp((utf8.len(tab.Name) or #tab.Name) * 7 + 46, 88, 180), isTouchDevice and 44 or 34),
			BackgroundColor3 = nativeTheme.Surface2,
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
			LayoutOrder = #self.Tabs + 1,
			Parent = self.TabList,
		})
		local tabBorder = addStroke(tabButton, nativeTheme.Stroke, 1)
		tabBorder.LineJoinMode = Enum.LineJoinMode.Miter
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
			Position = UDim2.fromOffset(24, 15),
			FontFace = Font.fromEnum(Enum.Font.Garamond),
			Size = UDim2.new(1, -72, 0, 40),
			Text = tab.Name,
			TextSize = 22,
			Parent = tabFrame,
		})
		if tabConfig.Desc then
			tab._description = createLabel({
				Position = UDim2.fromOffset(24, 56),
				Size = UDim2.new(1, -72, 0, 16),
				Text = tabConfig.Desc,
				TextSize = 13,
				FontFace = nativeFonts.Regular,
				TextColor3 = nativeTheme.Muted,
				Parent = tabFrame,
			})
		end
		local headerHeight = tabConfig.ShowTabTitle == true and (tabConfig.Desc and 84 or 72) or 8
		tab._heading.Visible = tabConfig.ShowTabTitle == true
		if tab._description then tab._description.Visible = tabConfig.ShowTabTitle == true end
		tab._headerHeight = headerHeight
		local tabScroll = createInstance("ScrollingFrame", {
			Position = UDim2.fromOffset(0, headerHeight),
			Size = UDim2.new(1, 0, 1, -headerHeight),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = isTouchDevice and 5 or 2,
			ScrollBarImageColor3 = nativeTheme.Accent,
			ScrollBarImageTransparency = isTouchDevice and 0.15 or 0.5,
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			CanvasSize = UDim2.new(),
			Parent = tabFrame,
		})
		addPadding(tabScroll, isTouchDevice and 8 or 16, isTouchDevice and 8 or 16, 2, isTouchDevice and 12 or 24)
		createInstance(
			"UIListLayout",
			{ SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8), Parent = tabScroll }
		)
		tab.List = tabScroll
		tab._scrollCue = createScrollCue(self, tabScroll, tabFrame, "Mais opções abaixo")
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
				if self._destroyed or self.CurrentTab then return end
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

	-- The selected surface is enough; keep the legacy indicator hidden.
	function NativeWindow:_placeIndicator(tab)
		self.Indicator.Visible = false
		self.Indicator.BackgroundTransparency = 1
		self.Indicator.Size = UDim2.fromOffset(0, 0)
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
			animate(currentTab._label, { TextColor3 = nativeTheme.Muted }, 0.16)
			currentTab._label.FontFace = nativeFonts.Medium
			currentTab._button.BackgroundColor3 = nativeTheme.Surface2
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
				if not self._destroyed and self._transitionGeneration == transitionGeneration then
					self:_settleOut()
				end
			end)
		end
		tab._button.BackgroundColor3 = NativeLibrary.Navigation.Fill
		tab._stroke.Color = NativeLibrary.Navigation.Edge
		animate(tab._button, { BackgroundTransparency = 0.12 }, 0.16)
		animate(tab._stroke, { Transparency = 0.4 }, 0.16)
		tab._label.FontFace = nativeFonts.Bold
		animate(tab._label, { TextColor3 = NativeLibrary.Navigation.Foreground }, 0.16)
		if tab._icon and tab._iconThemed then
			animate(tab._icon, { ImageColor3 = NativeLibrary.Navigation.Foreground }, 0.16)
		end
		self:_placeIndicator(tab)
		local _page = tab._page
		_page.Position = UDim2.fromOffset(0, 0)
		_page.Visible = true
		_page.Parent = self._inLayer
		self._inPage = _page
		revealPage(self._inLayer)
		task.delay(0.32, function()
			if not self._destroyed and self._transitionGeneration == transitionGeneration then
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
			-- A escala animada recalcula o layout inteiro a cada quadro.
			self.Scale.Scale = self._fitScale or 1
			animate(self.Body, { GroupTransparency = 0 }, 0.25)
			animate(self.BodyStroke, { Transparency = 0 }, 0.25)
			animate(self.Shadow, { ImageTransparency = 0.6 }, 0.3)
		else
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
		local message = tostring(notificationConfig.Title or "") .. " " .. tostring(notificationConfig.Content or "")
		if self._feedbackButton and message:lower():find("copiad", 1, true) then
			self._feedbackButton()
			return { Dismiss = function() end }
		end
		self._toastKeys = self._toastKeys or {}
		local toastKey = tostring(notificationConfig.Title or "") .. "\0" .. tostring(notificationConfig.Content or "")
		local existing = self._toastKeys[toastKey]
		if existing and not existing.IsDismissed() then existing.Refresh(duration);return existing end
		while #self._toasts >= self._notifyLimit do
			self._toasts[1](true)
		end
		local height = notificationConfig.Content and NOTIFICATION_HEIGHT or 48
		local accentColor = nativeTheme.Text
		self._notifyOrder += 1
		local notificationSlot = createInstance(frameClass, {
			Size = UDim2.new(1, 0, 0, 0),
			BackgroundTransparency = 1,
			LayoutOrder = self._notifyOrder,
			Parent = self.NotifyHolder,
		})
		local notificationRoot = createInstance(frameClass, {
			Position = UDim2.fromOffset(0, 8),
			Size = UDim2.new(1, 0, 0, height),
			BackgroundTransparency = 1,
			Parent = notificationSlot,
		})
		local notificationBody = createInstance("CanvasGroup", {
			Size = UDim2.new(1, 0, 0, height),
			BackgroundColor3 = nativeTheme.Surface,
			BorderSizePixel = 0,
			GroupTransparency = 1,
			Parent = notificationRoot,
		})
		addCorner(notificationBody, UDim.new(0, 6))
		addStroke(notificationBody, nativeTheme.StrokeHover, 0.65)
		local notificationHeader = createInstance(frameClass, {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Parent = notificationBody,
		})
		addPadding(notificationHeader, 14, 14, 12, 12)
		local iconWidth = 0
		if notificationConfig.Icon then
			local icon = createIcon(
				notificationHeader,
				notificationConfig.Icon,
				accentColor == nativeTheme.Text and nativeTheme.Accent or accentColor,
				UDim2.new(0, 0, 0, 8)
			)
			icon.Size = UDim2.fromOffset(14, 14)
			iconWidth = 24
		end
		createLabel({
			Position = UDim2.fromOffset(iconWidth, 0),
			Size = UDim2.new(1, -32 - iconWidth, 0, 16),
			Text = notificationConfig.Title or "Notification",
			TextSize = 13,
			FontFace = nativeFonts.Medium,
			TextColor3 = accentColor,
			Parent = notificationHeader,
		})
		local dismissButton = createInstance("TextButton", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 8, 0, -8),
			Size = UDim2.fromOffset(isTouchDevice and 40 or 32, isTouchDevice and 40 or 32),
			BackgroundTransparency = 1,
			Text = "×",
			TextColor3 = nativeTheme.Muted,
			TextSize = 18,
			FontFace = nativeFonts.Regular,
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
				Size = UDim2.new(1, -iconWidth - 32, 0, 42),
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
			Position = UDim2.new(0, 0, 1, 0),
			Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = nativeTheme.Surface,
			BorderSizePixel = 0,
			Parent = notificationBody,
		})
		addCorner(progressTrack, UDim.new(1, 0))
		local progressFill = createInstance(frameClass, {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = nativeTheme.Muted,
			BorderSizePixel = 0,
			Parent = progressTrack,
		})
		addCorner(progressFill, UDim.new(1, 0))
		local dismissed = false
		local expiryThread
		local dismissNotification
		local toastHandle
		local function removeNotification()
			if self._toastKeys[toastKey] == toastHandle then self._toastKeys[toastKey] = nil end
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
			animate(notificationRoot, { Position = UDim2.fromOffset(0, 8) }, 0.16, Enum.EasingStyle.Quint)
			animate(notificationBody, { GroupTransparency = 1 }, 0.15)
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
			height = contentLabel and 46 + math.clamp(contentLabel.TextBounds.Y, 14, 42) or 48
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
		animate(progressFill, { Size = UDim2.fromScale(0, 1) }, duration, Enum.EasingStyle.Linear)
		expiryThread = task.delay(duration, dismissNotification)
		dismissButton.MouseButton1Click:Connect(dismissNotification)
		local repetitions = 1
		local handle = { Dismiss = dismissNotification, IsDismissed = function() return dismissed end }
		toastHandle = handle
		handle.Refresh = function(nextDuration)
			if dismissed then return end
			repetitions += 1
			if contentLabel then contentLabel.Text = tostring(notificationConfig.Content) .. "  ×" .. repetitions end
			if expiryThread and coroutine.status(expiryThread) == "suspended" then task.cancel(expiryThread) end
			progressFill.Size = UDim2.fromScale(1,1)
			animate(progressFill, {Size = UDim2.fromScale(0,1)}, nextDuration, Enum.EasingStyle.Linear)
			expiryThread = task.delay(nextDuration, dismissNotification)
		end
		self._toastKeys[toastKey] = handle
		return handle
	end

	function NativeWindow:_releaseResources()
		if self._resourcesReleased then return end
		self._resourcesReleased = true
		self._transitionGeneration = (self._transitionGeneration or 0) + 1
		self._outPage, self._inPage = nil, nil
		while #self._toasts > 0 do
			releaseInterfaceResource(table.remove(self._toasts, 1), true)
		end
		for index, window in ipairs(NativeLibrary.Windows) do
			if window == self then
				table.remove(NativeLibrary.Windows, index)
				break
			end
		end
		for index, connection in ipairs(self._connections) do
			releaseInterfaceResource(connection.Disconnect, connection)
		end
		table.clear(self._connections)
		for _, listeners in pairs(self._inputListeners) do
			table.clear(listeners)
		end
		table.clear(self._frameSteps)
		table.clear(self._controls)
	end

	function NativeWindow:Destroy()
		if self._destroyed then
			return
		end
		self._destroyed = true
		self:_releaseResources()
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
				Warning = Color3.fromRGB(240, 240, 240),
				Success = Color3.fromRGB(150, 150, 150),
				Error = Color3.fromRGB(240, 240, 240),
				Background = Color3.fromRGB(16, 16, 16),
				Surface = Color3.fromRGB(20, 20, 20),
				Surface2 = Color3.fromRGB(24, 24, 24),
				Surface3 = Color3.fromRGB(40, 40, 40),
				Stroke = Color3.fromRGB(36, 36, 36),
				StrokeHover = Color3.fromRGB(80, 80, 80),
				Accent = Color3.fromRGB(230, 230, 230),
				AccentDark = Color3.fromRGB(18, 18, 18),
				Text = Color3.fromRGB(232, 232, 232),
				Muted = Color3.fromRGB(130, 130, 130),
				Glow = Color3.fromRGB(220, 220, 220),
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
			TransparencyValue = 0.04,
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
				error(result, 0)
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
				TweenService:Create(handle._checkbox, TweenInfo.new(0.16), {BackgroundColor3 = handle.Value and UIEngine.Navigation.Fill or UIEngine.Theme.Surface}):Play()
				TweenService:Create(handle._checkmark, TweenInfo.new(0.16), {ImageTransparency = handle.Value and 0 or 1, Rotation = handle.Value and 0 or -15}):Play()
				local edge = handle._checkbox:FindFirstChildOfClass("UIStroke")
				edge.Color = handle.Value and UIEngine.Navigation.Edge or UIEngine.Theme.Stroke
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
			if config.AttachmentPicker then return end
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
					return nil
				end
				native = context._provider:CreateButton(opts)
			elseif kind == "Toggle" then
				opts.CurrentValue = config.Value == true
				native = context._provider:CreateToggle(opts)
			elseif kind == "Slider" then
				opts.Range = { handle.Value.Min, handle.Value.Max }
				opts.CurrentValue = handle.Value.Default
				opts.Increment = config.Step or 1
				opts.Suffix = config.Suffix
				native = context._provider:CreateSlider(opts)
			elseif kind == "Dropdown" then
				opts.AttachmentPicker = config.AttachmentPicker
			opts.Options = normalizeOptions(handle.Values)
				opts.CurrentOption = toNativeSelection(handle, config.Value)
				opts.MultipleOptions = handle.Multi
				opts.ExclusiveOption = config.ExclusiveOption
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
					Name = "Checkbox", AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -16, 0.5, 0),
					Size = UDim2.fromOffset(22, 22),
					BorderSizePixel = 0,
					Parent = native._frame,
				})
				new("UICorner", { CornerRadius = UDim.new(0, 4), Parent = box })
				new("UIStroke", { Color = UIEngine.Theme.Stroke, Parent = box })
				local mark =
					new("ImageLabel", { Position = UDim2.fromOffset(4, 4), Size = UDim2.fromOffset(14, 14), BackgroundTransparency = 1, Parent = box })
				setIcon(mark, "check", UIEngine.Navigation.Foreground)
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

		function ContainerMethods:PlayerPicker(config)
			config = config or {}
			local picker
			local function values()
				local result = {}
				for _, player in ipairs(Players:GetPlayers()) do
					if player ~= Players.LocalPlayer then result[#result+1] = {
						Title = player.DisplayName .. " (@" .. player.Name .. ")", Name = player.Name,
						Icon = "rbxthumb://type=AvatarHeadShot&id=" .. player.UserId .. "&w=150&h=150"
					} end
				end
				table.sort(result,function(a,b)return a.Name < b.Name end)
				return result
			end
			picker = self:Dropdown({Title = config.Title or "Jogador", Desc = "Selecione pelo nome ou avatar.",
				Values = values(), SearchBarEnabled = true, AllowNone = true, Callback = function(value)
					call(config.Callback, type(value) == "table" and value.Name or "")
				end})
			local function refresh() if not picker._destroyed then picker:Refresh(values()) end end
			picker._connections[#picker._connections+1] = Players.PlayerAdded:Connect(refresh)
			picker._connections[#picker._connections+1] = Players.PlayerRemoving:Connect(function() task.defer(refresh) end)
			return picker
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
			local joined = config.Joined == true
			local frame = new("Frame", {
				Name = "ControlGroup",
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = joined and 0 or 1,
				BackgroundColor3 = UIEngine.Theme.Surface2,
				LayoutOrder = self._provider:_nextOrder(),
				Parent = self._provider.List,
			})
			if joined then
				new("UICorner", { CornerRadius = UDim.new(0, 12), Parent = frame })
				new("UIStroke", { Color = UIEngine.Theme.Stroke, Thickness = 1, Parent = frame })
			end
			new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, joined and 0 or 8), Parent = frame })
			local header = new("TextLabel", {
				Name = "Title",
				Text = config.Title or "",
				Visible = not joined or (type(config.Title) == "string" and config.Title ~= ""),
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
			list:SetAttribute("UIJoinedControls", joined)
			new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, joined and 0 or 8), Parent = list })
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

		local function sectionHeadingText(value, premium, visual)
			local title = tostring(value or "Section")
			if premium then
				title = title:gsub("<font[^>]*>%[PREMIUM%]</font>", ""):gsub("%[PREMIUM%]", ""):gsub("%s+$", "")
			end
			if visual then
				title = title:gsub("<font[^>]*>%[VISUAL%]</font>", ""):gsub("%[VISUAL%]", ""):gsub("%s+$", "")
			end
			if premium or visual then title = title:gsub("<font[^>]*>", ""):gsub("</font>", ""):gsub("%s+$", "") end
			return title
		end
		-- Short, local disclosure motion; no scaling or rasterizing the full window.
		local premiumSectionColor = Color3.fromRGB(238, 207, 104)
		local visualSectionColor = Color3.fromRGB(153, 210, 255)
		local sectionOpenMotion = TweenInfo.new(0.24, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
		local sectionCloseMotion = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		function ContainerMethods:Section(config)
			config = type(config) == "table" and config or { Title = tostring(config or "") }
			local slot = new("Frame", {
				Name = "SectionSlot", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1, BorderSizePixel = 0,
				LayoutOrder = self._provider:_nextOrder(), Parent = self._provider.List,
			})
			new("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder, Parent = slot})
			local spaceBefore = new("Frame", {Name = "SpaceBefore", Size = UDim2.new(1, 0, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0, LayoutOrder = 1, Parent = slot})
			local spaceAfter = new("Frame", {Name = "SpaceAfter", Size = UDim2.new(1, 0, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0, LayoutOrder = 3, Parent = slot})
			local frame = new("Frame", {
				Name = "Section", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundColor3 = UIEngine.Theme.Surface, BackgroundTransparency = 1, BorderSizePixel = 0,
				LayoutOrder = 2, Parent = slot,
			})
			new("UICorner", {CornerRadius = UDim.new(0, 6), Parent = frame})
			local groupEdge = new("UIStroke", {Name = "SectionOutline", Color = UIEngine.Theme.StrokeHover, Transparency = 1, Parent = frame})
			new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = frame })
			local header = new("TextButton", {
				Name = "SectionHeader", Size = UDim2.new(1, 0, 0, 60), Text = "", AutoButtonColor = false,
				BackgroundColor3 = UIEngine.Theme.Surface2, BackgroundTransparency = 0.4,
				BorderSizePixel = 0, LayoutOrder = 1, Parent = frame,
			})
			header:SetAttribute("NoDrag", true)
			header:SetAttribute("UIRole", "SectionHeader")
			header:SetAttribute("MichigunSection", true)
			new("UICorner", { CornerRadius = UDim.new(0, 6), Parent = header })
			local edge = new("UIStroke", {Color = UIEngine.Theme.Stroke, Transparency = 0.65, Parent = header})
			local stamp, icon
			if config.Icon then
				stamp = new("Frame", {
					Name = "SectionIcon", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.5, 0),
					Size = UDim2.fromOffset(30, 30), BackgroundColor3 = UIEngine.Navigation.Foreground,
					BackgroundTransparency = 0.93, BorderSizePixel = 0, Parent = header,
				})
				new("UICorner", {CornerRadius = UDim.new(0, 5), Parent = stamp})
				icon = new("ImageLabel", {Name = "Icon", Position = UDim2.fromOffset(7, 7), Size = UDim2.fromOffset(16, 16), BackgroundTransparency = 1, Parent = stamp})
				setIcon(icon, config.Icon, UIEngine.Theme.Text)
			end
			local inset = icon and 54 or 16
			local premium = config.__PremiumSection == true
			local visual = config.__VisualSection == true or tostring(config.Title or ""):find("[VISUAL]", 1, true) ~= nil
			local badgeCount = (premium and 1 or 0) + (visual and 1 or 0)
			local sectionAccent = premium and premiumSectionColor or UIEngine.Navigation.Accent
			local words = new("Frame", {
				Name = "Heading", Position = UDim2.fromOffset(inset, 12), Size = UDim2.new(1, -inset - (50 + badgeCount * 62), 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = header,
			})
			new("UIListLayout", {Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = words})
			local function headingLabel(name, text, size, tint, font, order)
				return new("TextLabel", {
					Name = name, Text = text, TextSize = size, TextColor3 = tint, FontFace = font,
					Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundTransparency = 1, RichText = true, TextWrapped = true,
					TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
					LayoutOrder = order, Parent = words,
				})
			end
			local title = headingLabel("Title", sectionHeadingText(config.Title, premium, visual), 15, UIEngine.Theme.Text, UIEngine.Fonts.Medium, 1)
			local description = headingLabel("Description", config.Desc or "", 12, UIEngine.Theme.Muted, UIEngine.Fonts.Regular, 2)
			description.Visible = config.Desc ~= nil and config.Desc ~= ""
			local badgeIndex = 0
			local function createBadge(name, text, tint)
				badgeIndex += 1
				return new("TextLabel", {
					Name = name, Text = text, TextSize = 11, FontFace = UIEngine.Fonts.Medium,
					TextColor3 = tint, BackgroundTransparency = 1,
					Position = UDim2.new(1, -50 - badgeIndex * 62, 0, 14), Size = UDim2.fromOffset(62, 18), Parent = header,
				})
			end
			local badge = premium and createBadge("PremiumBadge", "Premium", premiumSectionColor) or nil
			local visualBadge = visual and createBadge("VisualBadge", "Visual", visualSectionColor) or nil
			local disclosure = new("Frame", {
				Name = "Disclosure", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0),
				Size = UDim2.fromOffset(22, 22), BackgroundTransparency = 1, Parent = header,
			})
			local minus = new("Frame", {Name = "Minus", Position = UDim2.fromOffset(5, 10), Size = UDim2.fromOffset(12, 2), BackgroundColor3 = UIEngine.Theme.Muted, BorderSizePixel = 0, Parent = disclosure})
			local plus = new("Frame", {Name = "Plus", Position = UDim2.fromOffset(10, 5), Size = UDim2.fromOffset(2, 12), BackgroundColor3 = UIEngine.Theme.Muted, BorderSizePixel = 0, Parent = disclosure})
			local mark = new("Frame", {
				Name = "OpenMark", Position = UDim2.new(0, inset, 1, -2), Size = UDim2.fromOffset(0, 2),
				BackgroundColor3 = sectionAccent, BorderSizePixel = 0, Parent = header,
			})
			local body = new("Frame", {
				Name = "SectionBody", Size = UDim2.new(1, 0, 0, 0), ClipsDescendants = true,
				BackgroundTransparency = 1, LayoutOrder = 2, Parent = frame,
			})
			new("Frame", {
				Name = "SectionRail", Position = UDim2.fromOffset(8, 12), Size = UDim2.new(0, 2, 1, -24),
				BackgroundColor3 = sectionAccent, BackgroundTransparency = 0.65, BorderSizePixel = 0, Parent = body,
			})
			local list = new("Frame", {
				Name = "Controls", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1, Parent = body,
			})
			new("UIPadding", {PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 16), PaddingBottom = UDim.new(0, 16), Parent = list})
			new("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8), Parent = list})
			local section = context(self, provider(self, list), frame)
			section.__type, section._config = "Section", config
			section.Title, section.Desc = title.Text, config.Desc or ""
			section.Opened, section.Locked = config.Opened == true, config.Locked == true
			section.LockedTitle = config.LockedTitle
			section.UIElements.Title, section.UIElements.Desc = title, description
			section.UIElements.Header, section.UIElements.Container = header, list
			section.UIElements.Icon, section.UIElements.PremiumBadge = icon, badge
			section.UIElements.VisualBadge = visualBadge
			section.UIElements.Body = body
			local hovered, initialized = false, false
			local tweens, completion = {}, nil
			local function stopMotion()
				disconnect(completion)
				completion = nil
				for _, tween in ipairs(tweens) do tween:Cancel() end
				table.clear(tweens)
			end
			local function paint(target, properties, motion)
				if motion then
					local tween = TweenService:Create(target, motion, properties)
					tweens[#tweens + 1] = tween
					tween:Play()
					return tween
				end
				for key, value in pairs(properties) do target[key] = value end
				return nil
			end
			local function refreshStyle()
				local expanded = section.Opened or (body.Visible and body.Size.Y.Offset > 0)
				frame.BackgroundColor3 = expanded and premium and UIEngine.Theme.Surface:Lerp(premiumSectionColor, 0.045) or UIEngine.Theme.Surface
				frame.BackgroundTransparency = expanded and 0.05 or 1
				groupEdge.Color = premium and premiumSectionColor or UIEngine.Theme.StrokeHover
				groupEdge.Transparency = expanded and (premium and 0.72 or 0.45) or 1
				header.BackgroundColor3 = expanded and premium and UIEngine.Theme.Surface2:Lerp(premiumSectionColor, 0.065) or UIEngine.Theme.Surface2
				header.BackgroundTransparency = hovered and 0.12 or (section.Opened and 0.22 or 0.4)
				edge.Color = section.Opened and sectionAccent or UIEngine.Theme.Stroke
				edge.Transparency = expanded and 1 or 0.65
				title.TextColor3 = expanded and premium and premiumSectionColor or UIEngine.Theme.Text
				description.TextColor3 = UIEngine.Theme.Muted
				minus.BackgroundColor3 = section.Opened and sectionAccent or UIEngine.Theme.Muted
				plus.BackgroundColor3 = UIEngine.Theme.Muted
				if icon then icon.ImageColor3 = section.Opened and sectionAccent or UIEngine.Theme.Text end
			end
			local function updateBody(animated)
				stopMotion()
				local opened = section.Opened
				local scale = math.max(section._window._native.Scale.Scale, 0.01)
				local height = opened and list.AbsoluteSize.Y / scale or 0
				local motion = animated and (opened and sectionOpenMotion or sectionCloseMotion) or nil
				local gap = opened and (UIEngine.Touch and 10 or 16) or 0
				paint(spaceBefore, {Size = UDim2.new(1, 0, 0, gap)}, motion)
				paint(spaceAfter, {Size = UDim2.new(1, 0, 0, gap)}, motion)
				body.Visible, list.Visible = true, true
				body.ClipsDescendants = true
				refreshStyle()
				paint(plus, {Rotation = opened and 90 or 0, BackgroundTransparency = opened and 1 or 0}, motion)
				paint(mark, {Size = UDim2.fromOffset(opened and 32 or 0, 2)}, motion)
				if stamp then paint(stamp, {BackgroundTransparency = opened and 0.84 or 0.93}, motion) end
				paint(list, {Position = UDim2.fromOffset(0, opened and 0 or -6)}, motion)
				local tween = paint(body, {Size = UDim2.new(1, 0, 0, height)}, motion)
				local function finish()
					body.Visible, list.Visible = opened, opened
					body.ClipsDescendants = not opened
					refreshStyle()
					disconnect(completion)
					completion = nil
					table.clear(tweens)
				end
				if tween then completion = connect(tween.Completed, finish) else finish() end
			end
			section._header = { _frame = header, RefreshStyle = refreshStyle }
			section._native = {Destroy = function() stopMotion();slot:Destroy() end}
			function section:SetTitle(value)
				return ControlMethods.SetTitle(self, sectionHeadingText(value, premium, visual))
			end
			function section:SetDesc(value)
				self.Desc = tostring(value or "")
				description.Text, description.Visible = self.Desc, self.Desc ~= ""
				return self
			end
			function section:SetOpened(opened)
				if self._destroyed then return self end
				opened = opened == true
				if initialized and self.Opened == opened then return self end
				self.Opened = opened
				updateBody(initialized)
				initialized = true
				return self
			end
			section.Open = function(self) return self:SetOpened(true) end
			section.Close = function(self) return self:SetOpened(false) end
			section.SetOpen = section.SetOpened
			local function listen(signal, callback)
				section._connections[#section._connections + 1] = connect(signal, callback)
			end
			listen(header.Activated, function()
				if not section._destroyed and not isLocked(section) then section:SetOpened(not section.Opened) end
			end)
			listen(header.MouseEnter, function() hovered = true;refreshStyle() end)
			listen(header.MouseLeave, function() hovered = false;refreshStyle() end)
			listen(words:GetPropertyChangedSignal("AbsoluteSize"), function()
				if section._destroyed then return end
				local scale = math.max(section._window._native.Scale.Scale, 0.01)
				header.Size = UDim2.new(1, 0, 0, math.max(52, words.AbsoluteSize.Y / scale + 24))
			end)
			listen(list:GetPropertyChangedSignal("AbsoluteSize"), function()
				if not section._destroyed and section.Opened then updateBody(completion ~= nil) end
			end)
			section:SetOpened(section.Opened)
			if section.Locked then section:Lock(config.LockedTitle) end
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
			new("UICorner", { CornerRadius = UDim.new(0, 16), Parent = frame })
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
			local copySurface, copyText = Color3.fromRGB(38, 38, 38), Color3.fromRGB(224, 224, 224)
			local chatSurface, chatText = Color3.fromRGB(42, 42, 42), Color3.fromRGB(232, 232, 232)
			local clear = button(frame, "Limpar", 56)
			clear.TextSize = 11
			clear.Size = UDim2.fromOffset(56, UIEngine.Touch and 44 or 28)
			clear.AnchorPoint, clear.Position = Vector2.new(1, 0), UDim2.new(1, -12, 0, 6)
			local documentRow = new("Frame", {
				Name = "ChatDocument",
				Position = UDim2.fromOffset(12, 62),
				Size = UDim2.new(1, -24, 0, UIEngine.Touch and 44 or 34),
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
			local _messageLayout = new(
				"UIListLayout",
				{ SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 14), Parent = messages }
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
			local emptyTitle = text(empty, "O que vamos resolver?", 19, false, true)
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
			corner(composer, 16)
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
				Size = UDim2.new(1, -4, 0, 20),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				ClearTextOnFocus = false,
				Text = "",
				PlaceholderText = "Coloque sua pergunta aqui",
				MultiLine = true,
				TextWrapped = true,
				TextSize = 15,
				FontFace = UIEngine.Fonts.Regular,
				TextColor3 = UIEngine.Theme.Text,
				PlaceholderColor3 = UIEngine.Theme.Muted,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				Parent = draftScroll,
			})
			input:SetAttribute("NoDrag", true)
			local send = button(composer, "", 44)
			send.Name = "SendMessage"
			local sendIcon = new("ImageLabel", {
				Name = "SendIcon", Image = "rbxassetid://94849431195865",
				BackgroundTransparency = 1, ImageColor3 = UIEngine.Theme.Text,
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(20, 20), Parent = send,
			})
			corner(send, 12)
			send.AnchorPoint, send.Position = Vector2.new(1, 0.5), UDim2.new(1, -8, 0.5, 0)
			local hint =
				text(frame, UIEngine.Touch and "Toque em Enviar para conversar" or "Enter para enviar · Shift + Enter para nova linha", 10, true)
			hint.AnchorPoint, hint.Position = Vector2.new(0, 1), UDim2.new(0, 16, 1, -6)
			hint.Size = UDim2.new(1, -32, 0, 18)
			local function refreshSend()
				send.Interactable = not handle._busy and input.Text:match("%S") ~= nil
				send.BackgroundTransparency = send.Interactable and 0 or 0.4
			sendIcon.ImageTransparency = send.Interactable and 0 or 0.5
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
				if handle._destroyed then return end
				local page = self._provider.List
				local scale = self._window._native.Scale
				local zoom = scale and scale.Scale > 0 and scale.Scale or 1
				local padding = page:FindFirstChildOfClass("UIPadding")
				local inset = padding and (padding.PaddingTop.Offset + padding.PaddingBottom.Offset) or 0
				local available = math.max(0, page.AbsoluteSize.Y / zoom - inset)
				local documentHeight = documentRow.Visible
					and (handle._documents and handle._documents.Frame.Size.Y.Offset or (UIEngine.Touch and 44 or 34)) or 0
				local offset = UIEngine.Touch and 52 or 40
				local attachmentHeight = documentHeight > 0 and documentHeight + 8 or 0
				local minimumDraft = UIEngine.Touch and 56 or 50
				local draftHeight = math.clamp(input.TextBounds.Y + 20, minimumDraft, math.max(minimumDraft, math.min(112, available * 0.28)))
				local height = math.max(available, offset + draftHeight + 34 + attachmentHeight + 80)
				frame.Size = UDim2.new(1, 0, 0, height)
				composer.Size = UDim2.new(1, -24, 0, draftHeight)
				composer.Position = UDim2.new(0, 12, 1, -30)
				send.Size = UDim2.fromOffset(44, UIEngine.Touch and 44 or 36)
				documentRow.AnchorPoint = Vector2.new(0, 1)
				documentRow.Position = UDim2.new(0, 12, 1, -(draftHeight + 38))
				documentRow.Size = UDim2.new(1, -24, 0, documentHeight)
				local bottom = draftHeight + 34 + attachmentHeight
				messages.Position, messages.Size = UDim2.fromOffset(0, offset), UDim2.new(1, 0, 1, -(offset + bottom))
				empty.Position, empty.Size = UDim2.fromOffset(16, offset), UDim2.new(1, -32, 1, -(offset + bottom))
				local messageHeight = height - offset - bottom
				local greetingTop = math.max(8, (messageHeight - 80) / 2)
				emptyTitle.AnchorPoint = Vector2.new(0.5, 0)
				emptyTitle.Position, emptyTitle.Size = UDim2.new(0.5, 0, 0, greetingTop), UDim2.new(1, 0, 0, 26)
				emptyTitle.TextSize = messageHeight < 120 and 16 or 19
				emptyDesc.Position, emptyDesc.Size = UDim2.new(0.5, 0, 0, greetingTop + 30), UDim2.new(1, 0, 0, 40)
				emptyDesc.Text = "Tire uma dúvida, revise um texto ou consulte um documento."

			end
			bind(handle, self._provider.List:GetPropertyChangedSignal("AbsoluteSize"), layoutChat)
			bind(handle, input:GetPropertyChangedSignal("TextBounds"), layoutChat)
			bind(handle, self._window._native.Scale:GetPropertyChangedSignal("Scale"), layoutChat)
			layoutChat()
			function handle:Documents(options)
				if self._documents then
					return self._documents
				end
				options = table.clone(options or {})
				options.Title, options.Desc = "Anexar documento", nil
				options.AttachmentPicker = true
				options.SearchBarEnabled = true
				options.MaxVisibleOptions = 4
				local documentsContext = context(self, provider(self._context, documentRow), documentRow)
				self._documents = ContainerMethods.Dropdown(documentsContext, options)
				local refresh = self._documents.Refresh
				self._documents.Refresh = function(control, values, ...)
					local result = refresh(control, values, ...)
					documentRow.Visible = type(values) == "table" and #values > 1
					layoutChat()
					return result
				end
				documentRow.Visible = type(options.Values) == "table" and #options.Values > 1
				bind(self, self._documents.Frame:GetPropertyChangedSignal("Size"), layoutChat)
				layoutChat()
				return self._documents
			end

			function handle:SetContext(_value)
				return self
			end

			function handle:SetInput(value)
				input.Text = tostring(value or "")
				return self
			end

			local function formatMessageText(value)
				local source = tostring(value or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
				local parts, inCode, previousPlain = {}, false, false
				for line in (source .. "\n"):gmatch("(.-)\n") do
					local clean = line:gsub("^[ \t]+", ""):gsub("[ \t]+$", "")
					local fence = clean:match("^```") or clean:match("^~~~")
					local structured = clean == "" or clean:match("^[#>*|]") or clean:match("^[-+]%s")
						or clean:match("^%d+[%.%)]%s") or line:match("^    ") or line:match("^\t")
					local plain = not inCode and not fence and not structured
					if #parts > 0 then parts[#parts + 1] = previousPlain and plain and " " or "\n" end
					parts[#parts + 1] = inCode and line or clean
					previousPlain = plain and not line:match("  $") and not line:match("\\$")
					if fence then inCode = not inCode end
				end
				return table.concat(parts):gsub("%s+$", "")
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
					Size = UDim2.new(isUser and 0.86 or 1, 0, 0, 0),
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
				if not isUser and not message.Pending then rawText = formatMessageText(rawText) end
				local content = text(body, rawText, 14, false)
				content.Size, content.AutomaticSize = UDim2.new(1, 0, 0, 0), Enum.AutomaticSize.Y
				content.TextWrapped, content.TextTruncate = true, Enum.TextTruncate.None
				content.TextYAlignment, content.LayoutOrder = Enum.TextYAlignment.Top, 2
				entry.UIElements.Message = content
				local function layoutMessage()
					if entry._destroyed or not content.Parent then return end
					local zoom = math.max(self._window._native.Scale.Scale, 0.01)
					local available = body.AbsoluteSize.X / zoom
					if available <= 0 then return end
					local width = math.max(1, math.floor(available) - (isUser and 24 or 0))
					if content.Size.X.Scale ~= 0 or content.Size.X.Offset ~= width then
						content.Size = UDim2.fromOffset(width, 0)
					end
				end
				bind(entry, body:GetPropertyChangedSignal("AbsoluteSize"), layoutMessage)
				bind(entry, self._window._native.Scale:GetPropertyChangedSignal("Scale"), layoutMessage)
				layoutMessage()
				if message.Pending then
					content.Visible = false
					author.Text = "Pensando"
					author.TextColor3 = UIEngine.Theme.Text
					author.Size = UDim2.fromOffset(132, 18)
					local shimmer = new("UIGradient", {
						Name = "ThinkingShimmer",
						Color = ColorSequence.new({
							ColorSequenceKeypoint.new(0, Color3.fromRGB(110, 110, 110)),
							ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
							ColorSequenceKeypoint.new(1, Color3.fromRGB(110, 110, 110)),
						}),
						Offset = Vector2.new(-1, 0),
						Parent = author,
					})
					local shimmerTween = TweenService:Create(shimmer,
						TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1),
						{ Offset = Vector2.new(1, 0) })
					entry.UIElements.ThinkingStatus = author
					local destroy = entry.Destroy
					entry.Destroy = function(object)
						shimmerTween:Cancel()
						return destroy(object)
					end
					row.Destroying:Connect(function() shimmerTween:Cancel() end)
					shimmerTween:Play()
				end
				if not isUser and not message.Pending then
					local formatted = rawText:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
					formatted = formatted:gsub("%*%*(.-)%*%*", "<b>%1</b>")
					formatted = formatted:gsub("^#+%s+([^\n]+)", "<b>%1</b>"):gsub("\n#+%s+([^\n]+)", "\n<b>%1</b>")
					content.RichText, content.Text = true, formatted
				end
				if isUser and type(message.Attachment) == "string" and message.Attachment ~= "" then
					local attachment = new("Frame", {
						Name = "AttachedDocument", BackgroundColor3 = UIEngine.Theme.Surface2,
						BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 28), LayoutOrder = 3, Parent = body,
					})
					corner(attachment, 6)
					new("ImageLabel", {
						Image = "rbxassetid://91719007832323", ImageColor3 = UIEngine.Theme.Muted,
						BackgroundTransparency = 1, Position = UDim2.fromOffset(8, 6),
						Size = UDim2.fromOffset(16, 16), Parent = attachment,
					})
					local label = text(attachment, "Documento anexado · " .. message.Attachment, 11, true)
					label.Position, label.Size = UDim2.fromOffset(30, 0), UDim2.new(1, -38, 1, 0)
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
					local function responseAction(caption, asset)
						local control = button(actions, "", 0)
						control.Name = caption
						local icon = new("ImageLabel", {
							BackgroundTransparency = 1, Image = asset, ImageColor3 = UIEngine.Theme.Muted,
							AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0),
							Size = UDim2.fromOffset(16, 16), Parent = control,
						})
						local label = text(control, caption, 11, true)
						label.Position, label.Size = UDim2.fromOffset(32, 0), UDim2.new(1, -38, 1, 0)
						return control, label, icon
					end
					local copy, copyCaption, copyIcon = responseAction("Copiar", "rbxassetid://116378866141355")
					tintAction(entry, copy, copySurface, copyText)
					local gameChat, chatCaption, chatIcon = responseAction("Enviar no chat", "rbxassetid://86432989388834")
					tintAction(entry, gameChat, chatSurface, chatText)
					local function layoutActions()
						local scale = self._window._native.Scale.Scale
						local compact = actions.AbsoluteSize.X / math.max(scale, 0.01) < 220
						local height = UIEngine.Touch and 44 or 28
						local copyWidth, chatWidth = compact and 44 or 82, compact and 44 or 130
						actions.Size = UDim2.new(1, 0, 0, height)
						copy.Size = UDim2.fromOffset(copyWidth, height)
						gameChat.Position = UDim2.fromOffset(copyWidth + 6, 0)
						gameChat.Size = UDim2.fromOffset(chatWidth, height)
						copyCaption.Visible, chatCaption.Visible = not compact, not compact
						copyIcon.Position = UDim2.new(0, compact and 14 or 10, 0.5, 0)
						chatIcon.Position = copyIcon.Position
					end
					bind(entry, actions:GetPropertyChangedSignal("AbsoluteSize"), layoutActions)
					layoutActions()
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
				hint.Text = "Gerando resposta · " .. duration
				if self._pending and not self._pending._destroyed then
					local status = self._pending.UIElements.ThinkingStatus
					if status then status.Text = elapsed >= 15 and "Ainda pensando" or "Pensando" end
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
				send.Text = self._busy and "…" or ""
				sendIcon.Visible = not self._busy
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
					or "Enter para enviar · Shift + Enter para nova linha"
				if self._busy and not self._pending then
					local messageAdded, pending = pcall(self.AddMessage, self, { Text = "Pensando…", Pending = true })
					if messageAdded then
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

			local function submit(draft)
				if handle._destroyed or handle._busy then
					return
				end
				local value = (type(draft) == "string" and draft or input.Text):match("^%s*(.-)%s*$")
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
					and not UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
					and not UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
				then
					task.defer(submit, input.Text)
				end
			end)
			bind(handle, input.Focused, function()
				TweenService:Create(inputBorder, TweenInfo.new(0.16), { Color = UIEngine.Theme.StrokeHover }):Play()
			end)
			bind(handle, input.FocusLost, function()
				TweenService:Create(inputBorder, TweenInfo.new(0.16), { Color = UIEngine.Theme.Stroke }):Play()
			end)
			bind(handle, clear.Activated, function()
				if #handle._messages == 0 then
					return
				end
				if confirmingClear then
					call(config.OnClear)
					handle:Clear()
				else
					confirmingClear, clear.Text = true, "Limpar?"
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
			config = type(config) == "table" and table.clone(config) or { Desc = tostring(config or "") }
			config.Title = config.Title or config.Name or ""
			local handle = createParagraph(self, config)
			local frame, heading, body = handle.Frame, handle.UIElements.Title, handle.UIElements.Desc
			frame:SetAttribute("UIRole", "Paragraph")
			frame.BackgroundColor3, frame.BackgroundTransparency = UIEngine.Theme.Surface2, 0.15
			local stroke = frame:FindFirstChildOfClass("UIStroke")
			if stroke then stroke.Color = UIEngine.Theme.Stroke;stroke.Transparency = 0.8 end
			local corner = frame:FindFirstChildOfClass("UICorner")
			if corner then corner.CornerRadius = UDim.new(0, 5) end
			local padding = frame:FindFirstChildOfClass("UIPadding")
			if padding then
				padding.PaddingLeft, padding.PaddingRight = UDim.new(0, 12), UDim.new(0, 12)
				padding.PaddingTop, padding.PaddingBottom = UDim.new(0, 12), UDim.new(0, 12)
			end
			local layout = frame:FindFirstChildOfClass("UIListLayout")
			if layout then layout.Padding = UDim.new(0, 6) end
			heading.TextColor3, heading.FontFace, heading.TextSize = UIEngine.Theme.Text, UIEngine.Fonts.Medium, 13
			heading.Size, heading.AutomaticSize = UDim2.new(1, 0, 0, 0), Enum.AutomaticSize.Y
			heading.TextWrapped, heading.TextTruncate = true, Enum.TextTruncate.None
			heading.LayoutOrder = 1
			if body then
				body.TextColor3 = config.BodyTextColor or UIEngine.Theme.Muted:Lerp(UIEngine.Theme.Text, 0.45)
				body.TextSize, body.LineHeight = config.BodyTextSize or 13, config.BodyLineHeight or 1.3
				body.Size, body.AutomaticSize = UDim2.new(1, 0, 0, 0), Enum.AutomaticSize.Y
				body.TextWrapped, body.TextTruncate = true, Enum.TextTruncate.None
				body.LayoutOrder = 2
			end
			local header
			if config.Image then
				local imageSize = typeof(config.ImageSize) == "UDim2" and config.ImageSize
					or UDim2.fromOffset(tonumber(config.ImageSize) or 18, tonumber(config.ImageSize) or 18)
				header = new("Frame", {Name = "ParagraphHeading", Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, LayoutOrder = 1, Parent = frame})
				heading.Parent = header
				heading.AnchorPoint, heading.Position = Vector2.new(0, 0.5), UDim2.new(0, imageSize.X.Offset + 10, 0.5, 0)
				heading.Size = UDim2.new(1, -imageSize.X.Offset - 10, 0, 0)
				local image = new("ImageLabel", {
					Name = "Icon", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0),
					Size = imageSize, BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit, Parent = header,
				})
				setIcon(image, config.Image, UIEngine.Theme.Muted)
				local function resizeHeader()
					if handle._destroyed then return end
					local scale = math.max(handle._context._window._native.Scale.Scale, 0.01)
					header.Size = UDim2.new(1, 0, 0, math.max(imageSize.Y.Offset, heading.AbsoluteSize.Y / scale))
				end
				handle._connections[#handle._connections + 1] = connect(heading:GetPropertyChangedSignal("AbsoluteSize"), resizeHeader)
				task.defer(resizeHeader)
				handle.UIElements.Icon = image
			end
			local function updateHeading()
				if handle._destroyed then return end
				heading.Visible = heading.Text ~= ""
			end
			handle._connections[#handle._connections + 1] = connect(heading:GetPropertyChangedSignal("Text"), updateHeading)
			updateHeading()
			if type(config.Buttons) == "table" and #config.Buttons > 0 then
				local paragraphContext = context(self, provider(self, frame), frame)
				self._children[paragraphContext] = nil
				paragraphContext._context = handle
				handle._children[paragraphContext] = true
				local row = paragraphContext:HStack()
				row.Frame.LayoutOrder = 3
				for _, button in ipairs(config.Buttons) do row:Button(button) end
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
				local stopTime = math.clamp(tonumber(position) / 100, 0, 1)
				local hex = type(value) == "table" and (value.Color or value[1]) or value
				local opacity = type(value) == "table" and (value.Transparency or value[2]) or 0
				colors[#colors + 1] =
					ColorSequenceKeypoint.new(stopTime, typeof(hex) == "Color3" and hex or Color3.fromHex(hex))
				transparencies[#transparencies + 1] = NumberSequenceKeypoint.new(stopTime, opacity or 0)
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
			if self._destroyed then
				return
			end
			if self.Window then
				local result = self.Window._native:Notify(config)
				textLabels(self.ScreenGui)
				return result
			end
			self._pendingNotifications = self._pendingNotifications or {}
			self._pendingNotifications[#self._pendingNotifications + 1] = config
			return nil
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
			self._native._manualSize = true
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

		function WindowMethods:CreateTopbarButton(title, icon, callback, order, showTitle, tint, iconSize)
			local button = new("TextButton", {
				Name = title,
				Size = UDim2.fromOffset(showTitle and 106 or 28, 28),
				BackgroundTransparency = 1,
				Text = showTitle and title or "",
				TextSize = 12,
				FontFace = UIEngine.Fonts.Medium,
				TextColor3 = tint or UIEngine.Theme.Text,
				AutoButtonColor = false,
				LayoutOrder = order or 1,
				Parent = self.UIElements.Topbar.Right,
			})
			button:SetAttribute("NoDrag", true)
			button:SetAttribute("TopbarCaption", showTitle == true)
			if showTitle and icon then new("UIPadding", { PaddingLeft = UDim.new(0, 20), Parent = button }) end
			if icon then
			local image = new("ImageLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = showTitle and UDim2.new(0, -6, 0.5, 0) or UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(iconSize or 16, iconSize or 16),
				BackgroundTransparency = 1,
				Parent = button,
			})
			setIcon(image, icon, tint)
			end
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
							tab._heading.Position = UDim2.fromOffset(24, 15 + actionsOffset)
							if tab._description then
								tab._description.Position = UDim2.fromOffset(24, 56 + actionsOffset)
							end
							tab._heading.Size = UDim2.fromOffset(titleWidth, 40)
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
				Size = UDim2.fromOffset(64, 30),
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
				TextXAlignment = Enum.TextXAlignment.Center,
				AutoButtonColor = false,
				LayoutOrder = 1,
				Parent = group,
			})
			local title = new("TextLabel", {
				Name = "Title",
				Text = config.Title or "",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				FontFace = UIEngine.Fonts.Bold,
				TextSize = 12,
				TextColor3 = UIEngine.Theme.Text,
				TextXAlignment = Enum.TextXAlignment.Center,
				RichText = true,
				Parent = header,
			})
			header:SetAttribute("NoDrag", true)
			local border = new("UIStroke", { Color = UIEngine.Theme.Stroke, Transparency = 1, Thickness = 1, LineJoinMode = Enum.LineJoinMode.Miter, Parent = header })
			local categoryMark = new("Frame", {Name = "CategoryMark", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 8, 1, -2), Size = UDim2.new(1, -16, 0, 2), BackgroundColor3 = UIEngine.Navigation.Accent, BorderSizePixel = 0, Parent = header})
			title.Position = UDim2.fromOffset(8, 0)
			title.Size = UDim2.new(1, -36, 1, 0)
			local chevron = new("ImageLabel", { Size = UDim2.fromOffset(12, 12), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -12, 0.5, 0), BackgroundTransparency = 1, Parent = header })
			setIcon(chevron, "chevron-down", UIEngine.Theme.Muted)
			local list = new("Frame", {
				Name = "Tabs",
				-- Leave room for the centered UIStroke above and beside each tab.
				Position = UDim2.fromOffset(2, 1),
				Size = UDim2.new(0, 0, 1, -3),
				AutomaticSize = Enum.AutomaticSize.X,
				BackgroundTransparency = 1,
				LayoutOrder = 2,
				Visible = config.Opened == true,
				Parent = self._native.TabStrip,
			})
			new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4), Parent = list })
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
				if self._navigationStyled and self.Opened == (opened == true) then return self end
				self._navigationStyled = true
				self.Opened = opened == true
				list.Visible = self.Opened
				title.TextColor3 = self.Opened and UIEngine.Theme.Text or UIEngine.Theme.Muted
				header.BackgroundColor3 = UIEngine.Theme.Surface2
				header.BackgroundTransparency = 1
				border.Color = self.Opened and UIEngine.Navigation.Edge or UIEngine.Theme.Stroke
				border.Thickness = self.Opened and 1.5 or 1
				border.Transparency = 1
				categoryMark.Visible = self.Opened
				TweenService:Create(chevron, TweenInfo.new(0.25, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
					Rotation = self.Opened and 180 or 0,
					ImageColor3 = self.Opened and UIEngine.Navigation.Accent or UIEngine.Theme.Muted
				}):Play()
				if self.Opened then
					for _, other in ipairs(self._window._navigationSections) do
						if other ~= self then other:SetOpened(false) end
					end
					self._window._native.TabStrip.CanvasPosition = Vector2.zero
					self._window._native.TabStrip.CanvasSize = UDim2.fromOffset(list.AbsoluteSize.X + 4, 0)
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
			self._navigationSections = self._navigationSections or {}
			table.insert(self._navigationSections, section)
			section._native = {Destroy = function() list:Destroy();group:Destroy() end}
			local function layoutSectionWidth()
				if section._destroyed or not title.Parent then return end
				local scale = math.max(self._native.Scale.Scale, 0.01)
				group.Size = UDim2.fromOffset(math.max(64, math.ceil(title.TextBounds.X / scale) + 36), 30)
			end
			section._connections[#section._connections + 1] = connect(title:GetPropertyChangedSignal("TextBounds"), layoutSectionWidth)
			section._connections[#section._connections + 1] = connect(self._native.Scale:GetPropertyChangedSignal("Scale"), layoutSectionWidth)
			layoutSectionWidth()
			section:SetOpened(section.Opened)
			section._connections[#section._connections + 1] = connect(list:GetPropertyChangedSignal("AbsoluteSize"), function()
				if section.Opened then self._native.TabStrip.CanvasSize = UDim2.fromOffset(list.AbsoluteSize.X + 4, 0) end
			end)
			section._connections[#section._connections + 1] = connect(header.Activated, function()
				if not section.Locked then
					section:SetOpened(true)
					for _, tab in ipairs(self.TabModule.Tabs) do
						if tab._sidebarSection == section and not tab.Locked then tab:Select();break end
					end
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
				ShowTabTitle = config.ShowTabTitle == true,
				EmptyText = config.CustomEmptyPage and config.CustomEmptyPage.Desc or "Preparando os controles",
			})
			return self:_wrapTab(native, config, iconThemed)
		end

		function WindowMethods:_wrapTab(native, config, iconThemed)
			native._standalone = config.Standalone == true
						if native._icon then
				native._icon:SetAttribute("UIUnthemed", not iconThemed)
			end
			self._navigationGroups = self._navigationGroups or {}
			local title = tostring(config.Title or config.Name or ""):lower()
			local category = (title:find("config") or title:find("atalho") or title:find("api") or title:find("tema")) and "Configurações"
				or (title:find("player") or title:find("personagem") or title:find("avatar")) and "Personagem" or "Jogo"
			local parent = not config.Standalone and (self._sidebarSection or self._navigationGroups[category]) or nil
			if not parent and not config.Standalone then
				local previous = self._sidebarSection
				parent = self:Section({Title = category, Opened = true})
				self._sidebarSection = previous
				self._navigationGroups[category] = parent
			end
			if parent then
				native._button.Parent = parent._list
			end
			self._sidebarOrder += 1
			native._button.LayoutOrder = config.Standalone and (config.NavigationOrder or 0) or (parent and #self.TabModule.Tabs + 1 or self._sidebarOrder)
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
			local tab = self:_wrapTab(native, { Title = config.Name, Icon = config.Icon, Standalone = true }, true)
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
			control.Button.BackgroundTransparency = busy and 0.7 or 0.5
			control.Description.Visible = true
			control.Description.Text = description or control.DefaultDescription or ""
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
			self._native._transitionGeneration = (self._native._transitionGeneration or 0) + 1
			if not external then self._native:_settleTransition() end
			self._native._outPage, self._native._inPage = nil, nil
			self._destroyed = true
			Library._destroyed = true
			local children = {}
			for child in pairs(self._children) do
				children[#children + 1] = child
			end
			for _, child in ipairs(children) do
				releaseInterfaceResource(child.Destroy, child)
			end
			local controls = {}
			for control in pairs(Library._controls) do
				controls[#controls + 1] = control
			end
			for _, control in ipairs(controls) do
				releaseInterfaceResource(control.Destroy, control)
			end
			for connection in pairs(Library._connections) do
				releaseInterfaceResource(connection.Disconnect, connection)
			end
			Library._connections = {}
			if external then
				self._native._destroyed = true
				releaseInterfaceResource(self._native._releaseResources, self._native)
			else
				releaseInterfaceResource(self._native.Destroy, self._native)
			end
			self.PendingFlags = {}
			Library.ScreenGui = nil
			call(self._onDestroy)
		end

		function Library:Destroy()
			if self.Window then
				return self.Window:Destroy()
			end
			return nil
		end


		function Library:CreateWindow(config)
			assert(not self.Window, "Só é possível criar uma janela de UI por instância")
			config = config or {}
			self:SetTheme(config.Theme or self:GetCurrentTheme() or "Dark")
			UIEngine.Assets.Logo = config.Icon or "rbxassetid://115139843331828"
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

			local author = titleGroup:FindFirstChild("Author")
			if author and config.Author == "Premium" then
				author.TextColor3 = Color3.fromRGB(232, 232, 232)
				author.TextStrokeTransparency = 1
			end
			local topbar = new("Frame", {
				Name = "UITopbar",
				Size = UDim2.new(1, 0, 0, 48),
				BackgroundTransparency = 1,
				Parent = native.Body,
			})
			local brandTitle = titleGroup:FindFirstChild("Title")
			if brandTitle then table.insert(native._connections, brandTitle:GetPropertyChangedSignal("TextBounds"):Connect(function() native:_layoutResponsive() end)) end
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
				elseif tab then
					for _, section in ipairs(window._navigationSections or {}) do section:SetOpened(false) end
				end
				local showTabs = tab and tab._sidebarSection ~= nil
				if native._showTabStrip ~= showTabs then
					native._showTabStrip = showTabs
					native.TabStrip.Visible = showTabs
					native:_layoutResponsive()
				end
				nativeSelect(object, selected)
				if selected._refreshCommunity then selected._refreshCommunity() end
				if selected._refreshAccess then selected._refreshAccess() end
				task.defer(function()
					task.wait() -- Allow the horizontal canvas to finish layout before revealing the selection.
					if window._destroyed or native.CurrentTab ~= selected then return end
					local scale = math.max(native.Scale.Scale, 0.01)
					local function reveal(scroll, button)
						local width = scroll.AbsoluteSize.X / scale
						local left = (button.AbsolutePosition.X - scroll.AbsolutePosition.X) / scale + scroll.CanvasPosition.X
						local right = left + button.AbsoluteSize.X / scale
						local offset: number = scroll.CanvasPosition.X
						if left < offset then offset = left elseif right > offset + width then offset = right - width end
						scroll.CanvasPosition = Vector2.new(math.max(0, offset), 0)
					end
					if tab and tab._sidebarSection then
						reveal(native.TabList, tab._sidebarSection.Frame)
						reveal(native.TabStrip, selected._button)
					else reveal(native.TabList, selected._button) end
				end)
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
