-- STRAFE FPS | Skin Changer (local only)
--
-- WHAT IT DOES
--   * Skins: pick any weapon skin and your own gun shows it. The skins are already in the game's files on your PC.
--   * Knife look: make your Knife use the model and animations of a Karambit, Butterfly, Katana and so on.
--   Only YOU see the change. Other players still see what the server says you have equipped, and your inventory,
--   purchases and loadout are not touched.
--
-- HOW TO USE
--   1. Run the script. A window opens. RightShift hides or shows it.
--   2. Pick a weapon on the left, then click a skin on the right (click it again to turn it off).
--   3. Switch to another weapon and back. Skins are applied when a weapon is equipped.
--   Your choices are saved and come back the next time you run the script.

if _G.StrafeSkinChanger and _G.StrafeSkinChanger.unload then pcall(_G.StrafeSkinChanger.unload) end

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local lp = Players.LocalPlayer

local SAVE_FILE = "strafe_skin_changer.json"
local alive = true
local conns = {}
local function keep(c) conns[#conns + 1] = c; return c end

-- the game's modules can only be required from a thread with identity 2 (executors run at 8), so anything that
-- touches them goes through g(): it runs the function in such a thread, waits for it, and returns pcall's results
local function g(fn, ...)
	local args, res, done = table.pack(...), nil, false
	task.spawn(function()
		if type(setthreadidentity) == "function" then pcall(setthreadidentity, 2) end
		res = table.pack(pcall(fn, table.unpack(args, 1, args.n)))
		done = true
	end)
	local t = os.clock()
	while not done and os.clock() - t < 5 do task.wait() end
	if not res then return false, "timed out" end
	return table.unpack(res, 1, res.n)
end

local SM, SC, CC
g(function()
	SM = require(RS.Classes.Combat.SkinManager)
	SC = require(RS.Classes.Combat.SkinsConfig)
	local okC, c = pcall(require, RS.Classes.Combat.CasesConfig)
	if okC then CC = c end
end)
if not (SM and SC) then
	warn("[SkinChanger] This doesn't look like STRAFE FPS (its skin scripts were not found), so nothing was changed.")
	return
end

-- ===================== saved choices =====================
local sel = {}   -- weapon name -> skin name   (plus "__style" = the knife look, "__seenHelp" = true)
pcall(function()
	if type(readfile) == "function" and type(isfile) == "function" and isfile(SAVE_FILE) then
		local d = HttpService:JSONDecode(readfile(SAVE_FILE))
		if type(d) == "table" then
			for k, v in pairs(d) do
				if type(k) == "string" and (type(v) == "string" or v == true) then sel[k] = v end
			end
		end
	end
end)
local function save()
	pcall(function() if type(writefile) == "function" then writefile(SAVE_FILE, HttpService:JSONEncode(sel)) end end)
end

-- ===================== skin lists =====================
-- weapons come from the game's model folder; only weapons that have texture skins are listed
local weapons, skinsOf = {}, {}
local function computeSkins(w)   -- needs identity 2: call through g()
	local list = {}
	local ok, all = pcall(SC.getSkinsForWeapon, w)
	if ok and type(all) == "table" then
		for _, s in ipairs(all) do
			local okA, _, kind = pcall(SC.getSkinAsset, s.name)
			if okA and (kind == "texture" or kind == "tiled") then
				local color, rname
				if CC then
					pcall(function() color = CC.getRarityColor(s.rarity) end)
					pcall(function() rname = CC.getRarityDisplayName(s.rarity) end)
				end
				list[#list + 1] = {
					name = s.name, display = s.displayName or s.name, rarity = rname or tostring(s.rarity or ""),
					color = typeof(color) == "Color3" and color or nil,
				}
			end
		end
	end
	table.sort(list, function(a, b) return a.display < b.display end)
	return list
end
local function skinsFor(w)
	if not skinsOf[w] then
		local ok, list = g(computeSkins, w)
		skinsOf[w] = (ok and type(list) == "table") and list or {}
	end
	return skinsOf[w]
end
g(function()
	local models = RS:FindFirstChild("Models")
	if not models then return end
	for _, m in ipairs(models:GetChildren()) do
		local list = computeSkins(m.Name)
		skinsOf[m.Name] = list
		if #list > 0 then weapons[#weapons + 1] = m.Name end
	end
	table.sort(weapons)
end)

-- ===================== knife look =====================
-- Karambit, Butterfly and the other melee weapons are separate weapons with their own model and animations, but the
-- same damage and range as the Knife. "Knife look" makes the game build your Knife from another weapon's model and
-- animations. The server is still told you hold the Knife, so nothing about your loadout or what others see changes.
local styles = {}
g(function()
	local gm, models = RS:FindFirstChild("GunModules"), RS:FindFirstChild("Models")
	if not (gm and models and gm:FindFirstChild("Knife")) then return end
	local base = require(gm.Knife)
	for _, m in ipairs(gm:GetChildren()) do
		if m:IsA("ModuleScript") and m.Name ~= "Knife" and models:FindFirstChild(m.Name) then
			local ok, r = pcall(require, m)
			if ok and type(r) == "table" and r.weaponType == "MELEE" and r.damage == base.damage and r.range == base.range then
				styles[#styles + 1] = m.Name
			end
		end
	end
	table.sort(styles)
end)

-- numbers that matter for how the knife plays stay the Knife's own; only the look and animations are borrowed
local STYLE_KEEP = {
	damage = true, headshot = true, range = true, swingCooldown = true, walkSpeed = true, canAim = true,
	canReload = true, magSize = true, gunType = true, weaponType = true,
}
local stash = { model = nil, fields = nil }
local knifeStyle = nil

local function restoreStyle()   -- needs identity 2: call through g()
	local models, gm = RS:FindFirstChild("Models"), RS:FindFirstChild("GunModules")
	if stash.model and models then
		local cur = models:FindFirstChild("Knife")
		if cur and cur ~= stash.model then cur:Destroy() end
		stash.model.Parent = models
	end
	if stash.fields and gm and gm:FindFirstChild("Knife") then
		local base = require(gm.Knife)
		for k in pairs(base) do base[k] = nil end
		for k, v in pairs(stash.fields) do base[k] = v end
	end
	stash.model, stash.fields = nil, nil
	knifeStyle = nil
end

local function setStyle(name)   -- needs identity 2: call through g()
	restoreStyle()
	if not name or name == "" then return true end
	local models, gm = RS:FindFirstChild("Models"), RS:FindFirstChild("GunModules")
	local srcModel, srcMod = models and models:FindFirstChild(name), gm and gm:FindFirstChild(name)
	local knifeModel = models and models:FindFirstChild("Knife")
	if not (srcModel and srcMod and knifeModel and gm:FindFirstChild("Knife")) then return false end
	local base, src = require(gm.Knife), require(srcMod)
	local fields = {}
	for k, v in pairs(base) do fields[k] = v end
	-- make sure the module table can be written before anything is changed
	if not pcall(function() base.__probe = 1; base.__probe = nil end) then return false end
	stash.model, stash.fields = knifeModel, fields
	knifeModel.Parent = nil
	local copy = srcModel:Clone()
	copy.Name = "Knife"
	copy.Parent = models
	for k in pairs(fields) do if not STYLE_KEEP[k] then base[k] = nil end end
	for k, v in pairs(src) do if not STYLE_KEEP[k] then base[k] = v end end
	knifeStyle = name
	return true
end

-- ===================== the hook =====================
local hits = 0
local origEquipped = SM.applyEquippedSkin
SM.applyEquippedSkin = function(model, weapon, equipped, inventory)
	local want = sel[(weapon == "Knife" and knifeStyle) or weapon]
	if want and model then
		local ok, res = pcall(SM.applySkin, model, want)
		if ok and res then hits += 1; return res end
	end
	return origEquipped(model, weapon, equipped, inventory)
end

-- put the choice on the gun that is in your hands right now
local function findGun(weapon)
	local function scan(root)
		if not root then return nil end
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("Model") and d.Name == weapon and (d:FindFirstChild("Parts") or d:FindFirstChild("GunComponents") or d:GetAttribute("AppliedSkinName") ~= nil) then
				return d
			end
		end
		return nil
	end
	return scan(workspace.CurrentCamera) or scan(lp.Character) or nil
end
local function applyNow(weapon)
	local skin = sel[weapon]
	local gun = findGun(weapon == knifeStyle and "Knife" or weapon)
	if not gun then return false end
	if skin then
		local ok, res = g(SM.applySkin, gun, skin)
		return ok and res and true or false
	end
	return (g(SM.removeSkin, gun))
end

-- ===================== window =====================
local C = {
	bg = Color3.fromRGB(20, 21, 27), panel = Color3.fromRGB(30, 31, 40), item = Color3.fromRGB(42, 44, 56),
	itemHover = Color3.fromRGB(54, 57, 72), sel = Color3.fromRGB(58, 98, 210), text = Color3.fromRGB(236, 237, 242),
	dim = Color3.fromRGB(150, 153, 168), good = Color3.fromRGB(96, 208, 130), warn = Color3.fromRGB(240, 180, 90),
}
local gui = Instance.new("ScreenGui")
gui.Name = "StrafeSkinChanger"; gui.ResetOnSpawn = false; gui.DisplayOrder = 50; gui.IgnoreGuiInset = true
pcall(function() if type(syn) == "table" and syn.protect_gui then syn.protect_gui(gui) end end)
do   -- gethui can throw on some executors, so every parent is tried in turn
	local parents = {
		function() return type(gethui) == "function" and gethui() or nil end,
		function() return game:GetService("CoreGui") end,
		function() return lp:WaitForChild("PlayerGui", 5) end,
	}
	for _, get in ipairs(parents) do
		local ok, p = pcall(get)
		if ok and typeof(p) == "Instance" then
			local okP = pcall(function() gui.Parent = p end)
			if okP and gui.Parent == p then break end
		end
	end
	if not gui.Parent then warn("[SkinChanger] Couldn't place the window anywhere."); return end
end

local function corner(o, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 6); c.Parent = o end
local function make(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	o.Parent = parent
	return o
end
local function text(parent, str, size, color, pos, sz, align, font)
	return make("TextLabel", {
		BackgroundTransparency = 1, Text = str, TextSize = size, Font = font or Enum.Font.Gotham, TextColor3 = color or C.text,
		Position = pos, Size = sz, TextXAlignment = align or Enum.TextXAlignment.Left, TextWrapped = true,
	}, parent)
end
local function button(parent, str, pos, sz, bg)
	local b = make("TextButton", {
		Text = str, Position = pos, Size = sz, BackgroundColor3 = bg or C.item, TextColor3 = C.text,
		Font = Enum.Font.GothamMedium, TextSize = 13, AutoButtonColor = true,
	}, parent)
	corner(b, 6)
	return b
end

local win = make("Frame", {
	Size = UDim2.fromOffset(640, 440), Position = UDim2.new(0.5, -320, 0.5, -220), BackgroundColor3 = C.bg, BorderSizePixel = 0,
}, gui)
corner(win, 10)

-- a small tab to bring the window back after hiding it
local pill = button(gui, "Skin Changer", UDim2.new(0.5, -55, 0, 6), UDim2.fromOffset(110, 26), C.panel)
pill.Visible = false
local function setOpen(open) win.Visible = open; pill.Visible = not open end
pill.MouseButton1Click:Connect(function() setOpen(true) end)

local top = make("Frame", { Size = UDim2.new(1, 0, 0, 42), BackgroundColor3 = C.panel, BorderSizePixel = 0 }, win)
corner(top, 10)
text(top, "Skin Changer", 17, C.text, UDim2.fromOffset(14, 0), UDim2.fromOffset(150, 42), nil, Enum.Font.GothamBold)
text(top, "only you can see these changes", 12, C.dim, UDim2.fromOffset(150, 0), UDim2.new(1, -330, 1, 0))
local closeBtn = button(top, "X", UDim2.new(1, -36, 0, 8), UDim2.fromOffset(28, 26))
local hideBtn = button(top, "–", UDim2.new(1, -70, 0, 8), UDim2.fromOffset(28, 26))
local helpBtn = button(top, "?", UDim2.new(1, -104, 0, 8), UDim2.fromOffset(28, 26))

-- dragging by the title bar
do
	local dragging, startPos, startMouse
	keep(top.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = true; startPos = win.Position; startMouse = i.Position end
	end))
	keep(UIS.InputChanged:Connect(function(i)
		if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then
			local d = i.Position - startMouse
			win.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end))
	keep(UIS.InputEnded:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end end))
end

-- bottom bar: status line and reset buttons
local bar = make("Frame", { Position = UDim2.new(0, 10, 1, -52), Size = UDim2.new(1, -20, 0, 44), BackgroundColor3 = C.panel, BorderSizePixel = 0 }, win)
corner(bar, 8)
local status = text(bar, "", 12, C.dim, UDim2.fromOffset(12, 0), UDim2.new(1, -250, 1, 0))
local resetOne = button(bar, "Reset this one", UDim2.new(1, -236, 0, 8), UDim2.fromOffset(110, 28))
local resetAll = button(bar, "Reset everything", UDim2.new(1, -120, 0, 8), UDim2.fromOffset(112, 28))
local function setStatus(t, kind)
	status.Text = t
	status.TextColor3 = (kind == "good" and C.good) or (kind == "warn" and C.warn) or C.dim
end

local function column(x, w, title, withSearch)
	local f = make("Frame", { Position = UDim2.fromOffset(x, 50), Size = UDim2.new(0, w, 1, -110), BackgroundColor3 = C.panel, BorderSizePixel = 0 }, win)
	corner(f, 8)
	text(f, title, 12, C.dim, UDim2.fromOffset(12, 6), UDim2.new(1, -24, 0, 16), nil, Enum.Font.GothamMedium)
	local search
	local listTop = 28
	if withSearch then
		search = make("TextBox", {
			Position = UDim2.fromOffset(8, 26), Size = UDim2.new(1, -16, 0, 26), BackgroundColor3 = C.item, TextColor3 = C.text,
			PlaceholderText = "Search skins...", PlaceholderColor3 = C.dim, Text = "", Font = Enum.Font.Gotham, TextSize = 13,
			ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left,
		}, f)
		corner(search, 6)
		make("UIPadding", { PaddingLeft = UDim.new(0, 8) }, search)
		listTop = 58
	end
	local s = make("ScrollingFrame", {
		Position = UDim2.fromOffset(6, listTop), Size = UDim2.new(1, -12, 1, -(listTop + 6)), BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 4, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, f)
	make("UIListLayout", { Padding = UDim.new(0, 4) }, s)
	return s, search
end
local wCol = column(10, 190, "WEAPON")
local sCol, searchBox = column(208, 422, "SKIN", true)

local current      -- selected weapon (or the knife-look entry)
local weaponBtns, skinBtns = {}, {}
local refreshSkins
local STYLE_ENTRY = "Knife look"

-- a list row: left stripe (rarity colour), name, small tag on the right, blue when in use
local function row(parent, name, tag, active, stripe)
	local b = make("TextButton", {
		Size = UDim2.new(1, -4, 0, 30), BackgroundColor3 = active and C.sel or C.item, Text = "", AutoButtonColor = false,
	}, parent)
	corner(b, 6)
	if stripe then
		local st = make("Frame", { Size = UDim2.new(0, 4, 1, -10), Position = UDim2.fromOffset(5, 5), BackgroundColor3 = stripe, BorderSizePixel = 0 }, b)
		corner(st, 2)
	end
	text(b, name, 13, C.text, UDim2.fromOffset(stripe and 16 or 12, 0), UDim2.new(1, -110, 1, 0))
	if tag and tag ~= "" then
		text(b, tag, 11, active and C.text or C.dim, UDim2.new(1, -102, 0, 0), UDim2.fromOffset(94, 30), Enum.TextXAlignment.Right)
	end
	b.MouseEnter:Connect(function() if not active then b.BackgroundColor3 = C.itemHover end end)
	b.MouseLeave:Connect(function() if not active then b.BackgroundColor3 = C.item end end)
	return b
end

local entries = {}
if #styles > 0 then entries[1] = STYLE_ENTRY end
for _, w in ipairs(weapons) do entries[#entries + 1] = w end

local function refreshWeapons()
	for _, b in pairs(weaponBtns) do b:Destroy() end
	weaponBtns = {}
	for _, w in ipairs(entries) do
		local tag
		if w == STYLE_ENTRY then tag = knifeStyle or "" else tag = sel[w] and "custom" or "" end
		local b = row(wCol, w, tag, w == current)
		weaponBtns[w] = b
		b.MouseButton1Click:Connect(function() current = w; searchBox.Text = ""; refreshWeapons(); refreshSkins() end)
	end
end

local function chooseStyle(name)
	local ok, res = g(setStyle, name)
	if ok and res then
		sel.__style = name   -- nil clears it
		save()
		setStatus(name and (name .. " look is on. Switch to another weapon and back to your knife to see it.") or "Back to the normal Knife. Switch weapons and back to see it.", "good")
	else
		setStatus("Couldn't change the knife look, so nothing was changed.", "warn")
	end
	refreshWeapons(); refreshSkins()
end

local function note(str)
	local l = text(sCol, str, 12, C.dim, UDim2.new(), UDim2.new(1, -8, 0, 0), nil, Enum.Font.Gotham)
	l.AutomaticSize = Enum.AutomaticSize.Y
	skinBtns[#skinBtns + 1] = l
end

function refreshSkins()
	for _, b in pairs(skinBtns) do b:Destroy() end
	skinBtns = {}
	if not current then return end
	if current == STYLE_ENTRY then
		searchBox.Visible = false
		note("Choose which weapon your Knife looks and swings like. Damage and range stay the Knife's own, and other players still see a normal Knife.")
		local d0 = row(sCol, "Normal Knife", "default", knifeStyle == nil)
		skinBtns[#skinBtns + 1] = d0
		d0.MouseButton1Click:Connect(function() chooseStyle(nil) end)
		for _, name in ipairs(styles) do
			local b = row(sCol, name, knifeStyle == name and "in use" or "", knifeStyle == name)
			skinBtns[#skinBtns + 1] = b
			b.MouseButton1Click:Connect(function() chooseStyle(name) end)
		end
		return
	end
	searchBox.Visible = true
	local q = string.lower(searchBox.Text or "")
	local d = row(sCol, "My own skin (default)", sel[current] == nil and "in use" or "", sel[current] == nil)
	skinBtns[#skinBtns + 1] = d
	d.MouseButton1Click:Connect(function()
		sel[current] = nil; save(); refreshWeapons(); refreshSkins()
		applyNow(current)
		setStatus("Back to your own skin for the " .. current .. ". Switch weapons and back if it doesn't change right away.", "good")
	end)
	local shown = 0
	for _, s in ipairs(skinsFor(current)) do
		if q == "" or string.find(string.lower(s.display), q, 1, true) or string.find(string.lower(s.rarity), q, 1, true) then
			shown += 1
			local on = sel[current] == s.name
			local b = row(sCol, s.display, on and "in use" or s.rarity, on, s.color)
			skinBtns[#skinBtns + 1] = b
			b.MouseButton1Click:Connect(function()
				if sel[current] == s.name then sel[current] = nil else sel[current] = s.name end
				save(); refreshWeapons(); refreshSkins()
				if sel[current] then
					local ok = applyNow(current)
					setStatus(ok and ("Applied to the " .. current .. " in your hands.") or ("Saved. Switch to another weapon and back to see it on the " .. current .. "."), "good")
				else
					applyNow(current)
					setStatus("Turned off. Your own skin comes back when you re-equip.", "good")
				end
			end)
		end
	end
	if shown == 0 then note("No skins match \"" .. (searchBox.Text or "") .. "\".") end
end

keep(searchBox:GetPropertyChangedSignal("Text"):Connect(function() if current and current ~= STYLE_ENTRY then refreshSkins() end end))

resetOne.MouseButton1Click:Connect(function()
	if not current then return end
	if current == STYLE_ENTRY then chooseStyle(nil); return end
	sel[current] = nil; save(); refreshWeapons(); refreshSkins(); applyNow(current)
	setStatus("Reset the " .. current .. ".", "good")
end)
resetAll.MouseButton1Click:Connect(function()
	local seen = sel.__seenHelp
	for k in pairs(sel) do sel[k] = nil end
	sel.__seenHelp = seen
	g(setStyle, nil)
	save(); refreshWeapons(); refreshSkins()
	setStatus("Everything is back to normal. Switch weapons and back to see it.", "good")
end)

-- help card (shown the first time, and with the ? button)
local help = make("Frame", {
	Size = UDim2.fromOffset(420, 250), Position = UDim2.new(0.5, -210, 0.5, -125), BackgroundColor3 = C.panel, BorderSizePixel = 0,
	Visible = false, ZIndex = 20,
}, win)
corner(help, 10)
make("UIStroke", { Color = C.sel, Thickness = 1.5 }, help)
local helpText = text(help,
	"How it works\n\n1.  Pick a weapon on the left.\n2.  Click a skin on the right. Click it again to turn it off.\n3.  Switch to another weapon and back. Skins are applied when a weapon is equipped.\n\n\"Knife look\" lets your Knife use the model and animations of a Karambit, Butterfly and more.\n\nOnly you see these changes. Your inventory and what other players see are not touched.\n\nRightShift hides or shows this window.",
	13, C.text, UDim2.fromOffset(18, 14), UDim2.new(1, -36, 1, -64))
helpText.ZIndex = 21
helpText.TextYAlignment = Enum.TextYAlignment.Top
local gotIt = button(help, "Got it", UDim2.new(0.5, -50, 1, -44), UDim2.fromOffset(100, 30), C.sel)
gotIt.ZIndex = 21
local function showHelp(on) help.Visible = on end
helpBtn.MouseButton1Click:Connect(function() showHelp(not help.Visible) end)
gotIt.MouseButton1Click:Connect(function() showHelp(false); sel.__seenHelp = true; save() end)

hideBtn.MouseButton1Click:Connect(function() setOpen(false) end)
keep(UIS.InputBegan:Connect(function(i, gp)
	if not gp and i.KeyCode == Enum.KeyCode.RightShift then setOpen(not win.Visible) end
end))

-- bring back the knife look you chose last time
if sel.__style then
	local ok, res = g(setStyle, sel.__style)
	if not (ok and res) then sel.__style = nil end
end

current = entries[1]
refreshWeapons(); refreshSkins()
if sel.__seenHelp then
	setStatus("Pick a weapon, click a skin, then switch weapons and back. Only you see the change.")
else
	showHelp(true)
end

local function unload()
	if not alive then return end
	alive = false
	if SM.applyEquippedSkin ~= origEquipped then SM.applyEquippedSkin = origEquipped end
	g(restoreStyle)   -- puts the normal Knife model and numbers back
	for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
	pcall(function() gui:Destroy() end)
	_G.StrafeSkinChanger = nil
end
closeBtn.MouseButton1Click:Connect(unload)

_G.StrafeSkinChanger = {
	unload = unload, sel = sel, hits = function() return hits end,
	style = function() return knifeStyle end, styles = styles,
	setStyle = function(n) return g(setStyle, n) end,
}
print(("[SkinChanger] ready: %d weapons, %d knife looks"):format(#weapons, #styles))
