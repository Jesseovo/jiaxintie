#define AppName "夹心贴"
[Setup]
AppId={{E67B58A0-D7AC-4D99-9B3C-27848A33DD94}
AppName={#AppName}
AppVersion=1.0.2
AppPublisher=夹心贴
DefaultDirName={localappdata}\Programs\JiaXinTie
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
DisableDirPage=no
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=dist\1.0.2
OutputBaseFilename=夹心贴-安装程序-1.0.2
SetupIconFile=assets\app.ico
UninstallDisplayIcon={app}\夹心贴.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
AppMutex=Local\JiaXinTie.Singleton.v1
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "chinesesimp"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "快捷方式："; Flags: unchecked

[Files]
Source: "dist\1.0.2\夹心贴.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "dist\1.0.2\使用说明.md"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\夹心贴"; Filename: "{app}\夹心贴.exe"
Name: "{autodesktop}\夹心贴"; Filename: "{app}\夹心贴.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\夹心贴.exe"; Description: "启动夹心贴"; Flags: nowait postinstall skipifsilent

[Code]
var SavePage: TInputDirWizardPage;

procedure InitializeWizard;
begin
  SavePage := CreateInputDirPage(wpSelectDir, '选择截图保存文件夹',
    '之后按保存快捷键，图片就直接保存在这里。',
    '手动保存的截图长期保留；最近三张截图位于此目录下的「缓存」子文件夹。', False, '');
  SavePage.Add('截图保存文件夹：');
  SavePage.Values[0] := GetPreviousData('SaveDirectory', ExpandConstant('{userpics}\夹心贴'));
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if CurPageID = SavePage.ID then begin
    if Trim(SavePage.Values[0]) = '' then begin
      MsgBox('请选择截图保存文件夹。', mbError, MB_OK); Result := False;
    end else if not ForceDirectories(SavePage.Values[0]) then begin
      MsgBox('无法创建该文件夹，请选择有写入权限的位置。', mbError, MB_OK); Result := False;
    end;
  end;
end;

procedure RegisterPreviousData(PreviousDataKey: Integer);
begin
  SetPreviousData(PreviousDataKey, 'SaveDirectory', SavePage.Values[0]);
end;

procedure CurStepChanged(CurStep: TSetupStep);
var ExitCode: Integer;
begin
  if CurStep = ssPostInstall then begin
    if not Exec(ExpandConstant('{app}\夹心贴.exe'), '--configure "' + SavePage.Values[0] + '"',
      '', SW_HIDE, ewWaitUntilTerminated, ExitCode) or (ExitCode <> 0) then
      RaiseException('截图保存目录设置失败，请重新安装或首次启动时选择目录。');
  end;
end;
