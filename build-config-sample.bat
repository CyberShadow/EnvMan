set FAR1SDK=C:\Projects\Extern\FAR\FAR1\Headers.pas
set FAR2SDK=C:\Soft\Far2\PluginSDK\Headers.pas
set FAR3SDK=C:\Projects\Extern\FAR\FAR\unicode_far

set PC32=dcc32 -H
set PC32_DEFINE=-D
set PC32_SEARCH=-U
set PC32_OUTDIR=-E

set LAZARUS=C:\Soft\lazarus
set PC64=ppcrossx64 -Sd -Fu%LAZARUS%\lcl\units\x86_64-win64 -Fu%LAZARUS%\lcl -Fu%LAZARUS%\components\lazutils -Fi%LAZARUS%\lcl\include
set PC64_DEFINE=-d
set PC64_SEARCH=-Fu
set PC64_OUTDIR=-FE
