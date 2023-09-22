#!/bin/bash

if [ -z "${BASH_VERSION:-}" ]; then
  echo "Please run this script with bash"
  exit 1
fi

set -o pipefail
set -E
set -eu

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
readonly SCRIPT_DIR
if [[ ! -f "$SCRIPT_DIR"/build-my-box.conf ]]; then
  echo "Missing ${SCRIPT_DIR}/build-my-box.conf"
  exit 1
fi
. "$SCRIPT_DIR"/build-my-box.conf
if [[ -z ${INSTALL_CMD:-} ]]; then
  echo "Missing INSTALL_CMD in ${SCRIPT_DIR}/build-my-box.conf"
  exit 1
fi
if [[ -z ${CHECK_CMD:-} ]]; then
  echo "Missing CHECK_CMD in ${SCRIPT_DIR}/build-my-box.conf"
  exit 1
fi
if [[ -z ${MAIN_REQUIRED_PKGS:-} ]]; then
  echo "Missing MAIN_REQUIRED_PKGS in ${SCRIPT_DIR:-}/build-my-box.conf"
  exit 1
fi
if [[ -z ${MAIN_REQUIRED_CONF_VARS:-} ]]; then
  echo "Missing MAIN_REQUIRED_CONF_VARS in ${SCRIPT_DIR:-}/build-my-box.conf"
  exit 1
fi

readonly INSTRUCTIONS="#!/bin/bash"

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

add_bash_path() {
  local path="$1"
  append_instructions "append_if_absent \"export PATH=\"${path}:\\\$PATH\"\" \"${BASH_PATH_PATH}\""
}

add_bash_alias() {
  local alias="$1"
  append_instructions "append_if_absent \"alias ${alias}\" \"${BASH_ALIASES_PATH}\""
}

add_bash_function() {
  local func="$1"
  append_instructions "append_if_absent \"${func}\" \"${BASH_FUNCTIONS_PATH}\""
}

add_bash_env_var() {
  local var="$1"
  append_instructions "append_if_absent \"export ${var}\" \"${BASH_ENV_PATH}\""
}

add_to_vimrc() {
  local line="$1"
  append_instructions "append_if_absent \"${line}\" \"${VIM_PATH}\""
}

add_to_tmuxconf() {
  local line="$1"
  append_instructions "append_if_absent \"${line}\" \"${TMUX_PATH}\""
}

add_to_sshconf() {
  local line="$1"
  append_instructions "append_if_absent \"${line}\" \"${SSH_PATH}\""
}

handle_bash() {
  if [[ -n ${NEW_BASH_PATHS:-} || -n ${NEW_BASH_ALIASES:-} || -n ${NEW_BASH_FUNCTIONS:-} || -n ${NEW_BASH_ENV_VARS:-} ]]; then
    dlog "BASH is effected"
    check_required_files "${BASHRC}"
    if [[ -n ${NEW_BASH_PATHS:-} ]]; then
      append_instructions "append_to_file \"# PATHS for ${config_name}\" \"${BASH_PATH_PATH}\""
      for path in "${NEW_BASH_PATHS[@]}"; do
        add_bash_path "${path}"
      done
      append_instructions "append_to_file \" \"  \"${BASH_PATH_PATH}\""
      append_instructions "append_if_absent \"source ${BASH_PATH_PATH}\" \"${BASHRC}\""

    fi
    if [[ -n ${NEW_BASH_ALIASES:-} ]]; then
      append_instructions "append_to_file \"# ALIASES for ${config_name}\" \"${BASH_ALIASES_PATH}\""
      for alias in "${NEW_BASH_ALIASES[@]}"; do
        add_bash_alias "${alias}"
      done
      append_instructions "append_to_file \" \"  \"${BASH_ALIASES_PATH}\""
      append_instructions "append_if_absent \"source ${BASH_ALIASES_PATH}\" \"${BASHRC}\""
    fi
    if [[ -n ${NEW_BASH_FUNCTIONS:-} ]]; then
      append_instructions "append_to_file \"# FUNCTIONS for ${config_name}\" \"${BASH_FUNCTIONS_PATH}\""
      for func in "${NEW_BASH_FUNCTIONS[@]}"; do
        add_bash_function "${func}"
      done
      append_instructions "append_to_file \" \"  \"${BASH_FUNCTIONS_PATH}\""
      append_instructions "append_if_absent \"source ${BASH_FUNCTIONS_PATH}\" \"${BASHRC}\""
    fi
    if [[ -n ${NEW_BASH_ENV_VARS:-} ]]; then
      append_instructions "append_to_file \"# ENV_VARS for ${config_name}\" \"${BASH_ENV_PATH}\""
      for var in "${NEW_BASH_ENV_VARS[@]}"; do
        add_bash_env_var "${var}"
      done
      append_instructions "append_to_file \" \"  \"${BASH_ENV_PATH}\""
      append_instructions "append_if_absent \"source ${BASH_ENV_PATH}\" \"${BASHRC}\""
    fi
  fi
}

handle_vim() {
  if [[ -n ${NEW_VIM_LINES:-} ]]; then
    dlog "VIM is effected"
    check_required_files "${VIMRC}"
    append_instructions "append_to_file \"# From ${config_name}\" \"${VIM_PATH}\""
    for line in "${NEW_VIM_LINES[@]}"; do
      add_to_vimrc "${line}"
    done
    append_instructions "append_to_file \" \"  \"${VIM_PATH}\""
    append_instructions "append_if_absent \"source ${VIM_PATH}\" \"${VIMRC}\""
    
  fi
}

handle_tmux() {
  if [[ -n ${NEW_TMUX_LINES:-} ]]; then
    dlog "TMUX is effected"
    check_required_files "${TMUXCONF}"
    append_instructions "append_to_file\"# From ${config_name}\" \"${TMUX_PATH}\""
    for line in "${NEW_TMUX_LINES[@]}"; do
      add_to_tmuxconf "${line}"
    done
    append_instructions "append_to_file \" \"  \"${TMUX_PATH}\""
    append_instructions "append_if_absent \"source ${TMUX_PATH}\" \"${TMUXCONF}\""
    
  fi
}

handle_ssh() {
  if [[ -n ${NEW_SSH_LINES:-} ]]; then
    dlog "SSH is effected"
    check_required_files "${SSHCONF}"
    append_instructions "append_to_file \"# From ${config_name}\" \"${SSH_PATH}\""
    for line in "${NEW_SSH_LINES[@]}"; do
      add_to_sshconf "${line}"
    done
    append_instructions "append_to_file \" \"  \"${SSH_PATH}\""
    append_instructions "append_if_absent \"source ${SSH_PATH}\" \"${SSHCONF}\""
    
  fi
}

handle_repos() {
  if [[ -n ${NEW_GIT_REPOS:-} ]]; then
    dlog "REPOS is effected"
    append_instructions "prepare_backup_dir ${REPOS_DIR}"
    for repo in "${NEW_GIT_REPOS[@]}"; do
      regex='[/]([^/]*[/][^/]*)[.]git$'
      if [[ $repo =~ $regex ]]; then
        local repo_name="${BASH_REMATCH[1]}"
        append_instructions "git clone \"${repo}\" \"${REPOS_DIR}/${repo_name}\""
      else
        append_instructions "# TODO: set location: git clone \"${repo}\" \"${REPOS_DIR}/${BASH_REMATCH[1]}\""
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

build() {
  local config_name="$1"
  local config=$config_name
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
    echo "Building dependencies"
    indent build_dependencies "${DEPENDENCIES[@]}"
    echo "Done building dependencies"
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

  append_instructions "# ${config_name}"

  indent handle_reqs
  indent handle_bash
  indent handle_vim
  indent handle_tmux
  indent handle_ssh
  indent handle_repos

  append_instructions "# End ${config_name}\n"
}

build_dependencies() {
  for dep in "$@"; do
    echo "Building dependency: ${dep}"
    indent build "${dep}"
    if [[ $? -ne 0 ]]; then
      err "Failed to build dependency: ${dep}"
      exit 1
    fi
    echo "Done building dependency: ${dep}"
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

append_instructions() {
  local line="$1"
  if [[ -f "${INSTRUCTIONS_FILE}" ]]; then
    local prev_line=$(grep -n "^${line}$$" "${INSTRUCTIONS_FILE}")
    if [[ $prev_line =~ "([0-9]+[:])" ]]; then
      prev_line_num="${BASH_REMATCH[1]}"
      line="# $line # Previous line: ${prev_line_num}"
    fi
    echo -e "$line" >>"${INSTRUCTIONS_FILE}"
  fi
}

#######################################
# Run the main program.
# Globals:
#   MAIN_REQUIRED_CMDS
#   INSTALL_CMD
# Arguments:
#   Config to use, a filepath
# Returns:
#   None
# Outputs:
#   Recursively installs the config and its dependencies.
#######################################
main() {
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
  if [[ $# -ne 1 ]]; then
    echo "Provide a config file"
    usage
  fi
  CONFIG_NAME="$(basename $1 .conf)"
  check_required_packages "${MAIN_REQUIRED_PKGS[@]}"

  INSTRUCTIONS_FILE="${SCRIPT_DIR}/$(basename $1 .conf)-instructions.sh"
  readonly INSTRUCTIONS_FILE
  OUT_DIR_PATH="${SCRIPT_DIR}/out/${CONFIG_NAME}"
  echo "#!/bin/bash" >"${INSTRUCTIONS_FILE}"
  append_instructions "OUT_DIR=\"${OUT_DIR_PATH}\""
  append_instructions "prepare_backup_dir \$OUT_DIR"
  append_instructions "rm -rf \$OUT_DIR"
  append_instructions "mkdir -p \$OUT_DIR"
  

  echo "Building: $1"
  indent build "$1"
  echo "Done building: $1"
}

main "$@"
