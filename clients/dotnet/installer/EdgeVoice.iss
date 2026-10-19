; EdgeVoice Agent 설치 프로그램 (Inno Setup 6)
;
;   dotnet publish ../src/EdgeVoice.Agent.Desktop -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o ../../../publish/win-x64
;   ISCC.exe /DAppVersion=1.2.3 EdgeVoice.iss          → Output/EdgeVoice-Setup-1.2.3.exe
;
; - 사용자 단위 설치(%LOCALAPPDATA%\Programs\EdgeVoice) — 관리자 권한·UAC 없이 앱이 스스로 업데이트할 수 있다.
; - 특징 소개 페이지(스크린샷·인포그래픽 + 설명)를 차례로 보여 준 뒤 연결 설정을 받고 설치한다.
; - 설정은 %LOCALAPPDATA%\EdgeVoice\appsettings.json (앱의 UserSettings 와 같은 파일) — 업데이트·제거 때도 남는다.
; - 업데이트(같은 폴더에 다시 설치)는 실행 중인 앱을 닫고 기존 설치 파일을 모두 지운 뒤 새로 깐다.
; - 앱이 업데이트할 때는 /SILENT 로 실행한다: 마법사 없이 진행 막대만 보이고, 설치가 끝나면 앱을 다시 띄운다.
; - 구성 요소: [앱] 은 늘 설치, [AI 서버] 를 고르면 배포용 compose(deploy/)·서버 파일을 서버 폴더에 두고
;   setup-server.ps1 로 .env 준비(비밀 값 무작위) → 모델 받기 → docker compose pull · up -d 까지 한다.
;   업데이트 때도 같은 스크립트가 이미지 태그를 올려 pull · up -d 한다 (모델·DB 볼륨은 그대로).

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\..\publish\win-x64"
#endif
#define AppName "EdgeVoice Agent"
#define AppExe "EdgeVoice.Agent.Desktop.exe"
#define Pictures "..\..\..\assets\installer"
#define Repo "..\..\.."

[Setup]
; AppId 는 바꾸지 않는다 — 바꾸면 업데이트가 아니라 다른 프로그램으로 깔린다
AppId={{6E0B7C2A-9F4D-4B1E-A3C5-7D2E8F914B60}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=ghlee0786
AppPublisherURL=https://github.com/ghlee0786
VersionInfoVersion={#AppVersion}
DefaultDirName={localappdata}\Programs\EdgeVoice
DisableProgramGroupPage=yes
DisableDirPage=auto
UsePreviousAppDir=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=Output
OutputBaseFilename=EdgeVoice-Setup-{#AppVersion}
SetupIconFile=..\src\EdgeVoice.Agent.Desktop\Assets\edgevoice.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
WizardStyle=modern
WizardSizePercent=120
Compression=lzma2
SolidCompression=yes
; 업데이트 때 실행 중인 앱을 닫는다 (못 닫으면 PrepareToInstall 의 taskkill)
CloseApplications=force
RestartApplications=no

[Languages]
Name: "korean"; MessagesFile: "compiler:Languages\Korean.isl"

[Types]
Name: "full"; Description: "앱 + AI 서버 (이 PC 에서 AI 를 돌린다 — NVIDIA GPU · Docker Desktop · 디스크 약 60GB)"
Name: "app"; Description: "앱만 (AI 서버는 다른 PC 에 있다)"

[Components]
Name: "app"; Description: "EdgeVoice 앱 (트레이 · 파형 창 · 채팅 · 설정)"; Types: full app; Flags: fixed
Name: "server"; Description: "AI 서버 (Docker) — 모델 받기 · 서비스 시작까지 자동"; Types: full

[Tasks]
Name: "desktopicon"; Description: "바탕 화면에 바로 가기 만들기"
Name: "startup"; Description: "Windows 를 켤 때 자동으로 실행 (트레이에 상주, 'Hey Jarvis' 로 바로 부르기)"

[InstallDelete]
; 업데이트: 기존 설치 파일을 모두 지우고 새로 깐다 (사용자 설정은 설치 폴더 밖이라 남는다)
Type: filesandordirs; Name: "{app}\*"; Check: IsUpdate
; 서버 코드(shared 등)는 새 릴리스 것으로 바꾼다 — .env · models · logs 는 그대로
Type: filesandordirs; Name: "{code:ServerDir}\shared"; Components: server
Type: filesandordirs; Name: "{code:ServerDir}\services"; Components: server

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#Pictures}\feature-*.bmp"; Flags: dontcopy
; AI 서버 (deploy/docker-compose.yml 이 마운트하는 파일들을 같은 자리에)
Source: "{#Repo}\deploy\docker-compose.yml"; DestDir: "{code:ServerDir}"; Flags: ignoreversion; Components: server
Source: "{#Repo}\deploy\.env.example"; DestDir: "{code:ServerDir}"; Flags: ignoreversion; Components: server
Source: "{#Repo}\deploy\*.ps1"; DestDir: "{code:ServerDir}"; Flags: ignoreversion; Components: server
Source: "{#Repo}\shared\*"; DestDir: "{code:ServerDir}\shared"; Excludes: "__pycache__,*.pyc"; Flags: ignoreversion recursesubdirs createallsubdirs; Components: server
Source: "{#Repo}\services\llm\edgevoice_guard\*.py"; DestDir: "{code:ServerDir}\services\llm\edgevoice_guard"; Flags: ignoreversion; Components: server
Source: "{#Repo}\services\backend\static\*"; DestDir: "{code:ServerDir}\services\backend\static"; Flags: ignoreversion recursesubdirs createallsubdirs; Components: server
Source: "{#Repo}\config\mcp\*"; DestDir: "{code:ServerDir}\config\mcp"; Flags: ignoreversion; Components: server
Source: "{#Repo}\config\postgres\init.sql"; DestDir: "{code:ServerDir}\config\postgres"; Flags: ignoreversion; Components: server
Source: "{#Repo}\config\searxng\settings.yml"; DestDir: "{code:ServerDir}\config\searxng"; Flags: ignoreversion; Components: server

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon
Name: "{userstartup}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: startup
Name: "{autoprograms}\EdgeVoice AI 서버 준비"; Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{code:ServerDir}\setup-server.ps1"""; WorkingDir: "{code:ServerDir}"; Components: server

[Run]
; AI 서버 준비: 새 창에서 .env · 모델 받기 · 이미지 받기 · 시작 (오래 걸린다). 조용한 업데이트 때도 돌아 새 이미지로 바꾼다
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{code:ServerDir}\setup-server.ps1"" -Version v{#AppVersion} {code:TokenArg}"; WorkingDir: "{code:ServerDir}"; Description: "AI 서버 준비 — 모델 받기(처음 약 18GB) · 이미지 받기 · 시작 (오래 걸림)"; Flags: nowait postinstall; Components: server
; skipifsilent 를 붙이지 않는다 — 앱이 /SILENT 로 업데이트한 뒤에도 다시 띄운다
Filename: "{app}\{#AppExe}"; Description: "{#AppName} 실행"; Flags: nowait postinstall

[UninstallRun]
Filename: "{sys}\taskkill.exe"; Parameters: "/IM {#AppExe} /F"; Flags: runhidden; RunOnceId: "CloseApp"

[Code]
var
  ConnectionPage: TInputQueryWizardPage;
  UpdateCheck: TNewCheckBox;
  StopAiCheck: TNewCheckBox;
  ServerDirPage: TInputDirWizardPage;
  TokenPage: TInputQueryWizardPage;

function SettingsPath: String;
begin
  Result := ExpandConstant('{localappdata}\EdgeVoice\appsettings.json');
end;

{ 같은 폴더에 다시 설치하는 경우(업데이트)만 기존 파일을 지운다 — 새로 고른 폴더의 다른 파일은 건드리지 않는다 }
function IsUpdate: Boolean;
begin
  Result := (WizardForm.PrevAppDir <> '') and (CompareText(WizardForm.PrevAppDir, ExpandConstant('{app}')) = 0);
end;

{ 앱이 쓴 JSON 에서 "Key": 값 하나를 꺼낸다 (문자열·true/false 만) }
function JsonValue(const Json, Key, Default: String): String;
var
  P: Integer;
  Rest: String;
begin
  Result := Default;
  P := Pos('"' + Key + '"', Json);
  if P = 0 then
    Exit;
  Rest := Copy(Json, P + Length(Key) + 2, MaxInt);
  P := Pos(':', Rest);
  if P = 0 then
    Exit;
  Rest := Trim(Copy(Rest, P + 1, MaxInt));
  if Copy(Rest, 1, 1) = '"' then
  begin
    Rest := Copy(Rest, 2, MaxInt);
    P := Pos('"', Rest);
    if P > 0 then
    begin
      Result := Copy(Rest, 1, P - 1);
      StringChangeEx(Result, '\', '\', True);
    end;
  end
  else if CompareText(Copy(Rest, 1, 4), 'true') = 0 then
    Result := 'true'
  else if CompareText(Copy(Rest, 1, 5), 'false') = 0 then
    Result := 'false';
end;

{ AI 서버 폴더 (서버 구성 요소를 고를 때만 쓰인다). 설치 폴더 밖이어야 업데이트가 앱 폴더를 지워도 모델·.env 가 남는다 }
function ServerDir(Param: String): String;
begin
  Result := Trim(ServerDirPage.Values[0]);
end;

{ setup-server.ps1 에 넘길 HF 토큰 (비우면 .env 값 그대로) }
function TokenArg(Param: String): String;
begin
  Result := '';
  if Trim(TokenPage.Values[0]) <> '' then
    Result := '-HfToken "' + Trim(TokenPage.Values[0]) + '"';
end;

function CommandExists(const Name: String): Boolean;
var
  Code: Integer;
begin
  Result := Exec(ExpandConstant('{cmd}'), '/C where ' + Name, '', SW_HIDE, ewWaitUntilTerminated, Code) and (Code = 0);
end;

function JsonText(const S: String): String;
begin
  Result := S;
  StringChangeEx(Result, '\', '\\', True);
  StringChangeEx(Result, '"', '\"', True);
end;

{ 특징 소개 페이지 하나: 위에 설명, 아래에 그림(3:5 비율 유지) }
procedure AddFeaturePage(var After: Integer; const Title, Subtitle, Body, Picture: String);
var
  Page: TWizardPage;
  Text: TNewStaticText;
  Image: TBitmapImage;
  W, H: Integer;
begin
  Page := CreateCustomPage(After, Title, Subtitle);
  After := Page.ID;

  Text := TNewStaticText.Create(Page);
  Text.Parent := Page.Surface;
  Text.AutoSize := False;
  Text.WordWrap := True;
  Text.Width := Page.SurfaceWidth;
  Text.Height := ScaleY(40);
  Text.Caption := Body;

  ExtractTemporaryFile(Picture);
  Image := TBitmapImage.Create(Page);
  Image.Parent := Page.Surface;
  Image.Stretch := True;
  Image.Bitmap.LoadFromFile(ExpandConstant('{tmp}\') + Picture);
  H := Page.SurfaceHeight - Text.Height - ScaleY(6);
  W := H * 5 div 3;
  if W > Page.SurfaceWidth then
  begin
    W := Page.SurfaceWidth;
    H := W * 3 div 5;
  end;
  Image.SetBounds((Page.SurfaceWidth - W) div 2, Text.Height + ScaleY(6), W, H);
end;

procedure InitializeWizard;
var
  After: Integer;
  Raw: AnsiString;
  Json: String;
begin
  After := wpWelcome;
  AddFeaturePage(After, '음성 비서', '"Hey Jarvis" 로 부르고 말로 듣습니다 (1/6)',
    '호출어로 깨우면 듣고 → 글자로 바꾸고(STT) → 답을 만들어(LLM·도구) → 음성으로 읽어 줍니다(TTS). ' +
    '답하는 중에 말을 걸면 끼어들 수 있고, 화면의 파형 창을 누르면 듣기 시작·멈춤입니다.', 'feature-voice.bmp');
  AddFeaturePage(After, '채팅', '음성과 같은 대화를 글로도 (2/6)',
    '말로 나눈 대화도 채팅 창에 쌓여 이어서 글로 물어볼 수 있습니다. 최신 대화가 맨 위, 이미지도 붙일 수 있습니다.',
    'feature-chat.bmp');
  AddFeaturePage(After, '브라우저·컴퓨터 조작', '말로 시키면 PC 가 움직입니다 (3/6)',
    '"유튜브에서 ○○ 틀어 줘" 하면 크롬에서 찾아 재생하고 광고는 알아서 건너뜁니다. 크롬 닫기, 그림판 열고 그리기도 됩니다.',
    'feature-control.bmp');
  AddFeaturePage(After, '지식(RAG)', '내 문서를 근거로 답합니다 (4/6)',
    'PDF·DOCX·PPTX·TXT·MD 문서를 올리면 조각내어 검색해 두고, 질문과 관련된 부분을 근거로 답하며 출처를 보여 줍니다.',
    'feature-knowledge.bmp');
  AddFeaturePage(After, '대시보드·로그', '서비스 상태를 한눈에 (5/6)',
    'GPU 사용률, 서비스 상태, 로그 레벨별 건수를 보여 줍니다. 로그 탭에서 단계별 처리 시간을 실시간으로 볼 수 있습니다.',
    'feature-dashboard.bmp');
  AddFeaturePage(After, '설정', '모델·음성·MCP·스킬·업데이트 (6/6)',
    '음성 인식·답변 음성·언어 모델, 호출어 민감도, MCP 서버, 스킬을 바꾸고 저장 막대로 한 번에 저장합니다. ' +
    '새 버전이 나오면 업데이트할지 묻습니다.', 'feature-settings.bmp');

  { 연결 설정 — 업데이트로 다시 설치할 때는 지금 쓰는 값이 미리 채워진다 }
  Json := '';
  if LoadStringFromFile(SettingsPath, Raw) then
    Json := String(Raw);
  ConnectionPage := CreateInputQueryPage(After, '연결 설정',
    'EdgeVoice 서버(docker compose)에 연결할 주소',
    '서버를 이 PC 에서 돌리면 그대로 두세요. 다른 PC(예: Jetson)에서 돌리면 그 PC 의 주소로 바꿉니다. ' +
    '나중에 %LOCALAPPDATA%\EdgeVoice\appsettings.json 에서도 바꿀 수 있습니다.');
  ConnectionPage.Add('백엔드 주소 (BackendUrl):', False);
  ConnectionPage.Add('음성 게이트웨이 주소 (AudioGatewayWsUrl):', False);
  ConnectionPage.Values[0] := JsonValue(Json, 'BackendUrl', 'http://localhost:11000');
  ConnectionPage.Values[1] := JsonValue(Json, 'AudioGatewayWsUrl', 'ws://localhost:11008/ws/audio');

  UpdateCheck := TNewCheckBox.Create(ConnectionPage);
  UpdateCheck.Parent := ConnectionPage.Surface;
  UpdateCheck.Top := ConnectionPage.Edits[1].Top + ConnectionPage.Edits[1].Height + ScaleY(16);
  UpdateCheck.Width := ConnectionPage.SurfaceWidth;
  UpdateCheck.Height := ScaleY(20);
  UpdateCheck.Caption := '업데이트 자동 확인 — 새 버전이 나오면 업데이트할지 묻기 (설정 탭에서도 바꿀 수 있음)';
  UpdateCheck.Checked := JsonValue(Json, 'CheckForUpdates', 'true') = 'true';

  StopAiCheck := TNewCheckBox.Create(ConnectionPage);
  StopAiCheck.Parent := ConnectionPage.Surface;
  StopAiCheck.Top := UpdateCheck.Top + UpdateCheck.Height + ScaleY(8);
  StopAiCheck.Width := ConnectionPage.SurfaceWidth;
  StopAiCheck.Height := ScaleY(20);
  StopAiCheck.Caption := '앱을 종료할 때 AI 서비스도 끄기 (VRAM 비우기 — 다시 켤 때 약 3분)';
  StopAiCheck.Checked := JsonValue(Json, 'StopAiServicesOnExit', 'false') = 'true';

  { AI 서버 — 구성 요소에서 [AI 서버] 를 골랐을 때만 보인다 }
  ServerDirPage := CreateInputDirPage(wpSelectComponents, 'AI 서버 폴더',
    'compose 파일 · .env · 모델(약 20GB) · 로그를 둘 폴더',
    '여유 공간이 넉넉한 드라이브를 고르세요(모델·Docker 이미지 포함 약 60GB). 업데이트해도 이 폴더의 모델과 설정은 남습니다.',
    False, 'EdgeVoice');
  ServerDirPage.Add('');
  ServerDirPage.Values[0] := JsonValue(Json, 'ServerDir', ExpandConstant('{localappdata}\EdgeVoice\server'));

  TokenPage := CreateInputQueryPage(ServerDirPage.ID, 'AI 서버 설정', 'HuggingFace 토큰 (선택)',
    '모델은 HuggingFace 에서 받습니다(각 모델의 라이선스를 따릅니다). 공개 모델이라 토큰 없이도 받을 수 있지만, ' +
    '받기 속도 제한을 피하려면 https://huggingface.co/settings/tokens 의 읽기 토큰을 넣으세요. ' +
    '설치가 끝나면 새 창에서 모델 받기 → 이미지 받기 → 서비스 시작이 이어집니다(처음에는 오래 걸립니다).');
  TokenPage.Add('HF 토큰 (비워 두어도 됨):', True);
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := ((PageID = ServerDirPage.ID) or (PageID = TokenPage.ID)) and not WizardIsComponentSelected('server');
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if (CurPageID = wpSelectComponents) and WizardIsComponentSelected('server') then
  begin
    if not CommandExists('docker') then
      MsgBox('Docker Desktop 을 찾지 못했습니다. AI 서버는 Docker Desktop(WSL2)이 필요합니다.' + #13#10 +
        'https://www.docker.com/products/docker-desktop/ 에서 설치한 뒤, 시작 메뉴의 ''EdgeVoice AI 서버 준비'' 를 실행하면 이어서 준비합니다.',
        mbInformation, MB_OK);
    if not CommandExists('nvidia-smi') then
      MsgBox('NVIDIA GPU 드라이버(nvidia-smi)를 찾지 못했습니다. AI 서비스(언어 모델·음성 인식·답변 음성)는 NVIDIA GPU(VRAM 16GB 이상 권장)가 필요합니다.',
        mbInformation, MB_OK);
  end;
  if CurPageID = ServerDirPage.ID then
  begin
    if Pos(Uppercase(AddBackslash(WizardDirValue)), Uppercase(AddBackslash(ServerDir('')))) = 1 then
    begin
      MsgBox('AI 서버 폴더는 앱 설치 폴더 밖이어야 합니다 (업데이트 때 앱 폴더는 지워집니다).', mbError, MB_OK);
      Result := False;
    end;
  end;
  if CurPageID = ConnectionPage.ID then
  begin
    if (Pos('http://', ConnectionPage.Values[0]) <> 1) and (Pos('https://', ConnectionPage.Values[0]) <> 1) then
    begin
      MsgBox('백엔드 주소는 http:// 또는 https:// 로 시작해야 합니다.', mbError, MB_OK);
      Result := False;
    end
    else if (Pos('ws://', ConnectionPage.Values[1]) <> 1) and (Pos('wss://', ConnectionPage.Values[1]) <> 1) then
    begin
      MsgBox('음성 게이트웨이 주소는 ws:// 또는 wss:// 로 시작해야 합니다.', mbError, MB_OK);
      Result := False;
    end;
  end;
end;

{ 앱이 아직 떠 있으면(트레이 상주) 닫는다 }
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  Code: Integer;
begin
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/IM {#AppExe} /F', '', SW_HIDE, ewWaitUntilTerminated, Code);
  Result := '';
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  Json: String;
begin
  { 조용한 업데이트(/SILENT)는 마법사 값을 받지 않았으므로 지금 설정 파일을 그대로 둔다 }
  if (CurStep = ssPostInstall) and (not WizardSilent or not FileExists(SettingsPath)) then
  begin
    Json := '{' + #13#10 +
      '  "BackendUrl": "' + JsonText(Trim(ConnectionPage.Values[0])) + '",' + #13#10 +
      '  "AudioGatewayWsUrl": "' + JsonText(Trim(ConnectionPage.Values[1])) + '",' + #13#10;
    if UpdateCheck.Checked then
      Json := Json + '  "CheckForUpdates": true,' + #13#10
    else
      Json := Json + '  "CheckForUpdates": false,' + #13#10;
    if StopAiCheck.Checked then
      Json := Json + '  "StopAiServicesOnExit": true,' + #13#10
    else
      Json := Json + '  "StopAiServicesOnExit": false,' + #13#10;
    Json := Json + '  "ServerDir": "' + JsonText(ServerDir('')) + '"' + #13#10;
    Json := Json + '}' + #13#10;
    ForceDirectories(ExtractFileDir(SettingsPath));
    if not SaveStringToFile(SettingsPath, Json, False) then
      MsgBox('설정 파일을 쓰지 못했습니다: ' + SettingsPath, mbError, MB_OK);
  end;
end;
