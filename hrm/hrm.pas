program hrm;

{$mode objfpc}
{$H+}

uses
  cthreads,
  SysUtils,
  Classes,
  Process,
  BaseUnix;

type
  TConfig = record
    DryRun: Boolean;
    NoSound: Boolean;
    Verbose: Boolean;
    Help: Boolean;
    DelayMS: Integer;
    MaxSounds: Integer;
    Player: String;
  end;

  TEntryKind = (
    ekMissing,
    ekFileLike,
    ekDirectory
  );

  TSoundThread = class(TThread)
  private
    FScream: String;
    FExplosion: String;
    FPlayer: String;

    procedure PlayOne(const FileName: String);
  protected
    procedure Execute; override;
  public
    constructor Create(const AScream, AExplosion, APlayer: String);
  end;

const
  DEFAULT_DELAY_MS = 500;
  DEFAULT_MAX_SOUNDS = -1;

var
  Config: TConfig;
  Targets: TStringList;
  Screams: TStringList;
  Explosions: TStringList;
  Threads: TList;
  ExeDir: String;
  SFXDir: String;
  ScreamsDir: String;
  ExplosionsDir: String;

function StartsWith(const S, Prefix: String): Boolean;
begin
  Result := Copy(S, 1, Length(Prefix)) = Prefix;
end;

function StripPrefix(const S, Prefix: String): String;
begin
  Result := Copy(S, Length(Prefix) + 1, MaxInt);
end;

function PathJoin(const A, B: String): String;
begin
  Result := IncludeTrailingPathDelimiter(A) + B;
end;

function CommandPath(const Name: String): String;
begin
  Result := FileSearch(Name, GetEnvironmentVariable('PATH'));
end;

function DetectPlayer: String;
const
  Players: array[0..4] of String = (
    'mpv',
    'ffplay',
    'pw-play',
    'paplay',
    'aplay'
  );
var
  I: Integer;
  Found: String;
begin
  Result := '';

  if Config.Player <> '' then
  begin
    Found := CommandPath(Config.Player);

    if Found <> '' then
      Exit(Found);

    if FileExists(Config.Player) then
      Exit(Config.Player);

    Exit(Config.Player);
  end;

  for I := Low(Players) to High(Players) do
  begin
    Found := CommandPath(Players[I]);

    if Found <> '' then
      Exit(Found);
  end;
end;

function IsSoundFile(const FileName: String): Boolean;
var
  Ext: String;
begin
  Ext := LowerCase(ExtractFileExt(FileName));
  Result := (Ext = '.wav');
end;

procedure LoadSoundFiles(const Dir: String; List: TStringList);
var
  SR: TSearchRec;
  Full: String;
begin
  List.Clear;

  if not DirectoryExists(Dir) then
    Exit;

  if FindFirst(PathJoin(Dir, '*'), faAnyFile, SR) = 0 then
  begin
    repeat
      if (SR.Name <> '.') and (SR.Name <> '..') then
      begin
        Full := PathJoin(Dir, SR.Name);

        if ((SR.Attr and faDirectory) = 0) and IsSoundFile(Full) then
          List.Add(Full);
      end;
    until FindNext(SR) <> 0;

    FindClose(SR);
  end;
end;

function PickRandom(List: TStringList): String;
begin
  if List.Count <= 0 then
    Result := ''
  else
    Result := List[Random(List.Count)];
end;

function EntryKindNoFollow(const Path: String): TEntryKind;
var
  St: Stat;
begin
  Result := ekMissing;

  if fpLStat(PChar(Path), St) <> 0 then
    Exit;

  if (St.st_mode and S_IFMT) = S_IFDIR then
    Result := ekDirectory
  else
    Result := ekFileLike;
end;

function CountFilesRecursive(const Dir: String): Int64;
var
  SR: TSearchRec;
  Full: String;
  Kind: TEntryKind;
begin
  Result := 0;

  if FindFirst(PathJoin(Dir, '*'), faAnyFile, SR) = 0 then
  begin
    repeat
      if (SR.Name <> '.') and (SR.Name <> '..') then
      begin
        Full := PathJoin(Dir, SR.Name);
        Kind := EntryKindNoFollow(Full);

        case Kind of
          ekDirectory:
            Inc(Result, CountFilesRecursive(Full));

          ekFileLike:
            Inc(Result);
        end;
      end;
    until FindNext(SR) <> 0;

    FindClose(SR);
  end;
end;

function RemoveTree(const Path: String; out Err: String): Boolean;
var
  SR: TSearchRec;
  Full: String;
  Kind: TEntryKind;
begin
  Result := False;
  Err := '';

  Kind := EntryKindNoFollow(Path);

  case Kind of
    ekMissing:
      begin
        Err := 'No such file or directory';
        Exit;
      end;

    ekFileLike:
      begin
        if fpUnlink(PChar(Path)) = 0 then
          Exit(True);

        Err := SysErrorMessage(fpGetErrNo);
        Exit;
      end;

    ekDirectory:
      begin
        if FindFirst(PathJoin(Path, '*'), faAnyFile, SR) = 0 then
        begin
          repeat
            if (SR.Name <> '.') and (SR.Name <> '..') then
            begin
              Full := PathJoin(Path, SR.Name);

              if not RemoveTree(Full, Err) then
              begin
                FindClose(SR);
                Exit;
              end;
            end;
          until FindNext(SR) <> 0;

          FindClose(SR);
        end;

        if fpRmdir(PChar(Path)) = 0 then
          Exit(True);

        Err := SysErrorMessage(fpGetErrNo);
        Exit;
      end;
  end;
end;

procedure SleepMS(MS: Integer);
begin
  if MS > 0 then
    Sleep(MS);
end;

constructor TSoundThread.Create(const AScream, AExplosion, APlayer: String);
begin
  inherited Create(False);
  FreeOnTerminate := False;

  FScream := AScream;
  FExplosion := AExplosion;
  FPlayer := APlayer;
end;

procedure TSoundThread.PlayOne(const FileName: String);
var
  P: TProcess;
  PlayerName: String;
begin
  if (FPlayer = '') or (FileName = '') then
    Exit;

  if not FileExists(FileName) then
    Exit;

  PlayerName := LowerCase(ExtractFileName(FPlayer));

  P := TProcess.Create(nil);
  try
    P.Executable := FPlayer;
    P.Options := [poWaitOnExit, poUsePipes];

    if PlayerName = 'ffplay' then
    begin
      P.Parameters.Add('-nodisp');
      P.Parameters.Add('-autoexit');
      P.Parameters.Add('-loglevel');
      P.Parameters.Add('quiet');
      P.Parameters.Add(FileName);
    end
    else if PlayerName = 'mpv' then
    begin
      P.Parameters.Add('--really-quiet');
      P.Parameters.Add('--no-video');
      P.Parameters.Add(FileName);
    end
    else
    begin
      P.Parameters.Add(FileName);
    end;

    try
      P.Execute;
    except
      { audio failure should not fucking stop deletion. bullshit haunted files are not allowed to crash the ritual. }
    end;
  finally
    P.Free;
  end;
end;

procedure TSoundThread.Execute;
begin
  PlayOne(FScream);

  { tiny delay only, keeps the explosion timed right after cream i mean scream.}
  Sleep(80);

  PlayOne(FExplosion);
end;

procedure AddThread(T: TSoundThread);
begin
  Threads.Add(T);
end;

procedure WaitForThreads;
var
  I: Integer;
  T: TSoundThread;
begin
  for I := 0 to Threads.Count - 1 do
  begin
    T := TSoundThread(Threads[I]);
    T.WaitFor;
    T.Free;
  end;

  Threads.Clear;
end;

procedure PrintUsage;
begin
  Writeln('HRM: Horrified ReMove');
  Writeln('rm, but the files scream and explode first.');
  Writeln;
  Writeln('Usage: hrm [options] <file1> <file2> ...');
  Writeln;
  Writeln('Options:');
  Writeln('  --help              Show this help');
  Writeln('  --dry-run           Do everything except delete');
  Writeln('  --no-sound          Delete without playing sound');
  Writeln('  --delay=MS          Delay between screams for directories');
  Writeln('                      Default: ', DEFAULT_DELAY_MS);
  Writeln('  --max-sounds=N      Limit number of scream/explosion pairs per target');
  Writeln('                      Default: unlimited');
  Writeln('  --player=CMD        Force audio player');
  Writeln('                      Example: --player=mpv');
  Writeln('  --verbose           Print extra info');
  Writeln('  --                  Treat remaining args as files');
  Writeln;
  Writeln('SFX layout:');
  Writeln('  ./SFX/Screams/*.mp3 or *.wav');
  Writeln('  ./SFX/Explosions/*.mp3 or *.wav');
end;

procedure ParseArgs;
var
  I: Integer;
  S: String;
  Raw: String;
  StopOptions: Boolean;
begin
  Config.DryRun := False;
  Config.NoSound := False;
  Config.Verbose := False;
  Config.Help := False;
  Config.DelayMS := DEFAULT_DELAY_MS;
  Config.MaxSounds := DEFAULT_MAX_SOUNDS;
  Config.Player := '';

  StopOptions := False;
  I := 1;

  while I <= ParamCount do
  begin
    S := ParamStr(I);

    if StopOptions then
    begin
      Targets.Add(S);
      Inc(I);
      Continue;
    end;

    if S = '--' then
    begin
      StopOptions := True;
      Inc(I);
      Continue;
    end;

    if S = '--help' then
      Config.Help := True
    else if S = '--dry-run' then
      Config.DryRun := True
    else if S = '--no-sound' then
      Config.NoSound := True
    else if S = '--verbose' then
      Config.Verbose := True
    else if StartsWith(S, '--delay=') then
    begin
      Raw := StripPrefix(S, '--delay=');

      try
        Config.DelayMS := StrToInt(Raw);

        if Config.DelayMS < 0 then
          Config.DelayMS := 0;
      except
        Writeln('hrm: invalid delay: ', Raw);
        Halt(2);
      end;
    end
    else if StartsWith(S, '--max-sounds=') then
    begin
      Raw := StripPrefix(S, '--max-sounds=');

      try
        Config.MaxSounds := StrToInt(Raw);

        if Config.MaxSounds < 0 then
          Config.MaxSounds := DEFAULT_MAX_SOUNDS;
      except
        Writeln('hrm: invalid max-sounds: ', Raw);
        Halt(2);
      end;
    end
    else if StartsWith(S, '--player=') then
      Config.Player := StripPrefix(S, '--player=')
    else
      Targets.Add(S);

    Inc(I);
  end;
end;

procedure StartScreamingForTarget(const Target: String; SoundCount: Int64; const Player: String);
var
  I: Int64;
  RealCount: Int64;
  Scream: String;
  Explosion: String;
  T: TSoundThread;
begin
  if Config.NoSound then
    Exit;

  if Player = '' then
    Exit;

  if (Screams.Count = 0) or (Explosions.Count = 0) then
    Exit;

  RealCount := SoundCount;

  if RealCount < 1 then
    RealCount := 1;

  if (Config.MaxSounds >= 0) and (RealCount > Config.MaxSounds) then
    RealCount := Config.MaxSounds;

  for I := 1 to RealCount do
  begin
    Scream := PickRandom(Screams);
    Explosion := PickRandom(Explosions);

    T := TSoundThread.Create(Scream, Explosion, Player);
    AddThread(T);

    if RealCount > 1 then
      SleepMS(Config.DelayMS);
  end;
end;

procedure ProcessTarget(const Target: String; const Player: String);
var
  Kind: TEntryKind;
  FileCount: Int64;
  Err: String;
begin
  Kind := EntryKindNoFollow(Target);

  if Kind = ekMissing then
  begin
    Writeln('hrm: cannot remove ''', Target, ''': No such file or directory');
    Exit;
  end;

  FileCount := 1;

  if Kind = ekDirectory then
  begin
    FileCount := CountFilesRecursive(Target);

    if FileCount = 0 then
      FileCount := 1;
  end;

  if Config.Verbose then
  begin
    if Kind = ekDirectory then
      Writeln('hrm: ', Target, ': directory, ', FileCount, ' file scream(s)')
    else
      Writeln('hrm: ', Target, ': file, 1 scream');
  end;

  StartScreamingForTarget(Target, FileCount, Player);

  if Config.DryRun then
  begin
    if Kind = ekDirectory then
      Writeln('dry-run: ''', Target, ''' and its contents would be removed.')
    else
      Writeln('dry-run: ''', Target, ''' would be removed.');

    Exit;
  end;

  if RemoveTree(Target, Err) then
  begin
    if Kind = ekDirectory then
      Writeln('''', Target, ''' and its contents have been removed.')
    else
      Writeln('''', Target, ''' has been removed.');
  end
  else
  begin
    Writeln('hrm: cannot remove ''', Target, ''': ', Err);
  end;
end;

var
  I: Integer;
  Player: String;

begin
  Randomize;

  Targets := TStringList.Create;
  Screams := TStringList.Create;
  Explosions := TStringList.Create;
  Threads := TList.Create;

  try
    ParseArgs;

    if Config.Help or (Targets.Count = 0) then
    begin
      PrintUsage;
      Halt(0);
    end;

    ExeDir := ExtractFilePath(ExpandFileName(ParamStr(0)));
    SFXDir := PathJoin(GetEnvironmentVariable('HOME'), '.config/hrm/SFX');

    if not DirectoryExists(SFXDir) then
      SFXDir := PathJoin(ExeDir, 'SFX');

    if not DirectoryExists(SFXDir) then
      SFXDir := ExpandFileName(PathJoin(ExeDir, '../SFX'));

    if not DirectoryExists(SFXDir) then
      SFXDir := ExpandFileName(PathJoin(ExeDir, '../../SFX'));

    if not DirectoryExists(SFXDir) then
      SFXDir := '/usr/local/share/hrm/SFX';
if not DirectoryExists(SFXDir) then
      SFXDir := ExpandFileName(PathJoin(ExeDir, '../../SFX'));
    ScreamsDir := PathJoin(SFXDir, 'Screams');
    ExplosionsDir := PathJoin(SFXDir, 'Explosions');

    LoadSoundFiles(ScreamsDir, Screams);
    LoadSoundFiles(ExplosionsDir, Explosions);

    Player := '';

    if not Config.NoSound then
    begin
      Player := DetectPlayer;

      if Player = '' then
      begin
        Writeln('hrm: warning: no audio player found; continuing silently');
        Writeln('hrm: install mpv, ffplay, pw-play, paplay, or aplay');
      end;

      if Screams.Count = 0 then
        Writeln('hrm: warning: no scream sounds found in ', ScreamsDir);

      if Explosions.Count = 0 then
        Writeln('hrm: warning: no explosion sounds found in ', ExplosionsDir);
    end;

    for I := 0 to Targets.Count - 1 do
      ProcessTarget(Targets[I], Player);

    WaitForThreads;
  finally
    Targets.Free;
    Screams.Free;
    Explosions.Free;
    Threads.Free;
  end;
end.
