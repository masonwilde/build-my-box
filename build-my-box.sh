#!/bin/bash

readonly INSTRUCTIONS="$1"
TOP_CONF=""

set -eu

prepare_backup() {
  local file="$1"
  if [[ "$file" == "undo-${TOP_CONF}.sh" ]]; then
    return
  fi
  if [[ ! -d $(dirname "${file}") ]]; then
    prepare_backup_dir $(dirname "${file}")
  fi
  if [[ ! -f "${file}" ]]; then
    echo "touch ${file}"
    touch "$file"
    append_to_file "rm ${file}" "undo-${TOP_CONF}.sh"
  else
    echo "cp ${file} ${file}.${TOP_CONF}.bak"
    cp "${file}" "${file}.${TOP_CONF}.bak"
    append_to_file "cp ${file}.${TOP_CONF}.bak ${file}" "undo-${TOP_CONF}.sh"
  fi
}

prepare_backup_dir() {
  local dir="$1"
  if [[ ! -d "${dir}" ]]; then
    echo "mkdir -p $dir"
    mkdir -p "$dir"
    append_to_file "rm -rf ${dir}" "undo-${TOP_CONF}.sh"
  else
    echo "cp -r ${dir} ${dir}.${TOP_CONF}.bak"
    cp -r "${dir}" "${dir}.${TOP_CONF}.bak"
    append_to_file "rm -rf ${dir}" "undo-${TOP_CONF}.sh"
    append_to_file "cp -r ${dir}.${TOP_CONF}.bak/ ${dir}" "undo-${TOP_CONF}.sh"
  fi
}

append_if_absent() {
  local line="$1"
  local file="$2"
  local cmd="grep -q \"^${line}\$\" ${file}"
  local prev_line="$($cmd)"
  echo "PREVIOUS_GREP: $cmd"
  echo "PREVIOUS_FILE: '$file'"
  echo "PREVIOUS_LINE:$prev_line"
  if [[ $prev_line =~ ([0-9]+[:]) ]]; then
    prev_line_num="${BASH_REMATCH[1]}"
    line="# $line # Previous line: ${prev_line_num}"
  fi
  append_to_file "${line}" "${file}"
}

append_to_file() {
  local line="$1"
  local file="$2"
  prepare_backup "${file}"
  echo "echo ${line} >> ${file}"
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
  touch "undo-${TOP_CONF}.sh"
  source $INSTRUCTIONS
}

main "$@"
