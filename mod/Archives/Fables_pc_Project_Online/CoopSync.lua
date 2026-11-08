require("CoopLink.lua")

local kPoll = 0.25
local kRepeat = 10
local kChunk = 900
local kSyncPref = "Wolf Coop Sync"

local mSnap = (os.time() % 100000) * 10
local mLastWhere
local mLastSent
local mLastRepeat = 0
local mSnapshot
local mChunks = {}
local mAsked = 0
local mAppliedNote

local function Wait(seconds)
  local accum = 0
  while accum < seconds do
    if WaitForNextFrame then
      WaitForNextFrame()
    else
      Yield()
    end
    accum = accum + GetFrameTime()
  end
end

local function Log(text)
  CoopLink_Log("sync: " .. text)
end

local mLogQueue = {}
local mLastError
local mNoLinkNoted = false
local function LogLater(text)
  if CoopLink_LogNow then
    CoopLink_LogNow("sync: " .. text)
  elseif #mLogQueue < 32 then
    table.insert(mLogQueue, text)
  end
end
local function FlushLogs()
  local list = mLogQueue
  mLogQueue = {}
  for _, text in ipairs(list) do
    Log(text)
  end
end

local function Prefs()
  local ok, prefs = pcall(GetPreferences)
  return ok and prefs or nil
end

local function WritePref(value)
  local prefs = Prefs()
  if not prefs then
    return
  end
  if PropertyExists(prefs, kSyncPref) then
    PropertySet(prefs, kSyncPref, value)
  elseif value ~= "" then
    PropertyCreate(prefs, kSyncPref, "string", value)
  end
end

local function ReadPref()
  local prefs = Prefs()
  if prefs and PropertyExists(prefs, kSyncPref) then
    local value = PropertyGet(prefs, kSyncPref)
    if type(value) == "string" then
      return value
    end
  end
  return ""
end

local kCheckpointPref = "Wolf Coop Sync Checkpoint"
local mGuestCheckpoint

function CoopSync_PrepareCheckpoint(script, file, node)
  if not file or file == "" then
    return
  end
  pcall(AgentSetProperty, "logic_saveload", "SaveLoad - Checkpoint Dialog File", file)
  pcall(AgentSetProperty, "logic_saveload", "SaveLoad - Checkpoint Dialog Node", node)
  pcall(AgentSetProperty, "logic_script", "Script - Current", script)
end

function CoopSync_WriteCheckpointPref(value)
  local prefs = Prefs()
  if not prefs then
    return
  end
  if PropertyExists(prefs, kCheckpointPref) then
    PropertySet(prefs, kCheckpointPref, value)
  elseif value ~= "" then
    PropertyCreate(prefs, kCheckpointPref, "string", value)
  end
end

local function ReadCheckpointPref()
  local prefs = Prefs()
  if prefs and PropertyExists(prefs, kCheckpointPref) then
    local value = PropertyGet(prefs, kCheckpointPref)
    if type(value) == "string" then
      return value
    end
  end
  return ""
end

local kCoopSlot = "saveslot77.bundle"
local kMainSlotPref = "Wolf Coop Main Slot"
local kLoadedSavePref = "Wolf Coop Loaded Save"

local function GetStringPref(key)
  local prefs = Prefs()
  if prefs and PropertyExists(prefs, key) then
    local value = PropertyGet(prefs, key)
    if type(value) == "string" then
      return value
    end
  end
  return ""
end

local function SetStringPref(key, value)
  local prefs = Prefs()
  if not prefs then
    return
  end
  if PropertyExists(prefs, key) then
    PropertySet(prefs, key, value)
  elseif value ~= "" then
    PropertyCreate(prefs, key, "string", value)
  end
  pcall(SavePrefs)
end

function CoopSave_Enter(role)
  if not (SaveLoad_GetSlot and SaveLoad_SetSlot) then
    return
  end
  local current = SaveLoad_GetSlot()
  if current == kCoopSlot then
    return
  end
  SetStringPref(kMainSlotPref, current or "")
  local fresh = not ResourceExists(kCoopSlot)
  if fresh and role == "host" and current and ResourceExists(current) then
    pcall(SaveLoad_Copy, current, kCoopSlot)
    local okL, latest = pcall(SaveLoad_GetSlotValue, "Latest Save", current)
    if okL and type(latest) == "string" and latest ~= "" then
      local fromBase = string.gsub(current, "%.bundle$", "")
      local renamed = string.gsub(latest, fromBase, "saveslot77")
      pcall(SaveLoad_SetSlotValue, "Latest Save", renamed, nil, kCoopSlot)
      CoopLink_LogNow("sync: co-op slot latest save " .. tostring(latest) .. " -> " .. tostring(renamed))
    end
  end
  SaveLoad_SetSlot(kCoopSlot)
  pcall(SaveLoad_SetSlotName, CoopNet_Text("coop_title"), kCoopSlot)
  pcall(Save, kCoopSlot)
  CoopLink_LogNow("sync: using the co-op save slot" .. (fresh and " (new" .. (role == "host" and ", copied from " .. tostring(current) or "") .. ")" or ""))
end

function CoopSave_Leave()
  if not (SaveLoad_GetSlot and SaveLoad_SetSlot) then
    return
  end
  local main = GetStringPref(kMainSlotPref)
  if main ~= "" and SaveLoad_GetSlot() == kCoopSlot then
    SaveLoad_SetSlot(main)
    CoopLink_LogNow("sync: back to the player's own save slot " .. main)
  end
  if main ~= "" then
    SetStringPref(kMainSlotPref, "")
  end
end

local function LoadHostSave()
  local state = CoopLink_SaveState()
  if not state or state.ready == "0" or state.ready == GetStringPref(kLoadedSavePref) then
    return false
  end
  SetStringPref(kLoadedSavePref, state.ready)
  local okNames, names = pcall(ResourceLocationGetNames, "<User>", "_saveslot77_*")
  if okNames and type(names) == "table" then
    for _, name in ipairs(names) do
      pcall(Unload, name)
    end
  end
  pcall(Unload, kCoopSlot)
  SaveLoad_SetSlot(kCoopSlot)
  local save
  local name = gCoopHostSaveName
  if name and string.match(name, "^_saveslot77_[%w_]+%.bundle$") then
    pcall(Unload, name)
    local okE, exists = pcall(ResourceExists, name)
    if okE and exists then
      save = name
    end
  end
  if not save then
    local okS, latest = pcall(SaveLoad_GetLatestSave, kCoopSlot)
    save = okS and latest or nil
  end
  if not save then
    Log("host's save received, but no save found in it (" .. tostring(name) .. ")")
    return false
  end
  Log("guest loads the host's save " .. tostring(state.ready))
  ThreadStart(function()
    SaveLoad_Load(save)
  end)
  return true
end

local function HostSendSave()
  if not CoopLink_SaveSend() then
    return
  end
  local okL, latest = pcall(SaveLoad_GetSlotValue, "Latest Save", kCoopSlot)
  if okL and type(latest) == "string" and string.match(latest, "^[%w_%.]+$") then
    CoopLink_Send("SV|" .. latest)
  end
  local waited = 0
  while waited < 30 do
    Wait(0.5)
    waited = waited + 0.5
    local state = CoopLink_SaveState()
    if not state or not state.sending then
      break
    end
  end
  Log(string.format("host's co-op save sent (%.1f s)", waited))
end

local function Where()
  if CoopNet_Where() == "menu" then
    return nil, nil
  end
  local ep = SubProject_GetCurrent and SubProject_GetCurrent() or nil
  local ok, script = pcall(AgentGetProperty, "logic_script", "Script - Current")
  if not ok or type(script) ~= "string" or script == "" then
    return ep, nil
  end
  return ep, script
end

local function Escape(text)
  return (string.gsub(text, "[%%|\t\n]", function(c)
    return string.format("%%%02X", string.byte(c))
  end))
end

local function Unescape(text)
  return (string.gsub(text, "%%(%x%x)", function(h)
    return string.char(tonumber(h, 16))
  end))
end

local function KeyName(key)
  if type(key) == "string" then
    return key
  end
  local ok, name = pcall(SymbolToString, key)
  if ok and type(name) == "string" and name ~= "" then
    return name
  end
  return (string.gsub(tostring(key), "^symbol: ", ""))
end

local function LogicSnapshot()
  if not AgentExists("logic_game") then
    return nil
  end
  local props = AgentGetProperties("logic_game")
  local ok, keys = pcall(PropertyGetKeys, props)
  if not ok or type(keys) ~= "table" then
    return nil
  end
  local lines = {}
  for _, key in ipairs(keys) do
    local name = KeyName(key)
    local value = PropertyGet(props, key)
    local kind = type(value)
    if kind == "boolean" then
      table.insert(lines, Escape(name) .. "\tb\t" .. (value and "1" or "0"))
    elseif kind == "number" then
      table.insert(lines, Escape(name) .. "\tn\t" .. tostring(value))
    elseif kind == "string" then
      table.insert(lines, Escape(name) .. "\ts\t" .. Escape(value))
    end
  end
  return table.concat(lines, "\n"), #keys, #lines
end

local function ApplyLogic(text)
  if not text or text == "" or not AgentExists("logic_game") then
    return 0
  end
  local props = AgentGetProperties("logic_game")
  local okKeys, keys = pcall(PropertyGetKeys, props)
  local byName = {}
  if okKeys and type(keys) == "table" then
    for _, k in ipairs(keys) do
      byName[KeyName(k)] = k
    end
  end
  local count = 0
  for line in string.gmatch(text, "[^\n]+") do
    local name, kind, raw = string.match(line, "^([^\t]+)\t(%a)\t(.*)$")
    local key = name and byName[Unescape(name)]
    if key then
      do
        local value
        if kind == "b" then
          value = raw == "1"
        elseif kind == "n" then
          value = tonumber(raw)
        elseif kind == "s" then
          value = Unescape(raw)
        end
        if value ~= nil and PropertyGet(props, key) ~= value then
          PropertySet(props, key, value)
          count = count + 1
        end
      end
    end
  end
  return count
end

local function ApplyPending()
  local pending = ReadPref()
  if pending ~= "" and AgentExists("logic_game") then
    WritePref("")
    mAppliedNote = ApplyLogic(pending)
  end
  local checkpoint = ReadCheckpointPref()
  if checkpoint ~= "" and AgentExists("logic_saveload") then
    CoopSync_WriteCheckpointPref("")
    local script, file, node = string.match(checkpoint, "^([^\t]*)\t([^\t]*)\t([^\t]*)$")
    if script then
      CoopSync_PrepareCheckpoint(script, file, node)
      mGuestCheckpoint = file .. ":" .. node
      gCoopAppliedCheckpoint = node
    end
  end
end
local function WrapRestore()
  local fn = rawget(_G, "SaveLoad_RestoreCheckpoint")
  if type(fn) ~= "function" or fn == gCoopRestoreWrapper then
    return
  end
  local original = fn
  gCoopRestoreWrapper = function(...)
    local okF, file = pcall(AgentGetProperty, "logic_saveload", "SaveLoad - Checkpoint Dialog File")
    local okN, node = pcall(AgentGetProperty, "logic_saveload", "SaveLoad - Checkpoint Dialog Node")
    if okF and okN and type(file) == "string" and type(node) == "string" and file ~= "" and node ~= "" then
      gCoopLoadedCheckpoint = { file = file, node = node, at = os.clock() }
      if CoopLink_LogNow then
        CoopLink_LogNow("sync: this load resumes at checkpoint " .. node)
      end
    end
    return original(...)
  end
  _G.SaveLoad_RestoreCheckpoint = gCoopRestoreWrapper
end
WrapRestore()

if Callback_LogicOnSceneAdd then
  Callback_LogicOnSceneAdd:Add(function()
    WrapRestore()
    if not (gCoopLoadedCheckpoint and os.clock() - (gCoopLoadedCheckpoint.at or -1000) < 15) then
      gCoopLoadedCheckpoint = nil
    end
    local okF, file = pcall(AgentGetProperty, "logic_saveload", "SaveLoad - Checkpoint Dialog File")
    local okN, node = pcall(AgentGetProperty, "logic_saveload", "SaveLoad - Checkpoint Dialog Node")
    if okF and okN and type(file) == "string" and type(node) == "string" and file ~= "" and node ~= "" then
      gCoopLoadedCheckpoint = { file = file, node = node, at = os.clock() }
    end
    pcall(ApplyPending)
    gCoopSceneLoaded = true
    if CoopNet_GetSession and CoopNet_GetSession() then
      local ok, err = pcall(CoopNet_EnsureHeartbeat)
      CoopLink_LogNow("sync: scene added (" .. tostring(SubProject_GetCurrent and SubProject_GetCurrent()) ..
        ", checkpoint " .. (gCoopLoadedCheckpoint and gCoopLoadedCheckpoint.node or "none") ..
        "), heartbeat " .. (ok and "ensured" or ("failed: " .. tostring(err))) ..
        ", running=" .. tostring(gCoopHeartbeatThread ~= nil and ThreadIsRunning(gCoopHeartbeatThread)))
    end
  end)
end

local kMoveEpsilon = 0.05
local kTeleport = 6
local kQteWait = 45
local kBatchBytes = 1100
local mOutbox = {}
local mLastMove
local mLastStopped = true
local mInputMuted = false
local mApplying = false
local mPendingQte = {}
local mWrapped = {}
local mOriginal = {}
local kVerbWait = 4
local mVerb, mVerbAt
local mUseUntil = 0
local mHostUseUntil = 0
local mWatchThread
local mGuestWatch
local mStruggleFed = false
local mAimFed = false
local mActionMuted = false

local kGuestPlayFresh = 15
local mGuestPlayAt = -1000
local mLocalMoveAt = -1000
local mFollowPathAt = -1000
local mLastOwnMove
local mOwnUseUntil = 0
local mOwn = {}
local mAppliedAt = {}
local mGuestMashOwed = 0
local mLastOption = -1000
local mLastMoveAt, mHostRunning
local mLastFightAt = -1000
local mStartWait
local mStartChecked = false
local kFightQuiet = 8

local kFamilies = { "Move", "Attack" }
local kDirections = { "Up", "Down", "Left", "Right" }
local kQteHandlers = {
  "ActionMove_OnUp", "ActionMove_OnDown", "ActionMove_OnLeft", "ActionMove_OnRight",
  "ActionAttack_OnUp", "ActionAttack_OnDown", "ActionAttack_OnLeft", "ActionAttack_OnRight",
  "Action_OnEnterKey", "Action_OnLeftMouse", "ActionAttack_OnTrigger",
  "ActionMove_OnLeftStick", "ActionMove_OnRightStick", "Action_Swipe_Completed"
}
local kMashHandlers = { "Struggle_Execute", "Struggle_Execute_Touch" }

local function Role()
  local session = CoopNet_GetSession()
  return session and session.role or nil
end

local function GuestPlaying()
  return Role() == "guest" and GetTotalTime() - mGuestPlayAt < kGuestPlayFresh
end

local function NoteOwn(key)
  mOwn[key] = GetTotalTime()
end

local function TakeOwn(key, window)
  local at = mOwn[key]
  if at and GetTotalTime() - at < (window or 8) then
    mOwn[key] = nil
    return true
  end
  return false
end

local function Navigating()
  local ok, mode = pcall(Game_GetMode)
  return ok and eModeNavigate ~= nil and mode == eModeNavigate
end

local function Player()
  local ok, player = pcall(Game_GetPlayer)
  if ok and player then
    return player
  end
  return nil
end

local function Queue(event)
  if #mOutbox < 64 then
    table.insert(mOutbox, event)
  end
end

local function FlushNow()
  if #mOutbox == 0 then
    return
  end
  local batch, size = {}, 2
  for _, event in ipairs(mOutbox) do
    if size + #event + 1 > kBatchBytes and 0 < #batch then
      CoopLink_SendNow("B|" .. table.concat(batch, "\n"))
      batch, size = {}, 2
    end
    table.insert(batch, event)
    size = size + #event + 1
  end
  mOutbox = {}
  if 0 < #batch then
    CoopLink_SendNow("B|" .. table.concat(batch, "\n"))
  end
end

local function ActionFlags()
  local flags = {}
  local ok, list = pcall(Action_GetActiveActions)
  if not ok or type(list) ~= "table" then
    return flags
  end
  for _, agent in ipairs(list) do
    local props = agent.mProps
    for _, family in ipairs(kFamilies) do
      for _, dir in ipairs(kDirections) do
        local kind = family .. " " .. dir
        if props[kind .. " Enabled"] == true then
          flags[kind] = true
        elseif flags[kind] == nil then
          flags[kind] = false
        end
      end
    end
  end
  return flags
end

local function ActiveActions()
  local ok, list = pcall(Action_GetActiveActions)
  return ok and type(list) == "table" and 0 < #list
end

local function Wrap(name, makeWrapper)
  local current = rawget(_G, name)
  if type(current) ~= "function" or current == mWrapped[name] then
    return
  end
  mOriginal[name] = current
  local wrapper = makeWrapper(current)
  mWrapped[name] = wrapper
  _G[name] = wrapper
end

local function QteWrapper(original)
  return function(...)
    local role = Role()
    if role == "guest" and CoopLink_Info() and not mApplying then
      return
    end
    return original(...)
  end
end

local function MashWrapper(original)
  return function(...)
    if Role() == "guest" and CoopLink_Info() and not mApplying then
      return
    end
    return original(...)
  end
end

local function WaitFrame()
  if WaitForNextFrame then
    WaitForNextFrame()
  else
    Yield()
  end
end

local kAutoQteDelay = 0.4
local kHandlerFor

function CoopSync_AimTarget()
  local okCombat, combat = pcall(Reticle_IsCombatMode)
  if not okCombat or combat ~= true then
    return nil, {}
  end
  local names = {}
  local target
  local okAgents, agents = pcall(SceneGetAgents, Game_GetScene())
  if okAgents and type(agents) == "table" then
    for _, agent in pairs(agents) do
      local okU, useable = pcall(Game_IsUseable, agent)
      local okP, selectable = pcall(AgentGetProperty, agent, "Game Selectable")
      local okS, onScreen = pcall(AgentIsOnScreen, agent)
      local okH, hidden = pcall(AgentIsHidden, agent)
      if okU and useable and not (okP and selectable == false) and not (okH and hidden) and (not okS or onScreen) then
        table.insert(names, AgentGetName(agent))
        target = target or agent
      end
    end
  end
  return target, names
end

local function HostWatch()
  local executing = {}
  local tracked = {}
  local bars = {}
  local lastWindow = ""
  local windowSince = 0
  local autoDone = false
  local lastMash = 0
  local inCombat, combatSince, aimDone = false, 0, false
  local windowHits, closedAt = 0, nil
  local function DecideMiss()
    if closedAt and windowHits == 0 then
      Queue("Q|Miss")
      FlushNow()
      LogLater("host let a quick time event run out")
    end
    closedAt = nil
  end
  local barSent, barSentAt, barDone = {}, {}, {}
  while Role() == "host" and CoopLink_Info() do
    local info = CoopLink_Info()
    local now = {}
    local enabled = {}
    local ok, list = pcall(Action_GetActiveActions)
    local watched = {}
    local clock = GetTotalTime()
    if ok and type(list) == "table" then
      for _, agent in ipairs(list) do
        tracked[agent] = clock
      end
    end
    for agent, seen in pairs(tracked) do
      if clock - seen > 3 then
        tracked[agent] = nil
      else
        table.insert(watched, agent)
      end
    end
    if ok and type(list) == "table" then
      for _, agent in ipairs(watched) do
        local okName, name = pcall(AgentGetName, agent)
        local props = agent.mProps
        for _, family in ipairs(kFamilies) do
          for _, dir in ipairs(kDirections) do
            local kind = family .. " " .. dir
            local key = tostring(okName and name or "") .. "|" .. kind
            local on = props[kind .. " Enabled"]
            local busy = props[kind .. " Executing"] == true
            local before = executing[key] or {}
            local hit = (before.on == true and before.window and on == false) or (busy and not before.busy)
            local sent = before.sent
            if on == true and not before.on then
              sent = false
            end
            if hit and not sent then
              sent = true
              windowHits = windowHits + 1
              Queue("Q|" .. kind)
              FlushNow()
              LogLater("host quick time event " .. kind)
            end
            now[key] = { on = on, busy = busy, sent = sent, window = props["Action Enabled"] == true }
            if tracked[agent] == clock and props["Action Enabled"] and props[kind .. " Enabled"] == true then
              table.insert(enabled, kind)
            end
          end
        end
      end
    end
    executing = now
    local okCombat, combat = pcall(Reticle_IsCombatMode)
    combat = okCombat and combat == true
    if combat and not inCombat then
      inCombat = true
      combatSince = GetTotalTime()
      aimDone = false
    elseif not combat then
      inCombat = false
    end
    if inCombat and not aimDone and info and info.autoqte and GetTotalTime() - combatSince > 0.6 then
      combatSince = GetTotalTime()
      local target, names = CoopSync_AimTarget()
      if target then
        aimDone = true
        LogLater("autoqte aim, targets: " .. table.concat(names, ", "))
        ThreadStart(function()
          Game_UseAgent(target)
        end)
      end
    end
    local window = table.concat(enabled, ", ")
    if window ~= lastWindow then
      if lastWindow == "" and window ~= "" then
        DecideMiss()
        windowHits = 0
      elseif window == "" then
        closedAt = GetTotalTime()
      end
      lastWindow = window
      windowSince = GetTotalTime()
      autoDone = false
      if window ~= "" then
        LogLater("host quick time event window: " .. window)
      end
    end
    if closedAt and GetTotalTime() - closedAt > 1 then
      DecideMiss()
    end
    if info and info.autoqte and window ~= "" and not autoDone and GetTotalTime() - windowSince > kAutoQteDelay then
      autoDone = true
      local kind = enabled[1]
      local fn = rawget(_G, kHandlerFor[kind] or "")
      if fn then
        local okHit, err = pcall(fn, {})
        local agent = list[1]
        local props = agent and agent.mProps
        LogLater(string.format("autoqte %s: ok=%s err=%s cursor=%s choice=%s enabled=%s dialog=%s",
          kind, tostring(okHit), tostring(err), tostring(Input_UseCursor and Input_UseCursor()),
          tostring(props and props["Choice Functionality Enabled"]),
          tostring(props and props[kind .. " Enabled"]), tostring(props and props[kind .. " Dialog"])))
      end
    end
    local barsNow = {}
    local okS, active = pcall(Struggle_GetAllActive)
    if okS and type(active) == "table" then
      for _, agent in ipairs(active) do
        local okName, name = pcall(AgentGetName, agent)
        name = okName and name or "?"
        local pct = tonumber(agent.mProps["Button Mash - Current Percentage"]) or 0
        local last = bars[name]
        local props = agent.mProps
        if not barDone[name] then
          local scrub = tonumber(props["Chore Scrubber - Percentage Current"]) or 0
          local won = 0.95 <= scrub
          if won or props["Struggle - Failed"] == true then
            barDone[name] = true
            Queue("Q|BarDone|" .. Escape(name) .. "|" .. (won and "1" or "0"))
            FlushNow()
            LogLater("host struggle " .. name .. (won and " won" or " lost"))
          elseif math.abs(pct - (barSent[name] or -1)) > 0.004 and GetTotalTime() - (barSentAt[name] or -1) > 0.15 then
            barSent[name] = pct
            barSentAt[name] = GetTotalTime()
            Queue(string.format("Q|Bar|%s|%.4f", Escape(name), pct))
            FlushNow()
          end
        end
        if not last then
          LogLater("host struggle " .. name)
        end
        barsNow[name] = tonumber(agent.mProps["Button Mash - Current Percentage"]) or pct
        if info and info.autoqte and GetTotalTime() - lastMash > 0.1 and ButtonMash_DoTheMash then
          lastMash = GetTotalTime()
          pcall(ButtonMash_DoTheMash, agent, 0.5)
        end
      end
    end
    for name in pairs(bars) do
      if not barsNow[name] then
        if not barDone[name] then
          if 0.9 <= (bars[name] or 0) then
            Queue("Q|BarDone|" .. Escape(name) .. "|1")
            FlushNow()
          end
          LogLater("host struggle " .. name .. " closed")
        end
        barSent[name], barSentAt[name], barDone[name] = nil, nil, nil
      end
    end
    bars = barsNow
    if next(barsNow) == nil then
      mGuestMashOwed = 0
    end
    WaitFrame()
  end
  mWatchThread = nil
end

local function UseWrapper(original)
  return function(agent, ...)
    if Role() == "host" and CoopLink_Info() and agent then
      local ok, name = pcall(AgentGetName, agent)
      if ok and type(name) == "string" then
        local okCombat, combat = pcall(Reticle_IsCombatMode)
        if okCombat and combat == true then
          Queue("A|" .. Escape(name))
          LogLater("host aims at " .. name)
        else
          Queue("U|" .. Escape(name))
          mHostUseUntil = GetTotalTime() + 6
          LogLater("host uses " .. name)
        end
      end
    elseif agent and GuestPlaying() then
      local ok, name = pcall(AgentGetName, agent)
      if ok and type(name) == "string" then
        local okCombat, combat = pcall(Reticle_IsCombatMode)
        if okCombat and combat == true then
          return nil
        else
          NoteOwn("U|" .. name)
          mOwnUseUntil = GetTotalTime() + 6
          CoopLink_SendNow("G|U|" .. Escape(name))
          LogLater("guest uses " .. name .. " (own)")
        end
      end
    end
    return original(agent, ...)
  end
end

local function ChoiceIndex(dialogID, choiceID)
  local ok, choices = pcall(DlgGetChoices, dialogID)
  if ok and type(choices) == "table" then
    for i, choice in ipairs(choices) do
      if choice["Choice ID"] == choiceID then
        return i, #choices
      end
    end
  end
  return nil
end

local function SelectWrapper(original)
  return function(dialogID, choiceID, ...)
    if GetTotalTime() < mHostUseUntil and Role() == "host" and CoopLink_Info() then
      mHostUseUntil = 0
      local index, count = ChoiceIndex(dialogID, choiceID)
      if index then
        Queue("V|" .. index)
        LogLater("host verb " .. index .. " of " .. count)
      end
    elseif GetTotalTime() < mOwnUseUntil and Role() == "guest" then
      mOwnUseUntil = 0
      local index = ChoiceIndex(dialogID, choiceID)
      if index then
        CoopLink_SendNow("G|V|" .. index)
      end
    end
    return original(dialogID, choiceID, ...)
  end
end

local function StopWrapper(original)
  return function(dialogID, ...)
    local role = GetTotalTime() < mUseUntil and Role()
    if (role == "guest" or role == "host") and CoopLink_Info() then
      local ok, choices = pcall(DlgGetChoices, dialogID)
      if ok and type(choices) == "table" and 0 < #choices then
        mUseUntil = 0
        LogLater(role .. " verb choice, waiting for the verb")
        local selectChoice = role == "host" and DlgSelectChoice or (mOriginal.DlgSelectChoice or DlgSelectChoice)
        local args = { ... }
        ThreadStart(function()
          local waited = 0
          while not mVerb and waited < kVerbWait do
            Wait(0.1)
            waited = waited + 0.1
          end
          local index = mVerb
          mVerb = nil
          local choice = index and choices[index]
          if choice then
            Log("guest uses the host's verb " .. index)
            selectChoice(dialogID, choice["Choice ID"])
          else
            Log("guest got no verb, stops")
            original(dialogID, (table.unpack or unpack)(args))
          end
        end)
        return
      end
    end
    return original(dialogID, ...)
  end
end

local mRestartHooked
local function OnHostRestart()
  if Role() == "host" and CoopLink_Info() then
    CoopLink_SendNow("R")
    CoopLink_LogNow("sync: host replays from the checkpoint")
  end
end

local function HookRestart()
  local cb = rawget(_G, "Callback_OnRestart")
  if cb and cb ~= mRestartHooked and cb.Add then
    cb:Add(OnHostRestart)
    mRestartHooked = cb
  end
end

local function InstallLive()
  HookRestart()
  Wrap("DlgSelectChoice", SelectWrapper)
  Wrap("DlgStop", StopWrapper)
  for _, name in ipairs(kQteHandlers) do
    Wrap(name, QteWrapper)
  end
  for _, name in ipairs(kMashHandlers) do
    Wrap(name, MashWrapper)
  end
  Wrap("Game_UseAgent", UseWrapper)
end

function CoopSync_IsRunning(player)
  local props = player and player.mProps
  local walkKey = rawget(_G, "kWalkAnim") or "Walk Animation - Forward"
  local ok, same = pcall(function()
    local current, run = props[walkKey], props["Player - Run Anim"]
    if current == nil or run == nil then
      return false
    end
    if current == run then
      return true
    end
    local okA, a = pcall(ResourceGetName, current)
    local okB, b = pcall(ResourceGetName, run)
    if okA and okB and a and b then
      return a == b
    end
    return tostring(current) == tostring(run)
  end)
  return ok and same == true
end

local mGuestRunning
local function GuestRun(player, run)
  if run == mGuestRunning then
    return
  end
  mGuestRunning = run
  LogLater(run and "walks -> runs" or "runs -> walks")
  local walkKey = rawget(_G, "kWalkAnim") or "Walk Animation - Forward"
  pcall(function()
    local p = player.mProps
    local kind = run and "Run" or "Walk"
    p[walkKey] = p["Player - " .. kind .. " Anim"]
    p["Settle Anim - Left Anim"] = p["Player - " .. kind .. " Settle Left"]
    p["Settle Anim - Right Anim"] = p["Player - " .. kind .. " Settle Right"]
    PathAgentSetSpeedScale(player, p["Player - " .. kind .. " Speed"])
  end)
end

local function HostMovement(script)
  if not script or not Navigating() then
    mLastMove = nil
    return
  end
  local player = Player()
  if not player then
    return
  end
  local pos = AgentGetWorldPos(player)
  if not mLastMove or VectorDistance(pos, mLastMove) > kMoveEpsilon then
    local now = GetTotalTime()
    local run = CoopSync_IsRunning(player)
    if not run and mLastMove and mLastMoveAt and now > mLastMoveAt then
      local speed = VectorDistance(pos, mLastMove) / (now - mLastMoveAt)
      run = speed > (mHostRunning and 1.6 or 2.6)
    end
    if run ~= mHostRunning then
      mHostRunning = run
      LogLater(run and "host runs" or "host walks")
    end
    mLastMove = pos
    mLastMoveAt = now
    mLastStopped = false
    Queue(string.format("M|%s|%.3f|%.3f|%.3f|%d", Escape(script), pos.x, pos.y, pos.z, run and 1 or 0))
  elseif not mLastStopped then
    mLastStopped = true
    local f = AgentGetForwardVec(player)
    Queue(string.format("F|%s|%.3f|%.3f|%.3f|%.3f|%.3f", Escape(script), pos.x, pos.y, pos.z, f.x, f.z))
  end
end

local function FlushOutbox()
  if #mOutbox == 0 then
    return
  end
  local batch = {}
  local size = 2
  for _, event in ipairs(mOutbox) do
    if size + #event + 1 > kBatchBytes and 0 < #batch then
      CoopLink_Send("B|" .. table.concat(batch, "\n"))
      batch = {}
      size = 2
    end
    table.insert(batch, event)
    size = size + #event + 1
  end
  mOutbox = {}
  if 0 < #batch then
    CoopLink_Send("B|" .. table.concat(batch, "\n"))
  end
end

local function GuestLive(line)
  local kind = string.sub(line, 1, 1)
  local _, myScript = Where()
  if kind == "O" then
    local was = GuestPlaying()
    mGuestPlayAt = string.sub(line, 3) == "1" and GetTotalTime() or -1000
    if was ~= GuestPlaying() then
      Log(GuestPlaying() and "guest plays too" or "guest follows the host only")
    end
    return
  end
  if kind == "M" or kind == "F" then
    local script, x, y, z, fx, fz = string.match(line, "^%a|([^|]*)|([%-%d%.]+)|([%-%d%.]+)|([%-%d%.]+)|?([%-%d%.]*)|?([%-%d%.]*)$")
    if not script or Unescape(script) ~= myScript or not Navigating() then
      return
    end
    if GuestPlaying() and GetTotalTime() - mLocalMoveAt < 0.8 then
      return
    end
    if GetTotalTime() - mLastFightAt < kFightQuiet or 0 < #mPendingQte then
      return
    end
    local player = Player()
    if not player then
      return
    end
    if kind == "M" then
      GuestRun(player, fx == "1")
    else
      GuestRun(player, false)
    end
    local target = Vector(tonumber(x), tonumber(y), tonumber(z))
    local distance = VectorDistance(AgentGetWorldPos(player), target)
    if distance > kTeleport then
      AgentSetWorldPos(player, target)
    elseif distance > 0.1 then
      mFollowPathAt = GetTotalTime()
      PathAgentTo(player, target)
    end
    if kind == "F" and fx ~= "" then
      local face = Vector(target.x + tonumber(fx), target.y, target.z + tonumber(fz))
      ThreadStart(function()
        local waited = 0
        while waited < 3 and PathAgentIsPathing(player) do
          Wait(0.1)
          waited = waited + 0.1
        end
        PathAgentFacePos(player, face)
      end)
    end
  elseif kind == "U" then
    local name = Unescape(string.sub(line, 3))
    local original = mOriginal.Game_UseAgent or Game_UseAgent
    if TakeOwn("U|" .. name) then
      return
    end
    if AgentExists(name) then
      if not mVerbAt or GetTotalTime() - mVerbAt > 1 then
        mVerb = nil
      end
      mUseUntil = GetTotalTime() + 6
      Log("guest uses " .. name)
      ThreadStart(function()
        original(AgentFind(name))
      end)
    end
  elseif kind == "A" then
    local name = Unescape(string.sub(line, 3))
    if not TakeOwn("A|" .. name) then
      table.insert(mPendingQte, { kind = "Aim|" .. name, at = GetTotalTime() })
    end
  elseif kind == "V" then
    mVerb = tonumber(string.sub(line, 3))
    mVerbAt = GetTotalTime()
  elseif kind == "Q" then
    local qte = string.sub(line, 3)
    if not TakeOwn("Q|" .. qte, 10) then
      table.insert(mPendingQte, { kind = qte, at = GetTotalTime() })
    end
  end
end

kHandlerFor = {
  ["Move Up"] = "ActionMove_OnUp", ["Move Down"] = "ActionMove_OnDown",
  ["Move Left"] = "ActionMove_OnLeft", ["Move Right"] = "ActionMove_OnRight",
  ["Attack Up"] = "ActionAttack_OnUp", ["Attack Down"] = "ActionAttack_OnDown",
  ["Attack Left"] = "ActionAttack_OnLeft", ["Attack Right"] = "ActionAttack_OnRight",
  Mash = "Struggle_Execute"
}

local function ActiveStruggles()
  local ok, active = pcall(Struggle_GetAllActive)
  if ok and type(active) == "table" and 0 < #active then
    return active
  end
  return nil
end

local mBarTarget
local mLetRun = false
local mBarDone = false
local mAimGraceUntil, mQteGraceUntil = -1000, -1000

local function IsOpen(flags)
  for _, isOpen in pairs(flags) do
    if isOpen then
      return true
    end
  end
  return false
end

local function ApplicableQte(flags)
  local struggles = ActiveStruggles()
  local okCombat, combat = pcall(Reticle_IsCombatMode)
  local open = IsOpen(flags)
  for i, entry in ipairs(mPendingQte) do
    local k = entry.kind
    if string.match(k, "^Aim|") then
      if okCombat and combat == true then
        return i
      end
    elseif string.match(k, "^Mash|") or string.match(k, "^Bar|") or string.match(k, "^BarDone|") then
      if struggles then
        return i
      end
    elseif k == "Miss" then
      if open then
        return i
      end
    elseif flags[k] then
      return i
    end
  end
  return nil
end

local function GuestQte()
  while 0 < #mPendingQte do
    local flags = ActionFlags()
    local index = ApplicableQte(flags)
    if not index then
      local head = mPendingQte[1]
      if GetTotalTime() - head.at < kQteWait then
        return
      end
      table.remove(mPendingQte, 1)
      Log("quick time event input dropped (no window for it): " .. head.kind)
    else
      for _ = 1, index - 1 do
        local stale = table.remove(mPendingQte, 1)
        Log("quick time event input skipped (window passed): " .. stale.kind)
      end
      local entry = mPendingQte[1]
      local kind = entry.kind
      local aim = string.match(kind, "^Aim|(.+)$")
      if aim then
        table.remove(mPendingQte, 1)
        mAimGraceUntil = GetTotalTime() + 4
        if AgentExists(aim) then
          local use = mOriginal.Game_UseAgent or Game_UseAgent
          ThreadStart(function()
            use(AgentFind(aim))
          end)
          Log("guest aims at " .. aim)
        else
          Log("aim dropped (no such target): " .. aim)
        end
      elseif kind == "Miss" then
        table.remove(mPendingQte, 1)
        mLetRun = true
        Log("the host let this quick time event run out: so does the guest")
      elseif string.match(kind, "^Mash|") or string.match(kind, "^Bar|") or string.match(kind, "^BarDone|") then
        local total = 0
        while mPendingQte[1] do
          local k = mPendingQte[1].kind
          local mash = tonumber(string.match(k, "^Mash|([%d%.]+)$"))
          local bar = tonumber(string.match(k, "^Bar|[^|]*|([%d%.]+)$"))
          local done = string.match(k, "^BarDone|[^|]*|([01])$")
          if mash then
            total = total + mash
          elseif bar then
            if not mBarDone then
              mBarTarget = bar
            end
          elseif done then
            mBarDone = true
            mBarTarget = done == "1" and 1 or 0
            Log("the host's struggle " .. (done == "1" and "was won" or "was lost"))
          else
            break
          end
          table.remove(mPendingQte, 1)
        end
        if 0 < total then
          for _, agent in ipairs(ActiveStruggles() or {}) do
            local props = agent.mProps
            props["Button Mash - Current Percentage"] = (tonumber(props["Button Mash - Current Percentage"]) or 0) + total
            agent.bMashed = true
          end
        end
        mStruggleFed = true
      else
        table.remove(mPendingQte, 1)
        local name = kHandlerFor[kind]
        local fn = name and (mOriginal[name] or rawget(_G, name))
        if fn then
          mApplying = true
          mAppliedAt[kind] = GetTotalTime()
          local ok, err = pcall(fn, {})
          mApplying = false
          mQteGraceUntil = GetTotalTime() + 0.6
          if ok then
            Log("guest quick time event " .. kind)
          else
            Log("quick time event input failed: " .. tostring(err))
          end
        end
      end
    end
  end
end

local function GuestBars()
  local struggles = ActiveStruggles()
  if not struggles then
    mBarTarget = nil
    mBarDone = false
    return
  end
  if mBarTarget then
    for _, agent in ipairs(struggles) do
      agent.mProps["Button Mash - Current Percentage"] = mBarTarget
      agent.bMashed = true
    end
  end
end

local kHoldMax = 60
local mHeld, mHeldSince

local mPaced, mPace = nil, 1
local mPaceSkipUi = false
local mPaceGiven, mPaceGivenAt
local function GuestPace(factor, skipUi)
  if factor == mPace then
    return
  end
  mPaceSkipUi = skipUi and true or false
  if factor == 1 then
    for name, scale in pairs(mPaced or {}) do
      pcall(SceneSetTimeScale, name, scale)
    end
    local okM, mode = pcall(Game_GetMode)
    if okM and eModeMenu ~= nil and mode == eModeMenu then
      mPaceGiven = mPaced
      mPaceGivenAt = GetTotalTime()
    end
    mPaced = nil
  else
    local ok, names = pcall(SceneGetActiveSceneNames, true)
    if not ok or type(names) ~= "table" then
      return
    end
    mPaced = mPaced or {}
    for _, name in pairs(names) do
      if mPaceSkipUi and string.sub(tostring(name), 1, 3) == "ui_" then
      else
        if mPaced[name] == nil then
          local okT, scale = pcall(SceneGetTimeScale, name)
          mPaced[name] = (okT and scale and 0 < scale) and scale or 1
        end
        pcall(SceneSetTimeScale, name, mPaced[name] * factor)
      end
    end
  end
  mPace = factor
end

local function GuestPaceCheck()
  if mPace ~= 1 or not mPaceGiven or gCoopBoxUp then
    return
  end
  local okM, mode = pcall(Game_GetMode)
  if okM and eModeMenu ~= nil and mode == eModeMenu then
    return
  end
  for name, scale in pairs(mPaceGiven) do
    local okT, now = pcall(SceneGetTimeScale, name)
    if okT and now == 0 then
      pcall(SceneSetTimeScale, name, scale)
      LogLater("scene " .. tostring(name) .. " ran again")
    end
  end
  mPaceGiven = nil
end

local function GuestHold(on)
  if on and not mHeld then
    GuestPace(0)
    mHeld = true
    mHeldSince = GetTotalTime()
    LogLater("guest waits for the host's quick time event input")
  elseif not on and mHeld then
    GuestPace(1)
    mHeld = nil
    LogLater(string.format("guest goes on (waited %.1f s)", GetTotalTime() - mHeldSince))
  end
end

local kCatchUpAfter = 0.4
local kCatchUpSpeed = 2
local function GuestCatchUp()
  if mStartWait then
    return
  end
  local head = mPendingQte[1]
  local age = head and GetTotalTime() - head.at or 0
  local behind = head and age > kCatchUpAfter and age < 12
  if behind and not mHeld then
    if mPace ~= kCatchUpSpeed then
      LogLater("guest is behind the host: catching up")
    end
    GuestPace(kCatchUpSpeed)
  elseif mPace == kCatchUpSpeed then
    GuestPace(1)
  end
end

local kStartMax = 120
local kReadyMax = 300

local mBoxWant, mBoxShown, mBoxThread, mBoxFailed

local function BoxKey(view)
  return view and (view.text .. "|" .. tostring(view.button)) or ""
end

local function BoxPush(view)
  local active = UIZ_GetActiveMenu and UIZ_GetActiveMenu()
  if active then
    UIZ_DeactivateMenu(active)
  end
  local menu = UIZ_Popup(view.text, CoopNet_Text("coop_title"))
  function menu:activate()
    UIZ_ConsoleButton_Clear(menu)
    if view.button then
      UIZ_ConsoleButton("facebutton_down", "navhelp_select")
      AgentSetProperty("ui_menu_popup_OK", "Text Scale", 0.5)
    end
  end
  function menu:populate()
    if view.button then
      local button = UIZ_Button("ui_menu_popup_OK", nil, "CoopSync_BoxReady()")
      AgentSetProperty(button, "Text Dialog 2.0 File", "")
      AgentSetProperty(button, "Text Dialog 2.0 Node Name", "")
      AgentSetProperty(button, "Text String", view.button)
    end
  end
  UIZ_ActivateMenu(menu)
end

local function BoxStep()
  if mBoxShown and not (gCoopBoxUp and SceneIsActive("Menu_Pause.scene")) then
    mBoxShown = nil
  end
  if BoxKey(mBoxWant) == BoxKey(mBoxShown) then
    return
  end
  local view = mBoxWant
  if not view then
    Menu_Pause_CloseCoopBox()
    mBoxShown = nil
    LogLater("start box closed")
    return
  end
  if mBoxShown then
    BoxPush(view)
    mBoxShown = view
    return
  end
  if mBoxFailed or not Menu_Pause_OpenCoopBox then
    return
  end
  GuestPace(1)
  local opened = Menu_Pause_OpenCoopBox(function()
    BoxPush(view)
  end)
  if opened then
    mBoxShown = view
    LogLater("start box shown")
  end
end

local function EnsureBoxThread()
  if mBoxThread and ThreadIsRunning(mBoxThread) then
    return
  end
  mBoxThread = ThreadStart(function()
    while true do
      local ok, err = pcall(BoxStep)
      if not ok then
        mBoxFailed = true
        LogLater("start box failed: " .. tostring(err))
        mBoxWant, mBoxShown = nil, nil
      end
      WaitFrame()
    end
  end)
end

local mOnReady
function CoopSync_BoxReady()
  local fn = mOnReady
  mOnReady = nil
  if fn then
    fn()
  end
end

local kReadyKeys = { 0x0D, 0x20 }
local function AskReady(onReady)
  mOnReady = onReady
  ThreadStart(function()
    local wasDown = true
    while mOnReady == onReady and mStartWait do
      local down = false
      for _, vk in ipairs(kReadyKeys) do
        local ok, pressed = pcall(InputPCIsVKeyPressed, vk)
        if ok and pressed then
          down = true
        end
      end
      if down and not wasDown then
        CoopSync_BoxReady()
        return
      end
      wasDown = down
      WaitFrame()
    end
  end)
end

local function Banner(node)
  if CoopDialog_Notify and CoopNet_Text then
    pcall(CoopDialog_Notify, CoopNet_Text(node), 3)
  end
end

local function ShowWait(node)
  mBoxWant = { text = CoopNet_Text(node) }
  EnsureBoxThread()
end

local function ShowReady(ready, total, isReady)
  local vars = { ready = tostring(ready), total = tostring(total) }
  if isReady then
    mBoxWant = { text = CoopNet_Text("coop_box_ready_wait", vars) }
  else
    mBoxWant = { text = CoopNet_Text("coop_box_ready_ask", vars), button = CoopNet_Text("coop_box_ready_button") }
  end
  EnsureBoxThread()
end

local function StartWaitEnd(note)
  if not mStartWait then
    return
  end
  mStartWait = nil
  mOnReady = nil
  mBoxWant = nil
  GuestPace(1)
  if mBoxFailed then
    Banner("coop_hud_all_here")
  end
  LogLater(note)
end

local function OtherGames()
  local okR, state = pcall(CoopNet_Room, "/v1/state")
  if not (okR and state and state.ok == true) then
    return nil
  end
  local others = 0
  for _, p in ipairs(CoopNet_ReadNames(state)) do
    if not p.phone and not p.web and not p.host then
      others = others + 1
    end
  end
  return others
end

local function HostStartWait(script)
  local others = OtherGames() or 0
  if others == 0 then
    return
  end
  mStartWait = { script = script, since = GetTotalTime(), expect = others, ready = {} }
  GuestPace(0, true)
  ShowWait("coop_box_wait_players")
  LogLater("host waits for " .. others .. " game(s) to load " .. script)
end

local function CountKeys(t)
  local n = 0
  for _ in pairs(t) do
    n = n + 1
  end
  return n
end

local function HostGo(note)
  CoopLink_Send("GO|" .. Escape(mStartWait.script))
  StartWaitEnd(note)
end

local function HostStartTick(script)
  if not mStartWait then
    return
  end
  EnsureBoxThread()
  local wait = mStartWait
  local loaded = CountKeys(wait.ready)
  if wait.script ~= script then
    HostGo("host's scene changed: go")
    return
  end
  if not wait.asking then
    local timedOut = GetTotalTime() - wait.since > kStartMax
    if loaded >= wait.expect or timedOut then
      if loaded == 0 then
        HostGo("host goes on: no guest loaded the scene")
        return
      end
      wait.asking = true
      wait.askedAt = GetTotalTime()
      wait.expect = loaded
      wait.oks = {}
      wait.lastAsk = -1000
      wait.lastCount = GetTotalTime()
      LogLater("everyone loaded: ready check")
      AskReady(function()
        wait.hostOk = true
        wait.lastAsk = -1000
        LogLater("host is ready")
      end)
    end
    return
  end
  if GetTotalTime() - wait.lastCount > 5 then
    wait.lastCount = GetTotalTime()
    local others = OtherGames()
    if others and others < wait.expect then
      wait.expect = others
      LogLater("a player left: waiting for " .. others)
    end
  end
  local oks = CountKeys(wait.oks)
  local ready = oks + (wait.hostOk and 1 or 0)
  local total = wait.expect + 1
  if GetTotalTime() - wait.lastAsk > 2 then
    wait.lastAsk = GetTotalTime()
    CoopLink_Send("RQ|" .. Escape(wait.script) .. "|" .. ready .. "|" .. total)
  end
  ShowReady(ready, total, wait.hostOk)
  if wait.hostOk and oks >= wait.expect then
    HostGo("everyone is ready: go")
  elseif GetTotalTime() - wait.askedAt > kReadyMax then
    HostGo("host goes on: not everyone was ready in time")
  end
end

local function HostGuestOk(from, script)
  if mStartWait and mStartWait.asking and script == mStartWait.script then
    if not mStartWait.oks[tostring(from)] then
      mStartWait.oks[tostring(from)] = true
      mStartWait.lastAsk = -1000
      LogLater("a guest is ready")
    end
  end
end

local function HostGuestReady(from, script)
  local _, myScript = Where()
  if mStartWait and script == mStartWait.script then
    mStartWait.ready[tostring(from)] = true
  elseif script == myScript then
    CoopLink_Send("GO|" .. Escape(script))
  end
end

local function GuestStartWait(script)
  mStartWait = { script = script, since = GetTotalTime(), lastY = -1000 }
  GuestPace(0, true)
  ShowWait("coop_box_wait_host")
  LogLater("guest loaded " .. script .. ", waits for the host")
end

local function GuestStartTick()
  if not mStartWait then
    return
  end
  EnsureBoxThread()
  local wait = mStartWait
  if not wait.asked and GetTotalTime() - wait.since > kStartMax then
    StartWaitEnd("guest goes on without the host's go (waited too long)")
    return
  end
  if wait.asked and GetTotalTime() - wait.askedAt > kReadyMax + 30 then
    StartWaitEnd("guest goes on without the host's go (ready check too long)")
    return
  end
  if not wait.asked and GetTotalTime() - wait.lastY > 1.5 then
    wait.lastY = GetTotalTime()
    CoopLink_Send("Y|" .. Escape(wait.script))
  end
  if wait.asked then
    if wait.ok and GetTotalTime() - (wait.lastOk or -1000) > 2 then
      wait.lastOk = GetTotalTime()
      CoopLink_Send("OK|" .. Escape(wait.script))
    end
    ShowReady(wait.ready or 0, wait.total or 2, wait.ok)
  end
end

local function GuestReadyAsked(data)
  local escaped, ready, total = string.match(data, "^([^|]*)|?(%d*)|?(%d*)$")
  local script = Unescape(escaped or data)
  local wait = mStartWait
  if not wait or script ~= wait.script then
    return
  end
  local hostReady = tonumber(ready)
  if hostReady then
    if wait.okAt and GetTotalTime() - wait.okAt < 3 then
      wait.ready = math.max(hostReady, wait.ready or 0)
    else
      wait.ready = hostReady
    end
  end
  wait.total = tonumber(total) or wait.total
  if wait.asked then
    return
  end
  wait.asked = true
  wait.askedAt = GetTotalTime()
  AskReady(function()
    wait.ok = true
    wait.lastOk = -1000
    wait.okAt = GetTotalTime()
    wait.ready = (wait.ready or 0) + 1
    LogLater("guest is ready")
  end)
end

local mOwnBars = {}
local mQteKeysDown = {}
local kQteKeys = {
  Up = { 0x57, 0x26 }, Down = { 0x53, 0x28 }, Left = { 0x41, 0x25 }, Right = { 0x44, 0x27 },
  Enter = { 0x0D }
}
local function GuestOwnInputs()
  local flags = ActionFlags()
  local open = false
  for _, isOpen in pairs(flags) do
    if isOpen then
      open = true
    end
  end
  local pressed = {}
  if open and InputPCIsVKeyPressed then
    for dir, keys in pairs(kQteKeys) do
      for _, vk in ipairs(keys) do
        local okK, down = pcall(InputPCIsVKeyPressed, vk)
        if okK and down then
          pressed[dir] = true
        end
      end
    end
    for dir in pairs(pressed) do
      if not mQteKeysDown[dir] then
        local kind
        if dir == "Enter" then
          for _, d in ipairs(kDirections) do
            if not kind and flags["Attack " .. d] then
              kind = "Attack " .. d
            end
          end
        elseif flags["Attack " .. dir] then
          kind = "Attack " .. dir
        elseif flags["Move " .. dir] then
          kind = "Move " .. dir
        end
        if kind then
          CoopLink_SendNow("G|Q|" .. kind)
          LogLater("guest suggests " .. kind)
        end
      end
    end
  end
  mQteKeysDown = pressed
  local bars = {}
  local struggles = ActiveStruggles()
  if struggles then
    for _, agent in ipairs(struggles) do
      local key = tostring(agent)
      local pct = tonumber(agent.mProps["Button Mash - Current Percentage"]) or 0
      local last = mOwnBars[key]
      if last and pct > last + 0.0005 then
        CoopLink_SendNow(string.format("G|Q|Mash|%.4f", pct - last))
      end
      bars[key] = pct
    end
  end
  mOwnBars = bars
end

local function GuestWatch()
  while Role() == "guest" and CoopLink_Info() do
    if false and GuestPlaying() then
      if mHeld then
        GuestHold(false)
      end
      GuestOwnInputs()
      GuestQte()
      local struggles = ActiveStruggles()
      if struggles then
        for _, agent in ipairs(struggles) do
          mOwnBars[tostring(agent)] = tonumber(agent.mProps["Button Mash - Current Percentage"]) or 0
        end
      end
      WaitFrame()
    else
    local flags = ActionFlags()
    local actionOpen = IsOpen(flags)
    if not actionOpen then
      mLetRun = false
    end
    local window = actionOpen and not mLetRun
    if ActiveStruggles() then
      window = window or not mStruggleFed
    else
      mStruggleFed = false
    end
    window = window or (GetTotalTime() > mAimGraceUntil and CoopSync_AimTarget() ~= nil)
    if GetTotalTime() < mQteGraceUntil then
      window = false
    end
    local ready = ApplicableQte(flags) ~= nil
    if mHeld then
      if ready or not window or GetTotalTime() - mHeldSince > kHoldMax then
        GuestHold(false)
      end
    elseif window and not ready then
      GuestHold(true)
    end
    GuestBars()
    if not mHeld then
      GuestQte()
      GuestCatchUp()
    end
    if window or ActiveStruggles() then
      mLastFightAt = GetTotalTime()
    end
    WaitFrame()
    end
  end
  GuestHold(false)
  GuestPace(1)
  mGuestWatch = nil
end

local function GuestOwnMovement()
  if not GuestPlaying() or not Navigating() then
    mLastOwnMove = nil
    return
  end
  local player = Player()
  if not player then
    return
  end
  local okD, direct = pcall(DirectControl_IsMoving)
  local walking = okD and direct == true
  local _, script = Where()
  local pos = AgentGetWorldPos(player)
  if walking then
    mLocalMoveAt = GetTotalTime()
    if not mLastOwnMove or VectorDistance(pos, mLastOwnMove) > kMoveEpsilon then
      mLastOwnMove = pos
      CoopLink_SendNow(string.format("G|M|%s|%.3f|%.3f|%.3f|%d", Escape(script or ""), pos.x, pos.y, pos.z,
        CoopSync_IsRunning(player) and 1 or 0))
    end
  elseif mLastOwnMove then
    mLastOwnMove = nil
    local f = AgentGetForwardVec(player)
    CoopLink_SendNow(string.format("G|F|%s|%.3f|%.3f|%.3f|%.3f|%.3f", Escape(script or ""), pos.x, pos.y, pos.z, f.x, f.z))
  end
end

local function GuestControls()
  if GuestPlaying() then
    if mInputMuted and Navigate_EnableInput then
      Navigate_EnableInput(true)
      mInputMuted = false
    end
    if not mActionMuted and Action_Activate then
      Action_Activate(false)
      mActionMuted = true
    end
    GuestOwnMovement()
    return
  end
  if not mInputMuted and Navigating() and Navigate_EnableInput then
    Navigate_EnableInput(false)
    mInputMuted = true
    Log("guest controls follow the host")
  end
  mLastOwnMove = nil
  if not mActionMuted and Action_Activate then
    Action_Activate(false)
    mActionMuted = true
  end
end

local function RestoreControls()
  if mInputMuted and Navigate_EnableInput then
    Navigate_EnableInput(true)
  end
  mInputMuted = false
  if mActionMuted and Action_Activate then
    Action_Activate(true)
  end
  mActionMuted = false
end

local function HostCheckpoint()
  local okF, file = pcall(AgentGetProperty, "logic_saveload", "SaveLoad - Checkpoint Dialog File")
  local okN, node = pcall(AgentGetProperty, "logic_saveload", "SaveLoad - Checkpoint Dialog Node")
  if okF and okN and type(file) == "string" and type(node) == "string" and file ~= "" and node ~= "" then
    return file, node
  end
  local okL, loaded = pcall(Game_GetLoaded)
  if gCoopLoadedCheckpoint and okL and loaded then
    return gCoopLoadedCheckpoint.file, gCoopLoadedCheckpoint.node
  end
  return "", ""
end

local function SendState(ep, script, fresh)
  local text, keys, kept = LogicSnapshot()
  mSnapshot = text or ""
  mSnap = mSnap + 1
  local parts = {}
  local i = 1
  while i <= #mSnapshot do
    table.insert(parts, string.sub(mSnapshot, i, i + kChunk - 1))
    i = i + kChunk
  end
  for n, part in ipairs(parts) do
    CoopLink_Send("L|" .. mSnap .. "|" .. n .. "|" .. #parts .. "|" .. part)
  end
  local cf, cn = HostCheckpoint()
  local okL, loaded = pcall(Game_GetLoaded)
  if fresh and not (okL and loaded) then
    cf, cn = "", ""
  end
  CoopLink_Send("S|" .. mSnap .. "|" .. Escape(ep or "") .. "|" .. Escape(script or "") .. "|" .. #parts ..
    "|" .. Escape(cf) .. "|" .. Escape(cn) .. "|" .. (fresh and "1" or "0"))
  Log("host at " .. tostring(ep) .. "/" .. tostring(script) .. ": sent state (" .. tostring(kept) .. " of " ..
    tostring(keys) .. " keys, " .. #parts .. " pieces" .. (cf ~= "" and (", checkpoint " .. cn) or "") .. ")")
end

local function HostGuestInput(data)
  if not CoopNet_GetGuestPlay() then
    return
  end
  local kind, rest = string.match(data, "^G|(%a)|(.*)$")
  if not kind or kind == "Q" or kind == "A" then
    return
  end
  local _, myScript = Where()
  if kind == "M" or kind == "F" then
    local script, x, y, z, a, b = string.match(rest, "^([^|]*)|([%-%d%.]+)|([%-%d%.]+)|([%-%d%.]+)|?([%-%d%.]*)|?([%-%d%.]*)$")
    if not script or Unescape(script) ~= myScript or not Navigating() then
      return
    end
    local okD, hostWalking = pcall(DirectControl_IsMoving)
    if okD and hostWalking then
      return
    end
    local player = Player()
    if not player then
      return
    end
    GuestRun(player, kind == "M" and a == "1")
    local target = Vector(tonumber(x), tonumber(y), tonumber(z))
    local distance = VectorDistance(AgentGetWorldPos(player), target)
    if distance > kTeleport then
      AgentSetWorldPos(player, target)
    elseif distance > 0.1 then
      PathAgentTo(player, target)
    end
    if kind == "F" and a ~= "" then
      local face = Vector(target.x + tonumber(a), target.y, target.z + tonumber(b))
      ThreadStart(function()
        local waited = 0
        while waited < 3 and PathAgentIsPathing(player) do
          Wait(0.1)
          waited = waited + 0.1
        end
        PathAgentFacePos(player, face)
      end)
    end
  elseif kind == "U" then
    local name = Unescape(rest)
    if Navigating() and AgentExists(name) then
      if not mVerbAt or GetTotalTime() - mVerbAt > 1 then
        mVerb = nil
      end
      mUseUntil = GetTotalTime() + 6
      Log("host does a guest's use: " .. name)
      ThreadStart(function()
        Game_UseAgent(AgentFind(name))
      end)
    end
  elseif kind == "V" then
    mVerb = tonumber(rest)
    mVerbAt = GetTotalTime()
  elseif kind == "A" then
    local name = Unescape(rest)
    local okCombat, combat = pcall(Reticle_IsCombatMode)
    if okCombat and combat == true and AgentExists(name) then
      Log("host does a guest's shot: " .. name)
      ThreadStart(function()
        Game_UseAgent(AgentFind(name))
      end)
    end
  elseif kind == "Q" then
    local amount = string.match(rest, "^Mash|([%d%.]+)$")
    if amount then
      local struggles = ActiveStruggles()
      if struggles then
        for _, agent in ipairs(struggles) do
          local props = agent.mProps
          props["Button Mash - Current Percentage"] = (tonumber(props["Button Mash - Current Percentage"]) or 0) + tonumber(amount)
          agent.bMashed = true
        end
        mGuestMashOwed = mGuestMashOwed + tonumber(amount)
      end
    else
      local name = kHandlerFor[rest]
      local fn = name and rawget(_G, name)
      if fn and ActionFlags()[rest] then
        Log("host does a guest's quick time event: " .. rest)
        pcall(fn, {})
      end
    end
  end
end

local function HostTick()
  local ep, script = Where()
  local where = script and (tostring(ep) .. "|" .. script) or nil
  for _, msg in ipairs(CoopLink_Receive()) do
    if msg.data == "W" and where then
      HostSendSave()
      SendState(ep, script)
      mLastWhere = where
    elseif string.sub(msg.data, 1, 2) == "G|" then
      HostGuestInput(msg.data)
    elseif string.sub(msg.data, 1, 2) == "Y|" then
      HostGuestReady(msg.from, Unescape(string.sub(msg.data, 3)))
    elseif string.sub(msg.data, 1, 3) == "OK|" then
      HostGuestOk(msg.from, Unescape(string.sub(msg.data, 4)))
    end
  end
  HostStartTick(script)
  if GetTotalTime() - mLastOption > 2 then
    mLastOption = GetTotalTime()
    Queue("O|" .. (CoopNet_GetGuestPlay() and "1" or "0"))
  end
  if where and where ~= mLastWhere then
    Wait(0.5)
    ep, script = Where()
    if script then
      local justLoaded = gCoopSceneLoaded
      gCoopSceneLoaded = false
      if justLoaded then
        HostStartWait(script)
      end
      local okL, loaded = pcall(Game_GetLoaded)
      if okL and loaded and justLoaded and mStartWait then
        HostSendSave()
      end
      SendState(ep, script, true)
      mLastWhere = tostring(ep) .. "|" .. script
      mLastRepeat = GetTotalTime()
    end
  elseif where and GetTotalTime() - mLastRepeat > kRepeat then
    mLastRepeat = GetTotalTime()
    CoopLink_Send("P|" .. mSnap .. "|" .. Escape(ep or "") .. "|" .. Escape(script))
  end
  HostMovement(script)
  FlushOutbox()
end

local function Follow(ep, script, text, cf, cn, fresh)
  local myEp, myScript = Where()
  cf, cn = cf or "", cn or ""
  local key = cf .. ":" .. cn
  if myEp == ep and myScript == script then
    if not (fresh and cf ~= "" and key ~= mGuestCheckpoint) or not AgentExists("logic_game") then
      return
    end
    mGuestCheckpoint = key
    ApplyLogic(text)
    CoopSync_PrepareCheckpoint(script, cf, cn)
    Log("guest goes to the host's checkpoint " .. cn)
    Game_EndScene(script)
    return
  end
  mGuestCheckpoint = key
  if myEp == ep and myScript and AgentExists("logic_game") then
    local changed = ApplyLogic(text)
    CoopSync_PrepareCheckpoint(script, cf, cn)
    Log("guest follows to " .. script .. " (" .. tostring(changed) .. " values changed" ..
      (cf ~= "" and (", checkpoint " .. cn) or "") .. ")")
    Game_EndScene(script)
  else
    Log("guest switches to episode " .. tostring(ep) .. ", scene " .. script ..
      (cf ~= "" and (", checkpoint " .. cn) or ""))
    WritePref(text or "")
    CoopSync_WriteCheckpointPref(cf ~= "" and (script .. "\t" .. cf .. "\t" .. cn) or "")
    SubProject_Switch(ep, script .. ".lua")
  end
end

local function GuestTick()
  for _, msg in ipairs(CoopLink_Receive()) do
    local data = msg.data
    local kind = string.sub(data, 1, 1)
    if kind == "L" then
      local snap, i, n, part = string.match(data, "^L|(%d+)|(%d+)|(%d+)|(.*)$")
      if snap then
        local entry = mChunks[snap] or { n = tonumber(n), parts = {} }
        entry.parts[tonumber(i)] = part
        mChunks[snap] = entry
      end
    elseif kind == "S" then
      local snap, ep, script, n, cf, cn, fresh = string.match(data, "^S|(%d+)|([^|]*)|([^|]*)|(%d+)|?([^|]*)|?([^|]*)|?([01]?)$")
      if snap and script ~= "" then
        local entry = mChunks[snap] or { n = 0, parts = {} }
        local complete = true
        for i = 1, tonumber(n) do
          if not entry.parts[i] then
            complete = false
          end
        end
        mChunks = {}
        if LoadHostSave() then
          return
        end
        if complete then
          Follow(Unescape(ep), Unescape(script), table.concat(entry.parts), Unescape(cf or ""), Unescape(cn or ""),
            fresh == "1")
        else
          Log("state incomplete, asking again")
          CoopLink_Send("W")
        end
      end
    elseif kind == "B" then
      for line in string.gmatch(string.sub(data, 3), "[^\n]+") do
        GuestLive(line)
      end
    elseif string.sub(data, 1, 3) == "SV|" then
      gCoopHostSaveName = Unescape(string.sub(data, 4))
    elseif string.sub(data, 1, 3) == "RQ|" then
      GuestReadyAsked(string.sub(data, 4))
    elseif string.sub(data, 1, 3) == "GO|" then
      if mStartWait and Unescape(string.sub(data, 4)) == mStartWait.script then
        StartWaitEnd("the host says go")
      end
    elseif data == "R" then
      Log("the host replays from the checkpoint")
      mPendingQte = {}
      GuestHold(false)
    elseif kind == "P" then
      local _, ep, script = string.match(data, "^P|(%d+)|([^|]*)|([^|]*)$")
      if script and script ~= "" then
        local myEp, myScript = Where()
        if (myEp ~= Unescape(ep) or myScript ~= Unescape(script)) and GetTotalTime() - mAsked > 5 then
          mAsked = GetTotalTime()
          CoopLink_Send("W")
        end
      end
    end
  end
  local _, myScript = Where()
  if gCoopSceneLoaded and myScript then
    gCoopSceneLoaded = false
    GuestStartWait(myScript)
  end
  GuestStartTick()
  if not (mGuestWatch and ThreadIsRunning(mGuestWatch)) then
    mGuestWatch = ThreadStart(GuestWatch)
  end
  GuestControls()
end

function CoopSync_Ensure()
  if gCoopSyncThread and ThreadIsRunning(gCoopSyncThread) then
    return
  end
  local session = CoopNet_GetSession()
  if not session or not CoopLink_Hello() then
    if session and not mNoLinkNoted then
      mNoLinkNoted = true
      CoopLink_LogNow("sync: no answer from the component yet")
    end
    return
  end
  CoopLink_LogNow("sync: loop starts as " .. tostring(session.role))
  gCoopSyncThread = ThreadStart(function()
    pcall(ApplyPending)
    if mAppliedNote then
      Log("applied the host's state after switching episode (" .. tostring(mAppliedNote) .. " values changed)")
      if gCoopAppliedCheckpoint then
        Log("entered at the host's checkpoint " .. gCoopAppliedCheckpoint)
        gCoopAppliedCheckpoint = nil
      end
      mAppliedNote = nil
    end
    while true do
      local current = CoopNet_GetSession()
      if not current or not CoopLink_Info() then
        break
      end
      local ok, err = pcall(InstallLive)
      if current.role == "host" and not (mWatchThread and ThreadIsRunning(mWatchThread)) then
        mWatchThread = ThreadStart(HostWatch)
      end
      if ok then
        if current.role == "host" then
          ok, err = pcall(HostTick)
        elseif current.role == "guest" then
          ok, err = pcall(GuestTick)
        end
      end
      pcall(GuestPaceCheck)
      if not ok then
        err = tostring(err)
        if err ~= mLastError then
          mLastError = err
          Log("error: " .. err)
        end
      end
      FlushLogs()
      Wait(kPoll)
    end
    RestoreControls()
    gCoopSyncThread = nil
  end)
end
