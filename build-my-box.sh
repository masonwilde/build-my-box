#!/bin/bash

readonly INSTRUCTIONS="$1"
TOP_CONF=""

set -eu

indent() {
  #"$@" > >(sed 's/^/  /') 2> >(sed 's/^/  /' >&2)
  local indent=${INDENT:-"    "}
  # Hacky, but captures stderr without lagging behind stdout.
  { "$@" 2> >(sed "s/^/$indent/g" >&2); } | sed "s/^/$indent/g"
  return $?
}

prepare_backup_file() {
  local file="$1"
  if [[ $file =~ undo-${TOP_CONF}[.]sh ]]; then
    return
  fi
  if [[ ! -d $(dirname "${file}") ]]; then
    indent prepare_backup_dir $(dirname "${file}")
  fi
  if [[ ! -f "${file}" ]]; then
    echo "MAKE NEW FILE: ${file}"
    touch "$file"
    indent append_to_file "rm ${file}" "$UNDO_FILE"
  else
    if [[ ! -f "${file}.${TOP_CONF}.bak" ]]; then
      echo "BACKUP FILE: ${file}"
      cp "${file}" "${file}.${TOP_CONF}.bak"
      indent append_if_absent "cp ${file}.${TOP_CONF}.bak ${file}" "$UNDO_FILE"
    fi
  fi
}

prepare_backup_dir() {
  local dir="$1"
  if [[ ! -d "${dir}" ]]; then
    echo "MAKE NEW DIR: ${dir}"
    mkdir -p "$dir"
    indent append_to_file "rm -rf ${dir}" "$UNDO_FILE"
  else
    if [[ ! -f "${dir}.${TOP_CONF}.bak" ]]; then
      echo "BACKUP DIR: ${dir}"
      cp -r "${dir}" "${dir}.${TOP_CONF}.bak"
      indent append_to_file "rm -rf ${dir}" "$UNDO_FILE"
      indent append_to_file "cp -r ${dir}.${TOP_CONF}.bak/ ${dir}" "$UNDO_FILE"
    fi
  fi
}

append_if_absent() {
  local line="$1"
  local file="$2"
  # echo "APPEND IF ABSENT: '$line' >> '$file'"
  local cmd=(-n "^${line}\$" "${file}")
  local prev_line=$(grep "${cmd[@]}")
  if [[ $prev_line =~ ([0-9]+[:]) ]]; then
    prev_line_num="${BASH_REMATCH[1]}"
    # line="# $line # Previous line: ${prev_line_num}"
    # echo "FOUND: $prev_line_num"
    return
  fi
  indent append_to_file "${line}" "${file}"
}

append_to_file() {
  local line="$1"
  local file="$2"
  echo "APPEND TO FILE: '$line' >> '$file'"
  indent prepare_backup_file "${file}"
  echo "${line}" >> "${file}"
}



main() {
  if [[ ! -f "${INSTRUCTIONS}" ]]; then
    echo "ERROR: No instructions file found at ${INSTRUCTIONS}"
    exit 1
  fi
  if [[ $INSTRUCTIONS =~ (.+)-instructions[.]sh ]]; then
    TOP_CONF="${BASH_REMATCH[1]}"
  else
    echo "ERROR: Instructions file name must be of the form <top-level-conf>-instructions.sh"
    exit 1
  fi
  UNDO_FILE="undo-${TOP_CONF}-$(date +'%Y-%m-%dT%H:%M:%S%z').sh"
  touch "$UNDO_FILE"
  source $INSTRUCTIONS
}

main "$@"
