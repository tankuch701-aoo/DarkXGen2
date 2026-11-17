local DarkyX = {}
DarkyX.Version = "gen2-rework2+tile-tabs+header-search+tab-menu+full-header+skip-loading-only"
DarkyX.Debug = false -- true = print DarkyX messages to the console (off by default so nothing is written to the output log)

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer

-- =====================================================================
-- GEN 2 REWORK STYLE
--   CORNER_LARGE  : window, boxes, panels        (was 14 - 22 px)
--   CORNER_MEDIUM : buttons, tabs, inputs, cards (was  9 - 13 px)
-- Lower = squarer but still rounded. Keep both at 8 or less (square, but still a corner).
-- Pills / circles (UDim scale = 1, toggles, dots) are never touched.
-- =====================================================================
local CORNER_LARGE = math.clamp(tonumber(DarkyX.CornerLarge) or 8, 0, 8)
local CORNER_MEDIUM = math.clamp(tonumber(DarkyX.CornerMedium) or 6, 0, 8)
local WINDOW_RADIUS = UDim.new(0, CORNER_LARGE)
local function squareRadius(radius)
    if typeof(radius) ~= "UDim" or radius.Scale ~= 0 then return radius end
    local n = radius.Offset
    if n >= 14 then return UDim.new(0, CORNER_LARGE) end
    if n >= 9 then return UDim.new(0, CORNER_MEDIUM) end
    return radius
end

-- =====================================================================
-- SECURITY / STABILITY LAYER
--   * random, unpredictable GUI names + protected parent (gethui / protect_gui / CoreGui / PlayerGui fallback)
--   * tamper guard: if something un-parents or disables the interface, it is put back (the player's own
--     Delete / Window:Destroy still removes it for good)
--   * stale-window purge: running the same script again replaces the old window instead of stacking ghosts
--   * every user callback runs in a protected thread (an error in a callback can never break the UI)
--   * constant-time key comparison, key sanitising, brute-force lock-out
--   * input connections are tracked and released when the window is destroyed
-- NOTE: a client-side script can never be 100% tamper-proof. For real key security always verify the key on a
-- server (Platoboost does this) and never ship secrets you are not willing to lose.
-- =====================================================================
local Security = {}
do
    local rng = Random.new(math.floor((os.clock() * 1000003 + tick() * 1000) % 2147483647))
    local CHARS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    local HEX = "0123456789abcdef"

    Security.Session = nil -- set below
    Security.pending = nil -- the ScreenGui of a CreateWindow call that has not finished yet

    function Security.randomString(length)
        local out = table.create(length)
        for index = 1, length do
            local n = rng:NextInteger(1, #CHARS)
            out[index] = CHARS:sub(n, n)
        end
        return table.concat(out)
    end

    function Security.randomHex(length)
        local out = table.create(length)
        for index = 1, length do
            local n = rng:NextInteger(1, #HEX)
            out[index] = HEX:sub(n, n)
        end
        return table.concat(out)
    end

    Security.Session = Security.randomString(16)

    -- Console output: SILENT by default (a game can read the output log). DarkyX.Debug = true turns it on.
    function Security.log(message)
        if DarkyX.Debug == true then warn(message) end
    end

    local warned = {}
    function Security.warnOnce(tag, message)
        if warned[tag] then return end
        warned[tag] = true
        Security.log("[DarkyX] " .. tostring(message))
    end

    -- run a callback in its own protected thread: an error is reported, never propagated
    function Security.spawn(fn, ...)
        if type(fn) ~= "function" then return nil end
        return task.spawn(function(...)
            local ok, err = xpcall(fn, debug.traceback, ...)
            if not ok then Security.log("[DarkyX] callback error: " .. tostring(err)) end
        end, ...)
    end

    -- registry (shared between runs of the same executor session)
    local function registry()
        local holder = (type(shared) == "table") and shared or Security
        local list = holder.__uic_cache
        if type(list) ~= "table" then
            list = {}
            local ok = pcall(function() holder.__uic_cache = list end)
            if not ok then
                Security.__uic_cache = Security.__uic_cache or {}
                list = Security.__uic_cache
            end
        end
        return list
    end
    Security.currentKey = "default"

    function Security.register(gui)
        local list = registry()
        table.insert(list, {Gui = gui, Session = Security.Session, Key = Security.currentKey})
    end

    -- destroy GUIs left by an OLDER run of the same hub (same name, different session)
    function Security.purge(key)
        local list = registry()
        for index = #list, 1, -1 do
            local entry = list[index]
            -- protected: an entry left by an older version / a destroyed GUI can never make this throw
            local ok, drop, destroy = pcall(function()
                if type(entry) ~= "table" or typeof(entry.Gui) ~= "Instance" or not entry.Gui.Parent then return true, false end
                if entry.Session ~= Security.Session and entry.Key == key then return true, true end
                return false, false
            end)
            if not ok then drop, destroy = true, false end
            if destroy then pcall(function() entry.Gui:Destroy() end) end
            if drop then table.remove(list, index) end
        end
    end

    function Security.destroyAll()
        local list = registry()
        for index = #list, 1, -1 do
            local entry = list[index]
            if entry.Session == Security.Session and entry.Gui then
                pcall(function() entry.Gui:Destroy() end)
                table.remove(list, index)
            end
        end
    end

    -- creates a ScreenGui in the safest container available
    function Security.createScreenGui(name, displayOrder)
        local gui = Instance.new("ScreenGui")
        gui.Name = name or Security.randomString(14)
        gui.ResetOnSpawn = false
        gui.IgnoreGuiInset = true
        gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        gui.DisplayOrder = displayOrder or 999

        local protectFn = (type(syn) == "table" and syn.protect_gui) or protect_gui
        if type(protectFn) == "function" then pcall(protectFn, gui) end

        local parents = {}
        if type(gethui) == "function" then
            local ok, result = pcall(gethui)
            if ok and typeof(result) == "Instance" then table.insert(parents, result) end
        end
        local coreGui = CoreGui
        if type(cloneref) == "function" then
            local ok, result = pcall(cloneref, CoreGui)
            if ok and typeof(result) == "Instance" then coreGui = result end
        end
        table.insert(parents, coreGui)
        table.insert(parents, "PlayerGui") -- resolved last (only waited for when nothing else worked)

        for _, parent in ipairs(parents) do
            if parent == "PlayerGui" then
                parent = LocalPlayer and (LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 5))
            end
            if parent then
                local ok = pcall(function() gui.Parent = parent end)
                if ok and gui.Parent == parent then
                    Security.register(gui)
                    return gui, parent
                end
            end
        end
        gui:Destroy()
        error("DarkyX could not find a writable container for the interface.", 0)
    end

    -- tamper guard: returns a list of connections (disconnected by Security.release)
    function Security.guard(gui, owner)
        local connections = {}
        local restores, windowStart = 0, os.clock()
        local home = gui.Parent
        local function gone() return owner.Destroyed == true end

        table.insert(connections, gui.AncestryChanged:Connect(function()
            if gone() or gui.Parent ~= nil then return end
            if os.clock() - windowStart > 10 then restores, windowStart = 0, os.clock() end
            restores += 1
            if restores > 5 then
                Security.warnOnce("guard-limit", "the interface keeps being removed by another script; giving up restoring it.")
                return
            end
            task.defer(function()
                if gone() then return end
                pcall(function() gui.Parent = home end)
            end)
        end))
        table.insert(connections, gui:GetPropertyChangedSignal("Enabled"):Connect(function()
            if not gone() and gui.Enabled == false then pcall(function() gui.Enabled = true end) end
        end))
        table.insert(connections, gui.Destroying:Connect(function()
            if not gone() then
                Security.warnOnce("guard-destroyed", "the interface was destroyed by something other than DarkyX.")
                owner.Destroyed = true
            end
        end))
        return connections
    end

    -- proxy for a service whose events are tracked so they can all be disconnected at once
    function Security.trackInput(service)
        local connections = {}
        local proxy = {}
        local function remember(connection)
            connections[#connections + 1] = connection
            return connection
        end
        local function wrapSignal(signal)
            return {
                Connect = function(_, fn) return remember(signal:Connect(fn)) end,
                Once = function(_, fn) return remember(signal:Once(fn)) end,
                Wait = function() return signal:Wait() end,
            }
        end
        proxy._DarkyXDisconnectAll = function()
            for index = #connections, 1, -1 do
                pcall(function() connections[index]:Disconnect() end)
                connections[index] = nil
            end
        end
        return setmetatable(proxy, {
            __index = function(_, key)
                local value = service[key]
                if typeof(value) == "RBXScriptSignal" then return wrapSignal(value) end
                if type(value) == "function" then
                    return function(_, ...) return value(service, ...) end
                end
                return value
            end,
            __newindex = function(_, key, value) service[key] = value end,
        })
    end

    function Security.release(window)
        if window._Guard then
            for _, connection in ipairs(window._Guard) do pcall(function() connection:Disconnect() end) end
            window._Guard = nil
        end
        if window._Input and window._Input._DarkyXDisconnectAll then
            window._Input._DarkyXDisconnectAll()
        end
    end

    function Security.abortPending()
        local gui = Security.pending
        Security.pending = nil
        if gui then pcall(function() gui:Destroy() end) end
    end

    -- constant-time string comparison (no early exit on the first different character)
    function Security.equals(a, b)
        a, b = tostring(a), tostring(b)
        local diff = (#a ~= #b) and 1 or 0
        for index = 1, math.max(#a, #b) do
            diff = bit32.bor(diff, bit32.bxor(string.byte(a, index) or 0, string.byte(b, index) or 0))
        end
        return diff == 0
    end

    -- trim, drop control characters and cap the length
    function Security.cleanKey(value, maxLength)
        local text = tostring(value == nil and "" or value)
        text = text:gsub("[%z\1-\31\127]", "")
        text = text:gsub("^%s+", "")
        text = text:gsub("%s+$", "")
        if #text > (maxLength or 512) then text = text:sub(1, maxLength or 512) end
        return text
    end

    -- brute-force lock-out: after `maxAttempts` wrong keys the input locks (time doubles every round, max 5 min)
    function Security.newLimiter(maxAttempts, baseLock)
        local fails, level, lockedUntil = 0, 0, 0
        local limiter = {}
        function limiter.check()
            local left = lockedUntil - os.clock()
            if left > 0 then return false, math.ceil(left) end
            return true, 0
        end
        function limiter.fail()
            fails += 1
            if fails >= maxAttempts then
                fails = 0
                level += 1
                lockedUntil = os.clock() + math.min(baseLock * 2 ^ (level - 1), 300)
            end
        end
        function limiter.success()
            fails, level, lockedUntil = 0, 0, 0
        end
        return limiter
    end
end
-- only the key system itself may release a held window (nobody else can fake "key accepted")
local ksReleaseToken = {}
local function setProperty(object, property, value) object[property] = value end

local Themes = {
    cobalt = {
        Background = Color3.fromRGB(5, 7, 12),
        Background2 = Color3.fromRGB(7, 10, 17),
        Panel = Color3.fromRGB(9, 13, 21),
        Panel2 = Color3.fromRGB(12, 17, 27),
        Element = Color3.fromRGB(15, 21, 33),
        ElementHover = Color3.fromRGB(21, 29, 45),
        ElementPressed = Color3.fromRGB(25, 35, 55),
        Accent = Color3.fromRGB(66, 132, 255),
        Accent2 = Color3.fromRGB(118, 171, 255),
        AccentDark = Color3.fromRGB(32, 67, 135),
        Text = Color3.fromRGB(247, 250, 255),
        Muted = Color3.fromRGB(143, 154, 175),
        Faint = Color3.fromRGB(91, 103, 126),
        Border = Color3.fromRGB(28, 38, 58),
        Border2 = Color3.fromRGB(39, 53, 79),
        Danger = Color3.fromRGB(255, 75, 92),
        Success = Color3.fromRGB(67, 221, 147),
        White = Color3.fromRGB(255, 255, 255),
    },
    red = {
        Background = Color3.fromRGB(8, 5, 7), Background2 = Color3.fromRGB(12, 7, 9), Panel = Color3.fromRGB(16, 9, 12), Panel2 = Color3.fromRGB(21, 12, 15),
        Element = Color3.fromRGB(27, 14, 18), ElementHover = Color3.fromRGB(38, 19, 25), ElementPressed = Color3.fromRGB(49, 24, 31), Accent = Color3.fromRGB(237, 61, 79), Accent2 = Color3.fromRGB(255, 116, 130), AccentDark = Color3.fromRGB(118, 29, 41),
        Text = Color3.fromRGB(255, 246, 247), Muted = Color3.fromRGB(182, 149, 155), Faint = Color3.fromRGB(111, 83, 89), Border = Color3.fromRGB(57, 29, 35), Border2 = Color3.fromRGB(76, 38, 46), Danger = Color3.fromRGB(255, 74, 92), Success = Color3.fromRGB(69, 215, 143), White = Color3.new(1, 1, 1),
    },
    bluesky = {
        Background = Color3.fromRGB(4, 8, 12), Background2 = Color3.fromRGB(6, 12, 17), Panel = Color3.fromRGB(8, 15, 21), Panel2 = Color3.fromRGB(11, 21, 29),
        Element = Color3.fromRGB(13, 26, 35), ElementHover = Color3.fromRGB(18, 37, 49), ElementPressed = Color3.fromRGB(22, 48, 62), Accent = Color3.fromRGB(45, 176, 255), Accent2 = Color3.fromRGB(126, 219, 255), AccentDark = Color3.fromRGB(21, 94, 138),
        Text = Color3.fromRGB(242, 251, 255), Muted = Color3.fromRGB(141, 172, 190), Faint = Color3.fromRGB(83, 113, 130), Border = Color3.fromRGB(23, 48, 61), Border2 = Color3.fromRGB(31, 67, 85), Danger = Color3.fromRGB(255, 78, 95), Success = Color3.fromRGB(68, 218, 149), White = Color3.new(1, 1, 1),
    },
    dark = {
        Background = Color3.fromRGB(5, 5, 7), Background2 = Color3.fromRGB(8, 8, 10), Panel = Color3.fromRGB(10, 10, 12), Panel2 = Color3.fromRGB(14, 14, 17),
        Element = Color3.fromRGB(18, 18, 22), ElementHover = Color3.fromRGB(26, 26, 31), ElementPressed = Color3.fromRGB(32, 32, 39), Accent = Color3.fromRGB(116, 125, 255), Accent2 = Color3.fromRGB(168, 174, 255), AccentDark = Color3.fromRGB(55, 59, 125),
        Text = Color3.fromRGB(246, 246, 250), Muted = Color3.fromRGB(150, 150, 162), Faint = Color3.fromRGB(92, 92, 103), Border = Color3.fromRGB(31, 31, 36), Border2 = Color3.fromRGB(47, 47, 54), Danger = Color3.fromRGB(255, 77, 90), Success = Color3.fromRGB(67, 215, 141), White = Color3.new(1, 1, 1),
    },
    green = {
        Background = Color3.fromRGB(4, 8, 6), Background2 = Color3.fromRGB(6, 12, 8), Panel = Color3.fromRGB(7, 15, 10), Panel2 = Color3.fromRGB(10, 21, 14),
        Element = Color3.fromRGB(13, 28, 18), ElementHover = Color3.fromRGB(18, 41, 26), ElementPressed = Color3.fromRGB(23, 51, 32), Accent = Color3.fromRGB(50, 214, 113), Accent2 = Color3.fromRGB(111, 241, 161), AccentDark = Color3.fromRGB(24, 107, 58),
        Text = Color3.fromRGB(241, 255, 247), Muted = Color3.fromRGB(142, 175, 154), Faint = Color3.fromRGB(78, 108, 89), Border = Color3.fromRGB(22, 49, 31), Border2 = Color3.fromRGB(31, 68, 42), Danger = Color3.fromRGB(255, 79, 94), Success = Color3.fromRGB(69, 220, 139), White = Color3.new(1, 1, 1),
    },
    purple = {
        Background = Color3.fromRGB(6, 4, 9), Background2 = Color3.fromRGB(10, 7, 14), Panel = Color3.fromRGB(13, 9, 19), Panel2 = Color3.fromRGB(18, 12, 26),
        Element = Color3.fromRGB(23, 15, 34), ElementHover = Color3.fromRGB(33, 21, 49), ElementPressed = Color3.fromRGB(43, 27, 64), Accent = Color3.fromRGB(163, 91, 255), Accent2 = Color3.fromRGB(204, 151, 255), AccentDark = Color3.fromRGB(80, 45, 128),
        Text = Color3.fromRGB(250, 246, 255), Muted = Color3.fromRGB(171, 154, 195), Faint = Color3.fromRGB(101, 83, 122), Border = Color3.fromRGB(53, 35, 73), Border2 = Color3.fromRGB(73, 47, 99), Danger = Color3.fromRGB(255, 78, 94), Success = Color3.fromRGB(72, 217, 145), White = Color3.new(1, 1, 1),
    },
    orange = {
        Background = Color3.fromRGB(8, 5, 3), Background2 = Color3.fromRGB(13, 8, 5), Panel = Color3.fromRGB(17, 10, 6), Panel2 = Color3.fromRGB(23, 14, 8),
        Element = Color3.fromRGB(30, 18, 10), ElementHover = Color3.fromRGB(44, 26, 14), ElementPressed = Color3.fromRGB(56, 33, 18), Accent = Color3.fromRGB(255, 142, 48), Accent2 = Color3.fromRGB(255, 187, 112), AccentDark = Color3.fromRGB(131, 73, 23),
        Text = Color3.fromRGB(255, 249, 240), Muted = Color3.fromRGB(194, 166, 139), Faint = Color3.fromRGB(115, 88, 62), Border = Color3.fromRGB(61, 38, 21), Border2 = Color3.fromRGB(81, 49, 27), Danger = Color3.fromRGB(255, 78, 92), Success = Color3.fromRGB(71, 217, 143), White = Color3.new(1, 1, 1),
    },
    yellow = {
        Background = Color3.fromRGB(8, 8, 3), Background2 = Color3.fromRGB(13, 12, 5), Panel = Color3.fromRGB(17, 16, 7), Panel2 = Color3.fromRGB(23, 21, 9),
        Element = Color3.fromRGB(31, 29, 11), ElementHover = Color3.fromRGB(44, 41, 16), ElementPressed = Color3.fromRGB(56, 52, 20), Accent = Color3.fromRGB(243, 202, 50), Accent2 = Color3.fromRGB(255, 228, 112), AccentDark = Color3.fromRGB(126, 106, 25),
        Text = Color3.fromRGB(255, 253, 239), Muted = Color3.fromRGB(186, 180, 143), Faint = Color3.fromRGB(111, 105, 73), Border = Color3.fromRGB(67, 62, 25), Border2 = Color3.fromRGB(88, 80, 30), Danger = Color3.fromRGB(255, 77, 90), Success = Color3.fromRGB(68, 215, 141), White = Color3.new(1, 1, 1),
    },
    white = {
        Background = Color3.fromRGB(232, 235, 241), Background2 = Color3.fromRGB(242, 244, 248), Panel = Color3.fromRGB(247, 248, 251), Panel2 = Color3.fromRGB(235, 237, 243),
        Element = Color3.fromRGB(225, 228, 235), ElementHover = Color3.fromRGB(214, 218, 227), ElementPressed = Color3.fromRGB(205, 210, 221), Accent = Color3.fromRGB(45, 109, 255), Accent2 = Color3.fromRGB(83, 140, 255), AccentDark = Color3.fromRGB(31, 76, 177),
        Text = Color3.fromRGB(24, 28, 38), Muted = Color3.fromRGB(91, 97, 113), Faint = Color3.fromRGB(132, 138, 151), Border = Color3.fromRGB(199, 204, 216), Border2 = Color3.fromRGB(181, 187, 202), Danger = Color3.fromRGB(230, 54, 72), Success = Color3.fromRGB(37, 177, 105), White = Color3.new(1, 1, 1),
    },
}

Themes.default = {
    TextColor = Color3.fromRGB(240, 240, 240),

    Background = Color3.fromRGB(3, 5, 4),
    Shadow = Color3.fromRGB(1, 2, 2),
    Background2 = Color3.fromRGB(5, 8, 6),
    Panel = Color3.fromRGB(7, 11, 8),
    Panel2 = Color3.fromRGB(5, 8, 6),

    NotificationBackground = Color3.fromRGB(20, 20, 20),
    NotificationActionsBackground = Color3.fromRGB(230, 230, 230),

    ElementBackground = Color3.fromRGB(35, 35, 35),
    ElementBackgroundHover = Color3.fromRGB(40, 40, 40),
    SecondaryElementBackground = Color3.fromRGB(25, 25, 25),
    ElementStroke = Color3.fromRGB(50, 50, 50),
    SecondaryElementStroke = Color3.fromRGB(40, 40, 40),

    SliderBackground = Color3.fromRGB(38, 68, 48),
    SliderProgress = Color3.fromRGB(72, 194, 116),
    SliderStroke = Color3.fromRGB(105, 224, 146),

    ToggleBackground = Color3.fromRGB(26, 34, 29),
    ToggleEnabled = Color3.fromRGB(72, 194, 116),
    ToggleDisabled = Color3.fromRGB(78, 84, 80),
    ToggleEnabledStroke = Color3.fromRGB(105, 224, 146),
    ToggleDisabledStroke = Color3.fromRGB(118, 123, 120),
    ToggleEnabledOuterStroke = Color3.fromRGB(100, 100, 100),
    ToggleDisabledOuterStroke = Color3.fromRGB(65, 65, 65),

    DropdownSelected = Color3.fromRGB(40, 40, 40),
    DropdownUnselected = Color3.fromRGB(30, 30, 30),

    InputBackground = Color3.fromRGB(30, 30, 30),
    InputStroke = Color3.fromRGB(65, 65, 65),
    PlaceholderColor = Color3.fromRGB(178, 178, 178),

    Accent = Color3.fromRGB(72, 194, 116),
    Accent2 = Color3.fromRGB(105, 224, 146),
    AccentDark = Color3.fromRGB(32, 104, 59),
    Element = Color3.fromRGB(30, 30, 30),
    ElementHover = Color3.fromRGB(36, 36, 36),
    ElementPressed = Color3.fromRGB(24, 24, 24),
    Text = Color3.fromRGB(240, 240, 240),
    Muted = Color3.fromRGB(178, 178, 178),
    Faint = Color3.fromRGB(125, 125, 125),
    Border = Color3.fromRGB(61, 75, 65),
    Border2 = Color3.fromRGB(42, 54, 45),
    StatBackground = Color3.fromRGB(24, 78, 46),
    StatBackgroundHover = Color3.fromRGB(30, 94, 56),
    StatStroke = Color3.fromRGB(72, 145, 96),
    Danger = Color3.fromRGB(255, 72, 91),
    Success = Color3.fromRGB(67, 221, 147),
    White = Color3.new(1, 1, 1),
}

-- Make every dark theme's background layers darker (light "white" theme is left alone)
do
    local DARKEN = 0.55
    for name, t in pairs(Themes) do
        if name ~= "white" and name ~= "default" then
            for _, key in ipairs({"Background", "Background2", "Panel", "Panel2"}) do
                local c = t[key]
                if c then
                    t[key] = Color3.new(c.R * DARKEN, c.G * DARKEN, c.B * DARKEN)
                end
            end
        end
    end
end

local Icons = {lucide = {}}
pcall(function()
    local source = "https://raw.githubusercontent.com/Footagesus/Icons/refs/heads/main/lucide/dist/Icons.lua"
    local ok, result = pcall(function()
        return loadstring(game:HttpGet(source))()
    end)
    if ok and type(result) == "table" then
        Icons.lucide = result
    end
end)

DarkyX.Icons = Icons
DarkyX.Themes = Themes

-- CASE-INSENSITIVE CONFIG: every config table (window, tab, section, group, every element, notification, popup, key
-- system) is read case-insensitively, so  title / Title / TITLE ,  callback / Callback ,  sidebarLayout / SidebarLayout
-- ... all work. Underscores / spaces / dashes are ignored too (Show_Text = showtext), and a few common names are
-- accepted for the same setting:  title = name = label ,  desc = description ,  default = value ,  onclick = callback ,
-- values / items = options.  The user's own table is kept (live), only a lookup fallback is added to it.
local CI_ALIASES = {
    name = {"title", "label"},
    title = {"name", "label"},
    description = {"desc"},
    value = {"default", "currentvalue", "defaultvalue"},
    callback = {"onclick"},
    options = {"values", "items"},
}
local ciKeyCache = {}
local function ciNormal(key)
    local cached = ciKeyCache[key]
    if cached == nil then
        cached = string.lower(key):gsub("[%s_%-]", "")
        ciKeyCache[key] = cached
    end
    return cached
end
local ciMeta = {}
ciMeta.__index = function(tbl, key)
    if type(key) ~= "string" then return nil end
    local want = ciNormal(key)
    local alternatives = CI_ALIASES[want]
    for k, v in next, tbl do
        if type(k) == "string" and ciNormal(k) == want then return v end
    end
    if alternatives then
        for _, other in ipairs(alternatives) do
            for k, v in next, tbl do
                if type(k) == "string" and ciNormal(k) == other then return v end
            end
        end
    end
    return nil
end
local function ci(tbl)
    if type(tbl) ~= "table" then return tbl end
    local meta = getmetatable(tbl)
    if meta == ciMeta then return tbl end
    if meta == nil then
        pcall(setmetatable, tbl, ciMeta)
        if getmetatable(tbl) == ciMeta then return tbl end
    end
    -- the table already has its own metatable (or is locked): read from a copy instead
    local copy = {}
    for k, v in next, tbl do copy[k] = v end
    return setmetatable(copy, ciMeta)
end

-- Flag resolver for the Save Manager.
-- * Flag = "Name" (or flag = "Name") is used as-is.
-- * If an element has no Flag, one is generated automatically ("Slider_TabName_ElementName",
--   numbered when the same name appears twice), so EVERY stateful element is saved and loaded.
-- * Pass no `kind` (Stat) to only register explicit flags.
local function getFlag(element, kind, tabName, registry)
    if type(element) ~= "table" then return nil end
    local f = element.Flag
    if f == nil then f = element.flag end
    if f ~= nil and tostring(f) ~= "" then return tostring(f) end
    if not kind then return nil end
    local function clean(text) return (tostring(text or ""):gsub("[^%w]+", "")) end
    local base = kind .. "_" .. clean(tabName) .. "_" .. clean(element.name or kind)
    local flag, n = base, 1
    while registry and registry[flag] do
        n += 1
        flag = base .. "_" .. n
    end
    element.Flag = flag
    return flag
end

local function new(className, props, parent)
    local object = Instance.new(className)
    for property, value in pairs(props or {}) do
        -- one bad / unsupported property must never abort the whole interface build
        local ok, err = pcall(setProperty, object, property, value)
        if not ok then
            Security.warnOnce(className .. "." .. tostring(property), "could not set " .. className .. "." .. tostring(property) .. ": " .. tostring(err))
        end
    end
    if parent then
        local ok, err = pcall(setProperty, object, "Parent", parent)
        if not ok then
            Security.warnOnce("parent-" .. className, "could not parent " .. className .. ": " .. tostring(err))
        end
    end
    return object
end

local function corner(parent, radius)
    return new("UICorner", {CornerRadius = squareRadius(radius or UDim.new(0, 10))}, parent)
end

local function stroke(parent, color, transparency, thickness)
    return new("UIStroke", {
        Color = color,
        Transparency = transparency or 0,
        Thickness = thickness or 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, parent)
end

local function gradient(parent, colors, rotation, transparency)
    local g = new("UIGradient", {
        Rotation = rotation or 0,
        Color = ColorSequence.new(colors),
    }, parent)
    if transparency then
        if typeof(transparency) == "NumberSequence" then
            g.Transparency = transparency
        else
            g.Transparency = NumberSequence.new(transparency)
        end
    end
    return g
end

local function tween(object, duration, properties, style, direction)
    if not object then return end
    if DarkyX._Slow then duration = duration * 0.55 end -- Slow mode: every animation is shorter (lighter on slow devices)
    local ok, animation = pcall(function()
        local created = TweenService:Create(object, TweenInfo.new(duration, style or Enum.EasingStyle.Quint, direction or Enum.EasingDirection.Out), properties)
        created:Play()
        return created
    end)
    if not ok then return nil end -- a failed animation must never break the code that asked for it
    return animation
end

local function getTheme(theme)
    if type(theme) == "table" then
        -- a custom / partial theme table: missing keys fall back to the default theme instead of being nil
        if rawget(theme, "Panel") and rawget(theme, "Text") and rawget(theme, "Muted") and rawget(theme, "Accent")
            and rawget(theme, "Background") and rawget(theme, "Element") and rawget(theme, "ElementHover") and rawget(theme, "Danger") then
            return theme
        end
        return setmetatable({}, {__index = function(_, key)
            local value = theme[key]
            if value == nil then value = Themes.default[key] end
            return value
        end})
    end
    return Themes[string.lower(tostring(theme or "default"))] or Themes.default
end

-- true for "no image": nil, false, 0, "", "0", "rbxassetid://0" (asset 0 does not exist, so it must never be loaded)
local function isBlankAsset(value)
    if value == nil or value == false then return true end
    local text = string.lower((string.gsub(tostring(value), "%s", "")))
    return text == "" or text == "0" or text == "rbxassetid://0" or text == "rbxassetid:0"
end

local function resolveIcon(icon)
    if isBlankAsset(icon) then
        return nil
    end
    if typeof(icon) == "number" then
        return "rbxassetid://" .. tostring(icon)
    end
    if type(icon) ~= "string" then
        return nil
    end
    if icon:match("^rbxassetid://") then
        return icon
    end
    local name = string.lower(icon)
    local tableRef = Icons.lucide
    if tableRef then
        if tableRef[name] then return tableRef[name] end
        local compact = name:gsub("[^%w]", "")
        for key, value in pairs(tableRef) do
            if string.lower(tostring(key)):gsub("[^%w]", "") == compact then
                return value
            end
        end
    end
    return nil
end

local function makeIcon(parent, icon, size, color, zIndex)
    local asset = resolveIcon(icon)
    if not asset then return nil end
    return new("ImageLabel", {
        Name = "Icon",
        BackgroundTransparency = 1,
        Image = asset,
        ImageColor3 = color or Color3.new(1, 1, 1),
        Size = UDim2.fromOffset(size or 18, size or 18),
        ScaleType = Enum.ScaleType.Fit,
        ZIndex = zIndex or 1,
    }, parent)
end

local function addScale(parent, scale)
    return new("UIScale", {Scale = scale or 1}, parent)
end

-- Crisp drawn icons (no icon pack needed, sharp at any size). Each returns (holder, setColor).
local function drawMagnifier(parent, size, color, z)
    -- NEW search icon: a round lens (ring) with a small inner reflection and a long, round-capped handle.
    -- Drawn on a 20px canvas so it stays crisp when scaled. Returns (holder, setColor).
    size = math.max(tonumber(size) or 16, 16)
    local k = size / 20
    local holder = new("Frame", {
        Name = "Icon", BackgroundTransparency = 1, BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(size, size), ZIndex = z,
    }, parent)
    local lens = new("Frame", {
        BackgroundTransparency = 1, BorderSizePixel = 0,
        Position = UDim2.fromOffset(1.5 * k, 1.5 * k), Size = UDim2.fromOffset(12.5 * k, 12.5 * k), ZIndex = z,
    }, holder)
    corner(lens, UDim.new(1, 0))
    local lensStroke = stroke(lens, color, 0, math.max(1.9 * k, 1.8))
    -- small reflection inside the lens (top left), a quarter of the strength of the ring
    local shine = new("Frame", {
        BackgroundColor3 = color, BackgroundTransparency = 0.55, BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(5.2 * k, 5.2 * k),
        Size = UDim2.fromOffset(3.4 * k, math.max(1.4 * k, 1.2)), Rotation = -45, ZIndex = z,
    }, holder)
    corner(shine, UDim.new(1, 0))
    local handle = new("Frame", {
        BackgroundColor3 = color, BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(15.9 * k, 15.9 * k),
        Size = UDim2.fromOffset(7.4 * k, math.max(2.6 * k, 2.2)), Rotation = 45, ZIndex = z,
    }, holder)
    corner(handle, UDim.new(1, 0))
    return holder, function(c)
        tween(lensStroke, 0.16, {Color = c})
        tween(shine, 0.16, {BackgroundColor3 = c})
        tween(handle, 0.16, {BackgroundColor3 = c})
    end
end

-- SETTINGS ICON (drawn in code, no asset id that can expire): a crisp OUTLINE gear like the Lucide "settings" icon.
-- The outline is ONE closed line made of 40 short round-capped segments (8 trapezoid teeth with a slightly rounded root),
-- plus a round ring in the middle. Every size is relative to a 20px canvas, so it stays sharp at any scale.
-- Returns (holder, setColor).
local function drawGear(parent, size, color, z)
    size = math.max(tonumber(size) or 20, 16)
    local k = size / 20
    local holder = new("Frame", {
        Name = "Icon", BackgroundTransparency = 1, BorderSizePixel = 0, ClipsDescendants = false,
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(size, size), ZIndex = z,
    }, parent)
    local thickness = math.max(1.9 * k, 1.7)
    local TEETH, ROOT, TIP = 8, 6.5, 8.55
    local ROOT_HALF, TIP_HALF = 13, 8 -- half width of a tooth in degrees (at the root / at the tip)
    local function point(radius, degrees)
        local a = math.rad(degrees)
        return Vector2.new(10 + math.sin(a) * radius, 10 - math.cos(a) * radius)
    end
    local points = {}
    for tooth = 0, TEETH - 1 do
        local centre = tooth * (360 / TEETH)
        table.insert(points, point(ROOT, centre - ROOT_HALF))
        table.insert(points, point(TIP, centre - TIP_HALF))
        table.insert(points, point(TIP, centre + TIP_HALF))
        table.insert(points, point(ROOT, centre + ROOT_HALF))
        table.insert(points, point(ROOT, centre + (360 / TEETH) / 2)) -- middle of the root between two teeth
    end
    local segments = {}
    for index = 1, #points do
        local a = points[index]
        local b = points[index % #points + 1]
        local delta = b - a
        local length = delta.Magnitude
        local segment = new("Frame", {
            BackgroundColor3 = color, BorderSizePixel = 0,
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromOffset((a.X + b.X) / 2 * k, (a.Y + b.Y) / 2 * k),
            Size = UDim2.fromOffset(length * k + thickness, thickness),
            Rotation = math.deg(math.atan2(delta.Y, delta.X)), ZIndex = z,
        }, holder)
        corner(segment, UDim.new(1, 0))
        table.insert(segments, segment)
    end
    -- the round ring in the middle (the stroke is drawn outside the frame, so the ring's centre line is 3px from the middle)
    local ring = new("Frame", {
        BackgroundTransparency = 1, BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(math.max((3 * 2 - thickness / k) * k, 2), math.max((3 * 2 - thickness / k) * k, 2)), ZIndex = z,
    }, holder)
    corner(ring, UDim.new(1, 0))
    local ringStroke = stroke(ring, color, 0, thickness)
    return holder, function(c)
        tween(ringStroke, 0.16, {Color = c})
        for _, segment in ipairs(segments) do tween(segment, 0.16, {BackgroundColor3 = c}) end
    end
end

-- NEW settings icon (Gen 2 rework): three sliders, each with a round knob. Drawn in code (no asset id that can expire).
local function drawSettings(parent, size, color, z)
    size = math.max(tonumber(size) or 20, 16)
    local k = size / 20
    local holder = new("Frame", {
        Name = "Icon", BackgroundTransparency = 1, BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(size, size), ZIndex = z,
    }, parent)
    local thick = math.max(1.8 * k, 1.6)
    local parts, strokes = {}, {}
    local rows = {{y = 5, knob = 7}, {y = 10, knob = 13.5}, {y = 15, knob = 8.5}}
    local KNOB, GAP = 4.6, 3.1
    for _, row in ipairs(rows) do
        local function segment(x1, x2)
            if x2 - x1 < 0.5 then return end
            local bar = new("Frame", {
                BackgroundColor3 = color, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 0.5),
                Position = UDim2.fromOffset(x1 * k, row.y * k), Size = UDim2.fromOffset((x2 - x1) * k, thick), ZIndex = z,
            }, holder)
            corner(bar, UDim.new(1, 0))
            table.insert(parts, bar)
        end
        segment(2, row.knob - GAP)
        segment(row.knob + GAP, 18)
        local ring = new("Frame", {
            BackgroundTransparency = 1, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromOffset(row.knob * k, row.y * k),
            Size = UDim2.fromOffset(math.max((KNOB - 1.6) * k, 2), math.max((KNOB - 1.6) * k, 2)), ZIndex = z,
        }, holder)
        corner(ring, UDim.new(1, 0))
        table.insert(strokes, stroke(ring, color, 0, thick))
    end
    return holder, function(c)
        for _, ringStroke in ipairs(strokes) do tween(ringStroke, 0.16, {Color = c}) end
        for _, bar in ipairs(parts) do tween(bar, 0.16, {BackgroundColor3 = c}) end
    end
end

-- Drawn fallbacks for the window controls (used when the icon pack could not be downloaded, so the
-- minimize / close / back buttons never end up empty).
local function drawBar(holder, z, width, height, x, y, rotation, color)
    return new("Frame", {
        BackgroundColor3 = color, BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x, y),
        Size = UDim2.fromOffset(width, height), Rotation = rotation or 0, ZIndex = z,
    }, holder)
end
local function drawBarHolder(parent, size, z)
    return new("Frame", {
        Name = "Icon", BackgroundTransparency = 1, BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(size, size), ZIndex = z,
    }, parent)
end
local function barsColorSetter(bars)
    return function(c)
        for _, bar in ipairs(bars) do tween(bar, 0.16, {BackgroundColor3 = c}) end
    end
end
local function drawMinus(parent, size, color, z)
    local holder = drawBarHolder(parent, size, z)
    local bars = {drawBar(holder, z, size * 0.62, 2, size / 2, size / 2, 0, color)}
    corner(bars[1], UDim.new(1, 0))
    return holder, barsColorSetter(bars)
end
local function drawCross(parent, size, color, z)
    local holder = drawBarHolder(parent, size, z)
    local length = size * 0.78
    local bars = {
        drawBar(holder, z, length, 2, size / 2, size / 2, 45, color),
        drawBar(holder, z, length, 2, size / 2, size / 2, -45, color),
    }
    for _, bar in ipairs(bars) do corner(bar, UDim.new(1, 0)) end
    return holder, barsColorSetter(bars)
end
local function drawArrowLeft(parent, size, color, z)
    local holder = drawBarHolder(parent, size, z)
    local k = size / 16
    local bars = {
        drawBar(holder, z, 10 * k, 2, 8.5 * k, 8 * k, 0, color),        -- shaft
        drawBar(holder, z, 7.2 * k, 2, 5.6 * k, 5.4 * k, -45, color),   -- upper head
        drawBar(holder, z, 7.2 * k, 2, 5.6 * k, 10.6 * k, 45, color),   -- lower head
    }
    for _, bar in ipairs(bars) do corner(bar, UDim.new(1, 0)) end
    return holder, barsColorSetter(bars)
end

-- LoadingTitle icon: sits on the LEFT of the big title, and the icon + title are centered together on screen.
-- Default image is set here; CreateWindow({ LoadingIcon = "rbxassetid://..." }) changes it, LoadingIcon = false hides it.
local DEFAULT_LOADING_ICON = "rbxassetid://122219837651457"
local LOADING_ICON_SIZE = 60 -- medium: a bit shorter than the 74px title text
local function addLoadingIcon(label, iconValue)
    if iconValue == false then return nil end
    if iconValue == nil then iconValue = DEFAULT_LOADING_ICON end
    local asset = resolveIcon(iconValue)
    if not asset then return nil end
    local gap = 12
    local okSize, measured = pcall(function()
        return TextService:GetTextSize(label.Text, label.TextSize, label.Font, Vector2.new(2000, 200))
    end)
    local textW = okSize and measured.X or (#label.Text * label.TextSize * 0.62)
    local width = math.max(label.Size.X.Offset, math.ceil(textW + LOADING_ICON_SIZE + gap) + 80)
    label.Size = UDim2.fromOffset(width, label.Size.Y.Offset)
    -- shift the label so the (icon + title) pair is centered, not just the title
    label.Position = UDim2.new(label.Position.X.Scale, label.Position.X.Offset + (LOADING_ICON_SIZE + gap) / 2, label.Position.Y.Scale, label.Position.Y.Offset)
    return new("ImageLabel", {
        Name = "LoadingIcon",
        BackgroundTransparency = 1,
        Image = asset,
        ImageTransparency = 1,
        ScaleType = Enum.ScaleType.Fit,
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, width / 2 - textW / 2 - gap - LOADING_ICON_SIZE, 0.5, 0),
        Size = UDim2.fromOffset(LOADING_ICON_SIZE, LOADING_ICON_SIZE),
        ZIndex = label.ZIndex + 1,
    }, label)
end

-- LoadingTitle DARKER FADE: the title (and its icon) fades from the normal colour at the top to a darker
-- colour beneath. It is only a colour gradient, so the fade-in / fade-out tweens keep working.
local function addLoadingDarkFade(label, icon)
    local base = label.TextColor3
    local dark = base:Lerp(Color3.new(0, 0, 0), 0.62)
    local function gradient(parent)
        return new("UIGradient", {
            Name = "LoadingDarkFade",
            Rotation = 90,
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, base),
                ColorSequenceKeypoint.new(0.4, base),
                ColorSequenceKeypoint.new(1, dark),
            }),
        }, parent)
    end
    gradient(label)
    if icon then gradient(icon) end
end

-- Depth EFFECT without any extra boxes: the input itself lifts a little when it is clicked (springy scale),
-- then settles back. No plates / frames are created.
local function addDepthEffect(object, lift)
    local scale = object:FindFirstChildOfClass("UIScale") or addScale(object, 1)
    local api = {}
    function api.Show() tween(scale, 0.32, {Scale = lift or 1.035}, Enum.EasingStyle.Back) end
    function api.Hide() tween(scale, 0.2, {Scale = 1}, Enum.EasingStyle.Quint) end
    return api
end

local function iconPop(icon)
    if not icon or not icon.Parent then return end
    local scale = icon:FindFirstChildOfClass("UIScale") or addScale(icon, 1)
    scale.Scale = 0.82
    icon.Rotation = -10
    tween(scale, 0.22, {Scale = 1.08}, Enum.EasingStyle.Back)
    tween(icon, 0.22, {Rotation = 0}, Enum.EasingStyle.Quint)
    task.delay(0.18, function()
        if scale.Parent then tween(scale, 0.15, {Scale = 1}, Enum.EasingStyle.Quint) end
    end)
end

-- keeps a dragged object reachable: at least `margin` pixels (and the whole top edge) stay on screen
-- Drag helper (rewritten).
--   * Only the finger / mouse button that STARTED the drag can move it (a 2nd finger or stray touch can no longer
--     make the target jump to the bottom of the screen).
--   * The new position is calculated from the start position + the movement, and the allowed range is worked out
--     ONCE when the drag starts. Nothing is read back from AbsolutePosition while moving (that value lags behind
--     and caused the sudden teleport).
--   * A drag can never get "stuck": a new press always resets an old, unfinished drag, and losing the window focus
--     or the pointer release ends it too.
--   opts.fullyVisible = true  -> the target can never leave the screen (used by the floating button)
--   opts.onStart              -> called when a drag begins (used to stop a running position tween)
local function makeDrag(handle, target, onClick, onDragEnd, opts)
    opts = opts or {}
    local dragging = false
    local moved = false
    local startInput
    local dragStart
    local startPosition
    local minDx, maxDx, minDy, maxDy = -math.huge, math.huge, -math.huge, math.huge
    local moveConnection, endConnection, focusConnection

    local function releaseConnections()
        if moveConnection then moveConnection:Disconnect(); moveConnection = nil end
        if endConnection then endConnection:Disconnect(); endConnection = nil end
        if focusConnection then focusConnection:Disconnect(); focusConnection = nil end
    end

    local function stopDrag(cancelled)
        local wasMoved = moved
        local wasDragging = dragging
        dragging = false
        startInput = nil
        releaseConnections()
        if not wasDragging then return end
        if wasMoved and onDragEnd then onDragEnd() end
        if not wasMoved and not cancelled and onClick then onClick() end
    end

    -- how far the target may move from where it started, so it always stays reachable on screen
    local function computeLimits()
        minDx, maxDx, minDy, maxDy = -math.huge, math.huge, -math.huge, math.huge
        local parent = target.Parent
        if not parent or not parent:IsA("GuiBase2d") then return end
        local view, viewPos = parent.AbsoluteSize, parent.AbsolutePosition
        if view.X <= 0 or view.Y <= 0 then return end
        local pos, size = target.AbsolutePosition, target.AbsoluteSize
        local marginX = opts.fullyVisible and size.X or math.min(48, size.X)
        local marginY = opts.fullyVisible and size.Y or 48
        -- left / right edge (the target keeps `marginX` pixels on screen)
        minDx = (viewPos.X + marginX - size.X) - pos.X
        maxDx = (viewPos.X + view.X - marginX) - pos.X
        -- top edge is never crossed; at the bottom `marginY` pixels stay on screen
        minDy = viewPos.Y - pos.Y
        maxDy = (viewPos.Y + view.Y - marginY) - pos.Y
        if minDx > maxDx then minDx, maxDx = 0, 0 end
        if minDy > maxDy then minDy, maxDy = 0, 0 end
    end

    handle.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
        -- a new press always wins over an old unfinished drag (this is what used to leave the button "stuck")
        if dragging then
            dragging = false
            releaseConnections()
        end
        dragging = true
        moved = false
        startInput = input
        dragStart = input.Position
        startPosition = target.Position
        if opts.onStart then pcall(opts.onStart) end
        local limitsOk = pcall(computeLimits)
        if not limitsOk then minDx, maxDx, minDy, maxDy = -math.huge, math.huge, -math.huge, math.huge end

        moveConnection = UserInputService.InputChanged:Connect(function(changed)
            if not dragging then return end
            local isTouch = startInput.UserInputType == Enum.UserInputType.Touch
            if isTouch then
                if changed ~= startInput then return end -- only the finger that started the drag
            elseif changed.UserInputType ~= Enum.UserInputType.MouseMovement then
                return
            end
            local delta = changed.Position - dragStart
            if math.abs(delta.X) > 4 or math.abs(delta.Y) > 4 then moved = true end
            if not moved then return end -- a tap must not nudge the target
            local dx = math.clamp(delta.X, minDx, maxDx)
            local dy = math.clamp(delta.Y, minDy, maxDy)
            target.Position = UDim2.new(startPosition.X.Scale, startPosition.X.Offset + dx, startPosition.Y.Scale, startPosition.Y.Offset + dy)
        end)
        -- the release is listened to GLOBALLY: if the pointer slides off the handle the drag still ends
        endConnection = UserInputService.InputEnded:Connect(function(ended)
            if not dragging then return end
            if startInput.UserInputType == Enum.UserInputType.Touch then
                if ended ~= startInput then return end
            elseif ended.UserInputType ~= Enum.UserInputType.MouseButton1 then
                return
            end
            stopDrag(false)
        end)
        -- alt-tab / menu opened while holding: end the drag instead of leaving it half-finished
        focusConnection = UserInputService.WindowFocusReleased:Connect(function()
            stopDrag(true)
        end)
    end)

    handle.Destroying:Connect(function()
        dragging = false
        startInput = nil
        releaseConnections()
    end)
end

local function autoCanvas(scrollingFrame, layout)
    layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        local size = layout.AbsoluteContentSize
        scrollingFrame.CanvasSize = UDim2.fromOffset(0, size.Y + 12)
    end)
end

local function addGlow(parent, color, transparency, thickness)
    local glow = new("Frame", {
        Name = "Glow",
        BackgroundColor3 = color,
        BackgroundTransparency = transparency or 0.92,
        Position = UDim2.fromOffset(-8, -8),
        Size = UDim2.new(1, 16, 1, 16),
        ZIndex = (parent.ZIndex or 1) - 1,
    }, parent.Parent)
    corner(glow, UDim.new(0, thickness or 18))
    return glow
end

-- Neutral greys used for element borders and every soft glow (dark themes / light theme).
local function isLightTheme(theme)
    local bg = theme.Background or Color3.new(0, 0, 0)
    return (0.299 * bg.R + 0.587 * bg.G + 0.114 * bg.B) > 0.55
end

local function neutralGrey(theme)
    if isLightTheme(theme) then
        return Color3.fromRGB(105, 105, 105), Color3.fromRGB(190, 190, 190) -- glow, border
    end
    return Color3.fromRGB(165, 165, 165), Color3.fromRGB(55, 55, 55)
end

-- Soft glow made from stacked, increasingly faint strokes (smooth falloff, no image assets needed).
--   outer = glow ring outside the box      inner = glow ring just inside the edge
-- (inner is used where a parent clips its children, so the glow can never be cut off)
local GLOW_OUTER = {{1.5, 0.70}, {3.5, 0.85}, {6, 0.94}}
local GLOW_INNER = {{2, 0.66}, {4, 0.82}, {7, 0.93}}

local function addSoftGlow(object, color, radius, opts)
    opts = opts or {}
    local strength = opts.strength or 1
    local sizeScale = opts.size or 1
    radius = radius or 0
    local layers = {}
    local function add(name, layer, inset, thickness)
        local frame = new("Frame", {
            Name = name,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Active = false,
            Position = UDim2.fromOffset(inset, inset),
            Size = UDim2.new(1, -inset * 2, 1, -inset * 2),
            ZIndex = 1,
        }, object)
        corner(frame, UDim.new(0, math.max(radius - inset, 0)))
        local base = math.clamp(1 - (1 - layer[2]) * strength, 0, 1)
        local glowStroke = stroke(frame, color, base, thickness)
        table.insert(layers, {Frame = frame, Stroke = glowStroke, Base = base})
    end
    if opts.inner ~= false then
        for index, layer in ipairs(GLOW_INNER) do add("SoftGlowIn" .. index, layer, layer[1], layer[1]) end
    end
    if opts.outer ~= false then
        for index, layer in ipairs(GLOW_OUTER) do add("SoftGlowOut" .. index, layer, 0, layer[1] * sizeScale) end
    end
    return layers
end

-- Toggle knob effect: the library's LIGHT SOFT WHITE EFFECT on the knob itself (the same white glass sheen + soft top light the
-- element boxes use) plus the AMBIENT GLOW as a soft INNER glow / bloom: a bright, soft core inside the knob and a tight
-- halo of the theme colour that stays INSIDE the track (nothing spreads outside the toggle).
-- The knob keeps the colour of the theme the UI library uses (green on Default, the accent on the others).
-- Effect = false: the knob keeps the plain look of the reference (shaded pill + thin light rim), but no light soft white effect
-- and no glow.
-- The glow starts in the SAME moment the toggle is turned ON (no delay).
-- the knob colour while the toggle is OFF: dark, but not flat (the light soft white effect below sits on top of it)
local function knobOffColorFor(light)
    return light and Color3.fromRGB(96, 98, 108) or Color3.fromRGB(38, 38, 42)
end

-- every knob effect controller is listed here, so Slow mode can switch them all at once (weak: gone with the toggle)
local knobRegistry = setmetatable({}, {__mode = "k"})

-- enabled = true / false, or a function returning it (the toggles pass one, so Slow mode takes effect immediately)
local function addKnobGlow(knob, enabledValue, light, knobStroke)
    local function isEnabled()
        if type(enabledValue) == "function" then return enabledValue() == true end
        return enabledValue == true
    end
    local white = Color3.new(1, 1, 1)
    -- knob shading (like the reference): the top keeps the full colour, the bottom is a little deeper. This is part of the
    -- plain knob look, so it is ALWAYS on (also with Effect = false); only the light + glow below need Effect = true.
    local sheen = new("UIGradient", {
        Name = "KnobSheen", Rotation = 90, Enabled = true,
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, white),
            ColorSequenceKeypoint.new(0.45, white),
            ColorSequenceKeypoint.new(1, light and Color3.fromRGB(200, 200, 200) or Color3.fromRGB(120, 120, 120)),
        }),
    }, knob)
    local topLight = new("Frame", {
        Name = "KnobLight", BackgroundColor3 = white, BackgroundTransparency = 1, BorderSizePixel = 0, Active = false,
        Size = UDim2.fromScale(1, 1), ZIndex = (knob.ZIndex or 2) + 1,
    }, knob)
    corner(topLight, UDim.new(1, 0))
    gradient(topLight, {
        ColorSequenceKeypoint.new(0, white),
        ColorSequenceKeypoint.new(1, white),
    }, 90, NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.1),
        NumberSequenceKeypoint.new(0.65, 0.85),
        NumberSequenceKeypoint.new(1, 1),
    })).Name = "KnobLightFade"

    -- AMBIENT GLOW = soft INNER glow / bloom (only while the toggle is ON). Two parts, both made of stacked pill layers
    -- (no hard ring, no thick outline, no image assets):
    --   1) inner bloom : a soft, bright core INSIDE the knob (smaller and smaller layers of the lit theme colour)
    --   2) halo        : a tight halo of the theme colour around the knob that stays INSIDE the track
    -- It fades in the moment the toggle turns ON, fades out when it turns OFF and breathes very slowly while it is ON.
    -- Built the first time the toggle is turned ON (toggles that stay OFF never create it).
    -- Tuning: GLOW_REACH = how far the halo spreads (px, keep it inside the track), GLOW_POWER = halo strength,
    --         CORE_POWER = strength of the bloom inside the knob, GLOW_BREATHE = slow pulse.
    local GLOW_LAYERS = 6
    local GLOW_REACH = 2.5
    local GLOW_POWER = 0.09
    local CORE_LAYERS = 4
    local CORE_POWER = 0.035
    local GLOW_BREATHE = true
    local glowHolder, glowBloom, glowScale, glowLayers, coreLayers, breathTween
    local glowToken = 0
    local glowActive = false

    local function stopBreathe()
        if breathTween then pcall(function() breathTween:Cancel() end) breathTween = nil end
        if glowScale and glowScale.Parent then glowScale.Scale = 1 end
    end
    local function startBreathe()
        if not GLOW_BREATHE or not glowScale then return end
        stopBreathe()
        local ok, created = pcall(function()
            local info = TweenInfo.new(1.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
            local t = TweenService:Create(glowScale, info, {Scale = 1.05})
            t:Play()
            return t
        end)
        if ok then breathTween = created end
    end

    -- opacity of ONE halo layer: strongest next to the knob, fainter and fainter outwards (the layers stack up)
    local function layerAlpha(index)
        local falloff = 1 - (index - 1) / GLOW_LAYERS
        return GLOW_POWER * falloff * falloff
    end

    local function buildGlow()
        if glowHolder then return glowHolder.Parent ~= nil end
        local parent = knob.Parent
        if not parent then return false end
        -- the halo holder sits BEHIND the knob (same parent, lower ZIndex) and follows it while it slides
        glowHolder = new("Frame", {
            Name = "AmbientGlow", BackgroundTransparency = 1, BorderSizePixel = 0, Active = false,
            AnchorPoint = knob.AnchorPoint, Position = knob.Position, Size = knob.Size,
            ZIndex = math.max((knob.ZIndex or 2) - 1, 1),
        }, parent)
        glowBloom = new("Frame", {
            Name = "Bloom", BackgroundTransparency = 1, BorderSizePixel = 0, Active = false,
            AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1),
        }, glowHolder)
        glowScale = new("UIScale", {Scale = 1}, glowBloom)
        glowLayers = {}
        for index = 1, GLOW_LAYERS do
            local grow = GLOW_REACH * index / GLOW_LAYERS
            local layer = new("Frame", {
                Name = "BloomLayer" .. index, BackgroundColor3 = white, BackgroundTransparency = 1,
                BorderSizePixel = 0, Active = false,
                AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
                Size = UDim2.new(1, grow * 2, 1, grow * 2),
                ZIndex = GLOW_LAYERS - index + 1, -- the biggest, faintest layer is the lowest one
            }, glowBloom)
            corner(layer, UDim.new(1, 0))
            glowLayers[index] = layer
        end
        -- the soft bright core INSIDE the knob (children of the knob, so they slide with it)
        coreLayers = {}
        for index = 1, CORE_LAYERS do
            local inset = (index - 1) * 1.4
            local layer = new("Frame", {
                Name = "InnerBloom" .. index, BackgroundColor3 = white, BackgroundTransparency = 1,
                BorderSizePixel = 0, Active = false,
                AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
                Size = UDim2.new(1, -inset * 2, 1, -inset * 2),
                ZIndex = (knob.ZIndex or 2) + 1,
            }, knob)
            corner(layer, UDim.new(1, 0))
            coreLayers[index] = layer
        end
        local function follow() if glowHolder and glowHolder.Parent then glowHolder.Position = knob.Position end end
        knob:GetPropertyChangedSignal("Position"):Connect(follow)
        glowHolder.Destroying:Connect(stopBreathe)
        return true
    end

    -- colour the layers: the halo is a little whiter next to the knob, the core is the lit theme colour
    local function paintGlow(color, duration)
        for index, layer in ipairs(glowLayers) do
            local core = 0.06 * (1 - (index - 1) / math.max(GLOW_LAYERS - 1, 1))
            if layer.BackgroundTransparency >= 1 then layer.BackgroundColor3 = color:Lerp(white, core) end -- fresh layer: right colour from the first frame
            tween(layer, duration, {
                BackgroundColor3 = color:Lerp(white, core),
                BackgroundTransparency = 1 - layerAlpha(index),
            }, Enum.EasingStyle.Quad)
        end
        for _, layer in ipairs(coreLayers) do
            local lit = color
            if layer.BackgroundTransparency >= 1 then layer.BackgroundColor3 = lit end
            tween(layer, duration, {BackgroundColor3 = lit, BackgroundTransparency = 1 - CORE_POWER}, Enum.EasingStyle.Quad)
        end
    end

    local function stopGlow()
        glowToken += 1
        glowActive = false
        if glowLayers then
            for _, layer in ipairs(glowLayers) do tween(layer, 0.25, {BackgroundTransparency = 1}, Enum.EasingStyle.Quad) end
            for _, layer in ipairs(coreLayers) do tween(layer, 0.25, {BackgroundTransparency = 1}, Enum.EasingStyle.Quad) end
            local token = glowToken
            task.delay(0.3, function() if token == glowToken then stopBreathe() end end)
        end
        if knobStroke and knobStroke.Parent then
            tween(knobStroke, 0.2, {Thickness = 1, Transparency = 0.82, Color = white})
        end
    end
    -- the knob rim while the toggle is ON: a thin, lighter line of the theme colour (the outline of the reference knob).
    -- Part of the plain look, so it also shows with Effect = false.
    local function showRim(color, duration)
        if knobStroke and knobStroke.Parent then
            knobStroke.Color = color
            tween(knobStroke, duration, {Thickness = 1.2, Transparency = 0}, Enum.EasingStyle.Quad)
        end
    end
    local function startGlow(color)
        glowToken += 1
        glowActive = true
        -- NO delay any more: the glow starts in the same moment the toggle is turned ON and grows while the knob slides
        if not knob.Parent or not buildGlow() then return end
        showRim(color, 0.15)
        paintGlow(color, 0.15)
        if not breathTween then startBreathe() end
    end

    local controller = {}
    local isOn = false
    local lastColor = white
    function controller.Show(on, instant, color)
        color = color or white
        isOn = on == true
        lastColor = color
        if not isEnabled() then
            -- Slow mode: the plain look only (shaded pill + light rim), no light soft white effect, no glow
            if glowLayers then stopGlow() end
            topLight.BackgroundTransparency = 1
            if on then showRim(color, instant and 0 or 0.15)
            elseif knobStroke and knobStroke.Parent then
                tween(knobStroke, instant and 0 or 0.15, {Thickness = 1, Transparency = 0.82, Color = white})
            end
            return
        end
        -- the light soft white effect is on the knob in BOTH states: soft while OFF (dark knob), stronger while ON (theme colour)
        local value = on and 0.93 or 0.95
        if instant then topLight.BackgroundTransparency = value else tween(topLight, 0.22, {BackgroundTransparency = value}, Enum.EasingStyle.Quad) end
        if on then startGlow(color) else stopGlow() end
    end
    -- the theme colour changed (ColorPicker): the glow follows it while the toggle is ON
    function controller.Recolor(color)
        lastColor = color or white
        if isEnabled() then
            if glowActive then startGlow(color) end
        elseif isOn then
            showRim(color, 0.15)
        end
    end
    -- Slow mode was switched: show the knob again with the right amount of effect
    function controller.Resync()
        controller.Show(isOn, true, lastColor)
    end
    knobRegistry[controller] = true
    return controller
end

local function setTextPair(holder, name, description, theme, y, widthOffset, z, x, centerIn)
    x = x or 15
    local hasDesc = description ~= nil and tostring(description) ~= ""
    if centerIn then
        -- centerIn = the box height: the title (or title + description) sits in the middle of the box
        y = hasDesc and (math.floor((centerIn - 31) / 2) + 1) or 0
    end
    local title = new("TextLabel", {
        BackgroundTransparency = 1,
        Text = tostring(name or "Element"),
        TextColor3 = theme.Text,
        Font = Enum.Font.GothamMedium,
        TextSize = 13,
        TextScaled = true, -- the title shrinks when the box is narrow (a box with two things, a small window, any size)
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        Position = UDim2.fromOffset(x, y),
        Size = UDim2.new(1, widthOffset or -30, 0, (centerIn and not hasDesc) and centerIn or (description and 18 or 26)),
        ZIndex = z or 2,
    }, holder)
    new("UITextSizeConstraint", {MaxTextSize = 13, MinTextSize = 7}, title)
    if description and tostring(description) ~= "" then
        local descriptionLabel = new("TextLabel", {
            BackgroundTransparency = 1,
            Text = tostring(description),
            TextColor3 = theme.Muted,
            Font = Enum.Font.Gotham,
            TextSize = 10,
            TextWrapped = true,
            TextScaled = true, -- shrinks too (at most 10, at least 6) instead of being cut off
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top,
            Position = UDim2.fromOffset(x, y + 19),
            Size = UDim2.new(1, widthOffset or -30, 0, 22),
            ZIndex = z or 2,
        }, holder)
        new("UITextSizeConstraint", {MaxTextSize = 10, MinTextSize = 6}, descriptionLabel)
    end
    return title
end

-- ---------------------------------------------------------------------
-- Notifications: independent of the window. DarkyX:Notify({...}) works
-- before CreateWindow, while the LoadingTitle plays and behind the key system.
--   title / content / duration / icon
-- ---------------------------------------------------------------------
local notifyLayer

local function getNotifyLayer()
    if notifyLayer and notifyLayer.Parent and notifyLayer.Parent.Parent then
        return notifyLayer
    end
    Security.currentKey = "notifications"
    pcall(Security.purge, "notifications") -- running the script again replaces the old notification layer
    local gui = Security.createScreenGui(Security.randomString(14), 1001)
    notifyLayer = new("Frame", {
        Name = "Layer",
        BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -14, 0, 76),
        Size = UDim2.fromOffset(320, 300),
        ZIndex = 180,
    }, gui)
    new("UIListLayout", {
        Padding = UDim.new(0, 8),
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        SortOrder = Enum.SortOrder.LayoutOrder,
        VerticalAlignment = Enum.VerticalAlignment.Top,
    }, notifyLayer)
    return notifyLayer
end

local notifyCounter = 0

-- Notification (full form):
--   window:Notify({
--       Title    = "Auto-saved",
--       Content  = "Your configuration was saved.",
--       Icon     = "rbxassetid://0",        -- a lucide name or an asset id; nil / "rbxassetid://0" = no icon
--       Duration = 5,                       -- seconds (the countdown runs over this time)
--       Callback = function(profile) end,   -- runs when the user CLICKS the notification
--       OnClose  = function(profile) end,   -- optional: runs once when it disappears (click or timeout)
--   })
-- profile = {Title, Content, Icon, Duration, Clicked, Closed, Card, Dismiss()}.  Notify returns the same profile.
-- The short lowercase keys (title / content / icon / duration / callback) keep working.
local function buildNotification(state, notification, themeOverride)
    local theme = getTheme(themeOverride or notification.theme or (DarkyX._Window and DarkyX._Window.Theme) or DarkyX.CurrentTheme or "default")
    local duration = tonumber(notification.duration or notification.Duration or notification.time) or 4
    duration = math.max(duration, 0.5)
    local lightUi = isLightTheme(theme)
    local W, H = 300, 68

    notifyCounter += 1
    -- holder sits in the list layout; the card inside it slides, so the stack can glide smoothly
    local holder = new("Frame", {
        Name = "Notification",
        BackgroundTransparency = 1,
        Size = UDim2.fromOffset(W, 0),
        LayoutOrder = notifyCounter,
        ZIndex = 181,
    }, getNotifyLayer())
    state.holder = holder
    local card = new("CanvasGroup", {
        BackgroundColor3 = lightUi and theme.Panel2 or Color3.fromRGB(33, 33, 36),
        BorderSizePixel = 0,
        GroupTransparency = 1,
        Position = UDim2.fromOffset(46, 0),
        Size = UDim2.fromOffset(W, H),
        ZIndex = 181,
    }, holder)
    corner(card, UDim.new(0, 14)) -- no border: the soft top light and the dark surface do the work
    local sheen = new("Frame", {
        Name = "Sheen", BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Active = false,
        Size = UDim2.fromScale(1, 1), ZIndex = 182,
    }, card)
    new("UIGradient", {
        Rotation = 90,
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, lightUi and 0.55 or 0.92),
            NumberSequenceKeypoint.new(0.7, 1),
            NumberSequenceKeypoint.new(1, 1),
        }),
    }, sheen)

    local iconValue = notification.Icon
    if iconValue == nil then iconValue = notification.icon end
    do -- "rbxassetid://0", "0", 0 and "" mean: no icon
        local text = string.lower((tostring(iconValue or ""):gsub("%s", "")))
        if text == "" or text == "0" or text == "rbxassetid://0" then iconValue = nil end
    end
    local icon = iconValue ~= nil and makeIcon(card, iconValue, 20, theme.Text, 184) or nil
    if icon then icon.Position = UDim2.fromOffset(14, 14) end
    local left = icon and 44 or 14
    new("TextLabel", {
        BackgroundTransparency = 1,
        Text = tostring(notification.title or notification.Title or "Notification"),
        TextColor3 = theme.Text, Font = Enum.Font.GothamBold, TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
        Position = UDim2.fromOffset(left, 11), Size = UDim2.new(1, -left - 52, 0, 18), ZIndex = 184,
    }, card)
    new("TextLabel", {
        BackgroundTransparency = 1,
        Text = tostring(notification.content or notification.Content or ""),
        TextColor3 = theme.Muted, Font = Enum.Font.Gotham, TextSize = 10, TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
        Position = UDim2.fromOffset(left, 31), Size = UDim2.new(1, -left - 12, 0, 28), ZIndex = 184,
    }, card)

    -- countdown: seconds left (top right). (No coloured line / progress bar at the bottom.)
    local countdown = new("TextLabel", {
        BackgroundTransparency = 1, Text = string.format("%ds", math.ceil(duration)),
        TextColor3 = theme.Muted, Font = Enum.Font.GothamMedium, TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Right,
        AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 12), Size = UDim2.fromOffset(40, 14), ZIndex = 184,
    }, card)
    local clickCatcher = new("TextButton", {
        BackgroundTransparency = 1, Text = "", AutoButtonColor = false,
        Size = UDim2.fromScale(1, 1), ZIndex = 190,
    }, card)

    local closed = false
    local callback = notification.Callback
    if callback == nil then callback = notification.callback end
    if callback == nil then callback = notification.OnClick end
    local onClose = notification.OnClose
    if onClose == nil then onClose = notification.onClose end
    local profile = {
        Title = tostring(notification.title or notification.Title or "Notification"),
        Content = tostring(notification.content or notification.Content or ""),
        Icon = iconValue,
        Duration = duration,
        Clicked = false,
        Closed = false,
        Card = card,
    }
    local function dismiss()
        if closed then return end
        closed = true
        profile.Closed = true
        if typeof(onClose) == "function" then Security.spawn(onClose, profile) end
        tween(card, 0.28, {Position = UDim2.fromOffset(46, 0), GroupTransparency = 1}, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
        task.delay(0.24, function()
            if holder.Parent then tween(holder, 0.26, {Size = UDim2.fromOffset(W, 0)}, Enum.EasingStyle.Quint) end
        end)
        task.delay(0.52, function()
            if holder.Parent then holder:Destroy() end
        end)
    end
    function profile:Dismiss() dismiss() end
    profile.Destroy = profile.Dismiss
    clickCatcher.MouseButton1Click:Connect(function()
        if closed then return end
        profile.Clicked = true
        if typeof(callback) == "function" then Security.spawn(callback, profile) end
        dismiss()
    end)

    -- smooth appear: the stack opens up, the card slides in from the right while fading in
    tween(holder, 0.26, {Size = UDim2.fromOffset(W, H)}, Enum.EasingStyle.Quint)
    tween(card, 0.42, {Position = UDim2.fromOffset(0, 0), GroupTransparency = 0}, Enum.EasingStyle.Quint)

    task.spawn(function()
        local finish = os.clock() + duration
        while not closed and holder.Parent do
            local remaining = finish - os.clock()
            if remaining <= 0 then break end
            countdown.Text = string.format("%ds", math.ceil(remaining))
            task.wait(0.1)
        end
        dismiss()
    end)
    return profile
end

-- Last-resort notification: plain Instance.new + pcall'd property sets, so a notification is ALWAYS shown.
local function buildSimpleNotification(notification, themeOverride)
    local theme = getTheme(themeOverride or notification.theme or DarkyX.CurrentTheme or "default")
    local function make(class, props, parent)
        local object = Instance.new(class)
        for key, value in pairs(props) do pcall(function() object[key] = value end) end
        if parent then pcall(function() object.Parent = parent end) end
        return object
    end
    local duration = math.max(tonumber(notification.duration or notification.Duration or notification.time) or 4, 0.5)
    local gui = Security.createScreenGui(Security.randomString(14), 1001)
    local card = make("Frame", {
        BackgroundColor3 = theme.Panel, BorderSizePixel = 0, AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -14, 0, 76), Size = UDim2.fromOffset(300, 68), ZIndex = 181,
    }, gui)
    make("UICorner", {CornerRadius = squareRadius(UDim.new(0, 14))}, card)
    make("TextLabel", {
        BackgroundTransparency = 1, Text = tostring(notification.title or notification.Title or "Notification"),
        TextColor3 = theme.Text, Font = Enum.Font.GothamBold, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
        Position = UDim2.fromOffset(14, 11), Size = UDim2.new(1, -28, 0, 18), ZIndex = 182,
    }, card)
    make("TextLabel", {
        BackgroundTransparency = 1, Text = tostring(notification.content or notification.Content or ""),
        TextColor3 = theme.Muted, Font = Enum.Font.Gotham, TextSize = 10, TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
        Position = UDim2.fromOffset(14, 31), Size = UDim2.new(1, -28, 0, 28), ZIndex = 182,
    }, card)
    local profile = {Title = tostring(notification.title or notification.Title or ""), Closed = false, Clicked = false, Card = card}
    function profile:Dismiss()
        if profile.Closed then return end
        profile.Closed = true
        pcall(function() gui:Destroy() end)
    end
    profile.Destroy = profile.Dismiss
    task.delay(duration, function() profile:Dismiss() end)
    return profile
end

-- Public entry: runs protected. An error while building can never reach (and break) the script that called Notify.
function DarkyX:Notify(notification, themeOverride)
    if type(self) == "table" and self ~= DarkyX and notification == nil then
        notification, self = self, DarkyX -- called with a dot: DarkyX.Notify({...})
    end
    if type(notification) ~= "table" then notification = {content = notification} end
    notification = ci(notification)

    local state = {}
    local ok, result = xpcall(buildNotification, debug.traceback, state, notification, themeOverride)
    if ok and result then return result end

    -- the full card failed: remove what was half built, say why, show the simple card instead
    Security.log("[DarkyX] Notify (full) failed, showing the simple notification instead. Cause:\n" .. tostring(result))
    if state.holder then pcall(function() state.holder:Destroy() end) end
    local ok2, result2 = xpcall(buildSimpleNotification, debug.traceback, notification, themeOverride)
    if ok2 and result2 then return result2 end
    Security.log("[DarkyX] Notify failed:\n" .. tostring(result2))
    return {Title = "", Content = "", Closed = true, Clicked = false, Dismiss = function() end, Destroy = function() end}
end
DarkyX.Notification = DarkyX.Notify

-- ---------------------------------------------------------------------
-- Popups: independent of the window, like notifications. DarkyX:CreatePopup({...}) / window:CreatePopup({...})
-- They load in their OWN layer (shown even before the window has loaded, while it is minimized or behind the key
-- system), centered on the screen, with the same glass card + light soft white effect as the "Delete UI Library?" popup,
-- and NO dark background: the game / UI behind stays exactly as it is.
--
--   window:CreatePopup({
--       title   = "Reset everything?",
--       content = "This clears every saved value. You can't undo it.",
--       Color   = Color3.fromRGB(255, 160, 16),          -- colour of the SecondText box (the right / confirm button) only
--       Options = {
--           { FirstText  = "Cancel" },                   -- left button  (neutral)   optional Callback = fn
--           { SecondText = "Reset"  },                   -- right button (coloured)  optional Callback = fn
--       },
--       Callback = function() end,                       -- runs when the SECOND button is pressed (confirm)
--   })
--
--   * Callback / Color can be written in the popup itself (above) OR inside the option they belong to:
--       { SecondText = "Reset", Color = Color3.fromRGB(255, 80, 80), Callback = function() end }
--   * Options also accepts plain texts: Options = {"Cancel", "Reset"}  (first = left, second = right)
--     and a single entry can hold both texts: { FirstText = "Cancel", SecondText = "Reset" }
--   * Only ONE button (e.g. { FirstText = "OK" }): Callback runs when it is pressed. No Options = one "OK" button.
--   * optional: OnCancel = fn (left button), icon = "trash-2" (false = no icon), width = 280,
--               Duration = 8 (closes by itself after 8 seconds; default: stays until a button is pressed)
--   * returns a handle: :Close()  :IsOpen()
-- ---------------------------------------------------------------------
local popupLayer
local openPopups = {}

local function getPopupLayer()
    if popupLayer and popupLayer.Parent and popupLayer.Parent.Parent then
        return popupLayer
    end
    -- popups live in the SAME ScreenGui as the notifications (that layer is created and proven to load): no second
    -- ScreenGui, nothing extra that could fail. The popup layer sits above the notifications and never blocks input.
    local gui = getNotifyLayer().Parent
    popupLayer = new("Frame", {
        Name = "PopupLayer",
        BackgroundTransparency = 1,
        Active = false, -- never blocks anything: there is no dark background
        Size = UDim2.fromScale(1, 1),
        ZIndex = 200,
    }, gui)
    return popupLayer
end

-- reads the buttons / colour / callbacks from every way a popup can be written (see the usage above)
local function readPopupButtons(cfg, theme)
    local function pick(tbl, ...)
        for _, key in ipairs({...}) do
            if tbl[key] ~= nil then return tbl[key] end
        end
        return nil -- ALWAYS one value: tonumber(pick(...)) / type(pick(...)) raise "missing argument" when nothing is returned
    end
    local function asFunction(value) if typeof(value) == "function" then return value end end
    local function asColor(value) if typeof(value) == "Color3" then return value end end

    -- read the buttons: tolerant of every way the options can be written (see the usage above)
    local rawOptions = pick(cfg, "options", "Options", "buttons", "Buttons")
    local list = ci(type(rawOptions) == "table" and rawOptions or {})
    local first, second = {}, {}
    local function plain(text, callback, color)
        local slot = (first.text == nil) and first or second
        slot.text = tostring(text)
        slot.callback = slot.callback or callback
        if slot == second then slot.color = slot.color or color end
    end
    for _, entry in ipairs(list) do
        if type(entry) == "table" then
            entry = ci(entry)
            local firstValue = pick(entry, "FirstText", "firstText")
            local secondValue = pick(entry, "SecondText", "secondText")
            local callback = asFunction(pick(entry, "callback", "Callback"))
            local color = asColor(pick(entry, "Color", "color"))
            if firstValue ~= nil or secondValue ~= nil then
                if firstValue ~= nil then
                    first.text = tostring(firstValue)
                    if secondValue == nil then first.callback = callback end
                end
                if secondValue ~= nil then
                    second.text = tostring(secondValue)
                    second.callback = callback
                    second.color = color
                end
            else
                local text = pick(entry, "Text", "text", "Name", "name", "Title", "title")
                if text ~= nil then plain(text, callback, color) end
            end
        elseif type(entry) == "string" or type(entry) == "number" then
            plain(entry)
        end
    end
    -- Options written as a dictionary: Options = { FirstText = "Cancel", SecondText = "Delete", Callback = fn, Color = c }
    if first.text == nil and pick(list, "FirstText", "firstText") ~= nil then first.text = tostring(pick(list, "FirstText", "firstText")) end
    if second.text == nil and pick(list, "SecondText", "secondText") ~= nil then
        second.text = tostring(pick(list, "SecondText", "secondText"))
        second.callback = second.callback or asFunction(pick(list, "callback", "Callback"))
        second.color = second.color or asColor(pick(list, "Color", "color"))
    end
    -- also accept FirstText / SecondText written straight in the popup
    if first.text == nil and pick(cfg, "FirstText", "firstText") ~= nil then first.text = tostring(pick(cfg, "FirstText", "firstText")) end
    if second.text == nil and pick(cfg, "SecondText", "secondText") ~= nil then second.text = tostring(pick(cfg, "SecondText", "secondText")) end
    if first.text == nil and second.text == nil then first.text = "OK" end

    -- popup-level Callback = the main button (the second one, or the only one); OnCancel = the first button
    local mainButton = second.text ~= nil and second or first
    mainButton.callback = mainButton.callback or asFunction(pick(cfg, "callback", "Callback", "OnConfirm", "onConfirm"))
    if first.text ~= nil and mainButton ~= first then
        first.callback = first.callback or asFunction(pick(cfg, "OnCancel", "onCancel", "CancelCallback"))
    end
    -- Color: on the option, in the popup, or in the Options table itself
    local popupColor = asColor(second.color) or asColor(pick(cfg, "Color", "color", "Colour", "SecondColor", "secondColor")) or asColor(list.Color) or asColor(list.color)
    local secondColor = popupColor or theme.Accent
    if typeof(secondColor) ~= "Color3" then secondColor = Color3.fromRGB(255, 160, 16) end
    local firstText, secondText = first.text, second.text
    local firstCallback, secondCallback = first.callback, second.callback
    return {
        firstText = firstText, secondText = secondText,
        firstCallback = firstCallback, secondCallback = secondCallback,
        secondColor = secondColor, popupColor = popupColor,
    }
end

local function buildPopup(state, config, themeOverride, effectEnabled)
    local theme = getTheme(themeOverride or config.theme or (DarkyX._Window and DarkyX._Window.Theme) or DarkyX.CurrentTheme or "default")
    local lightUi = isLightTheme(theme)
    local fxEnabled = effectEnabled ~= false
    local layer = getPopupLayer()
    local buttons = readPopupButtons(config, theme)
    local firstText, secondText = buttons.firstText, buttons.secondText
    local secondColor, popupColor = buttons.secondColor, buttons.popupColor

    local function pick(tbl, ...)
        for _, key in ipairs({...}) do
            if tbl[key] ~= nil then return tbl[key] end
        end
        return nil -- ALWAYS one value: tonumber(pick(...)) / type(pick(...)) raise "missing argument" when nothing is returned
    end
    local titleText = tostring(pick(config, "title", "Title", "name", "Name") or "Popup")
    local bodyText = tostring(pick(config, "content", "Content", "description", "Description") or "")
    local cardWidth = math.max(220, tonumber((pick(config, "width", "Width"))) or 280)
    local bodyHeight = 0
    if bodyText ~= "" then
        bodyHeight = 14
        pcall(function()
            bodyHeight = game:GetService("TextService"):GetTextSize(bodyText, 10, Enum.Font.Gotham, Vector2.new(cardWidth - 36, 1000)).Y + 4
        end)
    end
    local cardHeight = 14 + 24 + 8 + bodyHeight + 18 + 32 + 16

    -- each popup that is open at the same time sits a little lower / to the right, so none hides another
    local stackIndex = 0
    for _, other in ipairs(openPopups) do if other.Open then stackIndex = stackIndex + 1 end end
    local offset = (stackIndex % 6) * 18

    local Z = 10
    local card = new("CanvasGroup", {
        Name = "Popup",
        BackgroundColor3 = theme.Panel,
        BorderSizePixel = 0,
        GroupTransparency = 1,
        Active = true, -- clicks on the card never reach what is behind it
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, offset, 0.5, offset),
        Size = UDim2.fromOffset(cardWidth, cardHeight),
        ZIndex = Z,
    }, layer)
    state.card = card
    corner(card, UDim.new(0, 14)) -- no border: the glass sheen + soft top light do the work
    if fxEnabled then
        new("UIGradient", {
            Name = "CardSheen", Rotation = 90,
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
                ColorSequenceKeypoint.new(1, lightUi and Color3.fromRGB(238, 238, 238) or Color3.fromRGB(205, 205, 205)),
            }),
        }, card)
        local light = new("Frame", {
            Name = "TopLight", BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Active = false,
            Size = UDim2.fromScale(1, 1), ZIndex = Z + 1,
        }, card)
        new("UIGradient", {
            Rotation = 90,
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, math.clamp(1 - (1 - (lightUi and 0.6 or 0.9)) * 1.1, 0, 1)),
                NumberSequenceKeypoint.new(0.65, 1),
                NumberSequenceKeypoint.new(1, 1),
            }),
        }, light)
    end
    local cardScale = addScale(card, 0.86)

    local iconName = pick(config, "icon", "Icon")
    local popupIcon = iconName ~= false and makeIcon(card, tostring(iconName or "info"), 18, theme.Text, Z + 3) or nil
    if popupIcon then popupIcon.Position = UDim2.fromOffset(18, 17) end
    new("TextLabel", {
        BackgroundTransparency = 1,
        Text = titleText,
        TextColor3 = theme.Text,
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        TextTruncate = Enum.TextTruncate.AtEnd,
        TextXAlignment = Enum.TextXAlignment.Left,
        Position = UDim2.fromOffset(popupIcon and 44 or 18, 14),
        Size = UDim2.new(1, -(popupIcon and 62 or 36), 0, 24),
        ZIndex = Z + 3,
    }, card)
    if bodyText ~= "" then
        new("TextLabel", {
            BackgroundTransparency = 1,
            Text = bodyText,
            TextColor3 = theme.Muted,
            Font = Enum.Font.Gotham,
            TextSize = 10,
            TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top,
            Position = UDim2.fromOffset(18, 46),
            Size = UDim2.new(1, -36, 0, bodyHeight),
            ZIndex = Z + 3,
        }, card)
    end

    local record = {Open = true}
    state.record = record
    table.insert(openPopups, record)
    local function closePopup()
        if not record.Open then return end
        record.Open = false
        for index = #openPopups, 1, -1 do
            if openPopups[index] == record then table.remove(openPopups, index) end
        end
        tween(card, 0.16, {GroupTransparency = 1})
        tween(cardScale, 0.16, {Scale = 0.88})
        task.delay(0.17, function()
            if card.Parent then card:Destroy() end
        end)
    end

    local boxColor = lightUi and theme.Element or Color3.fromRGB(33, 33, 36)
    local boxHover = lightUi and theme.ElementHover or Color3.fromRGB(42, 42, 46)
    local function popupButton(text, left, width, bg, hoverBg, textColor)
        local btn = new("TextButton", {
            AutoButtonColor = false,
            Text = tostring(text),
            BackgroundColor3 = bg,
            TextColor3 = textColor,
            Font = Enum.Font.GothamBold,
            TextSize = 11,
            Position = UDim2.new(left.X.Scale, left.X.Offset, 1, -48),
            Size = width,
            ZIndex = Z + 3,
        }, card)
        corner(btn, UDim.new(0, 9))
        if fxEnabled then -- same white glass look as the element boxes
            new("UIGradient", {
                Name = "ElementSheen", Rotation = 90,
                Color = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
                    ColorSequenceKeypoint.new(1, lightUi and Color3.fromRGB(240, 240, 240) or Color3.fromRGB(214, 214, 214)),
                }),
            }, btn)
            local btnLight = new("Frame", {
                Name = "TopLight", BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Active = false,
                Size = UDim2.fromScale(1, 1), ZIndex = Z + 4,
            }, btn)
            corner(btnLight, UDim.new(0, 9))
            new("UIGradient", {
                Rotation = 90,
                Transparency = NumberSequence.new({
                    NumberSequenceKeypoint.new(0, lightUi and 0.6 or 0.9),
                    NumberSequenceKeypoint.new(0.65, 1),
                    NumberSequenceKeypoint.new(1, 1),
                }),
            }, btnLight)
        end
        btn.MouseEnter:Connect(function() tween(btn, 0.14, {BackgroundColor3 = hoverBg}) end)
        btn.MouseLeave:Connect(function() tween(btn, 0.14, {BackgroundColor3 = bg}) end)
        return btn
    end

    local both = firstText ~= nil and secondText ~= nil
    local function run(callback)
        if not record.Open then return end -- a fast double click must never run the callback twice
        closePopup()
        if typeof(callback) == "function" then Security.spawn(callback) end
    end
    if firstText then
        local firstButton = popupButton(firstText, UDim2.new(0, 18, 0, 0), both and UDim2.new(0.5, -22, 0, 32) or UDim2.new(1, -36, 0, 32), boxColor, boxHover, theme.Text)
        firstButton.MouseButton1Click:Connect(function() run(buttons.firstCallback) end)
    end
    if secondText then
        -- only the second button takes the custom Color (light colours get dark text so it stays readable)
        local luminance = secondColor.R * 0.299 + secondColor.G * 0.587 + secondColor.B * 0.114
        local secondTextColor = luminance > 0.75 and Color3.fromRGB(20, 20, 24) or Color3.new(1, 1, 1)
        local secondButton = popupButton(secondText, both and UDim2.new(0.5, 4, 0, 0) or UDim2.new(0, 18, 0, 0), both and UDim2.new(0.5, -22, 0, 32) or UDim2.new(1, -36, 0, 32), secondColor, secondColor:Lerp(Color3.new(1, 1, 1), 0.18), secondTextColor)
        secondButton.MouseButton1Click:Connect(function() run(buttons.secondCallback) end)
    end

    -- smooth appear (same pop as the Delete UI Library popup), no dark layer behind
    tween(card, 0.22, {GroupTransparency = 0})
    tween(cardScale, 0.26, {Scale = 1}, Enum.EasingStyle.Back)
    task.delay(0.5, function() -- safety: whatever happened to the animation, the card ends fully visible
        if record.Open and card.Parent then
            pcall(function() card.GroupTransparency = 0 end)
            pcall(function() cardScale.Scale = 1 end)
        end
    end)

    local duration = tonumber((pick(config, "duration", "Duration")))
    if duration and duration > 0 then task.delay(duration, closePopup) end

    return {Close = closePopup, Destroy = closePopup, IsOpen = function() return record.Open end, Card = card}
end

-- Last-resort popup: only plain Instance.new + pcall'd property sets (no helpers, no gradients, no icons), so a
-- popup is ALWAYS created even if the full popup could not be built. It reads the same options.
local function buildSimplePopup(config, themeOverride)
    local theme = getTheme(themeOverride or config.theme or (DarkyX._Window and DarkyX._Window.Theme) or DarkyX.CurrentTheme or "default")
    local function make(class, props, parent)
        local object = Instance.new(class)
        for key, value in pairs(props) do pcall(function() object[key] = value end) end
        if parent then object.Parent = parent end
        return object
    end
    local function pick(tbl, ...)
        for _, key in ipairs({...}) do
            if tbl[key] ~= nil then return tbl[key] end
        end
        return nil -- ALWAYS one value: tonumber(pick(...)) / type(pick(...)) raise "missing argument" when nothing is returned
    end
    local first, second = {}, {}
    local list = (function() local v = pick(config, "options", "Options") if type(v) == "table" then return v end return {} end)()
    for _, entry in ipairs(list) do
        if type(entry) == "table" then
            local f, s2 = pick(entry, "FirstText", "firstText"), pick(entry, "SecondText", "secondText")
            local cb = pick(entry, "callback", "Callback")
            local color = pick(entry, "Color", "color")
            if f ~= nil then first.text = tostring(f) end
            if s2 ~= nil then second.text = tostring(s2); second.callback = cb; second.color = color end
            if f == nil and s2 == nil then
                local t = pick(entry, "Text", "text")
                if t ~= nil then
                    local slot = first.text == nil and first or second
                    slot.text = tostring(t); slot.callback = cb
                end
            end
        elseif type(entry) == "string" then
            local slot = first.text == nil and first or second
            slot.text = entry
        end
    end
    if first.text == nil and second.text == nil then first.text = "OK" end
    local main = second.text ~= nil and second or first
    main.callback = main.callback or pick(config, "callback", "Callback")
    local accent = second.color
    if typeof(accent) ~= "Color3" then accent = pick(config, "Color", "color") end
    if typeof(accent) ~= "Color3" then accent = list.Color end
    if typeof(accent) ~= "Color3" then accent = theme.Accent or Color3.fromRGB(255, 160, 16) end

    local gui, ownsGui = nil, false
    local okHost, host = pcall(function() return getNotifyLayer().Parent end)
    if okHost and typeof(host) == "Instance" then
        gui = host
    else
        gui, ownsGui = Security.createScreenGui(Security.randomString(14), 1002), true
    end
    local card = make("Frame", {
        Name = "Popup", BackgroundColor3 = theme.Panel or Color3.fromRGB(14, 14, 16), BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), Size = UDim2.new(0, 280, 0, 150),
        Active = true, ZIndex = 210,
    }, gui)
    make("UICorner", {CornerRadius = squareRadius(UDim.new(0, 14))}, card)
    local function label(text, y, h, size, font, color)
        make("TextLabel", {
            BackgroundTransparency = 1, Text = text, TextColor3 = color, Font = font, TextSize = size, TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
            Position = UDim2.new(0, 18, 0, y), Size = UDim2.new(1, -36, 0, h), ZIndex = 211,
        }, card)
    end
    label(tostring(pick(config, "title", "Title", "name", "Name") or "Popup"), 14, 24, 13, Enum.Font.GothamBold, theme.Text or Color3.new(1, 1, 1))
    label(tostring(pick(config, "content", "Content", "description", "Description") or ""), 46, 52, 10, Enum.Font.Gotham, theme.Muted or Color3.fromRGB(160, 160, 160))
    local open = true
    local function close()
        if not open then return end
        open = false
        pcall(function() if ownsGui then gui:Destroy() else card:Destroy() end end)
    end
    local function button(text, left, width, bg, textColor, callback)
        local b = make("TextButton", {
            AutoButtonColor = true, Text = text, BackgroundColor3 = bg, TextColor3 = textColor, Font = Enum.Font.GothamBold,
            TextSize = 11, Position = UDim2.new(0, left, 1, -48), Size = UDim2.new(0, width, 0, 32), ZIndex = 212,
        }, card)
        make("UICorner", {CornerRadius = squareRadius(UDim.new(0, 9))}, b)
        b.MouseButton1Click:Connect(function()
            if not open then return end
            close()
            Security.spawn(callback)
        end)
    end
    local both = first.text ~= nil and second.text ~= nil
    local width = both and 112 or 244
    if first.text then button(first.text, 18, width, Color3.fromRGB(28, 28, 32), theme.Text or Color3.new(1, 1, 1), first.callback) end
    if second.text then button(second.text, both and 150 or 18, width, accent, Color3.new(1, 1, 1), second.callback) end
    return {Close = close, Destroy = close, IsOpen = function() return open end, Card = card}
end

function DarkyX:CreatePopup(config, themeOverride, effectEnabled, ...)
    if type(self) == "table" and self ~= DarkyX and config == nil then
        config, self = self, DarkyX -- called with a dot: DarkyX.CreatePopup({...})
    end
    if type(config) == "string" then -- DarkyX:CreatePopup("Title", "Content")
        config = {title = config, content = type(themeOverride) == "string" and themeOverride or nil}
        themeOverride = nil
    end
    if type(config) ~= "table" then
        Security.log("[DarkyX] CreatePopup needs a table: window:CreatePopup({ title = ..., content = ..., Options = {...} })")
        return nil
    end
    config = ci(config)

    local state = {}
    local ok, result = xpcall(buildPopup, debug.traceback, state, config, themeOverride, effectEnabled)
    if ok and result then return result end

    -- the full popup failed: clean up what was half built, say why, and show the simple popup instead
    DarkyX.LastPopupError = tostring(result)
    Security.log("[DarkyX] CreatePopup (full) failed, showing the simple popup instead. Cause:\n" .. tostring(result))
    if state.record then
        state.record.Open = false
        for index = #openPopups, 1, -1 do
            if openPopups[index] == state.record then table.remove(openPopups, index) end
        end
    end
    if state.card then pcall(function() state.card:Destroy() end) end
    local ok2, result2 = xpcall(buildSimplePopup, debug.traceback, config, themeOverride)
    if ok2 and result2 then return result2 end
    Security.log("[DarkyX] CreatePopup failed:\n" .. tostring(result2))
    return nil
end
DarkyX.Popup = DarkyX.CreatePopup

-- =====================================================================
-- DOWNLOADER  (Dropdown:Download)
-- Saves instances (folders, Workspace, models, parts, services, the whole game...) to files in the
-- executor's workspace folder. It only uses what the executor itself provides (saveinstance / writefile):
-- if saveinstance is missing it falls back to a hierarchy text file (tree). Use it on places and models
-- you own or have permission to copy.
-- =====================================================================
do
    local Downloader = {}
    DarkyX._Downloader = Downloader

    local DEFAULT_FOLDER = "DarkyX/Downloads"

    local function trim(text)
        return (tostring(text):gsub("^%s+", ""):gsub("%s+$", ""))
    end
    -- file names: letters, digits, - _ . and spaces only (no slashes, no "..")
    local function safeName(text)
        local name = trim(text)
        name = name:gsub("[^%w%-_%. ]", "_")
        name = name:gsub("%s+", "_")
        name = name:gsub("^%.+", "")
        name = string.sub(name, 1, 80)
        if name == "" then name = "Download" end
        return name
    end
    -- folder: "A/B/C" - never absolute, never ".."
    local function safeFolder(path)
        path = trim(path or DEFAULT_FOLDER)
        path = path:gsub("\\", "/")
        local parts = {}
        for segment in string.gmatch(path, "[^/]+") do
            if segment ~= "." and segment ~= ".." then table.insert(parts, safeName(segment)) end
        end
        if #parts == 0 then return DEFAULT_FOLDER end
        return table.concat(parts, "/")
    end
    local function ensureFolder(path)
        if type(makefolder) ~= "function" or type(isfolder) ~= "function" then return false end
        local built = ""
        for segment in string.gmatch(path, "[^/]+") do
            built = built == "" and segment or (built .. "/" .. segment)
            local ok, exists = pcall(isfolder, built)
            if ok and not exists then pcall(makefolder, built) end
        end
        local ok, exists = pcall(isfolder, path)
        return ok and exists == true
    end
    local function fileExists(path)
        if type(isfile) ~= "function" then return nil end
        local ok, exists = pcall(isfile, path)
        if ok then return exists == true end
        return nil
    end
    local function joinPath(folder, file)
        return folder and (folder .. "/" .. file) or file
    end
    local function uniquePath(folder, base, ext, overwrite)
        local path = joinPath(folder, base .. "." .. ext)
        if overwrite or fileExists(path) ~= true then return path end
        for index = 2, 999 do
            path = joinPath(folder, string.format("%s_%d.%s", base, index, ext))
            if fileExists(path) ~= true then return path end
        end
        return path
    end

    local function getSaver()
        if type(saveinstance) == "function" then return saveinstance end
        if type(syn) == "table" and type(syn.saveinstance) == "function" then return syn.saveinstance end
        return nil
    end
    function Downloader.Support()
        return {SaveInstance = getSaver() ~= nil, WriteFile = type(writefile) == "function"}
    end

    -- Instance | "Workspace.Map.Building" | "ReplicatedStorage" | "game" | "PartName" | {Instance = inst, Name = "..."}
    function Downloader.Resolve(raw)
        if typeof(raw) == "Instance" then return raw end
        if type(raw) == "table" then
            local inner = raw.Instance or raw.Object or raw.Value or raw.Path
            if inner ~= nil and inner ~= raw then return Downloader.Resolve(inner) end
            return nil, "that option has no Instance"
        end
        if type(raw) == "string" then
            local text = trim(raw)
            if text == "" then return nil, "empty path" end
            local parts = {}
            for part in string.gmatch(text, "[^%.]+") do table.insert(parts, part) end
            if #parts == 0 then return nil, "empty path" end
            local first = string.lower(parts[1])
            local current
            if first == "game" then
                current = game
            elseif first == "workspace" then
                current = workspace
            else
                local okService, service = pcall(game.GetService, game, parts[1])
                current = (okService and service) or game:FindFirstChild(parts[1])
            end
            for index = 2, #parts do
                if not current then break end
                current = current:FindFirstChild(parts[index])
            end
            if not current and #parts == 1 then
                local okFind, found = pcall(game.FindFirstChild, game, text, true) -- a model / part by name anywhere
                if okFind then current = found end
            end
            if current then return current end
            return nil, "'" .. text .. "' was not found"
        end
        return nil, "unsupported target"
    end
    local function describe(raw)
        if typeof(raw) == "Instance" then
            local ok, name = pcall(raw.GetFullName, raw)
            return ok and name or raw.Name
        end
        if type(raw) == "table" then return tostring(raw.Name or raw.Text or raw.Label or "option") end
        return tostring(raw)
    end

    local function extensionFor(inst, format)
        format = format and string.lower(tostring(format)) or nil
        if format == "tree" or format == "txt" then return "txt" end
        if format == "rbxl" or format == "rbxlx" or format == "rbxm" or format == "rbxmx" then return format end
        if inst == game then return "rbxl" end
        return "rbxmx"
    end

    -- fallback: a text file with the whole hierarchy (class + name, indented)
    local function buildTree(root, config)
        local lines = {}
        local limit = tonumber(config.MaxInstances) or 50000
        local maxDepth = tonumber(config.MaxDepth)
        local count = 0
        local function walk(inst, depth)
            if count >= limit then return end
            count += 1
            table.insert(lines, string.rep("  ", depth) .. inst.ClassName .. " " .. inst.Name)
            if count % 400 == 0 then task.wait() end
            if maxDepth and depth >= maxDepth then return end
            for _, child in ipairs(inst:GetChildren()) do walk(child, depth + 1) end
        end
        walk(root, 0)
        if count >= limit then table.insert(lines, "-- stopped after " .. limit .. " instances (raise MaxInstances for more)") end
        return table.concat(lines, "\n")
    end
    local function writeTree(inst, path, config)
        if type(writefile) ~= "function" then return false, "writefile is not supported by this executor" end
        local okTree, text = pcall(buildTree, inst, config)
        if not okTree then return false, tostring(text) end
        local okWrite, err = pcall(writefile, path, text)
        if okWrite then return true end
        return false, tostring(err)
    end

    -- returns ok, method-or-error, finalPath
    local function saveOne(inst, path, ext, config)
        if ext == "txt" then
            local ok, err = writeTree(inst, path, config)
            return ok, ok and "tree" or err, path
        end
        local saver = getSaver()
        if not saver then
            if config.Fallback ~= false then
                local textPath = (string.gsub(path, "%.%w+$", "")) .. ".txt"
                local ok, err = writeTree(inst, textPath, config)
                if ok then return true, "tree", textPath end
                return false, "saveinstance is not supported by this executor (" .. tostring(err) .. ")", path
            end
            return false, "saveinstance is not supported by this executor", path
        end
        local decompile = config.Decompile == true
        local options = {
            FileName = path,
            Binary = (ext == "rbxl" or ext == "rbxm"),
            noscripts = not decompile, -- executors ignore the keys they do not know; extra keys: config.Options
            DecompileScripts = decompile,
            Decompile = decompile,
            mode = config.Mode,
        }
        if inst ~= game then options.Object = inst end
        if type(config.Options) == "table" then
            for key, value in pairs(config.Options) do options[key] = value end
        end
        local ok, err = pcall(saver, options)            -- saveinstance({Object = ..., FileName = ...})
        if ok then return true, "saveinstance", path end
        local okLegacy = pcall(saver, inst, path, options) -- older executors: saveinstance(Object, FileName, Options)
        if okLegacy then return true, "saveinstance", path end
        return false, tostring(err), path
    end

    -- Start(owner, config, rawTargets, helpers) -> job
    --   helpers.Notify(title, content, icon)   helpers.Spawn(fn, ...)
    -- job: .Status ("running" | "done" | "cancelled"), .Results, .Total, .Succeeded, .Failed, .Folder
    --      job:Wait() -> results      job:Cancel()
    function Downloader.Start(owner, config, rawTargets, helpers)
        if owner._DownloadJob and owner._DownloadJob.Status == "running" then
            if config.Notify ~= false then helpers.Notify("Download", "A download is already running.", "download") end
            return owner._DownloadJob
        end
        local job = {Status = "running", Results = {}, Total = #rawTargets, Succeeded = 0, Failed = 0, Cancelled = false}
        function job:Cancel() self.Cancelled = true end
        function job:Wait()
            while self.Status == "running" do task.wait(0.1) end
            return self.Results
        end
        owner._DownloadJob = job

        local function fail(name, why)
            job.Failed += 1
            table.insert(job.Results, {Name = name, Ok = false, Error = why})
        end

        task.spawn(function()
            local body = function()
                if #rawTargets == 0 then
                    job.Total = 1
                    fail("Nothing selected", "select something in the dropdown first (or pass Targets / All = true)")
                    return
                end
                local resolved = {}
                for _, raw in ipairs(rawTargets) do
                    local inst, why = Downloader.Resolve(raw)
                    if inst then table.insert(resolved, inst) else fail(describe(raw), why or "not found") end
                end
                if #resolved == 0 then return end

                local folder = safeFolder(config.Folder)
                if not ensureFolder(folder) then folder = nil end -- no makefolder: save next to the workspace root
                job.Folder = folder
                if config.Notify ~= false then
                    helpers.Notify("Downloading", #resolved == 1 and ("Saving " .. describe(resolved[1]) .. "...") or ("Saving " .. #resolved .. " items..."), "download")
                end

                for index, inst in ipairs(resolved) do
                    if job.Cancelled then break end
                    local name = inst == game and (game.Name ~= "" and game.Name or "Place") or inst.Name
                    if type(config.OnProgress) == "function" then pcall(config.OnProgress, index, #resolved, name) end
                    local ext = extensionFor(inst, config.Format)
                    local base
                    if config.FileName then
                        base = safeName(config.FileName)
                        if #resolved > 1 then base = base .. "_" .. index end
                    else
                        base = safeName(name)
                        if config.Timestamp ~= false then base = base .. "_" .. os.date("%Y%m%d_%H%M%S") end
                    end
                    local path = uniquePath(folder, base, ext, config.Overwrite == true)
                    local result = {Name = name, Instance = inst, Path = path, Format = ext}
                    local ok, how, finalPath = saveOne(inst, path, ext, config)
                    result.Ok = ok
                    if ok then
                        result.Method = how
                        result.Path = finalPath or path
                        if fileExists(result.Path) == false then
                            result.Warning = "no file found at that path (the executor may have saved it elsewhere)"
                        end
                        job.Succeeded += 1
                    else
                        result.Error = how
                        job.Failed += 1
                    end
                    table.insert(job.Results, result)
                    task.wait()
                end
            end
            local ok, err = pcall(body)
            if not ok then fail("Download", tostring(err)) end

            job.Status = job.Cancelled and "cancelled" or "done"
            if config.Notify ~= false then
                if job.Succeeded > 0 and job.Failed == 0 then
                    helpers.Notify("Download finished", job.Succeeded .. " saved to " .. (job.Folder or "the workspace folder"), "check")
                elseif job.Succeeded > 0 then
                    helpers.Notify("Download finished", job.Succeeded .. " saved, " .. job.Failed .. " failed", "download")
                else
                    local first = job.Results[1]
                    helpers.Notify("Download failed", first and first.Error or "nothing was saved", "x")
                end
            end
            local callback = config.OnDone or config.Callback
            if type(callback) == "function" then helpers.Spawn(callback, job.Results, job) end
        end)
        return job
    end
end

local function createWindowImpl(self, config)
    config = config or {}
    -- every input event of this window is tracked here and released again when the window is destroyed
    local UserInputService = Security.trackInput(UserInputService)
    local theme = getTheme(config.theme or "Default")
    -- Animations are ALWAYS on and automatic (the interface expands out of the floating button, the intro, the page slide,
    -- the tab light). There is no Animation option any more.
    -- LoadingTitle = true (default): the big title + icon plays first.
    -- LoadingTitle = false         : no LoadingTitle at all, the interface opens right away (faster).
    -- LoadingTitle = "My Hub"      : plays the LoadingTitle with your own text.
    -- (read right after the window table is created, see below)
    -- LoaderAPI = { {Title=, URL=}, ... } turns the window into the small script loader (see "LOADER MODE" at the end of this
    -- function). The loader never uses the sidebar layout. Remove LoaderAPI and the window is the normal one again.
    local hasLoaderAPI = type(config.LoaderAPI) == "table" and next(config.LoaderAPI) ~= nil
    local sidebarLayout = config.sidebarLayout == true and not hasLoaderAPI
    local SIDE_SCALE = 0.36 -- sidebarLayout = true: the sidebar is UDim2.new(0.36, 0, 1, 0) of the page area
    -- Auto: profile + username only exist when sidebarLayout = true (shown underneath the tab menu).
    -- When sidebarLayout = false they are automatically hidden (not created), so nothing can error.
    local showUserProfile = sidebarLayout
    local showUsername = sidebarLayout
    -- Default window size is 550 x 340 and the default scale is 1. Set your own start values in CreateWindow:
    --     Size    = UDim2.fromOffset(600, 250),   -- (also accepts Vector2, {600, 250} or "600x250")
    --     UIScale = "0.7",                        -- (a number or a string, 0.4 - 2.0)
    -- The player can still change both in the Save Manager card in Settings (typed inputs, saved automatically; the Load button brings them back),
    -- and the code can change them any time with Window:SetSize(width, height) / Window:SetScale(scale).
    -- (config.width / config.height are ignored on purpose.)
    local windowWidth = 550
    local windowHeight = 340
    if config.width ~= nil or config.height ~= nil then
        Security.log("[DarkyX] config.width / config.height are ignored. Use Window:SetSize(width, height) instead.")
    end
    local isDefaultTheme = type(config.theme) ~= "table" and string.lower(tostring(config.theme or "default")) == "default"
    local successColor = isDefaultTheme and theme.Success or theme.Accent -- check color: green on Default, theme accent otherwise
    -- Card look: very dark neutral surface, big soft corners, one subtle stroke, faint top light.
    local lightUi = isLightTheme(theme)
    local elementBox = lightUi and theme.Element or Color3.fromRGB(33, 33, 36)
    local elementBoxHover = lightUi and theme.ElementHover or Color3.fromRGB(42, 42, 46)
    local _, greyBorder = neutralGrey(theme)
    local elementBorder = lightUi and greyBorder or Color3.fromRGB(66, 66, 72)
    local elementBorderTransparency = 0.05
    local elementStrokeThickness = 1

    -- light soft white effect: a soft white light that falls from the top edge (used by boxes and the window)
    -- surface = true: a light of the window / settings page / popup card itself (removed when Effect is off)
    -- surface = nil : a light of an element box (only turned down to a low level when Effect is off)
    local function addTopLight(object, radius, zIndex, strength, surface)
        local light = new("Frame", {
            Name = "TopLight", BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Active = false,
            Size = UDim2.fromScale(1, 1), ZIndex = zIndex or 1,
        }, object)
        if surface then light:SetAttribute("FxSurface", true) end
        corner(light, radius)
        local base = lightUi and 0.68 or 0.935 -- SOFT: a gentler light than before
        base = math.clamp(1 - (1 - base) * (strength or 1), 0, 1)
        new("UIGradient", {
            Rotation = 90,
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, base),
                NumberSequenceKeypoint.new(0.4, 1 - (1 - base) * 0.45),
                NumberSequenceKeypoint.new(0.85, 1),
                NumberSequenceKeypoint.new(1, 1),
            }),
        }, light)
        return light
    end

    local function styleElementBox(object, radius)
        local boxRadius = UDim.new(0, math.max(radius or 11, 14))
        corner(object, boxRadius)
        -- (no border) light soft white effect instead: glass sheen + soft top light
        addTopLight(object, boxRadius, object.ZIndex, 1)
        -- small grey border (UIStroke) on every box
        stroke(object, lightUi and Color3.fromRGB(208, 210, 217) or Color3.fromRGB(72, 72, 78), 0.1, 1)
        new("UIGradient", {
            Name = "ElementSheen",
            Rotation = 90,
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
                ColorSequenceKeypoint.new(1, lightUi and Color3.fromRGB(245, 245, 245) or Color3.fromRGB(228, 228, 228)),
            }),
        }, object)
    end

    -- protected container + random name; `pending` lets CreateWindow clean up if the build ever fails half way
    local screenGui = Security.createScreenGui(Security.randomString(14), 999)
    Security.pending = screenGui

    -- ---------------------------------------------------------------
    -- LIGHT SOFT WHITE EFFECT   (CreateWindow({ Effect = true }) is the switch; YOU decide, nothing is automatic)
    --   Effect = true  (default): everything looks exactly as designed.
    --   Effect = false : the window, settings page, popups, the shine sweeps and the knob glows lose the light soft white
    --                    effect. Element boxes keep only a LOW version of it, so they never look flat.
    --   Slow mode (Settings > Slow mode, or Window:SetSlowMode(true)) is a manual switch on top of it: it lowers the effect
    --   and shortens every animation for a slow device. It never turns itself on, and with Effect = false it keeps the
    --   effect off when you switch Slow mode off again.
    -- Every light layer is registered here the moment it is created (DescendantAdded), so every element (also the ones
    -- added later) follows instantly, and fx.SetEnabled switches all existing ones.
    -- ---------------------------------------------------------------
    local fx = {Enabled = true, Allowed = true, Gradients = setmetatable({}, {__mode = "k"}), Original = setmetatable({}, {__mode = "k"})}
    do
        local flag = config.Effect
        if flag == nil then flag = config.effect end
        if flag == false then
            fx.Allowed = false
            fx.Enabled = false
        end

        local LOW = 0.20 -- strength kept by element boxes while Effect = false (0 = none, 1 = full)
        local SURFACE_SHEENS = {WindowSheen = true, SettingsSheen = true, CardSheen = true}

        local function lowTransparency(sequence)
            local points = {}
            for index, key in ipairs(sequence.Keypoints) do
                points[index] = NumberSequenceKeypoint.new(key.Time, math.clamp(1 - (1 - key.Value) * LOW, 0, 1))
            end
            return NumberSequence.new(points)
        end
        local function lowColor(sequence)
            local points = {}
            for index, key in ipairs(sequence.Keypoints) do
                points[index] = ColorSequenceKeypoint.new(key.Time, key.Value:Lerp(Color3.new(1, 1, 1), 1 - LOW))
            end
            return ColorSequence.new(points)
        end

        function fx.apply(gradient)
            local kind = fx.Gradients[gradient]
            local parent = gradient.Parent
            if not kind or not parent then return end
            local original = fx.Original[gradient]
            if kind == "surfaceSheen" then
                gradient.Enabled = fx.Enabled
            elseif kind == "surfaceLight" or kind == "shine" then
                parent.Visible = fx.Enabled
            elseif kind == "boxSheen" then
                gradient.Color = fx.Enabled and original or lowColor(original)
            elseif kind == "boxLight" then
                gradient.Transparency = fx.Enabled and original or lowTransparency(original)
            end
        end

        function fx.register(instance)
            if not instance:IsA("UIGradient") then return end
            local parent = instance.Parent
            if not parent then return end
            local kind
            if SURFACE_SHEENS[instance.Name] then
                kind = "surfaceSheen"
            elseif instance.Name == "ElementSheen" then
                kind = "boxSheen"
                fx.Original[instance] = instance.Color
            elseif parent.Name == "TopLight" then
                if parent:GetAttribute("FxSurface") then
                    kind = "surfaceLight"
                else
                    kind = "boxLight"
                    fx.Original[instance] = instance.Transparency
                end
            elseif parent.Name == "Shine" then
                kind = "shine"
            end
            if kind then
                fx.Gradients[instance] = kind
                fx.apply(instance)
            end
        end

        screenGui.DescendantAdded:Connect(function(instance)
            pcall(fx.register, instance)
        end)

        -- switch the whole effect on / off (Slow mode): every registered gradient and every knob follows at once
        function fx.SetEnabled(value)
            fx.Enabled = value == true
            for gradientObject in pairs(fx.Gradients) do
                pcall(fx.apply, gradientObject)
            end
            for controllerObject in pairs(knobRegistry) do
                pcall(controllerObject.Resync)
            end
        end
    end

    local window = {
        ScreenGui = screenGui,
        Theme = theme,
        Tabs = {},
        Sidebar = sidebarLayout,
        Destroyed = false,
        Visible = true,
        _StateEntries = {},
        _SearchItems = {},
        _Loaded = false,
        _Held = false,
        _Keybind = config.keybind or Enum.KeyCode.RightControl,
    }
    window._Input = UserInputService
    window._Guard = Security.guard(screenGui, window)

    -- Skipmode = true : skips ONLY the LoadingTitle (the big title that plays first). Everything else stays as it is:
    --                   the intro / open / close animations and the light effect are ALWAYS on automatically
    --                   (Animation = true, Effect = true are the defaults; Effect = false is the only way to turn it off).
    window._Skip = config.Skipmode == true
    -- HeaderTopbar = true : the top bar becomes a floating header card with the logo (Image), the title and button-style controls
    window._HeaderTopbar = config.HeaderTopbar == true

    -- GEN 2 BUTTON LOOK (the "Scan QR" screenshot): dark glass fill, soft top light, light border, small corner.
    -- window._StyleButton(object [, radius]) styles any GuiButton / Frame and returns its border (UIStroke).
    window._StyleButton = function(object, radius)
        radius = radius or UDim.new(0, CORNER_MEDIUM)
        corner(object, radius)
        addTopLight(object, radius, object.ZIndex, 0.9)
        local line = stroke(object, lightUi and Color3.fromRGB(208, 210, 217) or Color3.fromRGB(84, 84, 90), 0.05, 1)
        new("UIGradient", {
            Name = "ElementSheen", Rotation = 90,
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
                ColorSequenceKeypoint.new(1, lightUi and Color3.fromRGB(240, 240, 240) or Color3.fromRGB(205, 205, 205)),
            }),
        }, object)
        return line
    end

    -- The LoadingTitle plays only ONCE. If the key system already played it (key system runs before
    -- CreateWindow), the window skips its own LoadingTitle and opens right after the key is accepted.
    do
        local flag = config.LoadingTitle
        if flag == nil then flag = config.loadingTitle end
        window._LoadingTitleOff = flag == false or window._Skip == true
        window._LoadingTitleText = (type(flag) == "string" and flag ~= "") and flag or "DarkyX"
    end
    local loadingAlreadyPlayed = DarkyX._LoadingTitlePlayed == true
    DarkyX._LoadingTitlePlayed = false -- consumed: a later, separate window may play it again

    local loaderTitle, loaderIcon, loaderScale
    if not loadingAlreadyPlayed and not window._LoadingTitleOff then
        loaderTitle = new("TextLabel", {
            Name = "LoadingTitle",
            BackgroundTransparency = 1,
            Text = window._LoadingTitleText,
            TextColor3 = theme.Text,
            TextTransparency = 1,
            Font = Enum.Font.GothamBlack,
            TextSize = 74,
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(520, 90),
            ZIndex = 200,
        }, screenGui)
        local loadingIconValue = config.LoadingIcon
        if loadingIconValue == nil then loadingIconValue = config.loadingIcon end -- (false hides the icon)
        loaderIcon = addLoadingIcon(loaderTitle, loadingIconValue)
        addLoadingDarkFade(loaderTitle, loaderIcon)
        loaderScale = addScale(loaderTitle, 0.76)
        tween(loaderTitle, 0.38, {TextTransparency = 0})
        if loaderIcon then tween(loaderIcon, 0.38, {ImageTransparency = 0}) end
        tween(loaderScale, 0.48, {Scale = 1}, Enum.EasingStyle.Back)
    end

    local main = new("Frame", {
        Name = "Main",
        BackgroundColor3 = theme.Background,
        Size = UDim2.fromOffset(windowWidth, windowHeight),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        ZIndex = 5,
        Visible = false,
    }, screenGui)
    corner(main, WINDOW_RADIUS)
    -- small grey border (UIStroke) around the whole window
    stroke(main, lightUi and Color3.fromRGB(206, 208, 215) or Color3.fromRGB(44, 44, 50), 0.05, 1)
    addScale(main, 0.95)
    -- ---------------------------------------------------------------
    -- BACKGROUND IMAGE
    --   CreateWindow({ Background = "rbxassetid://123456", BackgroundTransparency = 0.5 })
    --   Not used (nil / false / "rbxassetid://0"): no image is created and the UI works exactly as before.
    --   Window:SetBackground("rbxassetid://...", 0.5)  /  Window:SetBackground(nil)  /  Window:SetBackgroundTransparency(0.7)
    -- The image sits behind every element (inside the rounded window), under the light soft white effect.
    -- ---------------------------------------------------------------
    do
        local function isBlank(value)
            if value == nil or value == false then return true end
            local text = string.lower((tostring(value):gsub("%s", "")))
            return text == "" or text == "0" or text == "rbxassetid://0" or text == "rbxassetid:0"
        end
        local backgroundIsIcon = false
        local function toAsset(value)
            backgroundIsIcon = false
            if type(value) == "number" then return "rbxassetid://" .. tostring(math.floor(value)) end
            local text = (tostring(value):gsub("^%s+", ""):gsub("%s+$", ""))
            if string.match(text, "^%d+$") then return "rbxassetid://" .. text end
            if not (text:match("^rbxasset") or text:match("^https?://") or text:match("^rbxthumb")) then
                -- Background = "house": an icon name becomes a soft tiled pattern of that icon
                local iconAsset = resolveIcon(text)
                if iconAsset then backgroundIsIcon = true; return iconAsset end
            end
            return text
        end
        local image
        local wanted = 0.5 -- image transparency (0 = fully visible, 1 = hidden)
        local function applyBackground(value, transparency, animate)
            if transparency ~= nil then wanted = math.clamp(tonumber(transparency) or wanted, 0, 1) end
            if isBlank(value) then
                if image then image:Destroy(); image = nil end
                window.Background = nil
                return false
            end
            if not image then
                image = new("ImageLabel", {
                    Name = "BackgroundImage", BackgroundTransparency = 1, BorderSizePixel = 0, Active = false,
                    ScaleType = Enum.ScaleType.Crop, ImageColor3 = Color3.fromRGB(185, 185, 185), -- a little dimmed: text stays readable
                    ImageTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 5,
                }, main)
                corner(image, WINDOW_RADIUS)
            end
            image.Image = toAsset(value)
            if backgroundIsIcon then
                image.ScaleType = Enum.ScaleType.Tile
                image.TileSize = UDim2.fromOffset(52, 52)
            else
                image.ScaleType = Enum.ScaleType.Crop
            end
            window.Background = image.Image
            if animate then
                tween(image, 0.5, {ImageTransparency = wanted})
            else
                image.ImageTransparency = wanted
            end
            return true
        end
        function window._ApplyBackground(value, transparency, animate) return applyBackground(value, transparency, animate) end
        function window._SetBackgroundTransparency(value)
            wanted = math.clamp(tonumber(value) or wanted, 0, 1)
            if image then
                tween(image, 0.3, {ImageTransparency = wanted})
            end
            return wanted
        end
        local initial = config.Background
        if initial == nil then initial = config.background end
        if initial == nil then initial = config.BackgroundImage end
        local initialAlpha = config.BackgroundTransparency
        if initialAlpha == nil then initialAlpha = config.backgroundTransparency end
        applyBackground(initial, initialAlpha, false)
    end
    -- (no border) light soft white effect for the window: soft white gradient on the surface + a light from the top edge
    new("UIGradient", {
        Name = "WindowSheen",
        Rotation = 90,
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
            ColorSequenceKeypoint.new(1, isLightTheme(theme) and Color3.fromRGB(238, 238, 238) or Color3.fromRGB(205, 205, 205)),
        }),
    }, main)
    local mainTopLight = new("Frame", {
        Name = "TopLight", BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Active = false,
        Size = UDim2.fromScale(1, 1), ZIndex = 6,
    }, main)
    mainTopLight:SetAttribute("FxSurface", true)
    corner(mainTopLight, WINDOW_RADIUS)
    new("UIGradient", {
        Rotation = 90,
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, isLightTheme(theme) and 0.62 or 0.92),
            NumberSequenceKeypoint.new(0.55, 1),
            NumberSequenceKeypoint.new(1, 1),
        }),
    }, mainTopLight)

    local topBar = new("Frame", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 58),
        ZIndex = 10,
    }, main)
    makeDrag(topBar, main)

    -- DragBar: floating pill below the window. Hold + drag it to move the UI (top bar dragging still works).
    local dragHandle = new("TextButton", {
        Name = "DragBar",
        AutoButtonColor = false,
        BackgroundTransparency = 1,
        Text = "",
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 1, 6),
        Size = UDim2.fromOffset(160, 24),
        ZIndex = 30,
    }, main)
    local dragPill = new("Frame", {
        Name = "Pill",
        BackgroundColor3 = Color3.new(1, 1, 1),
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(96, 5),
        ZIndex = 31,
    }, dragHandle)
    corner(dragPill, UDim.new(1, 0))
    local dragHeld = false
    local function dragVisual(held)
        dragHeld = held
        tween(dragPill, 0.16, {
            BackgroundTransparency = held and 0.3 or 0,
            Size = held and UDim2.fromOffset(116, 6) or UDim2.fromOffset(96, 5),
        }, Enum.EasingStyle.Quint)
    end
    dragHandle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragVisual(true)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if dragHeld and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
            dragVisual(false)
        end
    end)
    makeDrag(dragHandle, main)

    local titleWrap = new("Frame", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(14, 8),
        Size = UDim2.fromOffset(305, 42),
        ZIndex = 11,
    }, topBar)
    -- Window image is intentionally not shown here.
    -- config.Image is reserved for the FloatingButton logo.
    local titleLeft = 0 -- the title wrapper itself sits at x = 14 (no logo) or x = 54 (next to the header logo)
    if window._HeaderTopbar then
        -- header topper: the SAME width as the UI library (edge to edge). Only its top follows the window's rounded corners.
        local headerColor = lightUi and theme.Panel or Color3.fromRGB(21, 21, 24)
        local headerCard = new("Frame", {
            Name = "HeaderCard", BackgroundColor3 = headerColor, BorderSizePixel = 0,
            Position = UDim2.fromOffset(0, 0), Size = UDim2.new(1, 0, 0, 58), ZIndex = 9,
        }, topBar)
        corner(headerCard, WINDOW_RADIUS)
        new("Frame", { -- squares off the lower corners of the header
            Name = "HeaderFill", BackgroundColor3 = headerColor, BorderSizePixel = 0,
            Position = UDim2.new(0, 0, 1, -(CORNER_LARGE + 1)), Size = UDim2.new(1, 0, 0, CORNER_LARGE + 1), ZIndex = 9,
        }, headerCard)
        local headerLine = new("Frame", { -- thin divider under the header
            Name = "HeaderLine", BackgroundColor3 = lightUi and Color3.fromRGB(190, 194, 204) or Color3.fromRGB(60, 60, 66),
            BorderSizePixel = 0, Position = UDim2.new(0, 0, 1, -1), Size = UDim2.new(1, 0, 0, 1), ZIndex = 10,
        }, headerCard)
        new("UIGradient", {
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.12, 0.35),
                NumberSequenceKeypoint.new(0.88, 0.35), NumberSequenceKeypoint.new(1, 1),
            }),
        }, headerLine)
        -- NEW logo: config.Image (lucide name, asset id or rbxassetid://) in a small button-style badge
        local badge = new("Frame", {
            Name = "Logo", BackgroundColor3 = elementBox, BorderSizePixel = 0,
            Position = UDim2.fromOffset(14, 13), Size = UDim2.fromOffset(30, 30), ZIndex = 12,
        }, topBar)
        window._StyleButton(badge)
        local logoValue = config.Image
        if isBlankAsset(logoValue) then logoValue = config.Icon end
        local logo = (not isBlankAsset(logoValue)) and makeIcon(badge, logoValue, 18, Color3.new(1, 1, 1), 14) or nil
        if logo then
            logo.AnchorPoint = Vector2.new(0.5, 0.5)
            logo.Position = UDim2.fromScale(0.5, 0.5)
        else
            new("TextLabel", {
                BackgroundTransparency = 1, Text = string.upper(string.sub(tostring(config.name or "D"), 1, 1)),
                TextColor3 = theme.Text, Font = Enum.Font.GothamBold, TextSize = 15,
                Size = UDim2.fromScale(1, 1), ZIndex = 14,
            }, badge)
        end
        titleWrap.Position = UDim2.fromOffset(54, 8)
    end
    -- the title shrinks with the window and never runs into the search bar / buttons on the right (306 px reserved)
    titleWrap.Size = UDim2.new(1, -(titleWrap.Position.X.Offset + 306), 0, 42)
    local titleLabel = new("TextLabel", {
        BackgroundTransparency = 1,
        Text = tostring(config.name or "DarkyX Hub"),
        TextColor3 = theme.Text,
        Font = Enum.Font.GothamBold,
        TextTruncate = Enum.TextTruncate.AtEnd,
        TextSize = 17,
        TextXAlignment = Enum.TextXAlignment.Left,
        Position = UDim2.fromOffset(titleLeft, 0),
        Size = UDim2.new(1, -titleLeft, 0, 24),
        ZIndex = 11,
    }, titleWrap)
    new("TextLabel", {
        BackgroundTransparency = 1,
        Text = tostring(config.subtitle or "DarkyX"),
        TextColor3 = theme.Muted,
        Font = Enum.Font.Gotham,
        TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Left,
        Position = UDim2.fromOffset(titleLeft, 22),
        Size = UDim2.new(1, -titleLeft, 0, 17),
        ZIndex = 11,
    }, titleWrap)

    local controls = new("Frame", {
        BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(1, 0),
        Position = window._HeaderTopbar and UDim2.new(1, -16, 0, 13) or UDim2.new(1, -11, 0, 10),
        Size = UDim2.fromOffset(142, 30),
        ZIndex = 15,
    }, topBar)
    new("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder, -- fixed order: buttons can never swap places (minimize <-> close)
        Padding = UDim.new(0, 5),
    }, controls)

    local function makeControl(icon, tint, tooltip, draw, fallback, iconSize)
        local drawSize = iconSize or 16 -- size of icons drawn in code
        iconSize = iconSize or 15 -- pack icons; the button itself is 29 px
        local controlOrder = #controls:GetChildren() -- the layout is child #1, so buttons get 1, 2, 3, 4 in creation order
        local b = new("TextButton", {
            Name = "Control" .. controlOrder,
            LayoutOrder = controlOrder,
            AutoButtonColor = false,
            BackgroundTransparency = 1,
            Text = "",
            Size = UDim2.fromOffset(29, 29),
            ZIndex = 16,
        }, controls)
        if window._HeaderTopbar then -- button-style square controls (same look as every button)
            b.BackgroundTransparency = 0
            b.BackgroundColor3 = elementBox
            window._StyleButton(b)
        end
        local i, setTint
        if draw then
            local drawn, drawnIcon, drawnTint = pcall(draw, b, drawSize, tint or theme.Muted, 18)
            if drawn then
                i, setTint = drawnIcon, drawnTint
            else
                warn("[DarkyX] icon could not be drawn: " .. tostring(drawnIcon))
            end
        else
            i = makeIcon(b, icon, iconSize, tint or theme.Muted, 18)
            if i then
                i.AnchorPoint = Vector2.new(0.5, 0.5)
                i.Position = UDim2.fromScale(0.5, 0.5)
                setTint = function(c) tween(i, 0.16, {ImageColor3 = c}) end
            end
        end
        -- icon pack missing (download failed): draw the icon in code so the button is never empty
        if not i and fallback then
            i, setTint = fallback(b, math.max(iconSize, 16), tint or theme.Muted, 18)
        end
        b.MouseEnter:Connect(function()
            if setTint then setTint(tint or theme.Text) end
        end)
        b.MouseLeave:Connect(function()
            if setTint then setTint(tint or theme.Muted) end
        end)
        return b, i, setTint
    end

    local searchButton, searchButtonIcon, setSearchTint = makeControl("search", theme.Muted, nil, drawMagnifier)
    local settingsButton, settingsButtonIcon, setSettingsTint = makeControl("settings", theme.Muted, nil, drawSettings, nil, 20) -- NEW sliders icon, drawn in code, 20 px
    -- (the new sliders icon does not turn; it only changes colour on hover)
    local minimize, minimizeIcon = makeControl("minus", theme.Muted, nil, nil, drawMinus)
    local close, closeIcon = makeControl("x", theme.Muted, nil, nil, drawCross) -- grey like search / settings / minimize

    -- ---------------------------------------------------------------
    -- SEARCH DRAWER: the search bar slides down and pushes the page down.
    --   sidebarLayout = false: the drawer sits under the top bar, full width (original look).
    --   sidebarLayout = true : the drawer lives INSIDE the right box (beside the sidebar); only the pages are pushed down.
    -- The bar itself has the same light soft white effect as the element boxes (glass sheen + soft top light) and nothing else:
    -- no depth layers, no darker fade, no border.
    -- ---------------------------------------------------------------
    local SEARCH_H = 46
    local searchUi = {Open = true, Token = 0, Shift = Instance.new("NumberValue")}
    local searchDrawer = new("Frame", {
        Name = "SearchDrawer", BackgroundTransparency = 1, BorderSizePixel = 0, ClipsDescendants = true,
        Position = UDim2.fromOffset(0, 58), Size = UDim2.new(1, 0, 0, 0), Visible = false, ZIndex = 40,
    }, main)
    -- Gen 2: the search bar is ALWAYS there (inside the header, see "HEADER SEARCH + TAB MENU" below). It is small and square
    -- with a darker UIStroke border. No icon has to be clicked to open it.
    local searchPanel = new("Frame", {
        Name = "SearchBar",
        BackgroundColor3 = lightUi and theme.Panel2 or Color3.fromRGB(11, 11, 13), -- darker than the buttons
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.fromOffset(140, 30),
        ZIndex = 41,
    }, searchDrawer) -- (moved into the header below)
    corner(searchPanel, UDim.new(0, CORNER_MEDIUM))
    window._SearchStroke = stroke(searchPanel, lightUi and Color3.fromRGB(170, 175, 186) or Color3.fromRGB(44, 44, 50), 0, 1)
    local searchPanelIcon = drawMagnifier(searchPanel, 16, theme.Muted, 43)
    searchPanelIcon.Position = UDim2.new(0, 18, 0.5, 0)
    local searchBox = new("TextBox", {
        BackgroundTransparency = 1,
        ClearTextOnFocus = false,
        PlaceholderText = "Search...",
        PlaceholderColor3 = theme.Muted,
        Text = "",
        TextColor3 = theme.Text,
        Font = Enum.Font.Gotham,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        Position = UDim2.fromOffset(32, 0),
        Size = UDim2.new(1, -56, 1, 0),
        ZIndex = 44,
    }, searchPanel)
    -- clear button (x): only visible while there is text, one tap empties the search
    do
        local searchClear = new("TextButton", {
            Name = "Clear", AutoButtonColor = false, Text = "", BackgroundTransparency = 1, Visible = false,
            AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -4, 0.5, 0), Size = UDim2.fromOffset(20, 20), ZIndex = 45,
        }, searchPanel)
        local _, setClearTint = drawCross(searchClear, 10, theme.Muted, 46)
        local function tintMagnifier(color)
            for _, part in ipairs(searchPanelIcon:GetDescendants()) do
                if part:IsA("UIStroke") then tween(part, 0.16, {Color = color})
                elseif part:IsA("Frame") and part.BackgroundTransparency < 1 then tween(part, 0.16, {BackgroundColor3 = color}) end
            end
        end
        searchBox:GetPropertyChangedSignal("Text"):Connect(function()
            searchClear.Visible = searchBox.Text ~= ""
        end)
        searchBox.Focused:Connect(function() tintMagnifier(theme.Text) end)
        searchBox.FocusLost:Connect(function() tintMagnifier(theme.Muted) end)
        searchClear.MouseEnter:Connect(function() if setClearTint then setClearTint(theme.Text) end end)
        searchClear.MouseLeave:Connect(function() if setClearTint then setClearTint(theme.Muted) end end)
        searchClear.MouseButton1Click:Connect(function()
            searchBox.Text = ""
            searchBox:CaptureFocus()
        end)
    end
    -- slide: the drawer grows, the bar slides down inside it, the page below is pushed down
    searchUi.Shift.Changed:Connect(function(value)
        if searchUi.Place then
            searchUi.Place(value) -- sidebarLayout = true: set once the right side exists (see the sidebar layout below)
        else
            searchDrawer.Size = UDim2.new(1, 0, 0, value)
            searchPanel.Position = UDim2.new(0.5, 0, 0, 6 - (SEARCH_H - value))
        end
        if searchUi.Push then searchUi.Push(value) end
    end)

    local currentTab
    local closeSearchPanel
    local tabShell, tabBar, tabList, pages
    local setProfileVisible = function() end -- assigned in the sidebar layout (profile + username show / hide)

    local settingsPanel = new("Frame", {
        BackgroundColor3 = theme.Background2,
        BackgroundTransparency = 0,
        Position = UDim2.new(1, 0, 0, 58),
        Size = UDim2.new(1, 0, 1, -58),
        ClipsDescendants = true,
        Visible = false,
        ZIndex = 50,
    }, main)
    corner(settingsPanel, UDim.new(0, 14))
    -- light soft white effect for the settings page: soft white gradient on the surface + light from the top edge
    new("UIGradient", {
        Name = "SettingsSheen",
        Rotation = 90,
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
            ColorSequenceKeypoint.new(1, lightUi and Color3.fromRGB(238, 238, 238) or Color3.fromRGB(205, 205, 205)),
        }),
    }, settingsPanel)
    addTopLight(settingsPanel, UDim.new(0, 14), 51, 1.15, true)
    local settingsTop = new("Frame", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 58),
        ZIndex = 52,
    }, settingsPanel)
    new("TextLabel", {
        BackgroundTransparency = 1,
        Text = "Settings",
        TextColor3 = theme.Text,
        Font = Enum.Font.GothamBold,
        TextSize = 17,
        TextXAlignment = Enum.TextXAlignment.Left,
        Position = UDim2.fromOffset(16, 10),
        Size = UDim2.new(1, -70, 0, 24),
        ZIndex = 53,
    }, settingsTop)
    new("TextLabel", {
        BackgroundTransparency = 1,
        Text = "Interface, Performance, Keybind and Save Manager",
        TextColor3 = theme.Muted,
        Font = Enum.Font.Gotham,
        TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Left,
        Position = UDim2.fromOffset(16, 32),
        Size = UDim2.new(1, -70, 0, 16),
        ZIndex = 53,
    }, settingsTop)
    local settingsBack, settingsBackIcon = makeControl("arrow-left", theme.Muted, "Back", nil, drawArrowLeft)
    settingsBack.Parent = settingsTop
    settingsBack.AnchorPoint = Vector2.new(1, 0)
    settingsBack.Position = UDim2.new(1, -12, 0, 11)
    settingsBack.Visible = true
    settingsBack.ZIndex = 55
    if settingsBackIcon then
        settingsBackIcon.AnchorPoint = Vector2.new(0.5, 0.5)
        settingsBackIcon.Position = UDim2.fromScale(0.5, 0.5)
        settingsBackIcon.ZIndex = 57
    end

    local settingsScroll = new("ScrollingFrame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(12, 64),
        Size = UDim2.new(1, -24, 1, -76),
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollBarThickness = 0,
        ScrollBarImageColor3 = theme.Accent,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        ZIndex = 51,
    }, settingsPanel)
    local settingsList = new("UIListLayout", {
        Padding = UDim.new(0, 10),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, settingsScroll)
    new("UIPadding", {
        PaddingBottom = UDim.new(0, 12),
    }, settingsScroll)

    -- Settings elements (buttons / inputs) use the same look as the element boxes (dark glass surface, faint top light)
    local settingsInner = lightUi and theme.Panel2 or Color3.fromRGB(28, 28, 31)
    local settingsInnerHover = lightUi and theme.ElementHover or Color3.fromRGB(40, 40, 44)

    -- Gen 2: a settings SECTION has no box any more (plain title + text); only the elements inside it (buttons, inputs,
    -- toggles) keep their boxes.
    -- boxed = true: the section is a real box (dark glass, light soft white effect, small grey border) like the element boxes
    local function settingsCard(order, height, boxed)
        local card = new("Frame", {
            BackgroundColor3 = elementBox,
            BackgroundTransparency = boxed and 0 or 1,
            BorderSizePixel = 0,
            Size = UDim2.new(1, -4, 0, height),
            LayoutOrder = order,
            ZIndex = 52,
        }, settingsScroll)
        if boxed then styleElementBox(card, 14) end
        return card
    end
    -- small muted heading above a group of settings ("General", "Data", ...)
    local function settingsHeader(order, text)
        local header = new("Frame", {BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, -4, 0, 20), LayoutOrder = order, ZIndex = 52}, settingsScroll)
        new("TextLabel", {
            BackgroundTransparency = 1, Text = text, TextColor3 = theme.Muted, Font = Enum.Font.GothamMedium, TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(6, 0), Size = UDim2.new(1, -12, 1, 0), ZIndex = 54,
        }, header)
        return header
    end
    local function settingsText(parent, text, y, size, color, font)
        return new("TextLabel", {
            BackgroundTransparency = 1,
            Text = text,
            TextColor3 = color or theme.Text,
            Font = font or Enum.Font.GothamBold,
            TextSize = size or 12,
            TextXAlignment = Enum.TextXAlignment.Left,
            Position = UDim2.fromOffset(13, y),
            Size = UDim2.new(1, -26, 0, 18),
            ZIndex = 54,
        }, parent)
    end
    local function makeSettingsButton(parent, text, props)
        local button = new("TextButton", {
            AutoButtonColor = false,
            BackgroundColor3 = settingsInner,
            BorderSizePixel = 0,
            Text = text,
            TextColor3 = theme.Text,
            Font = Enum.Font.GothamMedium,
            TextSize = 10,
            ZIndex = 55,
        }, parent)
        for property, value in pairs(props or {}) do button[property] = value end
        corner(button, UDim.new(0, 9))
        addTopLight(button, UDim.new(0, 9), button.ZIndex, 0.8)
        stroke(button, lightUi and Color3.fromRGB(208, 210, 217) or Color3.fromRGB(72, 72, 78), 0.1, 1) -- small grey border
        button.MouseEnter:Connect(function() tween(button, 0.15, {BackgroundColor3 = settingsInnerHover}) end)
        button.MouseLeave:Connect(function() tween(button, 0.15, {BackgroundColor3 = settingsInner}) end)
        return button
    end

    -- A settings ROW with a toggle: title + small text on the left (they shrink to fit any width), the toggle on the right.
    -- Same look as the Keybind row. Returns apply(value, instant, silent) and state(). silent = do not call onChange.
    local function makeSettingsToggleRow(order, title, subtitle, initial, onChange)
        local row = settingsCard(order, 52)
        local rowBox = new("Frame", {BackgroundColor3 = elementBox, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = 53}, row)
        styleElementBox(rowBox, 14)
        setTextPair(rowBox, title, subtitle, theme, 8, -84, 56, 16, 52)
        local track = new("Frame", {
            BackgroundColor3 = isDefaultTheme and theme.ToggleBackground or theme.Panel2,
            AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0), Size = UDim2.fromOffset(46, 22), ZIndex = 56,
        }, rowBox)
        corner(track, UDim.new(1, 0))
        stroke(track, isDefaultTheme and theme.ToggleDisabledOuterStroke or Color3.fromRGB(104, 106, 114), 0.08, 1)
        local onColor = isDefaultTheme and theme.ToggleEnabled or theme.Accent
        local offColor = knobOffColorFor(lightUi)
        local knob = new("Frame", {
            BackgroundColor3 = offColor, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 3, 0.5, 0),
            Size = UDim2.fromOffset(22, 16), ZIndex = 57,
        }, track)
        corner(knob, UDim.new(1, 0))
        local knobStroke = stroke(knob, Color3.new(1, 1, 1), 0.82, 1)
        local glow = addKnobGlow(knob, function() return fx.Enabled end, lightUi, knobStroke)
        local state = false
        local function apply(value, instant, silent)
            state = value == true
            local goal = {
                Position = state and UDim2.new(1, -25, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
                BackgroundColor3 = state and onColor or offColor,
            }
            if instant then
                knob.Position = goal.Position
                knob.BackgroundColor3 = goal.BackgroundColor3
            else
                tween(knob, 0.22, goal, Enum.EasingStyle.Quint)
            end
            glow.Show(state, instant == true, onColor)
            if not silent and onChange then onChange(state) end
        end
        local click = new("TextButton", {
            BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Size = UDim2.fromScale(1, 1), ZIndex = 60,
        }, rowBox)
        click.MouseButton1Click:Connect(function() apply(not state) end)
        apply(initial == true, true, true)
        return apply, function() return state end
    end

    -- GENERAL ---------------------------------------------------------
    settingsHeader(0, "General")
    -- User Profile & Username (sidebarLayout = true only): ON by default, OFF hides avatar + name in the sidebar
    if sidebarLayout then
        local applyProfile, profileState = makeSettingsToggleRow(1, "User Profile & Username", "Show your avatar and name in the sidebar.", true, function(on)
            setProfileVisible(on)
        end)
        window._ProfileToggle = function(value) applyProfile(value) end
        window._ProfileState = profileState
    end

    -- Keybind: ONE row like the reference. Icon + title on the left, a pill button on the right that shows the key name.
    -- Click the pill -> it shows "Recording" (soft glow) -> press a key -> the pill shows the new key name again.
    -- Everything lives in this do-block (no extra locals); window._SetKeybindDisplay(text, recording) is used by the key handler.
    local keybindButton
    local keybindOk, keybindError = pcall(function()
        local row = settingsCard(2, 48)
        local rowBox = new("Frame", {
            BackgroundColor3 = elementBox, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = 53,
        }, row)
        styleElementBox(rowBox, 14) -- Effect = false: the same box with a LOWER light soft white effect (no border)

        -- small keyboard icon (drawn with frames, no image needed)
        local iconColor = lightUi and theme.Muted or Color3.fromRGB(205, 205, 210)
        local icon = new("Frame", {
            BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 16, 0.5, 0),
            Size = UDim2.fromOffset(18, 12), ZIndex = 56,
        }, rowBox)
        corner(icon, UDim.new(0, 3))
        stroke(icon, iconColor, 0.15, 1.2)
        for rowIndex = 0, 1 do
            for dot = 0, 3 do
                new("Frame", {
                    BackgroundColor3 = iconColor, BorderSizePixel = 0,
                    Position = UDim2.fromOffset(3 + dot * 3.6, 2.5 + rowIndex * 3), Size = UDim2.fromOffset(2, 2), ZIndex = 56,
                }, icon)
            end
        end
        new("Frame", {
            BackgroundColor3 = iconColor, BorderSizePixel = 0,
            Position = UDim2.fromOffset(5, 8), Size = UDim2.fromOffset(8, 1.6), ZIndex = 56,
        }, icon)

        setTextPair(rowBox, "Toggle Keybind", nil, theme, 0, -170, 56, 44, 48) -- the title shrinks to fit any width

        -- the pill button (key name / "Recording")
        local pillIdle = lightUi and theme.Panel2 or Color3.fromRGB(54, 54, 59)
        local pillIdleHover = lightUi and theme.ElementHover or Color3.fromRGB(64, 64, 69)
        local pillRecording = lightUi and Color3.fromRGB(150, 150, 156) or Color3.fromRGB(104, 104, 108)
        local pill = new("TextButton", {
            AutoButtonColor = false, BackgroundColor3 = pillIdle, BorderSizePixel = 0, Text = typeof(window._Keybind) == "EnumItem" and window._Keybind.Name or tostring(window._Keybind),
            TextColor3 = theme.Text, Font = Enum.Font.GothamMedium, TextSize = 12, TextTruncate = Enum.TextTruncate.AtEnd,
            AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(104, 28), ZIndex = 57,
        }, rowBox)
        corner(pill, UDim.new(1, 0))
        -- the pill's light: a slightly lighter top, like the reference
        local pillSheen = new("UIGradient", {
            Rotation = 90,
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
                ColorSequenceKeypoint.new(1, lightUi and Color3.fromRGB(225, 225, 225) or Color3.fromRGB(190, 190, 190)),
            }),
        }, pill)
        -- AMBIENT GLOW (soft bloom) while recording: stacked pill layers behind the button, brightest next to it and fading
        -- smoothly to nothing (no rings). Same technique as the toggle's ambient glow; only used while Effect = true.
        local BLOOM_LAYERS, BLOOM_REACH, BLOOM_POWER = 8, 8, 0.085 -- LOW: a quiet glow
        local bloomHolder = new("Frame", {
            Name = "AmbientGlow", BackgroundTransparency = 1, BorderSizePixel = 0, Active = false,
            AnchorPoint = pill.AnchorPoint, Position = pill.Position, Size = pill.Size, ZIndex = 56,
        }, rowBox)
        local bloomColor = lightUi and Color3.fromRGB(120, 124, 136) or Color3.fromRGB(235, 235, 240)
        local bloomLayers = {}
        for index = 1, BLOOM_LAYERS do
            local grow = BLOOM_REACH * index / BLOOM_LAYERS
            local layer = new("Frame", {
                Name = "BloomLayer" .. index, BackgroundColor3 = bloomColor, BackgroundTransparency = 1,
                BorderSizePixel = 0, Active = false,
                AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
                Size = UDim2.new(1, grow * 2, 1, grow * 2), ZIndex = BLOOM_LAYERS - index + 1,
            }, bloomHolder)
            corner(layer, UDim.new(1, 0))
            local falloff = 1 - (index - 1) / BLOOM_LAYERS
            bloomLayers[index] = {Frame = layer, Alpha = BLOOM_POWER * falloff * falloff}
        end
        local recording = false
        pill.MouseEnter:Connect(function() if not recording then tween(pill, 0.15, {BackgroundColor3 = pillIdleHover}) end end)
        pill.MouseLeave:Connect(function() if not recording then tween(pill, 0.15, {BackgroundColor3 = pillIdle}) end end)

        -- text = what the pill shows, isRecording = true while a key is being recorded (grey pill + soft ambient glow)
        window._SetKeybindDisplay = function(text, isRecording)
            recording = isRecording == true
            pill.Text = tostring(text)
            pill.TextColor3 = (recording and not lightUi) and Color3.new(1, 1, 1) or theme.Text
            tween(pill, 0.18, {BackgroundColor3 = recording and pillRecording or pillIdle})
            local showBloom = recording and fx.Enabled
            for _, layer in ipairs(bloomLayers) do
                tween(layer.Frame, showBloom and 0.18 or 0.25, {BackgroundTransparency = showBloom and (1 - layer.Alpha) or 1}, Enum.EasingStyle.Quad)
            end
        end
        keybindButton = pill
    end)
    if not keybindOk then
        warn("[DarkyX] Keybind row error: " .. tostring(keybindError))
    end
    if not keybindButton then -- never nil: the rest of the window keeps working
        keybindButton = Instance.new("TextButton")
        window._SetKeybindDisplay = window._SetKeybindDisplay or function() end
    end

    -- PERFORMANCE: Slow mode (manual switch: lower effects + shorter animations for slow devices)
    do
        local applySlow = makeSettingsToggleRow(3, "Slow mode", "Fewer effects and shorter animations for slow devices.", false, function(on)
            window:SetSlowMode(on)
        end)
        window._SlowToggle = function(value) applySlow(value, true, true) end -- Window:SetSlowMode moves the switch
    end

    -- DATA ------------------------------------------------------------
    settingsHeader(4, "Data")
    -- Save Manager: values save automatically; the Load button restores them (nothing loads by itself)
    local saveSection = settingsCard(5, 198, true)
    settingsText(saveSection, "Save Manager", 10)
    settingsText(saveSection, "Saves automatically. Press Load to restore your saved values.", 31, 10, theme.Muted, Enum.Font.Gotham)
    local interfaceReset = makeSettingsButton(saveSection, "Reset", {
        AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -13, 0, 10), Size = UDim2.fromOffset(52, 22),
    })
    local saveRow = new("Frame", {
        BackgroundTransparency = 1, Position = UDim2.fromOffset(13, 58), Size = UDim2.new(1, -26, 0, 32), ZIndex = 54,
    }, saveSection)
    local loadButton = makeSettingsButton(saveRow, "Load", {Size = UDim2.new(1, 0, 1, 0)})

    -- typed inputs: UI Scale + Window Size
    local function makeSettingsInput(parent, props)
        local box = new("TextBox", {
            BackgroundColor3 = settingsInner,
            BorderSizePixel = 0,
            ClearTextOnFocus = false,
            Text = "",
            PlaceholderColor3 = theme.Muted,
            TextColor3 = theme.Text,
            Font = Enum.Font.GothamBold,
            TextSize = 11,
            ZIndex = 55,
        }, parent)
        for property, value in pairs(props or {}) do box[property] = value end
        corner(box, UDim.new(0, 9))
        addTopLight(box, UDim.new(0, 9), box.ZIndex, 0.8)
        local boxStroke = nil -- (the small grey border below is fixed; focus only changes the fill)
        stroke(box, lightUi and Color3.fromRGB(208, 210, 217) or Color3.fromRGB(72, 72, 78), 0.1, 1)
        -- click the input: depth effect only (no boxes)
        local boxDepth = addDepthEffect(box, 1.04)
        box.Focused:Connect(boxDepth.Show)
        box.FocusLost:Connect(boxDepth.Hide)
        box.Focused:Connect(function() tween(box, 0.15, {BackgroundColor3 = settingsInnerHover}); if boxStroke then tween(boxStroke, 0.15, {Color = theme.Accent}) end end)
        box.FocusLost:Connect(function() tween(box, 0.15, {BackgroundColor3 = settingsInner}); if boxStroke then tween(boxStroke, 0.15, {Color = elementBorder}) end end)
        return box
    end
    settingsText(saveSection, "UI Scale", 109, 10, theme.Muted, Enum.Font.GothamMedium)
    local scaleBox = makeSettingsInput(saveSection, {
        AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -13, 0, 102), Size = UDim2.fromOffset(150, 28),
        PlaceholderText = "0.40 - 2.00",
    })
    settingsText(saveSection, "Window size", 145, 10, theme.Muted, Enum.Font.GothamMedium)
    local sizeRow = new("Frame", {
        BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -13, 0, 138), Size = UDim2.fromOffset(150, 28), ZIndex = 54,
    }, saveSection)
    local widthBox = makeSettingsInput(sizeRow, {Size = UDim2.fromOffset(62, 28), PlaceholderText = "Width", TextSize = 10})
    new("TextLabel", {
        BackgroundTransparency = 1, Text = "x", TextColor3 = theme.Muted, Font = Enum.Font.GothamBold, TextSize = 11,
        Position = UDim2.fromOffset(62, 0), Size = UDim2.fromOffset(26, 28), ZIndex = 55,
    }, sizeRow)
    local heightBox = makeSettingsInput(sizeRow, {Position = UDim2.fromOffset(88, 0), Size = UDim2.fromOffset(62, 28), PlaceholderText = "Height", TextSize = 10})
    -- WINDOW ----------------------------------------------------------
    settingsHeader(6, "Window")
    -- Window Position: button with a rotate icon that puts the window back to its original position
    local positionSection = settingsCard(7, 154, true)
    settingsText(positionSection, "Window Position & Theme", 10)
    settingsText(positionSection, "Moved the window or changed colours? Put everything back.", 31, 10, theme.Muted, Enum.Font.Gotham)
    local resetPositionButton = makeSettingsButton(positionSection, "Reset Window Position", {
        Position = UDim2.fromOffset(13, 58), Size = UDim2.new(1, -26, 0, 32),
    })
    local resetPositionIcon = makeIcon(resetPositionButton, "rotate-ccw", 14, theme.Accent2, 57)
    if resetPositionIcon then
        resetPositionIcon.AnchorPoint = Vector2.new(0.5, 0.5)
        resetPositionIcon.Position = UDim2.new(0, 20, 0.5, 0)
        resetPositionButton.TextXAlignment = Enum.TextXAlignment.Center
    end
    -- Reset Window Theme: same box as "Reset Window Position"; puts every colour changed by a ColorPicker back to the original
    do
        local resetThemeButton = makeSettingsButton(positionSection, "Reset Window Theme", {
            Position = UDim2.fromOffset(13, 98), Size = UDim2.new(1, -26, 0, 32),
        })
        local resetThemeIcon = makeIcon(resetThemeButton, "palette", 14, theme.Accent2, 57)
        if resetThemeIcon then
            resetThemeIcon.AnchorPoint = Vector2.new(0.5, 0.5)
            resetThemeIcon.Position = UDim2.new(0, 20, 0.5, 0)
            resetThemeButton.TextXAlignment = Enum.TextXAlignment.Center
        end
        resetThemeButton.MouseButton1Click:Connect(function()
            window:ResetTheme()
            if resetThemeIcon then
                resetThemeIcon.Rotation = 0
                tween(resetThemeIcon, 0.45, {Rotation = -360}, Enum.EasingStyle.Quint)
            end
            if resetThemeButton:GetAttribute("Busy") then return end
            resetThemeButton:SetAttribute("Busy", true)
            resetThemeButton.Text = "Theme Reset"
            task.delay(1.4, function()
                if resetThemeButton.Parent then
                    resetThemeButton:SetAttribute("Busy", nil)
                    resetThemeButton.Text = "Reset Window Theme"
                end
            end)
        end)
    end
    -- Delete UI Library (Gen 2): the top bar cross only closes the window, deleting the library lives here.
    do
        settingsHeader(8, "Danger zone")
        local deleteSection = settingsCard(9, 100, true)
        settingsText(deleteSection, "Delete UI Library", 10)
        settingsText(deleteSection, "Closes and removes the whole UI. You can't undo this.", 31, 10, theme.Muted, Enum.Font.Gotham)
        local deleteButton = makeSettingsButton(deleteSection, "Delete UI Library", {
            Position = UDim2.fromOffset(13, 58), Size = UDim2.new(1, -26, 0, 32),
        })
        local deleteIcon = makeIcon(deleteButton, "trash-2", 14, theme.Danger, 57)
        if deleteIcon then
            deleteIcon.AnchorPoint = Vector2.new(0.5, 0.5)
            deleteIcon.Position = UDim2.new(0, 20, 0.5, 0)
            deleteButton.TextXAlignment = Enum.TextXAlignment.Center
        end
        deleteButton.MouseButton1Click:Connect(function()
            if window._ShowDeleteConfirm then window._ShowDeleteConfirm() end
        end)
    end
    local settingsStatus = new("TextLabel", {
        BackgroundTransparency = 1, Text = "", TextColor3 = theme.Success, Font = Enum.Font.Gotham, TextSize = 9,
        TextXAlignment = Enum.TextXAlignment.Left,
        Position = UDim2.fromOffset(13, 176), Size = UDim2.new(1, -26, 0, 14), ZIndex = 55,
    }, saveSection)

    local settingsPageOpen = false
    -- sidebarLayout = true : the Settings page opens on the RIGHT side (where the pages are); the tab menu stays visible.
    -- sidebarLayout = false: the Settings page opens full size and hides the tab bar, like before.
    local function settingsShownRect()
        if sidebarLayout then
            return UDim2.new(SIDE_SCALE, 10, 0, 0), UDim2.new(1 - SIDE_SCALE, -10, 1, 0)
        end
        return UDim2.new(0, 0, 0, 58), UDim2.new(1, 0, 1, -58)
    end
    local function settingsHiddenPosition()
        if sidebarLayout then return UDim2.new(1, 12, 0, 0) end
        return UDim2.new(1, 0, 0, 58)
    end
    local function openSettingsPage()
        if settingsPageOpen then return end
        settingsPageOpen = true
        closeSearchPanel()
        if not sidebarLayout then tabShell.Visible = false end
        pages.Visible = false
        settingsPanel.Visible = true
        local shownPosition, shownSize = settingsShownRect()
        settingsPanel.Size = shownSize
        settingsPanel.Position = settingsHiddenPosition()
        tween(settingsPanel, 0.34, {Position = shownPosition}, Enum.EasingStyle.Quint)
        if setSettingsTint then setSettingsTint(theme.Accent2) end
    end
    local function closeSettingsPage()
        if not settingsPageOpen then return end
        settingsPageOpen = false
        tween(settingsPanel, 0.3, {Position = settingsHiddenPosition()}, Enum.EasingStyle.Quint)
        if setSettingsTint then setSettingsTint(theme.Muted) end
        task.delay(0.31, function()
            if settingsPanel.Parent and not settingsPageOpen then
                settingsPanel.Visible = false
                tabShell.Visible = window._TabShellWanted ~= false
                pages.Visible = true
            end
        end)
    end
    settingsBack.MouseButton1Click:Connect(closeSettingsPage)

    closeSearchPanel = function()
        searchBox.Text = ""
        if setSearchTint then setSearchTint(theme.Muted) end
        for _, entry in ipairs(window._SearchItems) do
            if not entry.Floating then entry.Holder.Visible = entry.Tab == currentTab end
        end
        if true then return end -- Gen 2: the header search bar is always open, nothing slides
        searchUi.Open = false
        searchUi.Token += 1
        local mine = searchUi.Token
        pcall(function() searchBox:ReleaseFocus() end)
        tween(searchUi.Shift, 0.3, {Value = 0}, Enum.EasingStyle.Quint) -- slides back up
        task.delay(0.34, function()
            if mine == searchUi.Token and not searchUi.Open and searchDrawer.Parent then searchDrawer.Visible = false end
        end)
    end

    searchButton.MouseButton1Click:Connect(function()
        if settingsPageOpen then
            closeSettingsPage()
        end
        if searchUi.Open then
            closeSearchPanel()
            return
        end
        searchUi.Open = true
        searchUi.Token += 1
        searchDrawer.Visible = true
        tween(searchUi.Shift, 0.4, {Value = SEARCH_H}, Enum.EasingStyle.Quint) -- slides down inside the UI
        if setSearchTint then setSearchTint(theme.Accent2) end
        task.defer(function()
            if searchBox.Parent then searchBox:CaptureFocus() end
        end)
    end)
    settingsButton.MouseButton1Click:Connect(function()
        if settingsPageOpen then
            closeSettingsPage()
        else
            openSettingsPage()
        end
    end)

    -- Profile (no box): avatar + display name + @username, placed underneath the tab menu
    local function buildProfile(parent, position, size, avatarSize)
        local profile = new("Frame", {
            Name = "UserProfile",
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Position = position,
            Size = size,
            ZIndex = 14,
        }, parent)
        local avatar = new("ImageLabel", {
            Name = "ProfileImage",
            BackgroundTransparency = 1,
            Image = "",
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, 6, 0.5, 0),
            Size = UDim2.fromOffset(avatarSize, avatarSize),
            ZIndex = 15,
        }, profile)
        corner(avatar, UDim.new(1, 0))
        task.spawn(function()
            local ok, contentUrl = pcall(function()
                return Players:GetUserThumbnailAsync(LocalPlayer.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
            end)
            if ok and avatar.Parent then avatar.Image = contentUrl end
        end)
        if showUsername then
            local textLeft = 6 + avatarSize + 6
            new("TextLabel", {
                Name = "DisplayName",
                BackgroundTransparency = 1,
                Text = tostring(LocalPlayer.DisplayName or LocalPlayer.Name),
                TextColor3 = theme.Text,
                Font = Enum.Font.GothamBold,
                TextSize = 10,
                TextTruncate = Enum.TextTruncate.AtEnd,
                TextXAlignment = Enum.TextXAlignment.Left,
                AnchorPoint = Vector2.new(0, 1),
                Position = UDim2.new(0, textLeft, 0.5, 1),
                Size = UDim2.new(1, -textLeft - 4, 0, 15),
                ZIndex = 16,
            }, profile)
            new("TextLabel", {
                Name = "Username",
                BackgroundTransparency = 1,
                Text = "@" .. tostring(LocalPlayer.Name),
                TextColor3 = theme.Muted,
                Font = Enum.Font.Gotham,
                TextSize = 9,
                TextTruncate = Enum.TextTruncate.AtEnd,
                TextXAlignment = Enum.TextXAlignment.Left,
                Position = UDim2.new(0, textLeft, 0.5, 1),
                Size = UDim2.new(1, -textLeft - 4, 0, 14),
                ZIndex = 16,
            }, profile)
        else
            avatar.Position = UDim2.new(0, 6, 0.5, 0)
        end
        return profile
    end

    local content = new("Frame", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(10, 58),
        Size = UDim2.new(1, -20, 1, -68),
        ZIndex = 7,
    }, main)
    -- the search drawer pushes the whole page area down while it is open
    if not sidebarLayout then
        searchUi.Push = function(value)
            content.Position = UDim2.fromOffset(10, 58 + value)
            content.Size = UDim2.new(1, -20, 1, -68 - value)
        end
    end

    if sidebarLayout then
        tabShell = new("Frame", {
            BackgroundTransparency = 1,
            Position = UDim2.fromOffset(0, 0),
            Size = UDim2.new(SIDE_SCALE, 0, 1, 0),
            ZIndex = 8,
        }, content)

        local profileHeight = (showUserProfile or showUsername) and 60 or 0

        tabBar = new("ScrollingFrame", {
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Position = UDim2.fromOffset(2, 2),
            Size = UDim2.new(1, -4, 1, -8 - profileHeight),
            CanvasSize = UDim2.new(),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            ScrollBarThickness = 0,
            ScrollBarImageColor3 = theme.Accent,
            ScrollingDirection = Enum.ScrollingDirection.Y,
            ZIndex = 9,
        }, tabShell)
        tabList = new("UIListLayout", {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder}, tabBar)
        new("UIPadding", {PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4), PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 5)}, tabBar)

        local profileFrame
        if showUserProfile or showUsername then
            profileFrame = buildProfile(tabShell, UDim2.new(0, 6, 1, -profileHeight), UDim2.new(1, -12, 0, profileHeight), 40)
        end
        -- Settings > "User Profile & Username": hide / show the profile, the tab list uses the freed space
        setProfileVisible = function(visible)
            visible = visible ~= false
            if profileFrame then profileFrame.Visible = visible end
            local usedHeight = (profileFrame and visible) and profileHeight or 0
            tween(tabBar, 0.2, {Size = UDim2.new(1, -4, 1, -8 - usedHeight)}, Enum.EasingStyle.Quint)
        end

        pages = new("Frame", {
            BackgroundTransparency = 1,
            Position = UDim2.new(SIDE_SCALE, 10, 0, 0),
            Size = UDim2.new(1 - SIDE_SCALE, -10, 1, 0),
            ZIndex = 7,
        }, content)
        -- search drawer (sidebarLayout = true): lives in the right box, beside the sidebar. Only the pages are pushed
        -- down; the sidebar and the box stay where they are.
        searchDrawer.Parent = content
        searchDrawer.ZIndex = 40
        searchUi.Place = function(value)
            searchDrawer.Position = UDim2.new(SIDE_SCALE, 10, 0, 0)
            searchDrawer.Size = UDim2.new(1 - SIDE_SCALE, -10, 0, value)
            searchPanel.Size = UDim2.new(1, -4, 0, 36)
            searchPanel.Position = UDim2.new(0.5, 0, 0, 6 - (SEARCH_H - value))
        end
        searchUi.Push = function(value)
            pages.Position = UDim2.new(SIDE_SCALE, 10, 0, value)
            pages.Size = UDim2.new(1 - SIDE_SCALE, -10, 1, -value)
        end
        -- RIGHT BOX (sidebarLayout = true only): a glass box behind the pages.
        --   Only its TOP-LEFT corner is round: the box is bigger than the window on the right and at the bottom and is
        --   clipped by a window-shaped CanvasGroup, so it ends exactly at the window edges (no corner ends there).
        --   top-left side: normal (lit corner + stroke), top-right and the lower part fade out,
        --   the bottom gets a darker fade, plus a soft light soft white effect from the top-left corner.
        do
            local boxClip = new("CanvasGroup", {
                Name = "RightBoxClip", BackgroundTransparency = 1, BorderSizePixel = 0, Active = false,
                Size = UDim2.fromScale(1, 1), ZIndex = 6,
            }, main)
            corner(boxClip, WINDOW_RADIUS) -- same corner as the window
            local rightBox = new("Frame", {
                Name = "RightBox", BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, Active = false,
                ZIndex = 1,
            }, boxClip)
            corner(rightBox, UDim.new(0, 22))
            new("UIGradient", { -- darker fade: clear at the top, darker toward the bottom
                Rotation = 90,
                Transparency = NumberSequence.new({
                    NumberSequenceKeypoint.new(0, 1),
                    NumberSequenceKeypoint.new(0.45, 0.9),
                    NumberSequenceKeypoint.new(1, lightUi and 0.82 or 0.3),
                }),
            }, rightBox)
            local boxStroke = stroke(rightBox, lightUi and Color3.fromRGB(110, 116, 130) or Color3.new(1, 1, 1), 0, 1)
            new("UIGradient", { -- stroke: normal at the top-left, fades toward the top-right and the bottom
                Rotation = 35,
                Transparency = NumberSequence.new({
                    NumberSequenceKeypoint.new(0, lightUi and 0.45 or 0.72),
                    NumberSequenceKeypoint.new(0.16, lightUi and 0.6 or 0.84),
                    NumberSequenceKeypoint.new(0.4, lightUi and 0.84 or 0.94),
                    NumberSequenceKeypoint.new(0.75, 0.98),
                    NumberSequenceKeypoint.new(1, 1),
                }),
            }, boxStroke)
            local boxLight = new("Frame", { -- light soft white effect from the top-left corner
                Name = "RightBoxLight", BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Active = false,
                Size = UDim2.fromScale(1, 1), ZIndex = 1,
            }, rightBox)
            corner(boxLight, UDim.new(0, 22))
            new("UIGradient", {
                Rotation = 35,
                Transparency = NumberSequence.new({
                    NumberSequenceKeypoint.new(0, lightUi and 0.72 or 0.9),
                    NumberSequenceKeypoint.new(0.3, lightUi and 0.9 or 0.97),
                    NumberSequenceKeypoint.new(0.6, 1),
                    NumberSequenceKeypoint.new(1, 1),
                }),
            }, boxLight)
            window._RightBox = rightBox
            -- follows the pages (sidebar width = 0.36 scale) and the search drawer (which pushes the page area down)
            window._PlaceRightBox = function(animate)
                local y = 52 -- fixed: the search bar slides down INSIDE the box
                -- same left edge as before (sideW + 12) written in scale: sideW = 0.36 * (window width - 20)
                local boxPos = UDim2.new(SIDE_SCALE, 12 - 20 * SIDE_SCALE, 0, y)
                local boxSize = UDim2.new(1 - SIDE_SCALE, 20 * SIDE_SCALE + 28, 1, -y + 40)
                if animate then
                    tween(rightBox, 0.2, {Position = boxPos, Size = boxSize}, Enum.EasingStyle.Quint)
                else
                    rightBox.Position = boxPos
                    rightBox.Size = boxSize
                end
            end
            window._PlaceRightBox(false)
        end
        -- the Settings page lives in the same area as the pages (right side of the sidebar)
        settingsPanel.Parent = content
        -- ...and it has NO box of its own here: the right box is its surface (no rounded ends, no extra light)
        settingsPanel.BackgroundTransparency = 1
        for _, child in ipairs(settingsPanel:GetChildren()) do
            if child.Name == "TopLight" then child:Destroy() end
        end
    else
        tabShell = new("Frame", {
            BackgroundTransparency = 1,
            Position = UDim2.fromOffset(0, 0),
            Size = UDim2.new(1, 0, 0, 42),
            ZIndex = 8,
        }, content)
        tabBar = new("ScrollingFrame", {
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Position = UDim2.fromOffset(3, 2),
            Size = UDim2.new(1, -6, 0, 40),
            CanvasSize = UDim2.new(),
            AutomaticCanvasSize = Enum.AutomaticSize.X,
            ScrollingDirection = Enum.ScrollingDirection.X,
            ScrollBarThickness = 0,
            ZIndex = 9,
        }, tabShell)
        tabList = new("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center}, tabBar)
        new("UIPadding", {PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 5)}, tabBar)
        pages = new("Frame", {
            BackgroundTransparency = 1,
            Position = UDim2.fromOffset(0, 50),
            Size = UDim2.new(1, 0, 1, -50),
            ZIndex = 7,
        }, content)
    end

    -- Sidebar layout (Gen 2): the sidebar is UDim2.new(0.36, 0, 1, 0). Its width never changes any more, so this only
    -- places the pages / search drawer / right box / settings page below the search drawer.
    local function relayoutSidebar(animate)
        if not sidebarLayout then return end
        local shift = searchUi.Shift.Value
        local pagesPos = UDim2.new(SIDE_SCALE, 10, 0, shift)
        local pagesSize = UDim2.new(1 - SIDE_SCALE, -10, 1, -shift)
        if searchUi.Place then searchUi.Place(shift) end
        if window._PlaceRightBox then window._PlaceRightBox(animate) end
        if animate then
            tween(pages, 0.2, {Position = pagesPos, Size = pagesSize}, Enum.EasingStyle.Quint)
            if settingsPageOpen then tween(settingsPanel, 0.2, {Position = pagesPos, Size = pagesSize}, Enum.EasingStyle.Quint) end
        else
            pages.Position = pagesPos
            pages.Size = pagesSize
            if settingsPageOpen then settingsPanel.Position = pagesPos; settingsPanel.Size = pagesSize end
        end
    end

    -- Window:SetProfileVisible(true/false) / Window:GetProfileVisible()  (sidebarLayout only; same as the Settings toggle)
    function window:SetProfileVisible(value)
        if window._ProfileToggle then window._ProfileToggle(value ~= false) end
    end
    function window:GetProfileVisible()
        if window._ProfileState then return window._ProfileState() end
        return false
    end

    -- Notifications live in their own ScreenGui, so they show even before the window has loaded.
    function window:Notify(notification)
        return DarkyX:Notify(notification, theme)
    end

    -- Tags sit directly next to the window title (measured from the real title text width)
    local titleTextWidth = 110
    pcall(function()
        titleTextWidth = game:GetService("TextService"):GetTextSize(titleLabel.Text, titleLabel.TextSize, titleLabel.Font, Vector2.new(1000, 24)).X
    end)
    -- (the title sits at titleWrap's x; the tags start after the title text and stop before the header search bar + buttons)
    window._TagStart = function()
        local wrapX = titleWrap.Position.X.Offset
        local shown = math.min(titleTextWidth, math.max(windowWidth - (wrapX + 306), 0)) -- the title is cut at its wrapper's width
        return wrapX + titleLeft + shown + 10
    end
    local tagX = window._TagStart()
    local tagMaxWidth = math.max(0, windowWidth - 303 - tagX)
    local tagLayer = new("Frame", {BackgroundTransparency=1, ClipsDescendants=true, Position=UDim2.fromOffset(tagX, 8), Size=UDim2.fromOffset(tagMaxWidth, 24), ZIndex=24}, topBar)
    new("UIListLayout", {FillDirection=Enum.FillDirection.Horizontal, HorizontalAlignment=Enum.HorizontalAlignment.Left, VerticalAlignment=Enum.VerticalAlignment.Center, Padding=UDim.new(0,5), SortOrder=Enum.SortOrder.LayoutOrder}, tagLayer)

    function window:CreateTag(tagConfig)
        tagConfig = tagConfig or {}
        local tag = {text=tostring(tagConfig.text or tagConfig.Text or ""), color=tagConfig.color or tagConfig.Color or theme.Accent2}
        -- TextColor = Color3.fromRGB(255, 175, 15)  -> color of the tag text (default white)
        tag.textColor = tagConfig.TextColor or tagConfig.textColor or tagConfig.TextColor3 or Color3.new(1,1,1)
        local pill = new("TextLabel", {BackgroundColor3=Color3.new(1,1,1), BackgroundTransparency=0.08, Text=tag.text, TextColor3=tag.textColor, TextStrokeColor3=Color3.new(0,0,0), TextStrokeTransparency=fx.Enabled and 0.75 or 1, Font=Enum.Font.GothamBold, TextSize=9, Size=UDim2.fromOffset(math.max(34,18+#tag.text*6),20), ZIndex=25}, tagLayer)
        corner(pill,UDim.new(1,0))
        -- soft DARKER fade only: darker on the left, fading into the plain tag color (no light fade)
        local tagGradient = new("UIGradient", {Name="TagSoftFade", Rotation=0}, pill)
        local function applyTagFade(color)
            if not fx.Enabled then -- Effect = false (tag): plain tag colour, no darker fade, no glow
                tagGradient.Color = ColorSequence.new(color)
                return
            end
            tagGradient.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, color:Lerp(Color3.new(0,0,0), 0.5)),
                ColorSequenceKeypoint.new(1, color),
            })
        end
        applyTagFade(tag.color)
        local function updateSize() pill.Size=UDim2.fromOffset(math.max(34,18+#tag.text*6),20) end
        function tag:Set(config)
            config=config or {}
            local newText = config.text
            if newText == nil then newText = config.Text end
            if newText~=nil then tag.text=tostring(newText); pill.Text=tag.text; updateSize() end
            local newColor = config.color or config.Color
            if newColor then tag.color=newColor; applyTagFade(newColor) end
            local newTextColor = config.TextColor or config.textColor or config.TextColor3
            if newTextColor then tag.textColor=newTextColor; pill.TextColor3=newTextColor end
            return tag
        end
        function tag:SetText(text) tag.text=tostring(text or ""); pill.Text=tag.text; updateSize(); return tag end
        function tag:SetColor(color) tag.color=color; applyTagFade(color); return tag end
        function tag:SetTextColor(color) if color then tag.textColor=color; pill.TextColor3=color end; return tag end
        return tag
    end

    local floatingWidth = tonumber(config.floatingWidth) or 168 -- a little longer button (floatingWidth = ... still overrides)
    local floatingHeight = tonumber(config.floatingHeight) or 48
    local floating = new("TextButton", {
        AutoButtonColor = false,
        BackgroundColor3 = elementBox,
        BackgroundTransparency = 0,
        Text = "",
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, 0),
        Size = UDim2.fromOffset(floatingWidth, floatingHeight),
        ZIndex = 120,
        Visible = false,
    }, screenGui)
    corner(floating, UDim.new(1, 0))
    -- same light-white glass look as the element boxes (no border): white top edge falling off to grey
    new("UIGradient", {
        Name = "ElementSheen",
        Rotation = 90,
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
            ColorSequenceKeypoint.new(1, lightUi and Color3.fromRGB(240, 240, 240) or Color3.fromRGB(214, 214, 214)),
        }),
    }, floating)
    -- soft light cast from the top edge
    local floatingTopLight = new("Frame", {
        Name = "TopLight", BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Active = false,
        Size = UDim2.fromScale(1, 1), ZIndex = 121,
    }, floating)
    corner(floatingTopLight, UDim.new(1, 0))
    new("UIGradient", {
        Rotation = 90,
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, lightUi and 0.55 or 0.88),
            NumberSequenceKeypoint.new(0.7, 1),
            NumberSequenceKeypoint.new(1, 1),
        }),
    }, floatingTopLight)
    -- white light band that sweeps across the button on hover
    local floatingShine = new("Frame", {
        Name = "Shine", BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Active = false,
        Size = UDim2.fromScale(1, 1), ZIndex = 122,
    }, floating)
    corner(floatingShine, UDim.new(1, 0))
    local floatingShineGradient = new("UIGradient", {
        Rotation = 20,
        Offset = Vector2.new(-1.2, 0),
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(0.32, 1),
            NumberSequenceKeypoint.new(0.5, lightUi and 0.5 or 0.72),
            NumberSequenceKeypoint.new(0.68, 1),
            NumberSequenceKeypoint.new(1, 1),
        }),
    }, floatingShine)
    -- (the old stacked glow rings are gone: the SHINE above is the effect of the floating button)
    local function playFloatingShine()
        floatingShineGradient.Offset = Vector2.new(-1.2, 0)
        tween(floatingShineGradient, 0.75, {Offset = Vector2.new(1.2, 0)}, Enum.EasingStyle.Quint)
    end
    -- the shine also runs when the button appears and when it is pressed
    floating:GetPropertyChangedSignal("Visible"):Connect(function()
        if floating.Visible then task.delay(0.12, playFloatingShine) end
    end)
    floating.MouseButton1Down:Connect(playFloatingShine)
    -- bigger icon / image (about 60% of the button height: 28px on the default 48px button)
    local floatingIconSize = math.floor(floatingHeight * 0.6)
    local floatingTextX = 14 + floatingIconSize + 8
    local floatingIcon = makeIcon(floating, (not isBlankAsset(config.floatingIcon) and config.floatingIcon) or (not isBlankAsset(config.Image) and config.Image) or "panel-top", floatingIconSize, Color3.new(1, 1, 1), 123)
    if floatingIcon then
        floatingIcon.AnchorPoint = Vector2.new(0, 0.5)
        floatingIcon.Position = UDim2.new(0, 14, 0.5, 0)
        floatingIcon.BorderSizePixel = 0
        addScale(floatingIcon, 1)
    else
        floatingTextX = 18
    end
    new("TextLabel", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Text = tostring(config.floatingTitle or config.name or "DarkyX Hub"),
        TextColor3 = theme.Text,
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        Position = UDim2.fromOffset(floatingTextX, 10),
        Size = UDim2.new(1, -(floatingTextX + 12), 0, 15),
        ZIndex = 123,
    }, floating)
    new("TextLabel", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Text = tostring(config.floatingSubtitle or "Tap to show"),
        TextColor3 = theme.Muted,
        Font = Enum.Font.Gotham,
        TextSize = 9,
        TextXAlignment = Enum.TextXAlignment.Left,
        Position = UDim2.fromOffset(floatingTextX, 27),
        Size = UDim2.new(1, -(floatingTextX + 12), 0, 13),
        ZIndex = 123,
    }, floating)
    -- The floating button has ONE position. It is set a single time (a default spot just above the window) and after
    -- that it changes ONLY when the player drags it. Opening / closing, resizing or scaling the window, and
    -- Animations never move it. (floating.Position itself is the saved position.)
    local floatingPlaced = false
    local function placeFloatingAbove()
        if floatingPlaced then return end
        local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1920, 1080)
        local mainPos = main.AbsolutePosition
        local mainSize = main.AbsoluteSize
        local x, y
        if mainSize.X > 1 then
            x = mainPos.X + (mainSize.X - floatingWidth) * 0.5
            y = mainPos.Y - floatingHeight - 10
            floatingPlaced = true -- real window position known: remember this default spot
        else
            -- the window is not laid out yet: use the screen centre for now and try again next time
            x = viewport.X * 0.5 - floatingWidth * 0.5
            y = viewport.Y * 0.5 - windowHeight * 0.5 - floatingHeight - 10
        end
        x = math.clamp(x, 8, math.max(8, viewport.X - floatingWidth - 8))
        y = math.max(8, y)
        floating.Position = UDim2.fromOffset(x, y)
    end

    -- keeps the floating button fully on screen (runs after a drag and when the screen size changes)
    local floatingFixTween
    local function keepFloatingOnScreen()
        floatingPlaced = true -- the player chose this spot
        local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1920, 1080)
        local pos = floating.Position
        local x = math.clamp(pos.X.Offset, 0, math.max(0, viewport.X - floatingWidth))
        local y = math.clamp(pos.Y.Offset, 0, math.max(0, viewport.Y - floatingHeight))
        if x ~= pos.X.Offset or y ~= pos.Y.Offset then
            if floatingFixTween then pcall(function() floatingFixTween:Cancel() end) end
            floatingFixTween = tween(floating, 0.18, {Position = UDim2.fromOffset(x, y)}, Enum.EasingStyle.Quint)
        end
    end

    makeDrag(floating, floating, function()
        if window.Visible then return end
        window:SetVisible(true)
    end, keepFloatingOnScreen, {
        fullyVisible = true,
        -- a running "back on screen" tween must never fight the finger
        onStart = function()
            if floatingFixTween then pcall(function() floatingFixTween:Cancel() end); floatingFixTween = nil end
        end,
    })
    do
        local camera = workspace.CurrentCamera
        if camera then
            camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
                if floating.Parent and floatingPlaced then pcall(keepFloatingOnScreen) end
            end)
        end
    end
    floating.MouseEnter:Connect(function()
        tween(floating, 0.18, {BackgroundColor3 = elementBoxHover, Size = UDim2.fromOffset(floatingWidth + 5, floatingHeight + 2)})
        if floatingIcon then tween(floatingIcon, 0.18, {ImageColor3 = Color3.new(1, 1, 1)}) end
        playFloatingShine()
    end)
    floating.MouseLeave:Connect(function()
        tween(floating, 0.18, {BackgroundColor3 = elementBox, Size = UDim2.fromOffset(floatingWidth, floatingHeight)})
        if floatingIcon then tween(floatingIcon, 0.18, {ImageColor3 = Color3.new(1, 1, 1)}) end
    end)

    local mainScale = main:FindFirstChildOfClass("UIScale")
    -- veil used by the floating-button open animation (hides the layout while the small UI grows)
    local openVeil = new("Frame", {
        Name = "OpenVeil",
        BackgroundColor3 = theme.Background,
        BorderSizePixel = 0,
        Active = false,
        Size = UDim2.fromScale(1, 1),
        ZIndex = 500,
        Visible = false,
    }, main)
    local openVeilCorner = corner(openVeil, WINDOW_RADIUS)
    local mainCorner = main:FindFirstChildOfClass("UICorner")
    local openVeilTitle = new("TextLabel", {
        Name = "OpenTitle",
        BackgroundTransparency = 1,
        Text = tostring(config.floatingTitle or config.name or "DarkyX Hub"),
        TextColor3 = theme.Text,
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        Size = UDim2.fromScale(1, 1),
        ZIndex = 502,
    }, openVeil)
    -- white light flash that runs over the window while it expands
    local openFlash = new("Frame", {
        Name = "OpenFlash", BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1,
        BorderSizePixel = 0, Active = false, Size = UDim2.fromScale(1, 1), ZIndex = 501, Visible = false,
    }, main)
    local openFlashCorner = corner(openFlash, WINDOW_RADIUS)
    new("UIGradient", {
        Rotation = 90,
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0),
            NumberSequenceKeypoint.new(0.6, 0.6),
            NumberSequenceKeypoint.new(1, 1),
        }),
    }, openFlash)
    local floatingSlide = false -- the floating button is waiting (in place) while the window opens out of it
    local openToken = 0
    local openActive = false
    local openFinalPos = main.Position
    local openTweens = {}

    -- stops a running open animation and snaps the window to its resting state
    local function endOpen()
        openToken += 1
        for _, running in ipairs(openTweens) do pcall(function() running:Cancel() end) end
        table.clear(openTweens)
        local introObjects = window._IntroObjects -- the intro rectangle / glow
        if introObjects then
            window._IntroObjects = nil
            for _, object in ipairs(introObjects) do pcall(function() object:Destroy() end) end
            -- interrupted while only the rectangle was showing: never leave the window invisible
            if window.Visible and not window._Held and not window.Destroyed and not main.Visible then
                main.Visible = true
            end
        end
        if floatingSlide then
            floatingSlide = false
            floating.Size = UDim2.fromOffset(floatingWidth, floatingHeight)
            floating.Visible = false
        end
        if openActive then
            openActive = false
            main.Position = openFinalPos
        end
        main.ClipsDescendants = false
        if mainCorner then mainCorner.CornerRadius = WINDOW_RADIUS end
        openVeilCorner.CornerRadius = WINDOW_RADIUS
        openFlashCorner.CornerRadius = WINDOW_RADIUS
        openVeil.BackgroundColor3 = theme.Background
        openVeil.Visible = false
        openFlash.Visible = false
        if dragPill and not dragHeld then dragPill.BackgroundTransparency = 0 end
    end

    local windowScale = 1 -- user scale (Window:SetScale); open / close animations are relative to it

    -- ---------------------------------------------------------------
    -- Window:SetSize / Window:SetScale   (work with  Window:SetScale(1.2)  and  Window.SetScale(1.2))
    -- ---------------------------------------------------------------
    local MIN_SCALE, MAX_SCALE = 0.4, 2.0 -- any value in between (2 decimals) is accepted
    local SCALE_STEPS = {}
    for step = 8, 40 do table.insert(SCALE_STEPS, step / 20) end -- 0.4, 0.45, ... 1.95, 2.0 (kept for GetValidScales)
    -- Window size has NO limits: any width / height is accepted (only 1 px and a real number are required)

    -- one place that pushes the current size / scale onto the real instances
    local function applyWindowLayout(animate)
        endOpen() -- a running open animation must not fight the new size / scale
        if window._Minimized and window._SetMinimized then window._SetMinimized(false, true) end
        local target = UDim2.fromOffset(windowWidth, windowHeight)
        local visibleNow = window.Visible and main.Visible and not window._Held
        if animate and visibleNow then
            tween(main, 0.25, {Size = target}, Enum.EasingStyle.Quint)
            tween(mainScale, 0.25, {Scale = windowScale}, Enum.EasingStyle.Quint)
        else
            main.Size = target
            if visibleNow or not window.Visible then mainScale.Scale = windowScale end
        end
        local startX = window._TagStart()
        if window._FitRails then window._FitRails() end
        tagLayer.Position = UDim2.fromOffset(startX, 8)
        tagLayer.Size = UDim2.fromOffset(math.max(0, windowWidth - 303 - startX), 24)
        if window._RefreshInterface then window._RefreshInterface() end
    end

    function window.GetValidScales()
        return table.clone(SCALE_STEPS)
    end

    function window.GetScale()
        return windowScale
    end

    function window.SetScale(a, b, c)
        local value, instant = a, b
        if a == window then value, instant = b, c end
        local number = tonumber(value)
        if not number then
            Security.log("[DarkyX] Window:SetScale expects a number between 0.4 and 2.0, e.g. Window:SetScale(1.25).")
            return windowScale
        end
        local best = math.floor(math.clamp(number, MIN_SCALE, MAX_SCALE) * 100 + 0.5) / 100
        if math.abs(best - number) > 0.0001 then
            Security.log(("[DarkyX] %s is outside the allowed scale (0.4 - 2.0). Using %s."):format(tostring(number), tostring(best)))
        end
        windowScale = best
        applyWindowLayout(not instant)
        return best
    end
    window.SetUIScale = window.SetScale

    function window.ResetScale(a, b)
        local instant = (a == window) and b or a
        return window.SetScale(1, instant)
    end

    function window.GetSize()
        return windowWidth, windowHeight
    end

    function window.SetSize(a, b, c, d)
        local width, height, instant = a, b, c
        if a == window then width, height, instant = b, c, d end
        if typeof(width) == "UDim2" then
            width, height, instant = width.X.Offset, width.Y.Offset, height -- Window:SetSize(UDim2.fromOffset(600, 250))
        elseif typeof(width) == "Vector2" then
            width, height, instant = width.X, width.Y, height
        elseif type(width) == "table" then
            width, height, instant = width[1] or width.Width or width.width, width[2] or width.Height or width.height, height
        end
        width, height = tonumber(width), tonumber(height)
        if not width or not height then
            Security.log("[DarkyX] Window:SetSize expects (width, height), e.g. Window:SetSize(550, 340).")
            return windowWidth, windowHeight
        end
        local function finite(n) return n == n and n ~= math.huge and n ~= -math.huge end
        if not finite(width) or not finite(height) then
            Security.log("[DarkyX] Window:SetSize needs real numbers, e.g. Window:SetSize(550, 340).")
            return windowWidth, windowHeight
        end
        windowWidth, windowHeight = math.max(1, math.floor(width)), math.max(1, math.floor(height))
        applyWindowLayout(not instant)
        return windowWidth, windowHeight
    end

    function window.ResetSize(a, b)
        local instant = (a == window) and b or a
        return window.SetSize(550, 340, instant)
    end

    -- open animation: the floating button STAYS exactly where it is (it only moves when the player drags it).
    -- The small window is hidden behind it, then the button disappears and the window opens to full size and
    -- settles in its position with a white light flash.
    -- safety net: if the window ended up (almost) completely outside the screen, put it back in the centre
    local function rescueMainOnScreen()
        if window.Destroyed or not window.Visible or window._Held or not main.Parent or not main.Visible then return end
        local camera = workspace.CurrentCamera
        local viewport = camera and camera.ViewportSize or Vector2.new(1920, 1080)
        local pos, size = main.AbsolutePosition, main.AbsoluteSize
        if size.X <= 1 or size.Y <= 1 then return end
        local shownW = math.min(pos.X + size.X, viewport.X) - math.max(pos.X, 0)
        local shownH = math.min(pos.Y + size.Y, viewport.Y) - math.max(pos.Y, 0)
        if shownW < 48 or shownH < 48 then
            main.Position = UDim2.fromScale(0.5, 0.5)
            openFinalPos = main.Position
        end
    end

    local function playOpen(speed)
        speed = speed or 0.55 -- faster open (smaller = faster)
        endOpen()
        local token = openToken
        local function track(running) if running then table.insert(openTweens, running) end return running end
        local function alive() return token == openToken and not window.Destroyed and main.Parent ~= nil end

        openFinalPos = main.Position
        openActive = true
        mainScale.Scale = windowScale

        -- the window grows out of the floating button's own spot (placed once, then only changed by dragging)
        placeFloatingAbove()
        local floatPos = floating.Position
        local startPos = UDim2.fromOffset(floatPos.X.Offset + floatingWidth * 0.5, floatPos.Y.Offset + floatingHeight * 0.5)
        -- the window starts SMALL and hidden behind the floating button (80% of its size, same center)
        local pillW, pillH = floatingWidth * 0.8 / windowScale, floatingHeight * 0.8 / windowScale
        local pillRadius = UDim.new(0, pillH / 2)
        local target = UDim2.fromOffset(windowWidth, windowHeight)

        floatingSlide = true -- the floating button stays visible until the window starts to expand
        floating.Size = UDim2.fromOffset(floatingWidth, floatingHeight)
        floating.Visible = true
        main.ClipsDescendants = true
        main.Position = startPos
        main.Size = UDim2.fromOffset(pillW, pillH)
        if mainCorner then mainCorner.CornerRadius = pillRadius end
        openVeilCorner.CornerRadius = pillRadius
        openFlashCorner.CornerRadius = pillRadius
        openVeil.BackgroundColor3 = elementBox
        openVeil.BackgroundTransparency = 0
        openVeil.Visible = true
        openVeilTitle.TextTransparency = 0
        openFlash.BackgroundTransparency = 1
        openFlash.Visible = false
        if dragPill then dragPill.BackgroundTransparency = 1 end
        main.Visible = true

        -- stage 2 (after a very short hold): the floating button disappears (without moving) and the window opens
        task.delay(0.12 * speed, function()
            if not alive() then return end
            floatingSlide = false
            floating.Visible = false
            local expandStyle, expandTime = Enum.EasingStyle.Back, 0.62 * speed
            track(tween(main, expandTime, {Size = target}, expandStyle))
            track(tween(main, expandTime * 0.9, {Position = openFinalPos}, Enum.EasingStyle.Quint))
            if mainCorner then track(tween(mainCorner, 0.5 * speed, {CornerRadius = WINDOW_RADIUS}, Enum.EasingStyle.Quint)) end
            track(tween(openVeilCorner, 0.5 * speed, {CornerRadius = WINDOW_RADIUS}, Enum.EasingStyle.Quint))
            track(tween(openFlashCorner, 0.5 * speed, {CornerRadius = WINDOW_RADIUS}, Enum.EasingStyle.Quint))
            track(tween(openVeilTitle, 0.16 * speed, {TextTransparency = 1}))
            track(tween(openVeil, 0.34 * speed, {BackgroundColor3 = theme.Background}))
            -- light flash
            if fx.Enabled then
                openFlash.Visible = true
                openFlash.BackgroundTransparency = 0.78
                track(tween(openFlash, 0.6 * speed, {BackgroundTransparency = 1}, Enum.EasingStyle.Quad))
            end
            task.delay(0.12 * speed, function()
                if not alive() then return end
                track(tween(openVeil, 0.36 * speed, {BackgroundTransparency = 1}))
            end)
            task.delay(expandTime - 0.04, function()
                if not alive() then return end
                openActive = false
                main.Position = openFinalPos
                main.ClipsDescendants = false
                openVeil.Visible = false
                openFlash.Visible = false
                openVeil.BackgroundColor3 = theme.Background
                if dragPill and not dragHeld then tween(dragPill, 0.3, {BackgroundTransparency = 0}) end
                task.delay(0.05, rescueMainOnScreen)
            end)
        end)
    end

    -- close animation: the window shrinks to a small pill and hides behind the floating button, which pops in
    local function playClose()
        endOpen()
        if not main.Visible then
            floating.Visible = true
            placeFloatingAbove()
            return
        end
        local token = openToken
        local function alive() return token == openToken and not window.Destroyed and main.Parent ~= nil and not window.Visible end
        local function track(running) if running then table.insert(openTweens, running) end return running end

        local closePos = main.Position
        -- the window shrinks into the floating button's own spot (never moved by the window, only by dragging)
        placeFloatingAbove()
        local endPos = UDim2.fromOffset(floating.Position.X.Offset + floatingWidth * 0.5, floating.Position.Y.Offset + floatingHeight * 0.5)
        openFinalPos = closePos
        openActive = true -- if this is interrupted, endOpen() puts the window back where it was

        -- fast: the window shrinks AND slides up at the same time, turning into the floating button
        local pillW, pillH = floatingWidth * 0.94 / windowScale, floatingHeight * 0.94 / windowScale
        local pillRadius = UDim.new(0, pillH / 2)
        local duration = 0.22

        main.ClipsDescendants = true
        openVeil.BackgroundColor3 = theme.Background
        openVeil.BackgroundTransparency = 1
        openVeil.Visible = true
        openVeilTitle.TextTransparency = 1
        local mainShrink = track(tween(main, duration, {Size = UDim2.fromOffset(pillW, pillH), Position = endPos}, Enum.EasingStyle.Quart))
        if mainCorner then track(tween(mainCorner, duration, {CornerRadius = pillRadius}, Enum.EasingStyle.Quart)) end
        track(tween(openVeilCorner, duration, {CornerRadius = pillRadius}, Enum.EasingStyle.Quart))
        track(tween(openVeil, 0.12, {BackgroundTransparency = 0, BackgroundColor3 = elementBox}))
        track(tween(openVeilTitle, 0.12, {TextTransparency = 0}))

        -- the floating button takes over right where the shrinking window ends
        task.delay(duration * 0.8, function()
            if not alive() then return end
            floating.Visible = true
            floating.Size = UDim2.fromOffset(floatingWidth - 4, floatingHeight - 2)
            tween(floating, 0.2, {Size = UDim2.fromOffset(floatingWidth, floatingHeight)}, Enum.EasingStyle.Back)
        end)
        -- hide the small window the moment the shrink ends. Three triggers (tween end, timer, safety timer) and a
        -- done-flag, so it can never stay on screen behind the floating button, whatever else happens meanwhile.
        local finished = false
        local function finish()
            if finished then return end
            -- a newer open / close has taken over (fast toggling): this old
            -- timer must never touch the window again, or it would hide a window that is still closing and
            -- cancel the floating button's pop-in, so nothing would be left on screen.
            if token ~= openToken then return end
            if window.Destroyed or window.Visible or window._Held or not main.Parent then return end
            finished = true
            endOpen() -- restores the window position, corners and veil
            main.Size = UDim2.fromOffset(windowWidth, windowHeight)
            main.Visible = false
            -- whenever the window is hidden, the floating button is always there to bring it back
            floating.Size = UDim2.fromOffset(floatingWidth, floatingHeight)
            floating.Visible = true
        end
        if mainShrink then mainShrink.Completed:Connect(finish) end
        task.delay(duration + 0.02, finish)
        task.delay(duration + 0.3, finish)
    end

    local hideCloseConfirm -- forward declaration (defined below)
    local function setVisible(visible)
        if window.Destroyed then return end
        if window._Held then return end -- hidden while the key system is open
        if not visible and hideCloseConfirm then hideCloseConfirm() end
        if not visible and window._Minimized and window._MinToCentre then window._MinToCentre() end -- close from the collapsed bar
        window.Visible = visible
        if visible then
            if window._Minimized and window._SetMinimized then window._SetMinimized(false, true) end -- reopen = normal size
        end
        if visible then
            playOpen() -- the open animation takes care of the floating button
        else
            playClose()
        end
    end

    -- Delete UI confirmation popup
    local confirmOverlay
    function hideCloseConfirm()
        local overlay = confirmOverlay
        if not overlay then return end
        confirmOverlay = nil
        tween(overlay, 0.16, {BackgroundTransparency = 1})
        local card = overlay:FindFirstChild("Card")
        local cardScale = card and card:FindFirstChildOfClass("UIScale")
        if cardScale then tween(cardScale, 0.16, {Scale = 0.88}) end
        task.delay(0.17, function()
            if overlay.Parent then overlay:Destroy() end
        end)
    end

    local function showCloseConfirm()
        if confirmOverlay or window.Destroyed then return end
        if not window.Visible or not main.Visible or openActive then return end -- not while minimized / animating
        local overlay = new("TextButton", {
            Name = "CloseConfirm",
            AutoButtonColor = false,
            Text = "",
            BackgroundColor3 = Color3.new(0, 0, 0),
            BackgroundTransparency = 1,
            Size = UDim2.fromScale(1, 1),
            ZIndex = 90,
        }, main)
        corner(overlay, WINDOW_RADIUS)
        confirmOverlay = overlay
        tween(overlay, 0.2, {BackgroundTransparency = 0.35})
        overlay.MouseButton1Click:Connect(hideCloseConfirm)

        local card = new("TextButton", {
            Name = "Card",
            AutoButtonColor = false,
            Text = "",
            BackgroundColor3 = theme.Panel,
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(280, 142),
            ZIndex = 91,
        }, overlay)
        corner(card, UDim.new(0, 14))
        -- (no border) light soft white effect: soft white gradient + light from the top edge
        new("UIGradient", {
            Name = "CardSheen", Rotation = 90,
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
                ColorSequenceKeypoint.new(1, lightUi and Color3.fromRGB(238, 238, 238) or Color3.fromRGB(205, 205, 205)),
            }),
        }, card)
        addTopLight(card, UDim.new(0, 14), 92, 1.1, true)
        local cardScale = addScale(card, 0.86)
        tween(cardScale, 0.26, {Scale = 1}, Enum.EasingStyle.Back)

        local warnIcon = makeIcon(card, "trash-2", 18, theme.Text, 93) -- white, not red
        if warnIcon then warnIcon.Position = UDim2.fromOffset(18, 17) end
        new("TextLabel", {
            BackgroundTransparency = 1,
            Text = "Delete UI Library?",
            TextColor3 = theme.Text,
            Font = Enum.Font.GothamBold,
            TextSize = 13,
            TextXAlignment = Enum.TextXAlignment.Left,
            Position = UDim2.fromOffset(warnIcon and 44 or 18, 14),
            Size = UDim2.new(1, -60, 0, 24),
            ZIndex = 93,
        }, card)
        new("TextLabel", {
            BackgroundTransparency = 1,
            Text = "This will close and remove the UI. You can't undo this.",
            TextColor3 = theme.Muted,
            Font = Enum.Font.Gotham,
            TextSize = 10,
            TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top,
            Position = UDim2.fromOffset(18, 46),
            Size = UDim2.new(1, -36, 0, 32),
            ZIndex = 93,
        }, card)

        local function popupButton(text, x, bg, hoverBg, textColor)
            local b = new("TextButton", {
                AutoButtonColor = false,
                Text = text,
                BackgroundColor3 = bg,
                TextColor3 = textColor,
                Font = Enum.Font.GothamBold,
                TextSize = 11,
                Position = UDim2.new(x, x == 0 and 18 or 4, 1, -48),
                Size = UDim2.new(0.5, -22, 0, 32),
                ZIndex = 93,
            }, card)
            corner(b, UDim.new(0, 9))
            -- same white glass look as the element boxes
            new("UIGradient", {
                Name = "ElementSheen", Rotation = 90,
                Color = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
                    ColorSequenceKeypoint.new(1, lightUi and Color3.fromRGB(240, 240, 240) or Color3.fromRGB(214, 214, 214)),
                }),
            }, b)
            addTopLight(b, UDim.new(0, 9), 93, 1)
            b.MouseEnter:Connect(function() tween(b, 0.14, {BackgroundColor3 = hoverBg}) end)
            b.MouseLeave:Connect(function() tween(b, 0.14, {BackgroundColor3 = bg}) end)
            return b
        end
        local cancelBtn = popupButton("Cancel", 0, elementBox, elementBoxHover, theme.Text)
        local deleteBtn = popupButton("Delete", 0.5, theme.Danger, theme.Danger:Lerp(Color3.new(1, 1, 1), 0.18), Color3.new(1, 1, 1))

        cancelBtn.MouseButton1Click:Connect(hideCloseConfirm)
        deleteBtn.MouseButton1Click:Connect(function()
            hideCloseConfirm()
            window:Destroy()
        end)
    end

    window._ShowDeleteConfirm = showCloseConfirm -- used by Settings > Delete UI Library

    -- window:CreatePopup({ ... })  (window:Popup({ ... }) is the same thing)
    -- The popup is NOT part of the window: it loads in its own layer like a notification (so it shows while the window is
    -- loading, minimized or held by the key system), uses this window's theme + light soft white effect, and has NO dark
    -- background behind it. See DarkyX:CreatePopup for every option.
    window._Popups = {}
    function window.CreatePopup(a, b, c)
        local cfg, extra = a, b
        if a == window then cfg, extra = b, c end -- called with a colon: window:CreatePopup({...})
        if type(cfg) == "string" then cfg = {title = cfg, content = type(extra) == "string" and extra or nil} end
        if type(cfg) ~= "table" then
            Security.log("[DarkyX] CreatePopup needs a table: window:CreatePopup({ title = ..., content = ..., Options = {...} })")
            return nil
        end
        if window.Destroyed then return nil end
        local handle = DarkyX:CreatePopup(cfg, theme, fx.Enabled)
        if handle then
            table.insert(window._Popups, handle)
            for index = #window._Popups - 1, 1, -1 do -- forget popups that are already closed
                if not window._Popups[index].IsOpen() then table.remove(window._Popups, index) end
            end
        end
        return handle
    end
    window.Popup = window.CreatePopup

    -- Gen 2: the cross CLOSES the window (the floating button brings it back). It no longer deletes the UI library:
    -- deleting is in Settings > "Delete UI Library".
    close.MouseButton1Click:Connect(function()
        iconPop(closeIcon)
        setVisible(false)
    end)

    local dropdowns = {}
    local filterCurrentTabSearch

    -- Darker fade at the bottom (more content below) and top (scrolled down) of the page area
    local function makeScrollFade(atBottom)
        local fade = new("Frame", {
            Name = atBottom and "BottomFade" or "TopFade",
            BackgroundColor3 = theme.Shadow or (theme.Background or Color3.new(0, 0, 0)):Lerp(Color3.new(0, 0, 0), 0.6),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            AnchorPoint = Vector2.new(0, atBottom and 1 or 0),
            -- Gen 2: the fade belongs to the UI library itself: it spans the whole window width at the window edge
            -- (bottom edge / just under the top bar) instead of sitting inside the scrolling box.
            Position = atBottom and UDim2.new(0, 0, 1, 0) or UDim2.fromOffset(0, sidebarLayout and 58 or 108),
            Size = UDim2.new(1, 0, 0, atBottom and 58 or 30),
            Active = false,
            ZIndex = 20,
        }, main)
        if atBottom then corner(fade, WINDOW_RADIUS) end -- follows the rounded bottom corners of the window
        new("UIGradient", {
            Rotation = 90,
            Transparency = atBottom
                and NumberSequence.new({NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.02)})
                or NumberSequence.new({NumberSequenceKeypoint.new(0, 0.02), NumberSequenceKeypoint.new(1, 1)}),
        }, fade)
        return fade
    end
    -- Only the BOTTOM darker fade remains (the top one was removed on request).
    local bottomFade = makeScrollFade(true)
    local fadeState = {bottom = false}

    local function setFade(frame, key, show)
        -- (the darker fade at the top / bottom of the page is NOT affected by Effect: it stays on for true AND false)
        if fadeState[key] == show then return end
        fadeState[key] = show
        tween(frame, 0.22, {BackgroundTransparency = show and 0 or 1})
    end

    local function updateScrollFades()
        local page = currentTab and currentTab.Page
        if not page or not page.Parent then
            setFade(bottomFade, "bottom", false)
            return
        end
        local y = page.CanvasPosition.Y
        local maxY = page.AbsoluteCanvasSize.Y - page.AbsoluteWindowSize.Y
        setFade(bottomFade, "bottom", maxY > 4 and y < maxY - 4)
    end

    -- ---------------------------------------------------------------
    -- MINIMIZE (Gen 2): everything slides up and only the rounded top of the window stays (title + subtitle + the
    -- minimize / close buttons). Click minimize again: everything slides back down and the window is normal again.
    -- ---------------------------------------------------------------
    window._Minimized = false
    window._MinState = {Token = 0, Busy = false}
    -- The window is centre-anchored everywhere else. While it is collapsed it is anchored at the TOP instead, so the top
    -- edge never moves and ONLY the size animates (no position tween = nothing to shake / jitter).
    -- Put the centre anchor back without changing what is on screen (used before the window closes to the floating button).
    function window._MinToCentre()
        if main.AnchorPoint.Y == 0 then
            local p = main.Position
            main.AnchorPoint = Vector2.new(0.5, 0.5)
            main.Position = UDim2.new(p.X.Scale, p.X.Offset, p.Y.Scale, p.Y.Offset + main.Size.Y.Offset * mainScale.Scale / 2)
        end
    end
    function window._SetMinimized(minimizing, instant)
        local state = window._MinState
        if window.Destroyed or window._Minimized == minimizing then return end
        if state.Busy and not instant then return end
        endOpen()
        if hideCloseConfirm then hideCloseConfirm() end
        local MIN_HEADER_H = 58
        local scale = mainScale.Scale
        local boxClip = window._RightBox and window._RightBox.Parent
        state.Token += 1
        local token = state.Token
        window._Minimized = minimizing
        if window._RailsSetMin then window._RailsSetMin(minimizing) end
        local duration = instant and 0 or 0.45
        local function guard() return token == state.Token and not window.Destroyed and main.Parent ~= nil end

        if minimizing then
            if settingsPageOpen then closeSettingsPage() end
            closeSearchPanel()
            local fullH = main.Size.Y.Offset
            local drop = fullH - MIN_HEADER_H
            if drop <= 0 then window._Minimized = false return end
            state.FullH = fullH
            -- 1) the content gets a clip window under the top bar, at a FIXED size, and slides up inside it
            local clip = new("Frame", {
                Name = "MinClip", BackgroundTransparency = 1, BorderSizePixel = 0, ClipsDescendants = true, Active = false,
                Position = UDim2.fromOffset(0, MIN_HEADER_H), Size = UDim2.new(1, 0, 1, -MIN_HEADER_H), ZIndex = content.ZIndex,
            }, main)
            state.Clip, state.ContentPos, state.ContentSize = clip, content.Position, content.Size
            content.Parent = clip
            content.Size = UDim2.fromOffset(windowWidth - 20, fullH - 68)
            content.Position = UDim2.fromOffset(state.ContentPos.X.Offset, state.ContentPos.Y.Offset - MIN_HEADER_H)
            searchButton.Visible, settingsButton.Visible = false, false
            if window._SearchGroup then window._SearchGroup.Visible = false end
            bottomFade.Visible = false
            -- 2) the right box keeps its full size (it is NOT re-drawn every frame) and just fades out quickly
            if boxClip and boxClip:IsA("CanvasGroup") then
                state.BoxSize = boxClip.Size
                boxClip.Size = UDim2.fromOffset(windowWidth, fullH)
                tween(boxClip, instant and 0 or 0.2, {GroupTransparency = 1}, Enum.EasingStyle.Sine)
            end
            -- 3) anchor at the top (nothing moves on screen), then ONLY the size animates
            local position = main.Position
            main.AnchorPoint = Vector2.new(0.5, 0)
            main.Position = UDim2.new(position.X.Scale, position.X.Offset, position.Y.Scale, position.Y.Offset - fullH * scale / 2)
            local targetSize = UDim2.fromOffset(windowWidth, MIN_HEADER_H)
            local slideTo = UDim2.fromOffset(state.ContentPos.X.Offset, state.ContentPos.Y.Offset - MIN_HEADER_H - drop)
            if instant then
                main.Size, content.Position = targetSize, slideTo
            else
                state.Busy = true
                tween(main, duration, {Size = targetSize}, Enum.EasingStyle.Quint)
                tween(content, duration, {Position = slideTo}, Enum.EasingStyle.Quint)
                task.delay(duration + 0.03, function() if guard() then state.Busy = false end end)
            end
            task.delay(instant and 0 or 0.22, function()
                if guard() and boxClip then boxClip.Visible = false end
            end)
        else
            local clip = state.Clip
            local fullH = state.FullH or windowHeight
            local targetSize = UDim2.fromOffset(windowWidth, fullH)
            local function toFullCentre() -- centre anchor again, with the window at its full height, same top edge
                local p = main.Position
                local topY = main.AnchorPoint.Y == 0 and p.Y.Offset or (p.Y.Offset - MIN_HEADER_H * scale / 2)
                main.AnchorPoint = Vector2.new(0.5, 0.5)
                main.Position = UDim2.new(p.X.Scale, p.X.Offset, p.Y.Scale, topY + fullH * scale / 2)
            end
            local function finish()
                if not main.Parent then return end
                main.Size = targetSize
                toFullCentre()
                if clip and clip.Parent then
                    content.Parent = main
                    content.Position = state.ContentPos or UDim2.fromOffset(10, MIN_HEADER_H)
                    content.Size = state.ContentSize or UDim2.new(1, -20, 1, -68)
                    clip:Destroy()
                end
                state.Clip = nil
                if boxClip then
                    boxClip.Size = state.BoxSize or UDim2.fromScale(1, 1)
                    boxClip.Visible = true
                    boxClip.GroupTransparency = 0
                end
                searchButton.Visible, settingsButton.Visible = true, true
                if window._SearchGroup then window._SearchGroup.Visible = true end
                bottomFade.Visible = true
                fadeState.bottom = false
                bottomFade.BackgroundTransparency = 1
                task.defer(updateScrollFades)
                task.delay(0.05, rescueMainOnScreen)
            end
            if instant or not (clip and clip.Parent) then
                finish()
            else
                state.Busy = true
                local contentPos = state.ContentPos or UDim2.fromOffset(10, MIN_HEADER_H)
                if boxClip then boxClip.Visible = true tween(boxClip, 0.3, {GroupTransparency = 0}, Enum.EasingStyle.Sine) end
                tween(main, duration, {Size = targetSize}, Enum.EasingStyle.Quint)
                tween(content, duration, {Position = UDim2.fromOffset(contentPos.X.Offset, contentPos.Y.Offset - MIN_HEADER_H)}, Enum.EasingStyle.Quint)
                task.delay(duration + 0.02, function()
                    if guard() then state.Busy = false finish() end
                end)
            end
        end
    end
    minimize.MouseButton1Click:Connect(function()
        iconPop(minimizeIcon)
        window._SetMinimized(not window._Minimized)
    end)

    local function buildPage(tab)
        local page = new("ScrollingFrame", {
            Name = tab.Name .. "Page",
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Size = UDim2.fromScale(1, 1),
            CanvasSize = UDim2.new(),
            ScrollBarThickness = 0,
            ScrollBarImageColor3 = theme.Accent,
            ScrollingDirection = Enum.ScrollingDirection.Y,
            VerticalScrollBarInset = Enum.ScrollBarInset.None,
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            Visible = false,
            ZIndex = 8,
        }, pages)
        new("UIPadding", {
            PaddingTop = UDim.new(0, 3),
            PaddingBottom = UDim.new(0, 10),
            PaddingLeft = UDim.new(0, 2),
            PaddingRight = UDim.new(0, 5),
        }, page)
        local list = new("UIListLayout", {
            Padding = UDim.new(0, 8),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }, page)
        autoCanvas(page, list)
        page:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
            if currentTab and currentTab.Page == page then updateScrollFades() end
        end)
        page:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(function()
            if currentTab and currentTab.Page == page then updateScrollFades() end
        end)
        page:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(function()
            if currentTab and currentTab.Page == page then updateScrollFades() end
        end)
        return page, list
    end

    local function selectTab(tab)
        if (sidebarLayout or tab.Side) and settingsPageOpen then closeSettingsPage() end -- tab menu stays usable beside the settings page
        if currentTab == tab then
            if tab.TabFxPulse then tab.TabFxPulse() end
            return
        end
        local previousTab = currentTab
        if window._ActiveDropdown then window._ActiveDropdown:Close() end -- an open dropdown never stays open on a hidden tab
        currentTab = tab
        for _, other in ipairs(window.Tabs) do
            other.Page.Visible = false
            if other.TabFxOut and other.SelectionBox and other.SelectionBox.Visible then other.TabFxOut() end
            other.TabText.TextColor3 = theme.Muted
            if other.Icon then other.Icon.ImageColor3 = theme.Muted end
        end
        tab.Page.Visible = true
        if previousTab then
            -- page slides in from the direction of the tab that was picked
            local fromIndex, toIndex = 0, 0
            for index, other in ipairs(window.Tabs) do
                if other == previousTab then fromIndex = index end
                if other == tab then toIndex = index end
            end
            local dir = toIndex >= fromIndex and 1 or -1
            if tab.Side then
                tab.Page.Position = UDim2.fromOffset(tab.Side == "Left" and -14 or 14, 0) -- slides in from the side of its floating tab menu
            else
                tab.Page.Position = sidebarLayout and UDim2.fromOffset(0, 14 * dir) or UDim2.fromOffset(9 * dir, 8)
            end
            tween(tab.Page, 0.38, {Position = UDim2.new()}, Enum.EasingStyle.Quint)
        else
            tab.Page.Position = UDim2.new()
        end
        task.defer(updateScrollFades)
        if tab.TabFxIn then tab.TabFxIn() end -- light soft white effect, instant
        tab.TabText.TextColor3 = theme.Text
        if tab.Icon then tab.Icon.ImageColor3 = theme.White; iconPop(tab.Icon) end
        if searchUi.Open then
            filterCurrentTabSearch(searchBox.Text)
        else
            for _, entry in ipairs(window._SearchItems) do
                if entry.Tab == tab and not entry.Floating then entry.Holder.Visible = true end
            end
        end
    end

    -- ---------------------------------------------------------------
    -- FLOATING ELEMENTS  (Section: Draggable = true, Scale = "1.00")
    --   * hold an element ~0.4 s, then drag: it leaves the window and floats in its own ScreenGui, resized to the
    --     section's Scale. Moving the finger / mouse before the hold ends is a normal tap / scroll, nothing floats.
    --   * once an element floats OUTSIDE the window it needs NO hold anymore: press + move drags it at once (a tap is
    --     still a click; a press on a slider bar / text box stays with that control). Only pulling it OUT needs the hold.
    --   * floating elements stay when the window is closed (hidden). Deleting the UI library removes them.
    --   * release a floating element over the open window: it goes back to its original place, inside its section.
    --   * several elements of the same section can float at the same time.
    -- ---------------------------------------------------------------
    local registerSearchItem
    do -- (own block: keeps the helpers below out of the 200-locals limit of this big function)
    local GuiService = game:GetService("GuiService")
    local FLOAT_HOLD, FLOAT_SLOP = 0.4, 8
    local floatGui, floatLayer

    local function getFloatLayer()
        if window.Destroyed then return nil end
        if floatLayer and floatLayer.Parent then return floatLayer end
        local previousKey = Security.currentKey
        Security.currentKey = tostring(config.name or "DarkyX Hub")
        local ok, gui = pcall(Security.createScreenGui, Security.randomString(14), 1003)
        Security.currentKey = previousKey
        if not ok or not gui then return nil end
        floatGui = gui
        floatLayer = new("Frame", {
            Name = Security.randomString(10), BackgroundTransparency = 1, Active = false,
            Size = UDim2.fromScale(1, 1), ZIndex = 1,
        }, gui)
        return floatLayer
    end

    window._DestroyFloating = function()
        pcall(function() if floatGui then floatGui:Destroy() end end)
        floatGui, floatLayer = nil, nil
    end

    local function guiInset()
        local ok, inset = pcall(function() return GuiService:GetGuiInset() end)
        if ok and typeof(inset) == "Vector2" then return inset end
        return Vector2.new(0, 0)
    end

    -- floating element -> back to its page, at its original position inside its section
    local function dockEntry(entry)
        local record = entry.FloatRecord
        if not record then return end
        entry.FloatRecord = nil
        entry.Floating = false
        local root = entry.Holder
        pcall(function() root:SetAttribute("FloatGrab", false) end)
        local home = record.Parent
        if root and root.Parent and home and home.Parent then
            root.Parent = home
            root.Position = record.Position
            if record.Fixed then
                root.Size = record.RootSize
                root.AutomaticSize = record.RootAuto
            end
            pcall(function() record.Wrapper:Destroy() end)
            if searchUi.Open then
                filterCurrentTabSearch(searchBox.Text)
            else
                root.Visible = entry.Tab == currentTab
            end
        else
            pcall(function() if root then root:Destroy() end end) -- its page is gone
            pcall(function() record.Wrapper:Destroy() end)
        end
    end

    function window:DockAll()
        for _, entry in ipairs(window._SearchItems) do
            if entry.Floating then dockEntry(entry) end
        end
    end

    -- the floating element gets a fixed width + height (the root fills the wrapper from then on)
    local function applyFloatSize(record, root, width, height)
        record.Fixed = true
        record.Wrapper.AutomaticSize = Enum.AutomaticSize.None
        record.Wrapper.Size = UDim2.fromOffset(width, height)
        root.AutomaticSize = Enum.AutomaticSize.None
        root.Size = UDim2.fromScale(1, 1)
    end

    -- resize grip (automatic for every floating element: Draggable sections and all V2 elements / SectionV2):
    -- three small diagonal lines in the bottom-right corner. record.MinW / record.MinH = smallest size.
    local function addResizeGrip(entry, record, layer)
        local root, wrapper, uiScale = entry.Holder, record.Wrapper, record.UIScale
        local gripSize = 20
        local grip = new("TextButton", {
            Name = Security.randomString(8), Text = "", AutoButtonColor = false, BackgroundTransparency = 1,
            AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -1, 1, -1),
            Size = UDim2.fromOffset(gripSize, gripSize), ZIndex = 2100, Active = true,
        }, wrapper)
        local lines = {}
        for index = 1, 3 do
            local offset = gripSize - 3.5 * index
            lines[index] = new("Frame", {
                Name = "Line", BackgroundColor3 = theme.Muted, BackgroundTransparency = 0.2, BorderSizePixel = 0,
                AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(offset, offset),
                Size = UDim2.fromOffset(5 * index, 2), Rotation = -45, ZIndex = 2101,
            }, grip)
            corner(lines[index], UDim.new(1, 0))
        end
        local function tint(color, transparency)
            for _, line in ipairs(lines) do line.BackgroundColor3 = color; line.BackgroundTransparency = transparency end
        end
        grip.MouseEnter:Connect(function() tint(theme.Text, 0) end)
        grip.MouseLeave:Connect(function() if not record.Resizing then tint(theme.Muted, 0.2) end end)

        grip.InputBegan:Connect(function(input)
            if window.Destroyed or record.Resizing then return end
            if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
            record.Resizing = true
            tint(theme.Text, 0)
            local isTouch = input.UserInputType == Enum.UserInputType.Touch
            local scale = math.max(uiScale.Scale, 0.1)
            local size = wrapper.AbsoluteSize
            local startW, startH = size.X / scale, size.Y / scale
            local startPointer = input.Position
            applyFloatSize(record, root, startW, startH)
            local moveConnection, endConnection
            local function stop()
                if moveConnection then moveConnection:Disconnect(); moveConnection = nil end
                if endConnection then endConnection:Disconnect(); endConnection = nil end
                record.Resizing = false
                tint(theme.Muted, 0.2)
            end
            moveConnection = UserInputService.InputChanged:Connect(function(changed)
                if isTouch then
                    if changed ~= input then return end
                elseif changed.UserInputType ~= Enum.UserInputType.MouseMovement then
                    return
                end
                local view = layer.AbsoluteSize
                local minW, minH = record.MinW or 70, record.MinH or 26
                local width = math.clamp(startW + (changed.Position.X - startPointer.X) / scale, minW, math.max(view.X / scale - 10, minW))
                local height = math.clamp(startH + (changed.Position.Y - startPointer.Y) / scale, minH, math.max(view.Y / scale - 10, minH))
                wrapper.Size = UDim2.fromOffset(width, height)
                entry.FloatSize = {width, height} -- remembered for the next time it floats
            end)
            endConnection = UserInputService.InputEnded:Connect(function(ended)
                if isTouch then
                    if ended ~= input then return end
                elseif ended.UserInputType ~= Enum.UserInputType.MouseButton1 then
                    return
                end
                stop()
            end)
        end)
    end

    local function beginFloatDrag(entry, section, input, pointerStart)
        local scale = section.Scale
        local root = entry.Holder
        local layer = getFloatLayer()
        if not layer or not root or not root.Parent then return end
        local record = entry.FloatRecord
        local compensation = Vector2.new(0, 0)
        if not record then
            local absPos, absSize = root.AbsolutePosition, root.AbsoluteSize
            local inset = guiInset()
            -- where inside the element the pointer is: after the resize that point stays under the pointer
            local grab = Vector2.new(
                math.clamp(pointerStart.X + inset.X - absPos.X, 0, absSize.X),
                math.clamp(pointerStart.Y + inset.Y - absPos.Y, 0, absSize.Y))
            compensation = grab * (1 - scale)
            local wrapper = new("Frame", {
                Name = Security.randomString(10), BackgroundTransparency = 1,
                Position = UDim2.fromOffset(absPos.X, absPos.Y), Size = UDim2.fromOffset(absSize.X, 0),
                AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 5,
            }, layer)
            local uiScale = new("UIScale", {Scale = 1}, wrapper)
            record = {
                Wrapper = wrapper, UIScale = uiScale, Parent = root.Parent, Position = root.Position,
                RootSize = root.Size, RootAuto = root.AutomaticSize,
            }
            entry.FloatRecord = record
            entry.Floating = true
            root.Position = UDim2.new()
            root.Visible = true
            root.Parent = wrapper
            tween(uiScale, 0.2, {Scale = scale}, Enum.EasingStyle.Quint)
            if section.Resizable ~= false then -- automatic: Draggable = true is enough
                if entry.FloatSize then applyFloatSize(record, root, entry.FloatSize[1], entry.FloatSize[2]) end
                addResizeGrip(entry, record, layer)
            end
        end
        local wrapper = record.Wrapper
        -- a shield above the element swallows the release: the toggle / button below can never "click" by accident
        local shield = new("TextButton", {
            Name = Security.randomString(8), AutoButtonColor = false, BackgroundTransparency = 1, Text = "",
            Size = UDim2.fromScale(1, 1), ZIndex = 2000, Active = true,
        }, wrapper)
        -- sliders / colour areas stop following the pointer while the element itself is being moved
        pcall(function() root:SetAttribute("FloatGrab", true) end)

        local startPosition = wrapper.Position
        local startX, startY = startPosition.X.Offset, startPosition.Y.Offset
        local isTouch = input.UserInputType == Enum.UserInputType.Touch
        local moveConnection, endConnection, focusConnection
        local function place(position)
            local view = layer.AbsoluteSize
            local size = wrapper.AbsoluteSize
            local x = startX + (position.X - pointerStart.X) + compensation.X
            local y = startY + (position.Y - pointerStart.Y) + compensation.Y
            x = math.clamp(x, 40 - size.X, math.max(view.X - 40, 40 - size.X))
            y = math.clamp(y, 0, math.max(view.Y - 30, 0))
            wrapper.Position = UDim2.fromOffset(x, y)
        end
        local function finish(cancelled)
            if moveConnection then moveConnection:Disconnect(); moveConnection = nil end
            if endConnection then endConnection:Disconnect(); endConnection = nil end
            if focusConnection then focusConnection:Disconnect(); focusConnection = nil end
            pcall(function() root:SetAttribute("FloatGrab", false) end)
            task.delay(0.12, function() pcall(function() shield:Destroy() end) end)
            if cancelled or window.Destroyed then return end
            -- released over the open window -> back to the original place
            if window.Visible and main.Visible then
                local center = wrapper.AbsolutePosition + wrapper.AbsoluteSize / 2
                local mainPos, mainSize = main.AbsolutePosition, main.AbsoluteSize
                if center.X >= mainPos.X and center.X <= mainPos.X + mainSize.X
                    and center.Y >= mainPos.Y and center.Y <= mainPos.Y + mainSize.Y then
                    dockEntry(entry)
                end
            end
        end
        moveConnection = UserInputService.InputChanged:Connect(function(changed)
            if isTouch then
                if changed ~= input then return end
            elseif changed.UserInputType ~= Enum.UserInputType.MouseMovement then
                return
            end
            place(changed.Position)
        end)
        endConnection = UserInputService.InputEnded:Connect(function(ended)
            if isTouch then
                if ended ~= input then return end
            elseif ended.UserInputType ~= Enum.UserInputType.MouseButton1 then
                return
            end
            finish(false)
        end)
        focusConnection = UserInputService.WindowFocusReleased:Connect(function() finish(true) end)
    end

    local function makeFloatable(entry, section)
        local root = entry.Holder
        if not root then return end
        local pressCount = 0
        local waiting = false
        -- a press on a slider bar / text box (tagged "NoFloatDrag") is for the element itself, never for moving it
        local pressOnControl = false
        for _, descendant in ipairs(root:GetDescendants()) do
            if descendant:GetAttribute("NoFloatDrag") then
                descendant.InputBegan:Connect(function(controlInput)
                    if controlInput.UserInputType == Enum.UserInputType.MouseButton1 or controlInput.UserInputType == Enum.UserInputType.Touch then
                        pressOnControl = true
                    end
                end)
            end
        end
        do
            local releaseConnection = UserInputService.InputEnded:Connect(function(endedInput)
                if endedInput.UserInputType == Enum.UserInputType.MouseButton1 or endedInput.UserInputType == Enum.UserInputType.Touch then
                    pressOnControl = false
                end
            end)
            root.Destroying:Connect(function() releaseConnection:Disconnect() end)
        end
        local function onPress(input)
            if window.Destroyed or waiting then return end
            if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
            waiting = true
            pressCount += 1
            local token = pressCount
            local isTouch = input.UserInputType == Enum.UserInputType.Touch
            local startPosition, lastPosition = input.Position, input.Position
            local moveConnection, endConnection
            local function stopWaiting()
                waiting = false
                if moveConnection then moveConnection:Disconnect(); moveConnection = nil end
                if endConnection then endConnection:Disconnect(); endConnection = nil end
            end
            moveConnection = UserInputService.InputChanged:Connect(function(changed)
                if isTouch then
                    if changed ~= input then return end
                elseif changed.UserInputType ~= Enum.UserInputType.MouseMovement then
                    return
                end
                lastPosition = changed.Position
                -- ALREADY FLOATING (outside the window): no hold needed, press + move drags it at once.
                -- A tap is still a click, a press on a slider bar / text box still belongs to that control.
                if entry.FloatRecord then
                    if math.abs(lastPosition.X - startPosition.X) > 5 or math.abs(lastPosition.Y - startPosition.Y) > 5 then
                        pressCount += 1
                        stopWaiting()
                        -- never while the resize grip is held: the grip only resizes, it can not move the element
                        if not pressOnControl and not entry.FloatRecord.Resizing then
                            beginFloatDrag(entry, section, input, startPosition)
                        end
                    end
                    return
                end
                -- moved before the hold was over: a normal drag / scroll, nothing floats
                if math.abs(lastPosition.X - startPosition.X) > FLOAT_SLOP or math.abs(lastPosition.Y - startPosition.Y) > FLOAT_SLOP then
                    pressCount += 1
                    stopWaiting()
                end
            end)
            endConnection = UserInputService.InputEnded:Connect(function(ended)
                if isTouch then
                    if ended ~= input then return end
                elseif ended.UserInputType ~= Enum.UserInputType.MouseButton1 then
                    return
                end
                pressCount += 1
                stopWaiting()
            end)
            task.delay(FLOAT_HOLD, function()
                if pressCount ~= token or not moveConnection then return end -- released / moved: not a hold
                if entry.FloatRecord then return end -- already floating: a plain press + move drags it, no hold involved
                stopWaiting()
                if window.Destroyed then return end
                beginFloatDrag(entry, section, input, lastPosition)
            end)
        end
        root.InputBegan:Connect(onPress)
        -- a dropdown / colour picker has a header BUTTON that covers the whole element and swallows the press: the hold
        -- is bound to every button directly inside the element too (never to the option list / colour areas)
        for _, child in ipairs(root:GetChildren()) do
            if child:IsA("TextButton") or child:IsA("ImageButton") then
                child.InputBegan:Connect(onPress)
            end
        end
    end

    -- ---------------------------------------------------------------
    -- V2 ELEMENTS   (they float OUTSIDE the window, on its right side, and can be dragged anywhere)
    --   tab:CreateButtonV2({...})   tab:CreateToggleV2({...})   tab:CreateSliderV2({...})   tab:CreateInputV2({...})
    --     The same elements as CreateButton / CreateToggle / CreateSlider / CreateInput (same look, same Callback /
    --     Flag / Value / save). A tap / click is a normal click, press + move drags the element. Every V2 element
    --     has a RESIZE GRIP in its bottom-right corner automatically (hold + drag = width AND height).
    --     Enabled = true shows the element, Enabled = false hides it. Option Width = 230 (pixels), Scale = 1.0.
    --       api:SetEnabled(bool)  api:GetEnabled()  api:ToggleEnabled()  api:ResetPosition()  api:SetScale(n)  api:Remove()
    --
    --   SECTION V2: a floating BOX (light soft white effect, icon + title) that can be dragged and resized, and that holds
    --   V2 elements inside it:
    --       local Section = tab:CreateSectionV2({ Title = "Aiming", Icon = 93364949241311, Enabled = true, Scale = "0.70" })
    --       Section:CreateSliderV2({ Title = "Field of view", Range = {70, 120}, Callback = fn })   -- inside the box
    --       tab:CreateInputV2({ ... })     -- also inside the box: after a SectionV2 the V2 elements of the tab go into it
    --       tab:EndSectionV2()             -- the next tab:Create...V2 floats on its own again
    --   (Section:CreateButtonV2 / CreateToggleV2 / CreateSliderV2 / CreateInputV2; CreateButton / ... are the same.)
    --   EVERY V2 element (also inside a Section) takes  Scale = "0.70"  (or 0.7): 0.1 - 3, so it can be as small as you want:
    --       Section:CreateButtonV2({ Title = "Panic", Scale = "0.70" })     tab:CreateToggleV2({ Title = "ESP", Scale = 0.8 })
    --   Section api: SetTitle  SetEnabled  GetEnabled  ToggleEnabled  ResetPosition  SetScale  Remove
    --   An element made in a section also has :SetEnabled(bool) / :Remove(). They disappear with the UI library.
    -- ---------------------------------------------------------------
    local floatWidgets = {} -- every V2 element / SectionV2 in creation order (default stacking)
    -- (helpers live in one table: keeps this big function under the 200-locals limit)
    local H = {Top = 0, Queued = false, WIDTH = {CreateButton = 230, CreateToggle = 230, CreateSlider = 260, CreateInput = 260}}

    function H.bringToFront(wrapper)
        H.Top += 1
        pcall(function() wrapper.ZIndex = 5 + H.Top end)
    end

    -- default places: stacked on the right side of the window; wraps into a new column when the screen is full.
    -- A widget the player moved by hand keeps its own place.
    function H.restack()
        if window.Destroyed or not floatLayer or not floatLayer.Parent then return end
        local view = floatLayer.AbsoluteSize
        local mainPos, mainSize = main.AbsolutePosition, main.AbsoluteSize
        local top = mainPos.Y
        local x, y, columnWidth = mainPos.X + mainSize.X + 12, top, 0
        for _, widget in ipairs(floatWidgets) do
            local wrapper = widget.Wrapper
            if wrapper.Parent and widget.Enabled and not widget.UserMoved then
                local size = wrapper.AbsoluteSize
                if y > top and y + size.Y > view.Y - 8 then
                    x, y, columnWidth = x + columnWidth + 12, top, 0
                end
                local placeX = x
                if placeX + size.X > view.X - 8 then placeX = math.max(view.X - size.X - 8, 8) end
                wrapper.Position = UDim2.fromOffset(placeX, y)
                y += size.Y + 10
                columnWidth = math.max(columnWidth, size.X)
            end
        end
    end
    function H.queueRestack()
        if H.Queued then return end
        H.Queued = true
        task.defer(function()
            H.Queued = false
            pcall(H.restack)
        end)
    end

    function H.removeWidget(widget)
        for index = #floatWidgets, 1, -1 do
            if floatWidgets[index] == widget then table.remove(floatWidgets, index) end
        end
        H.queueRestack()
    end

    function H.isPress(input)
        return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
    end

    -- press + move on `object` drags `wrapper` (a tap stays a normal click).
    -- hooks.canStart() -> false: this press is not for moving (slider bar, text box, scrolling list)
    -- hooks.moved(): the widget was moved by hand      hooks.dragging(bool): drag started / ended
    function H.bindDrag(wrapper, object, hooks)
        object.InputBegan:Connect(function(input)
            if window.Destroyed or not H.isPress(input) then return end
            H.bringToFront(wrapper)
            local isTouch = input.UserInputType == Enum.UserInputType.Touch
            local startPointer = input.Position
            local startX, startY = wrapper.Position.X.Offset, wrapper.Position.Y.Offset
            local dragging, shield = false, nil
            local moveConnection, endConnection
            local function release()
                if moveConnection then moveConnection:Disconnect(); moveConnection = nil end
                if endConnection then endConnection:Disconnect(); endConnection = nil end
            end
            moveConnection = UserInputService.InputChanged:Connect(function(changed)
                if isTouch then
                    if changed ~= input then return end
                elseif changed.UserInputType ~= Enum.UserInputType.MouseMovement then
                    return
                end
                local dx, dy = changed.Position.X - startPointer.X, changed.Position.Y - startPointer.Y
                if not dragging then
                    if math.abs(dx) + math.abs(dy) < 6 then return end
                    if hooks.canStart and not hooks.canStart() then release() return end
                    dragging = true
                    if hooks.moved then hooks.moved() end
                    if hooks.dragging then hooks.dragging(true) end
                    -- the release lands on this shield, so the button / toggle below never "clicks" after a drag
                    shield = new("TextButton", {
                        Name = Security.randomString(8), AutoButtonColor = false, BackgroundTransparency = 1, Text = "",
                        Size = UDim2.fromScale(1, 1), ZIndex = 2000, Active = true,
                    }, wrapper)
                end
                local layer = floatLayer
                if not layer then return end
                local view, size = layer.AbsoluteSize, wrapper.AbsoluteSize
                wrapper.Position = UDim2.fromOffset(
                    math.clamp(startX + dx, 40 - size.X, math.max(view.X - 40, 40 - size.X)),
                    math.clamp(startY + dy, 0, math.max(view.Y - 30, 0)))
            end)
            endConnection = UserInputService.InputEnded:Connect(function(ended)
                if isTouch then
                    if ended ~= input then return end
                elseif ended.UserInputType ~= Enum.UserInputType.MouseButton1 then
                    return
                end
                release()
                if dragging and hooks.dragging then hooks.dragging(false) end
                if shield then
                    local old = shield
                    task.delay(0.12, function() pcall(function() old:Destroy() end) end)
                end
            end)
        end)
    end

    -- a press on a slider bar / text box (objects tagged "NoFloatDrag") is never the start of a widget drag
    function H.trackNoDrag(root, state)
        for _, descendant in ipairs(root:GetDescendants()) do
            if descendant:GetAttribute("NoFloatDrag") then
                descendant.InputBegan:Connect(function(input)
                    if H.isPress(input) then state.Blocked = true end
                end)
            end
        end
    end
    function H.bindObjects(wrapper, root, hooks)
        H.bindDrag(wrapper, root, hooks)
        for _, child in ipairs(root:GetChildren()) do
            if child:IsA("TextButton") or child:IsA("ImageButton") then H.bindDrag(wrapper, child, hooks) end
        end
    end
    function H.newBlockState(wrapper)
        local state = {Blocked = false}
        local connection = UserInputService.InputEnded:Connect(function(input)
            if H.isPress(input) then state.Blocked = false end
        end)
        wrapper.Destroying:Connect(function() connection:Disconnect() end)
        return state
    end

    function H.argument(api, first, second) -- works for api:SetEnabled(v) and api.SetEnabled(v)
        if first == api then return second end
        return first
    end

    -- one V2 element (button / toggle / slider / input) on its own
    window._CreateFloatWidget = function(method, tab, cfg)
        cfg = ci(cfg or {})
        local layer = getFloatLayer()
        if not layer then error("DarkyX: the floating layer could not be created", 0) end
        local enabled = cfg.enabled ~= false -- default: shown
        local width = math.clamp(tonumber(cfg.width) or H.WIDTH[method] or 230, 120, 600)
        local wrapper = new("Frame", {
            Name = Security.randomString(10), BackgroundTransparency = 1, Visible = enabled,
            Position = UDim2.fromOffset(-2000, -2000), Size = UDim2.fromOffset(width, 0),
            AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 5,
        }, layer)
        local uiScale = new("UIScale", {Scale = math.clamp(tonumber(cfg.scale) or 1, 0.1, 3)}, wrapper)

        -- build the normal element, but inside the wrapper (and not as a draggable-section element)
        local savedPage, savedOrder, savedSection = tab.Page, tab.Order, rawget(tab, "_FloatSection")
        tab.Page, tab.Order = wrapper, 0
        rawset(tab, "_FloatSection", nil)
        local ok, api = pcall(tab[method], tab, cfg)
        tab.Page, tab.Order = savedPage, savedOrder
        rawset(tab, "_FloatSection", savedSection)
        if not ok then
            pcall(function() wrapper:Destroy() end)
            error(api, 0)
        end
        api = type(api) == "table" and api or {}
        local root
        for _, child in ipairs(wrapper:GetChildren()) do
            if child:IsA("GuiObject") and not child:IsA("UIScale") then root = child; break end
        end
        local entry = window._SearchItems[#window._SearchItems]
        if entry and entry.Holder == root then
            entry.Floating = true -- the page search / tab switch ignore it
        else
            entry = {Holder = root}
        end

        local widget = {Wrapper = wrapper, Enabled = enabled, UserMoved = false}
        table.insert(floatWidgets, widget)
        wrapper:GetPropertyChangedSignal("AbsoluteSize"):Connect(H.queueRestack)
        H.queueRestack()
        task.delay(0.8, H.queueRestack) -- again once the window finished its opening animation

        if root then
            -- automatic resize grip + drag (a tap stays a click; slider bar / text box keep their own press)
            local record = {Wrapper = wrapper, UIScale = uiScale, MinW = 110, MinH = 36}
            addResizeGrip(entry, record, layer)
            local state = H.newBlockState(wrapper)
            H.trackNoDrag(root, state)
            H.bindObjects(wrapper, root, {
                -- the resize grip only resizes: while it is held the element can not be dragged
                canStart = function() return not state.Blocked and not record.Resizing end,
                moved = function() widget.UserMoved = true end,
            })
        end

        function api:SetEnabled(value)
            enabled = H.argument(api, self, value) ~= false
            widget.Enabled = enabled
            wrapper.Visible = enabled
            H.queueRestack()
        end
        function api:GetEnabled() return enabled end
        function api:ToggleEnabled() api:SetEnabled(not enabled) return enabled end
        function api:ResetPosition() widget.UserMoved = false; H.queueRestack() end
        function api:SetScale(value)
            uiScale.Scale = math.clamp(tonumber(H.argument(api, self, value)) or uiScale.Scale, 0.1, 3)
            H.queueRestack()
        end
        function api:Remove()
            for index = #window._SearchItems, 1, -1 do
                if window._SearchItems[index] == entry then table.remove(window._SearchItems, index) end
            end
            H.removeWidget(widget)
            pcall(function() wrapper:Destroy() end)
        end
        api.Frame = wrapper
        return api
    end

    -- SECTION V2: a floating, draggable, resizable box (light soft white effect) that holds V2 elements
    window._CreateFloatSection = function(tab, cfg, attach)
        cfg = ci(cfg or {})
        local layer = getFloatLayer()
        if not layer then error("DarkyX: the floating layer could not be created", 0) end
        local enabled = cfg.enabled ~= false
        local width = math.clamp(tonumber(cfg.width) or 250, 150, 700)
        local HEADER_H, PAD, GAP = 36, 8, 6
        local white = Color3.new(1, 1, 1)

        local wrapper = new("Frame", {
            Name = Security.randomString(10), BackgroundTransparency = 1, Visible = enabled,
            Position = UDim2.fromOffset(-2000, -2000), Size = UDim2.fromOffset(width, HEADER_H + PAD * 2), ZIndex = 5,
        }, layer)
        local uiScale = new("UIScale", {Scale = math.clamp(tonumber(cfg.scale) or 1, 0.1, 3)}, wrapper)

        -- the box: dark card + the library's light soft white effect (top light + sheen), no border
        local card = new("Frame", {
            Name = "SectionV2", BackgroundColor3 = elementBox, BorderSizePixel = 0,
            Size = UDim2.fromScale(1, 1), ZIndex = 6,
        }, wrapper)
        styleElementBox(card, 16)
        -- (no white border at all: not at rest, not on hover and not while the box is dragged)

        local header = new("Frame", {
            Name = "Header", BackgroundTransparency = 1, Active = true,
            Size = UDim2.new(1, 0, 0, HEADER_H), ZIndex = 8,
        }, card)
        local iconObject = makeIcon(header, cfg.icon, 16, lightUi and theme.Text or Color3.new(1, 1, 1), 9) -- white, no theme colour
        local left = 14
        if iconObject then
            iconObject.AnchorPoint = Vector2.new(0, 0.5)
            iconObject.Position = UDim2.new(0, 14, 0.5, 0)
            left = 36
        end
        local titleLabel = new("TextLabel", {
            Name = "Title", BackgroundTransparency = 1, Text = tostring(cfg.name or "Section"),
            TextColor3 = theme.Text, Font = Enum.Font.GothamBold, TextSize = 13,
            TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
            Position = UDim2.fromOffset(left, 0), Size = UDim2.new(1, -(left + 12), 1, 0), ZIndex = 9,
        }, header)
        new("Frame", {
            Name = "Divider", BackgroundColor3 = white, BackgroundTransparency = 0.92, BorderSizePixel = 0,
            Position = UDim2.new(0, 12, 0, HEADER_H - 1), Size = UDim2.new(1, -24, 0, 1), ZIndex = 8,
        }, card)

        local body = new("ScrollingFrame", {
            Name = "Body", BackgroundTransparency = 1, BorderSizePixel = 0, Active = true,
            Position = UDim2.fromOffset(0, HEADER_H), Size = UDim2.new(1, 0, 1, -HEADER_H),
            CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
            ScrollingDirection = Enum.ScrollingDirection.Y, ScrollBarThickness = 3,
            ScrollBarImageColor3 = theme.Muted, ScrollBarImageTransparency = 0.4,
            ClipsDescendants = true, ZIndex = 8,
        }, card)
        new("UIListLayout", {Padding = UDim.new(0, GAP), SortOrder = Enum.SortOrder.LayoutOrder}, body)
        new("UIPadding", {
            PaddingTop = UDim.new(0, PAD), PaddingBottom = UDim.new(0, PAD),
            PaddingLeft = UDim.new(0, PAD), PaddingRight = UDim.new(0, PAD),
        }, body)

        local widget = {Wrapper = wrapper, Enabled = enabled, UserMoved = false}
        local record = {Wrapper = wrapper, UIScale = uiScale, MinW = 150, MinH = HEADER_H + 46}
        table.insert(floatWidgets, widget)

        -- height follows the content until the player resizes the box by hand; very long content scrolls
        local function refreshHeight()
            if record.Fixed or record.Resizing or window.Destroyed then return end
            local total, count = 0, 0
            for _, child in ipairs(body:GetChildren()) do
                if child:IsA("GuiObject") and child.Visible then
                    local height = child.Size.Y.Offset
                    if height <= 0 then height = child.AbsoluteSize.Y / math.max(uiScale.Scale, 0.1) end
                    total += height
                    count += 1
                end
            end
            if count > 1 then total += GAP * (count - 1) end
            local height = HEADER_H + total + PAD * 2
            local view = layer.AbsoluteSize
            height = math.min(height, math.max(view.Y / math.max(uiScale.Scale, 0.1) - 24, HEADER_H + 60))
            wrapper.Size = UDim2.fromOffset(wrapper.Size.X.Offset, height)
            H.queueRestack()
        end
        local function queueRefresh() task.defer(refreshHeight) end
        body.ChildAdded:Connect(function(child)
            if child:IsA("GuiObject") then
                child:GetPropertyChangedSignal("Size"):Connect(queueRefresh)
                child:GetPropertyChangedSignal("Visible"):Connect(queueRefresh)
            end
            queueRefresh()
        end)
        body.ChildRemoved:Connect(queueRefresh)
        wrapper:GetPropertyChangedSignal("AbsoluteSize"):Connect(H.queueRestack)
        task.delay(0.8, H.queueRestack)

        -- automatic resize grip
        addResizeGrip({Holder = card}, record, layer)

        -- drag: header, the box itself, the empty body and (when nothing scrolls) the elements
        local state = H.newBlockState(wrapper)
        local function scrollable() return body.AbsoluteCanvasSize.Y > body.AbsoluteWindowSize.Y + 1 end
        local boxHooks = {
            canStart = function() return not record.Resizing end, -- the resize grip only resizes, it never moves the box
            moved = function() widget.UserMoved = true end,
            dragging = function(active)
                wrapper:SetAttribute("Dragging", active)
            end,
        }
        local innerHooks = {
            canStart = function() return not state.Blocked and not scrollable() and not record.Resizing end,
            moved = boxHooks.moved,
            dragging = boxHooks.dragging,
        }
        H.bindDrag(wrapper, header, boxHooks)
        H.bindDrag(wrapper, card, boxHooks)
        H.bindDrag(wrapper, body, innerHooks)

        -- the V2 elements of this box are made by the normal element functions, with the body as their page
        local inner = setmetatable({Page = body, Order = 0, Owner = tab.Owner or tab, Frame = body}, {
            __index = function(_, key)
                if key == "Name" then return tab.Name end -- flags / save keys use the name of the tab
                return nil
            end,
        })
        attach(inner)

        local api = {Frame = wrapper, Card = card, Body = body, _Alive = true}
        local function addInner(method, config)
            config = ci(config or {})
            local ok, result = pcall(inner[method], inner, config)
            if not ok then error(result, 0) end
            result = type(result) == "table" and result or {}
            local root
            for _, child in ipairs(body:GetChildren()) do
                if child:IsA("GuiObject") and (not root or child.LayoutOrder >= root.LayoutOrder) then root = child end
            end
            if not root then return result end
            local entry = window._SearchItems[#window._SearchItems]
            if entry and entry.Holder == root then entry.Floating = true end
            local visible = config.enabled ~= false
            -- Scale = "0.70" (or 0.7): this element is drawn smaller / bigger INSIDE the box. It lives in a cell that has the
            -- scaled height, so the box layout follows. Scale = 1 / nothing: exactly as before (no cell).
            local cell
            local elementScale = tonumber(config.scale)
            if elementScale and math.abs(elementScale - 1) > 0.001 then
                elementScale = math.clamp(elementScale, 0.1, 3)
                cell = new("Frame", {
                    Name = "ScaleCell", BackgroundTransparency = 1, BorderSizePixel = 0,
                    LayoutOrder = root.LayoutOrder, Size = UDim2.new(1, 0, 0, math.max(root.Size.Y.Offset, 1) * elementScale),
                    ZIndex = root.ZIndex,
                }, body)
                local fullWidth = root.Size.X
                root.AnchorPoint = Vector2.new(0.5, 0)
                root.Position = UDim2.new(0.5, 0, 0, 0)
                root.Size = fullWidth
                new("UIScale", {Scale = elementScale}, root)
                root.Parent = cell
                local function followHeight()
                    if cell.Parent then
                        local height = root.Size.Y.Offset
                        if height <= 0 then height = root.AbsoluteSize.Y / math.max(elementScale * uiScale.Scale, 0.1) end
                        cell.Size = UDim2.new(1, 0, 0, math.max(height, 1) * elementScale)
                    end
                end
                root:GetPropertyChangedSignal("Size"):Connect(followHeight)
                cell.Visible = visible
            end
            local shown = cell or root
            shown.Visible = visible
            H.trackNoDrag(root, state)
            H.bindObjects(wrapper, root, innerHooks)
            if cell then H.bindDrag(wrapper, cell, innerHooks) end
            function result:SetEnabled(value)
                shown.Visible = H.argument(result, self, value) ~= false
            end
            function result:GetEnabled() return shown.Visible end
            function result:Remove()
                for index = #window._SearchItems, 1, -1 do
                    if window._SearchItems[index] == entry then table.remove(window._SearchItems, index) end
                end
                pcall(function() shown:Destroy() end)
            end
            function result:SetScale(value)
                local number = tonumber(H.argument(result, self, value))
                if not (number and cell and cell.Parent) then return end
                elementScale = math.clamp(number, 0.1, 3)
                local scaleObject = root:FindFirstChildOfClass("UIScale")
                if scaleObject then scaleObject.Scale = elementScale end
                cell.Size = UDim2.new(1, 0, 0, math.max(root.Size.Y.Offset, 1) * elementScale)
            end
            result.Frame = root
            queueRefresh()
            return result
        end
        function api:CreateButtonV2(config) return addInner("CreateButton", config) end
        function api:CreateToggleV2(config) return addInner("CreateToggle", config) end
        function api:CreateSliderV2(config) return addInner("CreateSlider", config) end
        function api:CreateInputV2(config) return addInner("CreateInput", config) end
        api.CreateButton, api.CreateToggle = api.CreateButtonV2, api.CreateToggleV2
        api.CreateSlider, api.CreateInput = api.CreateSliderV2, api.CreateInputV2

        function api:SetTitle(text)
            titleLabel.Text = tostring(H.argument(api, self, text) or "")
            return api
        end
        api.SetName = api.SetTitle
        function api:SetEnabled(value)
            enabled = H.argument(api, self, value) ~= false
            widget.Enabled = enabled
            wrapper.Visible = enabled
            H.queueRestack()
        end
        function api:GetEnabled() return enabled end
        function api:ToggleEnabled() api:SetEnabled(not enabled) return enabled end
        function api:ResetPosition() widget.UserMoved = false; H.queueRestack() end
        function api:SetScale(value)
            uiScale.Scale = math.clamp(tonumber(H.argument(api, self, value)) or uiScale.Scale, 0.1, 3)
            queueRefresh()
        end
        function api:Remove()
            api._Alive = false
            for index = #window._SearchItems, 1, -1 do
                local item = window._SearchItems[index]
                if item.Holder and item.Holder.Parent == body then table.remove(window._SearchItems, index) end
            end
            H.removeWidget(widget)
            pcall(function() wrapper:Destroy() end)
        end
        api.Destroy = api.Remove
        queueRefresh()
        H.queueRestack()
        return api
    end

    registerSearchItem = function(tab, holder, name, description)
        local entry = {
            Tab = tab.Owner or tab, -- elements inside a group still belong to their tab
            Holder = holder,
            Text = string.lower(tostring(name or "") .. " " .. tostring(description or "")),
        }
        table.insert(window._SearchItems, entry)
        local section = rawget(tab, "_FloatSection")
        if section and section.Draggable then
            pcall(makeFloatable, entry, section)
        end
    end
    end -- floating elements block

    filterCurrentTabSearch = function(query)
        query = string.lower(query or "")
        for _, entry in ipairs(window._SearchItems) do
            if entry.Tab == currentTab and not entry.Floating then
                entry.Holder.Visible = query == "" or string.find(entry.Text, query, 1, true) ~= nil
            end
        end
    end

    searchBox:GetPropertyChangedSignal("Text"):Connect(function()
        if searchUi.Open then filterCurrentTabSearch(searchBox.Text) end
    end)

    -- ---------------------------------------------------------------
    -- HEADER SEARCH + TAB MENU (Gen 2)
    --   [ tab-menu button ] [ search bar ]   sits in the header, left of the settings / minimize / close buttons.
    --   * The search bar is always open, small and square with a darker UIStroke border (no icon to click).
    --   * The tab-menu button opens a small box that lists every tab (icon + name). Click one: it opens at once.
    -- (own block: keeps these locals out of the 200-locals limit of this big function)
    -- ---------------------------------------------------------------
    do
        local rightPad = window._HeaderTopbar and 16 or 11
        local group = new("Frame", {
            Name = "SearchGroup", BackgroundTransparency = 1, BorderSizePixel = 0,
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, -(rightPad + 97 + 8), 0, window._HeaderTopbar and 14 or 11),
            Size = UDim2.fromOffset(176, 29), ZIndex = 20,
        }, topBar)
        window._SearchGroup = group

        -- the old magnifier button is no longer needed: park it in a hidden holder (other code still sets its Visible)
        local parked = new("Frame", {Name = "Parked", BackgroundTransparency = 1, Visible = false, Size = UDim2.fromOffset(0, 0)}, main)
        searchButton.Parent = parked

        -- search bar -> header
        searchPanel.Parent = group
        searchPanel.Size = UDim2.new(0, 140, 1, 0)
        searchPanel.Position = UDim2.new(1, 0, 0.5, 0)
        searchPanel.AnchorPoint = Vector2.new(1, 0.5)
        local searchLine = window._SearchStroke
        searchBox.Focused:Connect(function()
            if searchLine then tween(searchLine, 0.16, {Color = lightUi and Color3.fromRGB(110, 116, 132) or Color3.fromRGB(96, 96, 106)}) end
        end)
        searchBox.FocusLost:Connect(function()
            if searchLine then tween(searchLine, 0.16, {Color = lightUi and Color3.fromRGB(170, 175, 186) or Color3.fromRGB(44, 44, 50)}) end
        end)

        -- tab-menu button (left of the search bar): a small 2 x 2 grid icon drawn in code
        local menuButton = new("TextButton", {
            Name = "TabMenuButton", AutoButtonColor = false, Text = "",
            BackgroundColor3 = elementBox, BackgroundTransparency = 0,
            Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(30, 29), ZIndex = 21,
        }, group)
        window._StyleButton(menuButton)
        local cells = {}
        do
            local gridHolder = new("Frame", {
                BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
                Size = UDim2.fromOffset(13, 13), ZIndex = 22,
            }, menuButton)
            for row = 0, 1 do
                for col = 0, 1 do
                    local cell = new("Frame", {
                        BackgroundColor3 = theme.Muted, BorderSizePixel = 0,
                        Position = UDim2.fromOffset(col * 7, row * 7), Size = UDim2.fromOffset(6, 6), ZIndex = 23,
                    }, gridHolder)
                    corner(cell, UDim.new(0, 2))
                    table.insert(cells, cell)
                end
            end
        end
        local menuOpen = false
        local function tintCells(color)
            for _, cell in ipairs(cells) do tween(cell, 0.16, {BackgroundColor3 = color}) end
        end
        menuButton.MouseEnter:Connect(function() tintCells(theme.Text) end)
        menuButton.MouseLeave:Connect(function() if not menuOpen then tintCells(theme.Muted) end end)

        -- the tab list box
        local catcher = new("TextButton", {
            Name = "TabMenuCatcher", AutoButtonColor = false, Text = "", BackgroundTransparency = 1,
            Size = UDim2.fromScale(1, 1), ZIndex = 58, Visible = false,
        }, main)
        local ROW_H, BOX_W = 32, 196
        local box = new("Frame", {
            Name = "TabMenu", BackgroundColor3 = lightUi and theme.Panel or Color3.fromRGB(17, 17, 20), BorderSizePixel = 0,
            Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(BOX_W, 60), ZIndex = 60, Visible = false,
        }, main)
        corner(box, UDim.new(0, CORNER_LARGE))
        stroke(box, lightUi and Color3.fromRGB(190, 194, 204) or Color3.fromRGB(60, 60, 66), 0.05, 1)
        local boxScale = addScale(box, 1)
        local boxList = new("ScrollingFrame", {
            BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(6, 6), Size = UDim2.new(1, -12, 1, -12),
            CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 0,
            ScrollingDirection = Enum.ScrollingDirection.Y, ZIndex = 61,
        }, box)
        new("UIListLayout", {Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder}, boxList)

        local function clearRows()
            for _, child in ipairs(boxList:GetChildren()) do
                if child:IsA("GuiObject") then child:Destroy() end
            end
        end

        local menuToken = 0
        local function closeMenu()
            if not menuOpen then return end
            menuOpen = false
            menuToken += 1
            local mine = menuToken
            catcher.Visible = false
            tintCells(theme.Muted)
            tween(boxScale, 0.14, {Scale = 0.94}, Enum.EasingStyle.Quint)
            task.delay(0.15, function()
                if mine == menuToken and box.Parent then box.Visible = false end
            end)
        end
        window._CloseTabMenu = closeMenu

        local function buildRows()
            clearRows()
            local shown = 0
            for index, tab in ipairs(window.Tabs) do
                shown += 1
                local active = currentTab == tab
                local row = new("TextButton", {
                    AutoButtonColor = false, Text = "", LayoutOrder = index,
                    BackgroundColor3 = lightUi and theme.Element or Color3.fromRGB(36, 36, 40),
                    BackgroundTransparency = active and 0 or 1, BorderSizePixel = 0,
                    Size = UDim2.new(1, 0, 0, ROW_H), ZIndex = 62,
                }, boxList)
                corner(row, UDim.new(0, CORNER_MEDIUM))
                local icon = makeIcon(row, tab.IconData, 16, active and theme.Text or theme.Muted, 64)
                local textLeft = 12
                if icon then
                    icon.AnchorPoint = Vector2.new(0, 0.5)
                    icon.Position = UDim2.new(0, 10, 0.5, 0)
                    textLeft = 34
                end
                local label = new("TextLabel", {
                    BackgroundTransparency = 1, Text = tab.Name, TextColor3 = active and theme.Text or theme.Muted,
                    Font = Enum.Font.GothamMedium, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
                    TextTruncate = Enum.TextTruncate.AtEnd,
                    Position = UDim2.fromOffset(textLeft, 0), Size = UDim2.new(1, -(textLeft + 44), 1, 0), ZIndex = 64,
                }, row)
                if tab.Side then
                    new("TextLabel", {
                        BackgroundTransparency = 1, Text = tab.Side, TextColor3 = theme.Faint or theme.Muted,
                        Font = Enum.Font.Gotham, TextSize = 9, TextXAlignment = Enum.TextXAlignment.Right,
                        AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 0), Size = UDim2.new(0, 36, 1, 0), ZIndex = 64,
                    }, row)
                end
                row.MouseEnter:Connect(function()
                    if currentTab ~= tab then
                        tween(row, 0.12, {BackgroundTransparency = 0.6})
                        tween(label, 0.12, {TextColor3 = theme.Text})
                        if icon then tween(icon, 0.12, {ImageColor3 = theme.Text}) end
                    end
                end)
                row.MouseLeave:Connect(function()
                    if currentTab ~= tab then
                        tween(row, 0.12, {BackgroundTransparency = 1})
                        tween(label, 0.12, {TextColor3 = theme.Muted})
                        if icon then tween(icon, 0.12, {ImageColor3 = theme.Muted}) end
                    end
                end)
                row.MouseButton1Click:Connect(function()
                    closeMenu()
                    selectTab(tab) -- opens at once
                end)
            end
            local height = math.clamp(shown * (ROW_H + 4) + 8, 44, 232)
            box.Size = UDim2.fromOffset(BOX_W, height)
            return shown
        end

        local function openMenu()
            if menuOpen or window.Destroyed then return end
            if #window.Tabs == 0 then return end
            if settingsPageOpen then closeSettingsPage() end
            buildRows()
            menuOpen = true
            menuToken += 1
            -- place it right under the button (position inside the window, measured from the button)
            local scale = math.max(mainScale.Scale, 0.01)
            local rel = (menuButton.AbsolutePosition - main.AbsolutePosition) / scale
            local x = math.clamp(rel.X, 6, math.max(6, windowWidth - BOX_W - 6))
            box.Position = UDim2.fromOffset(x, rel.Y + menuButton.AbsoluteSize.Y / scale + 6)
            boxScale.Scale = 0.94
            box.Visible = true
            catcher.Visible = true
            tintCells(theme.Text)
            tween(boxScale, 0.2, {Scale = 1}, Enum.EasingStyle.Quint)
        end
        menuButton.MouseButton1Click:Connect(function()
            if menuOpen then closeMenu() else openMenu() end
        end)
        catcher.MouseButton1Click:Connect(closeMenu)
        main:GetPropertyChangedSignal("Visible"):Connect(function() if not main.Visible then closeMenu() end end)
        function window:OpenTabMenu() openMenu() end
        function window:CloseTabMenu() closeMenu() end
    end

    -- ---------------------------------------------------------------
    -- Recolor system (the ColorPicker recolors live while it is edited; Settings > "Reset Window Theme" restores the originals):
    --   Toggle / Slider / Stat elements register themselves; the picker recolors one kind at a time.
    -- ---------------------------------------------------------------
    window._Recolor = {Toggle = {}, Slider = {}, Stat = {}}
    window._RecolorApplied = {} -- kind -> colour, so elements created later follow the applied colour

    local function registerRecolor(kind, entry)
        table.insert(window._Recolor[kind], entry)
        local applied = window._RecolorApplied[kind]
        if applied then entry.Apply(applied) end
    end

    -- white glow that flashes over an element when its colour is applied / reset
    local function flashGlow(object, radius)
        if not object or not object.Parent then return end
        local glow = new("Frame", {
            Name = "RecolorGlow", BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.55,
            BorderSizePixel = 0, Active = false, Size = UDim2.fromScale(1, 1), ZIndex = object.ZIndex + 6,
        }, object)
        corner(glow, radius or UDim.new(0, 14))
        local glowStroke = stroke(glow, Color3.new(1, 1, 1), 0.05, 2)
        tween(glow, 0.75, {BackgroundTransparency = 1}, Enum.EasingStyle.Quad)
        tween(glowStroke, 0.75, {Transparency = 1}, Enum.EasingStyle.Quad)
        task.delay(0.8, function() if glow.Parent then glow:Destroy() end end)
    end

    -- Reset Window Theme: every Toggle / Slider / Stat goes back to its original colour and the pickers show their start colour
    window._ThemePickers = {}
    function window:ResetTheme()
        local total = 0
        for kind, list in pairs(window._Recolor) do
            for index = #list, 1, -1 do
                local entry = list[index]
                if entry.Glow and entry.Glow.Parent then
                    entry.Reset()
                    flashGlow(entry.Glow, entry.Radius)
                    total += 1
                else
                    table.remove(list, index)
                end
            end
            window._RecolorApplied[kind] = nil
        end
        for index = #window._ThemePickers, 1, -1 do
            local picker = window._ThemePickers[index]
            if picker.Holder.Parent then picker.Reset() else table.remove(window._ThemePickers, index) end
        end
        return total
    end
    window.ResetWindowTheme = window.ResetTheme

    -- =================================================================
    -- FLOATING SIDE TABS   window:CreateLeftTab({ Title = "Combat", Icon = 93364949241311 })
    --                      window:CreateRightTab({ Title = "Combat", Icon = 93364949241311 })
    -- The tab menu is its OWN floating rail (separate tiles a small gap away from the window - it is not welded to the
    -- window). It is a child of the window, so it follows it when you move / scale it and hides with it. A rail only exists
    -- on the side(s) you create tabs on: Left only -> only the left rail, Right only -> only the right rail, both -> both. The tabs return the same object as window:CreateTab, so
    -- Section / Button / Toggle / Slider ... all work on them. Only floating tabs used -> the top tab bar is hidden.
    -- =================================================================
    do
        local panels = {} -- ["Left"] / ["Right"]  (a panel only exists once a tab was created on that side)
        local GAP, ROW_H, ROW_GAP = 10, 60, 8
        local MIN_W, MAX_W = 56, 92
        local EDGE = 2 -- room for the 1 px border of every tile

        -- the rail is a child of the window: it moves, scales and hides together with it (nothing is polled every frame)
        local function railPos(rec, shift)
            shift = shift or 0
            if rec.Side == "Left" then return UDim2.new(0, -GAP + shift, 0, 0) end
            return UDim2.new(1, GAP + shift, 0, 0)
        end

        local function makePanel(side)
            local rec = {Side = side, Tabs = {}, Width = MIN_W + EDGE * 2}
            rec.Body = new("Frame", {
                Name = "FloatTabs" .. side, BackgroundTransparency = 1, BorderSizePixel = 0, Active = false,
                AnchorPoint = side == "Left" and Vector2.new(1, 0) or Vector2.new(0, 0),
                Position = railPos(rec), Size = UDim2.fromOffset(rec.Width, ROW_H + EDGE * 2), ZIndex = 20,
            }, main)
            rec.List = new("ScrollingFrame", {
                Name = "Tabs", BackgroundTransparency = 1, BorderSizePixel = 0,
                Position = UDim2.fromOffset(0, 0), Size = UDim2.fromScale(1, 1),
                CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
                ScrollBarThickness = 0, ScrollingDirection = Enum.ScrollingDirection.Y, ZIndex = 21,
            }, rec.Body)
            new("UIListLayout", {Padding = UDim.new(0, ROW_GAP), SortOrder = Enum.SortOrder.LayoutOrder}, rec.List)
            new("UIPadding", {
                PaddingLeft = UDim.new(0, EDGE), PaddingRight = UDim.new(0, EDGE),
                PaddingTop = UDim.new(0, EDGE), PaddingBottom = UDim.new(0, EDGE),
            }, rec.List)
            return rec
        end

        -- slide out of the window's edge (used when the window finished opening / was restored)
        local function playIn()
            for _, rec in pairs(panels) do
                rec.Body.Position = railPos(rec, rec.Side == "Left" and 26 or -26)
                tween(rec.Body, 0.4, {Position = railPos(rec)}, Enum.EasingStyle.Quint)
            end
        end

        local railToken = 0
        window._RailsSetMin = function(minimizing)
            railToken += 1
            local mine = railToken
            if minimizing then
                for _, rec in pairs(panels) do rec.Body.Visible = false end
            else
                task.delay(0.32, function()
                    if mine ~= railToken or window.Destroyed or window._Minimized then return end
                    for _, rec in pairs(panels) do rec.Body.Visible = true end
                    playIn()
                end)
            end
        end
        -- the open animation clips the window; when it is over (ClipsDescendants off) the rails slide out
        main:GetPropertyChangedSignal("ClipsDescendants"):Connect(function()
            if not main.ClipsDescendants and main.Visible and not window._Minimized then playIn() end
        end)

        window._EnsureFloatPanel = function(side)
            side = (string.lower(tostring(side)) == "right") and "Right" or "Left"
            local rec = panels[side]
            if not rec then
                rec = makePanel(side)
                panels[side] = rec
                if window._Minimized then rec.Body.Visible = false end
            end
            return rec
        end

        -- width = the widest tab title; height = the tabs, never taller than the window
        window._FitFloatPanel = function(side)
            local rec = panels[side]
            if not rec then return end
            local widest = 0
            for _, other in ipairs(rec.Tabs) do widest = math.max(widest, other.Width or 0) end
            rec.Width = math.clamp(widest, MIN_W, MAX_W) + EDGE * 2
            local count = #rec.Tabs
            local height = count * ROW_H + math.max(count - 1, 0) * ROW_GAP + EDGE * 2
            rec.Body.Size = UDim2.fromOffset(rec.Width, math.min(height, math.max(windowHeight, ROW_H + EDGE * 2)))
        end
        window._FitRails = function()
            for side in pairs(panels) do window._FitFloatPanel(side) end
        end

        -- only floating tabs in use: the top tab bar is hidden and the pages use its space
        window._RefreshTabShell = function()
            if sidebarLayout then return end
            local hasTop = false
            for _, other in ipairs(window.Tabs) do
                if not other.Side then hasTop = true; break end
            end
            local hideTop = (not hasTop) and window._FloatTabsUsed == true
            window._TabShellWanted = not hideTop
            if not settingsPageOpen then tabShell.Visible = not hideTop end
            pages.Position = hideTop and UDim2.fromOffset(0, 2) or UDim2.fromOffset(0, 50)
            pages.Size = hideTop and UDim2.new(1, 0, 1, -2) or UDim2.new(1, 0, 1, -50)
        end

        function window:CreateLeftTab(tabConfig)
            if type(tabConfig) == "string" then tabConfig = {Title = tabConfig} end
            return window:CreateTab(tabConfig, "Left")
        end
        function window:CreateRightTab(tabConfig)
            if type(tabConfig) == "string" then tabConfig = {Title = tabConfig} end
            return window:CreateTab(tabConfig, "Right")
        end
    end

    function window:CreateTab(tabConfig, side)
        tabConfig = ci(tabConfig or {})
        if side == nil then side = tabConfig.side end
        if side ~= nil then side = (string.lower(tostring(side)) == "right") and "Right" or "Left" end
        local tab = {
            Name = tostring(tabConfig.name or ("Tab " .. (#window.Tabs + 1))),
            IconData = tabConfig.icon or "layout-dashboard",
            Sections = {},
            Order = 0,
            Side = side,
        }

        local verticalTab = sidebarLayout or side ~= nil
        local TAB_TEXT_LEFT = side and 7 or (verticalTab and 38 or 33) -- floating tabs are tiles: the title sits under the icon
        local TAB_RIGHT_PAD = side and 7 or (verticalTab and 12 or 14)
        local tabButton = new("TextButton", {
            AutoButtonColor = false,
            BackgroundColor3 = theme.Element,
            BackgroundTransparency = 1,
            Text = "",
            Size = verticalTab and UDim2.new(1, 0, 0, side and 60 or 46) or UDim2.fromOffset(64, 34),
            LayoutOrder = #window.Tabs + 1,
            ZIndex = 10,
        }, side and window._EnsureFloatPanel(side).List or tabBar)
        -- selected tab: light soft white effect (no border, no soft glow)
        local tabLight = isLightTheme(theme)
        local selectedBox = new("Frame", {
            BackgroundColor3 = Color3.new(1, 1, 1),
            BackgroundTransparency = 1,
            Size = UDim2.new(1, -2, 1, -2),
            Position = UDim2.fromOffset(1, 1),
            ClipsDescendants = true,
            Visible = false,
            ZIndex = 11,
        }, tabButton)
        -- sidebarLayout = true (Gen 2): tab buttons use UDim.new(0.5, 0) corners; the top tab bar keeps the full pill shape
        local TAB_CORNER = UDim.new(0, CORNER_MEDIUM) -- Gen 2: every tab uses the same small corner
        corner(selectedBox, TAB_CORNER)
        -- small grey border (UIStroke) on every tab button
        if side then
            -- floating tile: its own dark rounded button with the lit border (same look as every other button)
            tabButton.BackgroundColor3 = elementBox
            tabButton.BackgroundTransparency = 0
            window._StyleButton(tabButton)
        else
            corner(tabButton, TAB_CORNER)
            stroke(tabButton, tabLight and Color3.fromRGB(208, 210, 217) or Color3.fromRGB(72, 72, 78), 0.1, 1)
        end
        -- LIGHT SOFT WHITE EFFECT of a selected tab: stronger than the original (1 = original), the same for Effect = true AND false.
        local TAB_LIGHT = 2.2
        local function tabLow(alpha) return math.clamp(1 - (1 - alpha) * TAB_LIGHT, 0, 1) end
        -- white glass body: lit at the top, fading toward the bottom (light soft white effect, lowered: not too white)
        new("UIGradient", {
            Name = "TabSheen", Rotation = 90,
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
                ColorSequenceKeypoint.new(1, tabLight and Color3.fromRGB(235, 235, 235) or Color3.fromRGB(205, 205, 205)),
            }),
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, tabLow(tabLight and 0.5 or 0.93)),
                NumberSequenceKeypoint.new(1, tabLow(tabLight and 0.78 or 0.98)),
            }),
        }, selectedBox)
        -- (soft glow removed on purpose: no soft top light, no glowing bar)
        -- flash: bright white that fades out right after the click
        local selectedFlash = new("Frame", {
            BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, BorderSizePixel = 0,
            Size = UDim2.fromScale(1, 1), ZIndex = 12,
        }, selectedBox)
        corner(selectedFlash, TAB_CORNER)
        -- shine: a white light band that sweeps across the tab
        local selectedShine = new("Frame", {
            BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
            Size = UDim2.fromScale(1, 1), ZIndex = 12,
        }, selectedBox)
        corner(selectedShine, TAB_CORNER)
        local shineGradient = new("UIGradient", {
            Rotation = 20,
            Offset = Vector2.new(-1.3, 0),
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 1),
                NumberSequenceKeypoint.new(0.36, 1),
                NumberSequenceKeypoint.new(0.5, tabLow(tabLight and 0.78 or 0.92)),
                NumberSequenceKeypoint.new(0.64, 1),
                NumberSequenceKeypoint.new(1, 1),
            }),
        }, selectedShine)
        -- INNER LIGHT (instead of a light running around the outside of the box): the light soft white effect of a selected tab
        -- appears INSTANTLY and lives INSIDE the box. A soft light rim lines the inner edge (brighter at the top), a flash
        -- fades out and one shine sweeps across the inside. Nothing runs around the outside and nothing repeats by itself.
        local innerLight = new("Frame", {
            Name = "InnerLight", BackgroundTransparency = 1, BorderSizePixel = 0, Active = false,
            Position = UDim2.fromOffset(1, 1), Size = UDim2.new(1, -2, 1, -2), ZIndex = 13,
        }, selectedBox)
        corner(innerLight, TAB_CORNER)
        local innerStroke = new("UIStroke", {
            Color = tabLight and Color3.fromRGB(110, 116, 132) or Color3.new(1, 1, 1), Thickness = 4,
            Transparency = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        }, innerLight)
        new("UIGradient", {
            Rotation = 90,
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0.15),
                NumberSequenceKeypoint.new(0.55, 0.7),
                NumberSequenceKeypoint.new(1, 1),
            }),
        }, innerStroke)
        local INNER_REST = 0.82 -- how soft the inner rim stays while the tab is selected
        local function playInner(withSweep)
            if not fx.Enabled then
                innerStroke.Transparency = 1
                return
            end
            innerStroke.Transparency = 0.45 -- instant (no fade-in) ...
            tween(innerStroke, 0.5, {Transparency = INNER_REST}, Enum.EasingStyle.Quad) -- ... then it settles softly
            if withSweep then
                selectedFlash.BackgroundTransparency = tabLow(tabLight and 0.74 or 0.93)
                tween(selectedFlash, 0.45, {BackgroundTransparency = 1}, Enum.EasingStyle.Quad)
                shineGradient.Offset = Vector2.new(-1.3, 0)
                tween(shineGradient, 0.55, {Offset = Vector2.new(1.3, 0)}, Enum.EasingStyle.Quint)
            end
        end
        local fxToken = 0
        tab.TabFxIn = function()
            fxToken += 1
            selectedBox.Visible = true
            selectedBox.BackgroundTransparency = 0 -- instant, no fade-in
            playInner(true)
        end
        -- clicking the tab that is already selected plays the inner light once more
        tab.TabFxPulse = function()
            if selectedBox.Visible then playInner(true) end
        end
        tab.TabFxOut = function()
            fxToken += 1
            local token = fxToken
            innerStroke.Transparency = 1
            tween(selectedBox, 0.16, {BackgroundTransparency = 1})
            tween(selectedFlash, 0.16, {BackgroundTransparency = 1})
            task.delay(0.17, function()
                if token == fxToken and selectedBox.Parent then selectedBox.Visible = false end
            end)
        end
        local icon = makeIcon(tabButton, tab.IconData, side and 26 or 16, theme.Muted, 13) -- tile tabs: a BIGGER icon
        if icon then
            if side then
                icon.AnchorPoint = Vector2.new(0.5, 0)
                icon.Position = UDim2.new(0.5, 0, 0, 8)
            else
                icon.Position = sidebarLayout and UDim2.fromOffset(14, 15) or UDim2.fromOffset(10, 9)
            end
            addScale(icon, 1)
        end
        local tabText = new("TextLabel", {
            BackgroundTransparency = 1,
            Text = tab.Name,
            TextColor3 = theme.Muted,
            Font = Enum.Font.GothamMedium,
            TextSize = side and 9 or 11, -- tile tabs: a SMALL title under the icon
            TextTruncate = Enum.TextTruncate.AtEnd,
            TextXAlignment = side and Enum.TextXAlignment.Center or Enum.TextXAlignment.Left,
            Position = side and UDim2.new(0, 3, 0, 38) or UDim2.fromOffset(TAB_TEXT_LEFT, 0),
            Size = side and UDim2.new(1, -6, 0, 16) or UDim2.new(1, -(TAB_TEXT_LEFT + TAB_RIGHT_PAD), 1, 0),
            ZIndex = 14,
        }, tabButton)
        tab.TabButton = tabButton
        tab.SelectionBox = selectedBox

        tab.TabButton = tabButton
        tab.TabText = tabText
        tab.Icon = icon
        tab.Page, tab.List = buildPage(tab)

        table.insert(window.Tabs, tab)
        if side then table.insert(window._EnsureFloatPanel(side).Tabs, tab) end

        -- auto width: a short title stays compact, a longer title makes the tab wider to fit it
        local function measureTabText()
            local ok, size = pcall(function()
                return TextService:GetTextSize(tab.Name, tabText.TextSize, tabText.Font, Vector2.new(1000, 40))
            end)
            return ok and size.X or (#tab.Name * 6.5)
        end
        local function applyTabWidth(animate)
            tab.Width = math.ceil(measureTabText()) + 3 + TAB_TEXT_LEFT + TAB_RIGHT_PAD
            if side then
                window._FitFloatPanel(side)
            elseif sidebarLayout then
                relayoutSidebar(animate)
            else
                local target = UDim2.fromOffset(math.clamp(tab.Width, 58, 300), 34)
                if animate then
                    tween(tabButton, 0.2, {Size = target}, Enum.EasingStyle.Quint)
                else
                    tabButton.Size = target
                end
            end
        end
        applyTabWidth(false)

        function tab:SetName(newName)
            tab.Name = tostring(newName or tab.Name)
            tabText.Text = tab.Name
            applyTabWidth(true)
            return tab
        end
        function tab:GetName() return tab.Name end

        tabButton.MouseEnter:Connect(function()
            if currentTab ~= tab then
                tween(tabText, 0.15, {TextColor3 = theme.Text})
                if icon then tween(icon, 0.15, {ImageColor3 = theme.Text}) end
            end
        end)
        tabButton.MouseLeave:Connect(function()
            if currentTab ~= tab then
                tween(tabText, 0.15, {TextColor3 = theme.Muted})
                if icon then tween(icon, 0.15, {ImageColor3 = theme.Muted}) end
            end
        end)
        tabButton.MouseButton1Click:Connect(function() selectTab(tab) end)
        if #window.Tabs == 1 then task.defer(function() selectTab(tab) end) end
        if side then window._FloatTabsUsed = true end
        window._RefreshTabShell()

        -- every element creator (Section, Button, Toggle, ...) is attached to a "target":
        -- the tab itself, or one column (left / right) of a group
        local function attachElements(tab)
        -- V2 elements: float OUTSIDE the window (right side), draggable, with an automatic resize grip.
        -- Enabled = true shows, false hides. After tab:CreateSectionV2(...) the V2 elements go INSIDE that floating box
        -- (until tab:EndSectionV2()); Section:CreateXxxV2(...) always puts the element inside that box.
        local function currentSectionV2()
            local sectionV2 = rawget(tab, "_SectionV2")
            if sectionV2 and sectionV2._Alive then return sectionV2 end
            return nil
        end
        function tab:CreateSectionV2(sectionConfig)
            local sectionV2 = window._CreateFloatSection(tab, sectionConfig, attachElements)
            rawset(tab, "_SectionV2", sectionV2)
            return sectionV2
        end
        function tab:EndSectionV2() rawset(tab, "_SectionV2", nil) end
        function tab:CreateButtonV2(element)
            local sectionV2 = currentSectionV2()
            if sectionV2 then return sectionV2:CreateButtonV2(element) end
            return window._CreateFloatWidget("CreateButton", tab, element)
        end
        function tab:CreateToggleV2(element)
            local sectionV2 = currentSectionV2()
            if sectionV2 then return sectionV2:CreateToggleV2(element) end
            return window._CreateFloatWidget("CreateToggle", tab, element)
        end
        function tab:CreateSliderV2(element)
            local sectionV2 = currentSectionV2()
            if sectionV2 then return sectionV2:CreateSliderV2(element) end
            return window._CreateFloatWidget("CreateSlider", tab, element)
        end
        function tab:CreateInputV2(element)
            local sectionV2 = currentSectionV2()
            if sectionV2 then return sectionV2:CreateInputV2(element) end
            return window._CreateFloatWidget("CreateInput", tab, element)
        end

        -- TWO WAYS to use a section (both work, also mixed in one tab):
        --   1) as before: the section is a heading, the elements that follow it are made with the tab
        --        Tab:CreateSection({ Title = "Combat" })
        --        Tab:CreateToggle({ Title = "Aimbot" })
        --   2) NEW: the section is an object, make the elements with the SECTION (change Tab: to Section:)
        --        local Combat = Tab:CreateSection({ Title = "Combat" })
        --        Combat:CreateToggle({ Title = "Aimbot" })
        --      The elements always land under THEIR section, in the order they were created, even when other
        --      sections / elements are created in between. Section:SetName("..."), Section:SetVisible(false),
        --      Section:Destroy() (the heading) are there too.
        --   Without any section: Tab:CreateToggle(...) simply works, as always.
        -- Section options (every element created AFTER the section, until the next section, belongs to it):
        --   Draggable = true   -> hold an element (~0.4 s) and drag it OUT of the window: it floats on the screen
        --                         by itself, stays when the window is closed, and disappears when the UI library is deleted.
        --                         Once it floats you can drag it again WITHOUT holding (press + move); only taking it
        --                         out of the window needs the hold.
        --                         Any number of elements of the section can float. Hold + drag a floating element
        --                         back over the window and it returns to its original place in its section at once.
        --   Scale     = "1.00" -> the size of an element once it floats (1.00 = the same size, 0.8 = smaller, 1.3 = bigger)
        --   Resizable (automatic) -> with Draggable = true a floating element always shows a small grip icon in its
        --                         bottom-right corner: hold the grip and drag to change its width AND height. The size is
        --                         remembered while the UI library lives; back in the window it has its normal size.
        --                         (Resizable = false turns the grip off.)
        function tab:CreateSection(sectionConfig)
            sectionConfig = ci(sectionConfig or {})
            tab.Order += 1
            do
                local draggable = sectionConfig.draggable
                local scaleValue = tonumber(sectionConfig.scale) or 1
                local resizable = sectionConfig.resizable
                if draggable == true or draggable == "true" or draggable == 1 then
                    rawset(tab, "_FloatSection", {
                        Draggable = true,
                        Scale = math.clamp(scaleValue, 0.4, 3),
                        -- Resizable is automatic now (Draggable = true is enough); Resizable = false switches it off
                        Resizable = not (resizable == false or resizable == "false" or resizable == 0),
                    })
                else
                    rawset(tab, "_FloatSection", nil)
                end
            end
            local hasDescription = sectionConfig.description and tostring(sectionConfig.description) ~= ""
            local holder = new("Frame", {
                BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 0, hasDescription and 52 or 34),
                LayoutOrder = tab.Order,
                ZIndex = 9,
            }, tab.Page)
            local sectionIcon = makeIcon(holder, sectionConfig.icon, 15, lightUi and theme.Text or Color3.new(1, 1, 1), 11) -- Gen 2: sections are white, no theme colour
            local left = 11
            if sectionIcon then sectionIcon.Position = UDim2.fromOffset(11, 5); left = 32 end
            new("TextLabel", {
                BackgroundTransparency = 1,
                Text = tostring(sectionConfig.name or "Section"),
                TextColor3 = theme.Text,
                Font = Enum.Font.GothamBold,
                TextSize = 12,
                TextXAlignment = Enum.TextXAlignment.Left,
                Position = UDim2.fromOffset(left, 2),
                Size = UDim2.new(1, -left, 0, 20),
                ZIndex = 10,
            }, holder)
            if hasDescription then
                new("TextLabel", {
                    BackgroundTransparency = 1,
                    Text = tostring(sectionConfig.description),
                    TextColor3 = theme.Muted,
                    Font = Enum.Font.Gotham,
                    TextSize = 10,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    TextTruncate = Enum.TextTruncate.AtEnd,
                    Position = UDim2.fromOffset(left, 22),
                    Size = UDim2.new(1, -left, 0, 18),
                    ZIndex = 10,
                }, holder)
            end
            -- SYSTEM 2: the section is a target of its own. Its elements are numbered inside a reserved block of
            -- LayoutOrders right after the heading, so they always stay under it (see the comment above).
            local SECTION_BLOCK = 10000
            local base = tab.Order
            local target = setmetatable({Page = tab.Page, Order = base, Owner = tab.Owner or tab, Frame = tab.Frame, Holder = holder}, {
                __index = function(_, key)
                    if key == "Name" then return tab.Name end -- flags / save keys use the name of the tab
                    return nil
                end,
            })
            rawset(target, "_FloatSection", rawget(tab, "_FloatSection")) -- Draggable / Scale of THIS section
            attachElements(target) -- target:CreateToggle / CreateButton / CreateSlider / ...
            tab.Order = base + SECTION_BLOCK -- what the tab creates next goes after this section's block
            function target:SetName(text)
                for _, child in ipairs(holder:GetChildren()) do
                    if child:IsA("TextLabel") and child.Font == Enum.Font.GothamBold then child.Text = tostring(text); break end
                end
            end
            target.SetTitle = target.SetName
            function target:SetVisible(value) holder.Visible = value ~= false end
            function target:Destroy() holder:Destroy() end
            return target
        end


        -- ---------------------------------------------------------------
        -- Note (paragraph): a title + a wrapped text under it. The box grows with the text.
        --   Tab:CreateNote({ Title = "Note", Note = "Your first UI library" })
        --   Tab:CreateNote("just a text")                       (short form)
        --   optional: Color = Color3 (the little bar on the left)
        --   local note = Tab:CreateNote({...});  note:Set({Title = "...", Note = "..."})
        --   note:SetTitle("...")  note:SetNote("...")  note:Get() -> title, note   note:Destroy()
        -- (CreateParagraph is the same function)
        -- ---------------------------------------------------------------
        function tab:CreateNote(element)
            if type(element) == "string" then element = {Note = element} end
            element = ci(type(element) == "table" and element or {})
            tab.Order += 1
            local function pick(...)
                for _, key in ipairs({...}) do
                    if element[key] ~= nil then return tostring(element[key]) end
                end
            end
            local titleText = pick("Title", "title", "Name", "name") or "Note"
            local bodyText = pick("Note", "note", "Text", "text", "Content", "content", "Description", "description") or ""
            local box = new("Frame", {
                Name = "Note",
                BackgroundColor3 = elementBox,
                Size = UDim2.new(1, 0, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                LayoutOrder = tab.Order,
                ZIndex = 9,
            }, tab.Page)
            styleElementBox(box, 11)
            local accent = typeof(element.Color) == "Color3" and element.Color or (typeof(element.color) == "Color3" and element.color or theme.Accent2)
            local bar = new("Frame", {
                Name = "NoteBar", BackgroundColor3 = accent, BorderSizePixel = 0, Active = false,
                Position = UDim2.fromOffset(12, 12), Size = UDim2.new(0, 3, 1, -24), ZIndex = 11,
            }, box)
            corner(bar, UDim.new(1, 0))
            -- text lives in its own holder: the layout / padding must not touch the box's light + sheen layers
            local inner = new("Frame", {
                BackgroundTransparency = 1, BorderSizePixel = 0, Active = false,
                Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 10,
            }, box)
            new("UIPadding", {
                PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 13),
                PaddingLeft = UDim.new(0, 24), PaddingRight = UDim.new(0, 14),
            }, inner)
            new("UIListLayout", {Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder}, inner)
            local titleLabel = new("TextLabel", {
                BackgroundTransparency = 1, Text = titleText, TextColor3 = theme.Text,
                Font = Enum.Font.GothamBold, TextSize = 12, TextWrapped = true,
                TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
                Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
                LayoutOrder = 1, Visible = titleText ~= "", ZIndex = 11,
            }, inner)
            local bodyLabel = new("TextLabel", {
                BackgroundTransparency = 1, Text = bodyText, TextColor3 = theme.Muted,
                Font = Enum.Font.Gotham, TextSize = 11, TextWrapped = true, LineHeight = 1.12,
                TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
                Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
                LayoutOrder = 2, Visible = bodyText ~= "", ZIndex = 11,
            }, inner)
            registerSearchItem(tab, box, titleText, bodyText)
            local searchEntry = window._SearchItems[#window._SearchItems]
            local note = {Frame = box}
            local function refreshSearch()
                if searchEntry then searchEntry.Text = string.lower(titleLabel.Text .. " " .. bodyLabel.Text) end
            end
            function note:SetTitle(text)
                titleLabel.Text = tostring(text or "")
                titleLabel.Visible = titleLabel.Text ~= ""
                refreshSearch()
                return note
            end
            function note:SetNote(text)
                bodyLabel.Text = tostring(text or "")
                bodyLabel.Visible = bodyLabel.Text ~= ""
                refreshSearch()
                return note
            end
            function note:Set(data)
                if type(data) == "string" then return note:SetNote(data) end
                data = type(data) == "table" and data or {}
                local newTitle = data.Title
                if newTitle == nil then newTitle = data.title end
                local newBody = data.Note
                if newBody == nil then newBody = data.note end
                if newBody == nil then newBody = data.Text end
                if newTitle ~= nil then note:SetTitle(newTitle) end
                if newBody ~= nil then note:SetNote(newBody) end
                if typeof(data.Color) == "Color3" then bar.BackgroundColor3 = data.Color end
                return note
            end
            function note:Get() return titleLabel.Text, bodyLabel.Text end
            function note:Destroy() box:Destroy() end
            return note
        end
        tab.CreateParagraph = tab.CreateNote

        -- NEW BUTTON (Gen 2 rework, the "Scan QR" look): dark glass fill, light border, icon + title together in the
        -- middle (description under the title). Icon = lucide name / asset id. Background = picture behind the button.
        function tab:CreateButton(element)
            element = ci(element or {})
            tab.Order += 1
            local hasDescription = element.description and tostring(element.description) ~= ""
            local height = hasDescription and 54 or 40
            local button = new("TextButton", {
                AutoButtonColor = false,
                BackgroundColor3 = elementBox,
                Text = "",
                Size = UDim2.new(1, 0, 0, height),
                LayoutOrder = tab.Order,
                ZIndex = 9,
            }, tab.Page)
            local buttonLine = window._StyleButton(button)
            -- Background = "rbxassetid://1234" (or 1234): a picture behind the whole button, cropped to its rounded shape.
            --   BackgroundDim = 0.35 (0 .. 1): how dark the picture is made so the title stays readable (0 = no dimming).
            local backgroundValue = element.background
            local backgroundImage
            if typeof(backgroundValue) == "number" then
                backgroundImage = "rbxassetid://" .. tostring(backgroundValue)
            elseif type(backgroundValue) == "string" and backgroundValue ~= "" then
                if backgroundValue:match("^%d+$") then
                    backgroundImage = "rbxassetid://" .. backgroundValue
                elseif backgroundValue:match("^rbxassetid://") or backgroundValue:match("^rbxasset://") or backgroundValue:match("^https?://") then
                    backgroundImage = backgroundValue
                end
            end
            local backgroundShade
            local shadeRest = 1
            if backgroundImage then
                local dim = math.clamp(tonumber(element.backgrounddim) or 0.35, 0, 1)
                shadeRest = 1 - dim
                local picture = new("ImageLabel", {
                    Name = "Background", BackgroundTransparency = 1, Active = false, Image = backgroundImage,
                    ScaleType = Enum.ScaleType.Crop, Size = UDim2.fromScale(1, 1), ZIndex = 9,
                }, button)
                corner(picture, UDim.new(0, CORNER_MEDIUM))
                backgroundShade = new("Frame", {
                    Name = "BackgroundShade", BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = shadeRest,
                    BorderSizePixel = 0, Active = false, Size = UDim2.fromScale(1, 1), ZIndex = 9,
                }, button)
                corner(backgroundShade, UDim.new(0, CORNER_MEDIUM))
                local topLight = button:FindFirstChild("TopLight")
                if topLight then topLight.ZIndex = 10 end -- the light soft white effect stays on top of the picture
            end
            -- icon + title (+ description) as one centered group
            local iconValue = element.Icon
            if iconValue == nil then iconValue = element.icon end
            local group = new("Frame", {
                Name = "Content", BackgroundTransparency = 1, BorderSizePixel = 0,
                AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
                Size = UDim2.new(1, -28, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 10,
            }, button)
            new("UIListLayout", {
                FillDirection = Enum.FillDirection.Vertical, HorizontalAlignment = Enum.HorizontalAlignment.Center,
                VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2),
            }, group)
            local pressScale = addScale(group, 1)
            local row = new("Frame", {
                Name = "Row", BackgroundTransparency = 1, BorderSizePixel = 0,
                Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 1, ZIndex = 10,
            }, group)
            new("UIListLayout", {
                FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
                VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8),
            }, row)
            local actionIcon
            if iconValue ~= nil and resolveIcon(iconValue) ~= nil then
                actionIcon = makeIcon(row, iconValue, 18, theme.Text, 12)
                if actionIcon then actionIcon.LayoutOrder = 1 end
            end
            new("TextLabel", {
                Name = "Title", BackgroundTransparency = 1, Text = tostring(element.name or "Button"),
                TextColor3 = theme.Text, Font = Enum.Font.GothamMedium, TextSize = 13,
                Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2, ZIndex = 12,
            }, row)
            if hasDescription then
                new("TextLabel", {
                    Name = "Description", BackgroundTransparency = 1, Text = tostring(element.description),
                    TextColor3 = theme.Muted, Font = Enum.Font.Gotham, TextSize = 10, TextWrapped = true,
                    TextXAlignment = Enum.TextXAlignment.Center,
                    Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, ZIndex = 12,
                }, group)
            end
            local lineRest = buttonLine.Color
            local lineHover = lightUi and Color3.fromRGB(140, 144, 158) or Color3.fromRGB(128, 128, 136)
            button.MouseEnter:Connect(function()
                tween(button, 0.15, {BackgroundColor3 = elementBoxHover})
                tween(buttonLine, 0.15, {Color = lineHover})
                if backgroundShade then tween(backgroundShade, 0.15, {BackgroundTransparency = math.min(1, shadeRest + 0.12)}) end
                if actionIcon then actionIcon.ImageColor3 = theme.Accent2 end -- instant, the icon never slides
            end)
            button.MouseLeave:Connect(function()
                tween(button, 0.15, {BackgroundColor3 = elementBox})
                tween(buttonLine, 0.15, {Color = lineRest})
                tween(pressScale, 0.12, {Scale = 1}, Enum.EasingStyle.Quad)
                if backgroundShade then tween(backgroundShade, 0.15, {BackgroundTransparency = shadeRest}) end
                if actionIcon then actionIcon.ImageColor3 = theme.Text end
            end)
            button.MouseButton1Down:Connect(function() tween(pressScale, 0.08, {Scale = 0.95}, Enum.EasingStyle.Quad) end)
            button.MouseButton1Up:Connect(function() tween(pressScale, 0.18, {Scale = 1}, Enum.EasingStyle.Back) end)
            button.MouseButton1Click:Connect(function()
                if actionIcon then iconPop(actionIcon) end
                if typeof(element.callback) == "function" then Security.spawn(element.callback) end
            end)
            registerSearchItem(tab, button, element.name or "Button", element.description)
            return button
        end

        function tab:CreateToggle(element)
            element = ci(element or {})
            tab.Order += 1
            local initialValue = element.value
            if initialValue == nil then initialValue = element.Value end
            local state = initialValue == true
            local hasDescription = element.description and tostring(element.description) ~= ""
            local height = hasDescription and 60 or 48
            local button = new("TextButton", {
                AutoButtonColor = false,
                BackgroundColor3 = elementBox,
                Text = "",
                Size = UDim2.new(1, 0, 0, height),
                LayoutOrder = tab.Order,
                ZIndex = 9,
            }, tab.Page)
            styleElementBox(button, 11)
            setTextPair(button, element.name or "Toggle", element.description, theme, 8, -80, 10, nil, height)

            local track = new("Frame", {
                BackgroundColor3 = isDefaultTheme and theme.ToggleBackground or theme.Panel2,
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, -14, 0.5, 0),
                Size = UDim2.fromOffset(46, 22), -- Gen 2: smaller knob box
                ZIndex = 11,
            }, button)
            corner(track, UDim.new(1, 0))
            local trackStroke = stroke(track, isDefaultTheme and theme.ToggleDisabledOuterStroke or Color3.fromRGB(104, 106, 114), 0.08, 1)
            local knob = new("Frame", {
                BackgroundColor3 = Color3.fromRGB(255, 255, 255),
                AnchorPoint = Vector2.new(0, 0.5),
                Position = UDim2.new(0, 3, 0.5, 0),
                Size = UDim2.fromOffset(22, 16), -- Gen 2: smaller knob
                ZIndex = 12,
            }, track)
            corner(knob, UDim.new(1, 0))
            -- KNOB: OFF = darker grey + a soft light soft white effect. ON = the colour of the theme the UI library uses (green on
            -- Default, the accent on the other themes) + a stronger light soft white effect + the ambient glow (see addKnobGlow).
            local knobOffColor = knobOffColorFor(lightUi)
            knob.BackgroundColor3 = knobOffColor
            local knobStroke = stroke(knob, Color3.new(1, 1, 1), 0.82, 1)

            local knobOnColor = isDefaultTheme and theme.ToggleEnabled or theme.Accent
            local knobOnOriginal = knobOnColor
            local knobGlow = addKnobGlow(knob, function() return fx.Enabled end, lightUi, knobStroke)
            local function paintKnob(on, color)
                tween(knob, 0.22, {BackgroundColor3 = on and color or knobOffColor}, Enum.EasingStyle.Quint)
            end
            registerRecolor("Toggle", {
                Glow = button, Radius = UDim.new(0, 14),
                Apply = function(c) knobOnColor = c; if state then paintKnob(true, c); knobGlow.Recolor(c) end end,
                Reset = function() knobOnColor = knobOnOriginal; if state then paintKnob(true, knobOnOriginal); knobGlow.Recolor(knobOnOriginal) end end,
            })
            local listeners = {}
            local syncListeners = {} -- run on EVERY change, also Set(v, false) and Load (used by Toggle:CreateSectionV2 ...)
            local function apply(stateValue, fire)
                state = stateValue == true
                local x = state and UDim2.new(1, -25, 0.5, 0) or UDim2.new(0, 3, 0.5, 0)
                -- ONLY the knob changes: dark + soft light (off) -> theme colour + stronger light (on).
                -- The track and its outline never change.
                tween(knob, 0.22, {Position = x}, Enum.EasingStyle.Quint)
                paintKnob(state, knobOnColor)
                knobGlow.Show(state, false, knobOnColor)
                for _, sync in ipairs(syncListeners) do pcall(sync, state) end
                if fire then
                    local callback = element.callback
                    if typeof(callback) ~= "function" then callback = element.Callback end
                    if typeof(callback) == "function" then Security.spawn(callback, state) end
                    for _, listener in ipairs(listeners) do Security.spawn(listener, state) end
                end
            end
            apply(state, false)
            button.MouseEnter:Connect(function() tween(button, 0.15, {BackgroundColor3 = elementBoxHover}) end)
            button.MouseLeave:Connect(function() tween(button, 0.15, {BackgroundColor3 = elementBox}) end)
            button.MouseButton1Click:Connect(function() apply(not state, true) end)

            -- Control the toggle from anywhere (another Button, Dropdown, Slider, a loop...):
            --   toggle:Set(true)          set true/false (runs the toggle's callback)
            --   toggle:Set(true, false)   set without running the callback
            --   toggle:Toggle()           flip it
            --   toggle.Value = true       same as Set(true)
            --   toggle:Get() / toggle.Value  read the state
            --   toggle:OnChanged(fn)      extra listener, fn(state)
            local api
            api = setmetatable({}, {
                __index = function(_, key)
                    if key == "Value" or key == "value" then return state end
                end,
                __newindex = function(t, key, v)
                    if key == "Value" or key == "value" then
                        t:Set(v)
                    else
                        rawset(t, key, v)
                    end
                end,
            })
            function api:Set(value, fire)
                apply(value == true, fire ~= false)
                return api
            end
            api.SetValue = api.Set
            function api:Toggle(fire)
                apply(not state, fire ~= false)
                return api
            end
            function api:Get()
                return state
            end
            function api:OnChanged(fn)
                if typeof(fn) == "function" then table.insert(listeners, fn) end
                return api
            end
            function api._OnState(fn)
                if typeof(fn) == "function" then table.insert(syncListeners, fn) end
            end
            do local flagName = getFlag(element, "Toggle", tab.Name, window._StateEntries); if flagName then window:_Register(flagName, api) end end
            registerSearchItem(tab, button, element.name or "Toggle", element.description)
            return api
        end

        function tab:CreateDropdown(element)
            element = ci(element or {})
            tab.Order += 1
            -- An option can be a string / number / boolean, an Instance (its Name is shown, e.g. a Player) or a table
            -- with Name / Text / Label. The callback always receives the ORIGINAL option (Instance, table...).
            local function keyOf(option)
                local kind = typeof(option)
                if kind == "Instance" then return option.Name end
                if kind == "table" then
                    option = ci(option)
                    local label = option.Name or option.Text or option.Label or option.Title
                    if label ~= nil then return tostring(label) end
                end
                return tostring(option)
            end
            -- options = {...}  OR  options = function() return {...} end  (a function is re-read every time the list opens)
            local optionsSource = element.options
            local options = {}
            local function loadOptions(list)
                options = {}
                local seen = {}
                if type(list) == "table" then
                    for _, option in ipairs(list) do
                        local key = keyOf(option)
                        if key ~= "" and not seen[key] then -- empty and duplicate names are skipped
                            seen[key] = true
                            table.insert(options, option)
                        end
                    end
                end
            end
            local function pullSource()
                if type(optionsSource) ~= "function" then return false end
                local ok, result = pcall(optionsSource)
                if ok and type(result) == "table" then loadOptions(result) return true end
                return false
            end
            if type(optionsSource) == "function" then pullSource() else loadOptions(optionsSource) end
            local placeholder = element.placeholder and tostring(element.placeholder) or "Select..."
            local selected = {}
            local function applyValue(value)
                table.clear(selected)
                if element.multiSelect then
                    for _, item in ipairs(type(value) == "table" and value or {value}) do selected[keyOf(item)] = true end
                elseif value ~= nil then
                    selected[keyOf(value)] = true
                end
            end
            applyValue(element.value)

            local hasDescription = element.description and tostring(element.description) ~= ""
            local closedHeight = hasDescription and 68 or 54
            local holder = new("Frame", {
                BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 0, closedHeight),
                LayoutOrder = tab.Order,
                ClipsDescendants = true,
                ZIndex = 12,
            }, tab.Page)
            local button = new("TextButton", {
                AutoButtonColor = false,
                BackgroundColor3 = elementBox,
                Text = "",
                Size = UDim2.new(1, 0, 0, closedHeight),
                ZIndex = 13,
            }, holder)
            styleElementBox(button, 11)
            setTextPair(button, element.name or "Dropdown", element.description, theme, 7, -140, 14, nil, closedHeight)

            local valueLabel = new("TextLabel", {
                BackgroundTransparency = 1,
                Text = placeholder,
                TextColor3 = theme.Muted,
                Font = Enum.Font.Gotham,
                TextSize = 10,
                TextTruncate = Enum.TextTruncate.AtEnd,
                TextXAlignment = Enum.TextXAlignment.Right,
                Position = UDim2.new(0.42, 0, hasDescription and 0 or 0.5, hasDescription and 42 or -8),
                Size = UDim2.new(0.52, -30, 0, 18),
                ZIndex = 15,
            }, button)
            local arrow = makeIcon(button, "chevron-down", 16, theme.Muted, 16)
            if arrow then arrow.AnchorPoint = Vector2.new(0.5, 0.5); arrow.Position = UDim2.new(1, -16, 0.5, 0) end

            local open = false
            local searchQuery = ""
            local expandedHeight = closedHeight
            local api = {}

            -- "Select all" / "Clear all" buttons under the search box.
            --   multiSelect dropdowns: both buttons are there by default (SelectAll = false / ClearAll = false hides one).
            --   single-select dropdowns: no buttons, unless ClearAll = true (a "Clear all" button that empties the choice).
            -- While a search is active the buttons work on the options that are listed (the matches).
            local showSelectAll = element.multiSelect and element.selectall ~= false
            local showClearAll = (element.multiSelect and element.clearall ~= false) or element.clearall == true
            local actionH = (showSelectAll or showClearAll) and 30 or 0

            -- search bar = the same bar as the window's search drawer: a pill with the light soft white effect (glass sheen +
            -- soft top light), the drawn magnifier on the left, no border
            local searchShell = new("Frame", {
                BackgroundColor3 = elementBox,
                BorderSizePixel = 0,
                Position = UDim2.fromOffset(8, closedHeight - 10),
                Size = UDim2.new(1, -16, 0, 34),
                Visible = false,
                ZIndex = 16,
            }, holder)
            styleElementBox(searchShell, 17) -- radius 17 = half of the 34 px bar = full pill
            local searchIcon = drawMagnifier(searchShell, 14, theme.Muted, 18)
            searchIcon.Position = UDim2.new(0, 20, 0.5, 0)
            local search = new("TextBox", {
                BackgroundTransparency = 1,
                ClearTextOnFocus = false,
                PlaceholderText = "Search options...",
                PlaceholderColor3 = theme.Muted,
                Text = "",
                TextColor3 = theme.Text,
                Font = Enum.Font.Gotham,
                TextSize = 11,
                TextXAlignment = Enum.TextXAlignment.Left,
                Position = UDim2.fromOffset(36, 0),
                Size = UDim2.new(1, -48, 1, 0),
                ZIndex = 18,
            }, searchShell)

            local list = new("ScrollingFrame", {
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                Position = UDim2.fromOffset(8, closedHeight + 31 + actionH),
                Size = UDim2.new(1, -16, 0, 0),
                CanvasSize = UDim2.new(),
                AutomaticCanvasSize = Enum.AutomaticSize.Y,
                ScrollBarThickness = 0,
                ScrollBarImageColor3 = theme.Accent,
                ScrollingDirection = Enum.ScrollingDirection.Y,
                ZIndex = 17,
                Visible = false,
            }, holder)
            new("UIListLayout", {Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder}, list)

            local actions
            if actionH > 0 then
                actions = new("Frame", {
                    BackgroundTransparency = 1,
                    Position = UDim2.fromOffset(8, closedHeight + 10),
                    Size = UDim2.new(1, -16, 0, 26),
                    Visible = false,
                    ZIndex = 16,
                }, holder)
                local function actionButton(text, iconName, order, onClick)
                    local count = (showSelectAll and 1 or 0) + (showClearAll and 1 or 0)
                    local buttonObject = new("TextButton", {
                        AutoButtonColor = false, BackgroundColor3 = elementBox,
                        Text = text, TextColor3 = theme.Muted, Font = Enum.Font.GothamMedium, TextSize = 10,
                        Size = count == 2 and UDim2.new(0.5, -3, 1, 0) or UDim2.fromScale(1, 1),
                        Position = (count == 2 and order == 2) and UDim2.new(0.5, 3, 0, 0) or UDim2.new(),
                        ZIndex = 18,
                    }, actions)
                    styleElementBox(buttonObject, 13) -- same pill look as the search bar (light soft white effect, no border)
                    local iconObject = makeIcon(buttonObject, iconName, 12, theme.Muted, 19)
                    if iconObject then
                        iconObject.AnchorPoint = Vector2.new(0, 0.5)
                        iconObject.Position = UDim2.new(0, 10, 0.5, 0)
                        new("UIPadding", {PaddingLeft = UDim.new(0, 14)}, buttonObject)
                    end
                    buttonObject.MouseEnter:Connect(function()
                        tween(buttonObject, 0.12, {BackgroundColor3 = elementBoxHover, TextColor3 = theme.Text})
                        if iconObject then tween(iconObject, 0.12, {ImageColor3 = theme.Accent2}) end
                    end)
                    buttonObject.MouseLeave:Connect(function()
                        tween(buttonObject, 0.12, {BackgroundColor3 = elementBox, TextColor3 = theme.Muted})
                        if iconObject then tween(iconObject, 0.12, {ImageColor3 = theme.Muted}) end
                    end)
                    buttonObject.MouseButton1Click:Connect(onClick)
                    return buttonObject
                end
                local order = 0
                if showSelectAll then
                    order += 1
                    actionButton("Select all", "check-check", order, function() api:_ApplyToListed(true) end)
                end
                if showClearAll then
                    order += 1
                    actionButton("Clear all", "x", order, function() api:_ApplyToListed(false) end)
                end
            end

            local function getSelectedText()
                local chosen = {}
                for _, item in ipairs(options) do
                    if selected[keyOf(item)] then table.insert(chosen, keyOf(item)) end
                end
                if #chosen == 0 then return placeholder end
                if #chosen <= 2 then return table.concat(chosen, ", ") end
                return tostring(#chosen) .. " selected"
            end

            local function updateValue()
                valueLabel.Text = getSelectedText()
            end
            updateValue()

            local function visibleOptions(query)
                local result = {}
                for _, option in ipairs(options) do
                    local text = keyOf(option)
                    if query == "" or string.find(string.lower(text), string.lower(query), 1, true) then
                        table.insert(result, option)
                    end
                end
                return result
            end

            local function refreshRows(query, keepScroll)
                local previousScroll = list.CanvasPosition
                for _, child in ipairs(list:GetChildren()) do
                    if child:IsA("GuiButton") or child:IsA("TextLabel") then child:Destroy() end
                end
                local matches = visibleOptions(query or "")
                if #matches == 0 then
                    new("TextLabel", {
                        BackgroundTransparency = 1,
                        Text = "No matching options",
                        TextColor3 = theme.Muted,
                        Font = Enum.Font.Gotham,
                        TextSize = 10,
                        Size = UDim2.new(1, 0, 0, 34),
                        ZIndex = 18,
                    }, list)
                else
                    for index, option in ipairs(matches) do
                        local text = keyOf(option)
                        local row = new("TextButton", {
                            AutoButtonColor = false,
                            BackgroundColor3 = selected[text] and (isDefaultTheme and theme.DropdownSelected or theme.AccentDark) or (isDefaultTheme and theme.DropdownUnselected or elementBox),
                            BackgroundTransparency = 0.03,
                            Text = "",
                            Size = UDim2.new(1, -2, 0, 34),
                            LayoutOrder = index,
                            ZIndex = 18,
                        }, list)
                        corner(row, UDim.new(0, 8))
                        if isDefaultTheme then
                            new("UIGradient", {
                                Name = "DefaultDropdownRowLight",
                                Rotation = 90,
                                Color = ColorSequence.new({
                                    ColorSequenceKeypoint.new(0, Color3.fromRGB(62, 63, 68)),
                                    ColorSequenceKeypoint.new(0.48, Color3.fromRGB(56, 57, 62)),
                                    ColorSequenceKeypoint.new(0.53, Color3.fromRGB(46, 47, 52)),
                                    ColorSequenceKeypoint.new(1, Color3.fromRGB(40, 41, 46)),
                                }),
                            }, row)
                        else
                            -- other themes: the same glass sheen the element boxes have
                            new("UIGradient", {
                                Name = "ElementSheen",
                                Rotation = 90,
                                Color = ColorSequence.new({
                                    ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
                                    ColorSequenceKeypoint.new(1, lightUi and Color3.fromRGB(240, 240, 240) or Color3.fromRGB(214, 214, 214)),
                                }),
                            }, row)
                        end
                        -- light soft white effect on every option, in every theme (a little stronger on the selected ones)
                        addTopLight(row, UDim.new(0, 8), row.ZIndex, selected[text] and 1.6 or 1)
                        local rowIcon = makeIcon(row, selected[text] and "check" or (element.optionIcon or "circle"), 14, selected[text] and theme.Accent2 or theme.Faint, 20)
                        if rowIcon then rowIcon.AnchorPoint = Vector2.new(0, 0.5); rowIcon.Position = UDim2.new(0, 10, 0.5, 0) end
                        new("TextLabel", {
                            BackgroundTransparency = 1,
                            Text = text,
                            TextColor3 = selected[text] and theme.Text or theme.Muted,
                            Font = Enum.Font.GothamMedium,
                            TextSize = 10,
                            TextTruncate = Enum.TextTruncate.AtEnd,
                            TextXAlignment = Enum.TextXAlignment.Left,
                            Position = UDim2.fromOffset(32, 0),
                            Size = UDim2.new(1, -42, 1, 0),
                            ZIndex = 20,
                        }, row)
                        row.MouseEnter:Connect(function() tween(row, 0.12, {BackgroundColor3 = selected[text] and (isDefaultTheme and theme.DropdownSelected or theme.AccentDark) or (isDefaultTheme and theme.ElementBackgroundHover or elementBoxHover)}) end)
                        row.MouseLeave:Connect(function() tween(row, 0.12, {BackgroundColor3 = selected[text] and (isDefaultTheme and theme.DropdownSelected or theme.AccentDark) or (isDefaultTheme and theme.DropdownUnselected or elementBox)}) end)
                        row.MouseButton1Click:Connect(function()
                            if element.multiSelect then
                                selected[text] = not selected[text]
                            else
                                table.clear(selected)
                                selected[text] = true
                            end
                            updateValue()
                            if typeof(element.callback) == "function" then
                                if element.multiSelect then
                                    local values = {}
                                    for _, item in ipairs(options) do if selected[keyOf(item)] then table.insert(values, item) end end
                                    Security.spawn(element.callback, values)
                                else
                                    Security.spawn(element.callback, option)
                                end
                            end
                            refreshRows(search.Text, true)
                            if not element.multiSelect then
                                api:Close()
                            end
                        end)
                    end
                end
                if keepScroll then
                    -- the rows were rebuilt: put the list back where it was (multi select no longer jumps to the top)
                    task.defer(function()
                        if not list.Parent then return end
                        local maxY = math.max(0, list.AbsoluteCanvasSize.Y - list.AbsoluteWindowSize.Y)
                        list.CanvasPosition = Vector2.new(0, math.min(previousScroll.Y, maxY))
                    end)
                end
            end

            local function recomputeHeight()
                local count = #visibleOptions(searchQuery)
                local listHeight = math.clamp(math.max(1, math.min(count, 6)) * 38, 38, 228)
                expandedHeight = closedHeight + 48 + actionH + listHeight + 8
                if open then
                    tween(holder, 0.28, {Size = UDim2.new(1, 0, 0, expandedHeight)}, Enum.EasingStyle.Quint)
                    tween(list, 0.28, {Size = UDim2.new(1, -16, 0, listHeight)}, Enum.EasingStyle.Quint)
                else
                    list.Size = UDim2.new(1, -16, 0, listHeight)
                end
            end

            local function openDropdown()
                if open then
                    api:Close()
                    return
                end
                if window._ActiveDropdown and window._ActiveDropdown ~= api then
                    window._ActiveDropdown:Close()
                end
                window._ActiveDropdown = api
                open = true
                if pullSource() then
                    -- dynamic list: drop selections that no longer exist
                    local present = {}
                    for _, item in ipairs(options) do present[keyOf(item)] = true end
                    for key in pairs(selected) do if not present[key] then selected[key] = nil end end
                    updateValue()
                end
                searchQuery = search.Text
                refreshRows(searchQuery)
                recomputeHeight()
                holder.Size = UDim2.new(1, 0, 0, closedHeight)
                searchShell.Visible = true
                list.Visible = true
                searchShell.Position = UDim2.fromOffset(8, closedHeight - 10)
                list.Position = UDim2.fromOffset(8, closedHeight + 28 + actionH)
                if actions then
                    actions.Visible = true
                    actions.Position = UDim2.fromOffset(8, closedHeight + 10)
                    tween(actions, 0.3, {Position = UDim2.fromOffset(8, closedHeight + 48)}, Enum.EasingStyle.Quint)
                end
                tween(holder, 0.3, {Size = UDim2.new(1, 0, 0, expandedHeight)}, Enum.EasingStyle.Quint)
                tween(searchShell, 0.3, {Position = UDim2.fromOffset(8, closedHeight + 8)}, Enum.EasingStyle.Back)
                tween(list, 0.3, {Position = UDim2.fromOffset(8, closedHeight + 50 + actionH)}, Enum.EasingStyle.Quint)
                if arrow then tween(arrow, 0.2, {Rotation = 180, ImageColor3 = theme.Accent2}) end
            end

            function api:Close()
                if not open then return end
                open = false
                searchQuery = ""
                search.Text = "" -- next time the list opens it starts with every option
                if window._ActiveDropdown == api then window._ActiveDropdown = nil end
                if arrow then tween(arrow, 0.2, {Rotation = 0, ImageColor3 = theme.Muted}) end
                tween(searchShell, 0.18, {Position = UDim2.fromOffset(8, closedHeight - 10)}, Enum.EasingStyle.Quint)
                tween(list, 0.18, {Position = UDim2.fromOffset(8, closedHeight + 28 + actionH)}, Enum.EasingStyle.Quint)
                if actions then tween(actions, 0.18, {Position = UDim2.fromOffset(8, closedHeight + 10)}, Enum.EasingStyle.Quint) end
                tween(holder, 0.24, {Size = UDim2.new(1, 0, 0, closedHeight)}, Enum.EasingStyle.Quint)
                task.delay(0.23, function()
                    if not open and searchShell.Parent then
                        searchShell.Visible = false
                        list.Visible = false
                        if actions then actions.Visible = false end
                    end
                end)
            end

            search:GetPropertyChangedSignal("Text"):Connect(function()
                if not open then return end
                searchQuery = search.Text
                refreshRows(searchQuery)
                recomputeHeight()
            end)
            button.MouseEnter:Connect(function() tween(button, 0.15, {BackgroundColor3 = elementBoxHover}) end)
            button.MouseLeave:Connect(function() if not open then tween(button, 0.15, {BackgroundColor3 = elementBox}) end end)
            button.MouseButton1Click:Connect(openDropdown)

            local function fireCallback()
                if typeof(element.callback) == "function" then Security.spawn(element.callback, api:Get()) end
            end
            local function selectionSignature()
                local parts = {}
                for _, item in ipairs(options) do
                    if selected[keyOf(item)] then table.insert(parts, keyOf(item)) end
                end
                return table.concat(parts, "\n")
            end
            local function redraw()
                updateValue()
                if open then refreshRows(search.Text, true); recomputeHeight() end
            end

            -- dropdown:Refresh(newOptions, newValue, fire)
            --   newOptions : a list, OR a function that returns a list (it is then re-read every time), OR nothing
            --                (re-reads the options function again / just redraws)
            --   newValue   : optional, select this after refreshing (a value, or a list for multiSelect)
            --   fire       : true = also call the callback when the selection changed (default: no callback)
            -- A selected value that is still in the new list stays selected; one that is gone is removed.
            function api:Refresh(newOptions, newValue, fire)
                local before = selectionSignature()
                if type(newOptions) == "function" then
                    optionsSource = newOptions
                    pullSource()
                elseif type(newOptions) == "table" then
                    loadOptions(newOptions)
                else
                    pullSource()
                end
                local present = {}
                for _, item in ipairs(options) do present[keyOf(item)] = true end
                for key in pairs(selected) do if not present[key] then selected[key] = nil end end
                if newValue ~= nil then applyValue(newValue) end
                redraw()
                if fire == true and selectionSignature() ~= before then fireCallback() end
                return api
            end
            function api:Set(value, fire)
                applyValue(value)
                redraw()
                if fire ~= false then fireCallback() end
            end
            function api:AddOption(option)
                local key = keyOf(option)
                for _, item in ipairs(options) do if keyOf(item) == key then return api end end
                if key ~= "" then table.insert(options, option) end
                redraw()
                return api
            end
            function api:RemoveOption(option)
                local key = keyOf(option)
                for index, item in ipairs(options) do
                    if keyOf(item) == key then table.remove(options, index) break end
                end
                selected[key] = nil
                redraw()
                return api
            end
            function api:Clear(fire) -- clears the SELECTION (the options stay)
                table.clear(selected)
                redraw()
                if fire == true then fireCallback() end
            end
            api.ClearAll = api.Clear
            function api:SelectAll(fire) -- multiSelect: selects EVERY option (fire = true also runs the callback)
                if not element.multiSelect then return api end
                local before = selectionSignature()
                for _, item in ipairs(options) do selected[keyOf(item)] = true end
                redraw()
                if fire == true and selectionSignature() ~= before then fireCallback() end
                return api
            end
            -- the "Select all" / "Clear all" buttons: they work on the options that are listed right now (a search
            -- narrows the list) and run the callback once when the selection changed
            function api:_ApplyToListed(state)
                local before = selectionSignature()
                for _, item in ipairs(visibleOptions(open and search.Text or "")) do
                    local key = keyOf(item)
                    if state then
                        if element.multiSelect then selected[key] = true end
                    else
                        selected[key] = nil
                    end
                end
                redraw()
                if selectionSignature() ~= before then fireCallback() end
            end
            function api:GetOptions() return table.clone(options) end
            function api:Open() if not open then openDropdown() end end
            function api:IsOpen() return open end
            function api:Get()
                if element.multiSelect then
                    local values = {}
                    for _, item in ipairs(options) do if selected[keyOf(item)] then table.insert(values, item) end end
                    return values
                end
                for _, item in ipairs(options) do if selected[keyOf(item)] then return item end end
                return nil
            end
            -- ---------------------------------------------------------------
            -- dropdown:Download({...})  saves what the user picked (folders, Workspace, models, parts, services...)
            --   Targets   = {inst, "Workspace.Map", ...}  what to save (default: the selected option(s))
            --   All       = true      save every option of the dropdown
            --   Format    = "rbxmx" | "rbxm" | "rbxl" | "rbxlx" | "tree"   (default: rbxl for the game, rbxmx otherwise)
            --   Folder    = "DarkyX/Downloads"   FileName = "MyModel"   Timestamp = false   Overwrite = true
            --   Decompile = true      also decompile scripts (needs executor support)
            --   Mode / Options = {...} passed to the executor's saveinstance
            --   OnProgress(index, total, name)   OnDone(results, job)   Notify = false
            --   Button    = true      adds a download button inside the open list instead of running now
            -- Returns a job: job:Wait() -> results, job:Cancel(), job.Status / .Succeeded / .Failed.
            -- Dropdown options may be Instances, e.g. Refresh({workspace, game.ReplicatedStorage, someModel}).
            -- ---------------------------------------------------------------
            local downloadHelpers = {
                Notify = function(title, content, icon)
                    pcall(function() window:Notify({title = title, content = content, icon = icon, duration = 4}) end)
                end,
                Spawn = function(fn, ...) Security.spawn(fn, ...) end,
            }
            local function collectDownloadTargets(config)
                local raw = {}
                if type(config.Targets) == "table" then
                    for _, target in ipairs(config.Targets) do table.insert(raw, target) end
                elseif config.Targets ~= nil then
                    table.insert(raw, config.Targets)
                elseif config.All == true then
                    for _, option in ipairs(options) do table.insert(raw, option) end
                else
                    local chosen = api:Get()
                    if element.multiSelect then
                        for _, item in ipairs(chosen) do table.insert(raw, item) end
                    elseif chosen ~= nil then
                        table.insert(raw, chosen)
                    end
                end
                return raw
            end
            local downloadButton
            local function installDownloadButton(config)
                if downloadButton then downloadButton:Destroy() end
                local runConfig = table.clone(config)
                runConfig.Button = nil
                downloadButton = new("TextButton", {
                    AutoButtonColor = false, BackgroundColor3 = theme.Panel, Text = "",
                    AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -5, 0.5, 0),
                    Size = UDim2.fromOffset(26, 26), ZIndex = 19,
                }, searchShell)
                corner(downloadButton, UDim.new(1, 0))
                stroke(downloadButton, theme.Border2, 0.3, 1)
                local icon = makeIcon(downloadButton, "download", 14, theme.Muted, 20)
                if icon then icon.AnchorPoint = Vector2.new(0.5, 0.5); icon.Position = UDim2.fromScale(0.5, 0.5) end
                search.Size = UDim2.new(1, -75, 1, 0)
                downloadButton.MouseEnter:Connect(function() tween(downloadButton, 0.15, {BackgroundColor3 = elementBoxHover}) end)
                downloadButton.MouseLeave:Connect(function() tween(downloadButton, 0.15, {BackgroundColor3 = theme.Panel}) end)
                downloadButton.MouseButton1Click:Connect(function()
                    local job = api:Download(runConfig)
                    if icon then tween(icon, 0.15, {ImageColor3 = theme.Accent2}) end
                    task.spawn(function()
                        job:Wait()
                        if not downloadButton or not downloadButton.Parent or not icon then return end
                        tween(icon, 0.15, {ImageColor3 = job.Failed == 0 and Color3.fromRGB(80, 200, 120) or Color3.fromRGB(230, 85, 85)})
                        task.wait(1.4)
                        if icon.Parent then tween(icon, 0.3, {ImageColor3 = theme.Muted}) end
                    end)
                end)
                local handle = {Button = downloadButton}
                function handle:Run() return api:Download(runConfig) end
                function handle:Remove()
                    if downloadButton then downloadButton:Destroy(); downloadButton = nil end
                    search.Size = UDim2.new(1, -48, 1, 0)
                end
                return handle
            end
            local lastDownload -- {Config = ..., Targets = ...} of the latest Download
            function api:Download(config)
                config = type(config) == "table" and config or {}
                if config.Button == true then return installDownloadButton(config) end
                local targets = collectDownloadTargets(config)
                lastDownload = {Config = config, Targets = targets}
                return DarkyX._Downloader.Start(api, config, targets, downloadHelpers)
            end
            -- dropdown:Redownload({...})  downloads the SAME targets again with the same settings as the last Download.
            --   Anything you pass overrides the old settings (Format, Folder, FileName, Targets...).
            --   OnlyFailed = true  -> only retry what failed last time.
            --   Without FileName a new timestamped file is made; with the same FileName the old file is replaced.
            --   Nothing downloaded yet -> it simply behaves like Download.
            function api:Redownload(overrides)
                overrides = type(overrides) == "table" and overrides or {}
                if not lastDownload then return api:Download(overrides) end
                local config = table.clone(lastDownload.Config)
                config.Button = nil
                for key, value in pairs(overrides) do config[key] = value end
                if overrides.Overwrite == nil then config.Overwrite = config.FileName ~= nil end
                if overrides.Targets == nil and overrides.All == nil then
                    config.All = nil
                    local targets = lastDownload.Targets
                    if overrides.OnlyFailed == true then
                        targets = {}
                        local last = api._DownloadJob
                        for _, result in ipairs(last and last.Results or {}) do
                            if result.Ok == false then table.insert(targets, result.Instance or result.Name) end
                        end
                    end
                    config.Targets = targets
                end
                config.OnlyFailed = nil
                return api:Download(config)
            end
            function api:CanDownload() -- {SaveInstance = bool, WriteFile = bool}
                return DarkyX._Downloader.Support()
            end
            do local flagName = getFlag(element, "Dropdown", tab.Name, window._StateEntries); if flagName then window:_Register(flagName, api) end end
            registerSearchItem(tab, holder, element.name or "Dropdown", element.description)
            table.insert(dropdowns, api)
            return api
        end

        function tab:CreateColorPicker(element)
            element = ci(element or {})
            tab.Order += 1
            local seed = element.color or Color3.fromRGB(255, 255, 255)
            local h, sat, val = Color3.toHSV(seed)
            local alpha = math.clamp(tonumber(element.alpha) or 1, 0, 1)
            local hasDescription = element.description and tostring(element.description) ~= ""
            local closedHeight = hasDescription and 68 or 54
            -- readable text colour on top of any colour (white on dark, near-black on light)
            local function textOnColor(c)
                local luma = c.R * 0.299 + c.G * 0.587 + c.B * 0.114
                return luma > 0.55 and Color3.fromRGB(10, 12, 14) or Color3.new(1, 1, 1)
            end
            local PANEL_HEIGHT = 208 -- colour square + sliders on the left; drop-down, preview, hex and opacity on the right
            local expandedHeight = closedHeight + PANEL_HEIGHT + 17
            local open = false

            local holder = new("Frame", {
                BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 0, closedHeight),
                LayoutOrder = tab.Order,
                ClipsDescendants = true,
                ZIndex = 12,
            }, tab.Page)

            local button = new("TextButton", {
                AutoButtonColor = false,
                BackgroundColor3 = elementBox,
                Text = "",
                Size = UDim2.new(1, 0, 0, closedHeight),
                ZIndex = 13,
            }, holder)
            styleElementBox(button, 11)
            setTextPair(button, element.name or "Color", element.description, theme, 7, -118, 14)

            local preview = new("Frame", {
                BackgroundColor3 = seed,
                Position = UDim2.new(1, -58, 0.5, -12),
                Size = UDim2.fromOffset(38, 24),
                ZIndex = 15,
            }, button)
            corner(preview, UDim.new(0, 6)) -- square corner
            stroke(preview, theme.Border2, 0.15, 1)

            local arrow = makeIcon(button, "chevron-down", 16, theme.Muted, 16)
            if arrow then
                arrow.AnchorPoint = Vector2.new(0.5, 0.5)
                arrow.Position = UDim2.new(1, -16, 0.5, 0)
            end

            local panel = new("Frame", {
                BackgroundColor3 = elementBox,
                Position = UDim2.fromOffset(8, closedHeight + 7),
                Size = UDim2.new(1, -16, 0, PANEL_HEIGHT),
                Visible = false,
                ZIndex = 20,
            }, holder)
            styleElementBox(panel, 11) -- glass panel with the light soft white effect (soft sheen + top light, no border)

            -- LEFT: colour square + two vertical column sliders (colour, opacity)
            local cluster = new("Frame", {
                BackgroundTransparency = 1,
                Position = UDim2.fromOffset(12, 12),
                Size = UDim2.new(0.5, -12, 1, -24),
                ZIndex = 21,
            }, panel)
            local sv = new("Frame", {
                BackgroundColor3 = Color3.fromHSV(h, 1, 1),
                Size = UDim2.new(1, -38, 1, 0),
                ZIndex = 21,
            }, cluster)
            corner(sv, UDim.new(0, 6))
            local svWhite = new("Frame", {BackgroundTransparency = 0, Size = UDim2.fromScale(1, 1), ZIndex = 22}, sv)
            corner(svWhite, UDim.new(0, 6))
            gradient(svWhite, {
                ColorSequenceKeypoint.new(0, Color3.new(1,1,1)),
                ColorSequenceKeypoint.new(1, Color3.new(1,1,1)),
            }, 0, NumberSequence.new({NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1)}))
            local svBlack = new("Frame", {BackgroundColor3 = Color3.new(0,0,0), BackgroundTransparency = 0, Size = UDim2.fromScale(1, 1), ZIndex = 23}, sv)
            corner(svBlack, UDim.new(0, 6))
            gradient(svBlack, {
                ColorSequenceKeypoint.new(0, Color3.new(0,0,0)),
                ColorSequenceKeypoint.new(1, Color3.new(0,0,0)),
            }, 90, NumberSequence.new({NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0)}))
            local svMarker = new("Frame", {BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5,0.5), Size = UDim2.fromOffset(14,14), ZIndex = 24}, sv)
            corner(svMarker, UDim.new(1, 0))
            stroke(svMarker, Color3.new(1,1,1), 0, 2) -- hollow ring marker

            -- column 1: the colour (hue) slider
            local hue = new("Frame", {Position = UDim2.new(1, -28, 0, 0), Size = UDim2.new(0, 12, 1, 0), ZIndex = 21}, cluster)
            corner(hue, UDim.new(0, 5))
            gradient(hue, {
                ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)),
                ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255,255,0)),
                ColorSequenceKeypoint.new(0.34, Color3.fromRGB(0,255,0)),
                ColorSequenceKeypoint.new(0.50, Color3.fromRGB(0,255,255)),
                ColorSequenceKeypoint.new(0.67, Color3.fromRGB(0,0,255)),
                ColorSequenceKeypoint.new(0.84, Color3.fromRGB(255,0,255)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(255,0,0)),
            }, 90)
            local hueMarker = new("Frame", {BackgroundColor3 = Color3.new(1,1,1), AnchorPoint = Vector2.new(0.5,0.5), Size = UDim2.new(1, 6, 0, 4), ZIndex = 23}, hue)
            corner(hueMarker, UDim.new(0, 2))
            stroke(hueMarker, Color3.new(0,0,0), 0.15, 1)

            -- column 2: the opacity slider (was the long bar under the picker), right next to the colour slider
            local alphaBar = new("Frame", {BackgroundColor3 = Color3.fromRGB(34, 34, 38), Position = UDim2.new(1, -12, 0, 0), Size = UDim2.new(0, 12, 1, 0), ZIndex = 21}, cluster)
            corner(alphaBar, UDim.new(0, 5))
            local alphaFill = new("Frame", {BackgroundColor3 = seed, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, alpha), ZIndex = 22}, alphaBar)
            corner(alphaFill, UDim.new(0, 5))
            local alphaMarker = new("Frame", {BackgroundColor3 = Color3.new(1,1,1), AnchorPoint = Vector2.new(0.5,0.5), Position = UDim2.new(0.5, 0, 1 - alpha, 0), Size = UDim2.new(1, 6, 0, 4), ZIndex = 23}, alphaBar)
            corner(alphaMarker, UDim.new(0, 2))
            stroke(alphaMarker, Color3.new(0,0,0), 0.15, 1)

            -- RIGHT: big colour preview + hex box + opacity box. The colour recolors the UI LIVE: nothing to apply.
            local side = new("Frame", {
                BackgroundTransparency = 1,
                Position = UDim2.new(0.5, 6, 0, 12),
                Size = UDim2.new(0.5, -18, 1, -24),
                ZIndex = 21,
            }, panel)
            local bigPreview = new("Frame", {
                BackgroundColor3 = seed,
                Position = UDim2.fromOffset(0, 38),
                Size = UDim2.new(1, 0, 1, -80),
                ZIndex = 22,
            }, side)
            corner(bigPreview, UDim.new(0, 9))
            local function makeValueBox(anchor, position, size, placeholder)
                local box = new("TextBox", {
                    BackgroundColor3 = theme.Panel2,
                    BorderSizePixel = 0,
                    Text = "",
                    PlaceholderText = placeholder,
                    PlaceholderColor3 = theme.Muted,
                    TextColor3 = theme.Text,
                    Font = Enum.Font.GothamMedium,
                    TextSize = 11,
                    ClearTextOnFocus = false,
                    AnchorPoint = anchor,
                    Position = position,
                    Size = size,
                    ZIndex = 22,
                }, side)
                corner(box, UDim.new(0, 8))
                stroke(box, theme.Border2, 0.25, 1)
                addTopLight(box, UDim.new(0, 8), 23, 1)
                return box
            end
            local hexBox = makeValueBox(Vector2.new(0, 1), UDim2.fromScale(0, 1), UDim2.new(0.62, -4, 0, 34), "#FFFFFF")
            local alphaBox = makeValueBox(Vector2.new(1, 1), UDim2.fromScale(1, 1), UDim2.new(0.38, -4, 0, 34), "100%")

            -- WHICH elements follow the colour: a MULTI-select drop-down (tick any number of element types). The ticked
            -- types recolor live while the colour is edited, there is no Apply button.
            local recolorKinds = {
                {Key = "Toggle", Label = "Toggle"},
                {Key = "Slider", Label = "Slider"},
                {Key = "Stat", Label = "Stat & Revenue"},
            }
            local chosen = {Toggle = true, Slider = true, Stat = true}
            local function chosenKinds()
                local result = {}
                for _, kind in ipairs(recolorKinds) do
                    if chosen[kind.Key] then table.insert(result, kind) end
                end
                return result
            end
            local function chosenSummary()
                local picked = chosenKinds()
                if #picked == 0 then return "Select..." end
                if #picked == #recolorKinds then return "All elements" end
                local names = {}
                for _, kind in ipairs(picked) do table.insert(names, kind.Label) end
                return table.concat(names, ", ")
            end
            -- light soft white effect for the drop-down (soft top light + glass sheen, same as the element boxes)
            local function glassLook(object, radius, zIndex)
                addTopLight(object, radius, zIndex or object.ZIndex, 1)
                new("UIGradient", {
                    Name = "ElementSheen", Rotation = 90,
                    Color = ColorSequence.new({
                        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
                        ColorSequenceKeypoint.new(1, lightUi and Color3.fromRGB(240, 240, 240) or Color3.fromRGB(214, 214, 214)),
                    }),
                }, object)
            end
            local function lightFlash(object, radius, strength)
                if not object or not object.Parent then return end
                local flash = new("Frame", {
                    Name = "LightFlash", BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = strength or 0.8,
                    BorderSizePixel = 0, Active = false, Size = UDim2.fromScale(1, 1), ZIndex = object.ZIndex + 3,
                }, object)
                corner(flash, radius or UDim.new(0, 6))
                tween(flash, 0.55, {BackgroundTransparency = 1}, Enum.EasingStyle.Quad)
                task.delay(0.6, function() if flash.Parent then flash:Destroy() end end)
            end

            local dropdownButton = new("TextButton", {
                AutoButtonColor = false,
                BackgroundColor3 = theme.Panel2,
                Text = "",
                Position = UDim2.fromOffset(0, 0),
                Size = UDim2.new(1, 0, 0, 30),
                ZIndex = 22,
            }, side)
            corner(dropdownButton, UDim.new(0, 8))
            glassLook(dropdownButton, UDim.new(0, 8), 22)
            local dropdownText = new("TextLabel", {
                BackgroundTransparency = 1,
                Text = chosenSummary(),
                TextColor3 = theme.Text,
                Font = Enum.Font.GothamMedium,
                TextSize = 11,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
                Position = UDim2.fromOffset(10, 0),
                Size = UDim2.new(1, -32, 1, 0),
                ZIndex = 23,
            }, dropdownButton)
            local dropdownArrow = makeIcon(dropdownButton, "chevron-down", 14, theme.Muted, 23)
            if dropdownArrow then
                dropdownArrow.AnchorPoint = Vector2.new(0.5, 0.5)
                dropdownArrow.Position = UDim2.new(1, -14, 0.5, 0)
            end
            dropdownButton.MouseEnter:Connect(function() tween(dropdownButton, 0.14, {BackgroundColor3 = elementBoxHover}) end)
            dropdownButton.MouseLeave:Connect(function() tween(dropdownButton, 0.14, {BackgroundColor3 = theme.Panel2}) end)

            -- the list opens over the preview
            local listFrame = new("Frame", {
                BackgroundColor3 = theme.Panel2,
                Position = UDim2.fromOffset(0, 34),
                Size = UDim2.new(1, 0, 0, #recolorKinds * 28 + 8),
                Visible = false,
                ZIndex = 40,
            }, side)
            corner(listFrame, UDim.new(0, 8))
            glassLook(listFrame, UDim.new(0, 8), 40)
            local optionRows = {}
            local rowTint = lightUi and theme.Accent or Color3.new(1, 1, 1)
            local rowSelectedAlpha = lightUi and 0.82 or 0.86
            local rowHoverAlpha = lightUi and 0.9 or 0.93

            local function recolorList(kind)
                local list = window._Recolor[kind]
                for index = #list, 1, -1 do
                    if not (list[index].Glow and list[index].Glow.Parent) then table.remove(list, index) end
                end
                return list
            end
            local function refreshRows()
                for _, entry in ipairs(optionRows) do
                    local on = chosen[entry.Kind.Key] == true
                    entry.Selected = on
                    tween(entry.Row, 0.14, {BackgroundTransparency = on and rowSelectedAlpha or 1})
                    tween(entry.Label, 0.14, {TextColor3 = on and theme.Text or theme.Muted})
                    if entry.Check then tween(entry.Check, 0.14, {ImageTransparency = on and 0 or 1}) end
                end
                dropdownText.Text = chosenSummary()
            end
            local function setList(show)
                if show and not listFrame.Visible then lightFlash(dropdownButton, UDim.new(0, 8), 0.85) end
                listFrame.Visible = show
                if dropdownArrow then tween(dropdownArrow, 0.18, {Rotation = show and 180 or 0}) end
            end

            -- LIVE recolor: after the colour has been edited once, every ticked type follows it
            local liveTouched = false
            local function applyLive(color)
                for _, kind in ipairs(chosenKinds()) do
                    window._RecolorApplied[kind.Key] = color
                    for _, entry in ipairs(recolorList(kind.Key)) do entry.Apply(color) end
                end
            end

            for index, kind in ipairs(recolorKinds) do
                local row = new("TextButton", {
                    AutoButtonColor = false,
                    BackgroundColor3 = rowTint,
                    BackgroundTransparency = 1,
                    Text = "",
                    Position = UDim2.fromOffset(4, 4 + (index - 1) * 28),
                    Size = UDim2.new(1, -8, 0, 26),
                    ZIndex = 41,
                }, listFrame)
                corner(row, UDim.new(0, 6))
                local rowLabel = new("TextLabel", {
                    BackgroundTransparency = 1,
                    Text = kind.Label,
                    TextColor3 = theme.Muted,
                    Font = Enum.Font.GothamMedium,
                    TextSize = 11,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    TextTruncate = Enum.TextTruncate.AtEnd,
                    Position = UDim2.fromOffset(8, 0),
                    Size = UDim2.new(1, -30, 1, 0),
                    ZIndex = 42,
                }, row)
                local check = makeIcon(row, "check", 13, theme.Accent2, 42)
                if check then
                    check.AnchorPoint = Vector2.new(0.5, 0.5)
                    check.Position = UDim2.new(1, -13, 0.5, 0)
                    check.ImageTransparency = 1
                end
                local entry = {Row = row, Label = rowLabel, Check = check, Kind = kind, Selected = false}
                table.insert(optionRows, entry)
                row.MouseEnter:Connect(function()
                    if not entry.Selected then tween(row, 0.12, {BackgroundTransparency = rowHoverAlpha}) end
                end)
                row.MouseLeave:Connect(function()
                    if not entry.Selected then tween(row, 0.12, {BackgroundTransparency = 1}) end
                end)
                row.MouseButton1Click:Connect(function()
                    -- multi-select: click toggles this type; the list stays open so more can be ticked
                    chosen[kind.Key] = not chosen[kind.Key] or nil
                    lightFlash(row, UDim.new(0, 6), 0.8)
                    refreshRows()
                    if chosen[kind.Key] and liveTouched then
                        -- a type that was just ticked immediately follows the colour that is being edited
                        local color = Color3.fromHSV(h, sat, val)
                        window._RecolorApplied[kind.Key] = color
                        for _, item in ipairs(recolorList(kind.Key)) do
                            item.Apply(color)
                            flashGlow(item.Glow, item.Radius)
                        end
                    end
                end)
            end
            dropdownButton.MouseButton1Click:Connect(function() setList(not listFrame.Visible) end)
            refreshRows()

            local seedAlpha = alpha
            local function updateVisuals(fire, live)
                local color = Color3.fromHSV(h, sat, val)
                sv.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
                svMarker.Position = UDim2.new(sat, 0, 1-val, 0)
                hueMarker.Position = UDim2.new(0.5, 0, h, 0)
                alphaFill.BackgroundColor3 = color
                alphaFill.Size = UDim2.fromScale(1, alpha)
                alphaMarker.Position = UDim2.new(0.5, 0, 1 - alpha, 0)
                preview.BackgroundColor3 = color
                bigPreview.BackgroundColor3 = color
                if not hexBox:IsFocused() then
                    hexBox.Text = string.format("#%02X%02X%02X", math.floor(color.R*255+0.5), math.floor(color.G*255+0.5), math.floor(color.B*255+0.5))
                end
                if not alphaBox:IsFocused() then
                    alphaBox.Text = string.format("%d%%", math.floor(alpha*100+0.5))
                end
                -- LIVE RECOLOR: the ticked element types change with the colour right away, no Apply button
                if live then
                    liveTouched = true
                    applyLive(color)
                end
                if fire and typeof(element.callback) == "function" then Security.spawn(element.callback, color, alpha) end
            end

            -- typing a hex code / opacity also recolors live
            local function parseHex(text)
                local digits = tostring(text):gsub("[^%x]", "")
                if #digits == 3 then digits = digits:gsub(".", "%0%0") end
                if #digits ~= 6 then return nil end
                local r, g, b = tonumber(digits:sub(1, 2), 16), tonumber(digits:sub(3, 4), 16), tonumber(digits:sub(5, 6), 16)
                if not (r and g and b) then return nil end
                return Color3.fromRGB(r, g, b)
            end
            hexBox.FocusLost:Connect(function()
                local typed = parseHex(hexBox.Text)
                if typed then h, sat, val = Color3.toHSV(typed) end
                updateVisuals(true, typed ~= nil)
            end)
            alphaBox.FocusLost:Connect(function()
                local number = tonumber((alphaBox.Text:gsub("[^%d%.]", "")))
                if number then alpha = math.clamp(number / 100, 0, 1) end
                updateVisuals(true, number ~= nil)
            end)

            -- Reset Window Theme (Settings) puts this picker back to its start colour too
            table.insert(window._ThemePickers, {
                Holder = holder,
                Reset = function()
                    h, sat, val = Color3.toHSV(seed)
                    alpha = seedAlpha
                    liveTouched = false
                    updateVisuals(false, false)
                end,
            })

            local function pct(guiObject, input)
                local x = math.clamp((input.Position.X - guiObject.AbsolutePosition.X) / math.max(guiObject.AbsoluteSize.X, 1), 0, 1)
                local y = math.clamp((input.Position.Y - guiObject.AbsolutePosition.Y) / math.max(guiObject.AbsoluteSize.Y, 1), 0, 1)
                return x, y
            end

            -- while a colour is being dragged the page behind must NOT scroll (touch drags used to scroll it)
            local lockedScrollers = {}
            local function lockScroll()
                if #lockedScrollers > 0 then return end
                local ancestor = holder.Parent
                while ancestor do
                    if ancestor:IsA("ScrollingFrame") then
                        table.insert(lockedScrollers, {Frame = ancestor, Was = ancestor.ScrollingEnabled})
                        ancestor.ScrollingEnabled = false
                    end
                    ancestor = ancestor.Parent
                end
            end
            local function unlockScroll()
                for _, saved in ipairs(lockedScrollers) do
                    if saved.Frame.Parent then saved.Frame.ScrollingEnabled = saved.Was end
                end
                table.clear(lockedScrollers)
            end

            local function bindDrag(guiObject, handler)
                local dragging = false
                holder:GetAttributeChangedSignal("FloatGrab"):Connect(function()
                    if holder:GetAttribute("FloatGrab") == true and dragging then dragging = false; unlockScroll() end
                end)
                guiObject.Active = true -- the colour areas swallow the touch, so the page never receives it
                guiObject.InputBegan:Connect(function(input)
                    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                        dragging = true
                        lockScroll()
                        if listFrame.Visible then setList(false) end
                        handler(input)
                    end
                end)
                UserInputService.InputChanged:Connect(function(input)
                    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then handler(input) end
                end)
                UserInputService.InputEnded:Connect(function(input)
                    if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
                        dragging = false
                        unlockScroll()
                    end
                end)
            end

            bindDrag(sv, function(input)
                local x,y = pct(sv,input)
                sat,val = x,1-y
                updateVisuals(true, true)
            end)
            bindDrag(hue, function(input)
                local _,y = pct(hue,input)
                h = y
                updateVisuals(true, true)
            end)
            bindDrag(alphaBar, function(input)
                local _,y = pct(alphaBar,input)
                alpha = 1 - y
                updateVisuals(true, true)
            end)

            local function setOpen(nextOpen)
                open = nextOpen
                if open then
                    if window._ActiveColorPicker and window._ActiveColorPicker ~= panel then window._ActiveColorPicker.Visible = false end
                    window._ActiveColorPicker = panel
                    panel.Visible = true
                    panel.Position = UDim2.fromOffset(8, closedHeight-8)
                    tween(panel,0.28,{Position=UDim2.fromOffset(8,closedHeight+7)},Enum.EasingStyle.Quint)
                    tween(holder,0.3,{Size=UDim2.new(1,0,0,expandedHeight)},Enum.EasingStyle.Quint)
                    if arrow then tween(arrow,0.2,{Rotation=180,ImageColor3=theme.Accent2}) end
                else
                    if window._ActiveColorPicker == panel then window._ActiveColorPicker=nil end
                    setList(false)
                    tween(panel,0.2,{Position=UDim2.fromOffset(8,closedHeight-8)},Enum.EasingStyle.Quint)
                    tween(holder,0.24,{Size=UDim2.new(1,0,0,closedHeight)},Enum.EasingStyle.Quint)
                    if arrow then tween(arrow,0.2,{Rotation=0,ImageColor3=theme.Muted}) end
                    task.delay(0.2,function() if not open and panel.Parent then panel.Visible=false end end)
                end
            end
            button.MouseEnter:Connect(function() tween(button,0.15,{BackgroundColor3=elementBoxHover}) end)
            button.MouseLeave:Connect(function() if not open then tween(button,0.15,{BackgroundColor3=elementBox}) end end)
            button.MouseButton1Click:Connect(function() setOpen(not open) end)

            local api = {}
            function api:Set(color, alphaValue, fire)
                local c = color or Color3.new(1,1,1)
                h,sat,val = Color3.toHSV(c)
                alpha = math.clamp(tonumber(alphaValue) or alpha,0,1)
                updateVisuals(fire ~= false)
            end
            function api:Get() return Color3.fromHSV(h,sat,val), alpha end
            updateVisuals(false)
            do local flagName = getFlag(element, "ColorPicker", tab.Name, window._StateEntries); if flagName then window:_Register(flagName, api) end end
            registerSearchItem(tab, holder, element.name or "ColorPicker", element.description)
            return api
        end

        function tab:CreateSlider(element)
            element = ci(element or {})
            tab.Order += 1
            local range = element.range or {0, 100}
            local minValue, maxValue = tonumber(range[1]) or 0, tonumber(range[2]) or 100
            if minValue > maxValue then minValue, maxValue = maxValue, minValue end
            local value = math.clamp(tonumber(element.value) or minValue, minValue, maxValue)
            local hasDescription = element.description and tostring(element.description) ~= ""
            -- Layout: LEFT = title / description / VALUE (under the title), RIGHT = the slider bar
            local valueY = hasDescription and 44 or 26
            local holder = new("Frame", {
                BackgroundColor3 = elementBox,
                Size = UDim2.new(1, 0, 0, valueY + 22),
                LayoutOrder = tab.Order,
                ZIndex = 9,
            }, tab.Page)
            styleElementBox(holder, 11)
            setTextPair(holder, element.name or "Slider", element.description, theme, 6, -30, 10)
            -- keep the left texts out of the bar's area
            for _, child in ipairs(holder:GetChildren()) do
                if child:IsA("TextLabel") then
                    child.Size = UDim2.new(0.44, -10, 0, child.Size.Y.Offset)
                    child.TextTruncate = Enum.TextTruncate.AtEnd
                end
            end

            local valueLabel = new("TextLabel", {
                Name = "Value",
                BackgroundTransparency = 1,
                Text = "",
                TextColor3 = theme.Accent2,
                Font = Enum.Font.GothamBold,
                TextSize = 13,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextYAlignment = Enum.TextYAlignment.Center,
                Position = UDim2.fromOffset(15, valueY),
                Size = UDim2.new(0.44, -10, 0, 16),
                ZIndex = 11,
            }, holder)

            local track = new("Frame", {
                BackgroundColor3 = isDefaultTheme and theme.SliderBackground or theme.Panel2,
                AnchorPoint = Vector2.new(0, 0.5),
                Position = UDim2.new(0.46, 0, 0.5, 0),
                Size = UDim2.new(0.54, -18, 0, 6),
                ZIndex = 11,
            }, holder)
            corner(track, UDim.new(1, 0))
            -- Soft dark -> light fade across the slider bar (dark on the left half, softly lighter on the right)
            local trackBase = isDefaultTheme and theme.SliderBackground or theme.Panel2
            new("UIGradient", {
                Name = "SliderSoftFade",
                Rotation = 0,
                -- the darker fade is NOT affected by Effect (same look for Effect = true and false)
                Color = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, Color3.new(trackBase.R * 0.35, trackBase.G * 0.35, trackBase.B * 0.35)),
                    ColorSequenceKeypoint.new(0.5, trackBase),
                    ColorSequenceKeypoint.new(1, trackBase:Lerp(theme.Accent2, 0.22)),
                }),
            }, track)
            local fill = new("Frame", {
                BackgroundColor3 = Color3.new(1, 1, 1),
                Size = UDim2.fromScale(0, 1),
                ZIndex = 12,
            }, track)
            corner(fill, UDim.new(1, 0))
            local fillBase = isDefaultTheme and theme.SliderProgress or theme.Accent
            local function fillSequence(c)
                return ColorSequence.new({
                    ColorSequenceKeypoint.new(0, c:Lerp(Color3.new(0, 0, 0), 0.55)),
                    ColorSequenceKeypoint.new(0.5, c),
                    ColorSequenceKeypoint.new(1, c:Lerp(Color3.new(1, 1, 1), 0.25)),
                })
            end
            local fillGradient = new("UIGradient", {
                Name = "SliderFillFade",
                Rotation = 0,
                Color = fillSequence(fillBase),
            }, fill)
            local function setFillColor(c, labelColor)
                fillGradient.Color = fillSequence(c)
                valueLabel.TextColor3 = labelColor
            end
            registerRecolor("Slider", {
                Glow = holder, Radius = UDim.new(0, 14),
                Apply = function(c) setFillColor(c, c) end,
                Reset = function() setFillColor(fillBase, theme.Accent2) end,
            })
            local knob = new("Frame", {
                BackgroundColor3 = Color3.new(1, 1, 1),
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.fromScale(0, 0.5),
                Size = UDim2.fromOffset(22, 14),
                ZIndex = 13,
            }, track)
            corner(knob, UDim.new(1, 0))
            local knobStroke = stroke(knob, Color3.new(1, 1, 1), 0.0, 2)
            local draggingSlider = false
            pcall(function() track:SetAttribute("NoFloatDrag", true) end) -- a press on the bar moves the value, never the V2 widget
            local function apply(valueValue, fire)
                local increment = tonumber(element.increment) or 1
                local snapped = minValue + math.floor(((valueValue - minValue) / increment) + 0.5) * increment
                value = math.clamp(snapped, minValue, maxValue)
                local alpha = (value - minValue) / math.max(maxValue - minValue, 0.0001)
                fill.Size = UDim2.fromScale(alpha, 1)
                knob.Position = UDim2.new(alpha, 0, 0.5, 0)
                tween(knobStroke, 0.15, {Color = Color3.new(1, 1, 1), Transparency = 0.0, Thickness = 2})
                valueLabel.Text = tostring(value) .. tostring(element.suffix or "")
                if fire and typeof(element.callback) == "function" then Security.spawn(element.callback, value) end
            end
            apply(value, false)
            local function inputValue(input)
                local length = math.max(track.AbsoluteSize.X, 1)
                local alpha = math.clamp((input.Position.X - track.AbsolutePosition.X) / length, 0, 1)
                apply(minValue + (maxValue - minValue) * alpha, true)
            end
            local valueBeforePress = value
            track.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                    valueBeforePress = value
                    draggingSlider = true
                    inputValue(input)
                end
            end)
            -- the element is being moved (floating): the press was meant for moving it, so the value goes back
            holder:GetAttributeChangedSignal("FloatGrab"):Connect(function()
                if holder:GetAttribute("FloatGrab") == true and draggingSlider then
                    draggingSlider = false
                    apply(valueBeforePress, true)
                end
            end)
            UserInputService.InputChanged:Connect(function(input)
                if draggingSlider and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then inputValue(input) end
            end)
            UserInputService.InputEnded:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then draggingSlider = false end
            end)
            local api = {}
            function api:Set(valueValue, fire) apply(tonumber(valueValue) or value, fire ~= false) end
            function api:Get() return value end
            do local flagName = getFlag(element, "Slider", tab.Name, window._StateEntries); if flagName then window:_Register(flagName, api) end end
            registerSearchItem(tab, holder, element.name or "Slider", element.description)
            return api
        end

        function tab:CreateStat(element)
            element = ci(element or {})
            tab.Order += 1
            local hasDescription = element.description and tostring(element.description) ~= ""
            local value = element.value
            if value == nil then value = element.Value end
            if value == nil then value = 0 end

            local holder = new("Frame", {
                BackgroundColor3 = Color3.new(1, 1, 1),
                BorderSizePixel = 0,
                Size = UDim2.new(1, 0, 0, hasDescription and 80 or 68),
                LayoutOrder = tab.Order,
                ZIndex = 9,
            }, tab.Page)
            corner(holder, UDim.new(0, 12)) -- no border on purpose

            -- Stat / Revenue card fade (remade): near-black on the LEFT -> vivid colour on the RIGHT,
            -- with a soft LIGHT lift at the very right edge. Built from many small steps so it is smooth (no banding).
            --   accent = the colour the card ends in on the right
            --   Default theme: emerald green. Other themes: their Accent. Per-card override: color = Color3.fromRGB(...)
            local accent
            if typeof(element.color) == "Color3" then
                accent = element.color
            elseif typeof(element.Color) == "Color3" then
                accent = element.Color
            elseif isDefaultTheme then
                accent = theme.StatAccent or Color3.fromRGB(16, 140, 84)
            else
                accent = theme.Accent
            end
            local STAT_LIGHT = 0.14 -- how much white is mixed into the far-right edge (the light fade)
            local STAT_CURVE = 1.7  -- bigger = the dark part lasts longer before it brightens
            local STAT_STEPS = 12
            local function statFade(c)
                -- the darker fade is NOT affected by Effect (same look for Effect = true and false)
                local dark = Color3.fromRGB(18, 20, 19):Lerp(c, 0.08) -- near black with a tiny tint of the colour
                local light = c:Lerp(Color3.new(1, 1, 1), STAT_LIGHT)
                local points = table.create(STAT_STEPS + 1)
                for i = 0, STAT_STEPS do
                    local t = i / STAT_STEPS
                    points[i + 1] = ColorSequenceKeypoint.new(t, dark:Lerp(c, t ^ STAT_CURVE):Lerp(light, t ^ 6))
                end
                return ColorSequence.new(points)
            end
            local statGradient = new("UIGradient", {
                Name = "StatSoftFade",
                Rotation = 0,
                Color = statFade(accent),
            }, holder)
            local statBaseOriginal = accent
            local function setStatBase(c)
                statGradient.Color = statFade(c)
            end
            registerRecolor("Stat", {
                Glow = holder, Radius = UDim.new(0, 12),
                Apply = function(c) setStatBase(c) end,
                Reset = function() setStatBase(statBaseOriginal) end,
            })

            local statTitle = setTextPair(holder, element.name or "Stat", element.description, theme, hasDescription and 18 or 21, -170, 10)
            statTitle.TextTruncate = Enum.TextTruncate.AtEnd
            -- Icon = "house" (a lucide name), "rbxassetid://1234" or 1234: shown on the LEFT of the title (and description)
            local statTexts = {}
            for _, child in ipairs(holder:GetChildren()) do
                if child:IsA("TextLabel") then table.insert(statTexts, child) end
            end
            local STAT_ICON_SIZE, STAT_ICON_X = 20, 16
            local statIcon
            local function setStatIcon(iconValue)
                if statIcon then statIcon:Destroy(); statIcon = nil end
                local textLeft = 15
                if iconValue ~= nil then
                    statIcon = makeIcon(holder, iconValue, STAT_ICON_SIZE, theme.Text, 11)
                    if statIcon then
                        statIcon.AnchorPoint = Vector2.new(0, 0.5)
                        statIcon.Position = UDim2.new(0, STAT_ICON_X, 0.5, 0)
                        textLeft = STAT_ICON_X + STAT_ICON_SIZE + 10
                    end
                end
                for _, label in ipairs(statTexts) do
                    -- the left edge moves right, the right edge stays where it was
                    label.Position = UDim2.new(0, textLeft, label.Position.Y.Scale, label.Position.Y.Offset)
                    label.Size = UDim2.new(1, -170 - (textLeft - 15), label.Size.Y.Scale, label.Size.Y.Offset)
                end
            end
            setStatIcon(element.icon)
            local valueLabel = new("TextLabel", {
                BackgroundTransparency = 1,
                Text = "",
                TextColor3 = theme.White or Color3.new(1, 1, 1),
                TextStrokeColor3 = Color3.new(0, 0, 0),
                TextStrokeTransparency = 0.75,
                Font = Enum.Font.GothamBold,
                TextSize = 22,
                TextXAlignment = Enum.TextXAlignment.Right,
                Position = UDim2.new(0.42, 0, 0, 0),
                Size = UDim2.new(0.58, -18, 1, 0),
                ZIndex = 11,
            }, holder)

            local displayed = tonumber(value)
            local token = 0
            local function render(v)
                valueLabel.Text = tostring(element.prefix or "") .. tostring(v) .. tostring(element.suffix or "")
            end

            -- proxy so revenue.value / revenue.Value always read the latest value,
            -- and assigning revenue.value = x also updates the label
            local api
            api = setmetatable({}, {
                __index = function(_, key)
                    if key == "value" or key == "Value" then return value end
                end,
                __newindex = function(t, key, v)
                    if key == "value" or key == "Value" then
                        t:Set(v)
                    else
                        rawset(t, key, v)
                    end
                end,
            })

            function api:Set(newValue)
                if newValue == nil then return api end
                value = newValue
                token += 1
                local mine = token
                local from, to = displayed, tonumber(newValue)
                if from and to and from ~= to and holder.Parent and element.instant ~= true then
                    local integer = from % 1 == 0 and to % 1 == 0
                    task.spawn(function()
                        local steps = 14
                        for i = 1, steps do
                            if mine ~= token or not holder.Parent then return end
                            local a = i / steps
                            a = 1 - (1 - a) ^ 3
                            local current = from + (to - from) * a
                            if integer then current = math.floor(current + 0.5) end
                            displayed = current
                            render(current)
                            task.wait(0.02)
                        end
                        if mine == token then
                            displayed = to
                            render(newValue)
                        end
                    end)
                else
                    displayed = to
                    render(newValue)
                end
                return api
            end
            function api:Add(amount)
                return api:Set((tonumber(value) or 0) + (tonumber(amount) or 0))
            end
            function api:Get() return value end
            function api:SetIcon(newIcon) -- "house", "rbxassetid://1234", 1234 (nil removes the icon)
                setStatIcon(newIcon)
                return api
            end

            render(value)
            do local flagName = getFlag(element); if flagName then window:_Register(flagName, api, true) end end
            registerSearchItem(tab, holder, element.name or "Stat", element.description)
            return api
        end
        -- aliases so tab:CreateRevenue(...) works the same as tab:CreateStat(...)
        tab.CreateRevenue = tab.CreateStat
        tab.CreateStats = tab.CreateStat

        function tab:CreateInput(element)
            element = ci(element or {})
            tab.Order += 1
            local hasDescription = element.description and tostring(element.description) ~= ""
            local holder = new("Frame", {
                BackgroundColor3 = elementBox,
                Size = UDim2.new(1, 0, 0, hasDescription and 58 or 44),
                LayoutOrder = tab.Order,
                ZIndex = 9,
            }, tab.Page)
            styleElementBox(holder, 11)
            -- slider style row: title on the left, input on the right
            local titleLabel = setTextPair(holder, element.name or "Input", element.description, theme, 0, -30, 10, nil, hasDescription and 58 or 44)
            titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
            local descLabel
            for _, child in ipairs(holder:GetChildren()) do
                if child:IsA("TextLabel") and child ~= titleLabel then descLabel = child end
            end

            local MIN_W, PAD_L, PAD_R, BOX_H = 64, 10, 28, 26
            local box = new("TextBox", {
                BackgroundColor3 = isDefaultTheme and theme.InputBackground or theme.Panel2,
                TextColor3 = theme.Text,
                PlaceholderColor3 = isDefaultTheme and theme.PlaceholderColor or theme.Muted,
                PlaceholderText = tostring(element.placeholder or "Type..."),
                Text = tostring(element.value or ""),
                ClearTextOnFocus = false,
                ClipsDescendants = true,
                TextTruncate = Enum.TextTruncate.AtEnd,
                Font = Enum.Font.Gotham,
                TextSize = 11,
                TextXAlignment = Enum.TextXAlignment.Left,
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, -14, 0.5, 0),
                Size = UDim2.fromOffset(MIN_W, BOX_H),
                ZIndex = 11,
            }, holder)
            corner(box, UDim.new(1, 0))
            pcall(function() box:SetAttribute("NoFloatDrag", true) end) -- typing area: never moves the V2 widget
            local boxStroke = stroke(box, isDefaultTheme and theme.InputStroke or theme.Border, 0.22, 1)
            -- click the input: depth effect only (no boxes)
            local boxDepth = addDepthEffect(box, 1.03)
            box.Focused:Connect(boxDepth.Show)
            box.FocusLost:Connect(boxDepth.Hide)
            new("UIPadding", {PaddingLeft = UDim.new(0, PAD_L), PaddingRight = UDim.new(0, PAD_R)}, box)

            -- pen icon on the right side (lucide "pen"; falls back to a small drawn pen if the icon pack is unavailable)
            local penColor = theme.Muted
            local pen = makeIcon(box, element.icon or "pen", 12, penColor, 12) or makeIcon(box, "pencil", 12, penColor, 12)
            local penBody
            if pen then
                pen.AnchorPoint = Vector2.new(1, 0.5)
                pen.Position = UDim2.new(1, PAD_R - 10, 0.5, 0)
            else
                pen = new("Frame", {
                    Name = "Icon",
                    BackgroundTransparency = 1,
                    AnchorPoint = Vector2.new(1, 0.5),
                    Position = UDim2.new(1, PAD_R - 10, 0.5, 0),
                    Size = UDim2.fromOffset(12, 12),
                    ZIndex = 12,
                }, box)
                penBody = new("Frame", {
                    BackgroundColor3 = penColor,
                    BorderSizePixel = 0,
                    AnchorPoint = Vector2.new(0.5, 0.5),
                    Position = UDim2.fromScale(0.5, 0.5),
                    Size = UDim2.fromOffset(3, 13),
                    Rotation = 45,
                    ZIndex = 12,
                }, pen)
                corner(penBody, UDim.new(0, 1))
            end
            local function tintPen(color)
                if penBody then tween(penBody, 0.15, {BackgroundColor3 = color})
                else tween(pen, 0.15, {ImageColor3 = color}) end
            end

            -- auto width: short when empty, grows as the value gets longer
            local function measure()
                local text = box.Text ~= "" and box.Text or tostring(box.PlaceholderText)
                local ok, size = pcall(function()
                    return TextService:GetTextSize(text, box.TextSize, box.Font, Vector2.new(10000, BOX_H))
                end)
                return ok and size.X or (#text * 6)
            end
            local function resize(animate)
                local holderW = holder.AbsoluteSize.X
                if holderW <= 0 then holderW = 380 end
                local maxW = math.max(MIN_W, math.min(holderW * 0.62, holderW - 150))
                local target = math.floor(math.clamp(math.ceil(measure()) + PAD_L + PAD_R + 4, MIN_W, maxW))
                local function widthOf(label) return UDim2.new(1, -(target + 39), label.Size.Y.Scale, label.Size.Y.Offset) end
                if animate then
                    tween(box, 0.15, {Size = UDim2.fromOffset(target, BOX_H)})
                    tween(titleLabel, 0.15, {Size = widthOf(titleLabel)})
                    if descLabel then tween(descLabel, 0.15, {Size = widthOf(descLabel)}) end
                else
                    box.Size = UDim2.fromOffset(target, BOX_H)
                    titleLabel.Size = widthOf(titleLabel)
                    if descLabel then descLabel.Size = widthOf(descLabel) end
                end
            end
            resize(false)
            box:GetPropertyChangedSignal("Text"):Connect(function() resize(true) end)
            holder:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() resize(false) end)

            local committed = box.Text
            local restBg = isDefaultTheme and theme.InputBackground or theme.Panel2
            local restStroke = isDefaultTheme and theme.InputStroke or theme.Border
            local flashToken = 0
            -- check border = value accepted (also after Load), then fades back to normal.
            -- Default theme: green. Every other theme (cobalt, red, ...): that theme's own accent color.
            local checkColor = isDefaultTheme and theme.Success or theme.Accent
            local function flashSuccess()
                flashToken += 1
                local token = flashToken
                tween(boxStroke, 0.15, {Color = checkColor, Transparency = 0, Thickness = 1.5})
                tintPen(checkColor)
                task.delay(0.5, function()
                    if token ~= flashToken or not box.Parent then return end
                    local focused = box:IsFocused()
                    tween(boxStroke, 0.35, {
                        Color = focused and theme.Accent2 or restStroke,
                        Transparency = focused and 0 or 0.22,
                        Thickness = 1,
                    })
                    tintPen(focused and theme.Accent2 or theme.Muted)
                end)
            end
            box.Focused:Connect(function()
                flashToken += 1
                tween(box, 0.15, {BackgroundColor3 = theme.ElementHover})
                tween(boxStroke, 0.15, {Color = theme.Accent2, Transparency = 0, Thickness = 1})
                tintPen(theme.Accent2)
            end)
            box.FocusLost:Connect(function(enterPressed)
                tween(box, 0.15, {BackgroundColor3 = restBg})
                if element.numeric and box.Text ~= "" and tonumber(box.Text) == nil then
                    box.Text = committed
                    flashToken += 1
                    tween(boxStroke, 0.15, {Color = restStroke, Transparency = 0.22, Thickness = 1})
                    tintPen(theme.Muted)
                    return
                end
                local changed = box.Text ~= committed
                committed = box.Text
                if enterPressed or changed then
                    flashSuccess()
                else
                    flashToken += 1
                    tween(boxStroke, 0.15, {Color = restStroke, Transparency = 0.22, Thickness = 1})
                    tintPen(theme.Muted)
                end
                if typeof(element.callback) == "function" then Security.spawn(element.callback, box.Text) end
            end)
            local api = {}
            function api:Set(value, fire)
                box.Text = tostring(value)
                committed = box.Text
                if fire then flashSuccess() end
                if fire and typeof(element.callback) == "function" then Security.spawn(element.callback, box.Text) end
            end
            function api:Get() return box.Text end
            do local flagName = getFlag(element, "Input", tab.Name, window._StateEntries); if flagName then window:_Register(flagName, api) end end
            registerSearchItem(tab, holder, element.name or "Input", element.description)
            return api
        end

        -- ---------------------------------------------------------------
        -- V2 from a normal element: what Toggle / Slider / Input / Dropdown / ColorPicker / Stat / Note return can make
        -- floating V2 elements and a floating section itself:
        --     local toggle = tab:CreateToggle({ Title = "Aimbot" })
        --     local box = toggle:CreateSectionV2({ Title = "Aimbot settings", Icon = 93364949241311 })
        --     box:CreateSliderV2({ Title = "Smoothness", Range = {1, 20} })
        --     toggle:CreateButtonV2({ Title = "Panic" })     -- a floating element on its own
        --     (:CreateSectionV2 / :CreateButtonV2 / :CreateToggleV2 / :CreateSliderV2 / :CreateInputV2)
        -- A TOGGLE shows what it made while it is ON and hides it while it is OFF.
        -- Follow = false in the config of the V2 element / section turns that off.
        -- (CreateButton returns the button Instance itself, so it has no methods: use tab:CreateButtonV2 there.)
        -- ---------------------------------------------------------------
        do
            local V2_KINDS = {Button = "CreateButton", Toggle = "CreateToggle", Slider = "CreateSlider", Input = "CreateInput"}
            local function giveV2(api, followable)
                if type(api) ~= "table" then return api end
                local function make(kind, selfOrConfig, config)
                    if selfOrConfig ~= api then config = selfOrConfig end
                    config = ci(type(config) == "table" and config or {})
                    local created
                    if kind == "Section" then
                        created = window._CreateFloatSection(tab, config, attachElements)
                    else
                        created = window._CreateFloatWidget(V2_KINDS[kind], tab, config)
                    end
                    if followable and config.follow ~= false and api._OnState then
                        created:SetEnabled(api:Get())
                        api._OnState(function(on) created:SetEnabled(on) end)
                    end
                    return created
                end
                function api:CreateSectionV2(config) return make("Section", self, config) end
                function api:CreateButtonV2(config) return make("Button", self, config) end
                function api:CreateToggleV2(config) return make("Toggle", self, config) end
                function api:CreateSliderV2(config) return make("Slider", self, config) end
                function api:CreateInputV2(config) return make("Input", self, config) end
                return api
            end
            for _, name in ipairs({"CreateToggle", "CreateSlider", "CreateInput", "CreateDropdown", "CreateColorPicker", "CreateStat", "CreateNote"}) do
                local original = tab[name]
                if original then
                    tab[name] = function(self, element)
                        return giveV2(original(self, element), name == "CreateToggle")
                    end
                end
            end
            tab.CreateParagraph = tab.CreateNote
            tab.CreateRevenue, tab.CreateStats = tab.CreateStat, tab.CreateStat
        end

        end
        attachElements(tab)

        -- Tab:CreateGroup() -> grid. grid:CreateGroupLeft() / grid:CreateGroupRight() return columns
        -- that have all the same element functions as the tab (CreateButton, CreateToggle, ...).
        -- Sections still work as before: tab:CreateSection(...) on the tab, or inside a column.
        function tab:CreateGroup(groupConfig)
            groupConfig = ci(groupConfig or {})
            tab.Order += 1
            local gap = tonumber(groupConfig.gap or groupConfig.Gap) or 8
            local holder = new("Frame", {
                Name = "Group",
                BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                LayoutOrder = tab.Order,
                ZIndex = 9,
            }, tab.Page)
            new("UIListLayout", {
                FillDirection = Enum.FillDirection.Horizontal,
                HorizontalAlignment = Enum.HorizontalAlignment.Left,
                VerticalAlignment = Enum.VerticalAlignment.Top,
                Padding = UDim.new(0, gap),
                SortOrder = Enum.SortOrder.LayoutOrder,
            }, holder)

            local grid = {Holder = holder, Tab = tab}
            local columns = {}
            local function makeColumn(side, order)
                local column = new("Frame", {
                    Name = "Group" .. side,
                    BackgroundTransparency = 1,
                    Size = UDim2.new(0.5, -math.floor(gap / 2), 0, 0),
                    AutomaticSize = Enum.AutomaticSize.Y,
                    LayoutOrder = order,
                    ZIndex = 9,
                }, holder)
                new("UIListLayout", {Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder}, column)
                local target = setmetatable({Page = column, Order = 0, Owner = tab, Frame = column}, {
                    __index = function(_, key)
                        if key == "Name" then return tab.Name end
                    end,
                })
                attachElements(target)
                columns[side] = target
                return target
            end
            function grid:CreateGroupLeft() return columns.Left or makeColumn("Left", 1) end
            function grid:CreateGroupRight() return columns.Right or makeColumn("Right", 2) end
            -- make sure the two halves always exist so the layout stays 50 / 50
            grid.Left = grid:CreateGroupLeft()
            grid.Right = grid:CreateGroupRight()
            return grid
        end

        return tab
    end

    -- ---------------------------------------------------------------
    -- Keybind
    -- ---------------------------------------------------------------
    local keybindCapturing = false
    local function setKeybindText(text, recording)
        window._SetKeybindDisplay(text, recording)
    end
    keybindButton.MouseButton1Click:Connect(function()
        if keybindCapturing then -- click again while recording = cancel, show the current key
            keybindCapturing = false
            setKeybindText(window._Keybind.Name, false)
            return
        end
        keybindCapturing = true
        setKeybindText("Recording", true)
    end)

    function window:SetKeybind(keyCode)
        if typeof(keyCode) == "string" then keyCode = Enum.KeyCode[keyCode] end
        if typeof(keyCode) ~= "EnumItem" then return window._Keybind end
        window._Keybind = keyCode
        keybindCapturing = false
        setKeybindText(keyCode.Name, false)
        return keyCode
    end

    UserInputService.InputBegan:Connect(function(input, processed)
        if keybindCapturing then
            if input.UserInputType == Enum.UserInputType.Keyboard then
                keybindCapturing = false
                if input.KeyCode == Enum.KeyCode.Escape then
                    setKeybindText(window._Keybind.Name, false)
                else
                    window:SetKeybind(input.KeyCode)
                end
            end
            return
        end
        if processed then return end
        if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == window._Keybind then
            window:Toggle()
        end
    end)

    -- ---------------------------------------------------------------
    -- Save Manager (Load button + automatic saving, no auto load)
    -- ---------------------------------------------------------------
    local HttpService = game:GetService("HttpService")
    local META_KEY = "__DarkyX_Meta"
    local safeName = tostring(config.name or "DarkyX"):gsub("[^%w_%-]", "")
    if safeName == "" then safeName = "DarkyX" end
    local legacyFile = "DarkyX_Save.json"
    local saveFile = config.SaveFile or config.saveFile
    if not saveFile then
        saveFile = "DarkyX_" .. safeName .. ".json"
        if type(makefolder) == "function" and type(isfolder) == "function" then
            pcall(function() if not isfolder("DarkyX") then makefolder("DarkyX") end end)
            local okFolder, hasFolder = pcall(isfolder, "DarkyX")
            if okFolder and hasFolder then saveFile = "DarkyX/" .. safeName .. ".json" end
        end
    end

    -- Auto Save is always on (the file is rewritten whenever a flagged value changes).
    -- Auto Load is gone: nothing is loaded by itself, the player presses Load in the settings page.
    local autoSave = config.AutoSave ~= false and config.autoSave ~= false
    local autoLoad = false
    window._Pending = {} -- saved values waiting for their element to be created

    local function setSettingsStatus(text, color)
        settingsStatus.Text = text
        settingsStatus.TextColor3 = color or theme.Success
        local mine = text
        task.delay(2, function()
            if settingsStatus.Parent and settingsStatus.Text == mine then settingsStatus.Text = "" end
        end)
    end

    -- true once the player typed a scale / size in the settings page (saved in the file). The script's own
    -- Size / UIScale are start values: they win over an old save, but never over what the player chose.
    local userSetScale, userSetSize = false, false

    -- ---------------------------------------------------------------
    -- Interface inputs (UI Scale / Window Size) - typed values, saved with the Save Manager
    -- UI Scale keeps its own valid range (MIN_SCALE - MAX_SCALE); Window Size is unlimited
    -- ---------------------------------------------------------------
    local function refreshInterface()
        scaleBox.Text = string.format("%.2f", window:GetScale())
        local w, h = window:GetSize()
        widthBox.Text = tostring(w)
        heightBox.Text = tostring(h)
    end
    window._RefreshInterface = refreshInterface

    local function parseNumber(text)
        text = tostring(text or ""):gsub(",", "."):gsub("%s+", "")
        local isPercent = text:find("%%") ~= nil
        local number = tonumber(text:match("^[%+]?(%d*%.?%d+)"))
        if not number then return nil end
        if isPercent then number = number / 100 end
        return number
    end

    scaleBox.FocusLost:Connect(function()
        local number = parseNumber(scaleBox.Text)
        if not number then
            refreshInterface()
            setSettingsStatus("Enter a number like 1.25", theme.Danger)
            return
        end
        if number > 10 then number = number / 100 end -- "125" is read as 125%
        local clamped = math.clamp(number, MIN_SCALE, MAX_SCALE)
        window:SetScale(clamped)
        userSetScale = true
        refreshInterface()
        if math.abs(clamped - number) > 0.0001 then
            setSettingsStatus(("Scale limited to %.2f - %.2f"):format(MIN_SCALE, MAX_SCALE), theme.Danger)
        else
            setSettingsStatus(("UI Scale set to %.2fx"):format(window:GetScale()))
        end
    end)

    local function applySizeInputs(sourceBox)
        -- "700x420" typed into either box sets both
        local pw, ph = tostring(sourceBox.Text):match("(%d+)%s*[xX%*,]%s*(%d+)")
        local width = tonumber(pw) or parseNumber(widthBox.Text)
        local height = tonumber(ph) or parseNumber(heightBox.Text)
        if not width or not height then
            refreshInterface()
            setSettingsStatus("Enter width and height in pixels", theme.Danger)
            return
        end
        window:SetSize(width, height)
        userSetSize = true
        refreshInterface()
        local w, h = window:GetSize()
        setSettingsStatus(("Window size set to %d x %d"):format(w, h))
    end
    widthBox.FocusLost:Connect(function() applySizeInputs(widthBox) end)
    heightBox.FocusLost:Connect(function() applySizeInputs(heightBox) end)

    -- Reset Window Position: back to the original (centered) position
    local defaultWindowPosition = UDim2.fromScale(0.5, 0.5)
    local resetPositionBusy = false
    function window:ResetPosition(animated)
        openFinalPos = defaultWindowPosition -- also the resting spot the open animation ends on
        if animated == false or openActive or not main.Visible then
            main.Position = defaultWindowPosition
        else
            tween(main, 0.35, {Position = defaultWindowPosition}, Enum.EasingStyle.Quint)
        end
        return window
    end
    window.ResetWindowPosition = window.ResetPosition
    resetPositionButton.MouseButton1Click:Connect(function()
        window:ResetPosition()
        if resetPositionIcon then
            resetPositionIcon.Rotation = 0
            tween(resetPositionIcon, 0.45, {Rotation = -360}, Enum.EasingStyle.Quint)
        end
        if resetPositionBusy then return end
        resetPositionBusy = true
        resetPositionButton.Text = "Position Reset"
        task.delay(1.4, function()
            resetPositionBusy = false
            if resetPositionButton.Parent then resetPositionButton.Text = "Reset Window Position" end
        end)
    end)

    interfaceReset.MouseButton1Click:Connect(function()
        window:SetScale(1)
        window:SetSize(550, 340)
        userSetScale, userSetSize = true, true
        refreshInterface()
        setSettingsStatus("Scale and size reset")
    end)
    task.defer(refreshInterface)

    -- value <-> JSON friendly form (Color3, Enum keys and tables survive a save)
    local function encodeValue(value, extra)
        local kind = typeof(value)
        if kind == "Color3" then
            return {__t = "Color3", r = value.R, g = value.G, b = value.B, a = extra}
        elseif kind == "EnumItem" then
            return {__t = "Enum", e = tostring(value.EnumType), n = value.Name}
        elseif kind == "number" then
            if value ~= value or value == math.huge or value == -math.huge then return 0 end
            return value
        elseif kind == "string" or kind == "boolean" then
            return value
        elseif kind == "table" then
            local out = {}
            if #value > 0 then
                for i, item in ipairs(value) do out[i] = encodeValue(item) end
            else
                for key, item in pairs(value) do
                    local encoded = encodeValue(item)
                    if encoded ~= nil then out[tostring(key)] = encoded end
                end
            end
            return out
        end
        return nil
    end
    local function decodeValue(raw)
        if type(raw) == "table" then
            if raw.__t == "Color3" then
                return Color3.new(tonumber(raw.r) or 0, tonumber(raw.g) or 0, tonumber(raw.b) or 0), tonumber(raw.a)
            elseif raw.__t == "Enum" then
                local ok, item = pcall(function() return Enum[tostring(raw.e)][tostring(raw.n)] end)
                return ok and item or nil
            end
            local out = {}
            for key, item in pairs(raw) do out[key] = (decodeValue(item)) end
            return out
        end
        return raw
    end
    local function canon(value) -- deterministic text form, used to detect changes
        if type(value) == "table" then
            local keys = {}
            for key in pairs(value) do table.insert(keys, tostring(key)) end
            table.sort(keys)
            local parts = {}
            for _, key in ipairs(keys) do
                local item = value[key]
                if item == nil then item = value[tonumber(key)] end
                table.insert(parts, key .. "=" .. canon(item))
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
        if type(value) == "number" then
            -- round: tiny float noise (0.30000000000000004 vs 0.3) must never count as a changed value
            return tostring(math.floor(value * 10000 + 0.5) / 10000)
        end
        return tostring(value)
    end

    local function collectData()
        local data = {}
        for flag, raw in pairs(window._Pending) do data[flag] = raw end -- keep values of elements not created yet
        for flag, entry in pairs(window._StateEntries) do
            if not entry._NoSave then
                local packed = table.pack(pcall(function() return entry:Get() end))
                if packed[1] then
                    local encoded = encodeValue(packed[2], packed[3])
                    if encoded ~= nil then data[flag] = encoded end
                end
            end
        end
        local w, h = window:GetSize()
        data[META_KEY] = {
            keybind = window._Keybind.Name, scale = window:GetScale(), width = w, height = h,
            userScale = userSetScale, userSize = userSetSize, slowMode = window._SlowMode == true or nil,
            autoSave = autoSave, autoLoad = autoLoad,
        }
        return data
    end

    -- lastSignature = the state that is already on disk (or was just loaded from it). A save happens ONLY when the
    -- current values differ from it, so an unchanged UI never touches the file.
    local lastSignature
    local failedSignature -- a state whose write failed: not retried until something changes again
    local function writeSave()
        if type(writefile) ~= "function" then return false, "writefile unavailable" end
        local data = collectData()
        local ok = pcall(function() writefile(saveFile, HttpService:JSONEncode(data)) end)
        if ok then lastSignature = canon(data) end
        return ok
    end

    local function readSave()
        if type(readfile) ~= "function" then return nil, "readfile unavailable" end
        for _, path in ipairs({saveFile, legacyFile}) do
            local okRead, raw = pcall(readfile, path)
            if okRead and type(raw) == "string" and raw ~= "" then
                local okDecode, data = pcall(function() return HttpService:JSONDecode(raw) end)
                if okDecode and type(data) == "table" then return data end
                return nil, "Invalid save"
            end
        end
        return nil, "No save found"
    end

    local function applyEntry(flag, raw)
        local entry = window._StateEntries[flag]
        if not entry or entry._NoSave then return false end
        local value, extra = decodeValue(raw)
        if value == nil then return true end
        if typeof(value) == "Color3" then
            pcall(function() entry:Set(value, extra, true) end)
        else
            pcall(function() entry:Set(value, true) end)
        end
        return true
    end

    local function applyMeta(meta, manual)
        if type(meta) ~= "table" then return end
        if config.keybind == nil and meta.keybind then pcall(function() window:SetKeybind(meta.keybind) end) end
        if meta.slowMode ~= nil and window.SetSlowMode then pcall(function() window:SetSlowMode(meta.slowMode == true) end) end
        local hasStartScale = config.UIScale ~= nil or config.uiScale ~= nil or config.Scale ~= nil or config.scale ~= nil
        local hasStartSize = config.Size ~= nil or config.size ~= nil
        -- saved values are used when the player chose them (settings page), when the script sets no start value,
        -- or when the player presses Load by hand
        if tonumber(meta.scale) and (manual or meta.userScale == true or not hasStartScale) then
            window:SetScale(tonumber(meta.scale), true)
            userSetScale = meta.userScale == true
        end
        if tonumber(meta.width) and tonumber(meta.height) and (manual or meta.userSize == true or not hasStartSize) then
            window:SetSize(tonumber(meta.width), tonumber(meta.height), true)
            userSetSize = meta.userSize == true
        end
    end

    local function applyData(data, withMeta, manual)
        window._Pending = {}
        for flag, raw in pairs(data) do
            if flag ~= META_KEY and not applyEntry(flag, raw) then window._Pending[flag] = raw end
        end
        if withMeta then applyMeta(data[META_KEY], manual) end
    end

    -- elements call this when they are created: saved values are applied the moment the element exists
    function window:_Register(flagName, api, noSave)
        if noSave then api._NoSave = true end
        window._StateEntries[flagName] = api
        -- a NEW element is not a changed value: record the starting state again instead of saving
        lastSignature, failedSignature = nil, nil
        local raw = window._Pending[flagName]
        if raw ~= nil and not noSave then
            window._Pending[flagName] = nil
            task.defer(applyEntry, flagName, raw)
        end
    end

    loadButton.MouseButton1Click:Connect(function()
        local data, err = readSave()
        if not data then
            setSettingsStatus(err or "Load failed", theme.Danger)
            return
        end
        applyData(data, true, true)
        refreshInterface()
        setSettingsStatus("Loaded")
        task.delay(0.3, function() -- values are now the ones on disk: that is the new "nothing changed" baseline
            pcall(function() lastSignature = canon(collectData()); failedSignature = nil end)
        end)
    end)
    -- Start values from CreateWindow({ Size = ..., UIScale = ... }). Nothing is auto loaded, so these are what the
    -- window starts with; the player can press Load in the settings page to bring back their saved values.
    do
        local sizeValue = config.Size
        if sizeValue == nil then sizeValue = config.size end
        if sizeValue ~= nil then
            local width, height
            if typeof(sizeValue) == "UDim2" then
                local view = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
                width = sizeValue.X.Offset + sizeValue.X.Scale * view.X
                height = sizeValue.Y.Offset + sizeValue.Y.Scale * view.Y
            elseif typeof(sizeValue) == "Vector2" then
                width, height = sizeValue.X, sizeValue.Y
            elseif type(sizeValue) == "table" then
                width = tonumber(sizeValue[1] or sizeValue.Width or sizeValue.width or sizeValue.X)
                height = tonumber(sizeValue[2] or sizeValue.Height or sizeValue.height or sizeValue.Y)
            elseif type(sizeValue) == "string" then
                local w, h = sizeValue:match("(%d+%.?%d*)%s*[xX%*,]%s*(%d+%.?%d*)")
                width, height = tonumber(w), tonumber(h)
            end
            if width and height then
                window:SetSize(width, height, true)
            else
                Security.log("[DarkyX] Size expects UDim2.fromOffset(600, 250), Vector2, {600, 250} or \"600x250\".")
            end
        end
        local scaleValue = config.UIScale
        if scaleValue == nil then scaleValue = config.uiScale end
        if scaleValue == nil then scaleValue = config.scale end
        if scaleValue == nil then scaleValue = config.Scale end
        if scaleValue ~= nil then
            local text = tostring(scaleValue):gsub("%s+", "")
            local number = tonumber((text:gsub("%%", "")))
            if number and text:find("%%") then number = number / 100 end
            if number then
                window:SetScale(number, true)
            else
                Security.log("[DarkyX] UIScale expects a number or a string like \"0.7\".")
            end
        end
    end

    -- Auto Save: writes the file ONLY when a flagged value (or the keybind / scale / size) really changed.
    --   * the first look (2 s after start) just records the starting state: no write
    --   * a change must stay the same for one more check before it is written, so dragging a slider is saved once
    --     when you let go, not on every tick
    --   * if the write fails (no writefile / bad path) it is not retried until a value changes again
    task.spawn(function()
        task.wait(2) -- let the script create its elements first
        local settling -- the changed state seen on the previous check
        while not window.Destroyed do
            -- protected: one bad element value can never kill the auto-save thread
            pcall(function()
                if autoSave and type(writefile) == "function" then
                    local signature = canon(collectData())
                    if lastSignature == nil then
                        lastSignature = signature -- starting state, nothing to save yet
                    elseif signature == lastSignature then
                        settling, failedSignature = nil, nil -- back to the saved state: nothing to do
                    elseif signature ~= failedSignature then
                        if signature == settling then -- unchanged since the last check: the player is done changing it
                            settling = nil
                            if writeSave() then
                                failedSignature = nil
                                if settingsPageOpen then setSettingsStatus("Auto saved") end
                            else
                                failedSignature = signature
                            end
                        else
                            settling = signature
                        end
                    end
                end
            end)
            task.wait(0.6)
        end
    end)

    local function getExecutorRequest()
        return request or http_request or syn_request
    end

    local function sha256Hex(input)
        local cryptApi = crypt or (syn and syn.crypt)
        if cryptApi and type(cryptApi.hash) == "function" then
            local ok, result = pcall(function() return cryptApi.hash(tostring(input), "sha256") end)
            if ok and type(result) == "string" then return result end
        end
        error("SHA-256 is unavailable in this executor.")
    end

    local function getClientIdentifier()
        if type(gethwid) == "function" then
            local ok, value = pcall(gethwid)
            if ok and value then return tostring(value) end
        end
        return tostring(LocalPlayer and LocalPlayer.UserId or 0)
    end

    local function createPlatoboostService(serviceId, secret)
        local httpRequest = getExecutorRequest()
        local setClipboardFn = setclipboard or toclipboard
        if type(httpRequest) ~= "function" then
            return {Verify=function() return false,"HTTP request function is unavailable." end, Copy=function() return false,"HTTP request function is unavailable." end}
        end
        local http = game:GetService("HttpService")
        local host = "https://api.platoboost.app"
        local cachedLink, cachedAt = "", 0
        local busy = false
        local function send(opt)
            local ok, response = pcall(httpRequest,opt)
            if not ok or not response then return nil,"Request failed." end
            return response
        end
        pcall(function()
            local probe = send({Url=host.."/public/connectivity",Method="GET"})
            if not probe or (probe.StatusCode ~= 200 and probe.StatusCode ~= 429) then host="https://api.platoboost.net" end
        end)
        local function keyLink()
            if cachedLink ~= "" and cachedAt + 600 > os.time() then return true,cachedLink end
            local response,err=send({Url=host.."/public/start",Method="POST",Body=http:JSONEncode({service=serviceId,identifier=sha256Hex(getClientIdentifier())}),Headers={["Content-Type"]="application/json",["User-Agent"]="Roblox/Exploit"}})
            if not response then return false,err end
            if response.StatusCode==429 then return false,"You are being rate limited." end
            if response.StatusCode~=200 then return false,"Platoboost returned HTTP "..tostring(response.StatusCode) end
            local ok,data=pcall(function() return http:JSONDecode(response.Body) end)
            if not ok or type(data)~="table" or data.success~=true then return false,(type(data)=="table" and data.message) or "Unable to create key link." end
            cachedLink=data.data and data.data.url or ""
            cachedAt=os.time()
            return cachedLink~="",cachedLink
        end
        local function verify(key)
            if busy then return false,"A request is already being sent." end
            busy=true
            local nonce=Security.randomHex(16)
            local identifier=sha256Hex(getClientIdentifier())
            local encodedKey=http:UrlEncode(tostring(key or ""))
            local url=host.."/public/whitelist/"..tostring(serviceId).."?identifier="..identifier.."&key="..encodedKey.."&nonce="..http:UrlEncode(nonce)
            local response,err=send({Url=url,Method="GET"})
            busy=false
            if not response then return false,err end
            if response.StatusCode==429 then return false,"You are being rate limited. Try again later." end
            if response.StatusCode~=200 then return false,"Platoboost returned HTTP "..tostring(response.StatusCode) end
            local ok,data=pcall(function() return http:JSONDecode(response.Body) end)
            if not ok or type(data)~="table" or data.success~=true then return false,(type(data)=="table" and data.message) or "Platoboost verification failed." end
            if data.data and data.data.valid==true then
                local expected=sha256Hex("true-"..nonce.."-"..tostring(secret or ""))
                if tostring(data.data.hash)==expected then return true,"" end
                return false,"Platoboost integrity verification failed."
            end
            if tostring(key or ""):sub(1,4)=="KEY_" then
                local redeemNonce=Security.randomHex(16)
                local redeemResponse,redeemErr=send({Url=host.."/public/redeem/"..tostring(serviceId),Method="POST",Body=http:JSONEncode({identifier=identifier,key=key,nonce=redeemNonce}),Headers={["Content-Type"]="application/json"}})
                if not redeemResponse then return false,redeemErr end
                if redeemResponse.StatusCode~=200 then return false,"Platoboost redeem failed." end
                local okRedeem,redeemData=pcall(function() return http:JSONDecode(redeemResponse.Body) end)
                if okRedeem and type(redeemData)=="table" and redeemData.success==true and redeemData.data and redeemData.data.valid==true then
                    local expected=sha256Hex("true-"..redeemNonce.."-"..tostring(secret or ""))
                    if tostring(redeemData.data.hash)==expected then return true,"" end
                    return false,"Platoboost integrity verification failed."
                end
            end
            return false,"Key is invalid."
        end
        return {
            Verify=verify,
            Copy=function()
                local ok,link=keyLink()
                if ok and type(setClipboardFn)=="function" then pcall(setClipboardFn,link) end
                return ok,link
            end,
        }
    end

    function window:CreateKeySystem(config)
        config=ci(config or {})
        local settings=ci(config.KeySettings or config)
        local title=tostring(settings.Title or "Access Required")
        local subtitle=tostring(settings.Subtitle or "Key System")
        local note=tostring(settings.Note or "Enter your key to continue.")
        local fileName=tostring(settings.FileName or "DarkyX_Key")
        local saveKey=settings.SaveKey==true
        local acceptedKeys=settings.Key
        local grab=settings.GrabKeyFromSite==true
        local siteUrl=settings.KeyURL or settings.URL
        local kind=string.lower(tostring(settings.Type or ""))
        local serviceId=settings.ServiceId
        local secret=settings.Secret or settings.Sercet
        if settings.PlatoboostAPI and type(settings.PlatoboostAPI)=="table" then
            local first=settings.PlatoboostAPI[1]
            if type(first)=="table" then
                kind=string.lower(tostring(first.Type or kind))
                serviceId=first.ServiceId or serviceId
                secret=first.Secret or first.Sercet or secret
            end
        end
        local overlay=new("Frame",{BackgroundTransparency=1,Size=UDim2.fromScale(1,1),ZIndex=300},screenGui)
        local panel=new("Frame",{BackgroundColor3=theme.Panel2,BackgroundTransparency=0.02,AnchorPoint=Vector2.new(0.5,0.5),Position=UDim2.fromScale(0.5,0.5),Size=UDim2.fromOffset(math.min(420,windowWidth-40),260),ZIndex=301},overlay)
        corner(panel,UDim.new(0,16))
        stroke(panel,Color3.fromRGB(255,255,255),0.82,1)
        local titleLabel=new("TextLabel",{BackgroundTransparency=1,Text=title,TextColor3=theme.Text,Font=Enum.Font.GothamBold,TextSize=18,Position=UDim2.fromOffset(22,20),Size=UDim2.new(1,-44,0,24),ZIndex=302},panel)
        new("TextLabel",{BackgroundTransparency=1,Text=subtitle,TextColor3=theme.Muted,Font=Enum.Font.Gotham,TextSize=11,Position=UDim2.fromOffset(22,45),Size=UDim2.new(1,-44,0,18),ZIndex=302},panel)
        new("TextLabel",{BackgroundTransparency=1,Text=note,TextWrapped=true,TextColor3=theme.Muted,Font=Enum.Font.Gotham,TextSize=10,TextXAlignment=Enum.TextXAlignment.Left,Position=UDim2.fromOffset(22,72),Size=UDim2.new(1,-44,0,38),ZIndex=302},panel)
        local keyBox=new("TextBox",{BackgroundColor3=theme.Element,ClearTextOnFocus=false,PlaceholderText="Enter key...",PlaceholderColor3=theme.Muted,Text="",TextColor3=theme.Text,Font=Enum.Font.Gotham,TextSize=11,Position=UDim2.fromOffset(22,118),Size=UDim2.new(1,-44,0,38),ZIndex=302},panel)
        corner(keyBox,UDim.new(0,10)); stroke(keyBox,theme.Border2,0.12,1)
        local status=new("TextLabel",{BackgroundTransparency=1,Text="",TextColor3=theme.Muted,Font=Enum.Font.Gotham,TextSize=9,TextXAlignment=Enum.TextXAlignment.Left,Position=UDim2.fromOffset(22,158),Size=UDim2.new(1,-44,0,18),ZIndex=302},panel)
        local getButton=new("TextButton",{AutoButtonColor=false,BackgroundColor3=theme.Panel,Text="Get Key",TextColor3=theme.Text,Font=Enum.Font.GothamBold,TextSize=10,Position=UDim2.fromOffset(22,190),Size=UDim2.new(0.33,-16,0,36),ZIndex=302},panel)
        local submitButton=getButton:Clone(); submitButton.Text="Submit"; submitButton.Position=UDim2.new(0.33,-4,0,190); submitButton.Size=UDim2.new(0.34,-8,0,36); submitButton.Parent=panel
        local cancelButton=getButton:Clone(); cancelButton.Text="Cancel"; cancelButton.Position=UDim2.new(0.67,4,0,190); cancelButton.Size=UDim2.new(0.33,-16,0,36); cancelButton.Parent=panel
        for _,b in ipairs({getButton,submitButton,cancelButton}) do corner(b,UDim.new(0,10)); stroke(b,theme.Border2,0.18,1) end

        local service
        if kind=="platoboost" and serviceId and secret then
            local ok,result=pcall(createPlatoboostService,serviceId,secret)
            if ok then service=result else status.Text="Platoboost setup failed."; status.TextColor3=theme.Danger end
        end
        local function accepted(key)
            if service then return service.Verify(key) end
            if type(acceptedKeys)=="table" then
                for _,allowed in ipairs(acceptedKeys) do if Security.equals(allowed,key) then return true,"" end end
            elseif acceptedKeys~=nil then
                local same=Security.equals(acceptedKeys,key)
                return same,same and "" or "Invalid key."
            end
            if grab and siteUrl and type(game.HttpGet)=="function" then
                local ok,raw=pcall(function() return game:HttpGet(siteUrl) end)
                if ok and Security.equals(Security.cleanKey(raw,512),key) then return true,"" end
            end
            return false,"Invalid key."
        end
        local function saveKeyValue(key)
            if saveKey and type(writefile)=="function" then pcall(writefile,fileName..".txt",tostring(key)) end
        end
        local function loadKeyValue()
            if not saveKey or type(readfile)~="function" or type(isfile)~="function" or not isfile(fileName..".txt") then return nil end
            local ok,value=pcall(readfile,fileName..".txt")
            return ok and value or nil
        end
        local unlocked=false
        local function unlock(message)
            unlocked=true
            status.Text=message or "Key accepted."
            status.TextColor3=successColor
            tween(panel,0.24,{Position=UDim2.fromScale(0.5,0.46)},Enum.EasingStyle.Quint)
            task.delay(0.23,function() if overlay.Parent then overlay:Destroy() end end)
        end
        local limiter=Security.newLimiter(5,20)
        local function verifyAndUnlock(key)
            key=Security.cleanKey(key,512)
            if key=="" then status.Text="Enter a key first."; status.TextColor3=theme.Danger; return false end
            local allowed,waitSeconds=limiter.check()
            if not allowed then status.Text="Too many wrong keys. Try again in "..tostring(waitSeconds).."s."; status.TextColor3=theme.Danger; return false end
            status.Text="Checking..."; status.TextColor3=theme.Muted
            local ok,valid,message=pcall(accepted,key)
            if ok and valid then limiter.success(); saveKeyValue(key); unlock("Key accepted."); return true end
            limiter.fail()
            status.Text=message or "Invalid key."; status.TextColor3=theme.Danger; return false
        end
        submitButton.MouseButton1Click:Connect(function() task.spawn(verifyAndUnlock,keyBox.Text) end)
        getButton.MouseButton1Click:Connect(function()
            if service then
                local ok,result=service.Copy(); status.Text=ok and "Key link copied." or tostring(result); status.TextColor3=ok and successColor or theme.Danger
            elseif grab and siteUrl then
                local clip=setclipboard or toclipboard
                if type(clip)=="function" then pcall(clip,tostring(siteUrl)); status.Text="Key URL copied."; status.TextColor3=successColor else status.Text=tostring(siteUrl) end
            else status.Text="No key method configured." end
        end)
        cancelButton.MouseButton1Click:Connect(function() keyBox.Text="" end)
        local saved=loadKeyValue()
        if saved and saved~="" then keyBox.Text=saved; task.spawn(verifyAndUnlock,saved) end
        window.KeySystem=overlay
        return {Verify=function(key) keyBox.Text=tostring(key or ""); return verifyAndUnlock(keyBox.Text) end, Destroy=function() if overlay.Parent then overlay:Destroy() end end}
    end

    function window:Toggle()
        setVisible(not window.Visible)
    end

    function window:SetVisible(value)
        setVisible(value == true)
    end

    -- (the Animation option is gone: animations are always on. These two stay only so old scripts do not error.)
    function window:SetAnimation() return true end
    function window:GetAnimation() return true end
    -- Window:SetSkipMode(true / false) / Window:GetSkipMode()  (same as CreateWindow({ Skipmode = true }))
    function window:SetSkipMode(value) window._Skip = value == true; return window._Skip end
    function window:GetSkipMode() return window._Skip == true end

    -- Window:SetBackground("rbxassetid://123", 0.5)  -> background image inside the window (nil / false / "rbxassetid://0" removes it)
    -- Window:SetBackgroundTransparency(0.7)          -> 0 = fully visible, 1 = hidden
    -- Window:GetBackground()                         -> current image id (or nil)
    function window:SetBackground(image, transparency)
        return window._ApplyBackground(image, transparency, true)
    end
    function window:SetBackgroundTransparency(value)
        return window._SetBackgroundTransparency(value)
    end
    function window:GetBackground()
        return window.Background
    end

    function window:Destroy()
        if window.Destroyed then return end
        window.Destroyed = true
        pcall(function() if loaderTitle and loaderTitle.Parent then loaderTitle:Destroy() end end)
        for _, popup in ipairs(window._Popups or {}) do pcall(popup.Close) end
        pcall(function() if window._DestroyFloating then window._DestroyFloating() end end) -- floating elements go too
        -- stop the tamper guard + every tracked input connection (nothing keeps running after the window is gone)
        pcall(Security.release, window)
        if screenGui and screenGui.Parent then
            pcall(tween, mainScale, 0.22, {Scale = windowScale * 0.92}, Enum.EasingStyle.Quint)
            task.delay(0.22, function()
                pcall(function() if screenGui then screenGui:Destroy() end end)
            end)
        end
        -- failsafe: whatever happened to the animation, the GUI is gone a moment later
        task.delay(1, function()
            pcall(function() if screenGui and screenGui.Parent then screenGui:Destroy() end end)
        end)
    end

    DarkyX._Window = window
    DarkyX.CurrentTheme = theme -- key system / notifications read this when no window theme is passed

    -- INTRO: the first time the interface shows, a small rounded rectangle fades in at the
    -- middle of the screen, then it smoothly EXPANDS into the full interface. No border, no overshoot, no bounce.
    function window._PlayIntro(speed)
        speed = speed or 1
        endOpen()
        local token = openToken
        local function track(running) if running then table.insert(openTweens, running) end return running end
        local function alive() return token == openToken and not window.Destroyed and main.Parent ~= nil end

        openFinalPos = main.Position
        mainScale.Scale = windowScale
        floating.Visible = false
        main.Visible = false

        local INTRO_W, INTRO_H, INTRO_R = 96, 62, 18
        local rect = new("Frame", {
            Name = "IntroRect",
            BackgroundColor3 = elementBox,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Active = false,
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = openFinalPos,
            Size = UDim2.fromOffset(INTRO_W, INTRO_H),
            ZIndex = 480,
        }, screenGui)
        corner(rect, UDim.new(0, INTRO_R))
        local rectScale = addScale(rect, windowScale * 0.86)
        window._IntroObjects = {rect}

        -- stage 1: the rectangle fades in and settles (smooth, no overshoot)
        track(tween(rect, 0.34 * speed, {BackgroundTransparency = 0}, Enum.EasingStyle.Sine))
        track(tween(rectScale, 0.4 * speed, {Scale = windowScale}, Enum.EasingStyle.Quint))

        -- stage 2: the real window takes over at the same size / place / colour and expands into the interface
        task.delay(0.5 * speed, function()
            if not alive() then return end
            openActive = true
            main.ClipsDescendants = true
            main.Position = openFinalPos
            main.Size = UDim2.fromOffset(INTRO_W, INTRO_H)
            local introRadius = UDim.new(0, INTRO_R)
            if mainCorner then mainCorner.CornerRadius = introRadius end
            openVeilCorner.CornerRadius = introRadius
            openFlashCorner.CornerRadius = introRadius
            openVeil.BackgroundColor3 = elementBox
            openVeil.BackgroundTransparency = 0
            openVeil.Visible = true
            openVeilTitle.TextTransparency = 1
            openFlash.BackgroundTransparency = 1
            openFlash.Visible = false
            if dragPill then dragPill.BackgroundTransparency = 1 end
            main.Visible = true
            rect:Destroy()
            window._IntroObjects = nil

            local expandTime = 0.8 * speed
            track(tween(main, expandTime, {Size = UDim2.fromOffset(windowWidth, windowHeight)}, Enum.EasingStyle.Quint))
            if mainCorner then track(tween(mainCorner, expandTime, {CornerRadius = WINDOW_RADIUS}, Enum.EasingStyle.Quint)) end
            track(tween(openVeilCorner, expandTime, {CornerRadius = WINDOW_RADIUS}, Enum.EasingStyle.Quint))
            track(tween(openFlashCorner, expandTime, {CornerRadius = WINDOW_RADIUS}, Enum.EasingStyle.Quint))
            track(tween(openVeil, expandTime * 0.5, {BackgroundColor3 = theme.Background}, Enum.EasingStyle.Sine))
            task.delay(expandTime * 0.3, function()
                if not alive() then return end
                track(tween(openVeil, expandTime * 0.55, {BackgroundTransparency = 1}, Enum.EasingStyle.Sine))
            end)
            task.delay(expandTime + 0.02, function()
                if not alive() then return end
                openActive = false
                main.Position = openFinalPos
                main.ClipsDescendants = false
                openVeil.Visible = false
                openFlash.Visible = false
                openVeil.BackgroundColor3 = theme.Background
                if dragPill and not dragHeld then tween(dragPill, 0.3, {BackgroundTransparency = 0}) end
                task.delay(0.05, rescueMainOnScreen)
            end)
        end)
    end

    local function revealMain()
        if DarkyX._KeyDenied == true then window:Destroy() return end -- never show the UI without a verified key
        window.Visible = true
        floating.Visible = false
        window._PlayIntro(1) -- rounded rectangle appears, then expands into the UI
    end

    -- used by DarkyX:CreatekeySystem: keep the window hidden until the key is accepted
    function window:_KeyHold()
        endOpen() -- stop a running open animation first
        window._Held = true
        window.Visible = false
        main.Visible = false
        floating.Visible = false
    end

    function window:_KeyRelease(token)
        if token ~= ksReleaseToken then return end -- only the key system itself can release a held window
        if not window._Held or window.Destroyed then return end
        window._Held = false
        revealMain()
    end

    local function finishLoading()
        if window.Destroyed then return end
        -- only now is the LoadingTitle really finished: the key system (or the UI) may appear
        window._Loaded = true
        local gate = DarkyX._KeyGate
        if gate and gate.Active and not gate.Passed then
            window:_KeyHold() -- key system takes over
        else
            revealMain()
        end
    end

    if loadingAlreadyPlayed or not loaderTitle then
        -- LoadingTitle already played once (by the key system): open the UI straight away
        task.defer(finishLoading)
    else
        task.delay(0.72, function()
            if window.Destroyed or not loaderTitle.Parent then return end
            tween(loaderScale, 0.24, {Scale = 1.12}, Enum.EasingStyle.Quint)
            tween(loaderTitle, 0.22, {TextTransparency = 1})
            if loaderIcon then tween(loaderIcon, 0.22, {ImageTransparency = 1}) end
            task.delay(0.25, function()
                if loaderTitle and loaderTitle.Parent then loaderTitle:Destroy() end
                finishLoading()
            end)
        end)
    end

    -- =====================================================================
    -- SLOW MODE (manual).  Window:SetSlowMode(true / false)  /  Window:GetSlowMode()  /  Settings > Slow mode
    -- It lowers the light soft white effect and shortens every animation. Nothing here is automatic.
    -- =====================================================================
    DarkyX._Slow = false
    function window:SetSlowMode(value)
        value = value == true
        window._SlowMode = value
        DarkyX._Slow = value
        fx.SetEnabled(fx.Allowed and not value) -- with Effect = false the effect stays off
        if window._SlowToggle then window._SlowToggle(value) end
        return value
    end
    function window:GetSlowMode()
        return window._SlowMode == true
    end

    -- =====================================================================
    -- LOADER MODE:  CreateWindow({ Title = "...", Subtitle = "...", Image = "rbxassetid://0", Theme = "Default",
    --                              LoaderAPI = { { Title = "My Hub", URL = "https://..." }, ... } })
    -- With LoaderAPI the window is ONLY a script loader: a square (soft corner) logo, the title, the subtitle and one button
    -- per entry (button = Title, small line under it = URL). A click does  loadstring(game:HttpGet(URL))()  and tells you
    -- with a notification how it went. Tabs / sections / elements / tags are switched off in this mode: Window:CreateTab(...)
    -- and everything on it just does nothing (no error), but Window:Notify(...) and DarkyX:Notify(...) keep working.
    -- Without LoaderAPI nothing changes: the window is the normal one.
    -- Optional per entry:  Description = "text under the title (default: the URL)"  /  Callback = function(ok, err) end
    -- =====================================================================
    local loaderOk, loaderError = pcall(function()
        local rawLoader = config.LoaderAPI
        local entries = {}
        if type(rawLoader) == "table" then
            local list = rawLoader
            if rawLoader[1] == nil and ci(rawLoader).URL ~= nil then list = {rawLoader} end -- one single entry is fine too
            for _, item in ipairs(list) do
                if type(item) == "table" then
                    item = ci(item)
                    local url = item.URL
                    if url == nil then url = item.Link end
                    if type(url) == "string" and url ~= "" then
                        table.insert(entries, {
                            Title = tostring(item.Title or ("Script " .. (#entries + 1))),
                            URL = url,
                            Description = item.Description ~= nil and tostring(item.Description) or nil,
                            Callback = type(item.Callback) == "function" and item.Callback or nil,
                        })
                    else
                        Security.log("[DarkyX] LoaderAPI entry without a URL was skipped.")
                    end
                end
            end
            if #entries == 0 then Security.log("[DarkyX] LoaderAPI has no valid entry (each needs Title + URL). Normal window used.") end
        end

        if #entries > 0 then
            window.LoaderMode = true
            window.LoaderEntries = entries

            -- 1) tabs / elements / tags off (they accept every call and do nothing)
            local function inert()
                local stub = {}
                return setmetatable(stub, {
                    __index = function() return function() return stub end end,
                    __newindex = function() end,
                })
            end
            window.CreateTab = function() return inert() end
            window.CreateLeftTab = function() return inert() end
            window.CreateRightTab = function() return inert() end
            window.CreateTag = function() return inert() end
            content.Visible = false
            searchButton.Visible = false
            if window._SearchGroup then window._SearchGroup.Visible = false end
            settingsButton.Visible = false
            titleWrap.Visible = false -- the loader panel shows the logo + title + subtitle itself
            tagLayer.Visible = false

            -- 2) compact window (unless the script chose its own Size)
            local loaderWidth = 360
            local loaderHeight = 58 + 14 + 112 + 10 + math.min(#entries, 4) * 50 + 14
            if config.Size == nil then
                window:SetSize(loaderWidth, loaderHeight, true)
                window.ResetSize = function(a, b)
                    local instant = (a == window) and b or a
                    return window.SetSize(loaderWidth, loaderHeight, instant)
                end
            end

            -- 3) the loader panel
            local panel = new("Frame", {
                Name = "LoaderPanel", BackgroundTransparency = 1,
                Position = UDim2.fromOffset(10, 58), Size = UDim2.new(1, -20, 1, -68), ZIndex = 8,
            }, main)

            -- logo: a square with soft corners (the light soft white effect like the boxes) + the Image inside
            local logo = new("Frame", {
                Name = "Logo", BackgroundColor3 = elementBox, BorderSizePixel = 0,
                AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 4), Size = UDim2.fromOffset(58, 58), ZIndex = 9,
            }, panel)
            styleElementBox(logo, 14)
            local imageValue = config.Image
            local imageId = nil
            if type(imageValue) == "number" then imageId = "rbxassetid://" .. tostring(math.floor(imageValue))
            elseif type(imageValue) == "string" and imageValue ~= "" then
                if imageValue:match("^%d+$") then imageId = "rbxassetid://" .. imageValue else imageId = imageValue end
            end
            if imageId and (imageId == "rbxassetid://0" or imageId == "rbxassetid://") then imageId = nil end
            if imageId then
                local image = new("ImageLabel", {
                    BackgroundTransparency = 1, Image = imageId, ScaleType = Enum.ScaleType.Fit,
                    AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -14, 1, -14), ZIndex = 11,
                }, logo)
                corner(image, UDim.new(0, 10))
            else
                new("TextLabel", { -- no image given: the first letter of the title
                    BackgroundTransparency = 1, Text = string.upper(string.sub(tostring(config.name or "D"), 1, 1)),
                    TextColor3 = theme.Text, Font = Enum.Font.GothamBold, TextSize = 26,
                    Size = UDim2.fromScale(1, 1), ZIndex = 11,
                }, logo)
            end
            new("TextLabel", {
                BackgroundTransparency = 1, Text = tostring(config.name or "DarkyX Hub"), TextColor3 = theme.Text,
                Font = Enum.Font.GothamBold, TextSize = 17, TextTruncate = Enum.TextTruncate.AtEnd,
                Position = UDim2.fromOffset(0, 68), Size = UDim2.new(1, 0, 0, 22), ZIndex = 9,
            }, panel)
            new("TextLabel", {
                BackgroundTransparency = 1, Text = tostring(config.subtitle or "DarkyX"), TextColor3 = theme.Muted,
                Font = Enum.Font.Gotham, TextSize = 11, TextTruncate = Enum.TextTruncate.AtEnd,
                Position = UDim2.fromOffset(0, 90), Size = UDim2.new(1, 0, 0, 16), ZIndex = 9,
            }, panel)

            -- the buttons (one per entry)
            local list = new("ScrollingFrame", {
                Name = "LoaderList", BackgroundTransparency = 1, BorderSizePixel = 0, Active = true,
                Position = UDim2.fromOffset(0, 116), Size = UDim2.new(1, 0, 1, -116),
                CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
                ScrollBarThickness = 2, ScrollBarImageColor3 = theme.Muted, ScrollingDirection = Enum.ScrollingDirection.Y, ZIndex = 9,
            }, panel)
            new("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8)}, list)

            local function shortUrl(url)
                local text = url:gsub("^%a+://", "")
                return text
            end

            for index, entry in ipairs(entries) do
                local row = new("TextButton", {
                    Name = "Loader" .. index, LayoutOrder = index, AutoButtonColor = false, Text = "",
                    BackgroundColor3 = elementBox, BorderSizePixel = 0,
                    Size = UDim2.new(1, -4, 0, 42), ZIndex = 10,
                }, list)
                styleElementBox(row, 14)
                new("TextLabel", {
                    BackgroundTransparency = 1, Text = entry.Title, TextColor3 = theme.Text, Font = Enum.Font.GothamMedium,
                    TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
                    Position = UDim2.fromOffset(16, 6), Size = UDim2.new(1, -92, 0, 17), ZIndex = 12,
                }, row)
                new("TextLabel", {
                    BackgroundTransparency = 1, Text = entry.Description or shortUrl(entry.URL), TextColor3 = theme.Muted,
                    Font = Enum.Font.Gotham, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left,
                    TextTruncate = Enum.TextTruncate.AtEnd,
                    Position = UDim2.fromOffset(16, 24), Size = UDim2.new(1, -92, 0, 12), ZIndex = 12,
                }, row)
                local pill = new("TextLabel", {
                    BackgroundColor3 = lightUi and theme.Panel2 or Color3.fromRGB(34, 34, 38), BorderSizePixel = 0,
                    Text = "Load", TextColor3 = theme.Text, Font = Enum.Font.GothamMedium, TextSize = 11,
                    AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(58, 24), ZIndex = 12,
                }, row)
                corner(pill, UDim.new(1, 0))

                row.MouseEnter:Connect(function() tween(row, 0.15, {BackgroundColor3 = elementBoxHover}) end)
                row.MouseLeave:Connect(function() tween(row, 0.15, {BackgroundColor3 = elementBox}) end)

                local busy = false
                local function setState(text, color)
                    if not pill.Parent then return end
                    pill.Text = text
                    pill.TextColor3 = color
                end
                row.MouseButton1Click:Connect(function()
                    if busy or window.Destroyed then return end
                    busy = true
                    setState("Loading", theme.Muted)
                    window:Notify({Title = entry.Title, Content = "Loading script...", Duration = 2})
                    task.spawn(function()
                        -- 1) download + compile (errors are reported, never thrown)
                        local ok, result = pcall(function()
                            local source = game:HttpGet(entry.URL)
                            local fn, compileError = loadstring(source)
                            if not fn then error(compileError or "the script could not be compiled", 0) end
                            return fn
                        end)
                        if window.Destroyed then return end
                        if ok then
                            -- 2) run it in its own thread, so a script that never returns cannot block this button
                            task.spawn(function()
                                local ran, runError = pcall(result)
                                if not ran and not window.Destroyed then
                                    window:Notify({Title = entry.Title, Content = "Error while running: " .. tostring(runError):sub(1, 140), Duration = 6})
                                end
                            end)
                            setState("Loaded", successColor)
                            window:Notify({Title = entry.Title, Content = "Script loaded.", Duration = 3})
                        else
                            setState("Failed", theme.Danger)
                            window:Notify({Title = entry.Title, Content = "Could not load: " .. tostring(result):sub(1, 140), Duration = 6})
                        end
                        if entry.Callback then pcall(entry.Callback, ok, ok and nil or result) end
                        task.delay(2, function()
                            busy = false
                            setState("Load", theme.Text)
                        end)
                    end)
                end)
            end
        end
    end)
    if not loaderOk then
        warn("[DarkyX] LoaderAPI error: " .. tostring(loaderError))
    end

    Security.pending = nil -- build finished: nothing to clean up any more
    return window
end

-- Public entry point: the build runs protected. If anything fails half way, the half-built GUI is removed
-- (no ghost window left behind) and the real error + traceback is printed.
function DarkyX:CreateWindow(config)
    local owner = self
    if owner ~= DarkyX and config == nil and type(owner) == "table" then
        config, owner = owner, DarkyX -- called with a dot: DarkyX.CreateWindow({...})
    end
    if type(config) == "string" then config = {name = config} end
    if type(config) ~= "table" then config = {} end
    config = ci(config)
    if DarkyX._KeyDenied == true then
        -- the key system ended without a verified key: no UI is built, every call on the result does nothing
        Security.log("[DarkyX] Key was not verified - the UI library is locked.")
        local stub = {Destroyed = true, Visible = false}
        return setmetatable(stub, {
            __index = function() return function() return stub end end,
            __newindex = function() end,
        })
    end
    local key = tostring(config.name or "DarkyX Hub")
    Security.currentKey = key
    Security.purge(key) -- running the same script again replaces its old window
    Security.pending = nil
    local ok, result = xpcall(createWindowImpl, function(err)
        return debug.traceback(tostring(err), 2)
    end, owner, config)
    if not ok then
        Security.abortPending()
        Security.log("[DarkyX] CreateWindow failed:\n" .. tostring(result))
        DarkyX.LastError = tostring(result)
        error("CreateWindow failed: " .. tostring(result), 0) -- the cause travels with the error (no console output needed)
    end
    return result
end

-- DarkyX:Unload() removes every DarkyX interface of this run (windows, key system, notifications)
function DarkyX:Unload()
    local window = DarkyX._Window
    if window and not window.Destroyed then pcall(function() window:Destroy() end) end
    Security.destroyAll()
end

-- =====================================================================
-- KEY SYSTEM   DarkyX:CreatekeySystem({ ... })
--
--   Title          big title                       Note           text under the title
--   Tag            small text above the title      KeyVaild       "Key1"  or  {"Key1", "Key2"}
--   MultikeyVaild  true  = every key in KeyVaild works, false = only the first one
--   SaveKey        remember the accepted key (needs writefile/readfile)
--   MultiURL       true  = Get Key opens a slide-down list, click a link to copy it
--                  false = Get Key copies the (first) link directly
--   KeyAPI         { URL = "https://..." }  or  { URL = {"https://a", "https://b"} }
--                  optional  Validate = function(key) return true/false, "message" end
--   PlatoboostAPI  { Type = "Platoboost", ServiceId = 1234, Sercet = "your secret" }
--                  Get Key copies a link Platoboost generates for the player, Continue verifies the key.
--                  (optional: UseNonce = false, Host = "...", OnMessage = function(message) end)
--   Callback       function(key) run when the key is accepted
--   OnCancel       function() run when the X is pressed
--   Yield          default true: the call waits until the key is accepted.
--                  Returns true (accepted) / false (cancelled).
--   Discord        "https://invite.discord.com/"  square box next to the X: click = copy the Discord link
--                  (Discord = false hides the box)
--   Corner         UDim.new(0, 6)  corner radius of the key system UI (a number = pixels)
--   CaseSensitive / FileName / LoadingTitle are optional too.
-- =====================================================================
-- light soft white effect: soft white light falling from the top edge
local function ksTopLight(object, radius, z, strength, lightUi)
    local light = new("Frame", {
        Name = "TopLight", BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Active = false,
        Size = UDim2.fromScale(1, 1), ZIndex = z or 1,
    }, object)
    corner(light, radius)
    local base = lightUi and 0.6 or 0.9
    base = math.clamp(1 - (1 - base) * (strength or 1), 0, 1)
    new("UIGradient", {
        Rotation = 90,
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, base),
            NumberSequenceKeypoint.new(0.65, 1),
            NumberSequenceKeypoint.new(1, 1),
        }),
    }, light)
    return light
end

-- white light band that sweeps across a box once (hover / focus)
local function ksShine(object, radius, z, lightUi)
    local band = new("Frame", {
        Name = "Shine", BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Active = false,
        Size = UDim2.fromScale(1, 1), ZIndex = z or 1,
    }, object)
    corner(band, radius)
    local g = new("UIGradient", {
        Rotation = 20,
        Offset = Vector2.new(-1.3, 0),
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(0.36, 1),
            NumberSequenceKeypoint.new(0.5, lightUi and 0.4 or 0.62),
            NumberSequenceKeypoint.new(0.64, 1),
            NumberSequenceKeypoint.new(1, 1),
        }),
    }, band)
    return function()
        g.Offset = Vector2.new(-1.3, 0)
        tween(g, 0.65, {Offset = Vector2.new(1.3, 0)}, Enum.EasingStyle.Quint)
    end
end

-- full light white look for a key system box: white glass gradient + top light (+ optional shine)
local function ksLightBox(object, radius, z, lightUi, strength)
    new("UIGradient", {
        Name = "ElementSheen", Rotation = 90,
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
            ColorSequenceKeypoint.new(1, lightUi and Color3.fromRGB(238, 238, 238) or Color3.fromRGB(205, 205, 205)),
        }),
    }, object)
    ksTopLight(object, radius, z, strength or 1.8, lightUi)
    return ksShine(object, radius, z, lightUi)
end

local function ksTrim(value)
    local text = tostring(value == nil and "" or value)
    text = text:gsub("^%s+", "")
    text = text:gsub("%s+$", "")
    return text
end

local function ksList(value)
    local list = {}
    if type(value) == "table" then
        for _, item in ipairs(value) do
            local text = ksTrim(item)
            if text ~= "" then table.insert(list, text) end
        end
    elseif value ~= nil then
        local text = ksTrim(value)
        if text ~= "" then table.insert(list, text) end
    end
    return list
end

local function ksUrls(api)
    local urls = {}
    if type(api) == "string" then api = {URL = api} end
    if type(api) ~= "table" then return urls end
    local source = api.URL or api.Url or api.URLs or api.Link or api.Links
    local function push(entry)
        local name, url
        if type(entry) == "table" then
            url = ksTrim(entry.URL or entry.Url or entry.Link or entry[1] or "")
            name = entry.Name or entry.Title
        else
            url = ksTrim(entry)
        end
        if url == "" then return end
        if not name then name = url:match("^%a+://([^/]+)") or url end
        table.insert(urls, {Name = tostring(name), URL = url})
    end
    if type(source) == "table" then
        if source.URL or source.Url or source.Link then
            push(source)
        else
            for _, entry in ipairs(source) do push(entry) end
        end
    elseif source ~= nil then
        push(source)
    end
    return urls
end

local function ksCopy(text)
    local fn = setclipboard or toclipboard or set_clipboard
    if type(fn) ~= "function" and type(Clipboard) == "table" and type(Clipboard.set) == "function" then
        fn = Clipboard.set
    end
    if type(fn) ~= "function" then return false end
    return (pcall(fn, tostring(text)))
end

local function ksReadClipboard()
    local fn = getclipboard or readclipboard or fromclipboard or get_clipboard or getclip
    if type(fn) ~= "function" and type(Clipboard) == "table" and type(Clipboard.get) == "function" then
        fn = Clipboard.get
    end
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn)
    if ok and type(value) == "string" then return value end
    return nil
end

local function ksSavePath(name)
    if type(makefolder) == "function" and type(isfolder) == "function" then
        pcall(function()
            if not isfolder("DarkyX") then makefolder("DarkyX") end
            if not isfolder("DarkyX/Keys") then makefolder("DarkyX/Keys") end
        end)
        local okFolder, exists = pcall(isfolder, "DarkyX/Keys")
        if okFolder and exists then return "DarkyX/Keys/" .. name .. ".key" end
    end
    return "DarkyX_Key_" .. name .. ".key"
end

local function ksTextOn(color)
    local luma = 0.299 * color.R + 0.587 * color.G + 0.114 * color.B
    return luma > 0.55 and Color3.fromRGB(10, 12, 14) or Color3.new(1, 1, 1)
end

-- drawn fallbacks, used when the lucide icon pack is not available
local function ksDrawCross(parent, size, color, z)
    local holder = new("Frame", {
        Name = "Icon", BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(size, size), ZIndex = z,
    }, parent)
    local bars = {}
    for _, rotation in ipairs({45, -45}) do
        local bar = new("Frame", {
            BackgroundColor3 = color, BorderSizePixel = 0,
            AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(size, 2), Rotation = rotation, ZIndex = z,
        }, holder)
        corner(bar, UDim.new(1, 0))
        table.insert(bars, bar)
    end
    return holder, function(c)
        for _, bar in ipairs(bars) do tween(bar, 0.15, {BackgroundColor3 = c}) end
    end
end

local function ksDrawClipboard(parent, size, color, z)
    local holder = new("Frame", {
        Name = "Icon", BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(size, size), ZIndex = z,
    }, parent)
    local body = new("Frame", {
        BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0),
        Size = UDim2.fromOffset(size - 4, size - 2), ZIndex = z,
    }, holder)
    corner(body, UDim.new(0, 2))
    local bodyStroke = stroke(body, color, 0, 1.4)
    local clip = new("Frame", {
        BackgroundColor3 = color, BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0),
        Size = UDim2.fromOffset(6, 4), ZIndex = z + 1,
    }, holder)
    corner(clip, UDim.new(0, 1))
    return holder, function(c)
        tween(bodyStroke, 0.15, {Color = c})
        tween(clip, 0.15, {BackgroundColor3 = c})
    end
end

local function ksDrawChat(parent, size, color, z)
    local holder = new("Frame", {
        Name = "Icon", BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(size, size), ZIndex = z,
    }, parent)
    local bubble = new("Frame", {
        BackgroundTransparency = 1, Size = UDim2.fromOffset(size, size - 3), ZIndex = z,
    }, holder)
    corner(bubble, UDim.new(1, 0))
    local bubbleStroke = stroke(bubble, color, 0, 1.4)
    local tail = new("Frame", {
        BackgroundColor3 = color, BorderSizePixel = 0, Rotation = 45,
        Position = UDim2.fromOffset(1, size - 5), Size = UDim2.fromOffset(4, 4), ZIndex = z,
    }, holder)
    return holder, function(c)
        tween(bubbleStroke, 0.15, {Color = c})
        tween(tail, 0.15, {BackgroundColor3 = c})
    end
end

-- lucide icon when available, otherwise the drawn fallback. Returns (icon, setColor)
local function ksIcon(parent, iconName, size, color, z, fallback)
    local image = makeIcon(parent, iconName, size, color, z)
    if image then
        image.AnchorPoint = Vector2.new(0.5, 0.5)
        image.Position = UDim2.fromScale(0.5, 0.5)
        return image, function(c) tween(image, 0.15, {ImageColor3 = c}) end
    end
    return fallback(parent, size, color, z)
end

-- =====================================================================
-- PLATOBOOST (built in)   used by DarkyX:CreatekeySystem({ PlatoboostAPI = {...} })
--   * Get Key  -> generates your Platoboost link for this player and copies it
--   * Continue -> verifies the typed key with Platoboost (redeems KEY_ keys automatically)
-- The JSON + SHA-256 helpers below come from the Platoboost template.
-- =====================================================================
local ksCryptoCache
local function ksCrypto()
    if ksCryptoCache then return ksCryptoCache end
    local function build()
local a=2^32;local b=a-1;local function c(d,e)local f,g=0,1;while d~=0 or e~=0 do local h,i=d%2,e%2;local j=(h+i)%2;f=f+j*g;d=math.floor(d/2)e=math.floor(e/2)g=g*2 end;return f%a end;local function k(d,e,l,...)local m;if e then d=d%a;e=e%a;m=c(d,e)if l then m=k(m,l,...)end;return m elseif d then return d%a else return 0 end end;local function n(d,e,l,...)local m;if e then d=d%a;e=e%a;m=(d+e-c(d,e))/2;if l then m=n(m,l,...)end;return m elseif d then return d%a else return b end end;local function o(p)return b-p end;local lshift;local function q(d,r)if r<0 then return lshift(d,-r)end;return math.floor(d%2^32/2^r)end;local function s(p,r)if r>31 or r<-31 then return 0 end;return q(p%a,r)end;lshift=function(d,r)if r<0 then return s(d,-r)end;return d*2^r%2^32 end;local function t(p,r)p=p%a;r=r%32;local u=n(p,2^r-1)return s(p,r)+lshift(u,32-r)end;local v={0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2}local function w(x)return string.gsub(x,".",function(l)return string.format("%02x",string.byte(l))end)end;local function y(z,A)local x=""for B=1,A do local C=z%256;x=string.char(C)..x;z=(z-C)/256 end;return x end;local function D(x,B)local A=0;for B=B,B+3 do A=A*256+string.byte(x,B)end;return A end;local function E(F,G)local H=64-(G+9)%64;G=y(8*G,8)F=F.."\128"..string.rep("\0",H)..G;assert(#F%64==0)return F end;local function I(J)J[1]=0x6a09e667;J[2]=0xbb67ae85;J[3]=0x3c6ef372;J[4]=0xa54ff53a;J[5]=0x510e527f;J[6]=0x9b05688c;J[7]=0x1f83d9ab;J[8]=0x5be0cd19;return J end;local function K(F,B,J)local L={}for M=1,16 do L[M]=D(F,B+(M-1)*4)end;for M=17,64 do local N=L[M-15]local O=k(t(N,7),t(N,18),s(N,3))N=L[M-2]L[M]=(L[M-16]+O+L[M-7]+k(t(N,17),t(N,19),s(N,10)))%a end;local d,e,l,P,Q,R,S,T=J[1],J[2],J[3],J[4],J[5],J[6],J[7],J[8]for B=1,64 do local O=k(t(d,2),t(d,13),t(d,22))local U=k(n(d,e),n(d,l),n(e,l))local V=(O+U)%a;local W=k(t(Q,6),t(Q,11),t(Q,25))local X=k(n(Q,R),n(o(Q),S))local Y=(T+W+X+v[B]+L[B])%a;T=S;S=R;R=Q;Q=(P+Y)%a;P=l;l=e;e=d;d=(Y+V)%a end;J[1]=(J[1]+d)%a;J[2]=(J[2]+e)%a;J[3]=(J[3]+l)%a;J[4]=(J[4]+P)%a;J[5]=(J[5]+Q)%a;J[6]=(J[6]+R)%a;J[7]=(J[7]+S)%a;J[8]=(J[8]+T)%a end;local function Z(F)F=E(F,#F)local J=I({})for B=1,#F,64 do K(F,B,J)end;return w(y(J[1],4)..y(J[2],4)..y(J[3],4)..y(J[4],4)..y(J[5],4)..y(J[6],4)..y(J[7],4)..y(J[8],4))end;local e;local l={["\\"]="\\",["\""]="\"",["\b"]="b",["\f"]="f",["\n"]="n",["\r"]="r",["\t"]="t"}local P={["/"]="/"}for Q,R in pairs(l)do P[R]=Q end;local S=function(T)return"\\"..(l[T]or string.format("u%04x",T:byte()))end;local B=function(M)return"null"end;local v=function(M,z)local _={}z=z or{}if z[M]then error("circular reference")end;z[M]=true;if rawget(M,1)~=nil or next(M)==nil then local A=0;for Q in pairs(M)do if type(Q)~="number"then error("invalid table: mixed or invalid key types")end;A=A+1 end;if A~=#M then error("invalid table: sparse array")end;for a0,R in ipairs(M)do table.insert(_,e(R,z))end;z[M]=nil;return"["..table.concat(_,",").."]"else for Q,R in pairs(M)do if type(Q)~="string"then error("invalid table: mixed or invalid key types")end;table.insert(_,e(Q,z)..":"..e(R,z))end;z[M]=nil;return"{"..table.concat(_,",").."}"end end;local g=function(M)return'"'..M:gsub('[%z\1-\31\\"]',S)..'"'end;local a1=function(M)if M~=M or M<=-math.huge or M>=math.huge then error("unexpected number value '"..tostring(M).."'")end;return string.format("%.14g",M)end;local j={["nil"]=B,["table"]=v,["string"]=g,["number"]=a1,["boolean"]=tostring}e=function(M,z)local x=type(M)local a2=j[x]if a2 then return a2(M,z)end;error("unexpected type '"..x.."'")end;local a3=function(M)return e(M)end;local a4;local N=function(...)local _={}for a0=1,select("#",...)do _[select(a0,...)]=true end;return _ end;local L=N(" ","\t","\r","\n")local p=N(" ","\t","\r","\n","]","}",",")local a5=N("\\","/",'"',"b","f","n","r","t","u")local m=N("true","false","null")local a6={["true"]=true,["false"]=false,["null"]=nil}local a7=function(a8,a9,aa,ab)for a0=a9,#a8 do if aa[a8:sub(a0,a0)]~=ab then return a0 end end;return#a8+1 end;local ac=function(a8,a9,J)local ad=1;local ae=1;for a0=1,a9-1 do ae=ae+1;if a8:sub(a0,a0)=="\n"then ad=ad+1;ae=1 end end;error(string.format("%s at line %d col %d",J,ad,ae))end;local af=function(A)local a2=math.floor;if A<=0x7f then return string.char(A)elseif A<=0x7ff then return string.char(a2(A/64)+192,A%64+128)elseif A<=0xffff then return string.char(a2(A/4096)+224,a2(A%4096/64)+128,A%64+128)elseif A<=0x10ffff then return string.char(a2(A/262144)+240,a2(A%262144/4096)+128,a2(A%4096/64)+128,A%64+128)end;error(string.format("invalid unicode codepoint '%x'",A))end;local ag=function(ah)local ai=tonumber(ah:sub(1,4),16)local aj=tonumber(ah:sub(7,10),16)if aj then return af((ai-0xd800)*0x400+aj-0xdc00+0x10000)else return af(ai)end end;local ak=function(a8,a0)local _=""local al=a0+1;local Q=al;while al<=#a8 do local am=a8:byte(al)if am<32 then ac(a8,al,"control character in string")elseif am==92 then _=_..a8:sub(Q,al-1)al=al+1;local T=a8:sub(al,al)if T=="u"then local an=a8:match("^[dD][89aAbB]%x%x\\u%x%x%x%x",al+1)or a8:match("^%x%x%x%x",al+1)or ac(a8,al-1,"invalid unicode escape in string")_=_..ag(an)al=al+#an else if not a5[T]then ac(a8,al-1,"invalid escape char '"..T.."' in string")end;_=_..P[T]end;Q=al+1 elseif am==34 then _=_..a8:sub(Q,al-1)return _,al+1 end;al=al+1 end;ac(a8,a0,"expected closing quote for string")end;local ao=function(a8,a0)local am=a7(a8,a0,p)local ah=a8:sub(a0,am-1)local A=tonumber(ah)if not A then ac(a8,a0,"invalid number '"..ah.."'")end;return A,am end;local ap=function(a8,a0)local am=a7(a8,a0,p)local aq=a8:sub(a0,am-1)if not m[aq]then ac(a8,a0,"invalid literal '"..aq.."'")end;return a6[aq],am end;local ar=function(a8,a0)local _={}local A=1;a0=a0+1;while 1 do local am;a0=a7(a8,a0,L,true)if a8:sub(a0,a0)=="]"then a0=a0+1;break end;am,a0=a4(a8,a0)_[A]=am;A=A+1;a0=a7(a8,a0,L,true)local as=a8:sub(a0,a0)a0=a0+1;if as=="]"then break end;if as~=","then ac(a8,a0,"expected ']' or ','")end end;return _,a0 end;local at=function(a8,a0)local _={}a0=a0+1;while 1 do local au,M;a0=a7(a8,a0,L,true)if a8:sub(a0,a0)=="}"then a0=a0+1;break end;if a8:sub(a0,a0)~='"'then ac(a8,a0,"expected string for key")end;au,a0=a4(a8,a0)a0=a7(a8,a0,L,true)if a8:sub(a0,a0)~=":"then ac(a8,a0,"expected ':' after key")end;a0=a7(a8,a0+1,L,true)M,a0=a4(a8,a0)_[au]=M;a0=a7(a8,a0,L,true)local as=a8:sub(a0,a0)a0=a0+1;if as=="}"then break end;if as~=","then ac(a8,a0,"expected '}' or ','")end end;return _,a0 end;local av={['"']=ak,["0"]=ao,["1"]=ao,["2"]=ao,["3"]=ao,["4"]=ao,["5"]=ao,["6"]=ao,["7"]=ao,["8"]=ao,["9"]=ao,["-"]=ao,["t"]=ap,["f"]=ap,["n"]=ap,["["]=ar,["{"]=at}a4=function(a8,a9)local as=a8:sub(a9,a9)local a2=av[as]if a2 then return a2(a8,a9)end;ac(a8,a9,"unexpected character '"..as.."'")end;local aw=function(a8)if type(a8)~="string"then error("expected argument of type string, got "..type(a8))end;local _,a9=a4(a8,a7(a8,1,L,true))a9=a7(a8,a9,L,true)if a9<=#a8 then ac(a8,a9,"trailing garbage")end;return _ end;
local lEncode, lDecode, lDigest = a3, aw, Z;
        return lEncode, lDecode, lDigest
    end
    local encode, decode, digest = build()
    ksCryptoCache = {encode = encode, decode = decode, digest = digest}
    return ksCryptoCache
end

-- returns a platoboost object, or nil + error message when the config is wrong
local function ksPlatoboost(cfg)
    local serviceId = tonumber(cfg.ServiceId or cfg.serviceId or cfg.ServiceID or cfg.Service or cfg.service)
    if not serviceId then return nil, "Platoboost ServiceId is missing (it must be a number)." end
    local secret = cfg.Sercet or cfg.Secret or cfg.secret or cfg.sercet
    local useNonce = not (cfg.UseNonce == false or cfg.useNonce == false)
    if useNonce and (type(secret) ~= "string" or secret == "") then
        return nil, "Platoboost Sercet is missing (or set UseNonce = false)."
    end

    local crypto = ksCrypto()
    local lEncode, lDecode, lDigest = crypto.encode, crypto.decode, crypto.digest

    local host = "https://api.platoboost.com"
    local onMessageCallback = type(cfg.OnMessage) == "function" and cfg.OnMessage or nil
    local lastMessage = nil

    -- every failure goes through here: returns false + a nicely capitalised message
    local function fail(message)
        message = tostring(message or "Something went wrong.")
        message = message:sub(1, 1):upper() .. message:sub(2)
        lastMessage = message
        if onMessageCallback then Security.spawn(onMessageCallback, message) end
        return false, message
    end

    local function getRequest()
        return (syn and syn.request) or request or http_request or (http and http.request) or (fluxus and fluxus.request)
    end

    local function getHwid()
        if type(gethwid) == "function" then
            local ok, value = pcall(gethwid)
            if ok and value ~= nil and tostring(value) ~= "" then return tostring(value) end
        end
        return tostring(LocalPlayer and LocalPlayer.UserId or 0)
    end

    local identifierCache
    local function getIdentifier()
        if not identifierCache then identifierCache = lDigest(getHwid()) end
        return identifierCache
    end

    local function urlEncode(text)
        return (tostring(text):gsub("[^%w%-_%.~]", function(c) return string.format("%%%02X", string.byte(c)) end))
    end

    -- run a function once; anybody else asking meanwhile waits for it
    local function once(fn)
        local state = 0
        return function()
            if state == 2 then return end
            if state == 1 then
                while state == 1 do task.wait(0.05) end
                return
            end
            state = 1
            pcall(fn)
            state = 2
        end
    end

    -- pick host: .com unless it is unreachable (then .net)
    local ensureHost = once(function()
        if cfg.Host then host = tostring(cfg.Host):gsub("/+$", ""); return end
        local req = getRequest()
        if not req then return end
        local ok, response = pcall(req, {Url = host .. "/public/connectivity", Method = "GET"})
        local status = ok and type(response) == "table" and response.StatusCode or nil
        if status ~= 200 and status ~= 429 then host = "https://api.platoboost.net" end
    end)

    local function generateNonce()
        local text = ""
        for _ = 1, 16 do text = text .. string.char(math.floor(math.random() * 26) + 97) end
        return text
    end

    -- sanity check from the template: two nonces must never repeat
    local nonceBroken = false
    local ensureNonce = once(function()
        for _ = 1, 5 do
            local first = generateNonce()
            task.wait(0.2)
            if generateNonce() == first then nonceBroken = true; return end
        end
    end)

    local function checkHash(hash, nonce)
        if not useNonce then return true end
        if hash == lDigest("true" .. "-" .. nonce .. "-" .. secret) then return true end
        return fail("failed to verify integrity.")
    end

    local function decodeBody(response)
        local ok, decoded = pcall(lDecode, response.Body)
        if ok and type(decoded) == "table" then return decoded end
        return nil
    end

    -- ---------------------------------------------------------------- link
    local cachedLink, cachedTime = "", 0
    local linkBusy = false

    local function fetchLink()
        local req = getRequest()
        if not req then return fail("your executor has no HTTP request function.") end
        ensureHost()
        local ok, response = pcall(req, {
            Url = host .. "/public/start",
            Method = "POST",
            Body = lEncode({service = serviceId, identifier = getIdentifier()}),
            Headers = {["Content-Type"] = "application/json"},
        })
        if not ok or type(response) ~= "table" then return fail("could not reach Platoboost.") end
        if response.StatusCode == 200 then
            local decoded = decodeBody(response)
            if decoded and decoded.success == true and type(decoded.data) == "table" and decoded.data.url then
                cachedLink = decoded.data.url
                cachedTime = os.time()
                return true, cachedLink
            end
            return fail(decoded and decoded.message or "failed to cache link.")
        elseif response.StatusCode == 429 then
            return fail("you are being rate limited, please wait 20 seconds and try again.")
        end
        return fail("failed to cache link.")
    end

    -- returns true, link   or   false, message
    local function getLink()
        while linkBusy do task.wait(0.05) end
        if cachedLink ~= "" and cachedTime + 10 * 60 >= os.time() then return true, cachedLink end
        linkBusy = true
        local ok, success, value = pcall(fetchLink)
        linkBusy = false
        if ok then return success, value end
        return fail("failed to cache link.")
    end

    -- ---------------------------------------------------------------- key
    local function redeemKey(key, req)
        local nonce = generateNonce()
        local body = {identifier = getIdentifier(), key = key}
        if useNonce then body.nonce = nonce end
        local response = req({
            Url = host .. "/public/redeem/" .. tostring(serviceId),
            Method = "POST",
            Body = lEncode(body),
            Headers = {["Content-Type"] = "application/json"},
        })
        if response.StatusCode == 200 then
            local decoded = decodeBody(response)
            if not decoded then return fail("server returned an invalid response, please try again later.") end
            if decoded.success == true and type(decoded.data) == "table" then
                if decoded.data.valid == true then return checkHash(decoded.data.hash, nonce) end
                return fail("key is invalid.")
            end
            local message = tostring(decoded.message or "")
            if message:sub(1, 27) == "unique constraint violation" then
                return fail("you already have an active key, please wait for it to expire before redeeming it.")
            end
            return fail(message ~= "" and message or "key is invalid.")
        elseif response.StatusCode == 429 then
            return fail("you are being rate limited, please wait 20 seconds and try again.")
        end
        return fail("server returned an invalid status code, please try again later.")
    end

    local sending = false
    local function doVerify(key, req)
        ensureNonce()
        if useNonce and nonceBroken then return fail("platoboost nonce error.") end
        ensureHost()
        local nonce = generateNonce()
        local endpoint = host .. "/public/whitelist/" .. tostring(serviceId)
            .. "?identifier=" .. getIdentifier() .. "&key=" .. urlEncode(key)
        if useNonce then endpoint = endpoint .. "&nonce=" .. nonce end
        local response = req({Url = endpoint, Method = "GET"})
        if response.StatusCode == 200 then
            local decoded = decodeBody(response)
            if not decoded then return fail("server returned an invalid response, please try again later.") end
            if decoded.success == true and type(decoded.data) == "table" then
                if decoded.data.valid == true then return checkHash(decoded.data.hash, nonce) end
                if key:sub(1, 4) == "KEY_" then return redeemKey(key, req) end
                return fail("key is invalid.")
            end
            return fail(decoded.message or "key is invalid.")
        elseif response.StatusCode == 429 then
            return fail("you are being rate limited, please wait 20 seconds and try again.")
        end
        return fail("server returned an invalid status code, please try again later.")
    end

    -- returns true   or   false, message
    local function verifyKey(key)
        key = tostring(key or "")
        if sending then return fail("a request is already being sent, please slow down.") end
        local req = getRequest()
        if not req then return fail("your executor has no HTTP request function.") end
        sending = true
        local ok, success, message = pcall(doVerify, key, req)
        sending = false
        if ok then return success, message end
        return fail("could not verify the key, please try again.")
    end

    return {
        GetLink = getLink,
        Verify = verifyKey,
        -- warm up in the background so Get Key is instant
        Prefetch = function() pcall(getLink); pcall(ensureNonce) end,
        LastMessage = function() return lastMessage end,
    }
end

function DarkyX:CreatekeySystem(config)
    config = ci(config or {})
    local settings = ci(type(config.KeySettings) == "table" and config.KeySettings or config)

    local function liveWindow()
        local w = DarkyX._Window
        if w and not w.Destroyed and w.ScreenGui and w.ScreenGui.Parent then return w end
        return nil
    end

    -- the key system uses the SAME theme as the UI library (window theme > DarkyX:SetTheme > Default).
    -- `settings.Theme` still overrides it.
    local theme = getTheme(settings.theme or settings.Theme or (liveWindow() and liveWindow().Theme) or DarkyX.CurrentTheme or "default")
    -- check / success color: Default theme = green, any other theme = that theme's own accent (cobalt, red, ...)
    local function okColor()
        if theme == Themes.default then return theme.Success end
        return theme.Accent
    end
    local title = tostring(settings.Title or "Key System")
    local note = tostring(settings.Note or "Enter your key to continue.")
    local tagText = tostring(settings.Tag or settings.Subtitle or settings.SmallTitle or "Key System")
    local keys = ksList(settings.KeyVaild or settings.KeyValid or settings.Keys or settings.Key)
    for _, extra in ipairs(settings) do
        if type(extra) == "string" and ksTrim(extra) ~= "" then table.insert(keys, ksTrim(extra)) end
    end
    local multiKeyValue = settings.MultikeyVaild
    if multiKeyValue == nil then multiKeyValue = settings.MultiKeyValid end
    local multiKey = multiKeyValue ~= false
    local multiUrl = settings.MultiURL == true or settings.MultiUrl == true
    local caseSensitive = settings.CaseSensitive ~= false
    local saveKey = settings.SaveKey == true
    local urls = ksUrls(settings.KeyAPI or settings.KeyApi)
    local customValidate = type(settings.KeyAPI) == "table" and settings.KeyAPI.Validate or settings.Validate
    -- PlatoboostAPI = {Type = "Platoboost", ServiceId = 1234, Sercet = "..."}
    --   Get Key copies a link generated by Platoboost, Continue verifies the key with Platoboost.
    local platoConfig = settings.PlatoboostAPI or settings.PlatoBoostAPI or settings.Platoboost
    local plato, platoError
    if type(platoConfig) == "table" then
        local kind = string.lower(tostring(platoConfig.Type or "Platoboost"))
        if kind == "platoboost" then
            local okPlato, built, builtError = pcall(ksPlatoboost, platoConfig)
            if okPlato and built then
                plato = built
            else
                platoError = tostring(okPlato and builtError or built)
                Security.log("[DarkyX] Platoboost setup failed: " .. platoError)
            end
        else
            platoError = "Unknown key API type: " .. kind
            Security.log("[DarkyX] " .. platoError)
        end
    end
    -- Discord = "https://..." : a square box next to the X copies this link (Discord = false hides the box)
    local discordLink = settings.Discord
    if discordLink == nil then discordLink = settings.discord or settings.DiscordLink or settings.DiscordInvite end
    if discordLink == nil then discordLink = "https://invite.discord.com/" end
    discordLink = (discordLink == false) and "" or ksTrim(discordLink)
    -- Corner = UDim.new(0, 6) (default): corner radius of the key system UI. A number is read as pixels.
    local keyCorner = settings.Corner
    if keyCorner == nil then keyCorner = settings.CornerRadius end
    if keyCorner == nil then keyCorner = settings.corner end
    if typeof(keyCorner) == "number" then keyCorner = UDim.new(0, keyCorner) end
    if typeof(keyCorner) ~= "UDim" then keyCorner = UDim.new(0, 6) end
    local keyInnerCorner = keyCorner.Scale > 0 and keyCorner or UDim.new(0, math.max(2, math.floor(keyCorner.Offset * 0.7)))

    local function validate(rawKey)
        local key = Security.cleanKey(rawKey, 512) -- trimmed, control characters removed, length capped
        if key == "" then return false, "Enter your key first." end
        if type(customValidate) == "function" then
            local ok, accepted = pcall(customValidate, key)
            if ok and accepted == true then return true end -- only a real `true` passes (never a truthy string / table)
        end
        for index, valid in ipairs(keys) do
            if index > 1 and not multiKey then break end
            local a, b = key, valid
            if not caseSensitive then a, b = a:lower(), b:lower() end
            if Security.equals(a, b) then return true end -- constant-time compare
        end
        if plato then
            local okPlato, message = plato.Verify(key)
            if okPlato then return true end
            return false, message or "Invalid key. Please try again."
        end
        if platoError then return false, platoError end
        return false, "Invalid key. Please try again."
    end

    local system = {Passed = false, Cancelled = false, Active = true, Key = nil}
    function system:Wait()
        while not self.Passed and not self.Cancelled do task.wait(0.05) end
        return self.Passed
    end

    local function releaseGate()
        -- the gate is released either because the key was verified (Passed = true) or because the key system
        -- ended WITHOUT a verified key (close button, error...). The second case locks the UI library out.
        if not system.Passed then DarkyX._KeyDenied = true end
        system.Active = false
        if DarkyX._KeyGate == system then DarkyX._KeyGate = nil end
    end

    -- the gate is set BEFORE the saved key is checked (Platoboost needs a web request), so a window
    -- that is created meanwhile holds back until we know the result
    DarkyX._KeyDenied = false -- a new key attempt starts: nothing is denied yet
    DarkyX._KeyGate = system

    -- previously saved key
    local saveName = tostring(settings.FileName or title):gsub("[^%w_%-]", "")
    if saveName == "" then saveName = "Key" end
    local savePath = saveKey and ksSavePath(saveName) or nil
    if savePath and type(isfile) == "function" and type(readfile) == "function" then
        local okExists, exists = pcall(isfile, savePath)
        if okExists and exists then
            local okRead, saved = pcall(readfile, savePath)
            local savedOk = false
            if okRead and saved then
                local okCheck, passed = pcall(validate, saved)
                savedOk = okCheck and passed == true
            end
            if savedOk then
                system.Passed = true
                releaseGate()
                system.Key = ksTrim(saved)
                local hold = liveWindow()
                if hold and hold._Held then pcall(function() hold:_KeyRelease(ksReleaseToken) end) end
                local cb = settings.Callback or settings.OnSuccess
                if type(cb) == "function" then Security.spawn(cb, system.Key) end
                if settings.Yield == false then return system end
                return true, system
            end
        end
    end

    local function build(w)
        if plato then task.spawn(plato.Prefetch) end
        Security.currentKey = "keysystem"
        local gui = Security.createScreenGui(Security.randomString(14), 1000)

        -- no window yet: show our own LoadingTitle first, then the key UI
        if not w and settings.LoadingTitle == false then
            DarkyX._LoadingTitlePlayed = true -- LoadingTitle = false: no LoadingTitle here and none in CreateWindow either
        elseif not w then
            local loader = new("TextLabel", {
                Name = "LoadingTitle", BackgroundTransparency = 1,
                Text = tostring(settings.LoadingTitle or "DarkyX"),
                TextColor3 = theme.Text, TextTransparency = 1,
                Font = Enum.Font.GothamBlack, TextSize = 74,
                AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
                Size = UDim2.fromOffset(520, 90), ZIndex = 200,
            }, gui)
            local loadingIconValue = settings.LoadingIcon
            if loadingIconValue == nil then loadingIconValue = settings.loadingIcon end -- (false hides the icon)
            local loaderIcon = addLoadingIcon(loader, loadingIconValue)
            addLoadingDarkFade(loader, loaderIcon)
            local loaderScale = addScale(loader, 0.76)
            tween(loader, 0.38, {TextTransparency = 0})
            if loaderIcon then tween(loaderIcon, 0.38, {ImageTransparency = 0}) end
            tween(loaderScale, 0.48, {Scale = 1}, Enum.EasingStyle.Back)
            task.wait(0.72)
            tween(loaderScale, 0.24, {Scale = 1.12}, Enum.EasingStyle.Quint)
            tween(loader, 0.22, {TextTransparency = 1})
            if loaderIcon then tween(loaderIcon, 0.22, {ImageTransparency = 1}) end
            task.wait(0.25)
            loader:Destroy()
            -- remember it: CreateWindow (called after the key is accepted) must NOT play the LoadingTitle again
            DarkyX._LoadingTitlePlayed = true
        end

        local WIDTH, BASE_H = 440, 190
        local INSET = 10                       -- gap between the glass panel and the inner surface
        local DROP_Y = 166                     -- slide-down list, in inner-surface coordinates
        local rowH, rowGap = 30, 4

        -- depth palette: glass panel > darker inner surface > darkest inset well
        local lightUi = isLightTheme(theme)
        local pal = lightUi and {
            panel = Color3.fromRGB(240, 242, 246), panelStroke = Color3.fromRGB(196, 200, 209),
            body = Color3.fromRGB(249, 250, 252),  bodyStroke = Color3.fromRGB(214, 218, 226),
            well = Color3.fromRGB(231, 234, 240),  wellStroke = Color3.fromRGB(205, 209, 218),
            field = Color3.fromRGB(255, 255, 255), fieldStroke = Color3.fromRGB(200, 204, 213),
            button = Color3.fromRGB(240, 242, 246), buttonHover = Color3.fromRGB(230, 233, 239),
        } or {
            panel = Color3.fromRGB(24, 24, 27),    panelStroke = Color3.fromRGB(58, 58, 64),
            body = Color3.fromRGB(13, 13, 15),     bodyStroke = Color3.fromRGB(33, 33, 37),
            well = Color3.fromRGB(7, 7, 9),        wellStroke = Color3.fromRGB(27, 27, 31),
            field = Color3.fromRGB(15, 15, 17),    fieldStroke = Color3.fromRGB(44, 44, 49),
            button = Color3.fromRGB(23, 23, 26),   buttonHover = Color3.fromRGB(32, 32, 36),
        }

        local backdrop = new("Frame", {
            Name = "Backdrop", BackgroundColor3 = Color3.new(0, 0, 0),
            BackgroundTransparency = 1, Active = true,
            Size = UDim2.fromScale(1, 1), ZIndex = 1,
        }, gui)
        tween(backdrop, 0.3, {BackgroundTransparency = 0.45})

        local root = new("Frame", {
            Name = "KeySystem", BackgroundTransparency = 1,
            AnchorPoint = Vector2.new(0.5, 0),
            Position = UDim2.new(0.5, 0, 0.5, -BASE_H / 2),
            Size = UDim2.fromOffset(WIDTH, BASE_H), ZIndex = 2,
        }, gui)
        local rootScale = addScale(root, 0.92)
        tween(rootScale, 0.34, {Scale = 1}, Enum.EasingStyle.Back)

        -- DragBar: pill below the key UI. Hold + drag it to move the key system.
        local keyDragHandle = new("TextButton", {
            Name = "DragBar", AutoButtonColor = false, BackgroundTransparency = 1, Text = "",
            AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 6),
            Size = UDim2.fromOffset(160, 24), ZIndex = 8,
        }, root)
        local keyDragPill = new("Frame", {
            Name = "Pill", BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, BorderSizePixel = 0,
            AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(96, 5), ZIndex = 9,
        }, keyDragHandle)
        corner(keyDragPill, UDim.new(1, 0))
        tween(keyDragPill, 0.4, {BackgroundTransparency = 0})
        local keyDragHeld = false
        local function keyDragVisual(held)
            keyDragHeld = held
            tween(keyDragPill, 0.16, {
                BackgroundTransparency = held and 0.3 or 0,
                Size = held and UDim2.fromOffset(116, 6) or UDim2.fromOffset(96, 5),
            })
        end
        keyDragHandle.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                keyDragVisual(true)
            end
        end)
        UserInputService.InputEnded:Connect(function(input)
            if keyDragHeld and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
                keyDragVisual(false)
            end
        end)
        makeDrag(keyDragHandle, root)

        -- Depth stack (back to front):  darker surface (light soft white effect) ->
        -- darkest inset well -> input / buttons, each with a subtle stroke.
        -- The old grey outer frame is gone: the card is only a fade container, the darker surface is the base layer.
        local strokeColor = lightUi and pal.fieldStroke or Color3.new(1, 1, 1)
        local strokeSoft = lightUi and 0.45 or 0.92 -- subtle strokes
        local strokeRest = lightUi and 0.35 or 0.88
        local card = new("CanvasGroup", {
            Name = "Card", BackgroundTransparency = 1,
            GroupTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 3,
        }, root)
        corner(card, keyCorner)
        stroke(card, strokeColor, strokeSoft, 1)
        local surface = new("Frame", {
            Name = "Surface", BackgroundColor3 = pal.body, BorderSizePixel = 0,
            Size = UDim2.fromScale(1, 1), ZIndex = 1,
        }, card)
        corner(surface, keyCorner)
        -- light soft white effect on the darker surface: white glass gradient + soft light from the top edge
        new("UIGradient", {
            Name = "SurfaceSheen", Rotation = 90,
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
                ColorSequenceKeypoint.new(1, lightUi and Color3.fromRGB(238, 238, 238) or Color3.fromRGB(205, 205, 205)),
            }),
        }, surface)
        ksTopLight(surface, keyCorner, 2, 1.6, lightUi)
        tween(card, 0.3, {GroupTransparency = 0})

        -- content container (no background of its own: only one surface layer)
        local body = new("Frame", {
            Name = "Body", BackgroundTransparency = 1, BorderSizePixel = 0,
            Position = UDim2.fromOffset(INSET, INSET), Size = UDim2.new(1, -INSET * 2, 1, -INSET * 2), ZIndex = 3,
        }, card)

        new("TextLabel", {
            Name = "Title", BackgroundTransparency = 1, Text = title,
            TextColor3 = theme.Text, Font = Enum.Font.GothamBold, TextSize = 20,
            TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
            Position = UDim2.fromOffset(14, 16), Size = UDim2.new(1, -84, 0, 26), ZIndex = 4,
        }, body)
        new("TextLabel", {
            Name = "Note", BackgroundTransparency = 1, Text = note,
            TextColor3 = theme.Muted, Font = Enum.Font.Gotham, TextSize = 11, TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
            Position = UDim2.fromOffset(14, 46), Size = UDim2.new(1, -28, 0, 30), ZIndex = 4,
        }, body)

        -- cancel icon (top right corner)
        local cancel = new("TextButton", {
            Name = "Cancel", AutoButtonColor = false, Text = "", BackgroundTransparency = 1,
            AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -(INSET + 8), 0, INSET + 8),
            Size = UDim2.fromOffset(24, 24), ZIndex = 6,
        }, card)
        local _, setCancelColor = ksIcon(cancel, "x", 14, theme.Muted, 7, ksDrawCross)
        cancel.MouseEnter:Connect(function() setCancelColor(theme.Danger) end)
        cancel.MouseLeave:Connect(function() setCancelColor(theme.Muted) end)

        -- Discord box: square box left of the X, click = copy the Discord link
        local discordBox, setDiscordColor
        if discordLink ~= "" then
            discordBox = new("TextButton", {
                Name = "Discord", AutoButtonColor = false, Text = "", BackgroundColor3 = pal.button,
                AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -(INSET + 8 + 24 + 6), 0, INSET + 8),
                Size = UDim2.fromOffset(24, 24), ZIndex = 6,
            }, card)
            corner(discordBox, UDim.new(0, 7))
            stroke(discordBox, strokeColor, strokeRest, 1)
            ksTopLight(discordBox, UDim.new(0, 7), 6, 1, lightUi)
            local discordIcon
            discordIcon, setDiscordColor = ksIcon(discordBox, "message-circle", 13, theme.Muted, 7, ksDrawChat)
            discordBox.MouseEnter:Connect(function()
                tween(discordBox, 0.15, {BackgroundColor3 = pal.buttonHover})
                setDiscordColor(theme.Accent2)
            end)
            discordBox.MouseLeave:Connect(function()
                tween(discordBox, 0.15, {BackgroundColor3 = pal.button})
                setDiscordColor(theme.Muted)
            end)
        end

        -- layer 3: darkest inset well holding  [ input .......... ][Get Key][Continue]
        local GET_W, CONT_W = 78, 92
        local well = new("Frame", {
            Name = "Well", BackgroundColor3 = pal.well, BorderSizePixel = 0,
            Position = UDim2.fromOffset(10, 90), Size = UDim2.new(1, -20, 0, 48), ZIndex = 4,
        }, body)
        corner(well, UDim.new(0, 20))
        stroke(well, strokeColor, strokeRest, 1)
        new("UIGradient", {
            Name = "InsetShade", Rotation = 90,
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(165, 165, 165)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 255)),
            }),
        }, well)
        local row = new("Frame", {
            Name = "Row", BackgroundTransparency = 1,
            Position = UDim2.fromOffset(6, 6), Size = UDim2.new(1, -12, 1, -12), ZIndex = 5,
        }, well)

        local restStroke = strokeColor
        local input = new("TextBox", {
            Name = "KeyInput", BackgroundColor3 = pal.field,
            ClearTextOnFocus = false, ClipsDescendants = true,
            PlaceholderText = "Enter your key...", PlaceholderColor3 = theme.PlaceholderColor or theme.Muted,
            Text = "", TextColor3 = theme.Text, Font = Enum.Font.Gotham, TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
            Size = UDim2.new(1, -(GET_W + CONT_W + 16), 1, 0), ZIndex = 6,
        }, row)
        corner(input, UDim.new(1, 0))
        local inputStroke = stroke(input, restStroke, strokeRest, 1) -- subtle stroke at rest
        local inputShine = ksLightBox(input, UDim.new(1, 0), 6, lightUi, 2)
        input.Focused:Connect(inputShine)
        input.MouseEnter:Connect(inputShine)
        -- click the key input: depth effect only (no boxes)
        local inputDepth = addDepthEffect(input, 1.02)
        input.Focused:Connect(inputDepth.Show)
        input.FocusLost:Connect(inputDepth.Hide)
        new("UIPadding", {PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 36)}, input)

        -- clipboard paste icon inside the input: one click pastes everything
        local pasteButton = new("TextButton", {
            Name = "Paste", AutoButtonColor = false, Text = "", BackgroundTransparency = 1,
            AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 36 - 6, 0.5, 0),
            Size = UDim2.fromOffset(24, 24), ZIndex = 8,
        }, input)
        local _, setPasteColor = ksIcon(pasteButton, "clipboard-paste", 14, theme.Muted, 9, ksDrawClipboard)

        local function makeButton(text, primary, width, xOffset)
            local button = new("TextButton", {
                AutoButtonColor = false, Text = text,
                BackgroundColor3 = primary and theme.Accent or pal.button,
                TextColor3 = primary and ksTextOn(theme.Accent) or theme.Text,
                Font = Enum.Font.GothamBold, TextSize = 11,
                AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, xOffset, 0, 0),
                Size = UDim2.new(0, width, 1, 0), ZIndex = 6,
            }, row)
            corner(button, UDim.new(1, 0))
            if primary then stroke(button, theme.Accent2, 0.35, 1) else stroke(button, strokeColor, strokeRest, 1) end
            local buttonShine = ksLightBox(button, UDim.new(1, 0), 6, lightUi, 1.6)
            button.MouseEnter:Connect(buttonShine)
            local rest = primary and theme.Accent or pal.button
            local hover = primary and theme.Accent2 or pal.buttonHover
            button.MouseEnter:Connect(function() tween(button, 0.15, {BackgroundColor3 = hover}) end)
            button.MouseLeave:Connect(function() tween(button, 0.15, {BackgroundColor3 = rest}) end)
            return button
        end
        local continueButton = makeButton("Continue", true, CONT_W, 0)
        local getButton = makeButton("Get Key", false, GET_W, -(CONT_W + 8))

        local status = new("TextLabel", {
            Name = "Status", BackgroundTransparency = 1, Text = "",
            TextColor3 = theme.Muted, Font = Enum.Font.Gotham, TextSize = 10,
            TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
            Position = UDim2.fromOffset(14, 144), Size = UDim2.new(1, -28, 0, 14), ZIndex = 4,
        }, body)
        local function setStatus(text, color)
            status.Text = text or ""
            status.TextColor3 = color or theme.Muted
        end

        -- slide-down link list (MultiURL): another inset well that grows the panel
        local shown = math.min(#urls, 4)
        local dropH = shown * rowH + math.max(shown - 1, 0) * rowGap
        local dropFull = dropH + 8
        local dropFrame = new("Frame", {
            Name = "Links", BackgroundColor3 = pal.well, BorderSizePixel = 0,
            ClipsDescendants = true, Visible = false,
            Position = UDim2.fromOffset(10, DROP_Y), Size = UDim2.new(1, -20, 0, 0), ZIndex = 4,
        }, body)
        corner(dropFrame, UDim.new(0, 16))
        stroke(dropFrame, strokeColor, strokeRest, 1)
        new("UIGradient", {
            Rotation = 90,
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(165, 165, 165)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 255)),
            }),
        }, dropFrame)
        local list = new("ScrollingFrame", {
            BackgroundTransparency = 1, BorderSizePixel = 0,
            Position = UDim2.fromOffset(4, 4), Size = UDim2.new(1, -8, 0, dropH), CanvasSize = UDim2.fromOffset(0, 0),
            AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 2,
            ScrollBarImageColor3 = theme.Accent, ZIndex = 5,
        }, dropFrame)
        new("UIListLayout", {Padding = UDim.new(0, rowGap), SortOrder = Enum.SortOrder.LayoutOrder}, list)

        local dropOpen = false
        local dropToken = 0
        local function setDropdown(open)
            if #urls == 0 then return end
            dropOpen = open
            dropToken += 1
            local token = dropToken
            if open then dropFrame.Visible = true end
            tween(dropFrame, 0.3, {Size = UDim2.new(1, -20, 0, open and dropFull or 0)})
            tween(root, 0.3, {Size = UDim2.fromOffset(WIDTH, open and (DROP_Y + dropFull + INSET * 2 + 12) or BASE_H)})
            if not open then
                task.delay(0.32, function()
                    if token == dropToken and dropFrame.Parent then dropFrame.Visible = false end
                end)
            end
        end

        for index, entry in ipairs(urls) do
            local scrollGap = #urls > 4 and -6 or 0
            local linkRow = new("TextButton", {
                Name = "Link" .. index, AutoButtonColor = false, Text = "",
                BackgroundColor3 = pal.button, LayoutOrder = index,
                Size = UDim2.new(1, scrollGap, 0, rowH), ZIndex = 6,
            }, list)
            corner(linkRow, UDim.new(1, 0))
            local linkStroke = stroke(linkRow, strokeColor, strokeRest, 1) -- subtle stroke at rest
            ksTopLight(linkRow, UDim.new(1, 0), 6, 1, lightUi)
            local linkIcon = makeIcon(linkRow, "link", 13, theme.Muted, 7)
            if linkIcon then
                linkIcon.AnchorPoint = Vector2.new(0, 0.5)
                linkIcon.Position = UDim2.new(0, 14, 0.5, 0)
            end
            local textStart = linkIcon and 34 or 16
            new("TextLabel", {
                BackgroundTransparency = 1, Text = entry.URL, TextColor3 = theme.Text,
                Font = Enum.Font.Gotham, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
                Position = UDim2.fromOffset(textStart, 0), Size = UDim2.new(1, -(textStart + 70), 1, 0), ZIndex = 7,
            }, linkRow)
            local hint = new("TextLabel", {
                BackgroundTransparency = 1, Text = "Copy", TextColor3 = theme.Muted,
                Font = Enum.Font.GothamBold, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Right,
                AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 0),
                Size = UDim2.fromOffset(52, rowH), ZIndex = 7,
            }, linkRow)
            linkRow.MouseEnter:Connect(function()
                tween(linkRow, 0.15, {BackgroundColor3 = pal.buttonHover})
                tween(linkStroke, 0.15, {Color = theme.Accent2, Transparency = 0.2})
            end)
            linkRow.MouseLeave:Connect(function()
                tween(linkRow, 0.15, {BackgroundColor3 = pal.button})
                tween(linkStroke, 0.15, {Color = strokeColor, Transparency = strokeRest})
            end)
            linkRow.MouseButton1Click:Connect(function()
                if ksCopy(entry.URL) then
                    hint.Text = "Copied!"
                    hint.TextColor3 = okColor()
                    tween(linkStroke, 0.15, {Color = okColor(), Transparency = 0})
                    setStatus("Link copied. Open it in your browser to get your key.", okColor())
                    DarkyX:Notify({title = "Link copied", content = "Open it in your browser to get your key.", icon = "link", duration = 3}, theme)
                    task.delay(0.9, function()
                        if not hint.Parent then return end
                        hint.Text = "Copy"
                        hint.TextColor3 = theme.Muted
                        tween(linkStroke, 0.2, {Color = strokeColor, Transparency = strokeRest})
                        setDropdown(false)
                    end)
                else
                    setStatus("Clipboard not supported: " .. entry.URL, theme.Danger)
                end
            end)
        end

        local submit -- assigned below, used by the Enter key

        -- input border states
        local strokeToken = 0
        local function flashInput(color)
            strokeToken += 1
            local token = strokeToken
            tween(inputStroke, 0.15, {Color = color, Transparency = 0, Thickness = 1.5})
            task.delay(0.9, function()
                if token ~= strokeToken or not input.Parent then return end
                local focused = input:IsFocused()
                tween(inputStroke, 0.35, {
                    Color = focused and theme.Accent2 or restStroke,
                    Transparency = focused and 0 or strokeRest,
                    Thickness = 1,
                })
            end)
        end
        input.Focused:Connect(function()
            strokeToken += 1
            tween(inputStroke, 0.15, {Color = theme.Accent2, Transparency = 0, Thickness = 1})
        end)
        input.FocusLost:Connect(function(enterPressed)
            strokeToken += 1
            tween(inputStroke, 0.2, {Color = restStroke, Transparency = strokeRest, Thickness = 1})
            if enterPressed and submit then task.defer(submit) end
        end)

        local closing = false
        local function closeUI()
            if closing then return end
            closing = true
            tween(card, 0.2, {GroupTransparency = 1})
            tween(rootScale, 0.2, {Scale = 0.94})
            tween(backdrop, 0.2, {BackgroundTransparency = 1})
            tween(keyDragPill, 0.2, {BackgroundTransparency = 1})
            if discordBox then tween(discordBox, 0.2, {BackgroundTransparency = 1}) end
            task.delay(0.24, function()
                if gui.Parent then gui:Destroy() end
            end)
        end

        local function shake()
            local rootBase = root.Position -- wherever the player dragged it to
            for _, dx in ipairs({8, -8, 5, -5, 0}) do
                tween(root, 0.05, {Position = UDim2.new(rootBase.X.Scale, rootBase.X.Offset + dx, rootBase.Y.Scale, rootBase.Y.Offset)}, Enum.EasingStyle.Sine)
                task.wait(0.05)
            end
        end

        local busy = false
        local limiter = Security.newLimiter(5, 20) -- 5 wrong keys -> locked 20s, doubling each round (max 5 min)
        local function accept(key)
            setStatus("Key accepted!", okColor())
            flashInput(okColor())
            DarkyX:Notify({title = "Key accepted", content = "Welcome! Loading your UI...", icon = "check", duration = 3}, theme)
            if savePath and type(writefile) == "function" then pcall(writefile, savePath, key) end
            task.wait(0.22)
            closeUI()
            system.Passed = true
            system.Key = key
            releaseGate()
            local cb = settings.Callback or settings.OnSuccess
            if type(cb) == "function" then Security.spawn(cb, key) end
            -- order: LoadingTitle -> key system -> (key UI fully gone) -> UI library opens.
            -- Nothing loads at the same time, and an error here can never break the key system.
            task.wait(0.28)
            local hold = liveWindow()
            if hold and hold._Held then
                local okRelease, releaseError = pcall(function() hold:_KeyRelease(ksReleaseToken) end)
                if not okRelease then Security.log("[DarkyX] UI library failed to open: " .. tostring(releaseError)) end
            end
        end

        submit = function()
            if busy or closing or system.Passed then return end
            local allowed, waitSeconds = limiter.check()
            if not allowed then
                setStatus("Too many wrong keys. Try again in " .. tostring(waitSeconds) .. "s.", theme.Danger)
                return
            end
            busy = true
            local key = Security.cleanKey(input.Text, 512)
            if plato and key ~= "" then setStatus("Checking your key...", theme.Muted) end
            local ok, message = validate(key)
            if closing then busy = false; return end
            if ok then
                limiter.success()
                accept(key)
            else
                limiter.fail()
                setStatus(message or "Invalid key.", theme.Danger)
                flashInput(theme.Danger)
                task.spawn(shake)
                busy = false
            end
        end
        continueButton.MouseButton1Click:Connect(submit)

        local linkBusy = false
        getButton.MouseButton1Click:Connect(function()
            if plato then
                -- Platoboost: generate the link for this player automatically and copy it
                if linkBusy then return end
                linkBusy = true
                setStatus("Generating your key link...", theme.Muted)
                getButton.Text = "Wait..."
                local okLink, link = plato.GetLink()
                linkBusy = false
                if not getButton.Parent then return end
                if not okLink then
                    getButton.Text = "Get Key"
                    setStatus(link or "Could not generate the key link.", theme.Danger)
                    return
                end
                if ksCopy(link) then
                    setStatus("Key link copied. Open it in your browser to get your key.", okColor())
                    DarkyX:Notify({title = "Link copied", content = "Open it in your browser to get your key.", icon = "link", duration = 3}, theme)
                    getButton.Text = "Copied!"
                    task.delay(1, function()
                        if getButton.Parent then getButton.Text = "Get Key" end
                    end)
                else
                    getButton.Text = "Get Key"
                    setStatus("Clipboard not supported: " .. link, theme.Danger)
                end
                return
            end
            if #urls == 0 then
                setStatus("No key link was set.", theme.Danger)
                return
            end
            if multiUrl then
                setDropdown(not dropOpen)
                return
            end
            local url = urls[1].URL
            if ksCopy(url) then
                setStatus("Key link copied. Open it in your browser to get your key.", okColor())
                DarkyX:Notify({title = "Link copied", content = "Open it in your browser to get your key.", icon = "link", duration = 3}, theme)
                getButton.Text = "Copied!"
                task.delay(1, function()
                    if getButton.Parent then getButton.Text = "Get Key" end
                end)
            else
                setStatus("Clipboard not supported: " .. url, theme.Danger)
            end
        end)

        pasteButton.MouseEnter:Connect(function() setPasteColor(theme.Accent2) end)
        pasteButton.MouseLeave:Connect(function() setPasteColor(theme.Muted) end)
        pasteButton.MouseButton1Click:Connect(function()
            local clip = ksReadClipboard()
            if clip == nil then
                setStatus("Clipboard read isn't supported here. Press Ctrl+V to paste.", theme.Danger)
                return
            end
            clip = clip:gsub("[\r\n]+", "")
            clip = ksTrim(clip)
            if clip == "" then
                setStatus("Your clipboard is empty.", theme.Muted)
                return
            end
            input.Text = clip
            setStatus("Pasted from clipboard.", okColor())
            setPasteColor(okColor())
            task.delay(0.8, function()
                if pasteButton.Parent then setPasteColor(theme.Muted) end
            end)
        end)

        if discordBox then
            discordBox.MouseButton1Click:Connect(function()
                if ksCopy(discordLink) then
                    setStatus("Discord link copied. Paste it in your browser to join.", okColor())
                    setDiscordColor(okColor())
                    DarkyX:Notify({title = "Discord copied", content = "Paste the invite in your browser to join.", icon = "check", duration = 3}, theme)
                    task.delay(1, function()
                        if discordBox.Parent then setDiscordColor(theme.Muted) end
                    end)
                else
                    setStatus("Clipboard not supported: " .. discordLink, theme.Danger)
                end
            end)
        end

        cancel.MouseButton1Click:Connect(function()
            if system.Passed or system.Cancelled or closing then return end
            system.Cancelled = true
            releaseGate()
            closeUI()
            local w2 = liveWindow()
            if w2 then w2:Destroy() end
            local cb = settings.OnCancel
            if type(cb) == "function" then Security.spawn(cb) end
        end)
    end

    local function run()
        local w = liveWindow()
        if not w and settings.Yield == false then
            -- not yielding: give CreateWindow a moment to be called right after us
            local started = os.clock()
            while not liveWindow() and os.clock() - started < 0.35 do task.wait() end
            w = liveWindow()
        end
        if w then
            -- CreateWindow was called right after us: follow its theme
            if settings.theme == nil and settings.Theme == nil then theme = getTheme(w.Theme) end
            if w._Loaded then w:_KeyHold() end
            -- the key UI appears once the window's LoadingTitle has finished
            while not w._Loaded and not w.Destroyed do task.wait(0.05) end
            if w.Destroyed then
                system.Cancelled = true
                releaseGate()
                return
            end
            task.wait(0.15)
        end
        build(w)
    end

    task.spawn(function()
        local ok, err = pcall(run)
        if not ok then
            Security.log("[DarkyX] Key system error: " .. tostring(err))
            system.Cancelled = true
            releaseGate()
            -- fail closed: the window stays hidden (a broken key screen must never open the UI), but say why
            pcall(function()
                DarkyX:Notify({title = "Key system error", content = "The key screen could not be built. See the console.", icon = "x", duration = 6}, theme)
            end)
        end
    end)

    if settings.Yield == false then return system end
    system:Wait()
    if system.Passed ~= true then
        -- closed / failed WITHOUT a verified key: the UI library stays locked and the script that called us
        -- is stopped here, so whatever comes after the key system (CreateWindow, features...) can never run.
        DarkyX._KeyDenied = true
        if settings.ContinueOnCancel == true then return false, system end -- opt-in: let the script handle it itself
        while true do task.wait(1e6) end
    end
    return true, system
end
DarkyX.CreateKeySystem = DarkyX.CreatekeySystem

-- DarkyX:SetTheme("cobalt") -> default theme for the key system and notifications that are created BEFORE the window
function DarkyX.SetTheme(a, b)
    local value = (a == DarkyX) and b or a
    DarkyX.CurrentTheme = getTheme(value)
    return DarkyX.CurrentTheme
end

return DarkyX
