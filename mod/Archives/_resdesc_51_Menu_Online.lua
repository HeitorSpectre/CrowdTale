local set = {}
set.name = "Menu_Online"
set.setName = "Menu_Online"
set.descriptionFilenameOverride = ""
set.logicalName = "<Menu>"
set.logicalDestination = "<>"
set.priority = 51
set.localDir = _currentDirectory
set.enableMode = "bootable"
set.version = "trunk"
set.descriptionPriority = 51
set.gameDataName = "Menu_Online Game Data"
set.gameDataPriority = 51
set.gameDataEnableMode = "constant"
set.localDirIncludeBase = true
set.localDirRecurse = false
set.localDirIncludeOnly = nil
set.localDirExclude = { "Packaging/", "_dev/" }
set.gameDataArchives = {
  _currentDirectory .. "Fables_pc_Menu_Online.ttarch2"
}
RegisterSetDescription(set)
