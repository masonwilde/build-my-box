#!/bin/bash

readonly INSTRUCTIONS="$1"
TOP_CONF=""

set -euo pipefail

#######################################
# Indents all output recursively
# Globals:
#   None
# Arguments:
#   Command with output to indent
# Returns:
#   None
# Outputs:
#   none.
#######################################
indent() {
  #"$@" > >(sed 's/^/  /') 2> >(sed 's/^/  /' >&2)
  local indent=${INDENT:-"    "}
  # Hacky, but captures stderr without lagging behind stdout.
  { "$@" 2> >(sed "s/^/$indent/g" >&2); } | sed "s/^/$indent/g"
  return $?
}

#######################################
# Creates a .bak version of a file if it exists and plans a command to undo it.
# Globals:
#   None
# Arguments:
#   filepath of the file
# Returns:
#   None
# Outputs:
#   Possibly creates a .bak file and appends a command to undo it.
#######################################
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

#######################################
# Creates a .bak version of a dir if it exists and plans a command to undo it.
# Globals:
#   None
# Arguments:
#   dirpath of the dir
# Returns:
#   None
# Outputs:
#   Possibly creates a .bak dir and appends a command to undo it.
#######################################
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

#######################################
# Checks if a string is in a file.
# Named "line" but technically any string.
# Globals:
#   None
# Arguments:
#   line to check for
#   file to check in
# Returns:
#   0 if line is in file, 1 otherwise
# Outputs:
#   none.
#######################################
is_line_in_file() {
  local line="$1"
  local file="$2"
  if grep -q "$line" "$file"; then
    return 0
  fi
  return 1
}

#######################################
# Appends a string to a file if it is not already there.
#
# Globals:
#   None
# Arguments:
#   string to append
#   file to append to
# Returns:
#   None
# Outputs:
#   Appends string to file if it is not already there.
#######################################
append_if_absent() {
  local string="$1"
  local file="$2"
  if is_line_in_file "$string" "$file"; then
    indent append_to_file "${string}" "${file}"
  fi
}

#######################################
# Appends a string to a file.
# Globals:
#   None
# Arguments:
#   string to append
#   file to append to
# Returns:
#   None
# Outputs:
#   None.
#######################################
append_to_file() {
  local line="$1"
  local file="$2"
  echo "APPEND TO FILE: '$line' >> '$file'"
  indent prepare_backup_file "${file}"
  echo "${line}" >>"${file}"
}

#######################################
# Prints usage output.
# Named "line" but technically any string.
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   Exit 1
# Outputs:
#   Exit 1
#######################################
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

#######################################
# Inserts a string in a config section in a file.
# Globals:
#   None
# Arguments:
#   line to insert
#   file to check in/insert into
#   config_name to insert into
# Returns:
#   0 if insertion occurs, 1 otherwise
# Outputs:
#   None
#######################################
add_to_section() {
  local line="$1"
  local file="$2"
  local config_name="$3"
  local marker="${END_SECTION_TAG} ${config_name}"
  if is_line_in_file "$marker" "$file"; then
    "sed s/\"^${marker}\"/\"${line}\n${marker}\"// $file"
    return 0
  fi
  return 1
}

#######################################
# Helper function to add instructions to add content to a file in a section
# Globals:
#   None
# Arguments:
#   content_arr of strings to add
#   config_name of the section to add to
#   target file to eventually add to
# Returns:
#   None
# Outputs:
#   None
#######################################
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

#######################################
# Handle additions to bash related files.
# Globals:
#   NEW_BASH_PATHS
#   NEW_BASH_ALIASES
#   NEW_BASH_FUNCTIONS
#   NEW_BASH_ENV_VARS
# Arguments:
#   None
# Returns:
#   None
# Outputs:
#   None
#######################################
handle_bash() {
  # TODO: possibly change to pass args
  if [[ -n ${NEW_BASH_PATHS:-} || -n ${NEW_BASH_ALIASES:-} || -n ${NEW_BASH_FUNCTIONS:-} || -n ${NEW_BASH_ENV_VARS:-} ]]; then
    dlog "BASH is effected"
    check_required_files "${BASHRC}"
    if [[ -n ${NEW_BASH_PATHS:-} ]]; then
      add_contents_to_config_section_in_file "${NEW_BASH_PATHS[@]}" "$config_name" "$BASH_PATH_PATH"
    fi
    if [[ -n ${NEW_BASH_ALIASES:-} ]]; then
      add_contents_to_config_section_in_file "${NEW_BASH_ALIASES[@]}" "$config_name" "$BASH_ALIASES_PATH"
    fi
    if [[ -n ${NEW_BASH_FUNCTIONS:-} ]]; then
      # TODO: Check why this multi-line use breaks the below function.
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
    fi
  fi
}

#######################################
# Handle additions to vim related files.
# Globals:
#   NEW_VIM_LINES
# Arguments:
#   None
# Returns:
#   None
# Outputs:
#   None
#######################################
handle_vim() {
  if [[ -n ${NEW_VIM_LINES:-} ]]; then
    dlog "VIM is effected"
    check_required_files "${VIMRC}"
    add_contents_to_config_section_in_file "${NEW_VIM_LINES[@]}" "$config_name" "$VIM_PATH"
  fi
}

#######################################
# Handle additions to tmux related files.
# Globals:
#   NEW_TMUX_LINES
# Arguments:
#   None
# Returns:
#   None
# Outputs:
#   None
#######################################
handle_tmux() {
  if [[ -n ${NEW_TMUX_LINES:-} ]]; then
    dlog "TMUX is effected"
    check_required_files "${TMUXCONF}"
    add_contents_to_config_section_in_file "${NEW_TMUX_LINES[@]}" "$config_name" "$TMUX_PATH"
  fi
}

#######################################
# Handle additions to ssh related files.
# Globals:
#   NEW_SSH_LINES
# Arguments:
#   None
# Returns:
#   None
# Outputs:
#   None
#######################################
handle_ssh() {
  if [[ -n ${NEW_SSH_LINES:-} ]]; then
    dlog "SSH is effected"
    check_required_files "${SSHCONF}"
    add_contents_to_config_section_in_file "${NEW_SSH_LINES[@]}" "$config_name" "$SSH_CONF"
  fi
}

#######################################
# Handle additions to repos.
# Globals:
#   NEW_GIT_REPOS
# Arguments:
#   None
# Returns:
#   None
# Outputs:
#   None
#######################################
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
        err "there was an issue setting the destination dir for $repo"
        return 1 # append_instructions "# TODO: set location: git clone \"${repo}\" \"${REPOS_DIR}/${BASH_REMATCH[1]}\""
      fi
    done
  fi
}

#######################################
# Handle required global elements.
# Globals:
#   REQUIRED_PKGS
#   REQUIRED_DIRS
#   REQUIRED_FILES
# Arguments:
#   None
# Returns:
#   None
# Outputs:
#   None
#######################################
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

#######################################
# Generate instructions for a given config name/path.
# Globals:
#   SCRIPT_DIR
#   INSTRUCTIONS_FILE
#   MAIN_REQUIRED_CONF_VARS
#   Others are optional
# Arguments:
#   config name to use
# Returns:
#   Exits 1 if config cannot be found
# Outputs:
#   Mutates the INSTRUCTIONS_FILE for the given config
#######################################
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

#######################################
# Generate a list of configs.
# Globals:
#   SEEN_DEPS
# Arguments:
#   list of deps
# Returns:
#   Exit 1 if a dependency fails
# Outputs:
#   None
#######################################
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

#######################################
# Checks that required files exist.
# Globals:
#   None
# Arguments:
#   list of files
# Returns:
#   Exit 1 if any file is missing
# Outputs:
#   None
#######################################
check_required_files() {
  for f in "$@"; do
    if [[ ! -f "${f}" ]]; then
      err "Missing file: ${f}"
      exit 1
    fi
  done
}

#######################################
# Checks that required dirs exist.
# Globals:
#   None
# Arguments:
#   list of dirs
# Returns:
#   Exit 1 if any dir is missing
# Outputs:
#   None
#######################################
check_required_dirs() {
  for d in "$@"; do
    err "Missing dir: ${d}"
    exit 1
  done
}

#######################################
# Creates a list of all required vars in SEEN_VARS
# Globals:
#   SEEN_VARS
# Arguments:
#   config to start from
# Returns:
#   Exit 1 if any config isn't found
# Outputs:
#   None
#######################################
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

#######################################
# Gets user values for any missing required vars.
# Globals:
#   None
# Arguments:
#   config to check
# Returns:
#   Exit 1 if any config is missing
# Outputs:
#   Creates a sourced config file of user values.
#######################################
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

#######################################
# Appends an instruction to the instruction file.
# Globals:
#   None
# Arguments:
#   line to append
# Returns:
#   None
# Outputs:
#   Appends to instruction file
#######################################
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

#######################################
# Executes the instructions in a relevant instruction file
# Globals:
#   None
# Arguments:
#   instruction_file to execute
# Returns:
#   Exit 1 if instruction file is not found
# Outputs:
#   Varies depending on the instruction file
#######################################
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

#######################################
# Generates an instruction file for a given config
# Globals:
#   None
# Arguments:
#   config to use
# Returns:
#   None
# Outputs:
#   A new instruction file is generated
#######################################
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
  # Clear out any old instruction file. Perhaps should be more explicit.
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

#######################################
# Verifies that the script config has all fields
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   Exit 1 if any field is missing
# Outputs:
#   None
#######################################
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

#######################################
# Main method. Handles flags and executes the matching sub-command
# Globals:
#   None
# Arguments:
#   flags
#   subcommand
#   subcommand args
# Returns:
#   None
# Outputs:
#   None
#######################################
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
