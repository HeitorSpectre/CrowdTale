local set = {}
set.name = "Project_Online"
set.setName = "Project_Online"
set.descriptionFilenameOverride = ""
set.logicalName = "<Project>"
set.logicalDestination = "<>"
set.priority = 51
set.localDir = _currentDirectory
set.enableMode = "constant"
set.version = "trunk"
set.descriptionPriority = 51
set.gameDataName = "Project_Online Game Data"
set.gameDataPriority = 51
set.gameDataEnableMode = "constant"
set.localDirIncludeBase = true
set.localDirRecurse = false
set.localDirIncludeOnly = nil
set.localDirExclude = { "Packaging/", "_dev/" }
set.gameDataArchives = {
  _currentDirectory .. "Fables_pc_Project_Online.ttarch2"
}
RegisterSetDescription(set)
