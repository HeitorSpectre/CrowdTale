require("uiz.lua")
require("uiz_title.lua")
require("uiz_background.lua")
require("uiz_consoleButtons.lua")
require("uiz_popup.lua")
require("MenuWidget_NewButton.lua")
require("Menu_ControlsHelp.lua")
require("Menu_Fablespedia.lua")
require("Menu_Achievements.lua")
require("Menu_Settings.lua")
require("Menu_Stats.lua")
require("Menu_Downloads.lua")
require("RichPresence.lua")
require("Menu_Online.lua")
mbIsClosing = false
mbIsOpening = false
if IsToolBuild() then
  require("Menu_Pause_Debug.lua")
end
local kScene = "Menu_Pause.scene"
local ActivateFunction, DeactivateFunction

function Menu_Pause_RestartPopup()
  UIZ_Confirm("Do you want to restart the current episode?", "RESTART EPISODE", "Menu_Pause_Restart()")
end

function Menu_Pause_ReturnToMainPopup()
  UIZ_Confirm(UIZ_GetText("popup_mainmenu_message"), UIZ_GetText("popup_mainmenu_header"), "Menu_Pause_Main()")
end

function Menu_Pause_Restart()
  if mbIsClosing then
    return
  end
  mbIsClosing = true
  InputMapperDeactivate("Button.imap")
  InputMapperDeactivate("Menu_ConsoleButton.imap")
  Menu_Pause_Hide()
  SubProject_Switch("Menu", "Menu_Main.lua")
  SubProject_Switch("Fables101", "FabletownAndersen.lua")
end

function Menu_Pause_Main()
  if mbIsClosing then
    return
  end
  mbIsClosing = true
  InputMapperDeactivate("Button.imap")
  InputMapperDeactivate("Menu_ConsoleButton.imap")
  Menu_Pause_Hide()
  Game_PrepareForMainMenu()
  SubProject_Switch("Menu", "Menu_Main.lua")
end

function Menu_Pause_Close()
  print("Menu_Pause_Close()")
  if gCoopBoxUp then
    return
  end
  if mbIsOpening then
    return
  end
  if mbIsClosing then
    return
  end
  mbIsClosing = true
  UIZ_PopMenu()
  InputMapperDeactivate("Button.imap")
  InputMapperDeactivate("Menu_ConsoleButton.imap")
  Menu_Pause_Hide()
  Menu_Close()
end

function Menu_Pause_Hide()
  ChorePlayAndWait("ui_menu_background_pause_hide.chore")
end

function Debug_UnlockChapters(epNum)
  if epNum == nil then
    epNum = SubProject_GetEpisodeNumber() or 101
  end
  local episode = "Fables" .. epNum
  Print("Unlocking Chapters for episode: " .. episode)
  if epNum == 101 then
    SaveLoad_Checkpoint("env_fabletownandersen_intro.dlog", "cs_enter", "chk_start101")
    SaveLoad_Checkpoint("env_fabletownWoodlandBuilding.dlog", "cs_enter", "chk_bigbyApt")
    SaveLoad_Checkpoint("env_businessoffice.dlog", "cs_enter", "chk_businessOffice")
    SaveLoad_Checkpoint("env_fabletownWoodlandBuilding.dlog", "cs_enter", "chk_theChoices")
    SaveLoad_Checkpoint("env_andersenWoodsmanApt.dlog", "cs_enter", "chk_woodsmanAptDay")
    SaveLoad_Checkpoint("env_faithApartment.dlog", "cs_enter", "chk_faithsApt")
    SaveLoad_Checkpoint("env_trollBar.dlog", "cs_enter", "chk_tripTrapBar")
  elseif epNum == 102 then
    SaveLoad_Checkpoint("env_policestationinterrogationroom.dlog", "cs_enter", "chk_policeStation")
    SaveLoad_Checkpoint("env_fabletown_woodlandsCell.dlog", "cs_enter", "chk_cell")
    SaveLoad_Checkpoint("env_businessoffice_QuestionTJ.dlog", "cs_enter", "chk_businessOffice102")
    SaveLoad_Checkpoint("env_puddinpie.dlog", "cs_enter", "chk_puddinPie")
    SaveLoad_Checkpoint("env_openarms.dlog", "cs_enter", "chk_openArms")
    SaveLoad_Checkpoint("env_openArmsUpstairs.dlog", "cs_enter", "chk_murderRoom")
  elseif epNum == 103 then
    SaveLoad_Checkpoint("env_openArmsLobby.dlog", "cs_enter", "chk_openArms103")
    SaveLoad_Checkpoint("env_buckinghamBridge_fight.dlog", "cs_enter", "chk_bridge")
    SaveLoad_Checkpoint("env_businessOffice.dlog", "cs_enter", "chk_businessOffice103")
    SaveLoad_Checkpoint("env_craneApt.dlog", "cs_enter", "chk_craneApt")
    SaveLoad_Checkpoint("env_tweedleOffice.dlog", "cs_enter", "chk_tweedleOffice")
    SaveLoad_Checkpoint("env_barTripTrap.dlog", "cs_enter", "chk_tripTrap103")
    SaveLoad_Checkpoint("env_greenleafApt.dlog", "cs_enter", "chk_greenLeaf")
    SaveLoad_Checkpoint("env_puddingAndPie.dlog", "cs_enter", "chk_puddinPie103")
  elseif epNum == 104 then
    SaveLoad_Checkpoint("env_bigbyApartment.dlog", "cs_enter", "chk_bigbyApt104")
    SaveLoad_Checkpoint("env_BeautyBeastApt.dlog", "cs_enter", "chk_beautyBeastApt")
    SaveLoad_Checkpoint("env_businessOffice.dlog", "cs_enter", "chk_businessOffice104")
    SaveLoad_Checkpoint("env_ButcherShop.dlog", "cs_enter", "chk_butcherShopTF1")
    SaveLoad_Checkpoint("env_ButcherShop.dlog", "cs_enter", "chk_butcherShopTF2")
    SaveLoad_Checkpoint("env_PawnShop.dlog", "cs_enter", "chk_pawnShopTF1")
    SaveLoad_Checkpoint("env_PawnShop.dlog", "cs_enter", "chk_pawnShopTF2")
    SaveLoad_Checkpoint("env_CrookedManLair.dlog", "cs_enter", "chk_crookedLair")
  elseif epNum == 105 then
    SaveLoad_Checkpoint("env_crookedManLair.dlog", "cs_enter", "chk_crookedLair105")
    SaveLoad_Checkpoint("env_streetChase.dlog", "cs_enter", "chk_streetChase")
    SaveLoad_Checkpoint("env_puddingNPie.dlog", "cs_enter", "chk_puddinPie105First")
    SaveLoad_Checkpoint("env_foundryOffice.dlog", "cs_enter", "chk_foundryOffice")
    SaveLoad_Checkpoint("env_witchingWellTrial.dlog", "cs_enter", "chk_witchingWell105")
    SaveLoad_Checkpoint("env_businessOffice.dlog", "cs_enter", "chk_businessOffice105")
  end
end

function Menu_Pause()
  local menu = UIZ_ListMenu("ui_menu_pause", kScene, 0.05)
  AgentSetProperty("ui_menu_pause", "Menu Alignment", "Left")
  local backButton = UIZ_BackButton("Menu_Pause_Close()")
  UIZ_ConsoleButton("facebutton_down", "navhelp_select")
  UIZ_ConsoleButton("facebutton_right", "navhelp_resumeGame", "Menu_Pause_Close()")
  ChoiceStats_Init()

  function menu:populate()
    NewButton("ui_buttonResume", "label_resumegame", "Menu_Pause_Close()")
    NewButton("ui_buttonSettings", "label_settings", "Menu_Settings(true)")
    Menu_Online_Button("ui_buttonCoopPause", "coop_button", "Menu_Online()")
    if rawget(_G, "IsSGFDemo") and IsSGFDemo() then
      local restartButton = NewButton("ui_buttonRestart", "", "Menu_Pause_RestartPopup()")
      AgentSetProperty(restartButton, "Text String", "RESTART")
    end
    NewButton("ui_buttonMain", "label_mainmenu", "Menu_Pause_ReturnToMainPopup()")
    if (not rawget(_G, "IsSGFDemo") or not IsSGFDemo()) and (IsPlatformMac() or IsPlatformPC() and not IsPlatformPS4() and not IsPlatformPS5() and not IsPlatformXboxOne() and not IsPlatformNX()) then
      NewButton("ui_exit", "label_exitgame", "UIZ_Confirm(UIZ_GetText('popup_quit_pause_message'), UIZ_GetText('popup_quit_pause_header'), 'EngineQuit()', 'label_yes', 'label_no')")
    end
    if not rawget(_G, "IsShipping") or not IsShipping() then
      local button = NewButton("ui_buttonUnlockChapters", "", "Debug_UnlockChapters()")
      AgentSetProperty(button, "Text String", "DEBUG: Unlock Chapters")
    end
  end

  if menu.activate then
    ActivateFunction = menu.activate
  end

  function menu:activate()
    if ActivateFunction then
      ActivateFunction(menu)
    end
    RichPresence_Set("richPresence_pauseMenu", false)
    if rawget(_G, "PlatformPlayerSessionStart") then
      PlatformPlayerSessionPause()
    end
    UIZ_BackButton("Menu_Pause_Close()")
    if not PlatformHasTouch() then
      AgentSetProperty(backButton, "Text Dialog 2.0 Node Name", "navhelp_resumeGame")
    end
  end

  if menu.deactivate then
    DeactivateFunction = menu.deactivate
  end

  function menu:deactivate()
    if DeactivateFunction then
      DeactivateFunction(menu)
    end
    PropertyRemove(backButton.mProps, "Text Dialog 2.0 Node Name")
  end

  SceneAdd("ui_menu_foreground.scene")
  SceneAdd("ui_menu_background_pause.scene")
  RenderDelay(1)
  UIZ_PushMenu()
end

function StartHorizontalStripe()
  if SceneIsActive("ui_menu_horizontalbar.scene") then
    SceneHide("ui_menu_horizontalbar.scene", false)
    ChorePlay("ui_menu_horizontalBar_show.chore")
  else
    SceneAdd("ui_menu_horizontalbar.scene", "StartHorizontalStripe")
  end
end

function StopHorizontalStripe()
  if SceneIsActive("ui_menu_horizontalbar.scene") and not SceneIsHidden("ui_menu_horizontalbar.scene") then
    ThreadStart(function()
      ChorePlayAndWait("ui_menu_horizontalbar_hide.chore")
      SceneHide("ui_menu_horizontalbar.scene", true)
    end)
  end
end

local mHiddenScenes = {}
local mCoopBoxBuild

function Menu_Pause_OpenCoopBox(build)
  if gCoopBoxUp or mbIsOpening or mbIsClosing or Game_GetMode() == eModeMenu then
    return false
  end
  gCoopBoxUp = true
  mCoopBoxBuild = build
  Menu_Open()
  return true
end

function Menu_Pause_CloseCoopBox()
  if not gCoopBoxUp then
    return
  end
  while mbIsOpening do
    Yield()
  end
  gCoopBoxUp = false
  mbIsClosing = true
  UIZ_PopMenu()
  UIZ_ClearStack()
  InputMapperDeactivate("Button.imap")
  InputMapperDeactivate("Menu_ConsoleButton.imap")
  Menu_Pause_Hide()
  Menu_Close()
end
local mMusicController

function Menu_Open()
  if mbIsClosing then
    return
  end
  if mbIsOpening then
    return
  end
  print("opening scene")
  mbIsOpening = true
  local musicAgent = AgentFind("logic_music")
  AgentSetProperty(musicAgent, "Music - Controller Scene", "logic.scene")
  Game_PushMode(eModeMenu)
  SceneAdd(kScene)
  local prefs = GetPreferences()
  local dimensions = prefs.Windowed and prefs["Window Size"] or prefs["Fullscreen Size"]
  RenderSetAspectRatio(dimensions.x / dimensions.y)
  while not SceneIsActive(kScene) do
    RenderDelay(1)
    Yield()
  end
  SceneHide(kScene, true)
  local pausedScenes = Game_GetPausedScenes()
  for _, scene in ipairs(pausedScenes) do
    if scene and not SceneIsHidden(scene) then
      SceneHide(scene, true)
      table.insert(mHiddenScenes, scene)
    end
  end
  if mCoopBoxBuild then
    local build = mCoopBoxBuild
    mCoopBoxBuild = nil
    SceneAdd("ui_menu_foreground.scene")
    SceneAdd("ui_menu_background_pause.scene")
    RenderDelay(1)
    UIZ_ClearStack()
    build()
  else
    Menu_Pause()
  end
  ChorePlay("ui_menu_background_pause_show.chore")
  print("scene opened")
  mbIsOpening = false
  CursorHide(false, kScene)
  SceneHide(kScene, false)
  Yield()
  mMusicController = ChorePlay("ui_menu_pausemusic.chore", 20000)
  ControllerSetLooping(mMusicController, true)
  local previousMusicController = musicAgent.musicController
  if previousMusicController then
    while ControllerGetContribution(previousMusicController) > 0 do
      Yield()
    end
  end
  PropertyRemove(AgentGetProperties("logic_music"), "Music - Controller Scene")
end

function Menu_Close()
  if mbIsOpening then
    return
  end
  print("closing scene")
  RichPresence_RestoreLogic()
  if rawget(_G, "PlatformPlayerSessionResume") then
    PlatformPlayerSessionResume()
  end
  for _, scene in ipairs(mHiddenScenes) do
    SceneHide(scene, false)
  end
  SceneHide(kScene, true)
  SceneRemove(kScene)
  SceneRemove("ui_menu_foreground.scene")
  SceneRemove("ui_menu_background_pause.scene")
  RenderSetAspectRatio(1.7777778)
  CursorHide(false, kScene)
  ControllerKill(mMusicController)
  mMusicController = nil
  repeat
    Yield()
  until not SceneIsActive("Menu_Pause.scene")
  repeat
    Yield()
  until not SceneIsActive("ui_menu_foreground.scene")
  repeat
    Yield()
  until not SceneIsActive("ui_menu_background_pause.scene")
  mbIsClosing = false
  print("scene is closed")
  Game_PopMode(eModeMenu)
end

function Menu_Pause_FromDebug()
  SceneHide("ui_debug.scene", true)
  SceneAdd("Menu_Pause.scene")
  local prefs = GetPreferences()
  local dimensions = prefs.Windowed and prefs["Window Size"] or prefs["Fullscreen Size"]
  RenderSetAspectRatio(dimensions.x / dimensions.y)
  Yield()
  Menu_Pause()
  ChorePlay("ui_menu_background_pause_show.chore")
end
