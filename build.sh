#!/bin/sh
set -e

mkdir -p bin
odin build src -out:bin/app -debug -vet
odin test src -all-packages -define:ODIN_TEST_THREADS=1 -out:bin/ui_tests
