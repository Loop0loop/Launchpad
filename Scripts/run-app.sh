#!/bin/sh
set -eu

output="$(Scripts/build-app.sh)"
app_path="$(printf '%s\n' "$output" | tail -n 1)"
open "$app_path"
