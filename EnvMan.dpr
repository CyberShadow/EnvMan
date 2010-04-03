{$MINENUMSIZE 4}
{$RESOURCE EnvMan.res}

library EnvMan;

{
  TODO:
  * allow escaping % in strings
  * Russian help file
  * "Ignore" setting
  * Command-line handler
  * better error checking?
}

uses Windows, Types, {$IFDEF UNICODE}PluginW{$ELSE}Plugin{$ENDIF}, PluginEx;

type
  TMessage = (
    MNewCaption, 
    MEditCaption, 
    MCopyCaption, 
    MImportCaption, 
    
    MEnabled, 
    MName, 
    MOK, 
    MCancel, 
    
    MConfirmDeleteTitle, 
    MConfirmDeleteText,
    
    MWarning,
    MEnvEdited1,
    MEnvEdited2,
    MEnvEdited3,
    MContinue,
    MImport,

    MNoChange1,
    MNoChange2,
    MNoChange3,
    MOverwrite,
    MKeep
  );

// ****************************************************************************

var
  RegKey: FarString;

function RegGetString(Key: HKEY; Name: PFarChar): FarString;
var
  R: Integer;
  Size: Cardinal;
begin
  Result := 'x'; // hack for @Result[1]
  Size := 0;
  R := RegQueryValueExF(Key, Name, nil, nil, @Result[1], @Size);
  if R=ERROR_MORE_DATA then
  begin
    SetLength(Result, Size div SizeOf(FarChar));
    R := RegQueryValueExF(Key, Name, nil, nil, @Result[1], @Size);
    if R<>ERROR_SUCCESS then
      Result := '';
  end;
  {$IFNDEF UNICODE}
  CharToOem(@Result[1], @Result[1]);
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

procedure RegSetString(Key: HKEY; Name: PFarChar; Value: FarString; RegType: Cardinal);
begin
  {$IFNDEF UNICODE}
  OemToChar(@Value[1], @Value[1]);
  {$ENDIF}
  RegSetValueExF(Key, Name, 0, RegType, @Value[1], Length(Value) * SizeOf(FarChar));
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
  if (S[1]=';') or (S[1]='#') then
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
function RemoveSpecial(A: TFarStringDynArray): TFarStringDynArray;
var
  I: Integer;
begin
  Result := nil;
  for I:=0 to High(A) do
    if (Length(A[I])>0) and (A[I][1] <> '=') then
    begin
      SetLength(Result, Length(Result)+1);
      Result[High(Result)] := A[I];
    end;
end;

function ReadEnvironment: TFarStringDynArray;
var
  Env: PFarChar;
begin
  Env := GetEnvironmentStringsF;
  Result := RemoveSpecial(NullStringsToArray(Env));
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
        Result[High(Result)].Name := PFarChar(RegGetString(SubKey, nil));
        Result[High(Result)].Vars := NullStringsToArray(PFarChar(RegGetString(SubKey, 'Vars')));
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

function EntryDiff(Env1, Env2: TFarStringDynArray): TEntry;
var
  I, J: Integer;
  Found, FoundEqual: Boolean;
  Name, NewValue, OldValue: String;

  procedure AppendSetting(Name, Value: FarString);
  begin
    SetLength(Result.Vars, Length(Result.Vars)+1);
    Result.Vars[High(Result.Vars)] := Name+'='+Value;
    if Result.Name<>'' then
      Result.Name := Result.Name + ', ';
    Result.Name := Result.Name + Name;
  end;

begin
  // Find new and modified variables
  for J:=0 to High(Env2) do
  begin
    FoundEqual := False;
    Name := GetName(Env2[J]);
    NewValue := GetValue(Env2[J]);
    for I:=0 to High(Env1) do
      if GetName(Env1[I])=Name then
      begin
        OldValue := GetValue(Env1[I]);
        if NewValue=OldValue then
          FoundEqual := True
        else
        begin
          if Copy(NewValue, 1, Length(OldValue))=OldValue then // append
            NewValue := '%'+Name+'%'+Copy(NewValue, Length(OldValue)+1, MaxInt)
          else
          if Copy(NewValue, Length(NewValue)-Length(OldValue)+1, Length(OldValue))=OldValue then // prepend
            NewValue := Copy(NewValue, Length(NewValue)-Length(OldValue)+1, MaxInt)+'%'+Name+'%';
        end;
        Break;
      end;
    if not FoundEqual then
      AppendSetting(Name, NewValue);
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
      AppendSetting(Name, '');
  end;
end;

// ****************************************************************************

function GetMsg(MsgId: TMessage): PFarChar;
begin
  Result := FARAPI.GetMsg(FARAPI.ModuleNumber, Integer(MsgId));
end;

{$IFDEF UNICODE}
procedure SetStartupInfoW(var psi: TPluginStartupInfo); stdcall;
{$ELSE}
procedure SetStartupInfo(var psi: TPluginStartupInfo); stdcall;
{$ENDIF}
begin
  Move(psi, FARAPI, SizeOf(FARAPI));
  RegKey := FARAPI.RootKey + '\EnvMan';
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
end;

procedure SaveEntry(Index: Integer; var Entry: TEntry);
var
  Key: HKEY;
begin
  Key := OpenEntryKey(Index);
  RegSetString(Key, nil, Entry.Name+#0, REG_SZ);
  RegSetString(Key, 'Vars', ArrayToNullStrings(Entry.Vars), REG_MULTI_SZ);
  RegSetInt(Key, 'Enabled', Ord(Entry.Enabled));
  RegCloseKey(Key);
end;

function EditEntry(var Entry: TEntry; Caption: TMessage): Boolean;
const
  W = 75;
  Rows = 15;
  H = Rows + 8;
  ItemNr = 6; // not counting rows
  TotalItemNr = ItemNr+Rows;
var
  Items: array[0..TotalItemNr-1] of TFarDialogItem;
  I: Integer;
{$IFDEF UNICODE}
  Data: array[0..TotalItemNr-1] of FarString;
  Handle: THandle;
{$ENDIF}
  
  procedure SetupData(Index: Integer; InitialData: FarString);
  begin
    {$IFNDEF UNICODE}
    CopyStrToBuf(InitialData, Items[Index].Data.Data, SizeOf(Items[Index].Data.Data));
    {$ELSE}
    Data[Index] := InitialData;
    Items[Index].PtrData := @Data[Index][1];
    Items[Index].MaxLen := 0;
    {$ENDIF}
  end;

  function GetData(Index: Integer): FarString;
  begin
    {$IFNDEF UNICODE}
    Result := PFarChar(@Items[Index].Data.Data[0])
    {$ELSE}
    Result := PFarChar(FARAPI.SendDlgMessage(Handle, DM_GETCONSTTEXTPTR, Index, 0));
    {$ENDIF}
  end;

begin
  FillChar(Items, SizeOf(Items), 0);

  Items[0].ItemType := DI_DOUBLEBOX;
  Items[0].X1 := 3;
  Items[0].Y1 := 1;
  Items[0].X2 := W-1-3;
  Items[0].Y2 := H-1-1;
  SetupData(0, GetMsg(Caption));

  Items[1].ItemType := DI_EDIT;
  Items[1].X1 := 11;
  Items[1].Y1 := 2;
  Items[1].X2 := W-1-5-13;
  Items[1].Y2 := 2;
  Items[1].Param.History := 'EnvVarsName';
  Items[1].Flags := DIF_HISTORY;
  if Entry.Name='' then
    Items[1].Focus := 1;
  SetupData(1, Entry.Name);

  Items[2].ItemType := DI_CHECKBOX;
  Items[2].X1 := W-1-5-10;
  Items[2].Y1 := 2;
  Items[2].Y2 := 2;
  Items[2].Param.Selected := Integer(Entry.Enabled);
  SetupData(2, GetMsg(MEnabled));

  Items[3].ItemType := DI_TEXT;
  Items[3].X1 := 5;
  Items[3].Y1 := 2;
  Items[3].X2 := 10;
  Items[3].Y2 := 2;
  SetupData(3, GetMsg(MName));

  for I:=0 to Rows-1 do
  begin
    Items[4+I].ItemType := DI_EDIT;
    Items[4+I].X1 := 5;
    Items[4+I].Y1 := 4+I;
    Items[4+I].X2 := W-1-5;
    Items[4+I].Y2 := 4+I;
    Items[4+I].Flags := DIF_EDITOR;
    if (I=0) and (Entry.Name<>'') then
      Items[4+I].Focus := 1;
    if I<Length(Entry.Vars) then
      SetupData(4+I, Entry.Vars[I]);
  end;

  Items[4+Rows].ItemType := DI_BUTTON;
  Items[4+Rows].Y1 := H-1-2;
  Items[4+Rows].Flags := DIF_CENTERGROUP;
  Items[4+Rows].DefaultButton := 1;
  SetupData(4+Rows, GetMsg(MOK));

  Items[5+Rows].ItemType := DI_BUTTON;
  Items[5+Rows].Y1 := H-1-2;
  Items[5+Rows].Flags := DIF_CENTERGROUP;
  SetupData(5+Rows, GetMsg(MCancel));

  Result := False;
  {$IFNDEF UNICODE}
  I := FARAPI.Dialog(FARAPI.ModuleNumber, -1, -1, W, H, 'Editor', @Items[0], Length(Items));
  {$ELSE}
  Handle := FARAPI.DialogInit(FARAPI.ModuleNumber, -1, -1, W, H, 'Editor', @Items[0], Length(Items), 0, 0, nil, 0);
  I := FARAPI.DialogRun(Handle);
  {$ENDIF}
  if I<>4+Rows then
  begin
    {$IFDEF UNICODE}FARAPI.DialogFree(Handle);{$ENDIF}
    Exit;
  end;

  SetLength(Entry.Vars, 1);
  Entry.Name := GetData(1);
  Entry.Enabled := Boolean(Items[2].Param.Selected);
  SetLength(Entry.Vars, Rows);
  for I:=0 to Rows-1 do
    Entry.Vars[I] := GetData(4+I);
  {$IFDEF UNICODE}FARAPI.DialogFree(Handle);{$ENDIF}
  Result := True;
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
const
  VK_CTRLUP   = VK_UP   or (PKF_CONTROL shl 16);
  VK_CTRLDOWN = VK_DOWN or (PKF_CONTROL shl 16);
  BreakKeys: array[0..9] of Integer = (
    VK_ADD,
    VK_SUBTRACT,
    VK_SPACE,
    VK_INSERT,
    VK_DELETE,
    VK_F4,
    VK_F5,
    VK_CTRLUP,
    VK_CTRLDOWN,
    0
  );

begin
  Env := ReadEnvironment;
  if not Quiet and not StringsEqual(LastUpdate, Env) then
  begin
    I := FARAPI.Message(FARAPI.ModuleNumber, FMSG_WARNING or FMSG_ALLINONE, nil, PPCharArray(PFarChar(
      PToStr(GetMsg(MWarning))+#10+
      PToStr(GetMsg(MEnvEdited1))+#10+
      PToStr(GetMsg(MEnvEdited2))+#10+
      PToStr(GetMsg(MEnvEdited3))+#10+
      PToStr(GetMsg(MContinue))+#10+
      PToStr(GetMsg(MCancel))+#10+
      PToStr(GetMsg(MImport)))), 7, 3);
    if (I=1) or (I=-1) then
      Exit;
    if I=2 then // import
    begin
      Entry := EntryDiff(LastUpdate, Env);
      Entry.Name := 'Imported: ' + Entry.Name;
      Entry.Enabled := True;
      if EditEntry(Entry, MImportCaption) then
      begin
        Entries := ReadEntries;
        SaveEntry(Length(Entries), Entry);
      end
      else
        Exit; // User cancelled
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
    Current := FARAPI.Menu(FARAPI.ModuleNumber, -1, -1, 0, FMENU_AUTOHIGHLIGHT or FMENU_WRAPMODE, 'Environment Manager', '+,-,Space,Ins,Del,F4,F5,Ctrl-Up,Ctrl-Down', 'MainMenu', @BreakKeys, @BreakCode, @Items[0], Length(Items));
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
          if FARAPI.Message(FARAPI.ModuleNumber, FMSG_WARNING or FMSG_ALLINONE or FMSG_MB_OKCANCEL, nil, PPCharArray(PFarChar(PToStr(GetMsg(MConfirmDeleteTitle))+#10+PToStr(GetMsg(MConfirmDeleteText))+#10+Entries[Current].Name)), 3, 0)=0 then
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
      if FARAPI.Message(FARAPI.ModuleNumber, FMSG_WARNING or FMSG_ALLINONE, nil, PPCharArray(PFarChar(
        PToStr(GetMsg(MWarning))+#10+
        PToStr(GetMsg(MNoChange1))+#10+
        PToStr(GetMsg(MNoChange2))+#10+
        PToStr(GetMsg(MNoChange3))+#10+
        PToStr(GetMsg(MOverwrite))+#10+
        PToStr(GetMsg(MKeep)))), 7, 2)<>0 then // Keep was selected?
      begin
        // Restore last environment
        SetEnvironment(Env);
        LastUpdate := Env;
      end;
    end;
end;

{$IFDEF UNICODE}
function OpenPluginW(OpenFrom: Integer; Item: Integer): THandle; stdcall;
{$ELSE}
function OpenPlugin(OpenFrom: Integer; Item: Integer): THandle; stdcall;
{$ENDIF}
var
  FromMacro: Boolean;
begin
  FromMacro := False;
  {$IFDEF UNICODE}
  if (OpenFrom and OPEN_FROMMACRO)<>0 then
  begin
    FromMacro := True;
    OpenFrom := OpenFrom and not OPEN_FROMMACRO;
  end;
  {$ENDIF}

  ShowEntryMenu(FromMacro);
  Result := INVALID_HANDLE_VALUE;
end;

exports
  {$IFDEF UNICODE}SetStartupInfoW{$ELSE}SetStartupInfo{$ENDIF},
  {$IFDEF UNICODE}GetPluginInfoW{$ELSE}GetPluginInfo{$ENDIF},
  {$IFDEF UNICODE}OpenPluginW{$ELSE}OpenPlugin{$ENDIF};

begin
  InitialEnvironment := ReadEnvironment;
end.
