#!/bin/sh
set -e

mkdir -p bin
kb_collection=$(sh scripts/kb-collection.sh "$PWD/bin/vendor")
odin build src "-collection:shaping=$kb_collection" -out:bin/app -debug -vet
