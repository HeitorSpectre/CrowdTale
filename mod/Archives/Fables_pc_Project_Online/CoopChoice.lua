require("CoopDialog.lua")

local kPollInterval = 0.75
local kVoteWindow = 20
local kGuestWait = 90
local kMaxFailures = 5

local kChoices = {
  {
    init = "FabletownWoodlands_ChoiceInit",
    options = { "FabletownWoodlands_ConfirmMovingChoiceToad", "FabletownWoodlands_ConfirmMovingChoiceFaith" },
    labels = {
      { "ui_hud_choice_mouse_button_left", "ui_hud_choice_controller_ring_left", "ui_choice_left" },
      { "ui_hud_choice_mouse_button_right", "ui_hud_choice_controller_ring_right", "ui_choice_right" }
    },
    fallback = { "Toad", "Lawrence" }
  }
}

local mActive
local mOpeningSince

local function LabelAgent(def, i)
  local candidates = def.labels[i]
  local first = Input_UseCursor and Input_UseCursor() and 1 or 2
  for _, k in ipairs({ first, 3 - first, 3 }) do
    local name = candidates[k]
    if name and AgentExists(name) and not AgentIsHidden(name) then
      return name
    end
  end
  for _, name in ipairs(candidates) do
    if AgentExists(name) then
      return name
    end
  end
  return nil
end
local mWrappers = {}

local kSideColors = { Color(0.24, 0.78, 0.91, 1), Color(0.95, 0.79, 0.3, 1) }
local kGold = Color(1, 0.82, 0.35, 1)
local kIconProp = "ui_hud_choice_arrow_left.prop"
local kIconTexture = "ui_coop_voter.d3dtx"
local kIconSize = 0.5
local kPixelFallback = 0.007
local kTallyCopy = {
  "Text Font",
  "Text Scale",
  "Text Render Layer",
  "Text Render After Post-Effects",
  "Text Depth Test",
  "Text Camera Facing",
  "Text Alignment Vertical",
  "Text Shadow Color",
  "Text Shadow Height"
}
local mTally = {}

local function TallyFor(i, label)
  local t = mTally[i]
  if t and t.label == label and AgentExists(t.text) and AgentExists(t.icon) then
    return t
  end
  local scene = AgentGetScene(label)
  local textName = "coop_choice_tally_text" .. i
  local iconName = "coop_choice_tally_icon" .. i
  local text = AgentExists(textName) and AgentFind(textName) or AgentCreate(textName, "ui_text.prop", Vector(0, 0, 0), nil, scene)
  local icon = AgentExists(iconName) and AgentFind(iconName) or AgentCreate(iconName, kIconProp, Vector(0, 0, 0), nil, scene)
  if not text or not icon then
    return nil
  end
  for _, key in ipairs(kTallyCopy) do
    local value = AgentGetProperty(label, key)
    if value ~= nil then
      AgentSetProperty(text, key, value)
    end
  end
  AgentSetProperty(text, "Text Alignment Horizontal", "Left Justified")
  AgentSetProperty(text, "Text String", "")
  AgentSetSelectable(text, false)
  AgentSetSelectable(icon, false)
  ShaderOverrideAllTextures(icon, kIconTexture)
  pcall(AgentSetProperty, icon, "Render Depth Test", false)
  local okL, layer = pcall(AgentGetProperty, label, "Text Render Layer")
  pcall(AgentSetProperty, icon, "Render Layer", (okL and type(layer) == "number" and layer or 0) + 10)
  t = { label = label, text = text, icon = icon }
  mTally[i] = t
  return t
end

local function Pixel(agent)
  local ok, scale = pcall(AgentGetPixelScale, agent)
  if ok and type(scale) == "number" and scale > 0.0001 and scale < 0.1 then
    return scale
  end
  return kPixelFallback
end

local function TextSpan(label, text)
  local width = TextGetWidth(label, text) or 0
  local align = tostring(AgentGetProperty(label, "Text Alignment Horizontal") or "")
  if align == "2" or string.find(align, "Center") then
    return -width / 2, width / 2
  elseif align == "3" or string.find(align, "Right") then
    return -width, 0
  end
  return 0, width
end

local function HideTally(i)
  local t = mTally[i]
  if t and AgentExists(t.text) and AgentExists(t.icon) then
    AgentHide(t.text, true)
    AgentHide(t.icon, true)
  end
end

local function ShowTally(i, label, text, n, color)
  local t = TallyFor(i, label)
  if not t then
    return
  end
  if n < 1 then
    HideTally(i)
    return
  end
  local number = tostring(n)
  AgentSetProperty(t.text, "Text String", number)
  AgentSetProperty(t.text, "Text Color", color)
  AgentSetProperty(t.icon, "Render Diffuse Color", color)
  local px = Pixel(label)
  local lineH = (TextGetLineHeight and TextGetLineHeight(label)) or 40
  local numberW = TextGetWidth(t.text, number) or lineH * 0.5
  local iconW = lineH * 0.6
  local tallyW = numberW + lineH * 0.15 + iconW
  local right = AgentGetRightVec(label, true)
  if right.x < 0 then
    right = VectorScale(right, -1)
  end
  local origin = AgentGetWorldPos(label)
  local first, last = TextSpan(label, text)
  local start
  if i == 1 then
    start = last + lineH * 0.3
  else
    start = first - lineH * 0.3 - tallyW
  end
  AgentSetWorldPos(t.text, VectorAdd(origin, VectorScale(right, start * px)))
  AgentSetWorldPos(t.icon, VectorAdd(origin, VectorScale(right, (start + numberW + lineH * 0.15 + iconW) * px)))
  AgentSetProperty(t.icon, "Render Global Scale", kIconSize)
  AgentHide(t.text, false)
  AgentHide(t.icon, false)
end

local function Refresh(active, poll)
  local best, bestCount = nil, 0
  if poll then
    for index, n in pairs(poll.votes) do
      if n > bestCount then
        best, bestCount = index, n
      elseif n == bestCount then
        best = nil
      end
    end
  end
  for i, candidates in ipairs(active.def.labels) do
    local color = kSideColors[i]
    for _, name in ipairs(candidates) do
      if AgentExists(name) then
        AgentSetProperty(name, "Text Color", color)
      end
    end
    local name = LabelAgent(active.def, i)
    if name then
      local n = poll and poll.votes[i] or 0
      local ok, err = pcall(ShowTally, i, AgentFind(name), active.texts and active.texts[i] or "", n, i == best and kGold or color)
      if not ok and not active.tallyError then
        active.tallyError = true
        CoopNet_Note("choice tally error: " .. tostring(err))
      end
    end
  end
end

local function ClearLook(active)
  for i, candidates in ipairs(active.def.labels) do
    HideTally(i)
    for _, name in ipairs(candidates) do
      if AgentExists(name) then
        PropertyRemove(AgentGetProperties(name), "Text Color")
      end
    end
  end
end

local function Wait(seconds)
  local accum = 0
  while accum < seconds do
    Yield()
    accum = accum + GetFrameTime()
  end
  return accum
end

local kPlaceholder = "Dialog Choice"

local function LabelText(def, i)
  local agent = LabelAgent(def, i)
  local text
  if agent then
    local okF, file = pcall(AgentGetProperty, agent, "Text Dialog 2.0 File")
    local okN, node = pcall(AgentGetProperty, agent, "Text Dialog 2.0 Node Name")
    if Dialog_GetText and okF and okN and file and node and tostring(node) ~= "" then
      for _, f in ipairs({ file, ResourceGetName and ResourceGetName(file) }) do
        local okT, value = pcall(Dialog_GetText, f, tostring(node))
        if okT and type(value) == "string" and value ~= "" and value ~= kPlaceholder then
          text = value
          break
        end
      end
    end
    if not text then
      local ok, value = pcall(AgentGetProperty, agent, "Text String")
      if ok and type(value) == "string" and value ~= "" and value ~= kPlaceholder then
        text = value
      end
    end
  end
  text = text and string.gsub(text, "%^[^%^]*%^", "") or ""
  text = StringTrim and StringTrim(text) or text
  if text == "" then
    text = def.fallback[i]
  end
  return text
end

local function Announce(active, poll)
  local seen = active.announced or 0
  local me = CoopNet_GetPlayerName()
  for i = seen + 1, #poll.voters do
    local voter = poll.voters[i]
    if voter.name ~= me then
      CoopDialog_Notify(CoopNet_Text("coop_hud_voted", { name = CoopNet_DisplayName(voter.name) }))
    end
  end
  active.announced = #poll.voters
end

local function Apply(active, index)
  if mActive ~= active then
    return
  end
  mActive = nil
  ClearLook(active)
  if active.seq and active.role == "guest" then
    local seq = active.seq
    ThreadStart(function()
      CoopDialog_Applied(seq)
    end)
  end
  local original = active.originals[index]
  if original then
    original()
  end
end

local function Abandon(active)
  if mActive ~= active then
    return
  end
  if active.myVote then
    Apply(active, active.myVote)
    return
  end
  mActive = nil
  ClearLook(active)
end

local function RunHost(active)
  local elapsed = 0
  local failures = 0
  while mActive == active do
    local paused = Game_IsPaused() and true or false
    if paused ~= (active.paused or false) then
      active.paused = paused
      CoopDialog_Pause(paused)
    end
    local role, status = CoopDialog_Status()
    if mActive ~= active then
      return
    end
    local poll = CoopDialog_ReadPoll(status)
    if role ~= "host" or not poll or poll.seq ~= active.seq then
      failures = failures + 1
      if failures >= kMaxFailures then
        Abandon(active)
        return
      end
    else
      failures = 0
      Announce(active, poll)
      Refresh(active, poll)
      if not paused then
        local players = tonumber(status.players) or 1
        local expired = not active.unlimited and elapsed >= kVoteWindow + active.extra
        if 0 < poll.total and (poll.total >= players or expired) then
          local result = CoopDialog_Resolve(active.seq)
          if mActive ~= active then
            return
          end
          if result then
            Apply(active, result)
          else
            Abandon(active)
          end
          return
        end
      end
    end
    local waited = Wait(kPollInterval)
    if not paused then
      elapsed = elapsed + waited
    end
  end
end

local function RunGuest(active)
  local waited = 0
  local failures = 0
  while mActive == active do
    local role, status = CoopDialog_Status()
    if mActive ~= active then
      return
    end
    if role ~= "guest" then
      failures = failures + 1
      if failures >= kMaxFailures or not CoopDialog_LocalRole() then
        Abandon(active)
        return
      end
    else
      failures = 0
      local applied = tonumber(status.applied) or 0
      local poll = CoopDialog_ReadPoll(status)
      local recent = CoopDialog_ReadRecent(status)
      if not active.seq then
        local candidate
        for _, r in ipairs(recent) do
          if r.seq > applied and r.count == active.count and (not candidate or r.seq < candidate) then
            candidate = r.seq
          end
        end
        if poll and poll.seq > applied and poll.count == active.count and (not candidate or poll.seq < candidate) then
          candidate = poll.seq
        end
        if candidate then
          active.seq = candidate
          if poll and poll.seq == candidate and active.myVote and not poll.result and poll.mine ~= active.myVote then
            CoopDialog_Vote(active.seq, active.myVote)
          end
        end
      end
      local done
      if active.seq then
        for _, r in ipairs(recent) do
          if r.seq == active.seq then
            done = r.result
          end
        end
      end
      if done then
        Apply(active, done)
        return
      elseif active.seq and poll and poll.seq == active.seq then
        Announce(active, poll)
        Refresh(active, poll)
        if poll.result then
          Apply(active, poll.result)
          return
        end
      elseif waited >= kGuestWait * (active.seq and 3 or 1) then
        Abandon(active)
        return
      end
    end
    waited = waited + Wait(kPollInterval)
  end
end

local function Begin(def, originals)
  mActive = nil
  local role = CoopDialog_LocalRole()
  if not role then
    return
  end
  local active = {
    def = def,
    role = role,
    count = #def.options,
    originals = originals,
    extra = 0
  }
  if role == "host" then
    active.extra = CoopNet_GetVoteExtra()
  end
  active.unlimited = active.extra == CoopNet_kVoteUnlimited
  mActive = active
  CoopNet_EnsureHeartbeat()
  ThreadStart(function()
    Wait(0.5)
    local texts = {}
    for i = 1, active.count do
      texts[i] = LabelText(def, i)
    end
    active.texts = texts
    Refresh(active, nil)
    if active.role == "host" then
      local secs
      if not active.unlimited then
        secs = kVoteWindow + active.extra
      end
      local seq = CoopDialog_OpenPoll(active.count, texts, secs)
      if mActive ~= active then
        return
      end
      if not seq then
        Abandon(active)
        return
      end
      active.seq = seq
      if active.myVote then
        CoopDialog_Vote(seq, active.myVote)
      end
      RunHost(active)
    else
      RunGuest(active)
    end
  end)
end

local function Choose(def, index)
  local active = mActive
  if not active or active.def ~= def then
    return false
  end
  if active.myVote == index then
    return true
  end
  active.myVote = index
  local name = CoopNet_GetPlayerName()
  if name then
    CoopDialog_Notify(CoopNet_Text("coop_hud_voted", { name = CoopNet_DisplayName(name) }))
  end
  local seq = active.seq
  if seq then
    ThreadStart(function()
      CoopDialog_Vote(seq, index)
    end)
  end
  return true
end

local function Install(def)
  local init = _G[def.init]
  if type(init) ~= "function" or init == mWrappers[def.init] then
    return
  end
  local originals = {}
  for i, name in ipairs(def.options) do
    local original = _G[name]
    if type(original) ~= "function" then
      return
    end
    originals[i] = original
  end
  for i, name in ipairs(def.options) do
    local original = originals[i]
    local wrapper = function(...)
      if Choose(def, i) then
        return
      end
      return original(...)
    end
    mWrappers[name] = wrapper
    _G[name] = wrapper
  end
  local initWrapper = function(...)
    mOpeningSince = GetTotalTime()
    init(...)
    mOpeningSince = nil
    Begin(def, originals)
  end
  mWrappers[def.init] = initWrapper
  _G[def.init] = initWrapper
end

function CoopChoice_InstallHooks()
  for _, def in ipairs(kChoices) do
    Install(def)
  end
end

function CoopChoice_Busy()
  return mActive ~= nil or mOpeningSince ~= nil and GetTotalTime() - mOpeningSince < 30
end
