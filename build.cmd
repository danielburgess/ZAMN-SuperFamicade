@echo off
echo Removing current build...
del .\out\ZAMN_SuperFamicade.sfc
echo Copying original (Base) ROM...
copy ".\base\Zombies Ate My Neighbors (USA).sfc" .\out\ZAMN_SuperFamicade.sfc
echo Building...
..\Tools\xkas-plus\xkas.exe -o .\out\ZAMN_SuperFamicade.sfc ZAMN_SuperFamicade.asm
echo Done.