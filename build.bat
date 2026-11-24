@echo off
if not exist bin mkdir bin
for /f "delims=" %%i in ('odin root') do set "odin_path=%%i"
odin build src "-collection:shaping=%odin_path%/vendor" -out:bin/app.exe -debug -vet
if errorlevel 1 exit /b %errorlevel%
