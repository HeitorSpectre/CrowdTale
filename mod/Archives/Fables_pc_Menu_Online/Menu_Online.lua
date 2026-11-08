require("CoopNet.lua")

local kRefreshSeconds = 2
local kPlayerRows = 4
local mButtonMain, mButtonSecond, mButtonVoteTime, mButtonGuestPlay
local mPlayerRows = {}
local mGapRow
local mLobbyGeneration = 0
local mPlayers
local mNames = {}

local T = CoopNet_Text

local function SetButtonText(button, value)
  if not button then
    return
  end
  AgentSetProperty(button, "Text Dialog 2.0 File", "")
  AgentSetProperty(button, "Text Dialog 2.0 Node Name", "")
  AgentSetProperty(button, "Text String", value)
end

local function SetButtonNode(button, node)
  SetButtonText(button, T(node))
end

local function PlayerLabel(p)
  local label = string.upper(p.name)
  if p.host then
    label = label .. "  " .. T("coop_tag_host")
  elseif p.phone then
    label = label .. "  " .. T("coop_tag_phone")
  elseif p.web then
    label = label .. "  " .. T("coop_tag_web")
  end
  return label
end

local function VoteTimeLabel()
  local extra = CoopNet_GetVoteExtra()
  local value
  if extra == 0 then
    value = T("coop_vote_time_game")
  elseif extra == CoopNet_kVoteUnlimited then
    value = T("coop_vote_time_unlimited")
  else
    value = T("coop_vote_time_extra", { n = extra })
  end
  return T("coop_vote_time") .. " " .. value
end

local function GuestPlayLabel()
  return T("coop_guest_play") .. " " .. T(CoopNet_GetGuestPlay() and "coop_on" or "coop_off")
end

local function IsHost()
  local session = CoopNet_GetSession()
  return session ~= nil and session.role == "host"
end

local function RefreshLabels()
  SetButtonText(mButtonVoteTime, VoteTimeLabel())
  SetButtonText(mButtonGuestPlay, GuestPlayLabel())
  local session = CoopNet_GetSession()
  if not session then
    SetButtonNode(mButtonMain, "coop_create")
    SetButtonNode(mButtonSecond, "coop_join")
    return
  end
  local label = T("coop_session_label", { code = CoopNet_FormatCode(session.code) })
  if mPlayers then
    label = label .. "  " .. T(mPlayers == 1 and "coop_players_one" or "coop_players_many", { n = mPlayers })
  end
  SetButtonText(mButtonMain, label)
  SetButtonNode(mButtonSecond, "coop_leave")
  for i = 1, kPlayerRows do
    local p = mNames[i]
    local text = ""
    if p then
      text = PlayerLabel(p)
      if i == kPlayerRows and #mNames > kPlayerRows then
        text = T("coop_more", { n = #mNames - kPlayerRows + 1 })
      end
    elseif i == 1 then
      text = T("coop_waiting_players")
    end
    SetButtonText(mPlayerRows[i], text)
  end
end

local function IsKickableRow(i)
  local session = CoopNet_GetSession()
  local p = mNames[i]
  if not (session and session.role == "host" and p and not p.host) then
    return false
  end
  return not (i == kPlayerRows and #mNames > kPlayerRows)
end

local function SetRowsSelectable()
  for i, row in ipairs(mPlayerRows) do
    if row then
      AgentSetSelectable(row, IsKickableRow(i))
    end
  end
  if mGapRow then
    AgentSetSelectable(mGapRow, false)
  end
end

local function ShowTitle()
  if not AgentExists("ui_title") then
    return
  end
  SetButtonText("ui_title", T("coop_title"))
  AgentHide("ui_title", false)
end

local function HideTitle()
  if AgentExists("ui_title") then
    AgentHide("ui_title", true)
  end
end

local function SettleAfterPopup()
  local _, isMain = coroutine.running()
  if isMain then
    return
  end
  local settle, frames = 0, 0
  while frames < 120 do
    local active = UIZ_GetActiveMenu()
    if settle >= 0.35 and not (active and AgentGetName(active) == "popup_parent") then
      return
    end
    WaitForNextFrame()
    settle = settle + GetFrameTime()
    frames = frames + 1
  end
end

local function Notify(message, header)
  SettleAfterPopup()
  HideTitle()
  UIZ_Notify(message, header)
end

local function Confirm(message, header, code)
  HideTitle()
  UIZ_Confirm(message, header, code)
end

local function RestoreTitle()
  if AgentExists("ui_title") then
    local props = AgentGetProperties("ui_title")
    PropertyRemove(props, "Text Dialog 2.0 File")
    PropertyRemove(props, "Text Dialog 2.0 Node Name")
    PropertyRemove(props, "Text String")
  end
end

local function ReadState()
  local reply = CoopNet_Room("/v1/state")
  if reply and reply.ok == true then
    mPlayers = tonumber(reply.players)
    mNames = CoopNet_ReadNames(reply)
    CoopLink_SetPeers(mNames)
  end
  return reply
end

local function Wait(seconds)
  local accum = 0
  while accum < seconds do
    WaitForNextFrame()
    accum = accum + GetFrameTime()
  end
end

local function LobbyLoop(generation)
  local hadSession = CoopNet_GetSession() ~= nil
  while generation == mLobbyGeneration do
    if CoopNet_GetSession() then
      ReadState()
      if generation ~= mLobbyGeneration then
        return
      end
      if not CoopNet_GetSession() and hadSession then
        Notify(T(gCoopEndReason or "coop_msg_closed"), T("coop_title"))
        gCoopEndReason = nil
        return
      end
      RefreshLabels()
      SetRowsSelectable()
    end
    Wait(kRefreshSeconds)
  end
end

local function Role()
  local session = CoopNet_GetSession()
  if session and session.role == "host" then
    return T("coop_msg_you_host")
  end
  return T("coop_msg_you_guest")
end

local kCodeChars = "23456789ABCDEFGHJKMNPQRSTUVWXYZ"
local mEntry

local function EntryDisplay()
  local text = mEntry.text
  if mEntry.code and #text > 3 then
    text = string.sub(text, 1, 3) .. "-" .. string.sub(text, 4)
  end
  return text .. "_"
end

local function EntryHeader(entry, text)
  if entry.headerAgent and AgentExists(entry.headerAgent) then
    AgentSetProperty(entry.headerAgent, "Text String", text)
  end
end

local function EntryRefresh()
  if mEntry and mEntry.agent then
    AgentSetProperty(mEntry.agent, "Text String", EntryDisplay())
    if mEntry.prompt then
      EntryHeader(mEntry, mEntry.prompt)
    end
  end
end

local kRepeatDelay = 0.45
local kRepeatRate = 0.05

local function BackspaceHeld()
  local ok, down = pcall(InputPCIsVKeyPressed, 8)
  return ok and down == true
end

local function EntryRepeatBackspace(entry)
  if entry.repeating then
    return
  end
  entry.repeating = true
  ThreadStart(function()
    local wait = kRepeatDelay
    while not entry.done and BackspaceHeld() do
      local accum = 0
      while accum < wait and not entry.done and BackspaceHeld() do
        WaitForNextFrame()
        accum = accum + GetFrameTime()
      end
      if entry.done or not BackspaceHeld() or entry.text == "" then
        break
      end
      entry.text = string.sub(entry.text, 1, -2)
      EntryRefresh()
      wait = kRepeatRate
    end
    entry.repeating = false
  end)
end

function Menu_Online_TextEntryFinish(bAccept)
  local entry = mEntry
  if not entry or entry.done or entry.checking then
    return
  end
  if bAccept and entry.text ~= "" and entry.validate then
    entry.checking = true
    ThreadStart(function()
      local ok, problem = entry.validate(entry.text)
      entry.checking = false
      if entry.done then
        return
      end
      if ok then
        entry.done = true
        entry.result = entry.text
        UIZ_PopMenu()
      else
        local line = string.match(tostring(problem or ""), "^[^\r\n]*")
        if string.find(line, ",%s*$") then
          line = string.gsub(tostring(problem), "%s*[\r\n]+%s*", " ")
        end
        EntryHeader(entry, line)
        if entry.agent then
          AgentSetProperty(entry.agent, "Text String", line)
        end
      end
    end)
    return
  end
  entry.done = true
  if bAccept and entry.text ~= "" then
    entry.result = entry.text
  end
  UIZ_PopMenu()
end

function Menu_Online_TextEntryKey(event)
  local entry = mEntry
  if not entry or entry.done or not event then
    return
  end
  local code = event.code
  if code == 13 then
    Menu_Online_TextEntryFinish(true)
    return
  elseif code == 27 then
    Menu_Online_TextEntryFinish(false)
    return
  elseif code == 8 then
    entry.text = string.sub(entry.text, 1, -2)
    EntryRefresh()
    EntryRepeatBackspace(entry)
    return
  end
  local char
  if code >= 0x60 and code <= 0x69 then
    char = string.char(48 + code - 0x60)
  elseif code >= 48 and code <= 57 or code >= 65 and code <= 90 then
    char = string.char(code)
  elseif code == 32 and not entry.code then
    char = " "
  end
  if not char or #entry.text >= entry.max then
    return
  end
  if entry.code and not string.find(kCodeChars, char, 1, true) then
    return
  end
  if char == " " and (entry.text == "" or string.sub(entry.text, -1) == " ") then
    return
  end
  entry.text = entry.text .. char
  EntryRefresh()
end

local function TextEntry(header, initial, maxLength, bCode, validate)
  SettleAfterPopup()
  mEntry = { text = string.upper(initial or ""), max = maxLength, code = bCode, done = false,
    validate = validate, prompt = header }
  HideTitle()
  local menu = UIZ_Popup(EntryDisplay(), header)
  mEntry.agent = UIZ_GetInstance("message", "ui_text.prop", menu)
  mEntry.headerAgent = UIZ_GetInstance("header", "ui_text.prop", menu)
  function menu:activate()
    UIZ_ConsoleButton_Clear(menu)
    UIZ_ConsoleButton("facebutton_down", "navhelp_select")
    AgentSetProperty("ui_menu_popup_OK", "Text Scale", 0.5)
    AgentSetProperty("ui_menu_popup_cancel", "Text Scale", 0.5)
    InputMapperActivate("CoopTextEntry.imap")
  end
  function menu:deactivate()
    InputMapperDeactivate("CoopTextEntry.imap")
    if mEntry and not mEntry.done then
      mEntry.done = true
    end
  end
  function menu:populate()
    UIZ_Button("ui_menu_popup_OK", "label_OK", "Menu_Online_TextEntryFinish(true)")
    UIZ_Button("ui_menu_popup_cancel", "label_Cancel", "Menu_Online_TextEntryFinish(false)")
  end
  UIZ_PushMenu(menu)
  local entry = mEntry
  while not entry.done do
    WaitForNextFrame()
  end
  mEntry = nil
  return entry.result
end

local function EnsureName()
  local steamName = CoopLink_SteamName()
  if steamName then
    CoopNet_SetPlayerName(steamName)
    return CoopNet_GetPlayerName() ~= nil
  end
  local name = TextEntry(T("coop_prompt_name"), CoopNet_GetPlayerName(), 20, false)
  if not name then
    return false
  end
  CoopNet_SetPlayerName(name)
  return CoopNet_GetPlayerName() ~= nil
end

local function ShowSession()
  local session = CoopNet_GetSession()
  ReadState()
  local text = T("coop_msg_session", {
    code = CoopNet_FormatCode(session.code),
    n = mPlayers or "?",
    host = CoopNet_RelayHost()
  }) .. "\n" .. Role()
  if gCoopShowPlatformInfo then
    text = text .. "\n" .. CoopNet_PlatformInfo()
  end
  Notify(text, T("coop_header_session"))
end

local function CreateSession()
  if not EnsureName() then
    return
  end
  local room, problem = CoopNet_Create()
  if not room then
    Notify(problem, T("coop_title"))
    return
  end
  mPlayers = tonumber(room.players)
  mNames = CoopNet_ReadNames(room)
  Notify(T("coop_msg_created", { code = CoopNet_FormatCode(room.code), host = CoopNet_RelayHost() }),
    T("coop_header_created"))
end

local function JoinSession()
  local text = TextEntry(T("coop_prompt_code"), "", 6, true, function(value)
    local candidate = CoopNet_NormalizeCode(value)
    if not candidate then
      return nil, T("coop_msg_bad_code")
    end
    return CoopNet_Check(candidate)
  end)
  if not text or text == "" then
    return
  end
  local code = CoopNet_NormalizeCode(text)
  if not code then
    return
  end
  if not EnsureName() then
    return
  end
  local room, problem = CoopNet_Join(code)
  if not room then
    Notify(problem, T("coop_title"))
    return
  end
  mPlayers = tonumber(room.players)
  mNames = CoopNet_ReadNames(room)
  Notify(T("coop_msg_joined", { code = CoopNet_FormatCode(code) }), T("coop_title"))
end

local function LeaveSession()
  CoopNet_Leave("LEAVE SESSION")
  mPlayers, mNames = nil, {}
  Notify(T("coop_msg_left"), T("coop_title"))
end

function Menu_Online_MainButton()
  ThreadStart(function()
    if CoopNet_GetSession() then
      ShowSession()
    else
      CreateSession()
    end
  end)
end

function Menu_Online_SecondButton()
  ThreadStart(function()
    if CoopNet_GetSession() then
      LeaveSession()
    else
      JoinSession()
    end
  end)
end

function Menu_Online_Invite()
  ThreadStart(function()
    CoopLink_Invite()
  end)
end

local function JoinFromInvite(code)
  local name = CoopLink_SteamName()
  if name then
    CoopNet_SetPlayerName(name)
  end
  local ok, problem = CoopNet_Check(code)
  local room
  if ok then
    room, problem = CoopNet_Join(code)
  end
  local active = UIZ_GetActiveMenu()
  if room and active and AgentGetName(active) == "ui_menu_main" then
    Menu_Online()
  end
  if not room then
    Notify(problem, T("coop_title"))
    return
  end
  mPlayers = tonumber(room.players)
  mNames = CoopNet_ReadNames(room)
  Notify(T("coop_msg_joined", { code = CoopNet_FormatCode(code) }), T("coop_title"))
end

function Menu_Online_WatchInvites()
  if gCoopInviteWatcher and ThreadIsRunning(gCoopInviteWatcher) then
    return
  end
  gCoopInviteWatcher = ThreadStart(function()
    CoopLink_Hello()
    while CoopNet_Where() == "menu" do
      if not CoopNet_GetSession() then
        if CoopSave_Leave then
          pcall(CoopSave_Leave)
        end
        local code = CoopLink_TakePending()
        if code then
          JoinFromInvite(code)
        end
      end
      Wait(1)
    end
    gCoopInviteWatcher = nil
  end)
end

function Menu_Online_VoteTime()
  CoopNet_CycleVoteExtra()
  SetButtonText(mButtonVoteTime, VoteTimeLabel())
end

function Menu_Online_GuestPlay()
  CoopNet_ToggleGuestPlay()
  SetButtonText(mButtonGuestPlay, GuestPlayLabel())
end

function Menu_Online_PlayerRow(i)
  if not IsKickableRow(i) then
    return
  end
  local p = mNames[i]
  Confirm(T("coop_msg_remove_ask", { name = string.upper(p.name) }), T("coop_header_remove"),
    "UIZ_PopMenu() Menu_Online_KickConfirmed(" .. tostring(p.id) .. ")")
end

function Menu_Online_KickConfirmed(id)
  ThreadStart(function()
    if CoopNet_Kick(id) then
      ReadState()
      Notify(T("coop_msg_removed_ok"), T("coop_title"))
    else
      Notify(T("coop_msg_remove_fail"), T("coop_title"))
    end
  end)
end

function Menu_Online_Button(name, textNode, command)
  local button = NewButton(name, nil, command)
  SetButtonNode(button, textNode)
  return button
end

local kSubmenuTextScale = 0.424
local function SubmenuButton(name, textNode, command)
  local button = Menu_Online_Button(name, textNode, command)
  AgentSetProperty(name, kTextScale, kSubmenuTextScale)
  return button
end

function Menu_Online()
  local menu = UIZ_ListMenu("ui_menu_coop", nil, -0.14)
  AgentSetProperty(menu, "Menu Alignment", "Left")
  UIZ_Title("header_extras")

  function menu:activate()
    UIZ_BackButton()
    UIZ_ConsoleButton("facebutton_down", "navhelp_select")
    UIZ_ConsoleButton("facebutton_right", "navhelp_previousmenu", "UIZ_PopMenu()")
    RefreshLabels()
    SetRowsSelectable()
    mLobbyGeneration = mLobbyGeneration + 1
    local generation = mLobbyGeneration
    ThreadStart(function()
      WaitForNextFrame()
      if generation == mLobbyGeneration then
        ShowTitle()
        SetRowsSelectable()
      end
      LobbyLoop(generation)
    end)
  end

  function menu:deactivate()
    mLobbyGeneration = mLobbyGeneration + 1
    AgentHide(menu, true, true)
    local generation = mLobbyGeneration
    ThreadStart(function()
      local active
      for _ = 1, 15 do
        WaitForNextFrame()
        active = UIZ_GetActiveMenu()
        if active then
          break
        end
      end
      if active and AgentGetName(active) == "popup_parent" then
        while generation == mLobbyGeneration and UIZ_GetActiveMenu() == active do
          HideTitle()
          AgentHide(menu, true, true)
          WaitForNextFrame()
        end
      elseif active then
        RestoreTitle()
      end
    end)
  end

  function menu:populate()
    mPlayerRows = {}
    mButtonMain = SubmenuButton("ui_buttonCreateSession", "coop_create", "Menu_Online_MainButton()")
    mGapRow = nil
    if CoopNet_GetSession() then
      for i = 1, kPlayerRows do
        mPlayerRows[i] = SubmenuButton("ui_buttonCoopPlayer" .. i, "coop_waiting_players", "Menu_Online_PlayerRow(" .. i .. ")")
      end
      mGapRow = SubmenuButton("ui_buttonCoopGap", "coop_waiting_players", "")
      SetButtonText(mGapRow, " ")
      AgentSetSelectable(mGapRow, false)
    end
    mButtonVoteTime = nil
    mButtonGuestPlay = nil
    if IsHost() then
      mButtonVoteTime = SubmenuButton("ui_buttonCoopVoteTime", "coop_vote_time", "Menu_Online_VoteTime()")
      mButtonGuestPlay = SubmenuButton("ui_buttonCoopGuestPlay", "coop_guest_play", "Menu_Online_GuestPlay()")
      if CoopLink_CanInvite() then
        SubmenuButton("ui_buttonCoopInvite", "coop_invite", "Menu_Online_Invite()")
      end
    end
    mButtonSecond = SubmenuButton("ui_buttonJoinSession", "coop_join", "Menu_Online_SecondButton()")
  end

  UIZ_PushMenu("ui_menu_coop")
  AgentHide("ui_title", false)
end
