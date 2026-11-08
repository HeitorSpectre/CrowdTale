Callback_GameDialogOnBegin = Callback()
Callback_GameDialogOnEnd = Callback()
Callback_CutsceneOnBegin = Callback()
Callback_CutsceneOnEnd = Callback()
require("CoopDialog.lua")
require("CoopChoice.lua")
local kScene = "ui_dialog"
local kInputMap = "GameDialog"
local kMaxChoices = 4
local kColorGray = Color(0.5, 0.5, 0.5, 1)
local kColorWhite = Color(1, 1, 1, 1)
local eDialogMode = {
  Cutscene = 0,
  Ambient = 1,
  Background = 2
}
local kNextPageChoice = {
  ["Choice Display Text"] = Dialog_GetText("ui_text.dlog", "text_moreChoices")
}
local kPrevPageChoice = {
  ["Choice Display Text"] = Dialog_GetText("ui_text.dlog", "text_previousChoices")
}
local mScene, mChoices, mAmbientID
local mAmbientFadeOutTime = 0
local mBackgroundIDs = {}
local mDialogID, mReticleID
local mbPausedDialog = false
local mDialogChoices, mVisibleChoices, mExitChoice, mDefaultChoice
local mNumChoices = 0
local mNumVisibleChoices = 0
local mSelectedIndex
local mStickDir = 0
local mbChoicesExhausted = false
local mbCursorMode = true
local mSwitchController, mSwitchThread
local mDelaySeconds = 0
local mbDisableDialogIdle = false
local mTimerThread, mTimerShowController, mTimerController
local mTimerLength = -1
local mExchangeTimerController, mDeactivateThread
local mbDisableChoiceDisplay = false
local mbPagedChoice = false
local mNumPages = 1
local mCurrentPage = 1
local mFrameNumber
local mCoop
local mCoopLastSeq = 0
local kCoopPollInterval = 0.75
local kCoopVoteWindow = 20
local kCoopGuestWait = 90
local kCoopMaxChoices = 8
local kCoopEarlyClose = 1.5
local CoopDecorateChoice, CoopColorButton, CoopResumeScene, CoopHideTallies
local mCoopFrozen
mDisableAmbientFadeIn = false
local CreateAssets = function()
  local fileName = FileSetExtension(kInputMap, "imap")
  if CreateResource(fileName, kDirInputMaps) then
    InputMapperAddEvent(fileName, kEventCodeMouseL, kEventEnd, "GameDialog_OnMouseL")
    InputMapperAddEvent(fileName, kEventCodeMouseR, kEventEnd, "GameDialog_OnMouseR")
    InputMapperAddEvent(fileName, kEventCodeEnter, kEventBegin, "GameDialog_OnButtonEnter")
    InputMapperAddEvent(fileName, kEventCodeButtonA, kEventBegin, "GameDialog_OnButtonA")
    InputMapperAddEvent(fileName, kEventCodeButtonB, kEventBegin, "GameDialog_OnButtonB")
    InputMapperAddEvent(fileName, kEventCodeButtonX, kEventBegin, "GameDialog_OnButtonX")
    InputMapperAddEvent(fileName, kEventCodeButtonY, kEventBegin, "GameDialog_OnButtonY")
    InputMapperAddEvent(fileName, kEventCodeRollover, kEventBegin, "GameDialog_OnRollOn")
    InputMapperAddEvent(fileName, kEventCodeRollover, kEventEnd, "GameDialog_OnRollOff")
    InputMapperAddEvent(fileName, kEventCodeWheelUp, kEventEnd, "GameDialog_OnUp")
    InputMapperAddEvent(fileName, kEventCodeWheelDown, kEventEnd, "GameDialog_OnDown")
    InputMapperAddEvent(fileName, kEventCodeUp, kEventBegin, "GameDialog_OnUp")
    InputMapperAddEvent(fileName, kEventCodeDown, kEventBegin, "GameDialog_OnDown")
    InputMapperAddEvent(fileName, kEventCodeLeft, kEventBegin, "GameDialog_OnLeft")
    InputMapperAddEvent(fileName, kEventCodeRight, kEventBegin, "GameDialog_OnRight")
    Save(fileName)
  end
  fileName = "dialog_start.prop"
  if CreateResource(fileName, kDirPrimitives) then
    PropertyCreate(fileName, "Dialog - Ambient", kBool)
    PropertyCreate(fileName, "Dialog - Ambient Fade Out Time", kFloat)
    PropertyCreate(fileName, "Dialog - Background", kBool)
    Save(fileName)
  end
  if not PropertyHasGlobal("module_dlgProps_Start.prop", fileName) then
    PropertyAddGlobal("module_dlgProps_Start.prop", fileName)
    Save("module_dlgProps_Start.prop")
  end
  fileName = "dialog_choices.prop"
  if CreateResource(fileName, kDirPrimitives) then
    PropertyCreate(fileName, "Choices - Delay", kFloat, -1)
    PropertyCreate(fileName, "Choices - Disable Dialog Idle", kBool, false)
    PropertyCreate(fileName, "Choices - Paged", kBool, false)
    PropertyCreate(fileName, "Choices - Timer", kFloat, -1)
    PropertyCreate(fileName, "Choices - Timer Logic Key", kString)
    Save(fileName)
  end
  if not PropertyHasGlobal("module_dlgProps_Choices.prop", fileName) then
    PropertyAddGlobal("module_dlgProps_Choices.prop", fileName)
    Save("module_dlgProps_Choices.prop")
  end
  fileName = "dialog_choice.prop"
  if CreateResource(fileName, kDirPrimitives) then
    PropertyAddGlobal(fileName, "module_dlg_choice_presentation.prop")
    PropertyCreate(fileName, "Default Choice", kBool)
    PropertyCreate(fileName, "Delayed Choice", kBool)
    PropertyCreate(fileName, "Hidden Choice", kBool)
    Save(fileName)
  end
  if not PropertyHasGlobal("module_dlgProps_Choice.prop", fileName) then
    PropertyAddGlobal("module_dlgProps_Choice.prop", fileName)
    Save("module_dlgProps_Choice.prop")
  end
  if not PropertyHasGlobal("module_dlgProps_Case.prop", "module_dlg_choice_presentation.prop") then
    PropertyAddGlobal("module_dlgProps_Case.prop", "module_dlg_choice_presentation.prop")
    Save("module_dlgProps_Case.prop")
  end
  if not PropertyHasGlobal("module_dlgProps_Element.prop", "module_dlg_choice_presentation.prop") then
    PropertyAddGlobal("module_dlgProps_Element.prop", "module_dlg_choice_presentation.prop")
    Save("module_dlgProps_Element.prop")
  end
  CreateGameLogic("logic_game_dialog.prop")
end
local IsAmbient = function(dialog, nodeID)
  return DlgGetObjUserPropsValue(dialog, nodeID, "Dialog - Ambient"), DlgUserPropIsLocal(dialog, nodeID, "Dialog - Ambient")
end
local IsBackground = function(dialog, nodeID)
  return DlgGetObjUserPropsValue(dialog, nodeID, "Dialog - Background"), DlgUserPropIsLocal(dialog, nodeID, "Dialog - Background")
end
local PlaySelectChore = function(index)
  if index then
    for i, choiceButton in ipairs(mChoices) do
      if i ~= index then
        ChorePlayOnAgent("ui_hud_dialog_unselected_on.chore", choiceButton)
      end
    end
    ChorePlayAndWait("ui_hud_dialog_selection_on_xbox360.chore", nil, "default_text", "ui_dialog_facebutton" .. index, "default_available", "ui_hud_dialog_available_gamepad" .. index)
  end
end
local GetVisibleChoiceIndex = function(pageNum, buttonIndex)
  return kMaxChoices * pageNum - kMaxChoices + buttonIndex
end
local SetupButtons = function()
  local defaultIndex
  if mDefaultChoice then
    defaultIndex = table.find(mVisibleChoices, mDefaultChoice)
  end
  local lastPageNumVisibleChoices = mNumVisibleChoices - GetVisibleChoiceIndex(mNumPages, 0)
  if 1 < mNumPages then
    lastPageNumVisibleChoices = lastPageNumVisibleChoices - 1
  end
  local indexForDefault = 1
  mChoices = {}
  mbCursorMode = Input_UseCursor()
  if mbCursorMode then
    AgentHide("ui_dialog_cursor", false, true)
    AgentHide("ui_dialog_gamepad", true, true)
    for i = 1, kMaxChoices do
      local choice = AgentFind("ui_hud_dialog_available" .. i)
      table.insert(mChoices, choice)
    end
    if lastPageNumVisibleChoices < 3 then
      AgentSetPos("ui_dialog_cursor", Vector(0, -1.75, 0))
    else
      AgentRestore("ui_dialog_cursor", 1)
    end
    indexForDefault = GetVisibleChoiceIndex(mNumPages, lastPageNumVisibleChoices)
  else
    AgentHide("ui_dialog_cursor", true, true)
    AgentHide("ui_dialog_gamepad", false, true)
    for i = 1, kMaxChoices do
      local choice = AgentFind("ui_dialog_facebutton" .. i)
      table.insert(mChoices, choice)
    end
    if 1 < lastPageNumVisibleChoices then
      indexForDefault = GetVisibleChoiceIndex(mNumPages, 2 < lastPageNumVisibleChoices and 4 or 2)
    end
  end
  if defaultIndex and defaultIndex ~= indexForDefault then
    mVisibleChoices[indexForDefault], mVisibleChoices[defaultIndex] = mVisibleChoices[defaultIndex], mVisibleChoices[indexForDefault]
  end
  Buttons_SelectDefault(mScene)
end
local SetChoices = function(pageNum)
  for i, choice in ipairs(mChoices) do
    local dlgChoice = mVisibleChoices[GetVisibleChoiceIndex(pageNum, i)]
    if dlgChoice then
      local text = StringTrim(dlgChoice["Choice Display Text"])
      if dlgChoice == mDefaultChoice then
        local silenceText = Dialog_GetText("ui_text.dlog", "text_silence")
        if not text or text == "" then
          text = silenceText
        end
        if text == silenceText then
          dlgChoice.mbDelay = true
        end
      end
      text = text or dlgChoice["First Line"]
      if text == "" then
        text = "This choice is blank!"
      end
      choice.mProps[kText] = CoopDecorateChoice(dlgChoice, text)
      if dlgChoice.mbNew then
        choice.mProps[kTextColor] = kColorWhite
      else
        choice.mProps[kTextColor] = kColorGray
      end
      CoopColorButton(choice, dlgChoice)
    end
    AgentHide(choice, dlgChoice == nil, true)
  end
end
local RefreshUI = function()
  if mSwitchThread or mDeactivateThread then
    return
  end
  local thread = ThreadStart(function()
    CursorHide(true, kScene)
    InputMapperDeactivate(kInputMap)
    PlaySelectChore(mSelectedIndex)
    mSelectedIndex = nil
    mSwitchController = ChorePlay(AgentGetProperty(SceneGetSceneAgent(mScene), kUIChoreClose), 90)
    ControllerWait(mSwitchController)
    mSwitchController = nil
    SetupButtons()
    SetChoices(mCurrentPage)
    mSwitchController = ChorePlay(AgentGetProperty(SceneGetSceneAgent(mScene), kUIChoreOpen), 90)
    ControllerWait(mSwitchController)
    mSwitchController = nil
    InputMapperActivate(kInputMap)
    CursorHide(false, kScene)
    RolloverResetStatus()
    mSwitchThread = nil
  end)
  if ThreadIsRunning(thread) then
    mSwitchThread = thread
  end
end
local ActivateChoice = function(choice, bSkipChore)
  mCoop = nil
  CoopResumeScene()
  CoopHideTallies()
  if not IsToolBuild() and (IsPlatformXboxOne() or IsPlatformPS4() or IsPlatformPS5()) then
    PlatformReportIncrementChoiceMade()
  end
  if choice == kNextPageChoice then
    mCurrentPage = mCurrentPage + 1
    RefreshUI()
    return
  end
  if choice == kPrevPageChoice then
    mCurrentPage = mCurrentPage - 1
    RefreshUI()
    return
  end
  if mTimerThread then
    ThreadKill(mTimerThread)
    mTimerThread = nil
  end
  if mTimerShowController then
    ControllerKill(mTimerShowController)
    mTimerShowController = nil
  end
  if mTimerController then
    ControllerKill(mTimerController)
    mTimerController = nil
  end
  if mSwitchThread then
    ThreadKill(mSwitchThread)
    mSwitchThread = nil
    CursorHide(false, kScene)
    bSkipChore = true
  end
  if mSwitchController then
    ControllerKill(mSwitchController)
    mSwitchController = nil
  end
  local bSleeping = false
  local thread = ThreadStart(function()
    InputMapperDeactivate(kInputMap)
    GameUI_BlockPause(true)
    if not bSkipChore then
      CursorHide(true, kScene)
      PlaySelectChore(mSelectedIndex)
      if mTimerLength and 0 < mTimerLength then
        ChorePlay("ui_hud_timer_hide.chore")
      end
      ChorePlayAndWait(AgentGetProperty(SceneGetSceneAgent(mScene), kUIChoreClose))
      CursorHide(false, kScene)
    end
    SceneHide(mScene, true)
    SceneRemove(kScene)
    mScene = nil
    mDialogChoices = nil
    mVisibleChoices = nil
    mSelectedIndex = nil
    if Game_GetMode() == eModeDialog then
      Game_PopMode(eModeDialog)
    end
    Yield()
    if not bSleeping then
      GameUI_BlockPause(false)
    end
    mDeactivateThread = nil
  end)
  if ThreadIsRunning(thread) then
    mDeactivateThread = thread
  end
  if choice then
    local blockingSubtitle
    local currentSubtitle = Subtitle_GetCurrentID()
    local subtitleInstance = SubtitleGetDlgInstanceID(currentSubtitle)
    if subtitleInstance == mDialogID then
      blockingSubtitle = currentSubtitle
    end
    if blockingSubtitle or choice.mbDelay and mExchangeTimerController then
      while Subtitle_GetCurrentID() == blockingSubtitle or choice.mbDelay and ControllerIsPlaying(mExchangeTimerController) do
        Yield()
        if mExchangeTimerController and ControllerIsPlaying(mExchangeTimerController) and ControllerGetLength(mExchangeTimerController) - ControllerGetTime(mExchangeTimerController) < 0.2 then
          GameUI_BlockPause(true)
        end
      end
    end
    while Game_IsPaused() or Game_GetMode() == eModePaused or Game_GetMode() == eModeMenu or SceneGetTimeScale(mScene) <= 0 do
      Yield()
    end
    GameUI_BlockPause(true)
    GameDialog_StopAmbient()
    DlgSelectChoice(mDialogID, choice["Choice ID"])
    ThreadStart(function()
      bSleeping = true
      local elapsedTime = 0
      while elapsedTime < 1 do
        elapsedTime = elapsedTime + GetFrameTime() * SceneGetTimeScale(mScene)
        Yield()
      end
      bSleeping = false
      GameUI_BlockPause(false)
    end)
  end
end
local CoopWait = function(seconds)
  local accum = 0
  while accum < seconds do
    Yield()
    accum = accum + GetFrameTime()
  end
  return accum
end
local CoopCanonicalIndex = function(coop, dlgChoice)
  for i, c in ipairs(coop.choices) do
    if c == dlgChoice then
      return i
    end
  end
  return nil
end
local kCoopColors = {
  Color(0.24, 0.78, 0.91, 1),
  Color(0.95, 0.79, 0.3, 1),
  Color(0.91, 0.28, 0.35, 1),
  Color(0.32, 0.79, 0.54, 1),
  Color(0.69, 0.49, 0.91, 1),
  Color(0.94, 0.54, 0.24, 1),
  Color(0.91, 0.44, 0.72, 1),
  Color(0.85, 0.82, 0.77, 1)
}
local kCoopDimColors = {
  Color(0.16, 0.55, 0.64, 1),
  Color(0.66, 0.55, 0.21, 1),
  Color(0.64, 0.2, 0.25, 1),
  Color(0.22, 0.55, 0.38, 1),
  Color(0.48, 0.34, 0.64, 1),
  Color(0.66, 0.38, 0.16, 1),
  Color(0.64, 0.31, 0.5, 1),
  Color(0.6, 0.58, 0.54, 1)
}
local CoopEligible = function()
  return mDialogChoices and not mbPagedChoice and mNumVisibleChoices >= 2 and mNumChoices <= kCoopMaxChoices
    and CoopDialog_LocalRole() ~= nil
end
local CoopChoiceIndex = function(dlgChoice)
  if mDialogChoices then
    for i, c in ipairs(mDialogChoices) do
      if c == dlgChoice then
        return i
      end
    end
  end
  return nil
end
local CoopColorFor = function(index, dlgChoice)
  local palette = dlgChoice and not dlgChoice.mbNew and kCoopDimColors or kCoopColors
  return palette[(index - 1) % #palette + 1]
end
local CoopOnSelect = function(button, bSelect)
  if bSelect or not button.mCoopColor then
    return
  end
  ThreadStart(function()
    Yield()
    while button.mChoreController and ControllerIsPlaying(button.mChoreController) do
      Yield()
    end
    if button.mCoopColor and not button.mbSelected then
      button.mProps[kTextColor] = button.mCoopColor
    end
  end)
end
CoopDecorateChoice = function(dlgChoice, text)
  dlgChoice.mCoopText = text
  return text
end
CoopColorButton = function(button, dlgChoice)
  button.mCoopColor = nil
  if not CoopEligible() then
    return
  end
  local index = CoopChoiceIndex(dlgChoice)
  if not index then
    return
  end
  button.mCoopColor = CoopColorFor(index, dlgChoice)
  button.mProps[kTextColor] = button.mCoopColor
  local scene = AgentGetScene(button)
  if scene then
    scene.mSelectCallback = CoopOnSelect
  end
end
local CoopReapplyColors = function()
  if not mChoices then
    return
  end
  for _, button in ipairs(mChoices) do
    if button.mCoopColor and not button.mbSelected then
      button.mProps[kTextColor] = button.mCoopColor
    end
  end
end
local CoopSettleColors = function()
  CoopReapplyColors()
  ThreadStart(function()
    for _ = 1, 3 do
      Yield()
    end
    local busy = true
    local guard = 0
    while busy and guard < 120 do
      busy = false
      for _, button in ipairs(mChoices or {}) do
        if button.mChoreController and ControllerIsPlaying(button.mChoreController) then
          busy = true
        end
      end
      guard = guard + 1
      Yield()
    end
    CoopReapplyColors()
  end)
end
local kCoopTallyGold = Color(1, 0.82, 0.35, 1)
local kCoopTallyGap = 0.12
local kCoopTallyIconScale = 1.0
local kCoopTallyIconProp = "ui_hud_notifications_saveicon.prop"
local kCoopTallyIconTexture = "ui_coop_voter.d3dtx"
local kCoopTallyIconOriginal = "ui_hud_notifications_saveIcon.d3dtx"
local mCoopTally = {}
local mCoopTallyError
local CoopTallyCopy = {
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
local CoopTallyFor = function(i, button)
  local t = mCoopTally[i]
  if t and t.button == button and AgentExists(t.text) and AgentExists(t.icon) then
    return t
  end
  local scene = AgentGetScene(button)
  local textName = "coop_tally_text" .. i
  local iconName = "coop_tally_icon" .. i
  local text = AgentExists(textName) and AgentFind(textName) or AgentCreate(textName, "ui_text.prop", Vector(0, 0, 0), nil, scene)
  local icon = AgentExists(iconName) and AgentFind(iconName) or AgentCreate(iconName, kCoopTallyIconProp, Vector(0, 0, 0), nil, scene)
  if not text or not icon then
    return nil
  end
  for _, key in ipairs(CoopTallyCopy) do
    local value = AgentGetProperty(button, key)
    if value ~= nil then
      AgentSetProperty(text, key, value)
    end
  end
  AgentSetProperty(text, "Text Alignment Horizontal", "Left Justified")
  AgentSetProperty(text, "Text String", "")
  AgentSetSelectable(text, false)
  AgentSetSelectable(icon, false)
  ShaderOverrideTexture(icon, kCoopTallyIconOriginal, kCoopTallyIconTexture)
  t = { button = button, text = text, icon = icon }
  mCoopTally[i] = t
  return t
end
CoopHideTallies = function()
  for _, t in pairs(mCoopTally) do
    if AgentExists(t.text) then
      AgentHide(t.text, true)
    end
    if AgentExists(t.icon) then
      AgentHide(t.icon, true)
    end
  end
end
local kCoopTallyPixelFallback = 0.007
local CoopTallyPixel = function(button)
  local ok, scale = pcall(AgentGetPixelScale, button)
  if ok and type(scale) == "number" and scale > 0.0001 and scale < 0.1 then
    return scale, "ps"
  end
  return kCoopTallyPixelFallback, "fb"
end
local CoopTallyEnd = function(button, label)
  local width = 0
  local ok, lines = pcall(TextGetLines, button, label)
  if ok and type(lines) == "table" and 1 < #lines then
    for _, line in ipairs(lines) do
      if type(line) == "string" then
        width = math.max(width, TextGetWidth(button, line) or 0)
      end
    end
  end
  if width <= 0 then
    width = TextGetWidth(button, label) or 0
  end
  local align = tostring(AgentGetProperty(button, "Text Alignment Horizontal") or "")
  if align == "2" or string.find(align, "Center") then
    return width / 2
  elseif align == "3" or string.find(align, "Right") then
    return 0
  end
  return width
end
local CoopShowTally = function(i, button, label, n, leader)
  local t = CoopTallyFor(i, button)
  if not t then
    return
  end
  if n < 1 then
    AgentHide(t.text, true)
    AgentHide(t.icon, true)
    return
  end
  local color = leader and kCoopTallyGold or (button.mCoopColor or kColorWhite)
  local number = tostring(n)
  AgentSetProperty(t.text, "Text String", number)
  AgentSetProperty(t.text, "Text Color", color)
  AgentSetProperty(t.icon, "Render Diffuse Color", color)
  local px, src = CoopTallyPixel(button)
  local lineH = (TextGetLineHeight and TextGetLineHeight(button)) or 40
  local numberW = TextGetWidth(t.text, number) or lineH * 0.5
  local right = AgentGetRightVec(button, true)
  if right.x < 0 then
    right = VectorScale(right, -1)
  end
  local origin = AgentGetWorldPos(button)
  local along = (CoopTallyEnd(button, label) + lineH * 0.3) * px
  local textPos = VectorAdd(origin, VectorScale(right, along))
  AgentSetWorldPos(t.text, textPos)
  local iconAlong = along + (numberW + lineH * 0.45) * px
  AgentSetWorldPos(t.icon, VectorAdd(origin, VectorScale(right, iconAlong)))
  if t.iconScale then
    AgentSetProperty(t.icon, "Render Global Scale", t.iconScale)
  elseif not t.measuring then
    t.measuring = true
    AgentSetProperty(t.icon, "Render Global Scale", 1)
    ThreadStart(function()
      WaitForNextFrame()
      WaitForNextFrame()
      if not (AgentExists(t.icon) and AgentExists(t.text)) then
        return
      end
      local okI, ia = pcall(AgentScreenArea, t.icon)
      local okT, ta = pcall(AgentScreenArea, t.text)
      if okI and okT and type(ia) == "number" and type(ta) == "number" and ia > 0 and ta > 0 then
        t.iconScale = math.sqrt(ta / 0.55 / ia) * kCoopTallyIconScale
      else
        t.iconScale = lineH * px
      end
      CoopNet_Note("tally icon area=" .. tostring(ia) .. " text=" .. tostring(ta) .. " scale=" .. tostring(t.iconScale))
      AgentSetProperty(t.icon, "Render Global Scale", t.iconScale)
    end)
  end
  AgentHide(t.text, false)
  AgentHide(t.icon, false)
end
local CoopRefreshTexts = function(coop, poll)
  poll = poll or coop.lastPoll
  if not mChoices or not mVisibleChoices then
    return
  end
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
  for i, button in ipairs(mChoices) do
    local dlgChoice = mVisibleChoices[GetVisibleChoiceIndex(mCurrentPage, i)]
    local shown = false
    if dlgChoice and dlgChoice.mCoopText then
      local index = CoopCanonicalIndex(coop, dlgChoice)
      if index then
        local n = poll and poll.votes[index] or 0
        local text = dlgChoice.mCoopText
        local ok, err = pcall(CoopShowTally, i, button, text, n, index == best)
        if button.mProps[kText] ~= text then
          button.mProps[kText] = text
        end
        if not ok and not mCoopTallyError then
          mCoopTallyError = true
          CoopNet_Note("tally error: " .. tostring(err))
        end
        shown = true
      end
    end
    local t = mCoopTally[i]
    if not shown and t and AgentExists(t.text) and AgentExists(t.icon) then
      AgentHide(t.text, true)
      AgentHide(t.icon, true)
    end
  end
end
local CoopAnnounceVoters = function(coop, poll)
  local seen = coop.announced or 0
  local me = CoopNet_GetPlayerName()
  for i = seen + 1, #poll.voters do
    local voter = poll.voters[i]
    if voter.name ~= me then
      CoopDialog_Notify(CoopNet_Text("coop_hud_voted", { name = CoopNet_DisplayName(voter.name) }))
    end
  end
  coop.announced = #poll.voters
end
local CoopApply = function(coop, index)
  if mCoop ~= coop then
    return
  end
  if coop.seq and coop.seq > mCoopLastSeq then
    local seq = coop.seq
    mCoopLastSeq = seq
    ThreadStart(function()
      CoopDialog_Applied(seq)
    end)
  end
  local choice = coop.choices[index]
  if not choice then
    mCoop = nil
    return
  end
  mSelectedIndex = nil
  if mVisibleChoices then
    for i = 1, kMaxChoices do
      if mVisibleChoices[GetVisibleChoiceIndex(mCurrentPage, i)] == choice then
        mSelectedIndex = i
      end
    end
  end
  ActivateChoice(choice)
end
CoopResumeScene = function()
  local frozen = mCoopFrozen
  mCoopFrozen = nil
  if frozen and ControllerIsPaused(frozen) then
    ControllerPlay(frozen)
  end
end
local CoopHoldScene = function(coop)
  local controller = mExchangeTimerController
  if not controller then
    return
  end
  ThreadStart(function()
    while mCoop == coop and ControllerIsPlaying(controller) do
      if ControllerGetLength(controller) - ControllerGetTime(controller) < 0.6 then
        ControllerPause(controller)
        mCoopFrozen = controller
        return
      end
      Yield()
    end
  end)
end
local CoopStretchTimer = function(seconds)
  if not mTimerController or not seconds or seconds <= 0 then
    return
  end
  local length = ChoreGetLength("ui_hud_timer_start.chore")
  local left = length - ControllerGetTime(mTimerController)
  if 0 < left then
    ControllerSetTimeScale(mTimerController, left / seconds)
  end
end
local CoopAbandon = function(coop)
  if mCoop ~= coop then
    return
  end
  if coop.myVote then
    CoopApply(coop, coop.myVote)
    return
  end
  mCoop = nil
  CoopResumeScene()
  if coop.timerExpired then
    GameDialog_SelectDefaultChoice()
  end
end
local kCoopMaxFailures = 5
local CoopRunHost = function(coop)
  local elapsed = 0
  local failures = 0
  while mCoop == coop do
    local paused = Game_IsPaused() and true or false
    if paused ~= (coop.paused or false) then
      coop.paused = paused
      CoopDialog_Pause(paused)
      if mCoop ~= coop then
        return
      end
    end
    local role, status = CoopDialog_Status()
    if mCoop ~= coop then
      return
    end
    local poll = CoopDialog_ReadPoll(status)
    if role ~= "host" or not poll or poll.seq ~= coop.seq then
      failures = failures + 1
      if failures >= kCoopMaxFailures then
        CoopAbandon(coop)
        return
      end
    else
      failures = 0
      coop.lastPoll = poll
      CoopRefreshTexts(coop, poll)
      CoopAnnounceVoters(coop, poll)
      if not paused then
        local players = tonumber(status.players) or 1
        local expired = false
        if not coop.unlimited then
          expired = coop.timerExpired or not coop.timed and elapsed >= kCoopVoteWindow + coop.extra or
            coop.timed and coop.timerLength and elapsed >= coop.timerLength + coop.extra - kCoopEarlyClose
        end
        local fallback = poll.total == 0 and coop.defaultIndex or nil
        if poll.total >= players or expired and (0 < poll.total or fallback) then
          local result = CoopDialog_Resolve(coop.seq, fallback)
          if mCoop ~= coop then
            return
          end
          if result then
            CoopApply(coop, result)
          else
            CoopAbandon(coop)
          end
          return
        end
      end
    end
    local waited = CoopWait(kCoopPollInterval)
    if not paused then
      elapsed = elapsed + waited
    end
  end
end
local CoopRunGuest = function(coop)
  local waited = 0
  local failures = 0
  while mCoop == coop do
    local role, status = CoopDialog_Status()
    if mCoop ~= coop then
      return
    end
    if role ~= "guest" then
      failures = failures + 1
      if failures >= kCoopMaxFailures or not CoopDialog_LocalRole() then
        CoopAbandon(coop)
        return
      end
      status = nil
    else
      failures = 0
    end
  if status then
    local applied = tonumber(status.applied)
    if applied and applied > mCoopLastSeq then
      mCoopLastSeq = applied
    end
    local poll = CoopDialog_ReadPoll(status)
    local recent = CoopDialog_ReadRecent(status)
    if not coop.seq then
      local candidate
      for _, r in ipairs(recent) do
        if r.seq > mCoopLastSeq and r.count == coop.count and (not candidate or r.seq < candidate) then
          candidate = r.seq
        end
      end
      if poll and poll.seq > mCoopLastSeq and poll.count == coop.count and (not candidate or poll.seq < candidate) then
        candidate = poll.seq
      end
      if candidate then
        coop.seq = candidate
        if poll and poll.seq == candidate then
          if coop.timed and poll.remaining and 0 < poll.remaining then
            CoopStretchTimer(poll.remaining)
          elseif coop.timed and not poll.remaining and mTimerController then
            ControllerPause(mTimerController)
          end
          if coop.myVote and not poll.result and poll.mine ~= coop.myVote then
            CoopDialog_Vote(coop.seq, coop.myVote)
          end
        end
      end
    end
    if coop.seq then
      for _, r in ipairs(recent) do
        if r.seq == coop.seq then
          CoopApply(coop, r.result)
          return
        end
      end
      if poll and poll.seq == coop.seq then
        coop.lastPoll = poll
        CoopRefreshTexts(coop, poll)
        CoopAnnounceVoters(coop, poll)
        if poll.result then
          CoopApply(coop, poll.result)
          return
        end
      elseif waited >= kCoopGuestWait * 3 then
        CoopAbandon(coop)
        return
      end
    elseif waited >= kCoopGuestWait then
      CoopAbandon(coop)
      return
    end
  end
    waited = waited + CoopWait(kCoopPollInterval)
  end
end
local CoopBegin = function()
  mCoop = nil
  if CoopChoice_Busy and CoopChoice_Busy() then
    return
  end
  if mbPagedChoice or mNumVisibleChoices < 2 or mNumChoices > kCoopMaxChoices or not mDialogChoices then
    return
  end
  local role = CoopDialog_LocalRole()
  CoopNet_Note("begin role=" .. tostring(role) .. " choices=" .. tostring(mNumChoices) .. " visible=" .. tostring(mNumVisibleChoices))
  if not role then
    return
  end
  local coop = {
    role = role,
    choices = mDialogChoices,
    count = mNumChoices,
    timed = mTimerLength and 0 < mTimerLength,
    timerLength = mTimerLength,
    extra = 0
  }
  if role == "host" then
    coop.extra = CoopNet_GetVoteExtra()
  end
  coop.unlimited = coop.extra == CoopNet_kVoteUnlimited
  for i, c in ipairs(mDialogChoices) do
    if c == mDefaultChoice then
      coop.defaultIndex = i
    end
  end
  mCoop = coop
  if coop.timed then
    CoopHoldScene(coop)
    if coop.unlimited then
      if mTimerController then
        ControllerPause(mTimerController)
      end
    elseif 0 < coop.extra then
      CoopStretchTimer(coop.timerLength + coop.extra)
    end
  end
  CoopSettleColors()
  CoopRefreshTexts(coop)
  CoopNet_EnsureHeartbeat()
  ThreadStart(function()
    if coop.role == "host" then
      local texts = {}
      for i, c in ipairs(coop.choices) do
        texts[i] = c.mCoopText or ""
      end
      local secs = nil
      if not coop.unlimited then
        secs = (coop.timed and coop.timerLength or kCoopVoteWindow) + coop.extra
      end
      local seq = CoopDialog_OpenPoll(coop.count, texts, secs)
      CoopNet_Note("poll seq=" .. tostring(seq))
      if mCoop ~= coop then
        return
      end
      if not seq then
        CoopAbandon(coop)
        return
      end
      coop.seq = seq
      if coop.myVote then
        CoopDialog_Vote(seq, coop.myVote)
      end
      CoopRunHost(coop)
    else
      CoopRunGuest(coop)
    end
  end)
end
local CoopOnTimer = function()
  if not mCoop then
    return false
  end
  mCoop.timerExpired = true
  return true
end
local ChooseChoice = function(choice)
  local coop = mCoop
  if not coop or not choice or choice == kNextPageChoice or choice == kPrevPageChoice then
    ActivateChoice(choice)
    return
  end
  local index = CoopCanonicalIndex(coop, choice)
  if not index then
    ActivateChoice(choice)
    return
  end
  coop.myVote = index
  CoopRefreshTexts(coop)
  local seq = coop.seq
  if seq then
    ThreadStart(function()
      CoopDialog_Vote(seq, index)
    end)
  end
end
Callback_GameDialogOnBegin:Add(function()
  if CoopNet_GetSession() then
    CoopChoice_InstallHooks()
    CoopNet_EnsureHeartbeat()
  end
end)
local OnSetInputMode = function(bUseCursor)
  if Game_GetMode() ~= eModeDialog or mbCursorMode == bUseCursor then
    return
  end
  RefreshUI()
end
local Init = function()
  if IsToolBuild() then
    CreateAssets()
  end
  DlgAddCallbackDialogBegin("GameDialog_OnBegin")
  DlgAddCallbackDialogEnd("GameDialog_OnEnd")
  DlgAddCallbackChoicesAvailable("GameDialog_OnChoicesAvailable")
  Callback_DialogOnStartNodeBegin:Add(GameDialog_OnStart)
  Callback_DialogOnChoicesNodeBegin:Add(GameDialog_OnChoicesNode)
  Callback_DialogOnCancelChoicesBegin:Add(GameDialog_OnCancelChoice)
  Callback_OnSetInputMode:Add(OnSetInputMode)
end

function GameDialog_StopAll()
  GameDialog_StopAmbient()
  GameDialog_StopBackground()
  if mDialogID then
    DlgStop(mDialogID)
  end
  mbPausedDialog = false
end

function GameDialog_StopAmbient(newID)
  local mainThread = function()
    if not mAmbientID then
      return
    end
    local fadeTime = mAmbientFadeOutTime
    local ambientID = mAmbientID
    mAmbientID = nil
    if 0 < fadeTime and DlgGetCurPlaybackController(ambientID) then
      local controller = DlgGetCurPlaybackController(ambientID)
      if controller.fadingOut then
        return
      end
      RenderDelay(5, true)
      controller.fadingOut = true
      ControllerSetEndPause(controller, true)
      local timeUntilEnd = ControllerGetLength(controller) - ControllerGetTime(controller) - GetFrameTime() * 2
      if fadeTime >= timeUntilEnd then
        Print("time was greater")
        fadeTime = timeUntilEnd - GetFrameTime()
        ControllerPause(controller)
      end
      local bFadeInNew = false
      RenderDelay(1)
      if newID and not mDisableAmbientFadeIn then
        bFadeInNew = true
        while not DlgGetCurPlaybackController(newID) do
          if not DlgIsRunning(newID) or fadeTime <= 0 then
            bFadeInNew = false
            if fadeTime < 0 then
              fadeTime = 0
            end
            break
          end
          Yield()
          fadeTime = fadeTime - GetFrameTime()
        end
      end
      if bFadeInNew then
        ControllerFadeIn(DlgGetCurPlaybackController(newID), fadeTime)
        ControllerSetPriority(controller, ControllerGetPriority(DlgGetCurPlaybackController(newID)) - 5)
      else
        ControllerFadeOut(controller, fadeTime)
        ControllerSetPriority(controller, ControllerGetPriority(controller) - 5)
      end
      local thread = function()
        local idToStop = ambientID
        while controller do
          Yield()
          if controller then
            ControllerSetEndPause(controller, true)
            if bFadeInNew and DlgGetCurPlaybackController(newID) then
              if ControllerIsPaused(controller) or ControllerGetContribution(DlgGetCurPlaybackController(newID)) >= 1 or ControllerGetTime(controller) >= ControllerGetLength(controller) - GetFrameTime() then
                DlgStop(idToStop)
                ControllerKill(controller)
                controller = nil
              end
            elseif ControllerIsPaused(controller) or ControllerGetContribution(controller) <= 0.1 or ControllerGetTime(controller) >= ControllerGetLength(controller) - GetFrameTime() then
              DlgStop(idToStop)
              ControllerKill(controller)
              controller = nil
            end
          else
            DlgStop(idToStop)
            controller = nil
          end
        end
      end
      ThreadStart(thread)
    else
      DlgStop(ambientID)
    end
  end
  ThreadStart(mainThread)
end

function GameDialog_StopBackground()
  for i, id in pairs(mBackgroundIDs) do
    DlgStop(id)
  end
end

function GameDialog_TogglePaused()
  if not mAmbientID and #mBackgroundIDs == 0 and not mDialogID then
    mbPausedDialog = false
    return
  end
  mbPausedDialog = not mbPausedDialog
  if mbPausedDialog then
    if mAmbientID then
      DlgPause(mAmbientID)
    end
    for _, id in pairs(mBackgroundIDs) do
      DlgPause(id)
    end
    if mDialogID then
      DlgPause(mDialogID)
    end
    if mTimerController then
      ControllerPause(mTimerController)
    end
  else
    if mAmbientID then
      DlgResume(mAmbientID)
    end
    for _, id in pairs(mBackgroundIDs) do
      DlgResume(id)
    end
    if mDialogID then
      DlgResume(mDialogID)
    end
    if mTimerController then
      ControllerPlay(mTimerController)
    end
  end
end

function GameDialog_Advance(id)
  if not DlgIsRunning(id) then
    return
  end
  local controller
  repeat
    RenderDelay(1)
    Yield()
    controller = DlgGetCurPlaybackController(id)
    if controller then
      ControllerSetTime(controller, ControllerGetLength(controller))
    end
  until controller == nil
  if DlgIsRunning(id) then
    RenderDelay(1)
    Yield()
    if mDialogChoices then
      local choice = mExitChoice
      choice = choice or mDialogChoices[1]
      ActivateChoice(choice, true)
      RenderDelay(1)
      Yield()
      GameDialog_Advance(id)
    end
  end
end

function GameDialog_TransitionToTime(timeToJumpTo, fadeTime, instanceID, bNewVersion)
  instanceID = instanceID or mAmbientID
  timeToJumpTo = timeToJumpTo - fadeTime / 2
  local thread = function()
    local controller = Dialog_GetController(instanceID)
    if not controller or timeToJumpTo <= ControllerGetTime(controller) + GetFrameTime() then
      return
    end
    local clonedChoreName = ResourceGetName(ControllerGetChore(controller)) or ResourceGetName(DlgExchangeGetChore(DlgGetCurrentDialog(instanceID), DlgGetCurrentNode(instanceID)))
    if not clonedChoreName or clonedChoreName == "" then
      Print("WARNING: GameDialog_TransitionToTime failed to find a chore name for instance " .. instanceID .. "! Can't clone the controller; jumping to time will fail!")
    end
    local clonedController = ChorePlay(clonedChoreName)
    ControllerSetContribution(clonedController, 0)
    ControllerSetSoundVolume(clonedController, 0)
    ControllerSetPriority(clonedController, ControllerGetPriority(controller) - 1)
    ControllerSetTime(clonedController, ControllerGetTime(controller))
    Yield()
    ChoreTracker_AddController(clonedController, "Jump (" .. clonedChoreName .. ")")
    ControllerSetContribution(clonedController, 1)
    ControllerSetContribution(controller, 0)
    ControllerSetTime(controller, timeToJumpTo)
    ControllerFadeTo(controller, fadeTime, 1)
    Sleep(fadeTime)
    if bNewVersion then
      while controller and ControllerIsPlaying(controller) do
        ControllerSetTime(clonedController, ControllerGetTime(controller))
        if ControllerIsPaused(controller) then
          ControllerPause(clonedController)
        else
          ControllerPlay(clonedController)
        end
        ControllerSetContribution(clonedController, 0.001)
        ControllerSetSoundVolume(clonedController, 0)
        ControllerSetPriority(clonedController, 0)
        Yield()
      end
    end
    ControllerKill(clonedController)
  end
  ThreadStart(thread)
end

function GameDialog_IsAmbientRunning()
  if mAmbientID and DlgIsRunning(mAmbientID) then
    return true
  end
  return false
end

function GameDialog_SelectDefaultChoice(bSkipChore)
  if not mDialogChoices or not mDefaultChoice then
    return
  end
  ActivateChoice(mDefaultChoice, bSkipChore)
end

function GameDialog_IsChoiceExhausted()
  return mbChoicesExhausted
end

function GameDialog_CutsceneToAmbient()
  if not mDialogID or Game_GetMode() == eModeDialog then
    return
  end
  local instanceID = mDialogID
  GameDialog_OnEnd(instanceID)
  GameDialog_OnBegin(instanceID, eDialogMode.Ambient)
end

function GameDialog_CutsceneToBackground()
  if not mDialogID or Game_GetMode() == eModeDialog then
    return
  end
  local instanceID = mDialogID
  GameDialog_OnEnd(instanceID)
  GameDialog_OnBegin(instanceID, eDialogMode.Background)
end

function GameDialog_AmbientToCutscene()
  if not mAmbientID or Game_GetMode() == eModeDialog then
    return
  end
  local instanceID = mAmbientID
  GameDialog_OnEnd(instanceID)
  GameDialog_OnBegin(instanceID, eDialogMode.Cutscene)
end

function GameDialog_AmbientToBackground()
  if not mAmbientID then
    return
  end
  local instanceID = mAmbientID
  GameDialog_OnEnd(instanceID)
  GameDialog_OnBegin(instanceID, eDialogMode.Background)
end

function GameDialog_OnBegin(dialogID, forceMode)
  local dialog = DlgGetCurrentDialog(dialogID)
  local nodeID = DlgGetCurrentNode(dialogID)
  local bAmbient = false
  local bBackground = false
  if forceMode then
    bAmbient = forceMode == eDialogMode.Ambient
    bBackground = forceMode == eDialogMode.Background
  else
    bAmbient = IsAmbient(dialog, nodeID)
    bBackground = IsBackground(dialog, nodeID)
  end
  if bAmbient then
    GameDialog_StopAmbient(dialogID)
    mAmbientID = dialogID
  elseif bBackground then
    table.insert(mBackgroundIDs, dialogID)
  else
    local stopDialog
    if mDialogID and mDialogID ~= dialogID then
      stopDialog = mDialogID
      Game_PopMode(eModeCutscene)
      Callback_CutsceneOnEnd:Run(stopDialog)
    end
    GameDialog_StopAmbient(dialogID)
    Game_PushMode(eModeCutscene)
    mDialogID = dialogID
    Callback_CutsceneOnBegin:Run(dialogID)
    if stopDialog then
      DlgStop(stopDialog)
    end
  end
  Callback_GameDialogOnBegin:Run(dialogID)
end

function GameDialog_OnEnd(dialogID)
  if dialogID == mAmbientID then
    mAmbientID = nil
  elseif table.contains(mBackgroundIDs, dialogID) then
    TableRemove(mBackgroundIDs, dialogID)
  elseif dialogID == mDialogID then
    mDialogID = nil
    Game_PopMode(eModeCutscene)
    Callback_CutsceneOnEnd:Run(dialogID)
  end
  if dialogID == mReticleID then
    mReticleID = nil
    mbDisableChoiceDisplay = false
  end
  Callback_GameDialogOnEnd:Run(dialogID)
end

function GameDialog_OnChoicesAvailable(dialogID)
  if dialogID == mReticleID and mbDisableChoiceDisplay then
    return
  end
  if dialogID ~= mDialogID then
    Print("Dialog:  Not a Cutscene dialog!  Dialog Choices are only allowed during Cutscenes!")
    DlgStop(dialogID)
    return
  end
  local newDialogChoices = DlgGetChoices(dialogID)
  if mDelaySeconds and 0 < mDelaySeconds then
    local accum = 0
    while accum < mDelaySeconds do
      Yield()
      accum = accum + GetFrameTime() * SceneGetTimeScale(Game_GetScene())
    end
  end
  while mDeactivateThread do
    Yield()
  end
  if mTimerThread then
    ThreadKill(mTimerThread)
    mTimerThread = nil
  end
  if mTimerController then
    ControllerKill(mTimerController)
    mTimerController = nil
  end
  local currentMode = Game_GetMode()
  while currentMode ~= eModeCutscene and currentMode ~= eModeDialog do
    Yield()
    currentMode = Game_GetMode()
  end
  mDialogChoices = newDialogChoices
  mVisibleChoices = {}
  mNumPages = 1
  mCurrentPage = 1
  local dialog = DlgGetCurrentDialog(dialogID)
  mExitChoice = nil
  mDefaultChoice = nil
  for i, dlgChoice in pairs(mDialogChoices) do
    local nodeID = DlgEvaluateToNode(dialog, dlgChoice["Choice Object ID"], "exit", false)
    if nodeID then
      mExitChoice = dlgChoice
    end
    dlgChoice.mbNew = DlgChoiceLeadsToUnplayedNode("exchange", dialogID, dlgChoice["Choice ID"], 1)
    if DlgGetObjUserPropsValue(dialog, dlgChoice["Choice Object ID"], "Default Choice") then
      mDefaultChoice = dlgChoice
    end
    dlgChoice.mbDelay = DlgGetObjUserPropsValue(dialog, dlgChoice["Choice Object ID"], "Delayed Choice")
    if not DlgGetObjUserPropsValue(dialog, dlgChoice["Choice Object ID"], "Hidden Choice") then
      if i <= kMaxChoices or mbPagedChoice then
        table.insert(mVisibleChoices, dlgChoice)
      end
      if mbPagedChoice then
        local numPages = math.floor((#mVisibleChoices + 3) / 4)
        if numPages > mNumPages then
          table.insert(mVisibleChoices, #mVisibleChoices - 1, kNextPageChoice)
          table.insert(mVisibleChoices, kPrevPageChoice)
          mNumPages = numPages
        end
      end
    end
  end
  mNumChoices = table.getn(mDialogChoices)
  mNumVisibleChoices = #mVisibleChoices
  if mNumChoices == 1 and mExitChoice then
    mbChoicesExhausted = true
    ActivateChoice(mExitChoice, true)
    return
  end
  mbChoicesExhausted = false
  CursorHide(true, kScene)
  local bDialogMode = currentMode == eModeDialog
  if not bDialogMode then
    Game_PushMode(eModeDialog)
    SceneAdd(kScene)
    while not SceneIsActive(kScene) do
      RenderDelay(1)
      Yield()
    end
    mScene = SceneFind(kScene)
    if Game_IsPaused() then
      SceneHide(mScene, true)
      while Game_IsPaused() do
        Yield()
      end
    end
    SetupButtons()
  else
    InputMapperDeactivate(kInputMap)
  end
  SetChoices(mCurrentPage)
  if not bDialogMode then
    SceneHide(mScene, false)
    ChorePlayAndWait(AgentGetProperty(SceneGetSceneAgent(mScene), kUIChoreOpen))
  end
  InputMapperActivate(kInputMap)
  CursorHide(false, kScene)
  RolloverResetStatus()
  mExchangeTimerController = nil
  if not mbDisableDialogIdle then
    mExchangeTimerController = DlgGetCurPlaybackController(dialogID)
    if mExchangeTimerController then
      mTimerLength = ControllerGetLength(mExchangeTimerController) - ControllerGetTime(mExchangeTimerController)
    end
  end
  if mTimerLength and 0 < mTimerLength then
    mTimerShowController = ChorePlay("ui_hud_timer_show.chore")
    local thread = ThreadStart(function()
      local choreLength = ChoreGetLength("ui_hud_timer_start.chore")
      mTimerController = ChorePlay("ui_hud_timer_start.chore")
      ControllerSetScene(mTimerController, mScene)
      ControllerSetTimeScale(mTimerController, choreLength / mTimerLength)
      ControllerWait(mTimerController)
      mTimerThread = nil
      mTimerController = nil
      if not CoopOnTimer() then
        GameDialog_SelectDefaultChoice()
      end
    end)
    if ThreadIsRunning(thread) then
      mTimerThread = thread
    end
  end
  CoopBegin()
end

function GameDialog_OnStart(dialog, nodeID, instanceID, executionCount)
  local bRestart = false
  local isAmbient, isAmbientLocal = IsAmbient(dialog, nodeID)
  local isBackground, isBackgroundLocal = IsBackground(dialog, nodeID)
  if isAmbient then
    mAmbientFadeOutTime = DlgGetObjUserPropsValue(dialog, nodeID, "Dialog - Ambient Fade Out Time")
    if isAmbientLocal and mAmbientID ~= instanceID then
      bRestart = true
    end
  elseif isBackground then
    if isBackgroundLocal and not table.contains(mBackgroundIDs, instanceID) then
      bRestart = true
    end
  elseif (isAmbientLocal or isBackgroundLocal) and mDialogID ~= instanceID then
    bRestart = true
  end
  if bRestart then
    GameDialog_OnEnd(instanceID)
    GameDialog_OnBegin(instanceID)
  end
end

function GameDialog_OnChoicesNode(dialog, nodeID, instanceID, executionCount)
  mbDisableChoiceDisplay = DlgGetObjUserPropsValue(dialog, nodeID, "Reticle Choices") and instanceID ~= mReticleID
  if mbDisableChoiceDisplay then
    mReticleID = instanceID
  else
    mDelaySeconds = DlgGetObjUserPropsValue(dialog, nodeID, "Choices - Delay")
    mbDisableDialogIdle = DlgGetObjUserPropsValue(dialog, nodeID, "Choices - Disable Dialog Idle")
    mbPagedChoice = DlgGetObjUserPropsValue(dialog, nodeID, "Choices - Paged")
    mTimerLength = nil
    local timerNumber = DlgGetObjUserPropsValue(dialog, nodeID, "Choices - Timer")
    if timerNumber and 0 < timerNumber then
      mTimerLength = timerNumber
    else
      local timerLogic = DlgGetObjUserPropsValue(dialog, nodeID, "Choices - Timer Logic Key")
      if timerLogic and timerLogic ~= "" then
        mTimerLength = LogicGet(timerLogic)
        if mTimerLength and type(mTimerLength) ~= "number" then
          mTimerLength = nil
        end
      end
    end
  end
end

function GameDialog_OnCancelChoice(dialog, nodeID, instanceID, executionCount)
  ActivateChoice()
end

function GameDialog_OnMouseL(event)
  if not (event.agent and Input_UseCursor()) or Game_GetMode() ~= eModeDialog then
    return
  end
  local button = Buttons_OnPress(event, mScene)
  if not button then
    return
  end
  local index = table.find(mChoices, button)
  if index then
    mSelectedIndex = index
    ChooseChoice(mVisibleChoices[GetVisibleChoiceIndex(mCurrentPage, index)])
  end
end

function GameDialog_OnButtonEnter(event)
  if Game_GetMode() ~= eModeDialog then
    return
  end
  local button = Buttons_OnPress(event, mScene)
  if not button then
    return
  end
  local index = table.find(mChoices, button)
  if index then
    mSelectedIndex = index
    ChooseChoice(mVisibleChoices[GetVisibleChoiceIndex(mCurrentPage, index)])
  end
end

function GameDialog_OnButtonX(event)
  if mFrameNumber and mFrameNumber == GetFrameNumber() then
    return
  end
  mFrameNumber = GetFrameNumber()
  if Game_GetMode() ~= eModeDialog or mbCursorMode then
    return
  end
  mSelectedIndex = 1
  local dialogChoice = mVisibleChoices[GetVisibleChoiceIndex(mCurrentPage, mSelectedIndex)]
  if dialogChoice then
    ChooseChoice(dialogChoice)
  end
end

function GameDialog_OnButtonB(event)
  if mFrameNumber and mFrameNumber == GetFrameNumber() then
    return
  end
  mFrameNumber = GetFrameNumber()
  if Game_GetMode() ~= eModeDialog or mbCursorMode then
    return
  end
  mSelectedIndex = 2
  local dialogChoice = mVisibleChoices[GetVisibleChoiceIndex(mCurrentPage, mSelectedIndex)]
  if dialogChoice then
    ChooseChoice(dialogChoice)
  end
end

function GameDialog_OnButtonY(event)
  if mFrameNumber and mFrameNumber == GetFrameNumber() then
    return
  end
  mFrameNumber = GetFrameNumber()
  if Game_GetMode() ~= eModeDialog or mbCursorMode then
    return
  end
  mSelectedIndex = 3
  local dialogChoice = mVisibleChoices[GetVisibleChoiceIndex(mCurrentPage, mSelectedIndex)]
  if dialogChoice then
    ChooseChoice(dialogChoice)
  end
end

function GameDialog_OnButtonA(event)
  if mFrameNumber and mFrameNumber == GetFrameNumber() then
    return
  end
  mFrameNumber = GetFrameNumber()
  if Game_GetMode() ~= eModeDialog or mbCursorMode then
    return
  end
  mSelectedIndex = 4
  local dialogChoice = mVisibleChoices[GetVisibleChoiceIndex(mCurrentPage, mSelectedIndex)]
  if dialogChoice then
    ChooseChoice(dialogChoice)
  end
end

function GameDialog_OnMouseR(event)
  if not Input_UseCursor() or Game_GetMode() ~= eModeDialog or not mbCursorMode then
    return
  end
  if mExitChoice then
    ChooseChoice(mExitChoice)
  end
end

function GameDialog_OnRollOn(event)
  if Game_GetMode() ~= eModeDialog or Input_UseTouch() then
    return
  end
  Buttons_OnRollOn(event, mScene)
end

function GameDialog_OnRollOff(event)
  if Game_GetMode() ~= eModeDialog then
    return
  end
  Buttons_OnRollOff(event, mScene)
end

function GameDialog_OnUp(event)
  if Game_GetMode() ~= eModeDialog then
    return
  end
  Buttons_OnUp(event, mScene)
end

function GameDialog_OnDown(event)
  if Game_GetMode() ~= eModeDialog then
    return
  end
  Buttons_OnDown(event, mScene)
end

function GameDialog_OnLeft(event)
  if Game_GetMode() ~= eModeDialog then
    return
  end
  Buttons_OnLeft(event, mScene)
end

function GameDialog_OnRight(event)
  if Game_GetMode() ~= eModeDialog then
    return
  end
  Buttons_OnRight(event, mScene)
end

function GameDialog_DisableAmbientFadeIn(bDisable)
  mDisableAmbientFadeIn = bDisable
end

Init()
