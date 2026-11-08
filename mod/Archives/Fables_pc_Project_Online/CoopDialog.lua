require("CoopNet.lua")

local function ToInt(value)
  local n = tonumber(value)
  if not n then
    return nil
  end
  return math.floor(n)
end

local function OkReply(reply)
  if reply and reply.ok == true then
    return reply
  end
  return nil
end

function CoopDialog_LocalRole()
  local session = CoopNet_GetSession()
  if session and (session.role == "host" or session.role == "guest") then
    return session.role
  end
  return nil
end

function CoopDialog_Status()
  local status = OkReply(CoopNet_Room("/v1/state"))
  if not status then
    return nil
  end
  if status.role == "host" or status.role == "guest" then
    return status.role, status
  end
  return nil, status
end

function CoopDialog_OpenPoll(count, texts, secs)
  local extra = "count=" .. tostring(count)
  if secs then
    extra = extra .. "&secs=" .. tostring(math.max(1, math.min(600, math.ceil(secs))))
  end
  for i = 1, count do
    local text = texts and texts[i] or ""
    extra = extra .. "&t" .. tostring(i - 1) .. "=" .. CoopNet_Encode(string.sub(text, 1, 160))
  end
  local reply = OkReply(CoopNet_Room("/v1/poll", extra))
  return reply and ToInt(reply.seq)
end

function CoopDialog_Vote(seq, index)
  return OkReply(CoopNet_Room("/v1/vote", "seq=" .. tostring(seq) .. "&index=" .. tostring(index - 1))) ~= nil
end

function CoopDialog_Applied(seq)
  return OkReply(CoopNet_Room("/v1/applied", "seq=" .. tostring(seq))) ~= nil
end

function CoopDialog_Pause(paused)
  return OkReply(CoopNet_Room("/v1/pause", "paused=" .. (paused and "1" or "0"))) ~= nil
end

function CoopDialog_Resolve(seq, fallback)
  local extra = "seq=" .. tostring(seq)
  if fallback then
    extra = extra .. "&fallback=" .. tostring(fallback - 1)
  end
  local reply = OkReply(CoopNet_Room("/v1/resolve", extra))
  local result = reply and ToInt(reply.result)
  return result and result + 1
end

function CoopDialog_ReadRecent(status)
  local list = {}
  local recent = status and status.recent
  if type(recent) ~= "table" then
    return list
  end
  local i = recent[0] ~= nil and 0 or 1
  while recent[i] ~= nil do
    local r = recent[i]
    if type(r) == "table" then
      local seq, count, result = ToInt(r.seq), ToInt(r.count), ToInt(r.result)
      if seq and count and result and result >= 0 and result < count then
        table.insert(list, { seq = seq, count = count, result = result + 1 })
      end
    end
    i = i + 1
  end
  return list
end

function CoopDialog_ReadPoll(status)
  local poll = status and status.poll
  if type(poll) ~= "table" then
    return nil
  end
  local seq, count = ToInt(poll.seq), ToInt(poll.count)
  if not seq or not count then
    return nil
  end
  local info = { seq = seq, count = count, votes = {}, total = 0 }
  if type(poll.votes) == "table" then
    local base = poll.votes[0] ~= nil and -1 or 0
    for i = 1, count do
      local n = ToInt(poll.votes[i + base]) or 0
      info.votes[i] = n
      info.total = info.total + n
    end
  end
  local result = ToInt(poll.result)
  if result and result >= 0 and result < count then
    info.result = result + 1
  end
  info.voters = {}
  if type(poll.voters) == "table" then
    local first = poll.voters[0] ~= nil and 0 or 1
    local i = first
    while poll.voters[i] ~= nil do
      local v = poll.voters[i]
      if type(v) == "table" then
        table.insert(info.voters, { name = tostring(v.name or "Player"), phone = v.kind == "phone" })
      end
      i = i + 1
    end
  end
  info.remaining = tonumber(poll.remaining)
  local mine = ToInt(poll.mine)
  if mine and mine >= 0 and mine < count then
    info.mine = mine + 1
  end
  return info
end

local kNotifyText = "ui_hud_notification_text"
local kNotifyIcon = "ui_hud_notification_message"
local kNotifyColor = Color(0.55, 0.85, 1, 1)
local mNotifyThread
local mNotifyQueue = {}

local function NotifyAvailable()
  if not AgentExists(kNotifyText) or not AgentExists(kNotifyIcon) then
    return false
  end
  if Notification_IsShowing and Notification_IsShowing() and not mNotifyThread then
    return false
  end
  return true
end

local function ShowOne(text, duration)
  PropertyRemove(AgentGetProperties(kNotifyText), "Text Dialog 2.0 File")
  PropertyRemove(AgentGetProperties(kNotifyText), "Text Dialog 2.0 Node Name")
  ShaderOverrideAllTextures(kNotifyIcon, "ui_hud_notifications_tutorial.d3dtx")
  AgentSetProperty(kNotifyIcon, "Render Diffuse Color", kNotifyColor)
  AgentSetProperty(kNotifyText, "Text Color", kNotifyColor)
  AgentSetProperty(kNotifyText, "Text String", text)
  ChorePlayAndWait("ui_hud_notification_show.chore")
  Sleep(duration)
  if Notification_IsShowing and Notification_IsShowing() then
    return
  end
  ChorePlayAndWait("ui_hud_notification_hide.chore")
  AgentSetProperty(kNotifyText, "Text String", "")
  PropertyRemove(AgentGetProperties(kNotifyText), "Text Color")
  PropertyRemove(AgentGetProperties(kNotifyIcon), "Render Diffuse Color")
  ShaderRestoreAllTextures(kNotifyIcon)
end

function CoopDialog_Notify(text, duration)
  if not text or text == "" or not NotifyAvailable() then
    return
  end
  if #mNotifyQueue >= 3 then
    table.remove(mNotifyQueue, 1)
  end
  table.insert(mNotifyQueue, { text = text, duration = duration or 2.5 })
  if mNotifyThread then
    return
  end
  mNotifyThread = ThreadStart(function()
    while 0 < #mNotifyQueue do
      local item = table.remove(mNotifyQueue, 1)
      if not (Notification_IsShowing and Notification_IsShowing()) then
        ShowOne(item.text, item.duration)
      end
    end
    mNotifyThread = nil
  end)
end

local kPlayersColors = {
  Color(0.36, 0.80, 0.95, 1),
  Color(0.98, 0.78, 0.30, 1),
  Color(0.55, 0.90, 0.45, 1),
  Color(0.95, 0.45, 0.55, 1),
  Color(0.70, 0.55, 0.98, 1),
  Color(1.00, 0.60, 0.30, 1),
  Color(0.40, 0.95, 0.80, 1),
  Color(0.90, 0.90, 0.90, 1)
}
local kPlayersAlpha = 0.6
local kPlayersMax = 8
local kPlayersRight = 0.972
local kPlayersTop = 0.045
local kPlayersRow = 0.042
local kPlayersTextGap = 0.022
local kPlayersTextScale = 0.75
local kPlayersIconScale = 1.1
local kPlayersIconProp = "ui_hud_notifications_saveicon.prop"
local kPlayersIconOriginal = "ui_hud_notifications_saveIcon.d3dtx"
local kPlayersIconTexture = "ui_coop_voter.d3dtx"
local kPlayersCopy = {
  "Text Font",
  "Text Render Layer",
  "Text Render After Post-Effects",
  "Text Depth Test",
  "Text Camera Facing",
  "Text Shadow Color",
  "Text Shadow Height"
}
local mRows = {}
local mShown = {}
local mColorOf = {}
local mPlayersThread

local function Faded(c)
  return Color(c.r, c.g, c.b, kPlayersAlpha)
end

local function RowAgents(slot)
  local row = mRows[slot]
  if row and AgentExists(row.text) and AgentExists(row.icon) then
    return row
  end
  if not AgentExists(kNotifyText) then
    return nil
  end
  local scene = AgentGetScene(kNotifyText)
  local textName = "coop_players_text" .. slot
  local iconName = "coop_players_icon" .. slot
  local text = AgentExists(textName) and AgentFind(textName) or AgentCreate(textName, "ui_text.prop", Vector(0, 0, 0), nil, scene)
  local icon = AgentExists(iconName) and AgentFind(iconName) or AgentCreate(iconName, kPlayersIconProp, Vector(0, 0, 0), nil, scene)
  if not text or not icon then
    return nil
  end
  for _, key in ipairs(kPlayersCopy) do
    local ok, value = pcall(AgentGetProperty, kNotifyText, key)
    if ok and value ~= nil then
      pcall(AgentSetProperty, text, key, value)
    end
  end
  local okS, scale = pcall(AgentGetProperty, kNotifyText, "Text Scale")
  pcall(AgentSetProperty, text, "Text Scale", (okS and type(scale) == "number" and scale or 1) * kPlayersTextScale)
  pcall(AgentSetProperty, text, "Text Alignment Horizontal", "Right Justified")
  pcall(AgentSetProperty, text, "Text Alignment Vertical", "Middle")
  PropertyRemove(AgentGetProperties(text), "Text Dialog 2.0 File")
  PropertyRemove(AgentGetProperties(text), "Text Dialog 2.0 Node Name")
  AgentSetProperty(text, "Text String", "")
  AgentSetSelectable(text, false)
  AgentSetSelectable(icon, false)
  pcall(ShaderOverrideTexture, icon, kPlayersIconOriginal, kPlayersIconTexture)
  pcall(AgentSetProperty, icon, "Render Global Scale", kPlayersIconScale)
  AgentHide(text, true)
  AgentHide(icon, true)
  row = { text = text, icon = icon }
  mRows[slot] = row
  return row
end

local function PlaceRow(row, y)
  pcall(AgentSetWorldPosFromLogicalScreenPos, row.icon, Vector(kPlayersRight, y, 0))
  pcall(AgentSetWorldPosFromLogicalScreenPos, row.text, Vector(kPlayersRight - kPlayersTextGap, y, 0))
end

local function NextColor()
  local used = {}
  for _, index in pairs(mColorOf) do
    used[index] = true
  end
  for i = 1, #kPlayersColors do
    if not used[i] then
      return i
    end
  end
  return 1
end

local function Animate()
  if mPlayersThread then
    return
  end
  mPlayersThread = ThreadStart(function()
    local moving = true
    while moving do
      moving = false
      local step = math.min(1, (GetFrameTime() or 0.016) * 10)
      for _, entry in pairs(mShown) do
        local row = mRows[entry.slot]
        if row and AgentExists(row.text) and AgentExists(row.icon) then
          local dy = entry.target - entry.y
          if math.abs(dy) > 0.0005 then
            entry.y = entry.y + dy * step
            moving = true
          else
            entry.y = entry.target
          end
          PlaceRow(row, entry.y)
        end
      end
      if moving then
        WaitForNextFrame()
      end
    end
    mPlayersThread = nil
  end)
end

function CoopDialog_ShowPlayers(names)
  local list = {}
  for _, p in ipairs(names or {}) do
    if p.id and #list < kPlayersMax then
      table.insert(list, p)
    end
  end
  local before = mShown
  mShown = {}
  for slot = 1, kPlayersMax do
    local row = mRows[slot]
    if row and AgentExists(row.text) and AgentExists(row.icon) and not list[slot] then
      AgentHide(row.text, true)
      AgentHide(row.icon, true)
    end
  end
  local present = {}
  for slot, p in ipairs(list) do
    local row = RowAgents(slot)
    if not row then
      break
    end
    present[p.id] = true
    if not mColorOf[p.id] then
      mColorOf[p.id] = NextColor()
    end
    local color = Faded(kPlayersColors[mColorOf[p.id]])
    local label = CoopNet_DisplayName and CoopNet_DisplayName(p.name) or p.name
    AgentSetProperty(row.text, "Text String", label)
    AgentSetProperty(row.text, "Text Color", color)
    pcall(AgentSetProperty, row.icon, "Render Diffuse Color", color)
    pcall(AgentSetProperty, row.icon, "Render Constant Alpha", kPlayersAlpha)
    local target = kPlayersTop + (slot - 1) * kPlayersRow
    local old = before[p.id]
    local y = old and old.y or target
    mShown[p.id] = { slot = slot, y = y, target = target }
    PlaceRow(row, y)
    AgentHide(row.text, false)
    AgentHide(row.icon, false)
  end
  for id in pairs(mColorOf) do
    if not present[id] then
      mColorOf[id] = nil
    end
  end
  Animate()
end
