Set WshShell = CreateObject("WScript.Shell")
' Get directory of current script to resolve path safely
strPath = CreateObject("Scripting.FileSystemObject").GetParentFolderName(Wscript.ScriptFullName)
WshShell.CurrentDirectory = strPath
' Run Node agent silently in background (0 hides window)
WshShell.Run "node src/server.js", 0, false
