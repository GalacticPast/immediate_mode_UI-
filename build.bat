@echo off
if not exist bin mkdir bin
odin build src -out:bin/app.exe -debug -vet
