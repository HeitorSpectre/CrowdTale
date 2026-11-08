local set = {}
set.name = "ReBase_Online"
set.setName = "ReBase_Online"
set.descriptionFilenameOverride = ""
set.logicalName = "<ReBase>"
set.logicalDestination = "<>"
set.priority = 61
set.localDir = _currentDirectory
set.enableMode = "bootable"
set.version = "trunk"
set.descriptionPriority = 61
set.gameDataName = "ReBase_Online Game Data"
set.gameDataPriority = 61
set.gameDataEnableMode = "constant"
set.localDirIncludeBase = true
set.localDirRecurse = false
set.localDirIncludeOnly = nil
set.localDirExclude = { "Packaging/", "_dev/" }
set.gameDataArchives = {
  _currentDirectory .. "Fables_pc_ReBase_Online.ttarch2"
}
RegisterSetDescription(set)


