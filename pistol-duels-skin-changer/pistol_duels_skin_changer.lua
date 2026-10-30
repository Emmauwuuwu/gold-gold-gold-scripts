-- PISTOL DUELS | Skin Changer (local only)
--
-- WHAT IT DOES
--   Pick any Glock, Tec-9, Deagle or Knife skin and your own gun shows it, even skins you don't own.
--   Only YOU see the change. Other players, your inventory, trades and purchases are not touched.
--   Skins that only exist for staff (admin_*) are left out on purpose.
--
-- HOW TO USE
--   1. Run the script. A window opens. RightShift hides or shows it.
--   2. Pick a weapon on the left, then click a skin on the right (click it again to turn it off).
--   3. If you are holding that weapon it updates by itself. Otherwise it shows the next time you equip it.
--   4. Patterned skins (the ones with a Pattern box) also let you choose the pattern number and wear.
--   Your choices are saved and come back the next time you run the script.
--   Note: a skin only shows up on a weapon that is in your loadout (the pistol slot or the knife slot).

if _G.PistolDuelsSkinChanger and _G.PistolDuelsSkinChanger.unload then pcall(_G.PistolDuelsSkinChanger.unload) end

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local lp = Players.LocalPlayer

local SAVE_FILE = "pistol_duels_skin_changer.json"
local alive = true
local conns = {}
local function keep(c) conns[#conns + 1] = c; return c end

-- the game's modules can only be required from a thread with identity 2 (executors run at 8), so anything that
-- touches them goes through g(): it runs the function in such a thread, waits for it, and returns pcall's results
local setIdentity = (type(setthreadidentity) == "function" and setthreadidentity)
	or (type(set_thread_identity) == "function" and set_thread_identity)
	or (type(setidentity) == "function" and setidentity)
	or (type(setthreadcontext) == "function" and setthreadcontext)
	or (type(syn) == "table" and type(syn.set_thread_identity) == "function" and syn.set_thread_identity)
	or nil
local function g(fn, ...)
	local args, res, done = table.pack(...), nil, false
	task.spawn(function()
		if setIdentity then pcall(setIdentity, 2) end
		res = table.pack(pcall(fn, table.unpack(args, 1, args.n)))
		done = true
	end)
	local t = os.clock()
	while not done and os.clock() - t < 5 do task.wait() end
	if not res then return false, "timed out" end
	return table.unpack(res, 1, res.n)
end

local SkinCatalog, WM, FC
g(function()
	local cos = RS:FindFirstChild("Cosmetics")
	if not cos then return end
	SkinCatalog = require(cos.SkinCatalog)
	WM = require(cos.WeaponModel)
	pcall(function()
		FC = require(lp.PlayerScripts.Client.Cosmetics.FinishClient)
	end)
end)
if not (SkinCatalog and WM) then
	local cos = RS:FindFirstChild("Cosmetics")
	if cos and cos:FindFirstChild("SkinCatalog") then
		warn("[SkinChanger] Your executor can't run the game's own scripts" .. (setIdentity and "" or " (it has no setthreadidentity)")
			.. ", which this script needs. Try an executor that supports setthreadidentity / require on game modules. Nothing was changed.")
	else
		warn("[SkinChanger] This doesn't look like Pistol Duels (its skin scripts were not found), so nothing was changed.")
	end
	return
end

-- ===================== saved choices =====================
local sel, pat, wear = {}, {}, {}   -- weapon -> skin id / pattern number / wear
local seenHelp = false
local hideArms = false
pcall(function()
	if type(readfile) == "function" and type(isfile) == "function" and isfile(SAVE_FILE) then
		local d = HttpService:JSONDecode(readfile(SAVE_FILE))
		if type(d) == "table" then
			for k, v in pairs(type(d.sel) == "table" and d.sel or {}) do if type(v) == "string" then sel[k] = v end end
			for k, v in pairs(type(d.pat) == "table" and d.pat or {}) do if type(v) == "number" then pat[k] = v end end
			for k, v in pairs(type(d.wear) == "table" and d.wear or {}) do if type(v) == "number" then wear[k] = v end end
			seenHelp = d.seenHelp == true
			hideArms = d.hideArms == true
		end
	end
end)
local function save()
	pcall(function()
		if type(writefile) == "function" then
			writefile(SAVE_FILE, HttpService:JSONEncode({ sel = sel, pat = pat, wear = wear, seenHelp = seenHelp, hideArms = hideArms }))
		end
	end)
end

-- ===================== skin lists =====================
local RANK = { Secret = 1, Exclusive = 2, Knife = 3, Legendary = 4, Epic = 5, Rare = 6, Uncommon = 7 }
local weapons, skinsOf, displayOf, byId = {}, {}, {}, {}
g(function()
	local order = type(SkinCatalog.WeaponOrder) == "table" and SkinCatalog.WeaponOrder or { "Glock", "Tec9", "Deagle", "Knife" }
	local names = type(SkinCatalog.WeaponNames) == "table" and SkinCatalog.WeaponNames or {}
	local colors = type(SkinCatalog.RarityColors) == "table" and SkinCatalog.RarityColors or {}
	for _, w in ipairs(order) do
		local list = {}
		for id, it in pairs(SkinCatalog.Items) do
			if it.weapon == w and not it.adminOnly and not it.standard and not string.find(tostring(id), "^admin_") then
				local c = colors[it.rarity]
				local s = {
					id = id, display = it.name or id, rarity = tostring(it.rarity or ""),
					color = typeof(c) == "Color3" and c or nil, patterned = it.procedural ~= nil, weapon = w,
				}
				list[#list + 1] = s
				byId[id] = s
			end
		end
		table.sort(list, function(a, b)
			local ra, rb = RANK[a.rarity] or 99, RANK[b.rarity] or 99
			if ra ~= rb then return ra < rb end
			return string.lower(a.display) < string.lower(b.display)
		end)
		skinsOf[w] = list
		weapons[#weapons + 1] = w
		displayOf[w] = names[w] or w
	end
end)
if #weapons == 0 then warn("[SkinChanger] Found no weapons in the skin catalog, so nothing was changed."); return end
for w, id in pairs(sel) do if not (byId[id] and byId[id].weapon == w) then sel[w] = nil end end

local function clampPat(n) return math.clamp(math.floor((tonumber(n) or 1) + 0.5), 1, 1000) end
local function clampWear(n) return math.clamp(tonumber(n) or 0, 0, 1) end

-- ===================== the hooks =====================
-- The game builds your gun in one place (CombatController's "model" function). We only swap the skin there, so the
-- inventory, the inspect screen, trades and the final-kill replay keep showing the real thing.
local hits = 0
local function fromCombat()
	local tb = debug.traceback("", 3)
	return string.find(tb, "CombatController:%d+ function model") ~= nil
end

local origCreateAnimated, origCreate, origBind = WM.createAnimated, WM.create, FC and FC.bind
local wrapCA, wrapC, wrapBind

wrapCA = function(weapon, skinId, ...)
	local want = sel[weapon]
	if want and fromCombat() then hits += 1; skinId = want end
	return origCreateAnimated(weapon, skinId, ...)
end
wrapC = function(weapon, flag, skinId, ...)
	local want = sel[weapon]
	if want and fromCombat() then skinId = want end
	return origCreate(weapon, flag, skinId, ...)
end
if origBind then
	wrapBind = function(model, item, dist, opts, ...)
		if typeof(model) == "Instance" and type(opts) == "table" and opts.fullDetail and not opts.transient then
			local w = string.match(model.Name, "^PD_(.+)$")
			if w and sel[w] and fromCombat() then
				item = { skinId = sel[w], pattern = pat[w] or 1, wear = wear[w] or 0 }
			end
		end
		return origBind(model, item, dist, opts, ...)
	end
end
g(function()
	WM.createAnimated = wrapCA
	WM.create = wrapC
	if wrapBind then FC.bind = wrapBind end
end)

-- ===================== re-equip =====================
-- Switching to the other slot and back makes the game build your weapon again, which is when the skin is swapped in.
local function heldModel()
	local cam = workspace.CurrentCamera
	if not cam then return nil end
	for _, c in ipairs(cam:GetChildren()) do
		if c:IsA("Model") then
			local w = string.match(c.Name, "^PD_(.+)$")
			if w then return c, w end
		end
	end
	return nil
end
local reEquipping = false
local function reEquip()
	if reEquipping then return false end
	local _, w = heldModel()
	if not w then return false end
	local ok, VIM = pcall(function() return game:GetService("VirtualInputManager") end)
	if not ok then return false end
	local function tap(key)
		VIM:SendKeyEvent(true, key, false, game)
		task.wait(0.06)
		VIM:SendKeyEvent(false, key, false, game)
	end
	reEquipping = true
	local isKnife = (w == "Knife")
	-- press a key and wait until the weapon in your hands really changes (one retry if the game ignored the press)
	local function switchTo(key, wantKnife)
		for _ = 1, 2 do
			tap(key)
			local t = os.clock()
			while os.clock() - t < 1.2 do
				local _, now = heldModel()
				if now ~= nil and (now == "Knife") == wantKnife then task.wait(0.25); return true end
				task.wait(0.05)
			end
		end
		return false
	end
	local ok2, res = pcall(function()
		if not switchTo(isKnife and Enum.KeyCode.One or Enum.KeyCode.Two, not isKnife) then return false end
		return switchTo(isKnife and Enum.KeyCode.Two or Enum.KeyCode.One, isKnife)
	end)
	reEquipping = false
	return ok2 and res == true
end
local function showingNow(weapon)   -- true when the weapon in your hands is the chosen skin
	local m, w = heldModel()
	return m ~= nil and w == weapon and m:GetAttribute("PDSkinId") == sel[weapon]
end

-- ===================== invisible arms =====================
-- Hides the arms/hands of your viewmodel so they don't cover the skin. Done every frame (after the game's own update)
-- because the game keeps setting the arm transparency itself.
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local armOrig = setmetatable({}, { __mode = "k" })       -- arm part -> its own transparency (to put back)
local trackedModels = setmetatable({}, { __mode = "k" }) -- model -> { parts = { [part] = true } }
local function isArmPart(p)
	if not p:IsA("BasePart") then return false end
	if p:FindFirstAncestor("AvatarArms") then return true end
	local n = string.lower(p.Name)
	if string.find(n, "^left") or string.find(n, "^right") then
		return string.find(n, "arm", 1, true) or string.find(n, "hand", 1, true) or string.find(n, "glove", 1, true)
			or string.find(n, "sleeve", 1, true) or false
	end
	return false
end
local function track(model)
	if trackedModels[model] then return trackedModels[model] end
	local rec = { parts = {} }
	trackedModels[model] = rec
	local function consider(d) if isArmPart(d) then rec.parts[d] = true end end
	consider(model)
	for _, d in ipairs(model:GetDescendants()) do consider(d) end
	model.DescendantAdded:Connect(consider)
	return rec
end
local function enforceArms()
	if not hideArms then return end
	local cam = workspace.CurrentCamera
	if not cam then return end
	for _, c in ipairs(cam:GetChildren()) do
		if string.find(c.Name, "^PD_") or c.Name == "AvatarArms" then
			local rec = track(c)
			for p in pairs(rec.parts) do
				if p.Parent then
					if armOrig[p] == nil then armOrig[p] = p.Transparency end
					if p.Transparency ~= 1 then p.Transparency = 1 end
				else
					rec.parts[p] = nil
				end
			end
		end
	end
end
local function restoreArms()
	for _, rec in pairs(trackedModels) do
		for p in pairs(rec.parts) do
			local o = armOrig[p]
			if o ~= nil and p.Parent then p.Transparency = o end
		end
	end
end
pcall(function() RunService:BindToRenderStep("PDSkinChangerArms", Enum.RenderPriority.Last.Value, enforceArms) end)

-- ===================== window =====================
local C = {
	bg = Color3.fromRGB(13, 14, 19), white = Color3.fromRGB(255, 255, 255), accent = Color3.fromRGB(94, 138, 255),
	text = Color3.fromRGB(240, 241, 246), dim = Color3.fromRGB(158, 163, 181),
	good = Color3.fromRGB(110, 214, 144), warn = Color3.fromRGB(243, 186, 98),
}
local gui = Instance.new("ScreenGui")
gui.Name = "PistolDuelsSkinChanger"; gui.ResetOnSpawn = false; gui.DisplayOrder = 50; gui.IgnoreGuiInset = true
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

local function corner(o, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 8); c.Parent = o end
local make
local function stroke(o, transparency, color, thickness)
	return make("UIStroke", { Color = color or C.white, Transparency = transparency or 0.88, Thickness = thickness or 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, o)
end
make = function(class, props, parent)
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
-- soft "glass" button: see-through, brightens on hover
local function button(parent, str, pos, sz, accent)
	local base = accent and 0.15 or 0.92
	local b = make("TextButton", {
		Text = str, Position = pos, Size = sz, BackgroundColor3 = accent and C.accent or C.white, BackgroundTransparency = base,
		TextColor3 = C.text, Font = Enum.Font.GothamMedium, TextSize = 13, AutoButtonColor = false,
	}, parent)
	corner(b, 8)
	b.MouseEnter:Connect(function() b.BackgroundTransparency = accent and 0.05 or 0.84 end)
	b.MouseLeave:Connect(function() b.BackgroundTransparency = base end)
	return b
end
local function inputBox(parent, pos, sz, placeholder)
	local t = make("TextBox", {
		Position = pos, Size = sz, BackgroundColor3 = C.white, BackgroundTransparency = 0.92, TextColor3 = C.text,
		PlaceholderText = placeholder, PlaceholderColor3 = C.dim, Text = "", Font = Enum.Font.Gotham, TextSize = 13, ClearTextOnFocus = false,
	}, parent)
	corner(t, 8)
	return t
end

local W, H = 640, 460
local win = make("Frame", {
	Size = UDim2.fromOffset(W, H), Position = UDim2.new(0.5, -W / 2, 0.5, -H / 2), BackgroundColor3 = C.bg,
	BackgroundTransparency = 0.2, BorderSizePixel = 0,
}, gui)
corner(win, 14)
stroke(win, 0.86)

-- a small pill to bring the window back after hiding it
local pill = button(gui, "Skin Changer", UDim2.new(0.5, -55, 0, 8), UDim2.fromOffset(110, 28))
pill.BackgroundColor3 = C.bg; pill.BackgroundTransparency = 0.25
pill.Visible = false
local function setOpen(open) win.Visible = open; pill.Visible = not open end
pill.MouseButton1Click:Connect(function() setOpen(true) end)

-- header: title on the left, arms switch + small buttons on the right
local top = make("Frame", { Size = UDim2.new(1, 0, 0, 52), BackgroundTransparency = 1 }, win)
text(top, "Skin Changer", 17, C.text, UDim2.fromOffset(18, 8), UDim2.fromOffset(200, 22), nil, Enum.Font.GothamBold)
text(top, "Pistol Duels  ·  only you see it", 11, C.dim, UDim2.fromOffset(18, 29), UDim2.fromOffset(220, 16))
local closeBtn = button(top, "×", UDim2.new(1, -44, 0, 12), UDim2.fromOffset(30, 28))
local hideBtn = button(top, "–", UDim2.new(1, -78, 0, 12), UDim2.fromOffset(30, 28))
local helpBtn = button(top, "?", UDim2.new(1, -112, 0, 12), UDim2.fromOffset(30, 28))
closeBtn.TextSize = 18

-- switch: Hide arms
local setStatus
local armsLabel = text(top, "Hide arms", 12, C.dim, UDim2.new(1, -226, 0, 0), UDim2.fromOffset(62, 52), Enum.TextXAlignment.Right)
local sw = make("TextButton", {
	Text = "", AutoButtonColor = false, Position = UDim2.new(1, -158, 0, 16), Size = UDim2.fromOffset(38, 20),
	BackgroundColor3 = C.white, BackgroundTransparency = 0.82,
}, top)
corner(sw, 10)
local knob = make("Frame", { Size = UDim2.fromOffset(16, 16), Position = UDim2.fromOffset(2, 2), BackgroundColor3 = C.text, BorderSizePixel = 0 }, sw)
corner(knob, 8)
local function paintSwitch(animate)
	local goal = {
		BackgroundColor3 = hideArms and C.accent or C.white,
		BackgroundTransparency = hideArms and 0.1 or 0.82,
	}
	local kgoal = { Position = hideArms and UDim2.fromOffset(20, 2) or UDim2.fromOffset(2, 2) }
	if animate then
		TweenService:Create(sw, TweenInfo.new(0.15), goal):Play()
		TweenService:Create(knob, TweenInfo.new(0.15), kgoal):Play()
	else
		for k, v in pairs(goal) do sw[k] = v end
		knob.Position = kgoal.Position
	end
end
local function setHideArms(on)
	hideArms = on and true or false
	paintSwitch(true); save()
	if hideArms then enforceArms() else restoreArms() end
end
sw.MouseButton1Click:Connect(function()
	setHideArms(not hideArms)
	setStatus(hideArms and "Arms hidden. They stay hidden when you switch weapons." or "Arms are back.", "good")
end)
paintSwitch(false)
make("Frame", { Position = UDim2.new(0, 14, 1, -1), Size = UDim2.new(1, -28, 0, 1), BackgroundColor3 = C.white, BackgroundTransparency = 0.9, BorderSizePixel = 0 }, top)

-- dragging by the header
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

-- bottom row: status text on the left, buttons on the right
local bar = make("Frame", { Position = UDim2.new(0, 14, 1, -50), Size = UDim2.new(1, -28, 0, 38), BackgroundTransparency = 1 }, win)
local status = text(bar, "", 12, C.dim, UDim2.fromOffset(2, 0), UDim2.new(1, -334, 1, 0))
local reBtn = button(bar, "Re-equip", UDim2.new(1, -326, 0, 4), UDim2.fromOffset(98, 30))
local resetOne = button(bar, "Reset this one", UDim2.new(1, -222, 0, 4), UDim2.fromOffset(110, 30))
local resetAll = button(bar, "Reset all", UDim2.new(1, -106, 0, 4), UDim2.fromOffset(106, 30))
setStatus = function(t, kind)
	status.Text = t
	status.TextColor3 = (kind == "good" and C.good) or (kind == "warn" and C.warn) or C.dim
end

-- two glass panels: weapons (left) and skins (right)
local function column(title)
	local f = make("Frame", { BackgroundColor3 = C.white, BackgroundTransparency = 0.95, BorderSizePixel = 0 }, win)
	corner(f, 12)
	stroke(f, 0.93)
	local t = text(f, title, 11, C.dim, UDim2.fromOffset(14, 9), UDim2.new(1, -28, 0, 14), nil, Enum.Font.GothamMedium)
	local s = make("ScrollingFrame", {
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3, ScrollBarImageColor3 = C.white,
		ScrollBarImageTransparency = 0.6, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, f)
	make("UIListLayout", { Padding = UDim.new(0, 4) }, s)
	make("UIPadding", { PaddingRight = UDim.new(0, 4) }, s)
	return { frame = f, title = t, scroll = s }
end
local left = column("WEAPONS")
left.frame.Position = UDim2.fromOffset(14, 60); left.frame.Size = UDim2.new(0, 158, 1, -120)
left.scroll.Position = UDim2.fromOffset(6, 30); left.scroll.Size = UDim2.new(1, -12, 1, -36)
local right = column("SKINS")
right.frame.Position = UDim2.fromOffset(180, 60); right.frame.Size = UDim2.new(1, -194, 1, -120)
local search = make("TextBox", {
	Position = UDim2.fromOffset(10, 30), Size = UDim2.new(1, -20, 0, 28), BackgroundColor3 = C.white, BackgroundTransparency = 0.92,
	TextColor3 = C.text, PlaceholderText = "Search skins or rarity...", PlaceholderColor3 = C.dim, Text = "", Font = Enum.Font.Gotham,
	TextSize = 13, ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left,
}, right.frame)
corner(search, 8)
make("UIPadding", { PaddingLeft = UDim.new(0, 10) }, search)

-- pattern / wear strip (only for patterned skins)
local strip = make("Frame", { Position = UDim2.fromOffset(10, 64), Size = UDim2.new(1, -20, 0, 28), BackgroundTransparency = 1, Visible = false }, right.frame)
text(strip, "Pattern", 12, C.dim, UDim2.fromOffset(2, 0), UDim2.fromOffset(46, 28))
local patBox = inputBox(strip, UDim2.fromOffset(50, 1), UDim2.fromOffset(56, 26), "1-1000")
text(strip, "Wear", 12, C.dim, UDim2.fromOffset(116, 0), UDim2.fromOffset(32, 28))
local wearBox = inputBox(strip, UDim2.fromOffset(150, 1), UDim2.fromOffset(56, 26), "0-1")
local randBtn = button(strip, "Random", UDim2.fromOffset(216, 1), UDim2.fromOffset(70, 26))
text(strip, "press Enter to apply", 11, C.dim, UDim2.fromOffset(294, 0), UDim2.new(1, -294, 0, 28))
local function layoutRight(showStrip)
	strip.Visible = showStrip
	right.scroll.Position = UDim2.fromOffset(6, showStrip and 98 or 66)
	right.scroll.Size = UDim2.new(1, -12, 1, showStrip and -104 or -72)
end
layoutRight(false)

local current      -- selected weapon
local weaponRows, skinRows = {}, {}
local refreshWeapons, refreshSkins

-- a list row: optional rarity dot, name, small tag on the right; accent colour when in use
local function row(parent, name, tag, active, dot)
	local b = make("TextButton", {
		Size = UDim2.new(1, -2, 0, 32), BackgroundColor3 = active and C.accent or C.white,
		BackgroundTransparency = active and 0.25 or 0.94, Text = "", AutoButtonColor = false,
	}, parent)
	corner(b, 8)
	local x = 12
	if dot then
		local d = make("Frame", { Size = UDim2.fromOffset(8, 8), Position = UDim2.new(0, 12, 0.5, -4), BackgroundColor3 = dot, BorderSizePixel = 0 }, b)
		corner(d, 4)
		x = 28
	end
	local label = text(b, name, 13, C.text, UDim2.fromOffset(x, 0), UDim2.new(1, -x - 88, 1, 0))
	label.TextTruncate = Enum.TextTruncate.AtEnd
	if tag and tag ~= "" then
		text(b, tag, 11, active and C.text or C.dim, UDim2.new(1, -90, 0, 0), UDim2.fromOffset(80, 32), Enum.TextXAlignment.Right)
	end
	b.MouseEnter:Connect(function() if not active then b.BackgroundTransparency = 0.86 end end)
	b.MouseLeave:Connect(function() if not active then b.BackgroundTransparency = 0.94 end end)
	return b
end
local function note(parent, str, store)
	local l = text(parent, str, 12, C.dim, UDim2.new(), UDim2.new(1, -8, 0, 0))
	l.AutomaticSize = Enum.AutomaticSize.Y
	store[#store + 1] = l
	return l
end

function refreshWeapons()
	for _, b in pairs(weaponRows) do b:Destroy() end
	weaponRows = {}
	for _, w in ipairs(weapons) do
		local b = row(left.scroll, displayOf[w], sel[w] and "custom" or "", w == current)
		weaponRows[#weaponRows + 1] = b
		b.MouseButton1Click:Connect(function() current = w; search.Text = ""; refreshWeapons(); refreshSkins() end)
	end
end

local function syncStrip()
	local s = current and sel[current] and byId[sel[current]]
	layoutRight(s and s.patterned or false)
	if s and s.patterned then
		patBox.Text = tostring(pat[current] or 1)
		wearBox.Text = string.format("%.2f", wear[current] or 0)
	end
end

-- put the choice on the weapon in your hands (if it is that weapon), and tell the user what happened
local function afterChange(w, msgOn, msgOff)
	local _, held = heldModel()
	if held == w then
		task.spawn(function()
			setStatus("Re-equipping your " .. (displayOf[w] or w) .. "...", nil)
			reEquip()
			if not alive then return end
			if sel[w] then
				if showingNow(w) then setStatus(msgOn, "good") else setStatus("Saved. Switch to another weapon and back to see it.", "warn") end
			else
				setStatus(msgOff, "good")
			end
		end)
	else
		setStatus(sel[w] and ("Saved. It shows the next time you equip the " .. (displayOf[w] or w) .. ".") or msgOff, "good")
	end
end

function refreshSkins()
	for _, b in pairs(skinRows) do b:Destroy() end
	skinRows = {}
	if not current then
		right.title.Text = "SKINS"
		layoutRight(false)
		note(right.scroll, "Pick a weapon on the left.", skinRows)
		return
	end
	syncStrip()
	local q = string.lower(search.Text or "")
	local list = skinsOf[current] or {}
	local d = row(right.scroll, "My own skin (default)", sel[current] == nil and "in use" or "", sel[current] == nil)
	skinRows[#skinRows + 1] = d
	d.MouseButton1Click:Connect(function()
		local w = current
		sel[w] = nil; save(); refreshWeapons(); refreshSkins()
		afterChange(w, "", "Back to your own skin for the " .. (displayOf[w] or w) .. ".")
	end)
	local shown = 0
	for _, s in ipairs(list) do
		if q == "" or string.find(string.lower(s.display), q, 1, true) or string.find(string.lower(s.rarity), q, 1, true) then
			shown += 1
			local on = sel[current] == s.id
			local b = row(right.scroll, s.display, on and "in use" or s.rarity, on, s.color or C.dim)
			skinRows[#skinRows + 1] = b
			b.MouseButton1Click:Connect(function()
				local w = current
				if sel[w] == s.id then sel[w] = nil else sel[w] = s.id end
				save(); refreshWeapons(); refreshSkins()
				afterChange(w, s.display .. " is on your " .. (displayOf[w] or w) .. ".", "Turned off. Your own skin is back on the " .. (displayOf[w] or w) .. ".")
			end)
		end
	end
	right.title.Text = "SKINS FOR " .. string.upper(displayOf[current] or current) .. "  ·  " .. (q == "" and #list or (shown .. " of " .. #list))
	if shown == 0 then note(right.scroll, "No skins match \"" .. (search.Text or "") .. "\".", skinRows) end
end

keep(search:GetPropertyChangedSignal("Text"):Connect(refreshSkins))

-- pattern / wear boxes
local function applyLook()
	local w = current
	if not (w and sel[w]) then return end
	pat[w] = clampPat(patBox.Text); wear[w] = clampWear(wearBox.Text)
	patBox.Text = tostring(pat[w]); wearBox.Text = string.format("%.2f", wear[w])
	save()
	afterChange(w, "Pattern " .. pat[w] .. ", wear " .. string.format("%.2f", wear[w]) .. " applied.", "")
end
patBox.FocusLost:Connect(function(enter) if enter then applyLook() end end)
wearBox.FocusLost:Connect(function(enter) if enter then applyLook() end end)
randBtn.MouseButton1Click:Connect(function()
	patBox.Text = tostring(math.random(1, 1000))
	applyLook()
end)

reBtn.MouseButton1Click:Connect(function()
	task.spawn(function()
		setStatus("Re-equipping...", nil)
		local ok = reEquip()
		setStatus(ok and "Re-equipped. Your skins are rebuilt." or "Couldn't switch weapons from here. Press your weapon keys yourself.", ok and "good" or "warn")
	end)
end)
resetOne.MouseButton1Click:Connect(function()
	local w = current
	if not w then return end
	sel[w] = nil; pat[w] = nil; wear[w] = nil
	save(); refreshWeapons(); refreshSkins()
	afterChange(w, "", "Reset the " .. (displayOf[w] or w) .. ".")
end)
resetAll.MouseButton1Click:Connect(function()
	for k in pairs(sel) do sel[k] = nil end
	for k in pairs(pat) do pat[k] = nil end
	for k in pairs(wear) do wear[k] = nil end
	save(); refreshWeapons(); refreshSkins()
	local _, held = heldModel()
	if held then task.spawn(function() reEquip(); if alive then setStatus("Everything is back to normal.", "good") end end)
	else setStatus("Everything is back to normal.", "good") end
end)

-- help card (shown the first time, and with the ? button)
local help = make("Frame", {
	Size = UDim2.fromOffset(450, 300), Position = UDim2.new(0.5, -225, 0.5, -150), BackgroundColor3 = C.bg,
	BackgroundTransparency = 0.04, BorderSizePixel = 0, Visible = false, ZIndex = 20,
}, win)
corner(help, 14)
stroke(help, 0.2, C.accent, 1.5)
local helpText = text(help,
	"How it works\n\n1.  Pick a weapon on the left.\n2.  Click a skin on the right. Click it again to turn it off.\n3.  If you are holding that weapon it updates by itself (the script quickly switches away and back). If not, it shows the next time you equip it.\n4.  Patterned skins get a Pattern and Wear box. Type a number and press Enter, or hit Random.\n5.  \"Hide arms\" (top right) makes your arms invisible so nothing covers the skin.\n\nA skin only shows on a weapon that is in your loadout. Only you see these changes. RightShift hides or shows this window.",
	13, C.text, UDim2.fromOffset(20, 16), UDim2.new(1, -40, 1, -70))
helpText.ZIndex = 21
helpText.TextYAlignment = Enum.TextYAlignment.Top
local gotIt = button(help, "Got it", UDim2.new(0.5, -50, 1, -46), UDim2.fromOffset(100, 32), true)
gotIt.ZIndex = 21
local function showHelp(on) help.Visible = on end
helpBtn.MouseButton1Click:Connect(function() showHelp(not help.Visible) end)
gotIt.MouseButton1Click:Connect(function() showHelp(false); seenHelp = true; save() end)

hideBtn.MouseButton1Click:Connect(function() setOpen(false) end)
keep(UIS.InputBegan:Connect(function(i, gp)
	if not gp and i.KeyCode == Enum.KeyCode.RightShift then setOpen(not win.Visible) end
end))

do
	local _, held = heldModel()
	current = (held and skinsOf[held]) and held or weapons[1]
end
refreshWeapons(); refreshSkins()
if seenHelp then
	setStatus("Pick a weapon, click a skin. Only you see the change.")
else
	showHelp(true)
end

local function unload()
	if not alive then return end
	alive = false
	pcall(function() RunService:UnbindFromRenderStep("PDSkinChangerArms") end)
	restoreArms()
	g(function()
		if WM.createAnimated == wrapCA then WM.createAnimated = origCreateAnimated end
		if WM.create == wrapC then WM.create = origCreate end
		if FC and FC.bind == wrapBind then FC.bind = origBind end
	end)
	for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
	pcall(function() gui:Destroy() end)
	_G.PistolDuelsSkinChanger = nil
end
closeBtn.MouseButton1Click:Connect(unload)

_G.PistolDuelsSkinChanger = {
	unload = unload, sel = sel, pat = pat, wear = wear, hits = function() return hits end, reEquip = reEquip,
	setHideArms = setHideArms, hideArms = function() return hideArms end,
}
print(("[SkinChanger] ready: %d weapons, %d skins"):format(#weapons, (function() local n = 0 for _, l in pairs(skinsOf) do n += #l end return n end)()))
