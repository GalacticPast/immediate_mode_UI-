#!/bin/sh
set -eu

# @test: Odin tests share a package directory with the source they test. Assemble a
# @test: temporary source tree so the checked-in tests can live separately in test/.
test_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)
project_dir=$(dirname "$test_dir")
test_workspace=$(mktemp -d "${TMPDIR:-/tmp}/imui-tests.XXXXXXXX")
trap 'rm -rf "$test_workspace"' EXIT

mkdir -p "$test_workspace/src"
cp -R "$project_dir/src/." "$test_workspace/src/"
cp "$test_dir/ui/"*.odin "$test_workspace/src/ui/"
cp "$test_dir/platform/"*.odin "$test_workspace/src/platform/"
cp "$test_dir/renderer/"*.odin "$test_workspace/src/renderer/"
cp "$test_dir/text/"*.odin "$test_workspace/src/text/"

kb_collection=$(sh "$project_dir/scripts/kb-collection.sh" "$project_dir/bin/vendor")
odin test "$test_workspace/src" "-collection:shaping=$kb_collection" "-define:IMUI_TEST_FONT=$project_dir/assets/font/Archivo-Regular.ttf" -all-packages -out:"$test_workspace/tests" -vet "$@"
