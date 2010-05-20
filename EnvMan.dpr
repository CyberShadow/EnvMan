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
  Windows, Types, {$IFDEF UNICODE}PluginW{$ELSE}Plugin{$ENDIF}, PluginEx;

// ****************************************************************************

var
  RegKey: FarString;

function RegGetStringRaw(Key: HKEY; Name: PFarChar; Default: FarString = ''): FarString;
var
  R: Integer;
  Size: Cardinal;
begin
  Result := Default;

  Size := 0;
  R := RegQueryValueExF(Key, Name, nil, nil, nil, @Size);
  if R<>ERROR_SUCCESS then
    Exit;
  
  SetLength(Result, Size div SizeOf(FarChar));
  if Size=0 then
    Exit;

  R := RegQueryValueExF(Key, Name, nil, nil, @Result[1], @Size);
  if R<>ERROR_SUCCESS then
    Result := Default;
end;

function RegGetString(Key: HKEY; Name: PFarChar; Default: FarString = ''): FarString;
begin
  Result := PFarChar(RegGetStringRaw(Key, Name, Default {+ #0}));
  {$IFNDEF UNICODE}
  CharToOem(PFarChar(Result), PFarChar(Result));
  {$ENDIF}
end;

function RegGetStrings(Key: HKEY; Name: PFarChar): TFarStringDynArray;
{$IFNDEF UNICODE}
var
  I: Integer;
{$ENDIF}
begin
  Result := NullStringsToArray(PFarChar(RegGetStringRaw(Key, Name)));
  {$IFNDEF UNICODE}
  for I:=0 to High(Result) do
    CharToOem(PFarChar(Result[I]), PFarChar(Result[I]));
  {$ENDIF}
end;

function RegGetInt(Key: HKEY; Name: PFarChar): Integer;
var
  Size: Cardinal;
begin
  Result := 0;
  Size := SizeOf(Result);
  RegQueryValueExF(Key, Name, nil, nil, @Result, @Size);
end;

procedure RegSetStringRaw(Key: HKEY; Name: PFarChar; Value: FarString; RegType: Cardinal);
begin
  RegSetValueExF(Key, Name, 0, RegType, @Value[1], Length(Value) * SizeOf(FarChar));
end;

procedure RegSetString(Key: HKEY; Name: PFarChar; Value: FarString);
begin
  {$IFNDEF UNICODE}
  OemToChar(@Value[1], @Value[1]);
  {$ENDIF}
  RegSetStringRaw(Key, Name, Value+#0, REG_SZ);
end;

procedure RegSetStrings(Key: HKEY; Name: PFarChar; Value: TFarStringDynArray);
{$IFNDEF UNICODE}
var
  I: Integer;
{$ENDIF}
begin
  {$IFNDEF UNICODE}
  for I:=0 to High(Value) do
    OemToChar(@Value[I][1], @Value[I][1]);
  {$ENDIF}
  
  RegSetStringRaw(Key, Name, ArrayToNullStrings(Value), REG_MULTI_SZ);
end;

procedure RegSetInt(Key: HKEY; Name: PFarChar; Value: Integer);
begin
  RegSetValueExF(Key, Name, 0, REG_DWORD, @Value, SizeOf(Value));
end;

function OpenPluginKey: HKEY;
begin
  Result := 0;
  RegCreateKeyExF(HKEY_CURRENT_USER, PFarChar(RegKey), 0, nil, 0, KEY_ALL_ACCESS, nil, Result, nil);
end;

function GetPluginString(Name: PFarChar; Default: FarString = ''): FarString;
var
  Key: HKEY;
begin
  Key := OpenPluginKey;
  Result := RegGetString(Key, Name, Default);
  RegCloseKey(Key);
end;

function GetIgnoredVariables: FarString;
begin
  Result := GetPluginString('IgnoredVariables', 'FARENV_EXPORT_HWND');
end;

procedure SetPluginString(Name: PFarChar; Value: FarString);
var
  Key: HKEY;
begin
  Key := OpenPluginKey;
  RegSetString(Key, Name, Value);
  RegCloseKey(Key);
end;

function OpenEntryKey(Index: Integer): HKEY;
begin
  Result := 0;
  RegCreateKeyExF(HKEY_CURRENT_USER, PFarChar(RegKey+'\'+IntToStr(Index)), 0, nil, 0, KEY_ALL_ACCESS, nil, Result, nil);
end;

function GetName(S: FarString): FarString;
begin
  Result := Copy(S, 1, Pos('=', S)-1);
end;

function GetValue(S: FarString): FarString;
begin
  Result := Copy(S, Pos('=', S)+1, MaxInt);
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
  Key, SubKey: HKEY;
  R, I: Integer;
begin
  Result := nil;
  R := RegCreateKeyExF(HKEY_CURRENT_USER, PFarChar(RegKey), 0, nil, 0, KEY_READ, nil, Key, nil);
  if R<>ERROR_SUCCESS then
    Exit;
  try
    I := 0;
    repeat
      R := RegOpenKeyExF(Key, PFarChar(IntToStr(I)), 0, KEY_READ, SubKey);
      if R<>ERROR_SUCCESS then
        Exit;
      try
        SetLength(Result, Length(Result)+1);
        Result[High(Result)].Name := RegGetString(SubKey, nil);
        Result[High(Result)].Vars := RegGetStrings(SubKey, 'Vars');
        Result[High(Result)].Enabled := Boolean(RegGetInt(SubKey, 'Enabled'));
      finally
        RegCloseKey(SubKey);
      end;
      Inc(I);
    until false;
  finally
    RegCloseKey(Key);
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

function DoConfigure(IgnoredVariables: FarString): Boolean;
const
  W = 75;
  H = 7;
  ItemNr = 5;
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
    Dialog.Items[IIgnoredVariables].Focus := 1;
    
    OK := Dialog.Add(DI_BUTTON, DIF_CENTERGROUP, 0, H-1-2, 0, 0, GetMsg(MOK));
    Dialog.Items[OK].DefaultButton := 1;
    
    Dialog.Add(DI_BUTTON, DIF_CENTERGROUP, 0, H-1-2, 0, 0, GetMsg(MCancel));

    Result := False;
    N := Dialog.Run(W, H, 'Configuration');
    if N <> OK then
      Exit;

    SetPluginString('IgnoredVariables', Dialog.GetData(IIgnoredVariables));
    Result := True;
  finally
    Dialog.Free;
  end;
end;

procedure SaveEntry(Index: Integer; var Entry: TEntry);
var
  Key: HKEY;
begin
  Key := OpenEntryKey(Index);
  RegSetString(Key, nil, Entry.Name);
  RegSetStrings(Key, 'Vars', Entry.Vars);
  RegSetInt(Key, 'Enabled', Ord(Entry.Enabled));
  RegCloseKey(Key);
end;

function EditEntryAlt(var Entry: TEntry): Boolean; forward;

function EditEntry(var Entry: TEntry; Caption: TMessage): Boolean;
const
  W = 75;
  Rows = 15;
  H = Rows + 8;
  ItemNr = 6; // not counting rows
  TotalItemNr = ItemNr+Rows;

var
  I, N: Integer;
  Dialog: TFarDialog;

begin
  if Length(Entry.Vars) > Rows then
  begin
    if Message(FMSG_WARNING or FMSG_MB_YESNO, [GetMsg(MWarning), GetMsg(MTooManyLines1), GetMsg(MTooManyLines2)])=0 then
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
    Dialog.Items[N].Param.History := 'EnvVarsName';
    if Entry.Name='' then
      Dialog.Items[N].Focus := 1;
    
    N := Dialog.Add(DI_CHECKBOX, DIF_NONE, W-1-5-10, 2, 0, 2, GetMsg(MEnabled));
    Dialog.Items[N].Param.Selected := Integer(Entry.Enabled);

    SetLength(Entry.Vars, Rows);
    for I:=0 to Rows-1 do
    begin
      N := Dialog.Add(DI_EDIT, DIF_EDITOR, 5, 4+I, W-1-5, 4+I, Entry.Vars[I], $10000);
      if (I=0) and (Entry.Name<>'') then
        Dialog.Items[N].Focus := 1;
    end;

    N := Dialog.Add(DI_BUTTON, DIF_CENTERGROUP, 0, H-1-2, 0, 0, GetMsg(MOK));
    Dialog.Items[N].DefaultButton := 1;
    
    Dialog.Add(DI_BUTTON, DIF_CENTERGROUP, 0, H-1-2, 0, 0, GetMsg(MCancel));

    Result := False;
    N := Dialog.Run(W, H, 'Editor');
    if N<>4+Rows then
      Exit;

    Entry.Name := Dialog.GetData(2);
    Entry.Enabled := Boolean(Dialog.Items[3].Param.Selected);
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

function EditEntryAlt(var Entry: TEntry): Boolean;
var
  Data: FarString;
begin
  Data := Join(EntryToLines(Entry), #13#10);
  Result := EditString(Data, Entry.Name + ' - EnvMan');
  if Result then
    Entry := LinesToEntry(SplitLines(Data));
end;

function EditEnvironment: Boolean;
var
  Data: FarString;
begin
  Data := Join(ReadEnvironment, #13#10);
  Result := EditString(Data, 'Environment');
  if Result then
    SetEnvironment(SplitLines(Data));
end;

procedure ShowEntryMenu(Quiet: Boolean);
var
  Entries: TEntryDynArray;
  Current: Integer;

  procedure InsertEntry(Index: Integer; var Entry: TEntry);
  var
    I: Integer;
  begin
    for I:=High(Entries) downto Index do
      SaveEntry(I+1, Entries[I]);
    SaveEntry(Index, Entry);
  end;

  procedure DeleteEntry(Index: Integer);
  var
    Key: HKEY;
    I: Integer;
  begin
    for I:=Index+1 to High(Entries) do
      SaveEntry(I-1, Entries[I]);
    Key := OpenPluginKey;
    RegDeleteKeyF(Key, PFarChar(IntToStr(High(Entries))));
    RegCloseKey(Key);
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
  Key: HKEY;
  Env, NewEnv: TFarStringDynArray;
  InitialEntries: TEntryDynArray;
  NewVars, ChangedVars, DeletedVars, AllVars: TFarStringDynArray;
const
  VK_CTRLUP   = VK_UP   or (PKF_CONTROL shl 16);
  VK_CTRLDOWN = VK_DOWN or (PKF_CONTROL shl 16);
  VK_SHIFTF3  = VK_F3   or (PKF_SHIFT   shl 16);
  VK_ALTF4    = VK_F4   or (PKF_ALT     shl 16);
  VK_SHIFTF4  = VK_F4   or (PKF_SHIFT   shl 16);
  BreakKeys: array[0..12] of Integer = (
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
    0
  );

begin
  Env := ReadEnvironment;

  if not Quiet and not StringsEqual(LastUpdate, Env) then
  begin
    Entry := MakeDiffEntry(LastUpdate, Env, NewVars, ChangedVars, DeletedVars);
    AllVars := ConcatStrings([NewVars, ChangedVars, DeletedVars]);
    Entry.Name := 'Imported: ' + Join(AllVars, ', ');
    Entry.Enabled := True;

    I := Message(FMSG_WARNING, ConcatStrings([
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
      Items[I].Selected := Integer(I=Current);
      Items[I].Checked := Integer(Entries[I].Enabled);
      Items[I].Separator := Integer({False}Entries[I].Name='-');
    end;
    Current := FARAPI.Menu(FARAPI.ModuleNumber, -1, -1, 0, FMENU_AUTOHIGHLIGHT or FMENU_WRAPMODE, 'Environment Manager', '+,-,Space,Ins,Del,F4,Alt-F4,F5,Ctrl-Up,Ctrl-Down,Shift+F4', 'MainMenu', @BreakKeys, @BreakCode, @Items[0], Length(Items));
    if (Current=-1) and (BreakCode=-1) then
      Break;
    case BreakCode of
      0: // VK_ADD
        if Current >= 0 then
        begin
          Key := OpenEntryKey(Current);
          RegSetInt(Key, 'Enabled', 1);
          MoveCurrent(1);
          RegCloseKey(Key);
        end;
      1: // VK_SUBTRACT
        if Current >= 0 then
        begin
          Key := OpenEntryKey(Current);
          RegSetInt(Key, 'Enabled', 0);
          MoveCurrent(1);
          RegCloseKey(Key);
        end;
      2: // VK_SPACE
        if Current >= 0 then
        begin
          Key := OpenEntryKey(Current);
          RegSetInt(Key, 'Enabled', 1-RegGetInt(Key, 'Enabled'));
          MoveCurrent(1);
          RegCloseKey(Key);
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
          if Message(FMSG_WARNING or FMSG_MB_OKCANCEL, [GetMsg(MConfirmDeleteTitle), GetMsg(MConfirmDeleteText), Entries[Current].Name])=0 then
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
        Message(FMSG_MB_OK, ConcatStrings([MakeStrings(['Environment']), Env]));
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
      end
      else // VK_RETURN / hotkey
        if Current >= 0 then
        begin
          Key := OpenEntryKey(Current);
          RegSetInt(Key, 'Enabled', 1-RegGetInt(Key, 'Enabled'));
          RegCloseKey(Key);
        end;
        //Break;
    end;
  until false;

  Update;
  NewEnv := ReadEnvironment;

  if not Quiet and EntriesEqual(InitialEntries, Entries) then // no changes
    if not StringsEqual(Env, NewEnv) then // but env has changed
    begin
      if Message(FMSG_WARNING, [
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
begin
  if not TryLoadText(FileName, S) then
  begin
    Message(FMSG_WARNING or FMSG_MB_OK, [GetMsg(MError), GetMsg(MFileLoadError), FileName]);
    Exit
  end;
  SetEnvironment(SplitLines(S));
end;

procedure ProcessCommandLine(PCmdLine: PFarChar);
var
  CmdLine, Name: FarString;
  Entries: TEntryDynArray;
  I: Integer;
begin
  CmdLine := PCmdLine;
  if Length(CmdLine)=0 then
    ShowEntryMenu(True)
  else
  if CmdLine[1]='<' then
    LoadEnv(Copy(CmdLine, 2, MaxInt))
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
          Message(FMSG_WARNING or FMSG_MB_OK, [GetMsg(MError), GetMsg(MBadCommandChar)]);
          Exit;
        end;
        SaveEntry(I, Entries[I]);
        Update;
        Exit;
      end;
    Message(FMSG_WARNING or FMSG_MB_OK, [GetMsg(MError), GetMsg(MNoSuchEntry), Name]);
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
  RegKey := FARAPI.RootKey + '\EnvMan';
  
  InitialEnvironment := ReadEnvironment;
  Update;
end;

var
  PluginMenuStrings, PluginConfigStrings: array[0..0] of PFarChar;

{$IFDEF UNICODE} 
procedure GetPluginInfoW(var pi: TPluginInfo); stdcall;
{$ELSE} 
procedure GetPluginInfo(var pi: TPluginInfo); stdcall;
{$ENDIF}
begin
  pi.StructSize := SizeOf(pi);
  pi.Flags := PF_PRELOAD or PF_EDITOR;

  PluginMenuStrings[0] := 'Environment Manager';
  pi.PluginMenuStrings := @PluginMenuStrings;
  pi.PluginMenuStringsNumber := 1;

  PluginConfigStrings[0] := 'Environment Manager';
  pi.PluginConfigStrings := @PluginConfigStrings;
  pi.PluginConfigStringsNumber := 1;

  pi.CommandPrefix := 'envman';
  pi.Reserved := $4D766E45; // 'EnvM'
end;

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

{$IFDEF UNICODE}
function ConfigureW(Item: Integer): Integer; stdcall;
{$ELSE}
function Configure(Item: Integer): Integer; stdcall;
{$ENDIF}
begin
  Result := Integer(DoConfigure(GetIgnoredVariables));
end;

// ****************************************************************************

exports
  {$IFDEF UNICODE}SetStartupInfoW{$ELSE}SetStartupInfo{$ENDIF},
  {$IFDEF UNICODE}GetPluginInfoW{$ELSE}GetPluginInfo{$ENDIF},
  {$IFDEF UNICODE}OpenPluginW{$ELSE}OpenPlugin{$ENDIF},
  {$IFDEF UNICODE}ConfigureW{$ELSE}Configure{$ENDIF};

end.
