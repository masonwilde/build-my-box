#!/bin/bash

readonly INSTRUCTIONS="$1"
TOP_CONF=""

set -euo pipefail

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

is_line_in_file() {
  local line="$1"
  local file="$2"
  if grep -q "$line" "$file"; then
    return 0
  fi
  return 1
}

append_if_absent() {
  local line="$1"
  local file="$2"
  if is_line_in_file "$line" "$file"; then
    indent append_to_file "${line}" "${file}"
  fi
}

append_to_file() {
  local line="$1"
  local file="$2"
  echo "APPEND TO FILE: '$line' >> '$file'"
  indent prepare_backup_file "${file}"
  echo "${line}" >>"${file}"
}

usage() {
  echo "Usage: $0 [-v] [-x] [-d] <config>"
  echo "  -v: verbose"
  echo "  -x: execute"
  echo "  -d: debug"
  echo "  <config>: config file to use"
  exit 1
}

#######################################
# Prints a message to stdout if VERBOSE is true.
# Globals:
#   VERBOSE
# Arguments:
#   Log message
# Returns:
#   None
# Outputs:
#   Prints log message to stdout.
#######################################
vlog() {
  if [[ "${VERBOSE}" == 'true' ]]; then
    echo "$*"
  fi
}

#######################################
# Prints a message to stdout if DEBUG is true.
# Globals:
#   DEBUG
# Arguments:
#   Log message
# Returns:
#   None
# Outputs:
#   Prints log message to stdout.
#######################################
dlog() {
  if [[ "${DEBUG}" == 'true' ]]; then
    echo -e "$*"
  fi
}

#######################################
# Logs a command to be executed or would be executed.
# Globals:
#   EXECUTE
# Arguments:
#   Command to execute and/or log
# Returns:
#   None
# Outputs:
#   executes or logs command
#######################################
execute_or_log() {
  if [[ "${EXECUTE}" == 'true' ]]; then
    err "You ran with -x, but execution is blocked for security"
    # vlog "Running: $*"
    # "$@"
    # return $?
  else
    append_instructions "$*"
  fi
}

#######################################
# Die if not executing.
# Globals:
#   EXECUTE
# Arguments:
#   None
# Returns:
#   None
# Outputs:
#   Exits with error if not executing.
#######################################
die_if_not_executing() {
  if [[ "${EXECUTE}" == 'false' ]]; then
    err "Cannot continue without -x option."
    exit 1
  fi
}

#######################################
# Prints an error message to stderr.
# Globals:
#   None
# Arguments:
#   Error message
# Returns:
#   None
# Outputs:
#   Prints error message to stderr.
#######################################
err() {
  append_instructions "# DO NOT SUBMIT: $*"
  echo "ERROR [$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*" >&2
}

#######################################
# Used to indent output.
# Globals:
#   None
# Arguments:
#   Command to indent
# Returns:
#   None
# Outputs:
#   All output indented by 2 spaces.
#######################################
indent() {
  #"$@" > >(sed 's/^/  /') 2> >(sed 's/^/  /' >&2)
  local indent=${INDENT:-"    "}
  # Hacky, but captures stderr without lagging behind stdout.
  { "$@" 2> >(sed "s/^/$indent/g" >&2); } | sed "s/^/$indent/g"
  return $?
}

#######################################
# Checks if a command is installed.
# Globals:
#   None
# Arguments:
#   Command to check for
# Returns:
#   0 if command is installed, 1 otherwise
# Outputs:
#   None
#######################################
has_package() {
  if ! $($CHECK_CMD "$1" &>/dev/null); then
    vlog "Missing command: $1"
    return 1
  fi
  dlog "Found command: $1"
}

#######################################
# Verify that required packages are installed.
# Globals:
#   INSTALL_CMD
# Arguments:
#   packages to check for
# Returns:
#   None
# Outputs:
#   Installs missing packages if EXECUTE.
#######################################
check_required_packages() {
  dlog "Checking for required commands: $*"
  local missing=()
  for cmd in "$@"; do
    if ! has_package "$cmd"; then
      missing+=("$cmd")
    fi
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    vlog "Missing required commands: ${missing[*]}"
    execute_or_log "$INSTALL_CMD" "${missing[@]}"
    die_if_not_executing
  fi
}

#######################################
# Verify that config has all vars
# Globals:
#   None
# Arguments:
#   Vars to check for
# Returns:
#   None
# Outputs:
#   None.
#######################################
check_required_vars() {
  dlog "Checking for required vars: $*"
  local missing=()
  for v in "$@"; do
    if [[ -z ${!v} ]]; then
      missing+=("$v")
    fi
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    err "Missing required vars in config: ${missing[*]}"
    exit 1
  fi
}

add_to_section() {
  local line="$1"
  local file="$2"
  local config_name="$3"
  local marker="${END_SECTION_TAG} ${config_name}"
  if is_line_in_file "$marker" "$file"; then
    "sed s/\"^${marker}\"/\"${line}\n${marker}\"// $file"
  fi
}

add_contents_to_config_section_in_file() {
  local content_arr=($1)
  local config_name="$2"
  local target="$3"
  append_instructions "append_if_absent \" ${START_SECTION_TAG} ${config_name}\" \"${target}\""
  append_instructions "append_if_absent \" ${END_SECTION_TAG} ${config_name}\" \"${target}\""
  for content in "${content_arr[@]}"; do
    # Need to sanitize/prepare vars for use in sed (/$"" use)
    append_instructions "add_to_section \"${content}\" \"${config_name}\" \"${target}\""
  done
}

handle_bash() {
  if [[ -n ${NEW_BASH_PATHS:-} || -n ${NEW_BASH_ALIASES:-} || -n ${NEW_BASH_FUNCTIONS:-} || -n ${NEW_BASH_ENV_VARS:-} ]]; then
    dlog "BASH is effected"
    check_required_files "${BASHRC}"
    if [[ -n ${NEW_BASH_PATHS:-} ]]; then
      add_contents_to_config_section_in_file "${NEW_BASH_PATHS[@]}" "$config_name" "$BASH_PATH_PATH"
      # append_instructions "append_if_absent \"${START_SECTION_TAG} ${config_name}\" \"${BASH_PATH_PATH}\""
      # append_instructions "append_if_absent \"${END_SECTION_TAG} ${config_name}\" \"${BASH_PATH_PATH}\""
      # for path in "${NEW_BASH_PATHS[@]}"; do
      #   append_instructions "add_to_section \"${path}\" \"${config_name}\" \"${BASH_PATH_PATH}\""
      # done
      # append_instructions "append_if_absent \"source ${BASH_PATH_PATH}\" \"${BASHRC}\""
    fi
    if [[ -n ${NEW_BASH_ALIASES:-} ]]; then
      add_contents_to_config_section_in_file "${NEW_BASH_ALIASES[@]}" "$config_name" "$BASH_ALIASES_PATH"
      # append_instructions "append_if_absent \"${START_SECTION_TAG} ${config_name}\" \"${BASH_ALIASES_PATH}\""
      # append_instructions "append_if_absent \"${END_SECTION_TAG} ${config_name}\" \"${BASH_ALIASES_PATH}\""
      # for alias in "${NEW_BASH_ALIASES[@]}"; do
      #   append_instructions "add_to_section \"${alias}\" \"${config_name}\" \"${BASH_ALIASES_PATH}\""
      # done
      # append_instructions "append_if_absent \"source ${BASH_ALIASES_PATH}\" \"${BASHRC}\""
    fi
    if [[ -n ${NEW_BASH_FUNCTIONS:-} ]]; then
      # add_contents_to_config_section_in_file ${NEW_BASH_FUNCTIONS} "$config_name" "$BASH_FUNCTIONS_PATH"
      append_instructions "append_if_absent \"${START_SECTION_TAG} ${config_name}\" \"${BASH_FUNCTIONS_PATH}\""
      append_instructions "append_if_absent \"${END_SECTION_TAG} ${config_name}\" \"${BASH_FUNCTIONS_PATH}\""
      for func in "${NEW_BASH_FUNCTIONS[@]}"; do
        append_instructions "add_to_section \"${func}\" \"${config_name}\" \"${BASH_FUNCTIONS_PATH}\""
      done
      append_instructions "append_if_absent \"source ${BASH_FUNCTIONS_PATH}\" \"${BASHRC}\""
    fi
    if [[ -n ${NEW_BASH_ENV_VARS:-} ]]; then
      add_contents_to_config_section_in_file "${NEW_BASH_ENV_VARS[@]}" "$config_name" "$BASH_ENV_PATH"
      # append_instructions "append_if_absent \" ${START_SECTION_TAG} ${config_name}\" \"${BASH_ENV_PATH}\""
      # append_instructions "append_if_absent \"${END_SECTION_TAG} ${config_name}\" \"${BASH_ENV_PATH}\""
      # for var in "${NEW_BASH_ENV_VARS[@]}"; do
      #   append_instructions "add_to_section \"${var}\" \"${config_name}\" \"${BASH_ENV_PATH}\""
      # done
      # append_instructions "append_if_absent \"source ${BASH_ENV_PATH}\" \"${BASHRC}\""
    fi
  fi
}

handle_vim() {
  if [[ -n ${NEW_VIM_LINES:-} ]]; then
    dlog "VIM is effected"
    check_required_files "${VIMRC}"
    add_contents_to_config_section_in_file "${NEW_VIM_LINES[@]}" "$config_name" "$VIM_PATH"
    # append_instructions "append_if_absent \" ${START_SECTION_TAG} ${config_name}\" \"${VIM_PATH}\""
    # append_instructions "append_if_absent \" ${START_SECTION_TAG} ${config_name}\" \"${VIM_PATH}\""
    # for line in "${NEW_VIM_LINES[@]}"; do
    #   append_instructions "add_to_section \"${line}\" \"${config_name}\" \"${VIM_PATH}\""
    # done
    # append_instructions "append_if_absent \"source ${VIM_PATH}\" \"${VIMRC}\""
  fi
}

handle_tmux() {
  if [[ -n ${NEW_TMUX_LINES:-} ]]; then
    dlog "TMUX is effected"
    check_required_files "${TMUXCONF}"
    add_contents_to_config_section_in_file "${NEW_TMUX_LINES[@]}" "$config_name" "$TMUX_PATH"
    # append_instructions "append_if_absent \" ${START_SECTION_TAG} ${config_name}\" \"${TMUX_PATH}\""
    # append_instructions "append_if_absent \" ${END_SECTION_TAG} ${config_name}\" \"${TMUX_PATH}\""
    # for line in "${NEW_TMUX_LINES[@]}"; do
    #   append_instructions "add_to_section \"${func}\" \"${config_name}\" \"${TMUX_PATH}\""
    # done
    # append_instructions "append_if_absent \"source ${TMUX_PATH}\" \"${TMUXCONF}\""
  fi
}

handle_ssh() {
  if [[ -n ${NEW_SSH_LINES:-} ]]; then
    dlog "SSH is effected"
    check_required_files "${SSHCONF}"
    add_contents_to_config_section_in_file "${NEW_SSH_LINES[@]}" "$config_name" "$SSH_CONF"
    # append_instructions "append_if_absent \" ${START_SECTION_TAG} ${config_name}\" \"${SSH_PATH}\""
    # append_instructions "append_if_absent \" ${END_SECTION_TAG} ${config_name}\" \"${SSH_PATH}\""
    # for line in "${NEW_SSH_LINES[@]}"; do
    #   append_instructions "add_to_section \"${line}\" \"${config_name}\" \"${SSH_PATH}\""
    # done
    # append_instructions "append_if_absent \"source ${SSH_PATH}\" \"${SSHCONF}\""
  fi
}

handle_repos() {
  if [[ -n ${NEW_GIT_REPOS:-} ]]; then
    dlog "REPOS is effected"
    # append_instructions "prepare_backup_dir ${REPOS_DIR}"
    for repo in "${NEW_GIT_REPOS[@]}"; do
      regex='[/]([^/]*[/][^/]*)[.]git$'
      if [[ $repo =~ $regex ]]; then
        local repo_name="${BASH_REMATCH[1]}"
        append_instructions "git clone \"${repo}\" \"${REPOS_DIR}${repo_name}\""
      else
        return 1 # append_instructions "# TODO: set location: git clone \"${repo}\" \"${REPOS_DIR}/${BASH_REMATCH[1]}\""
      fi
    done
  fi
}

handle_reqs() {
  if [[ -n ${REQUIRED_PKGS:-} ]]; then
    check_required_packages "${REQUIRED_PKGS[@]}"
  fi

  if [[ -n ${REQUIRED_DIRS:-} ]]; then
    check_required_dirs "${REQUIRED_DIRS[@]}"
  fi

  if [[ -n ${REQUIRED_FILES:-} ]]; then
    check_required_files "${REQUIRED_FILES[@]}"
  fi
}

generate_for_config() {
  local config="$1"
  local config_name="$(basename $config .conf)"
  if [[ ! -f "${config}" ]]; then
    vlog "Config file not found: ${config}. Looking in configs/."
    config="${SCRIPT_DIR}/configs/${config}.conf"
    if [[ ! -f "${config}" ]]; then
      if [[ "$config_name" =~ 'help' ]]; then
        usage
      fi
      echo "Config file not found for: ${config_name}" >"$INSTRUCTIONS_FILE"
      err "Config file not found for: ${config_name}"
      exit 1
    fi
  fi
  readonly config
  . "${config}"
  check_required_vars "${MAIN_REQUIRED_CONF_VARS[@]}"
  dlog "Config: ${config}"

  dlog "DEPENDENCIES: ${DEPENDENCIES[*]:-}"

  if [[ -n ${DEPENDENCIES:-} ]]; then
    echo "Generating dependencies"
    indent generate_dependencies "${DEPENDENCIES[@]}"
    echo "Done generating dependencies"
  fi

  dlog "REQUIRED_PKGS: ${REQUIRED_PKGS[*]:-}"
  dlog "REQUIRED_DIRS: ${REQUIRED_DIRS[*]:-}"
  dlog "REQUIRED_FILES: ${REQUIRED_FILES[*]:-}"
  dlog "NEW_BASH_PATHS: ${NEW_BASH_PATHS[*]:-}"
  dlog "NEW_BASH_ALIASES: ${NEW_BASH_ALIASES[*]:-}"
  dlog "NEW_BASH_FUNCTIONS: ${NEW_BASH_FUNCTIONS[*]:-}"
  dlog "NEW_BASH_ENV_VARS: ${NEW_BASH_ENV_VARS[*]:-}"
  dlog "NEW_VIM_LINES: ${NEW_VIM_LINES[*]:-}"
  dlog "NEW_TMUX_LINES: ${NEW_TMUX_LINES[*]:-}"
  dlog "NEW_SSH_LINES: ${NEW_SSH_LINES[*]:-}"
  dlog "NEW_GIT_REPOS: ${NEW_GIT_REPOS[*]:-}"

  append_instructions "${START_SECTION_TAG} $config_name"

  indent handle_reqs
  indent handle_bash
  indent handle_vim
  indent handle_tmux
  indent handle_ssh
  indent handle_repos

  append_instructions "${END_SECTION_TAG} $config_name"
}

generate_dependencies() {
  for dep in "$@"; do
    # Avoid circular dependency.
    if [[ ${SEEN_DEPS:-} =~ \s$dep\s ]]; then
      vlog "Saw $dep before...skipping to avoid loops."
      continue
    fi
    echo "Generating dependency: ${dep}"
    indent generate_for_config "${dep}"
    if [[ $? -ne 0 ]]; then
      err "Failed to build dependency: ${dep}"
      exit 1
    fi
    echo "Done generating dependency: ${dep}"
  done
}

check_required_files() {
  for f in "$@"; do
    if [[ ! -f "${f}" ]]; then
      err "Missing file: ${f}"
      exit 1
    fi
  done
}

check_required_dirs() {
  for d in "$@"; do
    err "Missing dir: ${d}"
  done
}

get_vars_rec() {
  local config="$1"
  local config_name="$(basename $config .conf)"
  if [[ ! -f "${config}" ]]; then
    vlog "Config file not found: ${config}. Looking in configs/."
    config="${SCRIPT_DIR}/configs/${config}.conf"
    if [[ ! -f "${config}" ]]; then
      err "Config file not found for: ${config_name}"
      exit 1
    fi
  fi
  readonly config
  . "${config}"
  vlog "VARS from $config_name"
  for var in "${REQUIRED_VARS[@]}"; do
    echo "$var"
    SEEN_VARS+=($var)
    echo "${SEEN_VARS[@]}"
  done
  if [[ -n ${DEPENDENCIES:-} ]]; then
    for dep in "${DEPENDENCIES[@]}"; do
      indent get_vars_rec "$dep"
    done
  fi
}

get_all_required_vars() {
  if [[ $# -ne 1 ]]; then
    echo "Provide a config file"
    usage
  fi
  CONFIG_NAME="$(basename $1 .conf)"
  MAIN_CONF="$CONFIG_NAME"
  . "$SCRIPT_DIR"/build-my-box.conf
  verify_main_conf
  SEEN_VARS=()
  get_vars_rec "$1"
  echo "${SEEN_VARS[@]}"
  for var in "${SEEN_VARS[@]}"; do
    echo "$var"
    if [[ -z "${var:-}" ]]; then
      printf "Enter a value for var '$var':"
      read $input
      echo "$input"
    fi
  done
}

append_instructions() {
  local line="$1"
  if [[ -f "${INSTRUCTIONS_FILE}" ]]; then
    local prev_line=$(grep -n "^${line}$$" "${INSTRUCTIONS_FILE}")
    if [[ $prev_line =~ "([0-9]+[:])" ]]; then
      prev_line_num="${BASH_REMATCH[1]}"
      line="# $line # Previous line: ${prev_line_num}"
    fi
    echo "$line" >>"${INSTRUCTIONS_FILE}"
  fi
}

Run_Instructions() {
  if [[ $# -ne 1 ]]; then
    echo "Provide an instruction file"
    usage
  fi
  local INSTRUCTIONS_FILE="$1"
  readonly INSTRUCTIONS_FILE
  if [[ ! -f "${INSTRUCTIONS_FILE}" ]]; then
    err "no instructions file found at ${INSTRUCTIONS}"
    exit 1
  fi
  if [[ $INSTRUCTIONS_FILE =~ (.+)-instructions[.]sh ]]; then
    TOP_CONF="${BASH_REMATCH[1]}"
    MAIN_CONF="$TOP_CONF"
    . "$SCRIPT_DIR"/build-my-box.conf
    verify_main_conf
  else
    err "instructions file name must be of the form <top-level-conf>-instructions.sh"
    exit 1
  fi
  # Ordering is hard here, need file to exist. Might just create it in Instructions
  UNDO_FILE="undo-${TOP_CONF}-$(date +'%Y-%m-%dT%H:%M:%S%z').sh"
  touch "$UNDO_FILE"

  # Oh baby, here we go
  source $INSTRUCTIONS_FILE
}

Generate_Instructions() {
  if [[ $# -ne 1 ]]; then
    echo "Provide a config file"
    usage
  fi
  CONFIG_NAME="$(basename $1 .conf)"
  MAIN_CONF="$CONFIG_NAME"
  . "$SCRIPT_DIR"/build-my-box.conf
  verify_main_conf
  check_required_packages "${MAIN_REQUIRED_PKGS[@]}"

  local INSTRUCTIONS_FILE="${SCRIPT_DIR}/${MAIN_CONF}-instructions.sh"
  readonly INSTRUCTIONS_FILE
  OUT_DIR_PATH="${SCRIPT_DIR}/out/${MAIN_CONF}"
  echo "#!/bin/bash" >"${INSTRUCTIONS_FILE}"
  append_instructions "OUT_DIR=\"${OUT_DIR}\""
  append_instructions "prepare_backup_dir \$OUT_DIR"
  append_instructions "rm -rf \$OUT_DIR"
  append_instructions "mkdir -p \$OUT_DIR"

  local SEEN_DEPS=()

  echo "Building: $1"
  indent generate_for_config "$1"
  echo "Done building: $1"
}

verify_main_conf() {
  # . "$SCRIPT_DIR"/build-my-box.conf
  if [[ -z ${INSTALL_CMD} ]]; then
    echo "Missing INSTALL_CMD in ${SCRIPT_DIR}/build-my-box.conf"
    exit 1
  fi
  if [[ -z ${CHECK_CMD} ]]; then
    echo "Missing CHECK_CMD in ${SCRIPT_DIR}/build-my-box.conf"
    exit 1
  fi
  if [[ -z ${MAIN_REQUIRED_PKGS} ]]; then
    echo "Missing MAIN_REQUIRED_PKGS in ${SCRIPT_DIR:-}/build-my-box.conf"
    exit 1
  fi
  if [[ -z ${MAIN_REQUIRED_CONF_VARS} ]]; then
    echo "Missing MAIN_REQUIRED_CONF_VARS in ${SCRIPT_DIR:-}/build-my-box.conf"
    exit 1
  fi
}

main() {
  local SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
  readonly SCRIPT_DIR
  local VERBOSE='false'
  local EXECUTE='false'
  local DEBUG='false'
  while getopts 'vxdh' flag; do
    case "${flag}" in
    d)
      DEBUG='true'
      VERBOSE='true'
      ;;
    v)
      VERBOSE='true'
      ;;
    x)
      EXECUTE='true'
      err "Execution blocked for security"
      exit 1
      ;;
    h)
      usage
      ;;
    *) ;;
    esac
  done
  readonly VERBOSE
  readonly EXECUTE
  readonly DEBUG
  dlog "VERBOSE: ${VERBOSE}\nEXECUTE: ${EXECUTE}\nDEBUG: ${DEBUG}"
  shift $((OPTIND - 1))
  if [[ ! -f "$SCRIPT_DIR"/build-my-box.conf ]]; then
    echo "Missing ${SCRIPT_DIR}/build-my-box.conf"
    exit 1
  fi

  local sub_arg="$1"
  shift 1
  case "$sub_arg" in
  Generate_Instructions)
    Generate_Instructions $@
    ;;
  Run_Instructions)
    Run_Instructions $@
    ;;
  get_all_required_vars)
    get_all_required_vars $@
    ;;
  *)
    usage
    ;;
  esac
}

main "$@"
