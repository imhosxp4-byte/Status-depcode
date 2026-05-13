Dim sh, installDir
installDir = CreateObject("WScript.Shell").ExpandEnvironmentStrings("%USERPROFILE%") & "\Desktop\Status-Depcode"

Set sh = CreateObject("WScript.Shell")
sh.CurrentDirectory = installDir
sh.Run "cmd /c node server.js >> """ & installDir & "\server.log"" 2>&1", 0, False
