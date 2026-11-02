@echo off
if not exist bin mkdir bin
odin build src -out:bin/app.exe -debug -vet
if errorlevel 1 exit /b %errorlevel%
odin test src -all-packages -define:ODIN_TEST_THREADS=1 -out:bin/ui_tests.exe
exit /b %errorlevel%
