#!/bin/sh
printf '\033c\033]0;%s\a' clankerUI
base_path="$(dirname "$(realpath "$0")")"
"$base_path/clankerUI.arm64" "$@"
