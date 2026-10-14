#!/usr/bin/env bash

ask() {
  local prompt="$1" default="${2:-}" reply
  if [[ -n "${default}" ]]; then
    read -r -p "${prompt} [${default}]: " reply || true
    echo "${reply:-$default}"
  else
    read -r -p "${prompt}: " reply || true
    echo "${reply}"
  fi
}

ask_yn() {
  local prompt="$1" default="${2:-y}" reply
  read -r -p "${prompt} [${default}]: " reply || true
  reply="$(echo "${reply:-$default}" | tr '[:upper:]' '[:lower:]')"
  [[ "${reply}" == "y" || "${reply}" == "yes" ]]
}

ask_secret() {
  local reply
  read -r -s -p "$1: " reply || true
  echo >&2
  echo "${reply}"
}
