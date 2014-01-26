{$MINENUMSIZE 4}
{$RESOURCE EnvMan.res}

library EnvMan;

{
  TODO:
  * allow escaping % in strings
  * Russian help file
  * better error checking?
}

uses
  Windows, Types, {$IFDEF UNICODE}PluginW{$ELSE}Plugin{$ENDIF}, PluginEx, Clipbrd;

// ****************************************************************************

function CreateSettings: TSettings;
begin
  Result := TRegistrySettings.Create('EnvMan');
end;

function GetPluginString(Name: FarString; Default: FarString = ''): FarString;
var
  Settings: TSettings;
begin
  Settings := CreateSettings;
  Result := Settings.GetString(Name, Default);
  Settings.Free;
end;

function GetIgnoredVariables: FarString;
begin
  Result := GetPluginString('IgnoredVariables', 'FARENV_EXPORT_HWND');
end;

procedure SetPluginString(Name: PFarChar; Value: FarString);
var
  Settings: TSettings;
begin
  Settings := CreateSettings;
  Settings.SetString(Name, Value);
  Settings.Free;
end;

function GetName(S: FarString): FarString;
begin
  Result := Copy(S, 1, Pos('=', S)-1);
end;

function GetValue(S: FarString): FarString;
begin
  Result := Copy(S, Pos('=', S)+1, MaxInt);
end;

function ReadFullEnvironment: TFarStringDynArray;
var
  Env: PFarChar;
begin
  Env := GetEnvironmentStringsF;
  Result := NullStringsToArray(Env);
  FreeEnvironmentStringsF(Env);
end;

procedure ApplyNameValuePair(S: FarString);
var
  P: Integer;
begin
  if S='' then
    Exit;
  P := Pos('=', S);
  if P=0 then Exit;
  S[P] := #0;
  if P=Length(S) then
    SetEnvironmentVariableF(@S[1], nil)
  else
    SetEnvironmentVariableF(@S[1], @S[P+1]);
end;

// Remove Windows' special environment strings (which start with =)
// Also remove "ignored" variables
function FilterEnv(A: TFarStringDynArray): TFarStringDynArray;
var
  I, J: Integer;
  IgnoredVariables: TFarStringDynArray;
  Ignored: Boolean;
  Name: FarString;
begin
  Result := nil;
  IgnoredVariables := SplitByAny(GetIgnoredVariables, ',;');
  for I:=0 to High(A) do
    if (Length(A[I])>0) and (A[I][1] <> '=') then
    begin
      Name := GetName(A[I]);
      Ignored := False;
      for J:=0 to High(IgnoredVariables) do
        if Name=IgnoredVariables[J] then
        begin
          Ignored := True;
          Break
        end;
      if not Ignored then
        AppendToStrings(Result, A[I]);
    end;
end;

function ReadEnvironment: TFarStringDynArray;
var
  Env: PFarChar;
begin
  Env := GetEnvironmentStringsF;
  Result := FilterEnv(NullStringsToArray(Env));
  FreeEnvironmentStringsF(Env);
end;

function ReadRawEnvironment: FarString;
var
  Env: PFarChar;
  I: Integer;
begin
  Env := GetEnvironmentStringsF;
  I := 0;
  while (Env[I]<>#0) or (Env[I+1]<>#0) do
    Inc(I);
  Inc(I);
  SetLength(Result, I);
  Move(Env^, Result[1], I*SizeOf(FarChar));
  FreeEnvironmentStringsF(Env);
end;

procedure ClearEnvironment;
var
  Env: TFarStringDynArray;
  I: Integer;
begin
  Env := ReadEnvironment;
  for I:=0 to High(Env) do
    SetEnvironmentVariableF(PFarChar(OemToCharStr(GetName(Env[I]))), nil);
end;

procedure SetEnvironment(Env: TFarStringDynArray);
var
  I: Integer;
begin
  ClearEnvironment;
  
  for I:=0 to High(Env) do
    ApplyNameValuePair(OemToCharStr(Env[I]));
end;

function ExpandEnv(S: FarString): FarString;
begin
  SetLength(Result, ExpandEnvironmentStringsF(PFarChar(S), nil, 0));
  ExpandEnvironmentStringsF(PFarChar(S), @Result[1], Length(Result));
  SetLength(Result, Length(Result)-1); // terminating null
end;

// ****************************************************************************

type
  TEntry = record
    Name: FarString;
    Vars: TFarStringDynArray;
    Enabled: Boolean;
  end;
  TEntryDynArray = array of TEntry;

function ReadEntries: TEntryDynArray;
var
  Settings, EntryKey: TSettings;
  KeyName: FarString;
  I: Integer;
begin
  Result := nil;
  Settings := CreateSettings;
  try
    I := 0;
    repeat
      KeyName := IntToStr(I);
      if not Settings.KeyExists(KeyName) then
        Exit;
      EntryKey := Settings.OpenKey(KeyName);
      try
        SetLength(Result, Length(Result)+1);
        Result[High(Result)].Name := EntryKey.GetString('');
        Result[High(Result)].Vars := EntryKey.GetStrings('Vars');
        Result[High(Result)].Enabled := Boolean(EntryKey.GetInt('Enabled'));
      finally
        EntryKey.Free;
      end;
      Inc(I);
    until false;
  finally
    Settings.Free;
  end;
end;

var
  InitialEnvironment, LastUpdate: TFarStringDynArray;

procedure Update;
var
  Entries: TEntryDynArray;
  I, J: Integer;
begin
  // Reset the environment to the initial state
  SetEnvironment(InitialEnvironment);

  // Apply entries
  Entries := ReadEntries;
  for I:=0 to High(Entries) do
    if Entries[I].Enabled then
      for J:=0 to High(Entries[I].Vars) do
        ApplyNameValuePair(ExpandEnv(OemToCharStr(Entries[I].Vars[J])));
  
  LastUpdate := ReadEnvironment;
end;

function StringsEqual(A, B: TFarStringDynArray): Boolean;
var
  I: Integer;
begin
  Result := False;
  if Length(A) <> Length(B) then
    Exit;
  for I:=0 to High(A) do
    if A[I] <> B[I] then
      Exit;
  Result := True;
end;

function EntriesEqual(A, B: TEntryDynArray): Boolean;
var
  I: Integer;
begin
  Result := False;
  if Length(A) <> Length(B) then
    Exit;
  for I:=0 to High(A) do
    if (A[I].Name <> B[I].Name) or not StringsEqual(A[I].Vars, B[I].Vars) or (A[I].Enabled <> B[I].Enabled) then
      Exit;
  Result := True;
end;

procedure AppendToCommaList(var S: FarString; S2: FarString);
begin
  if S<>'' then
    S := S + ', ';
  S := S + S2;
end;

function DescribeDiff(NewVars, ChangedVars, DeletedVars: TFarStringDynArray): TFarStringDynArray;
begin
  Result := nil;
  if Length(NewVars)<>0 then
    AppendToStrings(Result, GetMsg(MNewVars) + Join(NewVars, ', '));
  if Length(ChangedVars)<>0 then
    AppendToStrings(Result, GetMsg(MChangedVars) + Join(ChangedVars, ', '));
  if Length(DeletedVars)<>0 then
    AppendToStrings(Result, GetMsg(MDeletedVars) + Join(DeletedVars, ', '));
end;

function MakeDiffEntry(Env1, Env2: TFarStringDynArray; var NewVars, ChangedVars, DeletedVars: TFarStringDynArray): TEntry;
var
  I, J, P: Integer;
  Found: Boolean;
  Name, NewValue, OldValue: FarString;

  procedure AppendSetting(Name, Value: FarString; var List: TFarStringDynArray);
  begin
    AppendToStrings(Result.Vars, Name+'='+Value);
    AppendToStrings(List, Name);
  end;

begin
  NewVars := nil;
  ChangedVars := nil;
  DeletedVars := nil;
  
  // Find new and modified variables
  for J:=0 to High(Env2) do
  begin
    Found := False;
    Name := GetName(Env2[J]);
    NewValue := GetValue(Env2[J]);
    for I:=0 to High(Env1) do
      if GetName(Env1[I])=Name then
      begin
        Found := True;
        OldValue := GetValue(Env1[I]);
        if NewValue<>OldValue then
        begin
          if Length(OldValue)>0 then
          begin
            P := Pos(OldValue, NewValue);
            if P>0 then
              NewValue := Copy(NewValue, 1, P-1)+'%'+Name+'%'+Copy(NewValue, P+Length(OldValue), MaxInt);
          end;
          AppendSetting(Name, NewValue, ChangedVars);
        end;
        Break;
      end;
    if not Found then
      AppendSetting(Name, NewValue, NewVars);
  end;

  // Find deleted variables
  for I:=0 to High(Env1) do
  begin
    Name := GetName(Env1[I]);
    Found := False;
    for J:=0 to High(Env2) do
      if GetName(Env2[J])=Name then
      begin
        Found := True;
        Break
      end;
    
    if not Found then
      AppendSetting(Name, '', DeletedVars);
  end;
end;

// ****************************************************************************

function DoConfigure(IgnoredVariables: FarString): Boolean; overload;
const
  W = 75;
  H = 7;
  ItemNr = 5;
  GUID: TGUID = '{f213d17a-291e-4cb4-8765-d6e383067d25}';
var
  Dialog: TFarDialog;
  Name: PFarChar;
  N, OK, IIgnoredVariables: Integer;
begin
  while Copy(IgnoredVariables, 1, 1)=',' do
    Delete(IgnoredVariables, 1, 1);
  
  Dialog := TFarDialog.Create;
  try
    Dialog.Add(DI_DOUBLEBOX, DIF_NONE, 3, 1, W-1-3, H-1-1, GetMsg(MConfiguration));
    
    Name := GetMsg(MIgnoredVariables);
    
    Dialog.Add(DI_TEXT, DIF_NONE, 5, 2, 5+Length(Name), 2, Name);

    IIgnoredVariables := Dialog.Add(DI_EDIT, DIF_NONE, 5+Length(Name), 2, W-1-5, 2, IgnoredVariables);
    Dialog.Items[IIgnoredVariables].{$IFDEF FAR3}Flags := Dialog.Items[IIgnoredVariables].Flags or DIF_FOCUS{$ELSE}Focus := 1{$ENDIF};
    
    OK := Dialog.Add(DI_BUTTON, DIF_CENTERGROUP, 0, H-1-2, 0, 0, GetMsg(MOK));
    Dialog.Items[OK].{$IFDEF FAR3}Flags := Dialog.Items[OK].Flags or DIF_DEFAULTBUTTON{$ELSE}DefaultButton := 1{$ENDIF};
    
    Dialog.Add(DI_BUTTON, DIF_CENTERGROUP, 0, H-1-2, 0, 0, GetMsg(MCancel));

    Result := False;
    N := Dialog.Run(GUID, W, H, 'Configuration');
    if N <> OK then
      Exit;

    SetPluginString('IgnoredVariables', Dialog.GetData(IIgnoredVariables));
    Result := True;
  finally
    Dialog.Free;
  end;
end;

function DoConfigure: Boolean; overload;
begin
  Result := DoConfigure(GetIgnoredVariables);
end;

function OpenEntryKey(Index: Integer): TSettings;
var
  Settings: TSettings;
begin
  Settings := CreateSettings;
  Result := Settings.OpenKey(IntToStr(Index));
  Settings.Free;
end;

procedure SaveEntry(Index: Integer; const Entry: TEntry);
var
  Key: TSettings;
begin
  Key := OpenEntryKey(Index);
  Key.SetString('', Entry.Name);
  Key.SetStrings('Vars', Entry.Vars);
  Key.SetInt('Enabled', Ord(Entry.Enabled));
  Key.Free;
end;

function EditEntryAlt(var Entry: TEntry): Boolean; forward;

function EditEntry(var Entry: TEntry; Caption: TMessage): Boolean;
const
  W = 75;
  Rows = 15;
  H = Rows + 8;
  ItemNr = 6; // not counting rows
  TotalItemNr = ItemNr+Rows;
  TooManyLinesGUID: TGUID = '{726fd929-25fc-407f-b33a-73462d5a1453}';
  GUID: TGUID = '{b15cb128-d71e-4277-bbac-eb6ffb4af77d}';

var
  I, N: Integer;
  Dialog: TFarDialog;

begin
  if Length(Entry.Vars) > Rows then
  begin
    if Message(TooManyLinesGUID, FMSG_WARNING or FMSG_MB_YESNO, [GetMsg(MWarning), GetMsg(MTooManyLines1), GetMsg(MTooManyLines2)])=0 then
      Result := EditEntryAlt(Entry)
    else
      Result := False;
    Exit;
  end;

  Dialog := TFarDialog.Create;
  try
    Dialog.Add(DI_DOUBLEBOX, DIF_NONE, 3, 1, W-1-3, H-1-1, GetMsg(Caption));
    
    Dialog.Add(DI_TEXT, DIF_NONE, 5, 2, 10, 2, GetMsg(MName));

    N := Dialog.Add(DI_EDIT, DIF_HISTORY, 11, 2, W-1-5-13, 2, Entry.Name);
    Dialog.Items[N].{$IFNDEF FAR3}Param.{$ENDIF}History := 'EnvVarsName';
    if Entry.Name='' then
      Dialog.Items[N].{$IFDEF FAR3}Flags := Dialog.Items[N].Flags or DIF_FOCUS{$ELSE}Focus := 1{$ENDIF};
    
    N := Dialog.Add(DI_CHECKBOX, DIF_NONE, W-1-5-10, 2, 0, 2, GetMsg(MEnabled));
    Dialog.Items[N].Param.Selected := Integer(Entry.Enabled);

    SetLength(Entry.Vars, Rows);
    for I:=0 to Rows-1 do
    begin
      N := Dialog.Add(DI_EDIT, DIF_EDITOR, 5, 4+I, W-1-5, 4+I, Entry.Vars[I], $10000);
      if (I=0) and (Entry.Name<>'') then
        Dialog.Items[N].{$IFDEF FAR3}Flags := Dialog.Items[N].Flags or DIF_FOCUS{$ELSE}Focus := 1{$ENDIF};
    end;

    N := Dialog.Add(DI_BUTTON, DIF_CENTERGROUP, 0, H-1-2, 0, 0, GetMsg(MOK));
    Dialog.Items[N].{$IFDEF FAR3}Flags := Dialog.Items[N].Flags or DIF_DEFAULTBUTTON{$ELSE}DefaultButton := 1{$ENDIF};

    Dialog.Add(DI_BUTTON, DIF_CENTERGROUP, 0, H-1-2, 0, 0, GetMsg(MCancel));

    Result := False;
    N := Dialog.Run(GUID, W, H, 'Editor');
    if N<>4+Rows then
      Exit;

    Entry.Name := Dialog.GetData(2);
    Entry.Enabled := Dialog.GetChecked(3);
    for I:=0 to Rows-1 do
      Entry.Vars[I] := Dialog.GetData(4+I);
    
    Result := True;
  finally
    Dialog.Free;
  end;
end;

function EntryToLines(const Entry: TEntry): TFarStringDynArray;
begin
  Result := ConcatStrings([
    MakeStrings([
      '=Name=' + Entry.Name,
      '=Enabled=' + IntToStr(Integer(Entry.Enabled)),
      ''
    ]), 
    Entry.Vars, 
    MakeStrings([''])
  ]);
end;

function EntryToText(const Entry: TEntry): FarString;
begin
  Result := Join(EntryToLines(Entry), #13#10);
end;

function LinesToEntry(Lines: TFarStringDynArray): TEntry;
var
  I: Integer;
begin
  Result.Name := '';
  Result.Enabled := False;
  for I := 0 to High(Lines) do
    if Copy(Lines[I], 1, 6) = '=Name=' then
      Result.Name := Copy(Lines[I], 7, MaxInt)
    else
    if Copy(Lines[I], 1, 9) = '=Enabled=' then
      Result.Enabled := Copy(Lines[I], 10, MaxInt) = '1'
    else
    if Pos('=', Lines[I]) > 1 then
      AppendToStrings(Result.Vars, Lines[I]);
end;

function TextToEntry(Data: FarString): TEntry;
begin
  Result := LinesToEntry(SplitLines(Data));
end;

function EditEntryAlt(var Entry: TEntry): Boolean;
var
  Data: FarString;
begin
  Data := EntryToText(Entry);
  Result := EditString(Data, Entry.Name + ' - EnvMan');
  if Result then
    Entry := TextToEntry(Data);
end;

function EnvToText(Env: TFarStringDynArray): FarString;
begin
  Result := Join(Env, #13#10) + #13#10;
end;

function EditEnvironment: Boolean;
var
  Data: FarString;
begin
  Data := EnvToText(ReadEnvironment);
  Result := EditString(Data, 'Environment');
  if Result then
    SetEnvironment(SplitLines(Data));
end;

procedure ShowEntryMenu(Quiet: Boolean);
var
  Entries: TEntryDynArray;
  Current: Integer;

  procedure InsertEntry(Index: Integer; const Entry: TEntry);
  var
    I: Integer;
  begin
    for I:=High(Entries) downto Index do
      SaveEntry(I+1, Entries[I]);
    SaveEntry(Index, Entry);
  end;

  procedure DeleteEntry(Index: Integer);
  var
    Key: TSettings;
    I: Integer;
  begin
    for I:=Index+1 to High(Entries) do
      SaveEntry(I-1, Entries[I]);
    Key := CreateSettings;
    Key.DeleteKey(IntToStr(High(Entries)));
    Key.Free;
  end;

  procedure MoveCurrent(Direction: Integer);
  begin
    repeat
      Inc(Current, Direction);
    until (Current<0) or (Current>High(Entries)) or (Entries[Current].Name<>'-');
  end;

var
  Entry: TEntry;
  BreakCode: Integer;
  I: Integer;
  Items: array of TFarMenuItem;
  Key: TSettings;
  Env, NewEnv: TFarStringDynArray;
  InitialEntries: TEntryDynArray;
  NewVars, ChangedVars, DeletedVars, AllVars: TFarStringDynArray;
const
  {$IFDEF FAR3}
  BreakKeys: array[0..16] of TFarKey = (
    (VirtualKeyCode: VK_ADD     ; ControlKeyState: 0),
    (VirtualKeyCode: VK_SUBTRACT; ControlKeyState: 0),
    (VirtualKeyCode: VK_SPACE   ; ControlKeyState: 0),
    (VirtualKeyCode: VK_INSERT  ; ControlKeyState: 0),
    (VirtualKeyCode: VK_DELETE  ; ControlKeyState: 0),
    (VirtualKeyCode: VK_F4      ; ControlKeyState: 0),
    (VirtualKeyCode: VK_F5      ; ControlKeyState: 0),
    (VirtualKeyCode: VK_UP      ; ControlKeyState: LEFT_CTRL_PRESSED),
    (VirtualKeyCode: VK_DOWN    ; ControlKeyState: LEFT_CTRL_PRESSED),
    (VirtualKeyCode: VK_F3      ; ControlKeyState: SHIFT_PRESSED),
    (VirtualKeyCode: VK_F4      ; ControlKeyState: LEFT_ALT_PRESSED),
    (VirtualKeyCode: VK_F4      ; ControlKeyState: SHIFT_PRESSED),
    (VirtualKeyCode: VK_DELETE  ; ControlKeyState: SHIFT_PRESSED),
    (VirtualKeyCode: VK_INSERT  ; ControlKeyState: RIGHT_CTRL_PRESSED),
    (VirtualKeyCode: VK_INSERT  ; ControlKeyState: SHIFT_PRESSED),
    (VirtualKeyCode: VK_F2      ; ControlKeyState: 0),
    (VirtualKeyCode: 0          ; ControlKeyState: 0)
  );
  {$ELSE}
  VK_CTRLUP   = VK_UP     or (PKF_CONTROL shl 16);
  VK_CTRLDOWN = VK_DOWN   or (PKF_CONTROL shl 16);
  VK_SHIFTF3  = VK_F3     or (PKF_SHIFT   shl 16);
  VK_ALTF4    = VK_F4     or (PKF_ALT     shl 16);
  VK_SHIFTF4  = VK_F4     or (PKF_SHIFT   shl 16);
  VK_SHIFTDEL = VK_DELETE or (PKF_SHIFT   shl 16);
  VK_CTRLINS  = VK_INSERT or (PKF_CONTROL shl 16);
  VK_SHIFTINS = VK_INSERT or (PKF_SHIFT   shl 16);
  BreakKeys: array[0..16] of Integer = (
    VK_ADD,
    VK_SUBTRACT,
    VK_SPACE,
    VK_INSERT,
    VK_DELETE,
    VK_F4,
    VK_F5,
    VK_CTRLUP,
    VK_CTRLDOWN,
    VK_SHIFTF3,
    VK_ALTF4,
    VK_SHIFTF4,
    VK_SHIFTDEL,
    VK_CTRLINS,
    VK_SHIFTINS,
    VK_F2,
    0
  );
  {$ENDIF}
  EditedGUID: TGUID = '{0d0b19a9-93d6-2e4b-b417-05b258e6dee8}';
  ConfirmDeleteGUID: TGUID = '{a42cda5f-1d11-86a5-4cf3-b7d0b53dff12}';
  ViewEnvironmentGUID: TGUID = '{0a536038-d35c-c9e2-58eb-c6748bcad6ab}';
  NoChangeGUID: TGUID = '{3eaf2001-118c-4cdc-ac4e-a75676c2456e}';
  {$IFDEF FAR3}
  MenuGUID: TGUID = '{b84ab5a0-155e-909e-e4c3-15b3a0cbd19c}';
  {$ENDIF}

begin
  Env := ReadEnvironment;

  if not Quiet and not StringsEqual(LastUpdate, Env) then
  begin
    Entry := MakeDiffEntry(LastUpdate, Env, NewVars, ChangedVars, DeletedVars);
    AllVars := ConcatStrings([NewVars, ChangedVars, DeletedVars]);
    Entry.Name := 'Imported: ' + Join(AllVars, ', ');
    Entry.Enabled := True;

    I := Message(EditedGUID, FMSG_WARNING, ConcatStrings([
      MakeStrings([GetMsg(MWarning), GetMsg(MEnvEdited1), GetMsg(MEnvEdited2), GetMsg(MEnvEdited3)]),
      DescribeDiff(NewVars, ChangedVars, DeletedVars),
      MakeStrings([GetMsg(MContinue), GetMsg(MCancel), GetMsg(MImport), GetMsg(MIgnore)])
      ]), 4);
    if (I=1) or (I=-1) then
      Exit;
    if I=2 then // import
    begin
      if EditEntry(Entry, MImportCaption) then
      begin
        Entries := ReadEntries;
        SaveEntry(Length(Entries), Entry);
      end
      else
        Exit; // User cancelled
    end
    else
    if I=3 then // ignore
    begin
      if not DoConfigure(GetIgnoredVariables+','+Join(AllVars, ',')) then
        Exit;
      Env := ReadEnvironment;
      LastUpdate := Env;
    end;
  end;

  InitialEntries := ReadEntries;
  Current := 0;
  repeat
    Entries := ReadEntries;

    // clear heading/trailing separators
    while (Length(Entries)>0) and (Entries[0].Name='-') do
    begin
      DeleteEntry(0);
      Entries := ReadEntries;
      Dec(Current);
    end;
    while (Length(Entries)>0) and (Entries[High(Entries)].Name='-') do
    begin
      DeleteEntry(High(Entries));
      Entries := ReadEntries;
    end;

    SetLength(Items, 0); // Clear
    SetLength(Items, Length(Entries));
    while (Current >= 0) and (Current < Length(Entries)) and (Entries[Current].Name='-') do
      Inc(Current);
    if Current >= Length(Entries) then
      Current := Length(Entries)-1;
    if Current < 0 then
      Current := 0;
    for I:=0 to High(Entries) do
    begin
      {$IFNDEF UNICODE}
      CopyStrToBuf(Entries[I].Name, Items[I].Text, SizeOf(Items[I].Text));
      {$ELSE}
      Items[I].TextPtr := PFarChar(Entries[I].Name);
      {$ENDIF}
      if I=Current then
        Items[I].{$IFDEF FAR3}Flags := Items[I].Flags or MIF_SELECTED {$ELSE}Selected  := 1{$ENDIF};
      if Entries[I].Enabled then
        Items[I].{$IFDEF FAR3}Flags := Items[I].Flags or MIF_CHECKED  {$ELSE}Checked   := 1{$ENDIF};
      if Entries[I].Name='-' then
      begin
        Items[I].{$IFDEF FAR3}Flags := Items[I].Flags or MIF_SEPARATOR{$ELSE}Separator := 1{$ENDIF};
        {$IFNDEF UNICODE}
        CopyStrToBuf('', Items[I].Text, SizeOf(Items[I].Text));
        {$ELSE}
        Items[I].TextPtr := nil;
        {$ENDIF}
      end;
    end;
    Current := FARAPI.Menu({$IFDEF FAR3}PluginGUID, MenuGUID{$ELSE}FARAPI.ModuleNumber{$ENDIF}, -1, -1, 0, FMENU_AUTOHIGHLIGHT or FMENU_WRAPMODE, 'Environment Manager', 'Space,Ins,Del,F4,... [F1]', 'MainMenu', @BreakKeys, @BreakCode, @Items[0], Length(Items));
    if (Current=-1) and (BreakCode=-1) then
      Break;
    case BreakCode of
      0: // VK_ADD
        if Current >= 0 then
        begin
          Key := OpenEntryKey(Current);
          Key.SetInt('Enabled', 1);
          MoveCurrent(1);
          Key.Free;
        end;
      1: // VK_SUBTRACT
        if Current >= 0 then
        begin
          Key := OpenEntryKey(Current);
          Key.SetInt('Enabled', 0);
          MoveCurrent(1);
          Key.Free;
        end;
      2: // VK_SPACE
        if Current >= 0 then
        begin
          Key := OpenEntryKey(Current);
          Key.SetInt('Enabled', 1-Key.GetInt('Enabled'));
          MoveCurrent(1);
          Key.Free;
        end;
      3: // VK_INSERT
      begin
        if Current < 0 then
          Current := 0;
        Entry.Name := '';
        Entry.Vars := nil;
        Entry.Enabled := True;
        if EditEntry(Entry, MNewCaption) then
          InsertEntry(Current, Entry);
      end;
      4: // VK_DELETE
        if Current >= 0 then
        begin
          if Message(ConfirmDeleteGUID, FMSG_WARNING or FMSG_MB_OKCANCEL, [GetMsg(MConfirmDeleteTitle), GetMsg(MConfirmDeleteText), Entries[Current].Name])=0 then
            DeleteEntry(Current);
        end;
      5: // VK_F4
        if Current >= 0 then
        begin
          Entry := Entries[Current];
          if EditEntry(Entry, MEditCaption) then
            SaveEntry(Current, Entry);
        end;
      6: // VK_F5
        if Current >= 0 then
        begin
          Entry := Entries[Current];
          if EditEntry(Entry, MCopyCaption) then
            InsertEntry(Current+1, Entry);
        end;
      7: // VK_CTRLUP
        if Current >= 0 then
          if Current = 0 then // create separator
          begin
            Entry.Name := '-';
            Entry.Vars := nil;
            Entry.Enabled := False;
            InsertEntry(1, Entry);
          end
          else
          begin
            SaveEntry(Current, Entries[Current-1]);
            SaveEntry(Current-1, Entries[Current]);
            Dec(Current);
          end;
      8: // VK_CTRLDOWN
        if Current >= 0 then
          if Current = High(Entries) then // create separator
          begin
            Entry.Name := '-';
            Entry.Vars := nil;
            Entry.Enabled := False;
            InsertEntry(Current, Entry);
            Inc(Current);
          end
          else
          begin
            SaveEntry(Current, Entries[Current+1]);
            SaveEntry(Current+1, Entries[Current]);
            Inc(Current);
          end;
      9: // VK_SHIFTF3
        Message(ViewEnvironmentGUID, FMSG_MB_OK, ConcatStrings([MakeStrings(['Environment']), Env]));
      10: // VK_ALTF4
        if Current >= 0 then
        begin
          Entry := Entries[Current];
          if EditEntryAlt(Entry) then
            SaveEntry(Current, Entry);
        end;
      11: // VK_SHIFTF4
      begin
        if not EntriesEqual(InitialEntries, Entries) then
          Update;
        if EditEnvironment then
          Exit;
      end;
      12: // VK_SHIFTDEL
        if Current >= 0 then
        begin
          Clipboard.AsText := EntryToText(Entries[Current]);
          DeleteEntry(Current);
        end;
      13: // VK_CTRLINS
        if Current >= 0 then
          Clipboard.AsText := EntryToText(Entries[Current]);
      14: // VK_SHIFTINS
      begin
        if Current < 0 then
          Current := 0;
        InsertEntry(Current, TextToEntry(Clipboard.AsText));
      end;
      15: // VK_F2
      begin
        DoConfigure;
      end;
      else // VK_RETURN / hotkey
        if Current >= 0 then
        begin
          Key := OpenEntryKey(Current);
          Key.SetInt('Enabled', 1-Key.GetInt('Enabled'));
          Key.Free;
        end;
        //Break;
    end;
  until false;

  Update;
  NewEnv := ReadEnvironment;

  if not Quiet and EntriesEqual(InitialEntries, Entries) then // no changes
    if not StringsEqual(Env, NewEnv) then // but env has changed
    begin
      if Message(NoChangeGUID, FMSG_WARNING, [
        GetMsg(MWarning),
        GetMsg(MNoChange1),
        GetMsg(MNoChange2),
        GetMsg(MNoChange3),
        GetMsg(MOverwrite),
        GetMsg(MKeep)], 2)<>0 then // Keep was selected?
      begin
        // Restore last environment
        SetEnvironment(Env);
        LastUpdate := Env;
      end;
    end;
end;

procedure LoadEnv(FileName: FarString);
var
  S: FarString;
const
  ErrorGUID: TGUID = '{c5acb8a8-65ee-5850-bc3d-38aee52fc7ca}';
begin
  if not TryLoadText(FileName, S) then
  begin
    Message(ErrorGUID, FMSG_WARNING or FMSG_MB_OK, [GetMsg(MError), GetMsg(MFileLoadError), FileName]);
    Exit
  end;
  SetEnvironment(SplitLines(S));
end;

procedure SaveEnv(FileName: FarString);
const
  ErrorGUID: TGUID = '{a46bea4d-3998-9547-6ed0-c3300cb1620c}';
begin
  if not TrySaveText(FileName, EnvToText(ReadEnvironment)) then
    Message(ErrorGUID, FMSG_WARNING or FMSG_MB_OK, [GetMsg(MError), GetMsg(MFileCreateError), FileName]);
end;

procedure SaveRawEnv(FileName: FarString);
const
  ErrorGUID: TGUID = '{39f779fb-8dcd-5734-70e8-1166bf6c6f1d}';
begin
  if not TrySaveString(FileName, ReadRawEnvironment) then
    Message(ErrorGUID, FMSG_WARNING or FMSG_MB_OK, [GetMsg(MError), GetMsg(MFileCreateError), FileName]);
end;

procedure ProcessCommandLine(PCmdLine: PFarChar);
var
  CmdLine, Name: FarString;
  Entries: TEntryDynArray;
  I: Integer;
const
  BadCommandCharGUID: TGUID = '{71148345-8141-1f0e-4453-3a073e7b5178}';
  NoSuchEntryGUID: TGUID = '{7ad27a4e-b753-fd0f-cfb9-7b3409567649}';
begin
  CmdLine := PCmdLine;
  if Length(CmdLine)=0 then
    ShowEntryMenu(True)
  else
  if CmdLine[1]='<' then
    LoadEnv(Copy(CmdLine, 2, MaxInt))
  else
  if CmdLine[1]='>' then
    SaveEnv(Copy(CmdLine, 2, MaxInt))
  else
  if CmdLine[1]='}' then
    SaveRawEnv(Copy(CmdLine, 2, MaxInt))
  else
  if CmdLine[1]='e' then
    EditEnvironment
  else
  begin
    Name := Copy(CmdLine, 2, MaxInt);
    Entries := ReadEntries;
    for I:=0 to High(Entries) do
      if Entries[I].Name = Name then
      begin
        if CmdLine[1]='-' then
          Entries[I].Enabled := False
        else
        if CmdLine[1]='+' then
          Entries[I].Enabled := True
        else
        if CmdLine[1]='*' then
          Entries[I].Enabled := not Entries[I].Enabled
        else
        begin
          Message(BadCommandCharGUID, FMSG_WARNING or FMSG_MB_OK, [GetMsg(MError), GetMsg(MBadCommandChar)]);
          Exit;
        end;
        SaveEntry(I, Entries[I]);
        Update;
        Exit;
      end;
    Message(NoSuchEntryGUID, FMSG_WARNING or FMSG_MB_OK, [GetMsg(MError), GetMsg(MNoSuchEntry), Name]);
  end;
end;

// ****************************************************************************

{$IFDEF UNICODE}
procedure SetStartupInfoW(var psi: TPluginStartupInfo); stdcall;
{$ELSE}
procedure SetStartupInfo(var psi: TPluginStartupInfo); stdcall;
{$ENDIF}
begin
  Move(psi, FARAPI, SizeOf(FARAPI));
  InitialEnvironment := ReadEnvironment;
  Update;
end;

var
  PluginMenuStrings, PluginConfigStrings: array[0..0] of PFarChar;
{$IFDEF FAR3}
  PluginMenuGuids, PluginConfigGuids: array[0..0] of TGUID;
{$ENDIF}

{$IFDEF UNICODE} 
procedure GetPluginInfoW(var pi: TPluginInfo); stdcall;
{$ELSE} 
procedure GetPluginInfo(var pi: TPluginInfo); stdcall;
{$ENDIF}
{$IFDEF FAR3}
const
  GUID: TGUID = '{d46eede5-5d88-8652-50a9-2aecc0e0cad4}';
{$ENDIF}
begin
  pi.StructSize := SizeOf(pi);
  pi.Flags := PF_PRELOAD or PF_EDITOR;

  PluginMenuStrings[0] := 'Environment Manager';
{$IFDEF FAR3}
  PluginMenuGuids[0] := GUID;
  pi.PluginMenu.Strings := @PluginMenuStrings;
  pi.PluginMenu.Guids := @PluginMenuGuids;
  pi.PluginMenu.Count := 1;
{$ELSE}
  pi.PluginMenuStrings := @PluginMenuStrings;
  pi.PluginMenuStringsNumber := 1;
{$ENDIF}

  PluginConfigStrings[0] := 'Environment Manager';
{$IFDEF FAR3}
  PluginConfigGuids[0] := GUID;
  pi.PluginConfig.Strings := @PluginConfigStrings;
  pi.PluginConfig.Guids := @PluginConfigGuids;
  pi.PluginConfig.Count := 1;
{$ELSE}
  pi.PluginConfigStrings := @PluginConfigStrings;
  pi.PluginConfigStringsNumber := 1;
{$ENDIF}

  pi.CommandPrefix := 'envman';
{$IFNDEF FAR3}
  pi.Reserved := $4D766E45; // 'EnvM'
{$ENDIF}
end;

{$IFDEF FAR3}
procedure GetGlobalInfoW(Info: PGlobalInfo); stdcall;
begin
  Info.StructSize := SizeOf(pi);
  Info.MinFarVersion := MakeFARVersion(3, 0, 0, 2927, VS_RELEASE);
  Info.Version := MakeFARVersion(1, 6, 0, 0, VS_RELEASE);
  Info.Guid := PluginGUID;
  Info.Title := 'EnvMan';
  Info.Description := 'Environment Manager';
  Info.Author := 'Vladimir Panteleev <vladimir@thecybershadow.net>';
end;

function OpenW(Info: POpenInfo): THandle; stdcall;
var
  MacroInfo: POpenMacroInfo;
  CommandLineInfo: POpenCommandLineInfo;
begin
  case Info.OpenFrom of
    OPEN_FROMMACRO_,
    OPEN_LUAMACRO: // ???
      begin
        MacroInfo := POpenMacroInfo(Info.Data);
        if (MacroInfo.Count=1) and (MacroInfo.Values[0].fType=FMVT_STRING) then
          ProcessCommandLine(MacroInfo.Values[0].Value.fString);
      end;
    OPEN_COMMANDLINE:
      begin
        CommandLineInfo := POpenCommandLineInfo(Info.Data);
        ProcessCommandLine(CommandLineInfo.CommandLine);
      end;
    else
      ShowEntryMenu(False);
  end;

  Result := 0;
end;
{$ELSE}
{$IFDEF UNICODE}
function OpenPluginW(OpenFrom: Integer; Item: INT_PTR): THandle; stdcall;
{$ELSE}
function OpenPlugin(OpenFrom: Integer; Item: INT_PTR): THandle; stdcall;
{$ENDIF}
var
  FromMacro: Boolean;
begin
  FromMacro := False;
  if (OpenFrom and OPEN_FROMMACRO)<>0 then
  begin
    FromMacro := True;
    OpenFrom := OpenFrom and not OPEN_FROMMACRO;
  end;

  if (OpenFrom=OPEN_COMMANDLINE) or FromMacro then
    ProcessCommandLine(PFarChar(Item))
  else
    ShowEntryMenu(False);
  Result := INVALID_HANDLE_VALUE;
end;
{$ENDIF} // FAR3

{$IFDEF UNICODE}
function ConfigureW(Item: Integer): Integer; stdcall;
{$ELSE}
function Configure(Item: Integer): Integer; stdcall;
{$ENDIF}
begin
  Result := Integer(DoConfigure);
end;

// ****************************************************************************

exports
  {$IFDEF UNICODE}SetStartupInfoW{$ELSE}SetStartupInfo{$ENDIF},
  {$IFDEF UNICODE}GetPluginInfoW{$ELSE}GetPluginInfo{$ENDIF},
{$IFDEF FAR3}
  GetGlobalInfoW, OpenW,
{$ELSE}
  {$IFDEF UNICODE}OpenPluginW{$ELSE}OpenPlugin{$ENDIF},
{$ENDIF}
  {$IFDEF UNICODE}ConfigureW{$ELSE}Configure{$ENDIF};

{$IFDEF FAR3}
const
  PluginGUIDValue: TGUID = '{b09c3594-024e-115e-78d5-f7270a53606d}';

begin
  PluginGUID := PluginGUIDValue;
{$ENDIF}

end.
