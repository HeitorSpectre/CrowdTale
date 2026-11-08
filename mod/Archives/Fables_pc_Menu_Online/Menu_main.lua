require("uiz.lua")
require("uiz_Background.lua")
require("uiz_Title.lua")
require("uiz_ConsoleButtons.lua")
require("MenuWidget_NewButton.lua")
require("Menu_Fablespedia.lua")
require("Menu_Achievements.lua")
require("Menu_Settings.lua")
require("Menu_Chapters.lua")
require("Menu_SaveSlots.lua")
require("Menu_Extras.lua")
require("uiz_popup.lua")
require("SaveLoad.lua")
require("TTChoicesWatcher.lua")
require("Widget_FeedDisplay.lua")
require("RichPresence.lua")
require("Menu_Store.lua")
require("ViewTracker.lua")
require("Menu_DebugOptions.lua")
require("Menu_PlayDemo.lua")
require("Menu_Online.lua")
if IsToolBuild() then
  function ConnectedContentManager_UpdateDLC()
    print("ConnectedContentManager_UpdateDLC Updating")

    Sleep(2)
  end
end
local mIsMenuBlocked = false
local mLoggedInController

function Menu_UnloadStuff()
  local slot = SaveLoad_GetSlot()
  local slotnum = string.sub(slot, string.find(slot, "%d+"))
  local exclusion = "saveslot" .. slotnum .. "[^0-9]"
  local check = ResourceLocationGetNames("<User>", "*saveslot*.bundle")
  if check == nil then
    return
  end
  for i, v in ipairs(check) do
    if not string.find(v, exclusion) then
      Unload(v)
    end
  end
end

Callback_OnLoad:Add(Menu_UnloadStuff)
local mMenu_Chapters_LastEpisode = 0
local ActivateFunction
local kProjGeneralProp = "project_general.prop"

function Menu_Set_Chapters_LastEpisode(episode)
  mMenu_Chapters_LastEpisode = episode
end

function Menu_Get_Chapters_LastEpisode()
  return mMenu_Chapters_LastEpisode
end

function Menu_StartEpisode(episode)
  Menu_UnloadStuff()
  ViewTracker_MarkViewed("Menu_Chapters", episode)
  ViewTracker_SaveViewed()
  SubProject_StartEpisode(episode)
end

function GetIsMenuBlocked()
  return mIsMenuBlocked
end

function Menu_ShouldShowExitButton()
  return not IsPlatformPS4() and not IsPlatformPS5() and not IsPlatformXboxOne() and not IsPlatformNX()
end

function Menu_ExecuteButton(command)
  if GetIsMenuBlocked() then
    return
  end
  if command == "ui_buttonPlay" then
    if IsPlatformXboxOne() and not IsUserSignedIn(1) then
      Menu_StartEpisode("Fables101")
    else
      Menu_Chapters()
    end
  elseif command == "ui_Achievements" then
    PlatformOpenAchievementUI()
  elseif command == "ui_buttonExtras" then
    Menu_Extras()
  elseif command == "ui_buttonCoop" then
    Menu_Online()
  elseif command == "ui_buttonChangeSave" then
    Menu_SaveSlots(false)
  elseif command == "ui_buttonSettings" then
    Menu_Settings(false)
  elseif command == "ui_exit" then
    UIZ_Confirm(UIZ_GetText("popup_quit_message"), UIZ_GetText("popup_quit_header"), "Menu_Main_Quit()", "label_yes", "label_no")
  elseif command == "ui_changeProfile" and rawget(_G, "PlatformOpenAccountPickerUI") then
    PlatformOpenAccountPickerUI()
  end
end

function Menu_Main()
  Menu_Online_WatchInvites()
  if (not rawget(_G, "IsSGFDemo") or not IsSGFDemo()) and IsTTUser() then
    SaveLoad_Choices_TryUpload()
  end
  if ResourceExists(kProjGeneralProp) and PropertyGet(kProjGeneralProp, kDeletedScenesEnabled) ~= false then
    PropertySet(kProjGeneralProp, kDeletedScenesEnabled, false)
  end
  local menu = UIZ_ListMenu("ui_menu_main", "Menu_Main.scene", 0.05)
  AgentSetProperty("ui_menu_main", "Menu Alignment", "Left")
  UIZ_ConsoleButton("facebutton_down", "navhelp_select")
  ChoiceStats_Init()

  function menu:populate()
    local episodes = {}
    for i = 1, GetPreferences()["Menu episode count"] do
      table.insert(episodes, "Fables10" .. i)
    end
    local currentEpisode = SaveLoad_GetEpisode()
    local currentEpisodeOwned = true
    local slots = SaveLoad_GetSlotNames()
    local slotsExist
    if slots ~= nil then
      slotsExist = table.getn(slots) > 0
    else
      slotsExist = false
    end
    local gameStarted = SaveLoad_SavesExist()
    local gameFinished = SaveLoad_IsFinished()
    if IsPlatformXboxOne() and not IsUserSignedIn(1) then
      NewButton("ui_buttonPlay", "label_play", "Menu_ExecuteButton('ui_buttonPlay')")
    else
      NewButton("ui_buttonPlay", "label_play", "Menu_ExecuteButton('ui_buttonPlay')", Menu_Chapters_IsNew())
    end
    local bIsSGFDemo = rawget(_G, "IsSGFDemo") and IsSGFDemo()
    if bIsSGFDemo then
      NewButton("ui_buttonExtras", "label_extras", "", false, true)
    else
      NewButton("ui_buttonExtras", "label_extras", "Menu_ExecuteButton('ui_buttonExtras')", Menu_Extras_IsNew())
    end
    Menu_Online_Button("ui_buttonCoop", "coop_button", "Menu_ExecuteButton('ui_buttonCoop')")
    if IsRegistered() then
      if IsPlatformXboxOne() and not IsUserSignedIn(1) then
        print("No Profile for Player 1")
      else
        NewButton("ui_buttonChangeSave", "label_savefiles", "Menu_ExecuteButton('ui_buttonChangeSave')")
      end
    end
    NewButton("ui_buttonSettings", "label_settings", "Menu_ExecuteButton('ui_buttonSettings')")
    if Menu_ShouldShowExitButton() then
      NewButton("ui_exit", "label_exitgame", "Menu_ExecuteButton('ui_exit')")
    end
    if AgentExists("ui_menu_main_username") and IsPlatformXboxOne() then
      local username
      if rawget(_G, "PlatformGetUserName") then
        username = PlatformGetUserName()
      end
      AgentSetProperty("ui_menu_main_username", "Text String", username or "")
    end
    if rawget(_G, "GetPlatformVersionID") then
      local version = GetPlatformVersionID()
      local isValidVersion = version ~= nil and version ~= ""
      if AgentExists("ui_menu_main_version") and isValidVersion then
        Print("Platform Version is: " .. version)
        AgentSetProperty("ui_menu_main_version", "Text String", version)
      else
        Print("Could not display version information. IsValidVersion: " .. Ternary(isValidVersion, "true", "false"))
      end
    else
      AgentSetProperty("ui_menu_main_version", "Text String", "")
    end
    if IsPlatformXboxOne() then
      NewButton("ui_changeProfile", "label_selectProfile", "Menu_ExecuteButton('ui_changeProfile')")
    end
  end

  if menu.activate then
    ActivateFunction = menu.activate
  end

  function menu:activate()
    local popup = AgentFind("popup_parent")
    if popup ~= nil and popup.PS3DownloadNoSoundHack then
      popup.PS3DownloadNoSoundHack = false
    end
    if ActivateFunction then
      ActivateFunction(menu)
    end
    RichPresence_Set("richPresence_mainMenu", false)
    if rawget(_G, "PlatformPlayerSessionEnd") then
      PlatformPlayerSessionEnd()
    end
    if not rawget(_G, "IsSGFDemo") or not IsSGFDemo() then
      if IsTTUser() then
        mLoggedInController = nil
      else
        mLoggedInController = ChorePlay("ui_menu_ttaccount_notLoggedIn.chore")
      end
      ThreadStart(function()
        if mLoggedInController == nil then
          Sleep(0.5)
          ChoicesWatcher_Request_ShowIcon()
        else
          while ControllerIsPlaying(mLoggedInController) do
            Yield()
          end
          ChoicesWatcher_Request_ShowIcon()
          mLoggedInController = nil
        end
      end)
    end
  end

  UIZ_ActivateMenu("ui_menu_main")
  Yield()
  AgentSetProperty("logic_music", "Music - File", "mus_ui_menu_main.wav")
  if IsPlatformXboxOne() then
    AgentSetPosY("ui_menu_main_consoleButtons", -2.530762)
    if LangGetCurLanguage() == "spanish" then
      AgentSetPosY("ui_menu_main", 0.5)
    end
  end
end

local keyChore

function StartKeyArt()
  if SceneIsActive("keyart.scene") then
    SceneHide("keyart.scene", false)
    if not ControllerIsPlaying(keyChore) then
    end
  else
    RenderDelay(1)
    SceneAdd("keyart.scene", "StartKeyArt")
  end
end

function StopKeyArt()
  if SceneIsActive("keyart.scene") then
    SceneHide("keyart.scene", true)
  end
  if ControllerIsPlaying(keyChore) then
    ControllerKill(keyChore)
  end
end

function StartHorizontalStripe()
  if SceneIsActive("ui_menu_horizontalbar.scene") then
    SceneHide("ui_menu_horizontalbar.scene", false)
    ChorePlay("ui_menu_horizontalBar_show2.chore")
  else
    SceneAdd("ui_menu_horizontalbar.scene", "StartHorizontalStripe")
  end
end

function StopHorizontalStripe()
  if SceneIsActive("ui_menu_horizontalbar.scene") and not SceneIsHidden("ui_menu_horizontalbar.scene") then
    ThreadStart(function()
      ChorePlayAndWait("ui_menu_horizontalbar_hide2.chore")
    end)
  end
end

function Menu_Main_PlaySellScreenMovie(bIsDemo)
  SceneHide("keyart.scene", true)
  SceneHide("ui_menu_horizontalbar.scene", true)
  SceneAdd("ui_menu_sellscreen.scene")
  RenderDelay(1)
  Yield()
  AgentSetProperty("logic_music", "Music - File", "mus_ui_menu_sellscreen.wav")
  ChorePlay("ui_menu_background_main_show.chore")
  ChorePlayAndWait("ui_menu_sellscreen_show.chore")
end

function Menu_Main_Start()
  local kPreloadList = {
    "ui_menu_button_arrow_right_down.d3dtx",
    "ui_menu_coverflow_right.wav",
    "SceneGlow_QHi.t3fxb",
    "ui_coverflow_deselect.chore",
    "ui_menu_coverflow_chapter_continue_out.chore",
    "sk54_idle_bigbyDoubtfulA.chore",
    "sk54_idle_bigbyDoubtfulA.anm",
    "sk54_bigbyDoubtfulA.ptable",
    "ui_menu_navHelp_show.chore",
    "Mesh_SKN_BMP_QHi.t3fxb",
    "Mesh_SKN_BMP_DTL_SDTL_QHi.t3fxb",
    "Mesh_TOON_QHi.t3fxb",
    "SceneToonOutline2_QHi.t3fxb",
    "Mesh_BMP_DTL_TOON_SDTL_QHi.t3fxb",
    "SceneGBufferAlphaTest_SKN_QHi.t3fxb",
    "SceneShadowMapAlpha_SKN_QHi.t3fxb",
    "SceneVelocityAlpha_SKN_QHi.t3fxb",
    "SceneGlowAlphaTest_SKN_QHi.t3fxb",
    "SceneGlowAlphaBlend_SKN_QHi.t3fxb",
    "ui_menu_coverflow_chapter_diorama_background2.d3dtx",
    "Mesh_DTL_TOON_QHi.t3fxb",
    "Mesh_SSUV_QHi.t3fxb",
    "Mesh_LGT_SDW_DTL_TDTL_TOON_QHi.t3fxb",
    "Mesh_LGT_SDW_QHi.t3fxb",
    "Mesh_LGT_SDW_DTL_TOON_QHi.t3fxb"
  }
  for _, item in ipairs(kPreloadList) do
    LoadAsync(item)
  end
  RenderSetAspectRatio(1.7777778)
  SceneAdd("ui_menu_horizontalbar.scene")
  SceneHide("ui_menu_horizontalbar.scene", false)
  SceneAdd("keyart.scene", "StartKeyArt")
  SceneHide("keyart.scene", true)
  RenderDelay(1)
  Yield()
  SceneAdd("ui_menu_background_main.scene")
  SceneAdd("ui_menu_foreground.scene")
  SceneAdd("Menu_Main_Alias.scene")
  if not rawget(_G, "IsSGFDemo") or not IsSGFDemo() then
    SceneAdd("ui_menu_fullvideo.scene")
  end
  SceneAdd("ui_popup_connectionNotification.scene")
  RenderDelay(1)
  Yield()
  local aspectRatio = RenderGetAspectRatio()
  if 1.7 < aspectRatio then
    ChorePlay("ui_menu_widescreen_main.chore")
  end
  if rawget(_G, "IsSGFDemo") and IsSGFDemo() then
    Menu_Main()
    ChorePlayAndWait("ui_menu_background_main_show.chore")
    return
  end
  local bShowTTAccountFlow = false
  local prefs = GetPreferences()
  if not PropertyExists(prefs, "FTUE") then
    PropertyCreate(prefs, "FTUE", "bool", true)
    SavePrefs()
    CreateEventLogEvent("First Boot", "true", true)
    bShowTTAccountFlow = true
  end
  if bShowTTAccountFlow then
    mIsMenuBlocked = true
    Menu_Main()
    ChorePlay("ui_menu_background_main_show.chore")
    Sleep(0.3)
    Menu_TelltaleAccount(true)
    mIsMenuBlocked = false
  else
    Menu_Main()
    ChorePlayAndWait("ui_menu_background_main_show.chore")
  end
end

function Menu_Main_Quit()
  EngineQuit()
end

SceneOpen("Menu_Main.scene", "Menu_Main_Start")
