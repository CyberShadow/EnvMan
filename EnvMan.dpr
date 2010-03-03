{$MINENUMSIZE 4}
{$RESOURCE EnvMan.res}

library EnvMan;

{
  TODO:
  * don't overwrite unmanaged variables
  * allow escaping % in strings
  * ANSI/OEM compatibility?
  * Unicode version?
  * help file?
  * don't use undocumented RegRenameKey API
}

uses Windows, Types, Plugin;

type
  TMessage = (MNewCaption, MEditCaption, MCopyCaption, MEnabled, MName, MOK, MCancel, MConfirmDeleteTitle, MConfirmDeleteText);

var
  FARAPI: TPluginStartupInfo;
  RegKey: String;
  InitialEnvironment: TStringDynArray;

function RegRenameKey(Key: HKEY; hz: Pointer; NewName: PWideChar): HRESULT; stdcall; external 'advapi32.dll';

// ****************************************************************************

// Convert a zero-terminated string sequence (which itself is 
// doubly-zero-terminated) to a TStringDynArray.
function StringsToArray(P: PChar): TStringDynArray;
var
  P2: PChar;
begin
  SetLength(Result, 0);
  while P^<>#0 do
  begin
    P2 := P;
    repeat
      Inc(P2);
    until P2^=#0;
    SetLength(Result, Length(Result)+1);
    Result[High(Result)] := Copy(P, 1, Cardinal(P2)-Cardinal(P)); // 32-bit only
    P := P2;
    Inc(P);
  end;
end;

function ArrayToStrings(A: TStringDynArray): String;
var
  I: Integer;
begin
  Result := '';
  for I:=0 to High(A) do
    if Length(A[I])>0 then
      Result := Result + A[I] + #0;
  Result := Result + #0;
end;

procedure CopyStrToBuf(S: String; Buf: PChar; BufSize: Integer);
begin
  if Length(S)>BufSize-1 then
    S := Copy(S, 1, BufSize-1);
  S := S+#0;
  Move(S[1], Buf^, Length(S));
end;

function IntToStr(I: Integer): String;
begin
  Str(I, Result);
end;

function RegGetString(Key: HKEY; Name: PChar): String;
var
  R: Integer;
  Size: Cardinal;
begin
  Result := 'x'; // hack
  Size := 0;
  R := RegQueryValueEx(Key, Name, nil, nil, @Result[1], @Size);
  if R=ERROR_MORE_DATA then
  begin
    SetLength(Result, Size);
    R := RegQueryValueEx(Key, Name, nil, nil, @Result[1], @Size);
    if R<>ERROR_SUCCESS then
      Result := '';
  end;
end;

function RegGetInt(Key: HKEY; Name: PChar): Integer;
var
  Size: Cardinal;
begin
  Result := 0;
  Size := 4;
  RegQueryValueEx(Key, Name, nil, nil, @Result, @Size);
end;

procedure RegSetString(Key: HKEY; Name: PChar; Value: String; RegType: Cardinal);
begin
  RegSetValueEx(Key, Name, 0, RegType, @Value[1], Length(Value));
end;

procedure RegSetInt(Key: HKEY; Name: PChar; Value: Integer);
begin
  RegSetValueEx(Key, Name, 0, REG_DWORD, @Value, 4);
end;

function OpenPluginKey: HKEY;
begin
  Result := 0;
  RegCreateKeyEx(HKEY_CURRENT_USER, PChar(RegKey), 0, nil, 0, KEY_ALL_ACCESS, nil, Result, nil);
end;

function OpenEntryKey(Index: Integer): HKEY;
begin
  Result := 0;
  RegCreateKeyEx(HKEY_CURRENT_USER, PChar(RegKey+'\'+IntToStr(Index)), 0, nil, 0, KEY_ALL_ACCESS, nil, Result, nil);
end;

procedure MoveEntry(I, J: Integer);
var
  Key: HKEY;
begin
  Key := OpenEntryKey(I);
  RegRenameKey(Key, nil, PWideChar(WideString(IntToStr(J))));
  RegCloseKey(Key);
end;

function GetName(S: String): String;
begin
  Result := Copy(S, 1, Pos('=', S)-1);
end;

procedure ApplyNameValuePair(S: String);
var
  P: Integer;
begin
  if S='' then
    Exit;
  if S[1] in [';','#'] then
    Exit;
  P := Pos('=', S);
  if P=0 then Exit;
  S[P] := #0;
  if P=Length(S) then
    SetEnvironmentVariable(@S[1], nil)
  else
    SetEnvironmentVariable(@S[1], @S[P+1]);
end;

function ReadEnvironment: TStringDynArray;
var
  Env: PChar;
begin
  Env := GetEnvironmentStrings;
  Result := StringsToArray(Env);
  FreeEnvironmentStrings(Env);
end;

function ExpandEnv(S: String): String;
begin
  SetLength(Result, ExpandEnvironmentStrings(PChar(S), nil, 0));
  ExpandEnvironmentStrings(PChar(S), @Result[1], Length(Result));
  SetLength(Result, Length(Result)-1); // terminating null
end;

// ****************************************************************************

type
  TEntry = record
    Name: String;
    Vars: TStringDynArray;
    Enabled: Boolean;
  end;
  TEntryDynArray = array of TEntry;

function ReadEntries: TEntryDynArray;
var
  Key, SubKey: HKEY;
  R, I: Integer;
begin
  Result := nil;
  R := RegCreateKeyEx(HKEY_CURRENT_USER, PChar(RegKey), 0, nil, 0, KEY_READ, nil, Key, nil);
  if R<>ERROR_SUCCESS then
    Exit;
  try
    I := 0;
    repeat
      R := RegOpenKeyEx(Key, PChar(IntToStr(I)), 0, KEY_READ, SubKey);
      if R<>ERROR_SUCCESS then
        Exit;
      try
        SetLength(Result, Length(Result)+1);
        Result[High(Result)].Name := PChar(RegGetString(SubKey, nil));
        Result[High(Result)].Vars := StringsToArray(PChar(RegGetString(SubKey, 'Vars')));
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

procedure Update;
var
  Entries: TEntryDynArray;
  Env: TStringDynArray;
  I, J: Integer;
begin
  // Entirely clear environment
  Env := ReadEnvironment;
  for I:=0 to High(Env) do
    SetEnvironmentVariable(PChar(GetName(Env[I])), nil);
  
  // Reset the environment to the initial state
  for I:=0 to High(InitialEnvironment) do
    ApplyNameValuePair(InitialEnvironment[I]);

  Entries := ReadEntries;
  for I:=0 to High(Entries) do
    if Entries[I].Enabled then
      for J:=0 to High(Entries[I].Vars) do
        ApplyNameValuePair(ExpandEnv(Entries[I].Vars[J]));
end;

// ****************************************************************************

procedure ShowMessage(S: String); // KILLME
begin
  FARAPI.Message(FARAPI.ModuleNumber, FMSG_ALLINONE or FMSG_MB_OK, nil, PPCharArray(PChar('ShowMessage'+#10+S)), 2, 0);
end;

function GetMsg(MsgId: TMessage): PChar;
begin
  Result := FARAPI.GetMsg(FARAPI.ModuleNumber, Integer(MsgId));
end;

procedure SetStartupInfo(var psi: TPluginStartupInfo); stdcall;
begin
  Move(psi, FARAPI, SizeOf(FARAPI));
  RegKey := FARAPI.RootKey + '\EnvMan';
  Update;
end;

var
  PluginMenuStrings: array[0..0] of PChar;

procedure GetPluginInfo(var pi: TPluginInfo); stdcall;
begin
  pi.StructSize := SizeOf(pi);
  pi.Flags := PF_PRELOAD or PF_EDITOR;

  PluginMenuStrings[0] := 'Environment Manager';
  pi.PluginMenuStrings := @PluginMenuStrings;
  pi.PluginMenuStringsNumber := 1;
end;

procedure SaveEntry(Index: Integer; var Entry: TEntry);
var
  Key: HKEY;
begin
  Key := OpenEntryKey(Index);
  RegSetString(Key, nil, Entry.Name+#0, REG_SZ);
  RegSetString(Key, 'Vars', ArrayToStrings(Entry.Vars), REG_MULTI_SZ);
  RegSetInt(Key, 'Enabled', Ord(Entry.Enabled));
  RegCloseKey(Key);
end;

function EditEntry(var Entry: TEntry; Caption: TMessage): Boolean;
const
  W = 75;
  Rows = 15;
  H = Rows + 8;
  ItemNr = 6; // not counting rows
var
  Items: array[0..ItemNr+Rows-1] of TFarDialogItem;
  I: Integer;
begin
  FillChar(Items, SizeOf(Items), 0);
  
  Items[0].ItemType := DI_DOUBLEBOX;
  Items[0].X1 := 3;
  Items[0].Y1 := 1;
  Items[0].X2 := W-1-3;
  Items[0].Y2 := H-1-1;
  CopyStrToBuf(GetMsg(Caption), Items[0].Data.Data, SizeOf(Items[0].Data.Data));
  
  Items[1].ItemType := DI_EDIT;
  Items[1].X1 := 11;
  Items[1].Y1 := 2;
  Items[1].X2 := W-1-5-13;
  Items[1].Y2 := 2;
  Items[1].Param.History := 'EnvVarsName';
  Items[1].Flags := DIF_HISTORY;
  CopyStrToBuf(Entry.Name, Items[1].Data.Data, SizeOf(Items[1].Data.Data));

  Items[2].ItemType := DI_CHECKBOX;
  Items[2].X1 := W-1-5-10;
  Items[2].Y1 := 2;
  Items[2].Y2 := 2;
  Items[2].Param.Selected := Entry.Enabled;
  CopyStrToBuf(GetMsg(MEnabled), Items[2].Data.Data, SizeOf(Items[2].Data.Data));

  Items[3].ItemType := DI_TEXT;
  Items[3].X1 := 5;
  Items[3].Y1 := 2;
  Items[3].X2 := 10;
  Items[3].Y2 := 2;
  CopyStrToBuf(GetMsg(MName), Items[3].Data.Data, SizeOf(Items[3].Data.Data));

  for I:=0 to Rows-1 do
  begin
    Items[4+I].ItemType := DI_EDIT;
    Items[4+I].X1 := 5;
    Items[4+I].Y1 := 4+I;
    Items[4+I].X2 := W-1-5;
    Items[4+I].Y2 := 4+I;
    Items[4+I].Flags := DIF_EDITOR;
    if I=0 then
      Items[4+I].Focus := 1;
    if I<Length(Entry.Vars) then
      CopyStrToBuf(Entry.Vars[I], Items[4+I].Data.Data, SizeOf(Items[4+I].Data.Data));
  end;

  Items[4+Rows].ItemType := DI_BUTTON;
  Items[4+Rows].Y1 := H-1-2;
  Items[4+Rows].Flags := DIF_CENTERGROUP;
  Items[4+Rows].DefaultButton := true;
  CopyStrToBuf(GetMsg(MOK), Items[4+Rows].Data.Data, SizeOf(Items[4+Rows].Data.Data));

  Items[5+Rows].ItemType := DI_BUTTON;
  Items[5+Rows].Y1 := H-1-2;
  Items[5+Rows].Flags := DIF_CENTERGROUP;
  Items[5+Rows].DefaultButton := true;
  CopyStrToBuf(GetMsg(MCancel), Items[5+Rows].Data.Data, SizeOf(Items[5+Rows].Data.Data));

  Result := False;
  I := FARAPI.Dialog(FARAPI.ModuleNumber, -1, -1, W, H, nil, @Items[0], Length(Items));
  if I<>4+Rows then
    Exit;
  
  SetLength(Entry.Vars, 1);
  Entry.Name := PChar(@Items[1].Data.Data[0]);
  Entry.Enabled := Items[2].Param.Selected;
  SetLength(Entry.Vars, Rows);
  for I:=0 to Rows-1 do
    Entry.Vars[I] := PChar(@Items[4+I].Data.Data[0]);
  Result := True;
end;

function OpenPlugin(OpenFrom: Integer; Item: Integer): THandle; stdcall;
var
  Entries: TEntryDynArray;
  Current: Integer;

procedure InsertEntry(Index: Integer; var Entry: TEntry);
var
  I: Integer;
begin
  for I:=High(Entries) downto Index do
    MoveEntry(I, I+1);
  SaveEntry(Index, Entry);
end;

procedure DeleteEntry(Index: Integer);
var
  Key: HKEY;
  I: Integer;
begin
  Key := OpenPluginKey;
  RegDeleteKey(Key, PChar(IntToStr(Index)));
  RegCloseKey(Key);
  for I:=Index+1 to High(Entries) do
    MoveEntry(I, I-1);
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
      CopyStrToBuf(Entries[I].Name, Items[I].Text, SizeOf(Items[I].Text));
      Items[I].Selected := I=Current;
      Items[I].Checked := Entries[I].Enabled;
      Items[I].Separator := {False}Entries[I].Name='-';
    end;
    Current := FARAPI.Menu(FARAPI.ModuleNumber, -1, -1, 0, FMENU_AUTOHIGHLIGHT or FMENU_WRAPMODE, 'Environment Manager', '+,-,Space,Ins,Del,F4,F5,Ctrl-Up,Ctrl-Down', nil, @BreakKeys, @BreakCode, @Items[0], Length(Items));
    //ShowMessage('Current='+IntToStr(Current)+',BreakCode='+IntToStr(BreakCode));
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
          if FARAPI.Message(FARAPI.ModuleNumber, FMSG_WARNING or FMSG_ALLINONE or FMSG_MB_OKCANCEL, nil, PPCharArray(PChar(GetMsg(MConfirmDeleteTitle)+#10+GetMsg(MConfirmDeleteText)+#10+Entries[Current].Name)), 3, 0)=0 then
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
      begin
        if Current=0 then // create separator
        begin
          Entry.Name := '-';
          Entry.Vars := nil;
          Entry.Enabled := False;
          InsertEntry(0, Entry);
          Inc(Current);
        end;
        MoveEntry(Current, -1);
        MoveEntry(Current-1, Current);
        MoveEntry(-1, Current-1);
        Dec(Current);
      end;
      8: // VK_CTRLDOWN
      begin
        if Current=High(Entries) then // create separator
        begin
          Entry.Name := '-';
          Entry.Vars := nil;
          Entry.Enabled := False;
          SaveEntry(Current+1, Entry);
        end;
        MoveEntry(Current, -1);
        MoveEntry(Current+1, Current);
        MoveEntry(-1, Current+1);
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
  Result := INVALID_HANDLE_VALUE;
end;

exports
  SetStartupInfo,
  GetPluginInfo,
  OpenPlugin;

begin
  Randomize; // KILLME
  InitialEnvironment := ReadEnvironment;
end.
