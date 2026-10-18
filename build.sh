#!/bin/sh
mkdir -p bin
odin build src -out:bin/app -debug -vet
