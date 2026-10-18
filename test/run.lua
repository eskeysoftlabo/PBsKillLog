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
        if k == "GetFontHeight" then return function() return 24 end end
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

TOPLEFT, TOPRIGHT, BOTTOMLEFT, BOTTOMRIGHT = "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT"
CT_TEXTURE, CT_LABEL, TEXT_WRAP_MODE_ELLIPSIS = "CT_TEXTURE", "CT_LABEL", "ELLIPSIS"
DT_LOW, DT_MEDIUM, DT_HIGH, DL_OVERLAY = 0, 1, 2, 9
ALLIANCE_ALDMERI_DOMINION, ALLIANCE_DAGGERFALL_COVENANT, ALLIANCE_EBONHEART_PACT = 1, 2, 3
SCENE_SHOWN, SCENE_HIDING = "shown", "hiding"
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
-- where the player is: "cyrodiil", "imperialcity", "icCampaign" (Cyrodiil's world, Imperial City campaign),
-- "battleground" or "elsewhere"
local zone = "cyrodiil"
-- The documentation does not say what IsInCyrodiil is in the Imperial City or a Battleground, so the stub
-- takes the worst reading -- true in all of them -- and the add-on's own checks have to do the excluding.
function IsInCyrodiil() return zone ~= "elsewhere" end
function IsInImperialCity() return zone == "imperialcity" end
function IsActiveWorldBattleground() return zone == "battleground" end
function GetCurrentCampaignId() return (zone == "cyrodiil" or zone == "icCampaign") and (zone == "icCampaign" and 77 or 3) or 0 end
function IsImperialCityCampaign(id) return id == 77 end
function GetDisplayName() return "@Me" end
function GetRawUnitName(tag) return "Myself^Mx" end
SOUNDS = { TRIBUTE_AGENT_KNOCKED_OUT = "Tribute_AgentKnockedOut" }
local sounds = {}
function PlaySound(name) sounds[#sounds + 1] = name end

local now = 1000
function GetFrameTimeMilliseconds() return now end

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
EVENT_MANAGER = {
    RegisterForEvent = function(_, ns, ev, fn) handlers[ev] = fn end,
    UnregisterForEvent = function(_, ns, ev) handlers[ev] = nil end,
}
SLASH_COMMANDS = {}
local chat = {}
CHAT_ROUTER = { AddSystemMessage = function(_, t) chat[#chat + 1] = t end }
ZO_SavedVars = { NewAccountWide = function(_, name, ver, ns, defaults)
    local sv = {}
    for k, v in pairs(defaults) do sv[k] = v end
    return sv
end }
local fragmentShowing = false
ZO_SimpleSceneFragment = { New = function(_, control) return { IsShowing = function() return fragmentShowing end } end }
local sceneFragments = {}
HUD_SCENE = { AddFragment = function(_, f) sceneFragments[#sceneFragments + 1] = f end }
HUD_UI_SCENE = { AddFragment = function(_, f) sceneFragments[#sceneFragments + 1] = f end }

local callbacks = {}
CALLBACK_MANAGER = {
    RegisterCallback = function(_, name, fn) callbacks[name] = callbacks[name] or {}; table.insert(callbacks[name], fn) end,
    FireCallbacks = function(_, name, ...) for _, fn in ipairs(callbacks[name] or {}) do fn(...) end end,
}

-- scenes: the library's panel scene (console), and which scene is current
local currentScene = "hud"
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
    function panel:AddSetting(params) self.settings[#self.settings + 1] = params end
    function panel:UpdateControls() self.updates = self.updates + 1 end
    table.insert(self.addons, panel)
    return panel
end

---------------------------------------------------------------- load
for _, f in ipairs({ "Localization.lua", "PBsKillLog.lua", "Preview.lua", "Settings.lua" }) do
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
check(#sceneFragments == 2, "fragment added to HUD and HUD_UI scenes")
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
local bad = 0
for _, o in ipairs(panel.settings) do
    for _, field in ipairs({ "label", "tooltip", "buttonText" }) do
        local v = o[field]
        if v ~= nil then
            if type(v) ~= "string" or v:match("^[A-Z_]+$") then bad = bad + 1; print("    raw key shown: " .. tostring(v)) end
            if expectJa and not hasNonAscii(v) then bad = bad + 1; print("    not Japanese: " .. v) end
            if not expectJa and hasNonAscii(v) then bad = bad + 1; print("    not English: " .. v) end
        end
    end
end
check(bad == 0, expectJa and "every label, tooltip and button in the panel is Japanese, none is a raw key" or "every label in the panel is English, none is a raw key")
for _, item in ipairs((function() for _, o in ipairs(panel.settings) do if o.type == LIB.ST_DROPDOWN then return o.items end end end)()) do
    check(expectJa == hasNonAscii(item.name), "dropdown item: " .. item.name)
end

print("== panel structure")
local function opt(key) for _, o in ipairs(panel.settings) do if o.label == L(key) then return o end end end
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
check(sections == 5, "five sections (window, text, layer, sound, log)")
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

print("== Cyrodiil only")
local activated = handlers[EVENT_PLAYER_ACTIVATED]
check(activated ~= nil, "registers EVENT_PLAYER_ACTIVATED")
check(PBsKillLogWindowBuffer.hidden == true, "the log text starts hidden until the player is known to be in Cyrodiil")
activated()
check(PBsKillLogWindowBuffer.hidden == false, "entering the world in Cyrodiil shows the log")
local shownBefore = #messages
for _, place in ipairs({ "imperialcity", "icCampaign", "battleground", "elsewhere" }) do
    zone = place
    now = now + 20000
    fire(0, "", "@Eve" .. place, "Eve", 1, 1, "@Frank", "Frank", 2, 1, false)
    fire(0, "", "@Me", "Myself^Mx", 1, 1, "@Gus" .. place, "Gus", 2, 1, false)
    activated()
    check(#messages == shownBefore and #sounds == 0, "kills in '" .. place .. "' are not logged and play no sound")
    check(PBsKillLogWindowBuffer.hidden == true, "the log text is hidden in '" .. place .. "'")
end
zone = "cyrodiil"
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
check(#messages == shownBefore + 2, "a Cyrodiil kill is not mistaken for the twin of one that was ignored elsewhere")
local chatBefore = #chat
SLASH_COMMANDS["/pbkl"]("test")
check(#chat == chatBefore, "/pbkl test in Cyrodiil needs no warning")
zone = "elsewhere"
SLASH_COMMANDS["/pbkl"]("test")
check(chat[#chat] == "[PBsKillLog] " .. L("CMD_TEST_ELSEWHERE"), "/pbkl test elsewhere says the log is only drawn in Cyrodiil")
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
    -- what the library does: Select() fires AddonSelected, sets .selected, then pushes the scene
    CALLBACK_MANAGER:FireCallbacks("LibHarvensAddonSettings_AddonSelected", panel.name, panel)
    panel.selected = true
    currentScene = "panel"
    if HAS_PANEL_SCENE then SetPanelSceneState(SCENE_SHOWN) end
end
local function ClosePanel()
    if HAS_PANEL_SCENE then SetPanelSceneState(SCENE_HIDING) end
    panel.selected = false
    currentScene = "hud"
    -- the PC copy of the library has no panel scene: the preview notices on its next poll
    if not HAS_PANEL_SCENE and created["PBsKillLogPreview"] then
        now = now + 400
        created["PBsKillLogPreview"].handlers.OnUpdate()
    end
end
if HAS_PANEL_SCENE then
    currentScene = "list"
    CALLBACK_MANAGER:FireCallbacks("LibHarvensAddonSettings_AddonSelected", panel.name, panel)
    local pv = created["PBsKillLogPreview"]
    check(pv == nil or pv.hidden, "AddonSelected while the list is still the scene shows nothing yet")
    panel.selected = true
    currentScene = "panel"
    SetPanelSceneState(SCENE_SHOWN)
else
    CALLBACK_MANAGER:FireCallbacks("LibHarvensAddonSettings_AddonSelected", panel.name, panel)
    panel.selected = true
    currentScene = "panel"
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
currentScene = "hud"
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
print("== console crash guards")
local function slurp(f) local h = assert(io.open(ADDON_DIR .. f, "rb")); local t = h:read("*a"); h:close(); return t end
local function stripLua(t) return (t:gsub("%-%-[^\n]*", "")) end
local code = {
    ["PBsKillLog.lua"] = stripLua(slurp("PBsKillLog.lua")), ["Preview.lua"] = stripLua(slurp("Preview.lua")),
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
