@echo off

call build-config.bat

if exist out rd /S /Q out
mkdir out
if not exist obj mkdir obj

del *.res 2> nul
rc EnvMan.rc
if not exist EnvMan.res exit

for %%f in (1 2 3) do for %%p in (32 64) do call :build %%f %%p
goto :eof

:build

echo ############################## Far%1 x%2 ##############################

del *.dll 2> nul
del *.o 2> nul
del *.obj 2> nul
del *.ppu 2> nul
if exist *.dll echo Can't delete DLLs & exit /b 1

call set FARSDK=%%FAR%1SDK%%
call set PC=%%PC%2%%
call set PC_DEFINE=%%PC%2_DEFINE%%
call set PC_SEARCH=%%PC%2_SEARCH%%
call set PC_OUTDIR=%%PC%2_OUTDIR%%

set UNICODE=
if /I %1 GEQ 2 set UNICODE=%PC_DEFINE%UNICODE

set CONFIG=Far%1.%2
set OUTDIR=obj\%CONFIG%

if not exist %OUTDIR% mkdir %OUTDIR%
call %PC% %PC_DEFINE%FAR%1 %UNICODE% %PC_SEARCH%%FARSDK% %PC_OUTDIR%%OUTDIR% EnvMan.dpr
if errorlevel 1 exit 1
if not exist %OUTDIR%\EnvMan.dll exit 1
7z a out\EnvMan.%CONFIG%.zip %OUTDIR%\EnvMan.dll *.lng *.hlf

goto :eof
