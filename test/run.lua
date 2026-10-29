-- Offline tests for PB's KillLog. Stubs the ESO API and a LibHarvensAddonSettings just far enough to
-- run the add-on's files under LuaJIT (Lua 5.1):
--
--   luajit test/run.lua                                 PC, Japanese client
--   CONSOLE=1 LANGCODE=jp luajit test/run.lua           console, Japanese client
--   CONSOLE=1 LANGCODE=en luajit test/run.lua           console, English client
--   PANELSCENE=0 luajit test/run.lua                    PC copy of the library (no panel scene)
--
-- It is a stub, not the game: it cannot show that a font builds or a frame draws, only that the add-on
-- asks for the right things in the right order. LANGCODE is what GetCVar("language.2") returns.
local scriptDir = (arg and arg[0] or ""):match("^(.*)/[^/]*$") or "."
local ADDON_DIR = os.getenv("ADDON_DIR") or (scriptDir .. "/../")
local CONSOLE = os.getenv("CONSOLE") == "1"
local LANGCODE = os.getenv("LANGCODE") or "jp"
local HAS_PANEL_SCENE = os.getenv("PANELSCENE") ~= "0" -- console flow: the panel is its own scene
print(string.format("##### %s, language=%s, panel scene=%s", CONSOLE and "CONSOLE" or "PC", LANGCODE, tostring(HAS_PANEL_SCENE)))

local failures = 0
local function check(cond, msg)
    if cond then print("  ok   " .. msg) else print("  FAIL " .. msg); failures = failures + 1 end
end

---------------------------------------------------------------- generic control stub
local function Control(name, props)
    local c = { name = name, calls = {}, props = props or {}, last = {}, hidden = true, handlers = {} }
    return setmetatable(c, { __index = function(t, k)
        if k == "GetLeft" then return function() return t.props.left or 0 end end
        if k == "GetTop" then return function() return t.props.top or 0 end end
        if k == "GetWidth" then return function() return t.props.width or 0 end end
        if k == "GetHeight" then return function() return t.props.height or 0 end end
        if k == "IsHidden" then return function() return t.hidden end end
        if k == "GetFontHeight" then return function()
            -- A named gamepad font is drawn at the size its GP_ number maps to in the client's language (the
            -- Japanese client draws them smaller); a line is a quarter taller than the size. Anything else
            -- (the preview's descriptors) is 24.
            local number = type(t.font) == "string" and t.font:match("^ZoFontGamepad%a*(%d+)$")
            if number then
                local size = tonumber(number)
                if (LANGCODE == "jp" or LANGCODE == "ja") then size = ({ [18] = 14, [20] = 15, [22] = 17, [25] = 20, [27] = 21, [34] = 28, [42] = 34 })[size] or size end
                return math.ceil(size * 1.25)
            end
            return 24
        end end
        if k == "SetHidden" then return function(_, v) t.hidden = v; t.last.SetHidden = { v } end end
        if k == "SetText" then return function(_, v) t.text = v; t.last.SetText = { v } end end
        if k == "SetFont" then return function(_, v) t.font = v; t.last.SetFont = { v } end end
        if k == "SetHandler" then return function(_, n, fn) t.handlers[n] = fn end end
        return function(_, ...) t.calls[#t.calls + 1] = { k, ... }; t.last[k] = { ... } end
    end })
end

GuiRoot = Control("GuiRoot", { width = 1920, height = 1080 })
PBsKillLogWindow = Control("PBsKillLogWindow", { left = 60, top = 432, width = 640, height = 240 })
PBsKillLogWindowFrame = Control("Frame")
PBsKillLogWindowBuffer = Control("Buffer")
local messages = {}
function PBsKillLogWindowBuffer:AddMessage(text) messages[#messages + 1] = text end
function PBsKillLogWindowBuffer:Clear() messages = {} end
local bufferFont
function PBsKillLogWindowBuffer:SetFont(f) bufferFont = f end

local created = {}
WINDOW_MANAGER = {
    CreateTopLevelWindow = function(_, name) local c = Control(name); created[name] = c; return c end,
    CreateControl = function(_, name, parent, ctype) local c = Control(name); c.parent = parent; created[name] = c; return c end,
}

TOPLEFT, TOPRIGHT, BOTTOMLEFT, BOTTOMRIGHT, RIGHT = "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT", "RIGHT"
CT_TEXTURE, CT_LABEL, TEXT_WRAP_MODE_ELLIPSIS = "CT_TEXTURE", "CT_LABEL", "ELLIPSIS"
DT_LOW, DT_MEDIUM, DT_HIGH, DL_OVERLAY = 0, 1, 2, 9
ALLIANCE_ALDMERI_DOMINION, ALLIANCE_DAGGERFALL_COVENANT, ALLIANCE_EBONHEART_PACT = 1, 2, 3
SCENE_SHOWN, SCENE_HIDING = "shown", "hiding"
ACTION_RESULT_KILLING_BLOW, COMBAT_UNIT_TYPE_PLAYER = "KILLING_BLOW", "PLAYER"
REGISTER_FILTER_COMBAT_RESULT, REGISTER_FILTER_SOURCE_COMBAT_UNIT_TYPE = "F_RESULT", "F_SOURCE_TYPE"
SI_ABILITY_NAME, SI_DIALOG_ACCEPT, SI_DIALOG_CANCEL = "ABILITYNAME", 11, 12
GAMEPAD_DIALOGS = { BASIC = 1 }
SI_PVP_KILL_FEED_DEATH, SI_PVP_KILL_FEED_DEATH_AND_LOCATION = "DEATH", "DEATH_LOC"

function ZO_IsConsoleOrGameCoreUI() return CONSOLE end
function GetCVar(name) return LANGCODE end
function zo_round(v) return math.floor(v + 0.5) end
zo_floor, zo_max = math.floor, math.max
function zo_strformat(id, ...)
    local a = { ... }
    if id == "DEATH_LOC" then return string.format("%s%s defeated %s%s near %s", a[1], a[2], a[3], a[4], a[5]) end
    return string.format("%s%s defeated %s%s", a[1], a[2], a[3], a[4])
end

local Color = {}
Color.__index = Color
function Color:GetBright() return self end
function Color:Colorize(text) return "<" .. self.id .. ">" .. text .. "</>" end
function GetAllianceColor(a) return setmetatable({ id = "A" .. a }, Color) end
function ZO_GetColoredAvARankIconMarkup(rank, a, size) return "[rank" .. rank .. ":" .. size .. "]" end
function ZO_GetPrimaryPlayerName(display, char) return display end
-- where the player is: "cyrodiil", "imperialcity" (in the city), "icCampaignWorld" (in Cyrodiil's world while an
-- Imperial City campaign is played, outside the city), "battleground" or "elsewhere"
local zone = "cyrodiil"
-- The documentation does not say what IsInCyrodiil is in the Imperial City or in a Battleground. PB's Translate
-- found it false in the city, so both readings are tried in both places: the add-on's own checks have to cope.
local cyrodiilInCity, cyrodiilInBattleground = false, true
function IsInCyrodiil()
    if zone == "cyrodiil" or zone == "icCampaignWorld" then return true end
    if zone == "imperialcity" then return cyrodiilInCity end
    if zone == "battleground" then return cyrodiilInBattleground end
    return false
end
function IsInImperialCity() return zone == "imperialcity" end
function IsActiveWorldBattleground() return zone == "battleground" end
function GetDisplayName() return "@Me" end
function GetRawUnitName(tag) return "Myself^Mx" end
SOUNDS = { TRIBUTE_AGENT_KNOCKED_OUT = "Tribute_AgentKnockedOut" }
local sounds = {}
function PlaySound(name) sounds[#sounds + 1] = name end

local now = 1000
function GetFrameTimeMilliseconds() return now end

-- the two clocks: GetTimeStamp is UTC, GetSecondsSinceMidnight is local wall time (as PB's Omikuji found)
local function DaysFromCivil(y, m, d)
    if m <= 2 then y = y - 1 end
    local era = math.floor(y / 400)
    local yoe = y - era * 400
    local doy = math.floor((153 * (m + (m > 2 and -3 or 9)) + 2) / 5) + d - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    return era * 146097 + doe - 719468
end
local clockStamp, clockLocal = 0, 0
local function SetClock(y, m, d, hour, minute, tz)
    clockLocal = hour * 3600 + minute * 60
    clockStamp = DaysFromCivil(y, m, d) * 86400 + clockLocal - tz * 3600
end
function GetTimeStamp() return clockStamp end
function GetSecondsSinceMidnight() return clockLocal end
SetClock(2026, 10, 19, 12, 0, 9)

-- the client's death recap
local recap = {}
function GetNumKillingAttacks() return #recap end
function GetKillingAttackInfo(i)
    local a = recap[i]
    return a.name, 100, "icon", a.killingBlow, 500, 100, 1, a.id
end

-- zo_callLater: queued, run by the test when it wants the time to pass
local later = {}
function zo_callLater(fn, ms) later[#later + 1] = { fn = fn, ms = ms } end
local function RunLater() local q = later; later = {}; for _, item in ipairs(q) do item.fn() end return #q end

function ZO_CachedStrFormat(formatter, ...) return (...) end

-- confirmation dialogs
ESO_Dialogs = {}
local shownDialogs = {}
function ZO_Dialogs_ShowPlatformDialog(name, data, params) shownDialogs[#shownDialogs + 1] = { name = name, data = data } end
local function AnswerDialog(button)
    local d = table.remove(shownDialogs)
    local info = ESO_Dialogs[d.name]
    local b = info.buttons[button]
    if b.callback then b.callback({ data = d.data }) end
    return d.name
end

-- the real manifest's Title line, served the way GetAddOnManager serves it
local manifestTitle, manifestVersion
for line in io.lines(ADDON_DIR .. "PBsKillLog.addon") do
    manifestTitle = manifestTitle or line:match("^## Title: (.*)$")
    manifestVersion = manifestVersion or line:match("^## Version: (.*)$")
end
function GetAddOnManager()
    return {
        GetNumAddOns = function() return 2 end,
        GetAddOnInfo = function(_, i)
            if i == 1 then return "SomethingElse", "|cFF69B4PB's Other|r 9.9.9" end
            return "PBsKillLog", manifestTitle
        end,
    }
end

local handlers = {}
EVENT_ADD_ON_LOADED, EVENT_PVP_KILL_FEED_DEATH, EVENT_PLAYER_ACTIVATED = "ADDON_LOADED", "KILLFEED", "ACTIVATED"
EVENT_COMBAT_EVENT, EVENT_PLAYER_DEAD = "COMBAT", "DEAD"
local filters = {}
EVENT_MANAGER = {
    RegisterForEvent = function(_, ns, ev, fn) handlers[ev] = fn end,
    UnregisterForEvent = function(_, ns, ev) handlers[ev] = nil end,
    AddFilterForEvent = function(_, ns, ev, ...) filters[ev] = { ... } end,
}
SLASH_COMMANDS = {}
local chat = {}
CHAT_ROUTER = { AddSystemMessage = function(_, t) chat[#chat + 1] = t end }
ZO_SavedVars = { NewAccountWide = function(_, name, ver, ns, defaults)
    local sv = {}
    for k, v in pairs(defaults) do sv[k] = v end
    return sv
end }
local currentScene = "hud"
local scenesByName = {}
local allFragments = {}
local function FragmentShowing(f)
    local scene = scenesByName[currentScene]
    return scene ~= nil and scene.fragments[f] == true
end
ZO_SimpleSceneFragment = { New = function(_, control)
    local f = { control = control }
    f.IsShowing = function() return FragmentShowing(f) end
    allFragments[#allFragments + 1] = f
    return f
end }
local function MakeScene(name)
    local scene = { name = name, fragments = {} }
    function scene:AddFragment(f)
        self.fragments[f] = true
        if currentScene == self.name then f.control:SetHidden(false) end
    end
    function scene:RemoveFragment(f)
        self.fragments[f] = nil
        if currentScene == self.name then f.control:SetHidden(true) end
    end
    scenesByName[name] = scene
    return scene
end
HUD_SCENE = MakeScene("hud")
HUD_UI_SCENE = MakeScene("hudui")
-- moves to another scene: every fragment's control follows whether its scene holds it
local function GoToScene(name)
    currentScene = name
    for _, f in ipairs(allFragments) do f.control:SetHidden(not FragmentShowing(f)) end
end

local callbacks = {}
CALLBACK_MANAGER = {
    RegisterCallback = function(_, name, fn) callbacks[name] = callbacks[name] or {}; table.insert(callbacks[name], fn) end,
    FireCallbacks = function(_, name, ...) for _, fn in ipairs(callbacks[name] or {}) do fn(...) end end,
}

-- the library's panel scene (console)
local panelScene = {
    stateCallbacks = {}, showing = false,
    RegisterCallback = function(self, ev, fn) self.stateCallbacks[#self.stateCallbacks + 1] = fn end,
    IsShowing = function(self) return self.showing end,
}
local function SetPanelSceneState(state)
    panelScene.showing = (state == SCENE_SHOWN)
    for _, fn in ipairs(panelScene.stateCallbacks) do fn(panelScene, state) end
end
SCENE_MANAGER = {
    GetCurrentScene = function() return currentScene end,
    GetScene = function(_, name) return HAS_PANEL_SCENE and name == "LibHarvensAddonSettingsScene" and panelScene or nil end,
}

-- LibHarvensAddonSettings (API as read from votan73/ESO Addons/LibHarvensAddonSettings)
LibHarvensAddonSettings = {
    ST_CHECKBOX = 1, ST_SLIDER = 2, ST_EDIT = 3, ST_DROPDOWN = 4, ST_COLOR = 5, ST_BUTTON = 6,
    ST_LABEL = 7, ST_SECTION = 8, addons = {},
}
function LibHarvensAddonSettings:AddAddon(name)
    name = name:gsub("|[Cc][%w][%w][%w][%w][%w][%w]", ""):gsub("|[Rr]", "")
    local panel = { name = name, settings = {}, selected = false, updates = 0 }
    function panel:AddSetting(params, index) table.insert(self.settings, index or (#self.settings + 1), params) end
    function panel:AddSettings(rows, index)
        for i, params in ipairs(rows) do table.insert(self.settings, index and (index + i - 1) or (#self.settings + 1), params) end
    end
    function panel:RemoveSettings(index, count)
        for _ = 1, count or 1 do
            if not self.settings[index] then break end
            table.remove(self.settings, index)
        end
    end
    function panel:UpdateControls() self.updates = self.updates + 1 end
    table.insert(self.addons, panel)
    return panel
end

---------------------------------------------------------------- load
for _, f in ipairs({ "Localization.lua", "PBsKillLog.lua", "Records.lua", "Ranking.lua", "Preview.lua", "Settings.lua" }) do
    dofile(ADDON_DIR .. f)
end
local A = PBsKillLog
local L = A.L
local LIB = LibHarvensAddonSettings

print("== init")
handlers[EVENT_ADD_ON_LOADED](nil, "OtherAddon")
check(handlers[EVENT_PVP_KILL_FEED_DEATH] == nil, "ignores other add-ons' load events")
handlers[EVENT_ADD_ON_LOADED](nil, "PBsKillLog")
check(handlers[EVENT_PVP_KILL_FEED_DEATH] ~= nil, "registers EVENT_PVP_KILL_FEED_DEATH")
check(handlers[EVENT_ADD_ON_LOADED] == nil, "unregisters ADD_ON_LOADED")
check(SLASH_COMMANDS["/pbkl"] ~= nil, "registers /pbkl")
check(next(HUD_SCENE.fragments) ~= nil and next(HUD_UI_SCENE.fragments) ~= nil, "the window's fragment is on HUD and HUD_UI scenes")
check(bufferFont == "$(GAMEPAD_MEDIUM_FONT)|20|soft-shadow-thick", "default font string: " .. tostring(bufferFont))
check(A.sv.top == 432 and A.sv.left == 60, "default place derived from the screen")
check(PBsKillLogWindow.last.SetDrawTier[1] == DT_MEDIUM, "default draw tier medium")
check(PBsKillLogWindow.last.SetMouseEnabled == nil and PBsKillLogWindow.last.SetMovable == nil and PBsKillLogWindow.last.SetResizeHandleSize == nil, "init never touches mouse/move/resize")
check(next(created) == nil, "no preview control is built until it is wanted")

print("== name, version, apostrophe")
local panel = LIB.addons[1]
check(manifestTitle == "|cFF69B4PB's KillLog|r " .. tostring(manifestVersion), "manifest Title is pink 'PB's KillLog' + the Version line: " .. tostring(manifestTitle))
check(A.version == manifestVersion and A.version ~= "", "version read back from Title: '" .. tostring(A.version) .. "'")
check(panel ~= nil and panel.name == A.title, "settings panel registered under ADDON.title: " .. tostring(panel and panel.name))
check(A.title == "PB’s KillLog " .. A.version, "title is the display name + version")
check(A.title:find("'", 1, true) == nil and A.title:find("’", 1, true) ~= nil, "title uses the typographic apostrophe, no ASCII one")
local function ConsoleListName(addonName) local _, name = addonName:match("^(.+)'s%s(.+)"); return name or addonName end
check(ConsoleListName(A.title) == A.title, "console list keeps the whole name: " .. ConsoleListName(A.title))
check(ConsoleListName("PB's KillLog " .. A.version) == "KillLog " .. A.version, "(an ASCII apostrophe would have been split down to 'KillLog')")
check(panel.author == "PinkBanther" and panel.version == manifestVersion, "panel shows manifest author and version")
check(panel.allowDefaults == true, "reset-to-defaults enabled")

print("== language")
local expectJa = (LANGCODE == "jp" or LANGCODE == "ja")
check((L("KILL_SOUND") == "自分がキルした時に効果音を鳴らす") == expectJa, "L() language for '" .. LANGCODE .. "': " .. L("KILL_SOUND"))
local function hasNonAscii(s) return s:find("[\128-\255]") ~= nil end
local function Text(v) if type(v) == "function" then return v() end return v end
local function CheckLanguage(panelToCheck, what)
    local bad = 0
    for _, o in ipairs(panelToCheck.settings) do
        for _, field in ipairs({ "label", "tooltip", "buttonText" }) do
            local v = o[field]
            if v ~= nil then
                v = Text(v)
                if type(v) ~= "string" or v:match("^[A-Z_]+$") then bad = bad + 1; print("    raw key shown: " .. tostring(v)) end
                local plain = v:match("^[%-%d%s%.]*$") ~= nil -- a dash or a number needs no translation
                if expectJa and not plain and not hasNonAscii(v) then bad = bad + 1; print("    not Japanese: " .. v) end
                if not expectJa and hasNonAscii(v) then bad = bad + 1; print("    not English: " .. v) end
            end
        end
        if o.items then
            for _, item in ipairs(o.items) do
                if expectJa ~= hasNonAscii(item.name) then bad = bad + 1; print("    dropdown item in the wrong language: " .. item.name) end
            end
        end
    end
    check(bad == 0, what)
end
CheckLanguage(panel, expectJa and "every label, tooltip, button and dropdown item in the panel is Japanese, none is a raw key" or "every label in the panel is English, none is a raw key")
local ranksOk = true
for index = 1, 18 do
    local name = L("RANK_" .. index)
    if name == "RANK_" .. index or name == "" or hasNonAscii(name) ~= expectJa then ranksOk = false; print("    rank name " .. index .. ": " .. name) end
end
check(ranksOk, "all 18 rank names exist in the client language")

print("== panel structure")
local function opt(key) for _, o in ipairs(panel.settings) do if o.label == L(key) and o.type ~= LIB.ST_SECTION then return o end end end
check(panel.settings[1].type == LIB.ST_LABEL and panel.settings[1].label == L("EXPLANATION"), "starts with the explanation")
local unlock = opt("UNLOCK")
check((unlock ~= nil) == (not CONSOLE), "unlock checkbox exists on PC only")
local px, py, pw, ph, pf = opt("POS_X"), opt("POS_Y"), opt("WIDTH"), opt("HEIGHT"), opt("FONT_SIZE")
check(px.type == LIB.ST_SLIDER and px.min == 0 and px.max == 1920 and px.step == 5 and px.default == 60, "X slider: 0-1920 step 5 default 60")
check(py.max == 1080 and py.default == 432, "Y slider: max 1080, default 432")
check(pw.min == 160 and pw.max == 1920 and pw.default == 640 and ph.min == 48 and ph.max == 1080 and ph.default == 240, "width/height ranges and defaults")
check(pf.min == 12 and pf.max == 64 and pf.step == 1 and pf.default == 20, "font size 12-64 default 20")
for _, o in ipairs({ px, py, pw, ph, pf }) do check(o.getFunction() == A.sv[o == px and "left" or o == py and "top" or o == pw and "width" or o == ph and "height" or "fontSize"], "getFunction reads the saved value of '" .. o.label .. "'") end
local tier = opt("DRAW_TIER")
check(tier.type == LIB.ST_DROPDOWN and #tier.items == 3 and tier.default == tier.getFunction(), "tier dropdown: 3 items, default selected")
local level = opt("DRAW_LEVEL")
check(level.min == 0 and level.max == 100 and level.step == 5 and level.default == 0, "draw level 0-100 step 5")
local ksound = opt("KILL_SOUND")
check(ksound.type == LIB.ST_CHECKBOX and ksound.default == true and ksound.getFunction() == true, "kill sound checkbox, default on")
local pcheck = opt("PREVIEW")
check(pcheck.type == LIB.ST_CHECKBOX and pcheck.default == true and pcheck.getFunction() == true, "preview checkbox, default on")
local sections = 0
for _, o in ipairs(panel.settings) do if o.type == LIB.ST_SECTION then sections = sections + 1 end end
check(sections == 9, "nine sections (rank, ranking window, daily records, attacks, window, text, layer, sound, log)")
check(opt("TEST").type == LIB.ST_BUTTON and opt("CLEAR").type == LIB.ST_BUTTON and opt("TEST").buttonText == L("BUTTON_RUN"), "test and clear buttons")

print("== setting rows act on the window")
px.setFunction(300)
check(A.sv.left == 300 and PBsKillLogWindow.last.SetAnchor[4] == 300, "X slider stores and anchors")
pw.setFunction(700); ph.setFunction(260)
check(PBsKillLogWindow.last.SetDimensions[1] == 700 and PBsKillLogWindow.last.SetDimensions[2] == 260, "width/height slider resize the window")
pf.setFunction(26)
check(A.sv.fontSize == 26 and bufferFont == "$(GAMEPAD_MEDIUM_FONT)|26|soft-shadow-thick", "font slider stores and applies")
tier.setFunction(nil, "x", tier.items[3])
check(A.sv.drawTier == "high" and PBsKillLogWindow.last.SetDrawTier[1] == DT_HIGH, "tier dropdown applies")
level.setFunction(15)
check(PBsKillLogWindow.last.SetDrawLevel[1] == 15, "level slider applies")
check(tier.getFunction() == tier.items[3].name, "dropdown shows the stored tier")
-- reset-to-defaults replays every default through its setFunction
px.setFunction(px.default); pw.setFunction(pw.default); ph.setFunction(ph.default); pf.setFunction(pf.default)
tier.setFunction(nil, tier.default, tier.items[2]); level.setFunction(level.default)
check(A.sv.left == 60 and A.sv.width == 640 and A.sv.height == 240 and A.sv.fontSize == 20 and A.sv.drawTier == "medium" and A.sv.drawLevel == 0, "defaults restore the window")

---------------------------------------------------------------- kill feed
print("== kill feed")
local fire = handlers[EVENT_PVP_KILL_FEED_DEATH]
fire(0, "Chalman Keep", "@Alice", "Alice", 1, 12, "@Bob", "Bob", 3, 4, false)
check(#messages == 1 and messages[1] == "<A1>@Alice</>[rank12:27] defeated <A3>@Bob</>[rank4:27] near Chalman Keep", "one kill -> one formatted line: " .. tostring(messages[1]))
fire(0, "Chalman Keep", "@Alice", "Alice", 1, 12, "@Bob", "Bob", 3, 4, true)
check(#messages == 1, "same kill from the kill-location source within 10s is suppressed")
now = now + 3000
fire(0, "", "@Carol", "Carol", 2, 1, "@Dave", "Dave", 3, 1, true)
fire(0, "", "@Carol", "Carol", 2, 1, "@Dave", "Dave", 3, 1, false)
check(#messages == 2 and messages[2]:find("near") == nil, "kill-location first, then local duplicate -> one line, no 'near'")
now = now + 3000
fire(0, "", "@Carol", "Carol", 2, 1, "@Dave", "Dave", 3, 1, false)
fire(0, "", "@Carol", "Carol", 2, 1, "@Dave", "Dave", 3, 1, true)
check(#messages == 3, "a repeat from the same source is shown, its twin then suppressed")
now = now + 11000
fire(0, "", "@Carol", "Carol", 2, 1, "@Dave", "Dave", 3, 1, true)
check(#messages == 4, "after 10s the twin of an old kill counts as new")

print("== Cyrodiil and the Imperial City only")
local activated = handlers[EVENT_PLAYER_ACTIVATED]
check(activated ~= nil, "registers EVENT_PLAYER_ACTIVATED")
check(PBsKillLogWindowBuffer.hidden == true, "the log text starts hidden until the player is known to be somewhere it applies")
activated()
check(PBsKillLogWindowBuffer.hidden == false, "entering the world in Cyrodiil shows the log")
local shownBefore = #messages

-- not in a Battleground (whatever IsInCyrodiil says there) and not anywhere else
for _, case in ipairs({ { "battleground", false }, { "battleground", true }, { "elsewhere", false } }) do
    zone, cyrodiilInBattleground = case[1], case[2]
    now = now + 20000
    fire(0, "", "@Eve" .. case[1], "Eve", 1, 1, "@Frank", "Frank", 2, 1, false)
    fire(0, "", "@Me", "Myself^Mx", 1, 1, "@Gus" .. case[1], "Gus", 2, 1, false)
    activated()
    local what = case[1] .. (case[1] == "battleground" and (case[2] and " (IsInCyrodiil true there)" or " (IsInCyrodiil false there)") or "")
    check(#messages == shownBefore and #sounds == 0, "kills in '" .. what .. "' are not logged and play no sound")
    check(PBsKillLogWindowBuffer.hidden == true, "the log text is hidden in '" .. what .. "'")
end
cyrodiilInBattleground = true

-- the Imperial City: in the city, whatever IsInCyrodiil says there, and the world of its campaigns
local shownBeforeCity = #messages
local cityCases = {
    { place = "imperialcity", cyrodiil = false, what = "in the Imperial City (IsInCyrodiil false there)" },
    { place = "imperialcity", cyrodiil = true, what = "in the Imperial City (IsInCyrodiil true there)" },
    { place = "icCampaignWorld", cyrodiil = true, what = "in Cyrodiil's world during an Imperial City campaign" },
}
for index, case in ipairs(cityCases) do
    zone, cyrodiilInCity = case.place, case.cyrodiil
    now = now + 20000
    local linesBefore = #messages
    fire(0, "", "@CityEve" .. index, "Eve", 1, 1, "@CityFrank" .. index, "Frank", 2, 1, false)
    fire(0, "", "@Me", "Myself^Mx", 1, 1, "@CityGus" .. index, "Gus", 2, 1, false)
    PBsKillLogWindowBuffer.hidden = true
    activated()
    check(#messages == linesBefore + 2, "kills " .. case.what .. " are logged")
    check(#sounds == 1 and sounds[1] == "Tribute_AgentKnockedOut", "...and the player's own kill there plays the sound")
    sounds = {}
    check(PBsKillLogWindowBuffer.hidden == false, "...and the log text is shown there")
end
zone, cyrodiilInCity = "cyrodiil", false
shownBefore = #messages

now = now + 20000
activated()
check(PBsKillLogWindowBuffer.hidden == false, "back in Cyrodiil the log shows again")
fire(0, "", "@Eve", "Eve", 1, 1, "@Frank", "Frank", 2, 1, false)
check(#messages == shownBefore + 1, "...and kills are logged again")
-- a kill that arrives while the zone says otherwise leaves no trace in the duplicate filter either
zone = "battleground"
fire(0, "", "@Hal", "Hal", 1, 1, "@Ivy", "Ivy", 2, 1, false)
zone = "cyrodiil"
fire(0, "", "@Hal", "Hal", 1, 1, "@Ivy", "Ivy", 2, 1, true)
check(#messages == shownBefore + 2, "a Cyrodiil kill is not mistaken for the twin of one that was ignored in a Battleground")
local chatBefore = #chat
SLASH_COMMANDS["/pbkl"]("test")
check(#chat == chatBefore, "/pbkl test in Cyrodiil needs no warning")
zone = "elsewhere"
SLASH_COMMANDS["/pbkl"]("test")
check(chat[#chat] == "[PBsKillLog] " .. L("CMD_TEST_ELSEWHERE"), "/pbkl test elsewhere says where the log is drawn")
zone = "imperialcity"
chatBefore = #chat
SLASH_COMMANDS["/pbkl"]("test")
check(#chat == chatBefore, "/pbkl test in the Imperial City needs no warning either")
zone = "cyrodiil"


print("== kill sound")
check(#sounds == 0, "other players' kills played no sound")
now = now + 20000
fire(0, "", "@Me", "SomeoneElse^Fx", 1, 5, "@Bob", "Bob", 3, 1, false)
check(#sounds == 1 and sounds[1] == "Tribute_AgentKnockedOut", "own kill (display name) plays the Tribute knock-out sound")
fire(0, "", "@Me", "SomeoneElse^Fx", 1, 5, "@Bob", "Bob", 3, 1, true)
check(#sounds == 1, "its kill-location twin does not play it again")
now = now + 20000
fire(0, "", "@Other", "Myself^Mx", 1, 5, "@Carl", "Carl", 3, 1, false)
check(#sounds == 2, "own kill matched by raw character name plays it")
now = now + 20000
fire(0, "", "@Other", "Other^Mx", 1, 5, "@Me", "Myself^Mx", 3, 1, false)
fire(0, "", "", "", 1, 5, "@Dan", "Dan", 3, 1, false)
check(#sounds == 2, "being the victim, or an empty killer, plays nothing")
local linesBefore = #messages
ksound.setFunction(false)
now = now + 20000
fire(0, "", "@Me", "Myself^Mx", 1, 5, "@Erin", "Erin", 3, 1, false)
check(#sounds == 2 and #messages == linesBefore + 1, "sound off: kill still logged, silent")
ksound.setFunction(true)
check(#sounds == 3, "switching it on previews the sound")
sounds = {}

---------------------------------------------------------------- preview
print("== preview: console flow (list -> panel scene)")
local function OpenPanel()
    -- what the library does: Select() fires AddonSelected, sets .selected, then pushes the scene.
    -- (The PC copy has no scene of its own: the settings page is already the scene when a panel is picked.)
    if HAS_PANEL_SCENE then
        GoToScene("list")
        CALLBACK_MANAGER:FireCallbacks("LibHarvensAddonSettings_AddonSelected", panel.name, panel)
        panel.selected = true
        GoToScene("panel")
        SetPanelSceneState(SCENE_SHOWN)
    else
        GoToScene("panel")
        CALLBACK_MANAGER:FireCallbacks("LibHarvensAddonSettings_AddonSelected", panel.name, panel)
        panel.selected = true
    end
end
local function ClosePanel()
    if HAS_PANEL_SCENE then SetPanelSceneState(SCENE_HIDING) end
    panel.selected = false
    GoToScene("hud")
    -- the PC copy of the library has no panel scene: the preview notices on its next poll
    if not HAS_PANEL_SCENE then
        now = now + 400
        if created["PBsKillLogPreview"] then created["PBsKillLogPreview"].handlers.OnUpdate() end
        if created["PBsKillLogRanking"] then created["PBsKillLogRanking"].handlers.OnUpdate() end
    end
end
if HAS_PANEL_SCENE then
    GoToScene("list")
    CALLBACK_MANAGER:FireCallbacks("LibHarvensAddonSettings_AddonSelected", panel.name, panel)
    local pv = created["PBsKillLogPreview"]
    check(pv == nil or pv.hidden, "AddonSelected while the list is still the scene shows nothing yet")
    panel.selected = true
    GoToScene("panel")
    SetPanelSceneState(SCENE_SHOWN)
else
    GoToScene("panel")
    CALLBACK_MANAGER:FireCallbacks("LibHarvensAddonSettings_AddonSelected", panel.name, panel)
    panel.selected = true
end
local pv = created["PBsKillLogPreview"]
check(pv ~= nil and not pv.hidden, "preview is shown once the panel is open")
check(pv.last.SetDrawLayer[1] == DL_OVERLAY and pv.last.SetDrawTier[1] == DT_HIGH and pv.last.SetMouseEnabled[1] == false, "drawn above the panel, never takes input")
check(pv.last.SetAnchor[1] == "TOPLEFT" and pv.last.SetAnchor[4] == A.sv.left and pv.last.SetAnchor[5] == A.sv.top, "frame sits at the window's place")
check(pv.last.SetDimensions[1] == 640 and pv.last.SetDimensions[2] == 240, "frame has the window's size")
local cap = created["PBsKillLogPreviewCaption"]
check(cap.text == L("PREVIEW_CAPTION") and cap.last.SetAnchor[1] == "BOTTOMLEFT", "caption sits above the frame")
local function shownLines()
    local n = 0
    for i = 1, 40 do local l = created["PBsKillLogPreviewLine" .. i]; if l and not l.hidden then n = n + 1 end end
    return n
end
-- 24 high lines inside 240 - 12 -> 9
check(shownLines() == 9, "9 sample lines fit a 240 high frame at 24 per line: " .. shownLines())
local bottom, second = created["PBsKillLogPreviewLine1"], created["PBsKillLogPreviewLine2"]
check(bottom.font == "$(GAMEPAD_MEDIUM_FONT)|20|soft-shadow-thick", "sample lines use the window's font descriptor: " .. tostring(bottom.font))
check(bottom.text:find("%[rank15:27%]") ~= nil and second.text:find("%[rank6:27%]") ~= nil, "sample kills are formatted like real ones (newest at the bottom)")
check(bottom.last.SetAnchor[1] == "BOTTOMRIGHT" and second.last.SetAnchor[2] == bottom, "lines stack upwards from the bottom")

print("== preview follows the settings")
pw.setFunction(900); ph.setFunction(120)
check(pv.last.SetDimensions[1] == 900 and pv.last.SetDimensions[2] == 120, "width/height sliders resize the frame at once")
check(shownLines() == 4, "a shorter frame shows fewer lines: " .. shownLines())
px.setFunction(10); py.setFunction(10)
check(pv.last.SetAnchor[4] == 10 and pv.last.SetAnchor[5] == 10, "position sliders move the frame")
check(cap.last.SetAnchor[1] == "TOPLEFT", "near the top the caption drops below the frame")
pf.setFunction(40)
check(bottom.font == "$(GAMEPAD_MEDIUM_FONT)|40|soft-shadow-thick" and bottom.text:find("%[rank15:53%]") ~= nil, "font slider changes sample text and icon size")
px.setFunction(60); py.setFunction(432); pw.setFunction(640); ph.setFunction(240); pf.setFunction(20)

print("== preview checkbox, closing, other panels")
pcheck.setFunction(false)
check(pv.hidden, "preview checkbox off hides the frame")
check(A.sv.preview == false, "...and is remembered")
pcheck.setFunction(true)
check(not pv.hidden, "preview checkbox on shows it again")
ClosePanel()
check(pv.hidden, "closing the panel hides it")
OpenPanel()
check(not pv.hidden, "opening the panel a second time shows it again")
currentScene = "somewhere else"
now = now + 400
pv.handlers.OnUpdate()
check(pv.hidden, "the preview goes away by itself when the scene changes under it")
GoToScene("hud")
panel.selected = false
OpenPanel()
local other = { name = "Other add-on" }
CALLBACK_MANAGER:FireCallbacks("LibHarvensAddonSettings_AddonSelected", other.name, other)
check(pv.hidden, "picking another add-on's panel hides it")
ClosePanel()

print("== /pbkl preview")
SLASH_COMMANDS["/pbkl"]("preview")
check(not pv.hidden and chat[#chat] == "[PBsKillLog] " .. L("CMD_PREVIEW_ON"), "/pbkl preview shows the frame anywhere: " .. chat[#chat])
now = now + 400
pv.handlers.OnUpdate()
check(not pv.hidden, "...and it stays while the scene is unchanged")
SLASH_COMMANDS["/pbkl"]("preview")
check(pv.hidden and chat[#chat] == "[PBsKillLog] " .. L("CMD_PREVIEW_OFF"), "/pbkl preview again hides it")

---------------------------------------------------------------- lock / commands
print("== lock, commands")
check(A.IsUnlocked() == false, "starts locked")
if CONSOLE then
    SLASH_COMMANDS["/pbkl"]("unlock")
    check(A.IsUnlocked() == false and chat[#chat] == "[PBsKillLog] " .. L("CMD_NO_CURSOR"), "console: /pbkl unlock is refused and explained")
    check(PBsKillLogWindow.last.SetMouseEnabled == nil, "console: window never becomes mouse-enabled")
else
    SLASH_COMMANDS["/pbkl"]("unlock")
    check(A.IsUnlocked() and PBsKillLogWindow.last.SetMovable[1] == true and PBsKillLogWindow.last.SetResizeHandleSize[1] == 8 and PBsKillLogWindow.last.SetMouseEnabled[1] == true, "/pbkl unlock makes it movable")
    check(PBsKillLogWindowFrame.hidden == false, "frame visible while unlocked")
    unlock.setFunction(false)
    check(PBsKillLogWindow.last.SetMouseEnabled[1] == false and PBsKillLogWindowFrame.hidden == true, "unlock checkbox off: click-through again, frame hidden")
    unlock.setFunction(true)
    PBsKillLogWindow.props = { left = 100.4, top = 250.6, width = 500, height = 300 }
    panel.selected = true
    local before = panel.updates
    A.OnMoveStop()
    check(A.sv.left == 100 and A.sv.top == 251 and A.sv.width == 500 and A.sv.height == 300, "drag/resize saved (rounded)")
    check(panel.updates == before + 1, "an open panel re-reads its rows after a drag")
    panel.selected = false
    A.OnResizeStop()
    check(panel.updates == before + 1, "a closed panel is left alone")
    SLASH_COMMANDS["/pbkl"]("lock")
    unlock.setFunction(false)
end
SLASH_COMMANDS["/pbkl"]("test")
check(#messages > 0 and messages[#messages]:find(L("TEST_LOCATION"), 1, true) ~= nil, "/pbkl test adds a line")
SLASH_COMMANDS["/pbkl"]("  CLEAR ")
check(#messages == 0, "/pbkl clear empties the log")
opt("TEST").clickHandler()
check(#messages == 1, "test button adds a line")
opt("CLEAR").clickHandler()
check(#messages == 0, "clear button empties the log")
SLASH_COMMANDS["/pbkl"]("")
check(chat[#chat] == "[PBsKillLog] " .. L("CMD_HELP") and L("CMD_HELP"):find("preview") ~= nil, "no argument prints help (mentions preview)")
SLASH_COMMANDS["/pbkl"]("sound off")
check(A.sv.killSound == false and chat[#chat] == "[PBsKillLog] " .. L("CMD_SOUND_OFF"), "/pbkl sound off")
SLASH_COMMANDS["/pbkl"]("sound")
check(A.sv.killSound == true and #sounds == 1, "/pbkl sound toggles on with a preview")
A.sv.left, A.sv.fontSize, A.sv.killSound = 999, 33, false
panel.selected = true
local before = panel.updates
SLASH_COMMANDS["/pbkl"]("reset")
check(A.sv.left == 60 and A.sv.fontSize == 20 and A.sv.killSound == false, "/pbkl reset restores the window, leaves the sound option")
check(panel.updates == before + 1, "...and an open panel re-reads its rows")
panel.selected = false

---------------------------------------------------------------- crash guards
---------------------------------------------------------------- daily records, ranks, ranking window
print("== which day it is")
local R = A.records
local WD_MON, WD_TUE = expectJa and "月" or "Mon", expectJa and "火" or "Tue"
local function DateOf() return R:DateText(R:DayKey()) end
SetClock(2026, 10, 19, 12, 0, 9)
check(DateOf() == "2026/10/19(" .. WD_MON .. ")", "noon in Japan is 2026/10/19: " .. DateOf())
SetClock(2026, 10, 19, 8, 0, 9)
check(DateOf() == "2026/10/19(" .. WD_MON .. ")", "08:00 in Japan is still the 19th although UTC says the 18th")
SetClock(2026, 10, 19, 23, 59, 9)
check(DateOf() == "2026/10/19(" .. WD_MON .. ")", "23:59 is still the 19th")
SetClock(2026, 10, 20, 0, 1, 9)
check(DateOf() == "2026/10/20(" .. WD_TUE .. ")", "00:01 is the 20th")
local zonesOk = true
for _, tz in ipairs({ -8, -5, 0, 1, 5.5, 9, 12 }) do
    SetClock(2026, 10, 19, 20, 30, tz)
    if DateOf():sub(1, 10) ~= "2026/10/19" then zonesOk = false; print("    UTC" .. tz .. ": " .. DateOf()) end
end
check(zonesOk, "20:30 is the 19th in every timezone from UTC-8 to UTC+12")
local y, m, d = R:CivilFromDays(DaysFromCivil(2024, 2, 29))
check(y == 2024 and m == 2 and d == 29, "a leap day survives the calendar conversion")
y, m, d = R:CivilFromDays(DaysFromCivil(2100, 3, 1))
check(y == 2100 and m == 3 and d == 1, "so does a century that is not a leap year")

print("== counting kills and deaths")
R:ResetAll()
SetClock(2026, 10, 19, 12, 0, 9)
local function Feed(killer, killerChar, victim, victimChar, isLocation, advance)
    if advance ~= false then now = now + 20000 end
    fire(0, "", killer, killerChar, 1, 5, victim, victimChar, 3, 1, isLocation or false)
end
local function Day() return R:Day(R:DayKey()) end
Feed("@Me", "Myself^Mx", "@Bob", "Bob^Mx")
local tk, td = R:Totals()
check(tk == 1 and td == 0 and Day().kills == 1 and Day().deaths == 0, "a kill is counted in the totals and in today")
check(Day().killedPlayers["@Bob"] and Day().killedPlayers["@Bob"].count == 1, "...with the player that was killed")
Feed("@Carl", "Carl^Mx", "@Me", "Myself^Mx")
tk, td = R:Totals()
check(tk == 1 and td == 1 and Day().deaths == 1, "a death is counted")
check(Day().diedToPlayers["@Carl"] and Day().diedToPlayers["@Carl"].count == 1, "...with the player who killed the player")
Feed("@Alice", "Alice^Fx", "@Bob", "Bob^Mx")
tk, td = R:Totals()
check(tk == 1 and td == 1, "other players' kills are not counted")
Feed("@Me", "Myself^Mx", "@Dan", "Dan^Mx")
Feed("@Me", "Myself^Mx", "@Dan", "Dan^Mx", true, false)
tk = R:Totals()
check(tk == 2, "the kill-location twin of a kill is not counted twice")
zone = "battleground"
Feed("@Me", "Myself^Mx", "@Eve", "Eve^Fx"); Feed("@Fay", "Fay^Fx", "@Me", "Myself^Mx")
zone = "elsewhere"
Feed("@Me", "Myself^Mx", "@Eve", "Eve^Fx")
zone = "cyrodiil"
tk, td = R:Totals()
check(tk == 2 and td == 1, "kills and deaths in a Battleground or anywhere else are not counted")
Feed("@Me", "Myself^Mx", "@Me", "Myself^Mx")
tk, td = R:Totals()
check(tk == 2 and td == 2, "a player on both sides is counted once, as a death")
A.sv.killSound = false
Feed("@Me", "Myself^Mx", "@Gil", "Gil^Mx")
A.sv.killSound = true
tk = R:Totals()
check(tk == 3, "counting does not depend on the sound option")
SetClock(2026, 10, 20, 9, 0, 9)
Feed("@Me", "Myself^Mx", "@Hal", "Hal^Mx")
local keys = R:DayKeys()
check(#keys == 2 and keys[1] == keys[2] + 1, "the next day starts a record of its own, newest first")
local k1, d1 = R:Counts(keys[2])
local k2, d2 = R:Counts(keys[1])
check(k1 == 3 and d1 == 2 and k2 == 1 and d2 == 0, "each day keeps its own counts")
local ak, ad = R:Counts("all")
check(ak == 4 and ad == 2, "the 'all days' counts add the days up")

print("== counting in the Imperial City")
R:ResetAll()
SetClock(2026, 10, 19, 12, 0, 9)
for _, reading in ipairs({ false, true }) do
    R:ResetAll()
    cyrodiilInCity = reading
    zone = "imperialcity"
    handlers[EVENT_COMBAT_EVENT](0, ACTION_RESULT_KILLING_BLOW, false, "Wrecking Blow", 0, 0, "Myself^Mx", COMBAT_UNIT_TYPE_PLAYER, "Bob^Mx", "PLAYER", 100, 0, 0, true, 1, 2, 111, 0)
    now = now + 500
    Feed("@Me", "Myself^Mx", "@Bob", "Bob^Mx", false, false)
    Feed("@Carl", "Carl^Mx", "@Me", "Myself^Mx")
    local ck, cd = R:Totals()
    local day = R:Day(R:DayKey())
    local note = reading and " (IsInCyrodiil true there)" or " (IsInCyrodiil false there)"
    check(ck == 1 and cd == 1, "a kill and a death in the Imperial City are counted" .. note)
    check(day.killedPlayers["@Bob"] and day.diedToPlayers["@Carl"], "...with the players on the other side" .. note)
    check(day.killedWith["111"] and day.killedWith["111"].count == 1, "...and the killing blow is paired with the kill" .. note)
    zone = "icCampaignWorld"
    Feed("@Me", "Myself^Mx", "@Dan", "Dan^Mx")
    ck = R:Totals()
    check(ck == 2, "so is a kill in Cyrodiil's world during an Imperial City campaign")
    zone = "battleground"
    Feed("@Me", "Myself^Mx", "@Eve", "Eve^Fx")
    ck = R:Totals()
    check(ck == 2, "a Battleground kill is still not counted")
end
zone, cyrodiilInCity = "cyrodiil", false
R:ResetAll()

print("== skills and players")
R:ResetAll()
SetClock(2026, 10, 19, 12, 0, 9)
local function Blow(abilityName, abilityId, targetName)
    handlers[EVENT_COMBAT_EVENT](0, ACTION_RESULT_KILLING_BLOW, false, abilityName, 0, 0, "Myself^Mx", COMBAT_UNIT_TYPE_PLAYER, targetName, "PLAYER", 100, 0, 0, true, 1, 2, abilityId, 0)
end
local f = filters[EVENT_COMBAT_EVENT]
check(f and f[1] == REGISTER_FILTER_COMBAT_RESULT and f[2] == ACTION_RESULT_KILLING_BLOW and f[3] == REGISTER_FILTER_SOURCE_COMBAT_UNIT_TYPE and f[4] == COMBAT_UNIT_TYPE_PLAYER, "the combat event is filtered to the player's own killing blows")
check(handlers[EVENT_PLAYER_DEAD] ~= nil, "registers EVENT_PLAYER_DEAD")
local function KilledWith() return Day().killedWith end
now = now + 20000; Blow("Wrecking Blow", 111, "Bob^Mx"); now = now + 500
Feed("@Me", "Myself^Mx", "@Bob", "Bob^Mx", false, false)
check(KilledWith()["111"] and KilledWith()["111"].count == 1 and KilledWith()["111"].name == "Wrecking Blow", "a killing blow that came before the feed line is attributed")
Feed("@Me", "Myself^Mx", "@Cat", "Cat^Fx")
now = now + 500; Blow("Crystal Blast", 222, "Cat^Fx")
check(KilledWith()["222"] and KilledWith()["222"].count == 1, "so is one that comes after it")
now = now + 20000; Blow("Wrecking Blow", 111, "Zed^Mx"); now = now + 500
Feed("@Me", "Myself^Mx", "@Eli", "Eli^Mx", false, false)
check(KilledWith()["111"].count == 1, "a killing blow on somebody else is not given to this kill")
now = now + 20000; Blow("Wrecking Blow", 111, "Fin"); now = now + 500
Feed("@Me", "Myself^Mx", "@Fin", "Fin^Mx", false, false)
check(KilledWith()["111"].count == 2, "a name with and without its gender mark is the same player")
now = now + 20000; Blow("Old Blow", 333, "Gus^Mx"); now = now + 4000
Feed("@Me", "Myself^Mx", "@Gus", "Gus^Mx", false, false)
check(KilledWith()["333"] == nil, "a killing blow from four seconds before is not paired")
now = now + 20000; Blow("Mystery", 0, "Hex^Mx"); now = now + 100
Feed("@Me", "Myself^Mx", "@Hex", "Hex^Mx", false, false)
check(KilledWith()["n:Mystery"] and KilledWith()["n:Mystery"].count == 1, "an attack without an id is kept under its name")
Feed("@Me", "Myself^Mx", "@Ivy", "Ivy^Fx")
check(R:Counts("all") == 7, "all seven kills were counted, attributed or not")

Feed("@Jax", "Jax^Mx", "@Me", "Myself^Mx")
recap = { { name = "Light Attack", id = 5, killingBlow = false }, { name = "Dragonknight Standard", id = 777, killingBlow = true } }
handlers[EVENT_PLAYER_DEAD]()
check(#later == 1 and later[1].ms >= 2000, "the recap is read after the client has built it (>= 2000 ms)")
RunLater()
local diedTo = Day().diedTo
check(diedTo["777"] and diedTo["777"].count == 1 and diedTo["5"] == nil and diedTo["777"].name == "Dragonknight Standard", "the attack that dealt the killing blow is recorded, not the ones before it")
handlers[EVENT_PLAYER_DEAD](); RunLater()
check(diedTo["777"].count == 1, "a second read for the same death adds nothing")
now = now + 60000; handlers[EVENT_PLAYER_DEAD](); RunLater()
check(diedTo["777"].count == 1, "a death the feed did not count gets no attack")
Feed("@Kai", "Kai^Mx", "@Me", "Myself^Mx"); recap = {}
handlers[EVENT_PLAYER_DEAD](); RunLater()
local _, deathsToday = R:Counts(R:DayKey())
check(deathsToday == 2 and diedTo["777"].count == 1, "a death with no recap is still counted, without an attack")

local skills = R:Top("killedWith", "all", 10)
check(#skills == 3 and skills[1].name == "Wrecking Blow" and skills[1].count == 2, "the skill killed with most is first")
check(skills[2].name == "Crystal Blast" and skills[3].name == "Mystery", "ties are in name order")
check(#R:Top("killedWith", "all", 2) == 2, "a limit cuts the list")
check(R:EntryLine("killedWith", 1, skills[1]) == (expectJa and "1. Wrecking Blow ×2" or "1. Wrecking Blow x2"), "a row reads rank, name and count: " .. R:EntryLine("killedWith", 1, skills[1]))
check(R:EntryLine("killedWith", 3, { name = "", count = 4 }) == string.format(L("ABILITY_ROW"), 3, L("UNKNOWN_ATTACK"), 4), "an attack with no name is shown as unknown")
check(R:EntryLine("diedTo", 1, nil) == L("NONE_ROW"), "a missing row is a dash")
Feed("@Me", "Myself^Mx", "@Bob", "Bob^Mx")
local killedPlayers = R:Top("killedPlayers", "all", 10)
check(#killedPlayers == 7 and killedPlayers[1].name == "@Bob" and killedPlayers[1].count == 2, "every player killed is listed once, the one killed most first")
check(R:EntryLine("killedPlayers", 1, killedPlayers[1]) == (expectJa and "1. @Bob ×2" or "1. @Bob x2"), "players are shown by the name the client prefers")
local diedToPlayers = R:Top("diedToPlayers", "all", 10)
check(#diedToPlayers == 2 and diedToPlayers[1].count == 1, "the players who killed the player are listed too")
local bucket = {}
R:AddPlayer(bucket, "@Zoe", "Zoe^Fx"); R:AddPlayer(bucket, "@Zoe", "Zoe Renamed^Fx"); R:AddPlayer(bucket, "", ""); R:AddPlayer(bucket, "", "Nameless^Mx")
check(bucket["@Zoe"].count == 2 and bucket["@Zoe"].char == "Zoe Renamed^Fx", "the account name is the key; a renamed character does not make a second player")
check(bucket["c:Nameless^Mx"] and bucket["c:Nameless^Mx"].name == "Nameless", "without an account name the character stands in")
local entries = 0 for _ in pairs(bucket) do entries = entries + 1 end
check(entries == 2, "a player with no name at all is not recorded")
local dayKeys = R:DayKeys()
check(#R:Top("killedWith", dayKeys[1], 10) == 3 and #R:Top("killedWith", dayKeys[1] - 1, 10) == 0, "one day's list is that day's, an empty day has none")

print("== rank: one rank from the win rate and the number of battles")
local idx, nxt = R:RankOf(0)
check(idx == 1 and nxt == 5, "0 points is the lowest rank, 5 to the next")
idx, nxt = R:RankOf(4)
check(idx == 1 and nxt == 5, "4 is still the lowest")
idx, nxt = R:RankOf(5)
check(idx == 2 and nxt == 15, "5 is the second rank")
idx, nxt = R:RankOf(9999)
check(idx == 17 and nxt == 10000, "9999 is one short of the top")
idx, nxt = R:RankOf(10000)
check(idx == 18 and nxt == nil, "10000 is the top rank and there is no next")
local increasing = true
for i = 2, #R.RANK_THRESHOLDS do if R.RANK_THRESHOLDS[i] <= R.RANK_THRESHOLDS[i - 1] then increasing = false end end
check(increasing and R.NUM_RANKS == 18, "eighteen ranks with rising thresholds")
check(R:RankName(1) == (expectJa and "二等兵" or "Private") and R:RankName(18) == (expectJa and "元帥" or "Field Marshal"), "from private to marshal")

check(R:Battles(120, 8) == 128, "the battles are kills + deaths")
check(R:WinRate(0, 0) == nil and R:WinRate(3, 1) == 0.75 and R:WinRate(0, 4) == 0 and R:WinRate(5, 0) == 1, "the win rate is kills over battles, and there is none before the first battle")
check(R:RankPoints(10, 0) == 15 and R:RankPoints(0, 10) == 5 and R:RankPoints(5, 5) == 10, "points: a won battle is worth 1.5, a lost one 0.5")
local identity = true
for kills = 0, 60, 7 do
    for deaths = 0, 60, 5 do
        local battles = R:Battles(kills, deaths)
        if battles > 0 and math.abs(R:RankPoints(kills, deaths) - battles * (0.5 + R:WinRate(kills, deaths))) > 1e-9 then identity = false end
    end
end
check(identity, "the points are exactly battles x (0.5 + win rate)")

local function RankIndex(kills, deaths) return (R:RankOf(R:RankPoints(kills, deaths))) end
check(RankIndex(100, 0) == 6 and RankIndex(50, 50) == 6 and RankIndex(0, 100) == 4, "the same 100 battles: all won is rank 6, half won rank 6, none won only rank 4")
check(RankIndex(100, 0) > RankIndex(0, 100), "so a better win rate gives a higher rank at the same number of battles")
check(RankIndex(6, 6) < RankIndex(30, 30) and RankIndex(30, 30) < RankIndex(60, 60), "and more battles at the same win rate give a higher rank")
local monotone = true
for kills = 0, 39 do
    -- the same 40 battles with one more of them won
    if RankIndex(kills + 1, 39 - kills) < RankIndex(kills, 40 - kills) then monotone = false end
end
for deaths = 0, 40 do
    -- one more battle, lost
    if RankIndex(20, deaths + 1) < RankIndex(20, deaths) then monotone = false end
end
check(monotone, "winning one more of the same battles never lowers the rank, and no battle ever does")
-- 2 x points is 3 x kills + deaths, a whole number: the rank must agree with that exact arithmetic everywhere
local exact = true
for kills = 0, 400, 3 do
    for deaths = 0, 400, 7 do
        local twice, want = 3 * kills + deaths, 1
        for i, threshold in ipairs(R.RANK_THRESHOLDS) do if twice >= 2 * threshold then want = i end end
        if RankIndex(kills, deaths) ~= want then exact = false; print("    " .. kills .. "/" .. deaths) end
    end
end
check(exact, "the rank always agrees with exact whole-number arithmetic, so no threshold is missed by rounding")

-- how far to the next rank, at the win rate the player has now
check(R:BattlesToNextRank(10, 0) == 10, "10 won battles are 15 points; 10 more at the same rate make 30, exactly the next rank")
check(RankIndex(20, 0) == 4 and RankIndex(19, 0) == 3, "...and one fewer is not enough")
check(R:BattlesToNextRank(0, 0) == 5, "before the first battle it assumes an even win rate: 5 battles")
check(R:BattlesToNextRank(4, 0) == 6, "4 won battles, 6 more to the next rank")
check(R:BattlesToNextRank(12000, 0) == nil, "nothing is left to reach at the top")

A.sv.totals.kills, A.sv.totals.deaths = 120, 8
check(R:RankLine() == string.format(L("RANK_ROW"), L("RANK_7"), 39), "the rank line names the rank and the battles to the next: " .. R:RankLine())
check(R:StatsLine() == string.format(L("RANK_STATS_ROW"), 128, string.format("%.1f%%", 93.75), 120, 8), "the stats line shows the battles, the win rate and what they are made of: " .. R:StatsLine())
A.sv.totals.kills, A.sv.totals.deaths = 0, 0
check(R:RankLine() == string.format(L("RANK_ROW"), L("RANK_1"), 5) and R:StatsLine() == string.format(L("RANK_STATS_ROW"), 0, L("NONE_ROW"), 0, 0), "with no battles: the lowest rank, a dash for the win rate")
A.sv.totals.kills = 12000
check(R:RankLine() == string.format(L("RANK_ROW_MAX"), L("RANK_18")), "the top rank says so instead of a distance: " .. R:RankLine())
A.sv.totals.kills, A.sv.totals.deaths = 120, 8
local before = #chat
SLASH_COMMANDS["/pbkl"]("stats")
check(#chat == before + 3 and chat[#chat] == "[PBsKillLog] " .. R:StatsLine() and chat[#chat - 1] == "[PBsKillLog] " .. R:RankLine(), "/pbkl stats prints today, the rank and what it is made of")
check(R:TodayLine() == string.format(L("TODAY_ROW"), R:DateText(R:DayKey()), 8, 2, "4.00"), "today's line has the K/D: " .. R:TodayLine())

print("== records in the settings panel")
R:ResetAll()
SetClock(2026, 10, 19, 12, 0, 9)
now = now + 20000; Blow("Wrecking Blow", 111, "Bob^Mx"); now = now + 300
Feed("@Me", "Myself^Mx", "@Bob", "Bob^Mx", false, false)
Feed("@Carl", "Carl^Mx", "@Me", "Myself^Mx"); recap = { { name = "Dragonknight Standard", id = 777, killingBlow = true } }
handlers[EVENT_PLAYER_DEAD](); RunLater()
SetClock(2026, 10, 20, 12, 0, 9)
now = now + 20000; Blow("Crystal Blast", 222, "Dan^Mx"); now = now + 300
Feed("@Me", "Myself^Mx", "@Dan", "Dan^Mx", false, false)
GoToScene("hud"); panel.selected = false
OpenPanel()
local function SectionRows(title)
    local rows, inside = {}, false
    for _, o in ipairs(panel.settings) do
        if o.type == LIB.ST_SECTION then inside = (Text(o.label) == title) elseif inside then rows[#rows + 1] = o end
    end
    return rows
end
local order = {}
for _, o in ipairs(panel.settings) do if o.type == LIB.ST_SECTION then order[#order + 1] = Text(o.label) end end
check(table.concat(order, "|") == table.concat({ L("SECTION_RANK"), L("SECTION_RANKING"), L("SECTION_DAYS"), L("SECTION_ABILITIES"), L("SECTION_WINDOW"), L("SECTION_TEXT"), L("SECTION_LAYER"), L("SECTION_SOUND"), L("SECTION_LOG") }, "|"), "sections: rank, ranking window, daily records, attacks, then the window settings")
local rankRows = SectionRows(L("SECTION_RANK"))
check(#rankRows == 2, "the rank section: the rank and what it is made of")
check(Text(rankRows[1].label) == R:RankLine() and Text(rankRows[2].label) == R:StatsLine(), "the rows show the one rank and the battles and win rate behind it")
check(rankRows[1].canSelect and rankRows[2].canSelect and rankRows[1].tooltip == L("RANK_ROW_TIP") and rankRows[2].tooltip == L("RANK_ROW_TIP"), "the rows can be selected and explain how the rank is worked out")
local dayRows = SectionRows(L("SECTION_DAYS"))
local dk = R:DayKeys()
check(#dayRows == 3 and Text(dayRows[1].label) == R:TodayLine(), "daily records: today's line first")
check(Text(dayRows[2].label) == R:DayLine(dk[1]) and Text(dayRows[3].label) == R:DayLine(dk[2]), "...then one row per day, newest first")
check(Text(dayRows[2].label):find("2026/10/20", 1, true) ~= nil and Text(dayRows[3].label):find("2026/10/19", 1, true) ~= nil, "each row names its date: " .. Text(dayRows[2].label))
local selectable = true
for _, o in ipairs(dayRows) do if not o.canSelect then selectable = false end end
check(selectable, "every record row can be selected, so the d-pad can scroll a long list")
local abilityRows = SectionRows(L("SECTION_ABILITIES"))
local scopeBox = abilityRows[1]
check(scopeBox.type == LIB.ST_DROPDOWN and #scopeBox.items == 3 and scopeBox.items[1].data == "all", "attacks: a scope dropdown with 'all' and each day")
check(scopeBox.getFunction() == scopeBox.items[1].name and scopeBox.default == scopeBox.items[1].name, "it starts on all recorded days")
check(Text(abilityRows[2].label) == L("KILLED_WITH") and Text(abilityRows[8].label) == L("DIED_TO") and #abilityRows == 13, "two headings with five rows each, after the dropdown")
check(Text(abilityRows[3].label) == R:EntryLine("killedWith", 1, R:Top("killedWith", "all", 5)[1]), "the kill skills are listed")
check(Text(abilityRows[7].label) == L("NONE_ROW"), "missing rows are dashes")
check(Text(abilityRows[9].label) == R:EntryLine("diedTo", 1, R:Top("diedTo", "all", 5)[1]) and Text(abilityRows[9].label):find("Dragonknight Standard", 1, true) ~= nil, "the skills that killed the player are listed")
local updates = panel.updates
scopeBox.setFunction(nil, scopeBox.items[3].name, scopeBox.items[3])
check(panel.updates == updates + 1, "choosing a day redraws the rows")
check(scopeBox.getFunction() == scopeBox.items[3].name, "the dropdown shows the chosen day")
check(Text(abilityRows[3].label):find("Wrecking Blow", 1, true) ~= nil and Text(abilityRows[9].label):find("Dragonknight Standard", 1, true) ~= nil, "the lists now count only the older day (the 19th)")
scopeBox.setFunction(nil, scopeBox.items[2].name, scopeBox.items[2])
check(Text(abilityRows[3].label):find("Crystal Blast", 1, true) ~= nil and Text(abilityRows[9].label) == L("NONE_ROW"), "and the 20th has no deaths")
local count = #panel.settings
A.RebuildRecordRows()
check(#panel.settings == count, "rebuilding the rows does not add or lose any")
ClosePanel(); OpenPanel()
check(#panel.settings == count and scopeBox ~= SectionRows(L("SECTION_ABILITIES"))[1], "opening the panel again builds fresh rows, back on 'all'")
check(SectionRows(L("SECTION_ABILITIES"))[1].getFunction() == SectionRows(L("SECTION_ABILITIES"))[1].items[1].name, "...with the scope reset")

for i = 1, 35 do R:Day(5000 + i, true).kills = 1 end
A.RebuildRecordRows()
dayRows = SectionRows(L("SECTION_DAYS"))
check(#dayRows == 1 + 30 + 1 and Text(dayRows[#dayRows].label) == string.format(L("MORE_DAYS"), 7), "more than 30 days: 30 rows and a count of the rest (7)")
check(#SectionRows(L("SECTION_ABILITIES"))[1].items == 31, "the dropdown offers 'all' and the 30 newest days")
for i = 1, 35 do A.sv.records[tostring(5000 + i)] = nil end
A.RebuildRecordRows()

print("== clearing")
local clearDays, resetAll = opt("CLEAR_DAYS"), opt("RESET_ALL")
check(clearDays.type == LIB.ST_BUTTON and resetAll.type == LIB.ST_BUTTON, "two clear buttons in the log section")
local totalsBefore = { R:Totals() }
local rankBefore = R:RankLine()
clearDays.clickHandler()
check(#shownDialogs == 1 and shownDialogs[1].name == "PBsKillLog_ClearDays", "clearing asks first")
local dialog = ESO_Dialogs["PBsKillLog_ClearDays"]
check(dialog.title.text == L("DIALOG_CLEAR_DAYS_TITLE") and dialog.mainText.text == L("DIALOG_CLEAR_DAYS_TEXT") and dialog.buttons[1].text == SI_DIALOG_ACCEPT and dialog.buttons[2].text == SI_DIALOG_CANCEL and dialog.gamepadInfo.dialogType == GAMEPAD_DIALOGS.BASIC, "the dialog is the same kind PB's MailerExtension uses")
check(next(A.sv.records) ~= nil, "nothing is deleted until the answer is yes")
AnswerDialog(2)
check(next(A.sv.records) ~= nil, "cancel keeps the records")
clearDays.clickHandler(); AnswerDialog(1)
check(next(A.sv.records) == nil, "yes clears the daily records")
check(select(1, R:Totals()) == totalsBefore[1] and select(2, R:Totals()) == totalsBefore[2] and R:RankLine() == rankBefore, "...but not the totals or the rank")
dayRows = SectionRows(L("SECTION_DAYS"))
check(#dayRows == 2 and Text(dayRows[2].label) == L("NO_RECORDS"), "the day rows are rebuilt: nothing recorded yet")
check(R.pendingKill == nil and R.pendingDeath == nil and R.lastBlow == nil, "pending pairings are dropped with them")
clearDays.clickHandler(); resetAll.clickHandler()
check(#shownDialogs == 2 and shownDialogs[2].name == "PBsKillLog_ResetAll", "resetting everything asks with its own dialog")
AnswerDialog(1); table.remove(shownDialogs)
local tk2, td2 = R:Totals()
check(tk2 == 0 and td2 == 0, "yes also zeroes the totals, and so the rank")
check(R:RankLine():find(L("RANK_1"), 1, true) ~= nil, "back to the lowest rank")
local show = ZO_Dialogs_ShowPlatformDialog
ZO_Dialogs_ShowPlatformDialog = nil
A.sv.totals.kills = 9; R:Day(5001, true).kills = 9
local chatBefore = #chat
clearDays.clickHandler()
check(chat[#chat] == "[PBsKillLog] " .. L("ERR_NO_DIALOG") and #chat == chatBefore + 1 and next(A.sv.records) ~= nil, "no way to ask: it says so and deletes nothing")
ZO_Dialogs_ShowPlatformDialog = show
R:ResetAll()
GoToScene("hud")
panel.selected = false
CheckLanguage(panel, expectJa and "the rebuilt record rows, rank rows and dropdown are Japanese" or "the rebuilt record rows are English")

print("== ranking window")
check(created["PBsKillLogRanking"] == nil, "no ranking window until it is asked for")
R:ResetAll()
SetClock(2026, 10, 19, 12, 0, 9)
SLASH_COMMANDS["/pbkl"]("ranking")
local RK = created["PBsKillLogRanking"]
check(RK ~= nil and not RK.hidden and chat[#chat] == "[PBsKillLog] " .. L("CMD_RANKING_ON"), "/pbkl ranking builds the window and shows it on the HUD")
local attached = 0
for _, scene in ipairs({ HUD_SCENE, HUD_UI_SCENE }) do for fr in pairs(scene.fragments) do if fr.control == RK then attached = attached + 1 end end end
check(attached == 2, "its fragment is on HUD_SCENE and HUD_UI_SCENE")
check(RK.last.SetMouseEnabled[1] == false and RK.last.SetDrawLayer[1] == DL_OVERLAY and RK.last.SetDrawTier[1] == DT_HIGH, "it takes no input and is drawn above the panel")
local layout = A.ranking.layout
check(layout ~= nil and RK.last.SetDimensions[1] == layout.width and RK.last.SetDimensions[2] == layout.height, "the window has the size its layout worked out: " .. layout.width .. " x " .. layout.height)
check(layout.height <= 1080 - 40, "...and that fits the screen with room to spare: " .. layout.height .. " of 1080")
check(layout.rowFont == (expectJa and "ZoFontGamepad34" or "ZoFontGamepad27"), "the rows use the biggest font that fits: " .. layout.rowFont)
local function Height(font) local c = Control("measure"); c:SetFont(font); return c:GetFontHeight() end
check(Height(layout.rowFont) > Height("ZoFontGamepad20"), "the rows are bigger than the old size (" .. Height(layout.rowFont) .. " against " .. Height("ZoFontGamepad20") .. " high)")
local lastRow = created["PBsKillLogRankingList4Row10"]
local rightHeading = created["PBsKillLogRankingHeading4"]
check(lastRow.last.SetAnchor[5] + layout.rowHeight <= layout.height, "the last row ends inside the frame: " .. (lastRow.last.SetAnchor[5] + layout.rowHeight) .. " of " .. layout.height)
check(rightHeading.last.SetAnchor[4] + 560 <= layout.width, "the right-hand column ends inside the frame")
local roomy = true
for list = 1, 4 do
    for row = 1, 10 do
        local l = created["PBsKillLogRankingList" .. list .. "Row" .. row]
        if l:GetFontHeight() > l.last.SetDimensions[2] or l.font ~= layout.rowFont then roomy = false end
    end
    local h = created["PBsKillLogRankingHeading" .. list]
    if h:GetFontHeight() > h.last.SetDimensions[2] or h.font ~= layout.headingFont then roomy = false end
end
check(roomy and created["PBsKillLogRankingTitle"]:GetFontHeight() <= created["PBsKillLogRankingTitle"].last.SetDimensions[2], "every row, heading and the title is tall enough for its text")
local rows1 = created["PBsKillLogRankingList1Row1"].last.SetAnchor[5]
local rows2 = created["PBsKillLogRankingList1Row2"].last.SetAnchor[5]
check(rows2 - rows1 == layout.rowHeight and created["PBsKillLogRankingList3Row1"].last.SetAnchor[5] >= created["PBsKillLogRankingList1Row10"].last.SetAnchor[5] + layout.rowHeight, "rows are one row height apart, and the lower lists start below the upper ones (no overlap)")
-- the size follows the screen
local roomiest = A.ranking:ChooseLayout(5000)
local tight = A.ranking:ChooseLayout(800)
local tiny = A.ranking:ChooseLayout(300)
check(roomiest.rowFont == "ZoFontGamepad34", "with all the room in the world the biggest font is chosen")
check(tight.height <= 800 and Height(tight.rowFont) < Height(roomiest.rowFont), "on a screen 800 high a smaller font is chosen, and it fits: " .. tight.rowFont .. " at " .. tight.height)
check(tiny.rowFont == "ZoFontGamepad20" and tiny.height > 300, "when nothing fits the smallest is used rather than nothing")
local nonIncreasing, previous = true, nil
for maxHeight = 1200, 500, -50 do
    local chosen = A.ranking:ChooseLayout(maxHeight)
    if previous and Height(chosen.rowFont) > previous then nonIncreasing = false end
    previous = Height(chosen.rowFont)
end
check(nonIncreasing, "the less room there is, the smaller the font (never bigger)")
check(RK.last.SetAnchor[1] == "RIGHT" and RK.last.SetAnchor[4] == -40, "on the right-hand side, away from the settings list")
check(created["PBsKillLogRankingTitle"].text == string.format(L("RANKING_TITLE"), R:ScopeText("all")), "title names the period: " .. created["PBsKillLogRankingTitle"].text)
local wantedHeadings = { "RANKING_DIED_TO_SKILL", "RANKING_KILLED_WITH_SKILL", "RANKING_DIED_TO_PLAYER", "RANKING_KILLED_PLAYER" }
local headingsOk = true
for i, key in ipairs(wantedHeadings) do if created["PBsKillLogRankingHeading" .. i].text ~= L(key) then headingsOk = false end end
check(headingsOk, "four lists in the order asked for: skills that killed you, skills you killed with, players who killed you, players you killed")
check((expectJa and created["PBsKillLogRankingHeading1"].text == "殺されたスキル" and created["PBsKillLogRankingHeading2"].text == "殺したスキル" and created["PBsKillLogRankingHeading3"].text == "殺されたプレイヤー" and created["PBsKillLogRankingHeading4"].text == "殺したプレイヤー") or not expectJa, "the Japanese headings are the user's words")
local function RowText(list, row) local l = created["PBsKillLogRankingList" .. list .. "Row" .. row]; return l.text, l.hidden end
local emptyOk = true
for list = 1, 4 do local t1, h1 = RowText(list, 1); local _, h2 = RowText(list, 2); if t1 ~= L("NONE_ROW") or h1 or not h2 then emptyOk = false end end
check(emptyOk, "empty lists show a dash and nothing else")
-- data arrives while the window is up
now = now + 20000; Blow("Wrecking Blow", 111, "Bob^Mx"); now = now + 300
Feed("@Me", "Myself^Mx", "@Bob", "Bob^Mx", false, false)
Feed("@Carl", "Carl^Mx", "@Me", "Myself^Mx"); recap = { { name = "Dragonknight Standard", id = 777, killingBlow = true } }
handlers[EVENT_PLAYER_DEAD](); RunLater()
check(RowText(2, 1) == R:EntryLine("killedWith", 1, R:Top("killedWith", "all", 10)[1]) and RowText(2, 1):find("Wrecking Blow", 1, true) ~= nil, "skills you killed with: filled as it happens")
check(RowText(1, 1):find("Dragonknight Standard", 1, true) ~= nil, "skills that killed you: filled when the recap is read")
check(RowText(4, 1):find("@Bob", 1, true) ~= nil and RowText(3, 1):find("@Carl", 1, true) ~= nil, "players you killed and players who killed you")
local _, hiddenRow2 = RowText(2, 2)
check(hiddenRow2 == true, "rows beyond the list are hidden")
for i = 1, 12 do Feed("@Me", "Myself^Mx", "@Foe" .. i, "Foe" .. i .. "^Mx") end
local last = created["PBsKillLogRankingList4Row10"]
check(not last.hidden and created["PBsKillLogRankingList4Row11"] == nil, "ten rows at most, however many players there are")
check(RowText(4, 1):find("@Bob", 1, true) ~= nil, "the player killed most stays on top")

GoToScene("inventory")
check(RK.hidden, "hidden in a menu")
Feed("@Me", "Myself^Mx", "@Late", "Late^Mx")
GoToScene("hud")
check(not RK.hidden, "back on the HUD it is shown again")
GoToScene("hudui")
check(not RK.hidden, "and while the cursor is free")
GoToScene("hud")

print("== ranking window and the settings panel")
OpenPanel()
check(not RK.hidden, "wanted: it is drawn over the settings panel")
ClosePanel()
check(not RK.hidden, "closing the panel leaves it on the HUD")
GoToScene("inventory")
check(RK.hidden, "and it is not left over in another menu")
GoToScene("hud")
local btn = opt("RANKING_BUTTON")
btn.clickHandler()
check(RK.hidden and chat[#chat] ~= nil, "the panel's button put it away")
OpenPanel()
check(RK.hidden, "not wanted: opening the panel does not show it")
btn.clickHandler()
check(not RK.hidden, "the button shows it over the open panel at once")
btn.clickHandler()
check(RK.hidden, "and hides it again")
ClosePanel()
SLASH_COMMANDS["/pbkl"]("ranking")
check(not RK.hidden, "/pbkl ranking brings it back")
OpenPanel()
GoToScene("elsewhere"); now = now + 400
RK.handlers.OnUpdate()
check(RK.hidden, "drawn over the panel, it goes away by itself when that scene is left")
GoToScene("hud")
SLASH_COMMANDS["/pbkl"]("ranking")
check(RK.hidden and chat[#chat] == "[PBsKillLog] " .. L("CMD_RANKING_OFF"), "/pbkl ranking again puts it away")
check(next(HUD_SCENE.fragments) ~= nil, "(the log window's own fragment is untouched)")
ClosePanel()


-- the periods: one day, one month, all time
do
    print("== periods")
    R:ResetAll()
    SetClock(2026, 10, 19, 12, 0, 9)
    local dSep30, dOct1, dOct19, dAug15 = DaysFromCivil(2026, 9, 30), DaysFromCivil(2026, 10, 1), DaysFromCivil(2026, 10, 19), DaysFromCivil(2026, 8, 15)
    local function Fill(day, kills, deaths, skill, skillCount, players)
        local rec = R:Day(day, true)
        rec.kills, rec.deaths = kills, deaths
        for _ = 1, skillCount do R:AddAbility(rec.killedWith, skill.id, skill.name) end
        for name, count in pairs(players) do for _ = 1, count do R:AddPlayer(rec.killedPlayers, name, name:sub(2)) end end
    end
    local WRECK, CRYSTAL = { id = 1, name = "Wrecking Blow" }, { id = 2, name = "Crystal Blast" }
    Fill(dSep30, 2, 1, WRECK, 2, { ["@Bob"] = 2 })
    Fill(dOct1, 3, 0, CRYSTAL, 3, { ["@Bob"] = 1, ["@Cat"] = 2 })
    Fill(dOct19, 1, 0, WRECK, 1, {})
    Fill(dAug15, 5, 0, WRECK, 5, {})
    check(R:MonthKey(dSep30) == 202609 and R:MonthKey(dOct1) == 202610, "the month turns over between 30 September and 1 October")
    check(R:MonthText(202610) == (expectJa and "2026年10月" or "2026/10"), "a month is written for the client language: " .. R:MonthText(202610))
    local function K(scope) local k, d = R:Counts(scope); return k .. "/" .. d end
    check(K("all") == "11/1", "all time adds every day: " .. K("all"))
    check(K("thismonth") == "4/0", "this month is October only: " .. K("thismonth"))
    check(K("m202609") == "2/1" and K("m202608") == "5/0" and K("m202501") == "0/0", "a month by key, and a month with nothing in it")
    check(K("today") == "1/0" and K(dSep30) == "2/1" and K(tostring(dSep30)) == "2/1" and K(dOct1 + 100) == "0/0", "a day by number or by text, and a day with nothing in it")
    local function Names(kind, scope) local out = {}; for _, e in ipairs(R:Top(kind, scope, 10)) do out[#out + 1] = e.name .. "x" .. e.count end return table.concat(out, ",") end
    check(Names("killedWith", "all") == "Wrecking Blowx8,Crystal Blastx3", "skills over all time: " .. Names("killedWith", "all"))
    check(Names("killedWith", "thismonth") == "Crystal Blastx3,Wrecking Blowx1", "skills this month: " .. Names("killedWith", "thismonth"))
    check(Names("killedWith", "m202609") == "Wrecking Blowx2" and Names("killedWith", dAug15) == "Wrecking Blowx5", "skills of another month and of one day")
    check(Names("killedPlayers", "all") == "@Bobx3,@Catx2" and Names("killedPlayers", "m202609") == "@Bobx2" and Names("killedPlayers", "today") == "", "players over each period")
    check(R:ScopeText("all") == L("SCOPE_ALL_SHORT") and R:ScopeText("m202609") == string.format(L("SCOPE_MONTH"), R:MonthText(202609)), "the period is named: " .. R:ScopeText("m202609"))
    check(R:ScopeText("today") == string.format(L("SCOPE_TODAY"), R:DateText(dOct19)) and R:ScopeText("thismonth") == string.format(L("SCOPE_THIS_MONTH"), R:MonthText(202610)), "today and this month say so: " .. R:ScopeText("today"))
    check(R:ScopeText(dSep30) == string.format(L("SCOPE_DAY"), R:DateText(dSep30)), "a day is named by its date")
    local scopes = R:RankingScopes()
    local expected = { "all", "today", "thismonth", "m202609", "m202608", dOct1, dSep30, dAug15 }
    local same = #scopes == #expected
    for i = 1, #expected do if scopes[i] ~= expected[i] then same = false end end
    check(same, "the menu lists all time, today, this month, the other months, then the other days (" .. #scopes .. " of " .. #expected .. ")")
    SetClock(2026, 10, 20, 12, 0, 9)
    check(K("today") == "0/0" and K("thismonth") == "4/0", "'today' follows the clock; the month stays")
    check(R:ScopeText("today") == string.format(L("SCOPE_TODAY"), R:DateText(dOct19 + 1)), "...and its name does too")
    R:ResetAll()
    check(#R:RankingScopes() == 3, "with nothing recorded only the three standing periods are offered")
    SetClock(2026, 10, 19, 12, 0, 9)

    print("== ranking window: periods")
    Fill(dSep30, 2, 1, WRECK, 2, { ["@Bob"] = 2 })
    Fill(dOct1, 3, 0, CRYSTAL, 3, { ["@Bob"] = 1, ["@Cat"] = 2 })
    Fill(dOct19, 1, 0, WRECK, 1, {})
    local RK2 = created["PBsKillLogRanking"]
    local ranking = A.ranking
    SLASH_COMMANDS["/pbkl"]("ranking")
    if RK2.hidden then SLASH_COMMANDS["/pbkl"]("ranking") end
    GoToScene("hud")
    check(ranking.scope == "all" and not RK2.hidden, "the window starts on all time")
    local function Rows(list) local out = {}; for row = 1, 10 do local l = created["PBsKillLogRankingList" .. list .. "Row" .. row]; if not l.hidden then out[#out + 1] = l.text end end return table.concat(out, " | ") end
    ranking:SetScope("all")
    check(Rows(2):find("Wrecking Blow", 1, true) ~= nil and Rows(2):find("Crystal Blast", 1, true) ~= nil and created["PBsKillLogRankingTitle"].text == string.format(L("RANKING_TITLE"), R:ScopeText("all")), "all time: both skills, titled all time")
    ranking:SetScope("thismonth")
    check(created["PBsKillLogRankingTitle"].text == string.format(L("RANKING_TITLE"), R:ScopeText("thismonth")), "monthly: the title names the month: " .. created["PBsKillLogRankingTitle"].text)
    check(Rows(2):find("1. Crystal Blast", 1, true) == 1 and Rows(2):find("2. Wrecking Blow", 1, true) ~= nil, "monthly: October's skills, Crystal Blast first")
    check(Rows(4):find("@Cat", 1, true) ~= nil and Rows(4):find("@Bob", 1, true) ~= nil, "monthly: October's players")
    ranking:SetScope("m202609")
    check(Rows(2):find("Wrecking Blow", 1, true) ~= nil and Rows(2):find("Crystal Blast", 1, true) == nil and Rows(4):find("@Cat", 1, true) == nil, "another month shows only that month")
    ranking:SetScope("today")
    check(Rows(2):find("Wrecking Blow", 1, true) ~= nil and Rows(2):find("Crystal Blast", 1, true) == nil and Rows(4) == L("NONE_ROW"), "daily: only today's skills, and a dash where nobody was killed today")
    check(created["PBsKillLogRankingTitle"].text == string.format(L("RANKING_TITLE"), R:ScopeText("today")), "daily: the title names the day: " .. created["PBsKillLogRankingTitle"].text)
    ranking:SetScope(dSep30)
    check(Rows(4):find("@Bob", 1, true) ~= nil and Rows(2):find("Crystal Blast", 1, true) == nil, "a past day by its number")
    ranking:SetScope(nil)
    check(ranking.scope == "all", "no period means all time")

    -- the clock moves on while the window is up
    ranking:SetScope("today")
    SetClock(2026, 10, 20, 0, 5, 9)
    Feed("@Me", "Myself^Mx", "@Newday", "Newday^Mx")
    check(Rows(4) == "1. @Newday " .. (expectJa and "×1" or "x1"), "after midnight the daily ranking is the new day's: " .. Rows(4))
    SetClock(2026, 10, 19, 12, 0, 9)
    ranking:SetScope("all")

    -- the menu (its items are listed when the panel opens, so open it again now that there are records)
    A.RebuildRecordRows()
    local periodBox = opt("RANKING_PERIOD")
    local tokens = R:RankingScopes()
    check(periodBox and periodBox.type == LIB.ST_DROPDOWN and #periodBox.items == #tokens, "the panel has a period dropdown with one item per period: " .. #periodBox.items)
    check(periodBox.items[1].data == "all" and periodBox.items[2].data == "today" and periodBox.items[3].data == "thismonth", "all time, today, this month come first")
    local namesDistinct, seen = true, {}
    for _, item in ipairs(periodBox.items) do if seen[item.name] then namesDistinct = false end seen[item.name] = true end
    check(namesDistinct, "every item has its own name")
    check(periodBox.ignoreDefault == true, "'reset to defaults' leaves it out, so it cannot pop the window up")
    check(periodBox.getFunction() == periodBox.items[1].name, "it shows the period the window is on")
    SLASH_COMMANDS["/pbkl"]("ranking")
    check(ranking.wanted == false and RK2.hidden, "(window off)")
    periodBox.setFunction(nil, periodBox.items[3].name, periodBox.items[3])
    check(ranking.scope == "thismonth" and ranking.wanted == true and not RK2.hidden, "choosing a period sets it and shows the window")
    check(periodBox.getFunction() == periodBox.items[3].name, "the dropdown shows the chosen period")
    local rowsBefore = Rows(2)
    periodBox.setFunction(nil, periodBox.items[1].name, periodBox.items[1])
    check(ranking.scope == "all" and ranking.wanted == true, "choosing another period keeps the window up")
    A.RebuildRecordRows()
    local rebuilt = opt("RANKING_PERIOD")
    check(rebuilt ~= periodBox and rebuilt.getFunction() == rebuilt.items[1].name, "the items are built again whenever the panel opens")

    -- /pbkl ranking day|month|all
    SLASH_COMMANDS["/pbkl"]("ranking")
    SLASH_COMMANDS["/pbkl"]("ranking day")
    check(ranking.scope == "today" and ranking.wanted and not RK2.hidden and chat[#chat] == "[PBsKillLog] " .. string.format(L("CMD_RANKING_SCOPE"), R:ScopeText("today")), "/pbkl ranking day: today's ranking, window shown: " .. chat[#chat])
    SLASH_COMMANDS["/pbkl"]("ranking month")
    check(ranking.scope == "thismonth" and ranking.wanted, "/pbkl ranking month: this month's")
    SLASH_COMMANDS["/pbkl"]("ranking  ALL")
    check(ranking.scope == "all" and ranking.wanted, "/pbkl ranking all: all time (case and spaces do not matter)")
    SLASH_COMMANDS["/pbkl"]("ranking")
    check(ranking.wanted == false and RK2.hidden and chat[#chat] == "[PBsKillLog] " .. L("CMD_RANKING_OFF"), "/pbkl ranking alone still flips it off")
    check(L("CMD_HELP"):find("ranking [day|month|all]", 1, true) ~= nil, "the help line shows the periods")
    R:ResetAll()
end

print("== console crash guards")
local function slurp(f) local h = assert(io.open(ADDON_DIR .. f, "rb")); local t = h:read("*a"); h:close(); return t end
local function stripLua(t) return (t:gsub("%-%-[^\n]*", "")) end
local code = {
    ["PBsKillLog.lua"] = stripLua(slurp("PBsKillLog.lua")), ["Preview.lua"] = stripLua(slurp("Preview.lua")),
    ["Records.lua"] = stripLua(slurp("Records.lua")), ["Ranking.lua"] = stripLua(slurp("Ranking.lua")),
    ["Settings.lua"] = stripLua(slurp("Settings.lua")), ["Localization.lua"] = stripLua(slurp("Localization.lua")),
    ["PBsKillLog.xml"] = (slurp("PBsKillLog.xml"):gsub("<!%-%-.-%-%->", "")),
}
local forbidden = { "CHAT_FONT", "ANTIQUE_FONT", "HANDWRITTEN_FONT", "STONE_TABLET_FONT", "ZoFontChat", "ZO_DefaultBackdrop", "outline", "LibAddonMenu", "LAM%-" }
local clean = true
for file, text in pairs(code) do
    for _, token in ipairs(forbidden) do
        if text:find(token) then clean = false; print("    " .. file .. " contains " .. token) end
    end
end
check(clean, "no forbidden font / keyboard-only template / LibAddonMenu reference outside comments")
for font in code["PBsKillLog.xml"]:gmatch('font="([^"]*)"') do check(font:find("^ZoFontGamepad") ~= nil, "XML font is a gamepad font: " .. font) end
-- every named font the add-on draws with must be one the console UI already has loaded
local namedFonts, namedFontsOk = 0, true
for file, text in pairs(code) do
    for font in text:gmatch('"(ZoFont[%w_]*)"') do
        namedFonts = namedFonts + 1
        if not font:find("^ZoFontGamepad") then namedFontsOk = false; print("    " .. file .. " uses " .. font) end
    end
end
check(namedFontsOk and namedFonts >= 5, "every named font in the code is a ZoFontGamepad* font (" .. namedFonts .. " found)")
for _, name in ipairs({ "CAPTION_FONT" }) do
    local f = code["Preview.lua"]:match(name .. ' = "([^"]*)"')
    check(f ~= nil and f:find("^ZoFontGamepad") ~= nil, "preview caption font is a gamepad font: " .. tostring(f))
end
local seen = {}
for size = A.MIN_FONT_SIZE, A.MAX_FONT_SIZE do
    A.sv.fontSize = size; A.ApplyFont()
    local face, sz, style = bufferFont:match("^(.-)|(%d+)|(.-)$")
    if face ~= "$(GAMEPAD_MEDIUM_FONT)" or tonumber(sz) ~= size or (style ~= "soft-shadow-thin" and style ~= "soft-shadow-thick") then check(false, "font at " .. size .. ": " .. bufferFont) end
    seen[face] = true
end
check(next(seen) == "$(GAMEPAD_MEDIUM_FONT)" and next(seen, "$(GAMEPAD_MEDIUM_FONT)") == nil, "every size uses the single already-loaded face")

print(failures == 0 and "\nALL PASSED" or ("\n" .. failures .. " FAILED"))
os.exit(failures == 0 and 0 or 1)
