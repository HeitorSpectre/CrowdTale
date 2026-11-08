require("CoopNetConfig.lua")
require("CoopLink.lua")

local kRelay = gCoopRelayUrl
local kTimeout = 8
local kHeartbeatSeconds = 10
local mBusy = false
local mBusyAt = 0
local mRid = (os.time() % 100000) * 1000
local mInbox = {}

local kSessionPref = "Wolf Coop Session"
local kNamePref = "Wolf Coop Name"
local kStaleSeconds = 600

gCoopSession = gCoopSession or nil
gCoopPlayerName = gCoopPlayerName or nil

local function RunTime()
  local ok, clock = pcall(os.clock)
  if ok and type(clock) == "number" then
    return math.floor(clock), true
  end
  return math.floor(GetTotalTime()), false
end

local function Prefs()
  local ok, prefs = pcall(GetPreferences)
  if ok and prefs then
    return prefs
  end
  return nil
end

local function WritePref(key, value)
  local prefs = Prefs()
  if not prefs then
    return
  end
  if PropertyExists(prefs, key) then
    PropertySet(prefs, key, value)
  elseif value ~= "" then
    PropertyCreate(prefs, key, "string", value)
  end
end

local function ReadPref(key)
  local prefs = Prefs()
  if prefs and PropertyExists(prefs, key) then
    local value = PropertyGet(prefs, key)
    if type(value) == "string" then
      return value
    end
  end
  return nil
end

local function StoreSession(session)
  gCoopSession = session
  if session then
    WritePref(kSessionPref, session.code .. ":" .. session.token .. ":" .. session.role .. ":" ..
      tostring(RunTime()) .. ":" .. tostring(os.time()))
  else
    WritePref(kSessionPref, "")
  end
end

function CoopNet_Text(node, vars)
  local text = node
  local ok, data = pcall(DlgEvaluateToNode, "ui_online.dlog", node, "text", false)
  if ok and data then
    local okText, value = pcall(function()
      return data:GetText()
    end)
    if okText and type(value) == "string" then
      text = value
    end
  end
  if vars then
    text = string.gsub(text, "{(%w+)}", function(key)
      local value = vars[key]
      if value == nil then
        return "{" .. key .. "}"
      end
      return tostring(value)
    end)
  end
  return text
end

function CoopNet_OnReply(body)
  if type(body) == "string" and #body < 16384 then
    table.insert(mInbox, body)
    if #mInbox > 8 then
      table.remove(mInbox, 1)
    end
  end
end

local function NextFrame()
  if WaitForNextFrame then
    WaitForNextFrame()
  else
    Yield()
  end
end

function CoopNet_Encode(text)
  return (string.gsub(tostring(text or ""), "[^%w%-_%.~]", function(c)
    return string.format("%%%02X", string.byte(c))
  end))
end

function CoopNet_Call(path, params)
  while mBusy and GetTotalTime() - mBusyAt < kTimeout + 1 do
    NextFrame()
  end
  mBusy = true
  mBusyAt = GetTotalTime()
  mRid = mRid + 1
  local rid = mRid
  mInbox = {}
  local url = kRelay .. path .. "?rid=" .. tostring(rid)
  if params and params ~= "" then
    url = url .. "&" .. params
  end
  local result
  if pcall(HttpGetAsync, url, "CoopNet_OnReply") then
    local waited = 0
    while waited < kTimeout and not result do
      NextFrame()
      waited = waited + GetFrameTime()
      while 0 < #mInbox and not result do
        local body = table.remove(mInbox, 1)
        local ok, reply = pcall(HttpParseJson, body)
        if ok and type(reply) == "table" and tonumber(reply.rid) == rid then
          result = reply
        end
      end
    end
  end
  mBusy = false
  return result
end

function CoopNet_RelayHost()
  return (string.gsub(kRelay, "^https?://", ""))
end

local mMarkedAt = -1000
function CoopNet_GetSession()
  if gCoopSession then
    local now = RunTime()
    if now - mMarkedAt >= 3 or now < mMarkedAt then
      mMarkedAt = now
      WritePref(kSessionPref, gCoopSession.code .. ":" .. gCoopSession.token .. ":" .. gCoopSession.role .. ":" ..
        tostring(now) .. ":" .. tostring(os.time()))
    end
    return gCoopSession
  end
  local value = ReadPref(kSessionPref)
  if not value or value == "" then
    return nil
  end
  local code, token, role, runTime, wallTime = string.match(value, "^(%w+):(%x+):(%a+):(%d+):(%d+)$")
  local now, reliable = RunTime()
  local restarted = reliable and now + 5 < tonumber(runTime or 0)
  local stale = not reliable and os.time() - tonumber(wallTime) > kStaleSeconds
  if not code or restarted or stale then
    WritePref(kSessionPref, "")
    if CoopLink_LogNow then
      CoopLink_LogNow("net: session dropped (" .. (restarted and "game restarted" or "marks too old") ..
        ", clock " .. (reliable and "process" or "engine") .. ")")
    end
    return nil
  end
  gCoopSession = { code = code, token = token, role = role }
  return gCoopSession
end

function CoopNet_ClearSession()
  StoreSession(nil)
end

local function SessionParams(session)
  return "code=" .. session.code .. "&token=" .. session.token
end

function CoopNet_FormatCode(code)
  return string.sub(code, 1, 3) .. "-" .. string.sub(code, 4)
end

function CoopNet_NormalizeCode(text)
  if type(text) ~= "string" then
    return nil
  end
  local code = string.upper(string.gsub(text, "[%s%-]", ""))
  if #code ~= 6 or not string.match(code, "^[23456789ABCDEFGHJKMNPQRSTUVWXYZ]+$") then
    return nil
  end
  return code
end

function CoopNet_GetPlayerName()
  if gCoopPlayerName and gCoopPlayerName ~= "" then
    return gCoopPlayerName
  end
  local saved = ReadPref(kNamePref)
  if saved and saved ~= "" then
    gCoopPlayerName = saved
    return saved
  end
  if rawget(_G, "PlatformGetUserName") then
    local ok, name = pcall(PlatformGetUserName)
    if ok and type(name) == "string" and name ~= "" then
      gCoopPlayerName = name
      return name
    end
  end
  return nil
end

function CoopNet_SetPlayerName(name)
  if type(name) == "string" then
    name = string.gsub(name, "^%s+", "")
    name = string.gsub(name, "%s+$", "")
    if name ~= "" then
      gCoopPlayerName = string.sub(name, 1, 40)
      WritePref(kNamePref, gCoopPlayerName)
      pcall(SavePrefs)
    end
  end
end

function CoopNet_Leave(reason)
  local session = CoopNet_GetSession()
  if session then
    if CoopLink_LogNow then
      CoopLink_LogNow("net: leaving the session (" .. tostring(reason or "?") .. ")")
    end
    StoreSession(nil)
    CoopNet_Call("/v1/leave", SessionParams(session))
    CoopLink_Leave()
  end
end

local function SceneUp(name)
  local ok, active = pcall(SceneIsActive, name)
  return ok and active
end

function CoopNet_Where()
  if SceneUp("Menu_Main.scene") then
    return "menu"
  end
  local ok, paused = pcall(Game_IsPaused)
  if ok and paused or SceneUp("Menu_Pause.scene") then
    return "paused"
  end
  return "game"
end

local function AnnouncePlayers(reply)
  if not (reply and reply.ok == true) then
    return
  end
  local names = CoopNet_ReadNames(reply)
  CoopLink_SetPeers(names)
  local current = {}
  for _, p in ipairs(names) do
    if p.id then
      current[p.id] = p.name
    end
  end
  local known = gCoopKnownPlayers
  gCoopKnownPlayers = current
  local show = rawget(_G, "CoopDialog_ShowPlayers")
  if show then
    pcall(show, CoopNet_Where() ~= "menu" and names or nil)
  end
  local notify = rawget(_G, "CoopDialog_Notify")
  if not known or not notify or CoopNet_Where() == "menu" then
    return
  end
  local me = tonumber(reply.id)
  for id, name in pairs(current) do
    if not known[id] and id ~= me then
      notify(CoopNet_Text("coop_hud_joined", { name = CoopNet_DisplayName(name) }))
    end
  end
  for id, name in pairs(known) do
    if not current[id] and id ~= me then
      notify(CoopNet_Text("coop_hud_left", { name = CoopNet_DisplayName(name) }))
    end
  end
end

local kWhereCheckSeconds = 2
local kEpisodeCheckSeconds = 6
function CoopNet_EnsureHeartbeat()
  if gCoopHeartbeatThread and ThreadIsRunning(gCoopHeartbeatThread) then
    return
  end
  if CoopLink_LogNow then
    CoopLink_LogNow("net: heartbeat starts")
  end
  gCoopHeartbeatThread = ThreadStart(function()
    local sinceBeat = 0
    local lastWhere
    while CoopNet_GetSession() do
      local accum = 0
      while accum < kWhereCheckSeconds and CoopNet_GetSession() do
        NextFrame()
        accum = accum + GetFrameTime()
      end
      sinceBeat = sinceBeat + accum
      if CoopChoice_InstallHooks then
        CoopChoice_InstallHooks()
      end
      if CoopSync_Ensure then
        local ok, err = pcall(CoopSync_Ensure)
        if not ok and CoopLink_Log then
          CoopLink_Log("sync: start failed: " .. tostring(err))
        end
      end
      if CoopLink_Relay then
        CoopLink_Relay(CoopNet_GetSession())
      end
      local current = CoopNet_GetSession()
      if current and CoopSave_Enter and CoopLink_Info and CoopLink_Info() and CoopNet_Where() == "menu" then
        pcall(CoopSave_Enter, current.role)
      end
      if not CoopSync_Ensure and gCoopSyncLoadError and CoopLink_Hello and CoopLink_Hello() then
        CoopLink_Log("sync: script failed to load: " .. gCoopSyncLoadError)
        gCoopSyncLoadError = nil
      end
      local session = CoopNet_GetSession()
      if session then
        local inEpisode = CoopNet_Where() ~= "menu"
        local where = session.role == "host" and CoopNet_Where() or nil
        local due = inEpisode and kEpisodeCheckSeconds or kHeartbeatSeconds
        if sinceBeat >= due or where ~= lastWhere then
          sinceBeat = 0
          lastWhere = where
          StoreSession(session)
          AnnouncePlayers(CoopNet_Room("/v1/state"))
        end
      end
    end
    if rawget(_G, "CoopDialog_ShowPlayers") then
      pcall(CoopDialog_ShowPlayers, nil)
    end
    gCoopHeartbeatThread = nil
  end)
end

local function NameParam()
  local params = {}
  local name = CoopNet_GetPlayerName()
  if name then
    table.insert(params, "name=" .. CoopNet_Encode(name))
  end
  local sid = CoopLink_PeerId and CoopLink_PeerId()
  if sid then
    table.insert(params, "sid=" .. CoopNet_Encode(sid))
  end
  return table.concat(params, "&")
end

function CoopNet_Create()
  CoopNet_Leave("new session")
  local reply = CoopNet_Call("/v1/create", NameParam())
  if not reply then
    return nil, CoopNet_Text("coop_msg_offline")
  end
  if reply.ok ~= true or type(reply.code) ~= "string" or type(reply.token) ~= "string" then
    return nil, CoopNet_Text("coop_msg_refused")
  end
  StoreSession({ code = reply.code, token = reply.token, role = "host" })
  CoopLink_Host(reply.code)
  CoopNet_EnsureHeartbeat()
  return reply
end

function CoopNet_Join(code)
  CoopNet_Leave("joining another")
  local params = "code=" .. code
  local name = NameParam()
  if name ~= "" then
    params = params .. "&" .. name
  end
  local reply = CoopNet_Call("/v1/join", params)
  if not reply then
    return nil, CoopNet_Text("coop_msg_offline")
  end
  if reply.ok ~= true or type(reply.token) ~= "string" then
    if reply.error == "session not found" then
      return nil, CoopNet_Text("coop_msg_not_found")
    elseif reply.error == "session is full" then
      return nil, CoopNet_Text("coop_msg_full")
    end
    return nil, CoopNet_Text("coop_msg_join_failed")
  end
  StoreSession({ code = code, token = reply.token, role = "guest" })
  CoopNet_EnsureHeartbeat()
  return reply
end

function CoopNet_Check(code)
  local reply = CoopNet_Call("/v1/check", "code=" .. code .. "&kind=game")
  if not reply then
    return nil, CoopNet_Text("coop_msg_offline")
  end
  if reply.ok ~= true then
    if reply.error == "session not found" then
      return nil, CoopNet_Text("coop_msg_not_found")
    elseif reply.error == "session is full" then
      return nil, CoopNet_Text("coop_msg_full")
    end
    return nil, CoopNet_Text("coop_msg_join_failed")
  end
  return true
end

function CoopNet_Room(path, extra)
  local session = CoopNet_GetSession()
  if not session then
    return nil
  end
  local params = SessionParams(session)
  if extra and extra ~= "" then
    params = params .. "&" .. extra
  end
  if path == "/v1/state" and session.role == "host" then
    params = params .. "&where=" .. CoopNet_Where()
  end
  local reply = CoopNet_Call(path, params)
  if reply and reply.ok ~= true and (reply.error == "session not found" or reply.error == "not a member of this session"
      or reply.error == "removed by the host") then
    if gCoopSession == session then
      gCoopEndReason = reply.error == "removed by the host" and "coop_msg_removed" or "coop_msg_closed"
      if CoopLink_LogNow then
        CoopLink_LogNow("net: session ended by the relay (" .. tostring(reply.error) .. ")")
      end
      StoreSession(nil)
      if CoopLink_Leave then
        CoopLink_Leave()
      end
    end
  end
  return reply
end

function CoopNet_ReadNames(state)
  local list = {}
  local names = state and state.names
  if type(names) ~= "table" then
    return list
  end
  local first = names[0] ~= nil and 0 or 1
  local i = first
  while names[i] ~= nil do
    local p = names[i]
    if type(p) == "table" then
      table.insert(list, {
        id = tonumber(p.id),
        name = tostring(p.name or "Player"),
        host = p.host == true,
        phone = p.kind == "phone",
        web = p.kind == "web",
        sid = type(p.sid) == "string" and p.sid or nil
      })
    end
    i = i + 1
  end
  return list
end

function CoopNet_Kick(id)
  local reply = CoopNet_Room("/v1/kick", "id=" .. tostring(math.floor(tonumber(id) or 0)))
  return reply and reply.ok == true
end

function CoopNet_PlatformInfo()
  local parts = {}
  for _, fn in ipairs({ "PlatformGetUserName", "PlatformIsUserSignedIn", "PlatformGetUserID", "PlatformGetDeviceName" }) do
    local f = rawget(_G, fn)
    if f then
      local ok, value = pcall(f)
      table.insert(parts, fn .. "=" .. type(value) .. ":" .. string.sub(tostring(value), 1, 24))
    else
      table.insert(parts, fn .. "=missing")
    end
  end
  return table.concat(parts, "  ")
end

function CoopNet_Note(text)
  if not gCoopDebugNotes then
    return
  end
  pcall(HttpGetAsync, kRelay .. "/v1/health?note=" .. CoopNet_Encode(string.sub(tostring(text), 1, 300)), "CoopNet_OnReply")
end

if CoopNet_GetSession() then
  CoopNet_EnsureHeartbeat()
end

CoopNet_kVoteUnlimited = -1
local kVoteExtraPref = "Wolf Coop Vote Extra"
local kVoteExtraSteps = { 0, 10, 20, 30, CoopNet_kVoteUnlimited }

function CoopNet_GetVoteExtra()
  local value = tonumber(ReadPref(kVoteExtraPref))
  for _, step in ipairs(kVoteExtraSteps) do
    if value == step then
      return step
    end
  end
  return 0
end

function CoopNet_CycleVoteExtra()
  local current = CoopNet_GetVoteExtra()
  local nextValue = kVoteExtraSteps[1]
  for i, step in ipairs(kVoteExtraSteps) do
    if step == current then
      nextValue = kVoteExtraSteps[i % #kVoteExtraSteps + 1]
    end
  end
  WritePref(kVoteExtraPref, tostring(nextValue))
  pcall(SavePrefs)
  return nextValue
end

local kGuestPlayPref = "Wolf Coop Guest Play"

function CoopNet_GetGuestPlay()
  return ReadPref(kGuestPlayPref) == "1"
end

function CoopNet_ToggleGuestPlay()
  local value = not CoopNet_GetGuestPlay()
  WritePref(kGuestPlayPref, value and "1" or "0")
  pcall(SavePrefs)
  return value
end

function CoopNet_DisplayName(name)
  name = tostring(name or "")
  if string.find(name, "%l") or string.find(name, "[\128-\255]") then
    return name
  end
  local result = string.gsub(string.lower(name), "(%a)([%w']*)", function(first, rest)
    return string.upper(first) .. rest
  end)
  return result
end

do
  local ok, err = pcall(require, "CoopSync.lua")
  if not ok then
    gCoopSyncLoadError = tostring(err)
  end
end
