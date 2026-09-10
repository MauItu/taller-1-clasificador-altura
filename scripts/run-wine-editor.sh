#!/usr/bin/env bash
# Lanza el editor OIP (build Windows) bajo wine, en un scope propio de systemd
# para no heredar el oom_score_adj=200 del terminal.
export WINEPREFIX=$HOME/dev/oip/wineprefix
export WINEDLLOVERRIDES="mscoree,mshtml="
export WINEDEBUG=fixme-all
exec systemd-run --user --scope --quiet --collect -- \
  wine "$HOME/dev/oip/release/OIP_v4.7-rc1.exe" \
  --path 'Z:\home\mauarch\dev\oip\project\default_project' \
  --editor "$@"
