; MacUnZip 安装钩子：写入资源管理器右键菜单（当前用户，不需要管理员权限）。
; Windows 11 中这些菜单位于“显示更多选项”里。

!macro NSIS_HOOK_POSTINSTALL
  WriteRegStr HKCU "Software\Classes\*\shell\MacUnZip" "MUIVerb" "MacUnZip"
  WriteRegStr HKCU "Software\Classes\*\shell\MacUnZip" "Icon" "$INSTDIR\MacUnZip.exe"
  WriteRegStr HKCU "Software\Classes\*\shell\MacUnZip" "SubCommands" ""
  WriteRegStr HKCU "Software\Classes\*\shell\MacUnZip\shell\01extract" "" "解压到此处"
  WriteRegStr HKCU "Software\Classes\*\shell\MacUnZip\shell\01extract" "AppliesTo" "System.FileExtension:=.zip OR System.FileExtension:=.rar OR System.FileExtension:=.7z OR System.FileExtension:=.tar OR System.FileExtension:=.gz OR System.FileExtension:=.tgz OR System.FileExtension:=.xz OR System.FileExtension:=.bz2 OR System.FileExtension:=.zst"
  WriteRegStr HKCU "Software\Classes\*\shell\MacUnZip\shell\01extract\command" "" '"$INSTDIR\MacUnZip.exe" --extract-here "%1"'
  WriteRegStr HKCU "Software\Classes\*\shell\MacUnZip\shell\02extractto" "" "解压到…"
  WriteRegStr HKCU "Software\Classes\*\shell\MacUnZip\shell\02extractto" "AppliesTo" "System.FileExtension:=.zip OR System.FileExtension:=.rar OR System.FileExtension:=.7z OR System.FileExtension:=.tar OR System.FileExtension:=.gz OR System.FileExtension:=.tgz OR System.FileExtension:=.xz OR System.FileExtension:=.bz2 OR System.FileExtension:=.zst"
  WriteRegStr HKCU "Software\Classes\*\shell\MacUnZip\shell\02extractto\command" "" '"$INSTDIR\MacUnZip.exe" --extract-to "%1"'
  WriteRegStr HKCU "Software\Classes\*\shell\MacUnZip\shell\03preview" "" "打开…"
  WriteRegStr HKCU "Software\Classes\*\shell\MacUnZip\shell\03preview" "AppliesTo" "System.FileExtension:=.zip OR System.FileExtension:=.rar OR System.FileExtension:=.7z OR System.FileExtension:=.tar OR System.FileExtension:=.gz OR System.FileExtension:=.tgz OR System.FileExtension:=.xz OR System.FileExtension:=.bz2 OR System.FileExtension:=.zst"
  WriteRegStr HKCU "Software\Classes\*\shell\MacUnZip\shell\03preview\command" "" '"$INSTDIR\MacUnZip.exe" --open "%1"'
  WriteRegStr HKCU "Software\Classes\*\shell\MacUnZip\shell\04quick" "" "快速压缩"
  WriteRegStr HKCU "Software\Classes\*\shell\MacUnZip\shell\04quick\command" "" '"$INSTDIR\MacUnZip.exe" --quick-compress "%1"'
  WriteRegStr HKCU "Software\Classes\*\shell\MacUnZip\shell\05compress" "" "压缩…"
  WriteRegStr HKCU "Software\Classes\*\shell\MacUnZip\shell\05compress\command" "" '"$INSTDIR\MacUnZip.exe" --compress "%1"'
  WriteRegStr HKCU "Software\Classes\Directory\shell\MacUnZip" "MUIVerb" "MacUnZip"
  WriteRegStr HKCU "Software\Classes\Directory\shell\MacUnZip" "Icon" "$INSTDIR\MacUnZip.exe"
  WriteRegStr HKCU "Software\Classes\Directory\shell\MacUnZip" "SubCommands" ""
  WriteRegStr HKCU "Software\Classes\Directory\shell\MacUnZip\shell\01quick" "" "快速压缩"
  WriteRegStr HKCU "Software\Classes\Directory\shell\MacUnZip\shell\01quick\command" "" '"$INSTDIR\MacUnZip.exe" --quick-compress "%1"'
  WriteRegStr HKCU "Software\Classes\Directory\shell\MacUnZip\shell\02compress" "" "压缩…"
  WriteRegStr HKCU "Software\Classes\Directory\shell\MacUnZip\shell\02compress\command" "" '"$INSTDIR\MacUnZip.exe" --compress "%1"'
  System::Call 'shell32::SHChangeNotify(i 0x08000000, i 0, i 0, i 0)'
!macroend

!macro NSIS_HOOK_PREUNINSTALL
  DeleteRegKey HKCU "Software\Classes\*\shell\MacUnZip"
  DeleteRegKey HKCU "Software\Classes\Directory\shell\MacUnZip"
  System::Call 'shell32::SHChangeNotify(i 0x08000000, i 0, i 0, i 0)'
!macroend
