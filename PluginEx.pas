// Helper unit for Delphi FAR plugins.
unit PluginEx;

interface

uses
  Windows, {$IFDEF UNICODE}PluginW{$ELSE}Plugin{$ENDIF};

type
{$IFNDEF UNICODE}
  TFarChar = AnsiChar;
  PFarChar = PAnsiChar;
  FarString = AnsiString;
{$ELSE}
  FarString = WideString;
{$ENDIF}
  FarChar = TFarChar;
  TFarStringDynArray = array of FarString;
  
function PToStr(P: PFarChar): FarString; inline; // work around Delphi's strict type declarations
function CharToOemStr(S: FarString): FarString;
function OemToCharStr(S: FarString): FarString;
function NullStringsToArray(P: PFarChar): TFarStringDynArray;
function ArrayToNullStrings(A: TFarStringDynArray): FarString;
procedure CopyStrToBuf(S: FarString; Buf: PFarChar; BufSize: Integer);
function IntToStr(I: Integer): FarString; inline;
function LoadString(FileName: FarString): FarString;
function TryLoadString(FileName: FarString; var Data: FarString): Boolean;
procedure SaveString(FileName, Data: FarString);
function StrReplace(Haystack, Source, Dest: FarString): FarString;
function Trim(S: FarString): FarString;
function Split(S: FarString; Delim: FarString): TFarStringDynArray;
function SplitByAny(S, Delims: FarString): TFarStringDynArray;
function SplitLines(S: FarString): TFarStringDynArray;
function Join(S: TFarStringDynArray; Delim: FarString): FarString;
function MakeStrings(const S: array of FarString): TFarStringDynArray;
procedure AppendToStrings(var Strings: TFarStringDynArray; S: FarString);
function ConcatStrings(const S: array of TFarStringDynArray): TFarStringDynArray;
function GetTempFullFileName(PrefixString: FarString='Far'): FarString;

// ANSI/UNICODE wrappers for WinAPI functions
function RegCreateKeyExF(hKey: HKEY; lpSubKey: PFarChar; Reserved: DWORD; lpClass: PFarChar; dwOptions: DWORD; samDesired: REGSAM; lpSecurityAttributes: PSecurityAttributes; var phkResult: HKEY; lpdwDisposition: PDWORD): Longint; inline;
function RegOpenKeyExF(hKey: HKEY; lpSubKey: PFarChar; ulOptions: DWORD; samDesired: REGSAM; var phkResult: HKEY): Longint; inline;
function RegQueryValueExF(hKey: HKEY; lpValueName: PFarChar; lpReserved: Pointer; lpType: PDWORD; lpData: PByte; lpcbData: PDWORD): Longint; inline;
function RegSetValueExF(hKey: HKEY; lpValueName: PFarChar; Reserved: DWORD; dwType: DWORD; lpData: Pointer; cbData: DWORD): Longint; inline;
function RegDeleteKeyF(hKey: HKEY; lpSubKey: PFarChar): Longint; inline;
function SetEnvironmentVariableF(lpName, lpValue: PFarChar): BOOL; inline;
function GetEnvironmentStringsF: PFarChar; inline;
function FreeEnvironmentStringsF(EnvBlock: PFarChar): BOOL; inline;
function ExpandEnvironmentStringsF(lpSrc: PFarChar; lpDst: PFarChar; nSize: DWORD): DWORD; inline;
function GetTempPathF(nBufferLength: DWORD; lpBuffer: PFarChar): DWORD;
function GetTempFileNameF(lpPathName, lpPrefixString: PFarChar; uUnique: UINT; lpTempFileName: PFarChar): UINT;
function DeleteFileF(lpFileName: PFarChar): BOOL;

type
  TFarDialog = class
    Items: array of TFarDialogItem;
    function Add(ItemType, Flags: Integer; X1, Y1, X2, Y2: Integer; InitialData: FarString; MaxLen: Integer = 0): Integer;
    function Run(W, H: Integer; HelpTopic: PFarChar = nil): Integer;
    function GetData(Index: Integer): FarString;
  {$IFDEF UNICODE}
    destructor Destroy; override;
  {$ENDIF}
  private
    Data: TFarStringDynArray;
  {$IFDEF UNICODE}
    Handle: THandle;
  {$ENDIF}
  end;

function Message(Flags: DWORD; const Lines: array of FarString; ButtonCount: Integer = 0; HelpTopic: PFarChar = nil): Integer;

{$IFNDEF UNICODE}
const OPEN_FROMMACRO = $10000; // not in Plugin.pas
{$ENDIF}

const DIF_NONE = 0;

var
  FARAPI: TPluginStartupInfo;

implementation

// ************************************************************************************************************************************************************

function PToStr(P: PFarChar): FarString; inline;
begin
{$IFNDEF UNICODE}
  Result := PChar(P);
{$ELSE}
  Result := PWideChar(P);
{$ENDIF}
end;

function CharToOemStr(S: FarString): FarString;
begin
{$IFNDEF UNICODE}
  SetLength(Result, Length(S));
  CharToOem(PFarChar(S), @Result[1]);
{$ELSE}
  Result := S;
{$ENDIF}
end;

function OemToCharStr(S: FarString): FarString;
begin
{$IFNDEF UNICODE}
  SetLength(Result, Length(S));
  OemToChar(PFarChar(S), @Result[1]);
{$ELSE}
  Result := S;
{$ENDIF}
end;

// Convert a zero-terminated string sequence (which itself is
// doubly-zero-terminated) to a TStringDynArray.
function NullStringsToArray(P: PFarChar): TFarStringDynArray;
var
  P2: PFarChar;
begin
  SetLength(Result, 0);
  while P^<>#0 do
  begin
    P2 := P;
    repeat
      Inc(P2);
    until P2^=#0;
    SetLength(Result, Length(Result)+1);
    Result[High(Result)] := Copy(P, 1, UINT_PTR(P2)-UINT_PTR(P));
    P := P2;
    Inc(P);
  end;
end;

function ArrayToNullStrings(A: TFarStringDynArray): FarString;
var
  I: Integer;
begin
  Result := '';
  for I:=0 to High(A) do
    if Length(A[I])>0 then
      Result := Result + A[I] + #0;
  Result := Result + #0;
end;

procedure CopyStrToBuf(S: FarString; Buf: PFarChar; BufSize: Integer);
begin
  if Length(S)>BufSize-1 then
    S := Copy(S, 1, BufSize-1);
  S := S+#0;
  Move(S[1], Buf^, Length(S) * SizeOf(FarChar));
end;

// To avoid pulling in heavy SysUtils unit
function IntToStr(I: Integer): FarString; inline;
begin
  Str(I, Result);
end;

function LoadString(FileName: FarString): FarString;
var
  F: File;
  OldFileMode: Integer;
begin
  OldFileMode := FileMode; FileMode := {fmOpenRead}0;
  Assign(F, FileName);
  Reset(F, SizeOf(FarChar));
  FileMode := OldFileMode;
  SetLength(Result, FileSize(F));
  if FileSize(F)>0 then
    BlockRead(F, Result[1], FileSize(F));
  CloseFile(F);
end;

function TryLoadString(FileName: FarString; var Data: FarString): Boolean;
var
  F: File;
  OldFileMode: Integer;
begin
  OldFileMode := FileMode; FileMode := {fmOpenRead}0;
  Assign(F, FileName);
  {$I-}
  Reset(F, SizeOf(FarChar));
  {$I+}
  FileMode := OldFileMode;
  Result := False;
  if IOResult<>0 then
    Exit;
  SetLength(Data, FileSize(F));
  if FileSize(F)>0 then
    BlockRead(F, Data[1], FileSize(F));
  CloseFile(F);
  Result := True;
end;

procedure SaveString(FileName, Data: FarString);
var
  F: File;
begin
  Assign(F, FileName);
  ReWrite(F, SizeOf(FarChar));
  BlockWrite(F, Data[1], Length(Data));
  CloseFile(F);
end;

function StrReplace(Haystack, Source, Dest: FarString): FarString;
var
  P: Integer;
begin
  Result := Haystack;
  while true do
  begin
    P := Pos(Source, Result);
    if P=0 then
      Exit;
    Delete(Result, P, Length(Source));
    Insert(Result, Dest, P);
  end;
end;

function Trim(S: FarString): FarString;
begin
  while Copy(S, 1, 1)=' ' do
    Delete(S, 1, 1);
  while (Length(S)>0) and (Copy(S, Length(S), 1)=' ') do
    Delete(S, Length(S), 1);
  Result := S;
end;

function PosAny(Delims, S: FarString): Integer;
var
  I, P: Integer;
begin
  Result := 0;
  for I := 1 to Length(Delims) do
  begin
    P := Pos(Delims[I], S);
    if (Result=0) or ((P <> 0) and (P < Result)) then
      Result := P;
  end;
end;

function Split(S: FarString; Delim: FarString): TFarStringDynArray;
var
  P: Integer;
begin
  Result := nil;
  if S='' then Exit;
  S := S + Delim;
  while S<>'' do
  begin
    SetLength(Result, Length(Result)+1);
    P := Pos(Delim, S);
    Result[High(Result)] := Copy(S, 1, P-1);
    Delete(S, 1, P-1+Length(Delim));
  end;
end;

function SplitByAny(S, Delims: FarString): TFarStringDynArray;
var
  P: Integer;
begin
  Result := nil;
  if S='' then Exit;
  S := S + Delims[1];
  while S<>'' do
  begin
    SetLength(Result, Length(Result)+1);
    P := PosAny(Delims, S);
    Result[High(Result)] := Copy(S, 1, P-1);
    Delete(S, 1, P);
  end;
end;

function SplitLines(S: FarString): TFarStringDynArray;
var
  I: Integer;
begin
  Result := Split(S, #10);
  for I:=0 to High(Result) do
  begin
    while Copy(Result[I], 1, 1)=#13 do
      Delete(Result[I], 1, 1);
    while Copy(Result[I], Length(Result[I]), 1)=#13 do
      Delete(Result[I], Length(Result[I]), 1);
  end;
end;

function Join(S: TFarStringDynArray; Delim: FarString): FarString;
var
  I: Integer;
begin
  Result := '';
  for I:=0 to High(S) do
  begin
    if I>0 then
      Result := Result + Delim;
    Result := Result + S[I];
  end;
end;

function MakeStrings(const S: array of FarString): TFarStringDynArray;
var
  I: Integer;
begin
  SetLength(Result, Length(S));
  for I:=0 to High(S) do
    Result[I] := S[I];
end;

procedure AppendToStrings(var Strings: TFarStringDynArray; S: FarString);
begin
  SetLength(Strings, Length(Strings)+1);
  Strings[High(Strings)] := S;
end;

function ConcatStrings(const S: array of TFarStringDynArray): TFarStringDynArray;
var
  I, J, N: Integer;
begin
  Result := nil;
  for I:=0 to High(S) do
  begin
    N := Length(Result);
    SetLength(Result, Length(Result)+Length(S[I]));
    for J:=0 to High(S[I]) do
      Result[N+J] := S[I][J];
  end;
end;

function GetTempFullFileName(PrefixString: FarString='Far'): FarString;
var
  Path: array[0..MAX_PATH] of FarChar;
begin
  GetTempPathF(MAX_PATH, @Path[0]);
  GetTempFileNameF(@Path[0], PFarChar(PrefixString), 0, @Path[0]);
  Result := PFarChar(@Path[0]);
end;

// ************************************************************************************************************************************************************

function RegCreateKeyExF(hKey: HKEY; lpSubKey: PFarChar; Reserved: DWORD; lpClass: PFarChar; dwOptions: DWORD; samDesired: REGSAM; lpSecurityAttributes: PSecurityAttributes; var phkResult: HKEY; lpdwDisposition: PDWORD): Longint; inline;
begin
  Result := {$IFNDEF UNICODE}RegCreateKeyExA{$ELSE}RegCreateKeyExW{$ENDIF}(hKey, lpSubKey, Reserved, lpClass, dwOptions, samDesired, lpSecurityAttributes, phkResult, lpdwDisposition);
end;

function RegOpenKeyExF(hKey: HKEY; lpSubKey: PFarChar; ulOptions: DWORD; samDesired: REGSAM; var phkResult: HKEY): Longint; inline;
begin
  Result := {$IFNDEF UNICODE}RegOpenKeyExA{$ELSE}RegOpenKeyExW{$ENDIF}(hKey, lpSubKey, ulOptions, samDesired, phkResult);
end;

function RegQueryValueExF(hKey: HKEY; lpValueName: PFarChar; lpReserved: Pointer; lpType: PDWORD; lpData: PByte; lpcbData: PDWORD): Longint; inline;
begin
  Result := {$IFNDEF UNICODE}RegQueryValueExA{$ELSE}RegQueryValueExW{$ENDIF}(hKey, lpValueName, lpReserved, lpType, lpData, lpcbData);
end;

function RegSetValueExF(hKey: HKEY; lpValueName: PFarChar; Reserved: DWORD; dwType: DWORD; lpData: Pointer; cbData: DWORD): Longint; inline;
begin
  Result := {$IFNDEF UNICODE}RegSetValueExA{$ELSE}RegSetValueExW{$ENDIF}(hKey, lpValueName, Reserved, dwType, lpData, cbData);
end;

function RegDeleteKeyF(hKey: HKEY; lpSubKey: PFarChar): Longint; inline;
begin
  Result := {$IFNDEF UNICODE}RegDeleteKeyA{$ELSE}RegDeleteKeyW{$ENDIF}(hKey, lpSubKey);
end;

function SetEnvironmentVariableF(lpName, lpValue: PFarChar): BOOL; inline;
begin
  Result := {$IFNDEF UNICODE}SetEnvironmentVariableA{$ELSE}SetEnvironmentVariableW{$ENDIF}(lpName, lpValue);
end;

function GetEnvironmentStringsF: PFarChar; inline;
begin
  Result := {$IFNDEF UNICODE}GetEnvironmentStringsA{$ELSE}GetEnvironmentStringsW{$ENDIF};
end;

function FreeEnvironmentStringsF(EnvBlock: PFarChar): BOOL; inline;
begin
  Result := {$IFNDEF UNICODE}FreeEnvironmentStringsA{$ELSE}FreeEnvironmentStringsW{$ENDIF}(EnvBlock);
end;

function ExpandEnvironmentStringsF(lpSrc: PFarChar; lpDst: PFarChar; nSize: DWORD): DWORD; inline;
begin
  Result := {$IFNDEF UNICODE}ExpandEnvironmentStringsA{$ELSE}ExpandEnvironmentStringsW{$ENDIF}(lpSrc, lpDst, nSize);
end;

function GetTempPathF(nBufferLength: DWORD; lpBuffer: PFarChar): DWORD;
begin
  Result := {$IFNDEF UNICODE}GetTempPathA{$ELSE}GetTempPathW{$ENDIF}(nBufferLength, lpBuffer);
end;

function GetTempFileNameF(lpPathName, lpPrefixString: PFarChar; uUnique: UINT; lpTempFileName: PFarChar): UINT;
begin
  Result := {$IFNDEF UNICODE}GetTempFileNameA{$ELSE}GetTempFileNameW{$ENDIF}(lpPathName, lpPrefixString, uUnique, lpTempFileName);
end;

function DeleteFileF(lpFileName: PFarChar): BOOL;
begin
  Result := {$IFNDEF UNICODE}DeleteFileA{$ELSE}DeleteFileW{$ENDIF}(lpFileName);
end;

// ************************************************************************************************************************************************************

function TFarDialog.Add(ItemType, Flags: Integer; X1, Y1, X2, Y2: Integer; InitialData: FarString; MaxLen: Integer = 0): Integer;
var
  NewItem: PFarDialogItem;
begin
  SetLength(Items, Length(Items)+1);
  Result := High(Items);
  NewItem := @Items[Result];
  FillChar(NewItem^, SizeOf(NewItem^), 0);

  NewItem.ItemType := ItemType;
  NewItem.Flags := Flags;
  NewItem.X1 := X1;
  NewItem.Y1 := Y1;
  NewItem.X2 := X2;
  NewItem.Y2 := Y2;
  
  if MaxLen < Length(InitialData)+1 then
    MaxLen := Length(InitialData)+1;

  {$IFNDEF UNICODE}
  if (MaxLen >= SizeOf(NewItem.Data.Data)) and ((ItemType=DI_COMBOBOX) or (ItemType=DI_EDIT)) then
  begin
    SetLength(Data, Length(Items));
    Data[Result] := InitialData + #0;
    SetLength(Data[Result], MaxLen);
    NewItem.Data.Ptr.PtrFlags := 0;
    NewItem.Data.Ptr.PtrLength := MaxLen;
    NewItem.Data.Ptr.PtrData := @Data[Result][1];
    NewItem.Flags := NewItem.Flags or DIF_VAREDIT;
  end
  else
    CopyStrToBuf(InitialData, NewItem.Data.Data, SizeOf(NewItem.Data.Data));
  {$ELSE}
  SetLength(Data, Length(Items));
  Data[Result] := InitialData;
  NewItem.PtrData := @Data[Result][1];
  NewItem.MaxLen := 0;
  {$ENDIF}
end;

function TFarDialog.Run(W, H: Integer; HelpTopic: PFarChar = nil): Integer;
begin
  {$IFNDEF UNICODE}
  Result := FARAPI.Dialog(FARAPI.ModuleNumber, -1, -1, W, H, HelpTopic, @Items[0], Length(Items));
  {$ELSE}
  Handle := FARAPI.DialogInit(FARAPI.ModuleNumber, -1, -1, W, H, HelpTopic, @Items[0], Length(Items), 0, 0, nil, 0);
  Result := FARAPI.DialogRun(Handle);
  {$ENDIF}
end;

{$IFDEF UNICODE}
destructor TFarDialog.Destroy;
begin
  FARAPI.DialogFree(Handle);
  inherited;
end;
{$ENDIF}

function TFarDialog.GetData(Index: Integer): FarString;
begin
  {$IFNDEF UNICODE}
  if (Items[Index].Flags and DIF_VAREDIT)<>0 then
    Result := PFarChar(@Data[Index][1])
  else
    Result := PFarChar(@Items[Index].Data.Data[0]);
  {$ELSE}
  Result := PFarChar(FARAPI.SendDlgMessage(Handle, DM_GETCONSTTEXTPTR, Index, 0));
  {$ENDIF}
end;

// ************************************************************************************************************************************************************

function Message(Flags: DWORD; const Lines: array of FarString; ButtonCount: Integer = 0; HelpTopic: PFarChar = nil): Integer;
begin
  Result := FARAPI.Message(FARAPI.ModuleNumber, Flags, HelpTopic, PPCharArray(@Lines[0]), Length(Lines), ButtonCount);
end;

end.
