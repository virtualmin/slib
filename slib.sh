#!/bin/sh
# shellcheck disable=SC3043 disable=SC2086 disable=SC2059 disable=SC2039 disable=SC2034 disable=SC2317
#------------------------------------------------------------------------------
# Utility function library for installation scripts
# slib v1.5.0 (https://github.com/virtualmin/slib)
# Copyright 2017-2026 The Virtualmin Developers
# slog logging library Copyright Fred Palmer and Joe Cooper
# Licensed under the BSD 3 clause license
#------------------------------------------------------------------------------

restore_cursor () {
  tput cnorm
}

cleanup () {
  exit_code=$1
  stty echo 1>/dev/null 2>&1
  echo
  # Make super duper sure we reap all the spinners
  # This is ridiculous, and I still don't know why spinners stick around.
  if [ -n "$allpids" ]; then
    for pid in $allpids; do
      kill "$pid" 1>/dev/null 2>&1
    done
    tput sgr0
  fi
  restore_cursor
  # Clean any env dirs
  env | grep '_INSTALL_TEMPDIR=' | while IFS='=' read -r var temp_dir; do
    [ -z "$temp_dir" ] && continue
    prefix="${var%%_INSTALL_TEMPDIR}"
    if [ -d "$temp_dir" ] && echo "$temp_dir" | grep -iq "${prefix}-"; then
      rm -rf "$temp_dir"
    fi
  done

  exit $exit_code
}

# Check for interactive shell
INTERACTIVE_MODE="on"
[ -z "${NONINTERACTIVE-}" ] && NONINTERACTIVE=0      # Set only if unset
if [ ! -t 0 ] && [ -z "${PS1-}" ]; then
    INTERACTIVE_MODE="off"
    [ -z "${NONINTERACTIVE-}" ] && NONINTERACTIVE=1  # Only set if unset
fi

# This tries to catch any exit, whether normal or forced (e.g. Ctrl-C)
if [ "$INTERACTIVE_MODE" != "off" ]; then
  trap 'cleanup 2' INT
  trap 'cleanup 3' QUIT
  trap 'cleanup 15' TERM
  # Preserve failures, including swap-only errors, through terminal cleanup.
  trap 'cleanup "$?"' 0
fi

# scolors - Color constants
# canonical source http://github.com/swelljoe/scolors

# Check if terminal is supported and set TERM to a supported one if not
is_term_supported () {
  term=$1
  [ -n "$term" ] || term=dumb            # avoid empty TERM
  # Tput probe
  if command -pv tput >/dev/null 2>&1; then
    tput -T "$term" cols >/dev/null 2>&1 && return 0 || return 1
  fi
  # Infocmp probe
  if command -pv infocmp >/dev/null 2>&1; then
    infocmp "$term" >/dev/null 2>&1 && return 0 || return 1
  fi
  return 1
}
FALLBACK_TERMS='xterm-256color xterm-color xterm vt220 ansi dumb'
if ! is_term_supported "$TERM"; then
  OLDTERM=$TERM
  for alt in $FALLBACK_TERMS; do
    if is_term_supported "$alt"; then
      TERM=$alt
      export TERM
      echo "[INFO] Terminal type '$OLDTERM' not supported; switched to '$TERM'"
      break
    fi
  done
fi

# do we have tput?
if command -pv 'tput' > /dev/null; then
  # do we have a terminal?
  if [ -t 1 ]; then
    # does the terminal have colors?
    ncolors=$(tput colors)
    if [ "$ncolors" -ge 8 ]; then
      BLACK="$(tput setaf 0)"
      RED=$(tput setaf 1)
      GREEN=$(tput setaf 2)
      YELLOW=$(tput setaf 3)
      ORANGE=$(tput setaf 3)
      BLUE=$(tput setaf 4)
      MAGENTA=$(tput setaf 5)
      CYAN=$(tput setaf 6)
      WHITE=$(tput setaf 7)
      REDBG=$(tput setab 1)
      GREENBG=$(tput setab 2)
      YELLOWBG=$(tput setab 3)
      ORANGEBG=$(tput setab 3)
      BLUEBG=$(tput setab 4)
      MAGENTABG=$(tput setab 5)
      CYANBG=$(tput setab 6)
      WHITEBG=$(tput setab 7)

      # Do we have support for bright colors?
      if [ "$ncolors" -ge 16 ]; then
        WHITE=$(tput setaf 15)
        WHITEBG=$(tput setab 15)
      fi

      # Do we have support for 256 colors to make it more readable?
      if [ "$ncolors" -ge 256 ]; then
        RED=$(tput setaf 124)
        GREEN=$(tput setaf 34)
        YELLOW=$(tput setaf 186)
        BLUE=$(tput setaf 25)
        ORANGE=$(tput setaf 202)
        MAGENTA=$(tput setaf 90)
        CYAN=$(tput setaf 45)
        WHITE=$(tput setaf 255)
        REDBG=$(tput setab 160)
        YELLOWBG=$(tput setab 186)
        ORANGEBG=$(tput setab 166)
        BLUEBG=$(tput setab 25)
        MAGENTABG=$(tput setab 90)
        CYANBG=$(tput setab 45)
      fi

      BOLD=$(tput bold)
      UNDERLINE=$(tput smul) # Many terminals don't support this
      NORMAL=$(tput sgr0)
    fi
  fi
else
  echo "tput not found, colorized output disabled."
  BLACK=''
  RED=''
  GREEN=''
  YELLOW=''
  ORANGE=''
  BLUE=''
  MAGENTA=''
  CYAN=''
  WHITE=''
  REDBG=''
  GREENBG=''
  YELLOWBG=''
  ORANGEBG=''
  BLUEBG=''
  MAGENTABG=''
  CYANBG=''

  BOLD=''
  UNDERLINE=''
  NORMAL=''
fi

# slog - logging library
# canonical source http://github.com/swelljoe/slog

# LOG_PATH - Define $LOG_PATH in your script to log to a file, otherwise
# just writes to STDOUT.

# LOG_LEVEL_STDOUT - Define to determine above which level goes to STDOUT.
# By default, all log levels will be written to STDOUT.
LOG_LEVEL_STDOUT="INFO"

# LOG_LEVEL_LOG - Define to determine which level goes to LOG_PATH.
# By default all log levels will be written to LOG_PATH.
LOG_LEVEL_LOG="INFO"

# Useful global variables that users may wish to reference
SCRIPT_ARGS="$*"
SCRIPT_NAME="$0"
SCRIPT_NAME="${SCRIPT_NAME#\./}"
SCRIPT_NAME="${SCRIPT_NAME##/*/}"

#--------------------------------------------------------------------------------------------------
# Begin Logging Section
if [ "$INTERACTIVE_MODE" = "off" ]
then
    # Then we don't care about log colors
    LOG_DEFAULT_COLOR=""
    LOG_ERROR_COLOR=""
    LOG_INFO_COLOR=""
    LOG_SUCCESS_COLOR=""
    LOG_WARN_COLOR=""
    LOG_DEBUG_COLOR=""
else
    LOG_DEFAULT_COLOR=$(tput sgr0)
    LOG_ERROR_COLOR=$(tput setaf 1)
    LOG_INFO_COLOR=$(tput setaf 6)
    LOG_SUCCESS_COLOR=$(tput setaf 2)
    LOG_WARN_COLOR=$(tput setaf 3)
    LOG_DEBUG_COLOR=$(tput setaf 4)
fi

# This function scrubs the output of any control characters used in colorized output
# It's designed to be piped through with text that needs scrubbing.  The scrubbed
# text will come out the other side!
prepare_log_for_nonterminal () {
    # Essentially this strips all the control characters for log colors
    sed -E 's/\x1B\[[0-9;]*[mK]//g; s/\x1B\([A-Za-z]//g' | tr -d '[:cntrl:]'
}

log_date () {
  local log_date_level="$1"
  echo "[$(date +"%Y-%m-%d %H:%M:%S %Z")] [$log_date_level] "
}

log () {
  local log_text="$1"
  local log_level="$2"
  local log_color="$3"

  # Levels for comparing against LOG_LEVEL_STDOUT and LOG_LEVEL_LOG
  local LOG_LEVEL_DEBUG=0
  local LOG_LEVEL_INFO=1
  local LOG_LEVEL_SUCCESS=2
  local LOG_LEVEL_WARNING=3
  local LOG_LEVEL_ERROR=4

  # Default level to "info"
  [ -z "${log_level}" ] && log_level="INFO";
  [ -z "${log_color}" ] && log_color="${LOG_INFO_COLOR}";

  # Validate LOG_LEVEL_STDOUT and LOG_LEVEL_LOG since they'll be eval-ed.
  case $LOG_LEVEL_STDOUT in
    DEBUG|INFO|SUCCESS|WARNING|ERROR)
      ;;
    *)
      LOG_LEVEL_STDOUT=INFO
      ;;
  esac
  case $LOG_LEVEL_LOG in
    DEBUG|INFO|SUCCESS|WARNING|ERROR)
      ;;
    *)
      LOG_LEVEL_LOG=INFO
      ;;
  esac

  # Check LOG_LEVEL_STDOUT to see if this level of entry goes to STDOUT.
  # XXX This is the horror that happens when your language doesn't have a hash data struct.
  eval log_level_int="\$LOG_LEVEL_${log_level}";
  eval log_level_stdout="\$LOG_LEVEL_${LOG_LEVEL_STDOUT}"
  # shellcheck disable=SC2154
  if [ "$log_level_stdout" -le "$log_level_int" ]; then
    # STDOUT
    printf "%s[%s]%s %s\\n" "$log_color" "$log_level" "$LOG_DEFAULT_COLOR" "$log_text";
  fi
  # This is all very tricky; figures out a numeric value to compare.
  eval log_level_log="\$LOG_LEVEL_${LOG_LEVEL_LOG}"
  # Check LOG_LEVEL_LOG to see if this level of entry goes to LOG_PATH
  # shellcheck disable=SC2154
  if [ "$log_level_log" -le "$log_level_int" ]; then
    # LOG_PATH minus fancypants colors
    if [ -n "$LOG_PATH" ]; then
      today=$(date +"%Y-%m-%d %H:%M:%S %Z")
      printf "[%s] [%s] %s\\n" "$today" "$log_level" "$log_text" >> "$LOG_PATH"
    fi
  fi

  return 0;
}

log_info()      { log "$@"; }
log_success()   { log "$1" "SUCCESS" "${LOG_SUCCESS_COLOR}"; }
log_error()     { log "$1" "ERROR" "${LOG_ERROR_COLOR}"; }
log_warning()   { log "$1" "WARNING" "${LOG_WARN_COLOR}"; }
log_debug()     { log "$1" "DEBUG" "${LOG_DEBUG_COLOR}"; }

# End Logging Section
#--------------------------------------------------------------------------------------------------

# spinner - Log to provide spinners when long-running tasks happen
# Canonical source http://github.com/swelljoe/spinner

# Config variables, set these after sourcing to change behavior.
SPINNER_COLORNUM=2 # What color? Irrelevent if COLORCYCLE=1.
SPINNER_COLORCYCLE=1 # Does the color cycle?
SPINNER_DONEFILE="stopspinning" # Path/name of file to exit on.
SPINNER_SYMBOLS="WIDE_ASCII_PROG" # Name of the variable containing the symbols.
SPINNER_CLEAR=1 # Blank the line when done.

spinner () {
  # Add this trap to make sure the spinner is terminated and the cursor
  # is restored, when the script is either finished or killed.
  trap 'restore_cursor; exit' INT QUIT TERM EXIT
  # Safest option are one of these. Doesn't need Unicode, at all.
  local WIDE_ASCII_PROG="[>-] [->] [--] [--]"
  local WIDE_UNI_GREYSCALE2="▒▒▒ █▒▒ ██▒ ███ ▒██ ▒▒█ ▒▒▒"

  local SPINNER_NORMAL
  SPINNER_NORMAL=$(tput sgr0)

  eval SYMBOLS=\$${SPINNER_SYMBOLS}

  # Get the parent PID
  SPINNER_PPID=$(ps -p "$$" -o ppid=)
  while :; do
    tput civis
    for c in ${SYMBOLS}; do
      if [ $SPINNER_COLORCYCLE -eq 1 ]; then
        if [ $SPINNER_COLORNUM -eq 7 ]; then
          SPINNER_COLORNUM=1
        else
          SPINNER_COLORNUM=$((SPINNER_COLORNUM+1))
        fi
      fi
      local SPINNER_COLOR
      SPINNER_COLOR=$(tput setaf ${SPINNER_COLORNUM})
      printf "\033[77G"  # Move to column 77
      env printf "${SPINNER_COLOR}${c}${SPINNER_NORMAL}"
      if [ -f "${SPINNER_DONEFILE}" ]; then
        if [ ${SPINNER_CLEAR} -eq 1 ]; then
          tput el
        fi
	      rm -f ${SPINNER_DONEFILE}
	      break 2
      fi
      # This is questionable. sleep with fractional seconds is not
      # always available, but seems to not break things, when not.
      env sleep .2
      # Check to be sure parent is still going; handles sighup/kill
      if [ -n "$SPINNER_PPID" ]; then
        # This is ridiculous. ps prepends a space in the ppid call, which breaks
        # this ps with a "garbage option" error.
        # XXX Potential gotcha if ps produces weird output.
        # shellcheck disable=SC2086
        SPINNER_PARENTUP=$(ps --no-headers $SPINNER_PPID)
        if [ -z "$SPINNER_PARENTUP" ]; then
          break 2
        fi
      fi
    done
  done
  restore_cursor
  return 0
}

# run_ok - function to run a command or function, start a spinner and print a confirmation
# indicator when done.
# Canonical source - http://github.com/swelljoe/run_ok
RUN_LOG="run.log"

# Check for unicode support in the shell
# This is a weird function, but seems to work. Checks to see if a unicode char can be
# written to a file and can be read back.
shell_has_unicode () {
  # Write a unicode character to a file...read it back and see if it's handled right.
  env printf "\\u2714"> unitest.txt

  read -r unitest < unitest.txt
  rm -f unitest.txt
  if [ ${#unitest} -le 3 ]; then
    return 0
  else
    return 1
  fi
}

# Some terminals can round-trip Unicode but still render badge glyphs awkwardly.
# Allow forcing either mode, and otherwise prefer ASCII in known-problematic
# terminals.
status_badges_use_unicode () {
  case "${SLIB_STATUS_BADGES:-auto}" in
    1|on|true|yes|unicode)
      return 0
      ;;
    0|off|false|no|ascii)
      return 1
      ;;
  esac

  if ! shell_has_unicode; then
    return 1
  fi

  case "${TERM_PROGRAM:-}:${TERM:-}:${GHOSTTY_BIN_DIR:-}:${GHOSTTY_RESOURCES_DIR:-}" in
    *ghostty*)
      return 1
      ;;
  esac

  return 0
}

# Setup spinner with our prefs.
SPINNER_COLORCYCLE=0
SPINNER_COLORNUM=6
if shell_has_unicode; then
  SPINNER_SYMBOLS="WIDE_UNI_GREYSCALE2"
else
  SPINNER_SYMBOLS="WIDE_ASCII_PROG"
fi
SPINNER_CLEAR=0 # Don't blank the line, so our check/x can simply overwrite it.

# Perform an action, log it, and print a colorful checkmark or X if failed
# Returns 0 if successful, $? if failed.
run_ok () {
  # Shell is really clumsy with passing strings around.
  # This passes the unexpanded $1 and $2, so subsequent users get the
  # whole thing.
  local cmd="${1}"
  local msg="${2}"
  local log_pref
  log_pref="$(log_date "INFO")"

  printf "%s" "$2"
  printf "\033[K"      # Clear to end of line
  printf "\033[77G"    # Move cursor to column 77

  CHECK='\u2714'
  BALLOT_X='\u2718'
  if [ "$INTERACTIVE_MODE" != "off" ];then
    stty -echo 1>/dev/null 2>&1
    spinner &
    spinpid=$!
    allpids="$allpids $spinpid"
    echo "$log_pref Spin pid is: $spinpid" >> ${RUN_LOG}
  fi
  eval "${cmd}" 1>> ${RUN_LOG} 2>&1
  local res=$?
  touch ${SPINNER_DONEFILE}
  env sleep .4 # It's possible to have a race for stdout and spinner clobbering the next bit
  # Just in case the spinner survived somehow, kill it.
  if [ "$INTERACTIVE_MODE" != "off" ];then
    stty echo 1>/dev/null 2>&1
    pidcheck=$(ps --no-headers ${spinpid})
    if [ -n "$pidcheck" ]; then
      echo "$log_pref Made it here...why?" >> ${RUN_LOG}
      kill $spinpid 2>/dev/null
      rm -rf ${SPINNER_DONEFILE} 2>/dev/null 2>&1
      restore_cursor
    fi
  fi
  # Log what we were supposed to be running
  msg_safe=$(echo "$msg" | prepare_log_for_nonterminal)
  printf "$log_pref ${msg_safe}: " >> ${RUN_LOG}
  if status_badges_use_unicode; then
    if [ $res -eq 0 ]; then
      printf "$log_pref Success.\\n" >> ${RUN_LOG}
      printf "\033[77G\033[K"  # Position and clear
      env printf "${GREENBG}${WHITE} ${CHECK} ${NORMAL}\\n"
      return 0
    else
      printf "$log_pref Failed with error: ${res}\\n" >> ${RUN_LOG}
      printf "\033[77G\033[K"  # Position and clear
      env printf "${REDBG}${WHITE} ${BALLOT_X} ${NORMAL}\\n"
      if [ "$RUN_ERRORS_FATAL" ]; then
        echo
        log_fatal "Something went wrong. Exiting."
        log_fatal "The last few log entries were:"
        tail -17 "${RUN_LOG}" | head -15
        exit 1
      fi
      return ${res}
    fi
  else
    if [ $res -eq 0 ]; then
      printf "$log_pref Success.\\n" >> ${RUN_LOG}
      printf "\033[77G\033[K"
      env printf "${GREENBG} OK ${NORMAL}\\n"
      return 0
    else
      printf "$log_pref Failed with error: ${res}\\n" >> ${RUN_LOG}
      printf "\033[77G\033[K"
      env printf "${REDBG} ER ${NORMAL}\\n"
      if [ "$RUN_ERRORS_FATAL" ]; then
        log_fatal "Something went wrong with the previous command. Exiting."
        exit 1
      fi
      return ${res}
    fi
  fi
}

# Ask a yes or no question
# if $skipyesno is 1, always Y
# if NONINTERACTIVE environment variable is 1, always N, and print error message to use --force
yesno () {
  # XXX skipyesno is a global set in the calling script
  # shellcheck disable=SC2154
  if [ "$skipyesno" = "1" ]; then
    return 0
  fi
  if [ "$NONINTERACTIVE" = "1" ]; then
    echo "Non-interactive shell detected. Cannot continue, as the script may need to ask questions."
    echo "If you're running this from a script and want to install with default options, use '--force'."
    return 1
  fi
  stty echo 1>/dev/null 2>&1
  while read -r line; do
    stty -echo 1>/dev/null 2>&1
    case $line in
      y|Y|Yes|YES|yes|yES|yEs|YeS|yeS) return 0
      ;;
      n|N|No|NO|no|nO) return 1
      ;;
      *)
      stty echo 1>/dev/null 2>&1
      printf "\\n${YELLOW}Please enter ${CYAN}[y]${YELLOW} or ${CYAN}[n]${YELLOW}:${NORMAL} "
      ;;
    esac
  done
  stty -echo 1>/dev/null 2>&1
}

# mkdir if it doesn't exist
testmkdir () {
  if [ ! -d "$1" ]; then
    mkdir -p "$1"
  fi
}

# Copy a file if the destination doesn't exist
testcp () {
  if [ ! -e "$2" ]; then
    cp "$1" "$2"
  fi
}

# Set a Webmin directive or add it if it doesn't exist
setconfig () {
  sc_config="$2"
  sc_value="$1"
  sc_directive=$(echo "$sc_value" | cut -d'=' -f1)
  if grep -q "$sc_directive $2"; then
    sed -i -e "s#$sc_directive.*#$sc_value#" "$sc_config"
  else
    echo "$1" >> "$2"
  fi
}

# Detect the primary IP address
# works across most Linux and FreeBSD (maybe)
detect_ip () {
  # Interface detection
  defaultdev=$(ip ro ls 2>>"${RUN_LOG}" | grep default | head -1 | sed -e 's/.*\sdev\s//g' | awk '{print $1}')
  # IPv6 only?
  if [ -z "$defaultdev" ]; then
    defaultdev=$(ip -6 ro ls 2>>"${RUN_LOG}" | grep default | head -1 | sed -e 's/.*\sdev\s//g' | awk '{print $1}')
  fi
  # No default route at all: isolated or internal-only system?
  if [ -z "$defaultdev" ]; then
    log_warning "No default route detected. Cannot determine primary interface."
    log_warning "Extracting the name of the first active network interface that is not the loopback!"
    defaultdev=$(ip -o link show 2>>"${RUN_LOG}" | awk -F': ' '/state UP/ && !/LOOPBACK/ {print $2}' | head -1)
  fi
  # IPv4
  primaryaddr=$(ip -f inet addr show dev "$defaultdev" 2>>"${RUN_LOG}" | grep 'inet ' | awk '{print $2}' | head -1 | cut -d"/" -f1 | cut -f1)
  # IPv6 only?
  if [ -z "$primaryaddr" ]; then
      primaryaddr=$(ip -f inet6 addr show dev "$defaultdev" 2>>"${RUN_LOG}" | grep 'inet6 ' | awk '{print $2}' | head -1 | cut -d"/" -f1 | cut -f1)
  fi
  if [ "$primaryaddr" ]; then
    log_debug "Primary address detected as $primaryaddr"
    address=$primaryaddr
    return 0
  else
    log_warning "Unable to determine IP address of primary interface."
    echo "Please enter the name of your primary network interface: "
    stty echo 1>/dev/null 2>&1
    read -r primaryinterface
    stty -echo 1>/dev/null 2>&1
    # IPv4
    primaryaddr=$(/sbin/ip -f inet -o -d addr show dev "$primaryinterface" 2>>"${RUN_LOG}" | head -1 | awk '{print $4}' | head -1 | cut -d"/" -f1)
    # IPv6 only?
    if [ -z "$primaryaddr" ]; then
      primaryaddr=$(/sbin/ip -f inet6 -o -d addr show dev "$primaryinterface" 2>>"${RUN_LOG}" | head -1 | awk '{print $4}' | head -1 | cut -d"/" -f1)
    fi
    if [ "$primaryaddr" = "" ]; then
      # FreeBSD (IPv4)
      primaryaddr=$(/sbin/ifconfig "$primaryinterface" 2>>"${RUN_LOG}" | grep 'inet' | awk '{ print $2 }')
      # FreeBSD IPv6 only?
      if [ -z "$primaryaddr" ]; then
        primaryaddr=$(/sbin/ifconfig "$primaryinterface" 2>>"${RUN_LOG}" | grep 'inet6' | awk '{ print $2 }')
      fi
    fi
    if [ "$primaryaddr" ]; then
      log_debug "Primary address detected as $primaryaddr"
      address=$primaryaddr
    else
      fatal "Unable to determine IP address of selected interface.  Cannot continue."
    fi
    return 0
  fi
}

# Set the hostname in cloud-init
set_hostname_cloud () {
  # If cloud-init is installed, preserve the hostname
  if [ -f "/etc/cloud/cloud.cfg" ]; then
    if grep "^preserve_hostname: false" /etc/cloud/cloud.cfg >/dev/null; then
      log_debug "Setting preserve_hostname to true in /etc/cloud/cloud.cfg"
      sed -i "s/^preserve_hostname: false/preserve_hostname: true/" /etc/cloud/cloud.cfg
    fi
  fi
}

# Set the hostname
set_hostname () {
  local i=0
  local forcehostname
  if [ -n "$1" ]; then
    forcehostname=$1
  fi
  while [ $i -le 3 ]; do
    if [ -z "$forcehostname" ]; then
      local name
      name=$(hostname -f)
      log_error "Your system hostname $name is not fully qualified."
      printf "Please enter a fully qualified hostname (e.g.: host.example.com): "
      stty echo 1>/dev/null 2>&1
      read -r line
      stty -echo 1>/dev/null 2>&1
    else
      log_debug "Setting hostname to $forcehostname"
      line=$forcehostname
    fi
    if ! is_fully_qualified "$line"; then
      i=$((i + 1))
      log_warning "Hostname $line is not fully qualified."
      if [ "$i" = "4" ]; then
        fatal "Unable to set fully qualified hostname."
      fi
    else
      hostname "$line"
      echo "$line" > /etc/hostname
      hostnamectl set-hostname "$line" 1>/dev/null 2>&1
      set_hostname_cloud
      detect_ip
      shortname=$(echo "$line" | cut -d"." -f1)
      if grep "^$address" /etc/hosts >/dev/null; then
        log_debug "Entry for IP $address exists in /etc/hosts."
        log_debug "Updating with new hostname."
        sed -i "s/^$address.*/$address $line $shortname/" /etc/hosts
      else
        log_debug "Adding new entry for hostname $line on $address to /etc/hosts."
        printf "%s\\t%s\\t%s\\n" "$address" "$line" "$shortname" >> /etc/hosts
      fi
      i=4
    fi
  done
}

is_fully_qualified () {
  case $1 in
    localhost.localdomain)
      log_warning "Hostname cannot be localhost.localdomain."
      return 1
      ;;
    *.localdomain)
      log_warning "Hostname cannot be *.localdomain."
      return 1
      ;;
    *.internal)
      log_warning "Hostname cannot be *.internal."
      return 1
      ;;
    *.*)
      log_debug "Hostname is fully qualified as $1"
      return 0
      ;;
  esac
  return 1
}

# sets up distro version globals os_type, os_version, os_major_version, os_real
# returns 1 if something fails.
get_distro () {
  os=$(uname -o)
  # Make sure we're Linux
  if echo "$os" | grep -iq linux; then
    if [ -f /etc/cloudlinux-release ]; then # Oracle
      local os_string
      os_string=$(cat /etc/cloudlinux-release)
      os_real='CloudLinux'
      os_pretty=$os_string
      os_type='cloudlinux'
      os_version=$(echo "$os_string" | grep -o '[0-9\.]*')
      os_major_version=$(echo "$os_version" | cut -d '.' -f1)
    elif [ -f /etc/oracle-release ]; then # Oracle
      local os_string
      os_string=$(cat /etc/oracle-release)
      os_real='Oracle Linux'
      os_pretty=$os_string
      os_type='ol'
      os_version=$(echo "$os_string" | grep -o '[0-9\.]*')
      os_major_version=$(echo "$os_version" | cut -d '.' -f1)
    elif [ -f /etc/redhat-release ]; then # RHEL/CentOS/Alma/Rocky
      local os_string
      os_string=$(cat /etc/redhat-release)
      isrhel=$(echo "$os_string" | grep 'Red Hat')
      iscentosstream=$(echo "$os_string" | grep 'CentOS Stream')
      if [ -n "$isrhel" ]; then
        os_real='RHEL'
      elif [ -n "$iscentosstream" ]; then
        os_real='CentOS Stream'
      else
        os_real=$(echo "$os_string" | cut -d' ' -f1) # Doesn't work for Scientific
      fi
      os_pretty=$os_string
      os_type=$(echo "$os_real" | tr '[:upper:]' '[:lower:]' | tr ' ' '_')
      os_version=$(echo "$os_string" | grep -o '[0-9\.]*')
      os_major_version=$(echo "$os_version" | cut -d '.' -f1)
    elif [ -f /etc/os-release ]; then # Debian/Ubuntu
      # Source it, so we can check VERSION_ID
      # shellcheck disable=SC1091
      . /etc/os-release
      # Not technically correct, but os-release does not have 7.xxx for centos
      # shellcheck disable=SC2153
      os_real=$NAME
      os_pretty=$PRETTY_NAME
      os_type=$ID
      os_version=$VERSION_ID
      os_major_version=$(echo "${os_version}" | cut -d'.' -f1)
    else
      printf "${RED}No /etc/*-release file found, this OS is probably not supported.${NORMAL}\\n"
      return 1
    fi
  else
    printf "${RED}Failed to detect a supported operating system.${NORMAL}\\n"
    return 1
  fi
  if [ -n "$1" ]; then
    case $1 in
      real)
        echo "$os_real"
        ;;
      type)
        echo "$os_type"
        ;;
      version)
        echo "$os_version"
        ;;
      major)
        echo "$os_major_version"
        ;;
      *)
        printf "${RED}Unknown argument${NORMAL}\\n"
        return 1
        ;;
    esac
  fi
  return 0
}

# Versioned contract for installers that expose explicit swap controls.
SLIB_SWAP_API=2

# swap_file_active [path] [proc_swaps]
# Match the kernel pathname exactly, never a substring of another swap area.
swap_file_active () {
  awk -v path="${1:-/swap.vm}" 'NR > 1 && $1 == path { found = 1 }
    END { exit found ? 0 : 1 }' "${2:-/proc/swaps}" 2>/dev/null
}

# kb_size_h kb - Sizes use binary units, matching Linux memory accounting.
kb_size_h () {
  if [ $(($1 % 1048576)) -eq 0 ]; then
    echo "$(($1 / 1048576)) GiB"
  else
    echo "$(($1 / 1024)) MiB"
  fi
}

# swap_size_wanted all_mem mem_total usable_disk_kb
# Automatic sizing is an installer policy, not a workload or hibernation sizing
# rule: top up toward 8 GiB, capped by twice RAM and by available disk space.
swap_size_wanted () {
  if [ -n "$swapsize" ]; then
    if [ "$3" -ge "$swapsize" ]; then echo "$swapsize"; else echo 0; fi
    return 0
  fi
  wanted_size=$(( (8388608 - $1 + 1048575) / 1048576 * 1048576 ))
  if [ "$1" -ge 8388608 ]; then echo 0; return 0; fi
  wanted_ram_cap=$(( ($2 * 2 + 1048575) / 1048576 * 1048576 ))
  [ "$wanted_size" -le "$wanted_ram_cap" ] || wanted_size=$wanted_ram_cap
  if [ "$3" -ge 41943040 ]; then
    wanted_cap=6291456
  elif [ "$3" -ge 20971520 ]; then
    wanted_cap=3145728
  elif [ "$3" -ge 10485760 ]; then
    wanted_cap=2097152
  elif [ "$3" -ge 5242880 ]; then
    wanted_cap=1048576
  else
    wanted_cap=0
  fi
  [ "$wanted_size" -le "$wanted_cap" ] || wanted_size=$wanted_cap
  echo "$wanted_size"
}

# swap_fstab_check path
# Leave administrator options intact; conflicting or duplicate records require
# manual reconciliation before any live swap is changed.
swap_fstab_check () {
  awk -v path="$1" '
    $1 == path {
      count++
      if ($3 != "swap" || NF < 4) bad = 1
      n = split($4, opts, ",")
      for (i = 1; i <= n; i++)
        if (opts[i] == "noauto" || opts[i] ~ /^x-systemd\./) bad = 1
    }
    END { exit (bad || count > 1) ? 1 : 0 }
  ' /etc/fstab
}

# swap_systemd_ordering - Btrfs serializes swap activation filesystem-wide.
# Start our optional swap after the ordinary swap units finish, retaining the
# normal shutdown ordering while avoiding an ordering cycle with swap.target.
swap_systemd_ordering () {
  cat <<'SWAP_UNIT'
# Managed by Virtualmin: serialize Btrfs swap activation.
[Unit]
DefaultDependencies=no
After=swap.target systemd-remount-fs.service
Conflicts=umount.target
Before=umount.target
SWAP_UNIT
}

# swap_resume_partition major:minor
# Only a verified swap block device is independent of our regular swapfile.
# In particular, a Btrfs file's st_dev is not its backing block-device number.
swap_resume_partition () {
  [ -b "/dev/block/$1" ] || return 1
  swap_resume_type=$(blkid -p -s TYPE -o value "/dev/block/$1" 2>/dev/null) || return 1
  [ "$swap_resume_type" = swap ]
}

# swap_resume_conflict
# Nonzero offsets indicate swapfile resume. Zero-offset partition resume is
# safe only when its target is verified; unresolved or malformed data is refused.
swap_resume_conflict () {
  # Check every command-line occurrence without integer overflow or octal parsing.
  if ! awk '
    { for (i = 1; i <= NF; i++) if ($i ~ /^resume_offset=/) {
        sub(/^resume_offset=/, "", $i)
        if ($i !~ /^0+$/) conflict = 1
      }
    }
    END { exit conflict ? 1 : 0 }
  ' /proc/cmdline; then return 0; fi
  if [ -e /sys/power/resume_offset ]; then
    swap_resume_offset=$(cat /sys/power/resume_offset) || return 0
    case "$swap_resume_offset" in ''|*[!0]*) return 0 ;; esac
  fi

  # Kernels without the resume interface have no active resume device to check.
  [ -e /sys/power/resume ] || return 1
  swap_resume_dev=$(cat /sys/power/resume) || return 0
  [ "$swap_resume_dev" != '0:0' ] || return 1
  if ! printf '%s\n' "$swap_resume_dev" | grep -Eq '^[0-9]+:[0-9]+$'; then return 0; fi
  if swap_resume_partition "$swap_resume_dev"; then return 1; fi
  return 0
}

# swap_plan [installation_disk_gb]
# Read-only preflight shared by the confirmation message and the executor.
# Only the historical /swap.vm and the dedicated Btrfs swapfile are managed.
swap_plan () {
  swap_action=none
  swap_error=
  swap_size=0
  swap_old_size=0
  swap_active=0
  swap_path=/swap.vm
  swap_reserve=${1:-1}
  if [ -n "$setup_only" ] || [ -n "$noswap" ]; then return 0; fi
  # Later probes such as blkid silently return nothing without root, which
  # would otherwise be reported as an unsafe or unrecognized file.
  if [ "$(id -u)" -ne 0 ]; then swap_error="Swap management requires root."; return 1; fi

  # Validate the library API too, since callers other than the installer use it.
  if [ -n "$swapsize" ]; then
    case "$swapsize" in
      *[!0-9]*|'') swap_error="Invalid swap size in KiB."; return 1 ;;
    esac
    swapsize=${swapsize#"${swapsize%%[!0]*}"}
    swapsize=${swapsize:-0}
    if [ "${#swapsize}" -gt 10 ] || [ "$swapsize" -gt 1073740800 ] ||
       [ $((swapsize % 1024)) -ne 0 ]; then
      swap_error="Swap size must be whole MiB, below 1 TiB."; return 1
    fi
  fi
  swap_fs=$(findmnt -n -o FSTYPE -T /) || {
    swap_error="Cannot detect the mounted root filesystem."; return 1;
  }
  # Include persistent references when choosing the managed pathname, so a
  # missing file from an interrupted/earlier run can be repaired or removed.
  swap_legacy_ref=$(awk '$1 == "/swap.vm" {print 1; exit}' /etc/fstab)
  swap_btrfs_ref=$(awk '$1 == "/swap.virtualmin/swapfile" {print 1; exit}' /etc/fstab)
  if [ -e /swap.virtualmin ] || [ -L /swap.virtualmin ]; then
    if [ -L /swap.virtualmin ] || [ ! -d /swap.virtualmin ] ||
       [ "$(stat -c '%u:%a' /swap.virtualmin)" != '0:700' ]; then
      swap_error="Unsafe /swap.virtualmin directory; refusing to change swap."; return 1
    fi
  fi
  if [ -e /swap.vm ] || [ -L /swap.vm ] || [ "$swap_legacy_ref" = 1 ]; then
    if [ -e /swap.virtualmin/swapfile ] || [ -L /swap.virtualmin/swapfile ] ||
       [ "$swap_btrfs_ref" = 1 ]; then
      swap_error="Both swap locations exist; reconcile them manually."; return 1
    fi
  elif [ "$swap_fs" = btrfs ] || [ -d /swap.virtualmin ] || [ "$swap_btrfs_ref" = 1 ]; then
    # A separate subvolume prevents our Btrfs swapfile from blocking root snapshots.
    swap_path=/swap.virtualmin/swapfile
  fi

  # Automatic installation leaves an existing Virtualmin swapfile alone.
  if [ -z "$swapsize" ] && { [ -e "$swap_path" ] || [ -L "$swap_path" ]; }; then
    return 0
  fi
  if [ -e "$swap_path" ] || [ -L "$swap_path" ]; then
    if [ -L "$swap_path" ] || [ ! -f "$swap_path" ] ||
       [ "$(stat -c '%u:%h' "$swap_path")" != '0:1' ] ||
       [ "$(blkid -p -s TYPE -o value "$swap_path" 2>/dev/null)" != swap ]; then
      swap_error="Refusing to replace an unsafe or unrecognized file at $swap_path."; return 1
    fi
    swap_old_bytes=$(stat -c %s "$swap_path") || return 1
    swap_old_size=$((swap_old_bytes / 1024))
  fi
  if swap_file_active "$swap_path"; then swap_active=1; fi

  # Persist only an unambiguous, ordinary fstab entry for our pathname.
  if [ -L /etc/fstab ] || [ ! -f /etc/fstab ] || ! swap_fstab_check "$swap_path"; then
    swap_error="Conflicting or unsafe /etc/fstab configuration for $swap_path."; return 1
  fi
  # A second boot reference could survive removal or override our fstab
  # settings. Do not take ownership of aliases or native systemd units.
  if ! awk -v path="$swap_path" '$1 ~ /^\// && $1 != path {print $1}' /etc/fstab |
       while IFS= read -r swap_source; do
         swap_source=$(printf '%b' "$swap_source")
         if [ "$(readlink -f "$swap_source")" = "$swap_path" ]; then exit 1; fi
       done; then
    swap_error="Another fstab entry refers to $swap_path through an alias."; return 1
  fi
  swap_unit=${swap_path#/}
  swap_unit=$(printf '%s' "$swap_unit" | tr / -).swap
  swap_order_dir="/etc/systemd/system/$swap_unit.d"
  swap_order_file="$swap_order_dir/50-virtualmin-swap.conf"
  for swap_unit_dir in /etc/systemd/system /run/systemd/system /usr/lib/systemd/system /lib/systemd/system; do
    if [ -e "$swap_unit_dir/$swap_unit" ] || [ -L "$swap_unit_dir/$swap_unit" ] ||
       [ -L "$swap_unit_dir/$swap_unit.d" ]; then
      swap_error="Custom systemd configuration for $swap_path requires manual review."; return 1
    fi
    # Only our unchanged ordering drop-in can be reconciled automatically.
    for swap_dropin in "$swap_unit_dir/$swap_unit.d/"* "$swap_unit_dir/$swap_unit.d/".[!.]* "$swap_unit_dir/$swap_unit.d/"..?*; do
      [ -e "$swap_dropin" ] || [ -L "$swap_dropin" ] || continue
      if [ "$swap_dropin" != "$swap_order_file" ] || [ -L "$swap_dropin" ] ||
         [ ! -f "$swap_dropin" ] || [ "$(cat "$swap_dropin")" != "$(swap_systemd_ordering)" ]; then
        swap_error="Custom systemd configuration for $swap_path requires manual review."; return 1
      fi
    done
  done
  swap_options=$(awk -v path="$swap_path" '$1 == path {print $4}' /etc/fstab)
  swap_options=${swap_options:-defaults}
  swap_old_priority=$(awk -v path="$swap_path" '$1 == path {print $5}' /proc/swaps)
  swap_fstab_ref=$(awk -v path="$swap_path" '$1 == path {print 1; exit}' /etc/fstab)
  if [ "$swapsize" = 0 ]; then
    # Without a file, boot entry, or drop-in there is nothing to remove.
    if [ ! -e "$swap_path" ] && [ ! -L "$swap_path" ] && [ "$swap_active" = 0 ] &&
       [ "$swap_fstab_ref" != 1 ] && [ ! -e "$swap_order_file" ]; then
      return 0
    fi
    swap_action=remove
  elif [ -n "$swapsize" ] && [ "$swap_old_size" -eq "$swapsize" ]; then
    swap_action=reuse
    swap_size=$swapsize
  else
    # Resize requires room for the replacement while the old file is retained.
    # Always keep 1 GiB of headroom in addition to the installation estimate.
    swap_avail=$(LC_ALL=C df -Pk / | awk 'NR == 2 {print $4}')
    swap_mem=$(awk '$1 == "MemTotal:" {print $2}' /proc/meminfo)
    swap_total=$(awk '$1 == "SwapTotal:" {print $2}' /proc/meminfo)
    case "$swap_avail:$swap_mem:$swap_total" in
      *[!0-9:]*|:*|*::*|*:) swap_error="Cannot read memory or disk capacity."; return 1 ;;
    esac
    swap_size=$(swap_size_wanted "$((swap_mem + swap_total))" "$swap_mem" \
      "$((swap_avail - (swap_reserve + 1) * 1048576))")
    if [ "$swap_size" -eq 0 ]; then
      if [ -n "$swapsize" ]; then
        swap_error="Insufficient free disk space for the replacement swap and reserved headroom."; return 1
      fi
      return 0
    fi
    swap_action=create
    [ "$swap_old_size" -eq 0 ] || swap_action=resize
  fi

  # Replacing a file changes its resume offset. Refuse to guess whether an
  # existing swapfile hibernation setup belongs to this particular file.
  if [ "$swap_old_size" -gt 0 ] &&
     { [ "$swap_action" = resize ] || [ "$swap_action" = remove ]; } &&
     swap_resume_conflict; then
    swap_error="Hibernation into a swapfile is configured or cannot be ruled out; resize or removal requires manual review."; return 1
  fi

  # Btrfs creation must use its native helper and a dedicated subvolume.
  # Legacy Btrfs /swap.vm can be reused or removed but is not recreated in root.
  if [ "$swap_action" = create ] || [ "$swap_action" = resize ]; then
    case "$swap_fs" in
      ext2|ext3|ext4|xfs) ;;
      btrfs)
        if [ "$swap_path" = /swap.vm ] ||
           ! btrfs filesystem mkswapfile --help >/dev/null 2>&1; then
          swap_error="Btrfs swap creation requires btrfs-progs 6.1+ and /swap.virtualmin/swapfile."; return 1
        fi
        if [ -d /swap.virtualmin ] &&
           ! btrfs subvolume show /swap.virtualmin >/dev/null 2>&1; then
          swap_error="/swap.virtualmin must be a dedicated Btrfs subvolume."; return 1
        fi
        ;;
      *) swap_error="Swapfile creation is unsupported on $swap_fs."; return 1 ;;
    esac
  fi
  return 0
}

# swap_size_planned [installation_disk_gb] - Compatibility with older callers.
swap_size_planned () (
  swap_plan "${1:-1}" || return 1
  case "$swap_action" in create|resize) echo "$swap_size" ;; *) echo 0 ;; esac
)

# swap_plan_message - Describe the user-visible change without storage details.
swap_plan_message () {
  case "$swap_action" in
    create) echo "The swap space will be created with a size of $(kb_size_h "$swap_size")." ;;
    resize) echo "The swap space will be resized from $(kb_size_h "$swap_old_size") to $(kb_size_h "$swap_size")." ;;
    remove) echo "The swap space previously configured by this installer will be removed." ;;
    reuse) echo "The existing swap space of $(kb_size_h "$swap_size") will be reused." ;;
  esac
}

# swap_can_deactivate path
# Keep a conservative RAM margin before swapoff, which can otherwise trigger
# memory pressure. The kernel remains the final authority if usage changes.
swap_can_deactivate () {
  swap_used=$(awk -v path="$1" '$1 == path {print $4}' /proc/swaps)
  swap_available=$(awk '$1 == "MemAvailable:" {print $2}' /proc/meminfo)
  if [ -z "$swap_used" ] || [ -z "$swap_available" ] ||
     [ "$swap_available" -lt "$((swap_used + 262144))" ]; then
    log_error "Insufficient available RAM to safely deactivate $1 (256 MiB reserve required)."
    return 1
  fi
}

# swap_write_fstab - Prepare an atomic update, preserving unrelated records and
# existing options; nofail keeps unavailable swap from becoming a boot requirement.
swap_write_fstab () {
  swap_fstab_tmp=$(mktemp /etc/.fstab.virtualmin.XXXXXX) || return 1
  swap_fstab_before=$(cksum /etc/fstab) || return 1
  cp --preserve=all /etc/fstab "$swap_fstab_tmp" || return 1
  awk -v path="$swap_path" -v action="$swap_action" '
    $1 == path {
      found = 1
      if (action == "remove") next
      if ($4 !~ /(^|,)nofail(,|$)/) $4 = $4 ",nofail"
    }
    { print }
    END {
      if (!found && action != "remove")
        print path " none swap defaults,nofail 0 0"
    }
  ' /etc/fstab > "$swap_fstab_tmp"
}

# swap_write_ordering - Install boot ordering before publishing the fstab entry.
# Retain existing identical content and track new files for failure cleanup.
swap_write_ordering () {
  if [ "$swap_fs" != btrfs ] || [ ! -d /run/systemd/system ] ||
     [ "$swap_action" = remove ] || [ -f "$swap_order_file" ]; then return 0; fi
  if [ ! -d "$swap_order_dir" ]; then mkdir -m 0755 "$swap_order_dir" || return 1; fi
  swap_order_tmp=$(mktemp "$swap_order_dir/.virtualmin.XXXXXX") || return 1
  swap_systemd_ordering > "$swap_order_tmp" && chmod 0644 "$swap_order_tmp" || return 1
  swap_order_created=1
  mv -f "$swap_order_tmp" "$swap_order_file"
}

# swap_commit_fstab - Do not overwrite an administrator edit made during allocation.
swap_commit_fstab () {
  if [ "$(cksum /etc/fstab)" != "$swap_fstab_before" ]; then
    log_error "/etc/fstab changed during swap setup; refusing to overwrite it."
    return 1
  fi
  mv -f "$swap_fstab_tmp" /etc/fstab
}

# swap_cleanup - Roll back failed live changes before removing temporary files.
# If recovery fails, retain the old file and report its pathname for the operator.
swap_cleanup () {
  swap_result=$?
  trap - 0 HUP INT TERM
  if [ "$swap_result" -ne 0 ]; then
    log_error "Swap operation failed; see $RUN_LOG for details."
  fi
  if [ "$swap_committed" != 1 ]; then
    # A failed persistence repair must also undo activation of an existing file.
    # Keep the file intact even if memory pressure prevents deactivation.
    if [ "$swap_reuse_activated" = 1 ] && ! swapoff "$swap_path" >>"$RUN_LOG" 2>&1; then
      log_error "Could not undo activation of $swap_path; the original file remains active."
      swap_result=1
    fi
    if [ "$swap_new_installed" = 1 ] && swap_file_active "$swap_path"; then
      if ! swapoff "$swap_path" >>"$RUN_LOG" 2>&1; then
        log_error "Rollback could not deactivate $swap_path; retained $swap_backup."
        exit 1
      fi
    fi
    if [ -n "$swap_backup" ] && [ -e "$swap_backup" ]; then
      # A failed rename can leave both names pointing to the original inode.
      if [ "$(stat -c '%d:%i' "$swap_backup")" = "$(stat -c '%d:%i' "$swap_path" 2>/dev/null)" ]; then
        rm -f "$swap_backup"
      elif ! mv -f "$swap_backup" "$swap_path"; then
        log_error "Restore $swap_path manually from $swap_backup."
        exit 1
      fi
    elif [ "$swap_new_installed" = 1 ]; then
      rm -f "$swap_path"
    fi
    if [ "$swap_old_off" = 1 ]; then
      if [ "${swap_old_priority:--1}" -ge 0 ]; then
        swap_options="$swap_options,pri=$swap_old_priority"
      fi
      swapon --options="$swap_options" "$swap_path" >>"$RUN_LOG" 2>&1 ||
        log_error "Could not reactivate the original $swap_path; its contents were retained."
    fi
  fi
  if [ -n "$swap_new" ] && [ -e "$swap_new" ]; then
    # Signals can arrive after trial activation but before trial deactivation.
    if swap_file_active "$swap_new" && ! swapoff "$swap_new" >>"$RUN_LOG" 2>&1; then
      log_error "Temporary swap remains active at $swap_new; retained for recovery."
      swap_result=1
    else
      rm -f "$swap_new"
    fi
  fi
  [ -z "$swap_fstab_tmp" ] || rm -f "$swap_fstab_tmp"
  [ -z "$swap_order_tmp" ] || rm -f "$swap_order_tmp"
  if [ "$swap_committed" != 1 ] && [ "$swap_order_created" = 1 ]; then
    rm -f "$swap_order_file"
    rmdir "$swap_order_dir" 2>/dev/null || :
  fi
  # Delete the retained original only after both live swap and fstab succeeded.
  if [ "$swap_committed" = 1 ] && [ -n "$swap_backup" ]; then
    rm -f "$swap_backup" || swap_result=1
  fi
  exit "$swap_result"
}

# swap_setup [installation_disk_gb]
# Serialize cooperating runs, stage the entire replacement, and retain the old
# inode until activation and boot persistence both succeed. A subshell confines
# the lock, umask, transaction variables, and traps to this operation.
swap_setup () (
  if [ -n "$setup_only" ] || [ -n "$noswap" ]; then return 0; fi
  if [ "$(id -u)" -ne 0 ]; then log_error "Swap management requires root."; return 1; fi
  RUN_LOG=${RUN_LOG:-/dev/null}
  umask 077
  exec 9>/run/virtualmin-swap.lock || return 1
  if ! flock -n 9; then log_error "Another swap operation is running."; return 1; fi
  swap_plan "${1:-1}" || { log_error "$swap_error"; return 1; }
  [ "$swap_action" != none ] || return 0
  swap_new='' swap_backup='' swap_fstab_tmp='' swap_order_tmp=''
  swap_new_installed=0 swap_old_off=0 swap_committed=0 swap_order_created=0 swap_reuse_activated=0
  trap 'swap_cleanup' 0
  trap 'exit 1' HUP INT TERM
  # The preview already announced the change; record execution only in the log.
  printf 'Swap plan: action=%s path=%s filesystem=%s size=%sKiB previous=%sKiB options=%s\n' \
    "$swap_action" "$swap_path" "$swap_fs" "$swap_size" "$swap_old_size" "$swap_options" >>"$RUN_LOG"
  swap_write_fstab || { log_error "Cannot prepare /etc/fstab update."; return 1; }
  swap_write_ordering || { log_error "Cannot prepare Btrfs swap boot ordering."; return 1; }

  # A matching file only needs permission, activation, and persistence repair.
  if [ "$swap_action" = reuse ]; then
    chmod 0600 "$swap_path" || return 1
    if [ "$swap_active" = 0 ]; then
      swapon --options="$swap_options" "$swap_path" >>"$RUN_LOG" 2>&1 || return 1
      swap_reuse_activated=1
    fi
  elif [ "$swap_action" = remove ]; then
    if [ "$swap_active" = 1 ]; then
      swap_can_deactivate "$swap_path" || return 1
      swapoff "$swap_path" >>"$RUN_LOG" 2>&1 || return 1
      swap_old_off=1
    fi
    # Remove persistence before unlinking, so interruption never leaves a
    # boot entry pointing to a deleted file.
    swap_commit_fstab || return 1
    swap_committed=1
    rm -f "$swap_path" || return 1
    if [ -f "$swap_order_file" ]; then
      rm -f "$swap_order_file" || return 1
      rmdir "$swap_order_dir" 2>/dev/null || :
    fi
  else
    # Btrfs gets a separate subvolume; all new files start private to root.
    if [ "$swap_path" = /swap.virtualmin/swapfile ] && [ ! -d /swap.virtualmin ]; then
      if [ "$swap_fs" = btrfs ]; then
        btrfs subvolume create /swap.virtualmin >>"$RUN_LOG" 2>&1 &&
          chmod 0700 /swap.virtualmin || return 1
      else
        mkdir -m 0700 /swap.virtualmin || return 1
      fi
    fi
    swap_new=$(mktemp "${swap_path}.new.XXXXXX") || return 1
    if [ "$swap_fs" = btrfs ]; then
      # The native helper insists on creating the pathname itself.
      rm -f "$swap_new" || return 1
      btrfs filesystem mkswapfile --size "${swap_size}K" "$swap_new" >>"$RUN_LOG" 2>&1 || return 1
    else
      # Writing all blocks works across the supported ext and XFS versions,
      # including those that reject fallocate-created swapfiles with holes.
      dd if=/dev/zero of="$swap_new" bs=1048576 count=$((swap_size / 1024)) >>"$RUN_LOG" 2>&1 &&
        mkswap "$swap_new" >>"$RUN_LOG" 2>&1 || return 1
    fi
    chmod 0600 "$swap_new" || return 1
    # Prove that the replacement can be activated before touching the old file.
    swapon "$swap_new" >>"$RUN_LOG" 2>&1 || return 1
    if ! swapoff "$swap_new" >>"$RUN_LOG" 2>&1; then
      log_error "Cannot deactivate tested replacement $swap_new; retained it for recovery."
      swap_new=
      return 1
    fi
    if [ "$swap_active" = 1 ]; then
      swap_can_deactivate "$swap_path" || return 1
      swapoff "$swap_path" >>"$RUN_LOG" 2>&1 || return 1
      swap_old_off=1
    fi
    if [ "$swap_old_size" -gt 0 ]; then
      # A hard link retains the original inode while rename atomically puts a
      # valid replacement at the boot pathname, without a missing-file window.
      swap_backup="${swap_new}.old"
      ln "$swap_path" "$swap_backup" || return 1
    fi
    swap_new_installed=1
    mv -f "$swap_new" "$swap_path" || return 1
    swapon --options="$swap_options" "$swap_path" >>"$RUN_LOG" 2>&1 || return 1
  fi

  if [ "$swap_action" != remove ]; then
    swap_commit_fstab || return 1
    swap_committed=1
  fi
  # Refresh generated units only; do not start or stop any other swap areas.
  if [ -d /run/systemd/system ]; then
    systemctl daemon-reload >>"$RUN_LOG" 2>&1 || {
      log_error "Swap updated, but systemd daemon-reload failed."; return 1;
    }
  fi
  printf '%s\n' 'Swap configuration updated.' >>"$RUN_LOG"
)

# memory_ok minimum_kb installation_disk_gb
# Any swap failure stops installation, even when existing memory is sufficient.
memory_ok () {
  if [ -n "$setup_only" ] || [ -n "$noswap" ]; then return 0; fi
  min_mem=${1:-1048576}
  swap_setup "${2:-1}" || return 1
  all_mem=$(awk '$1 == "MemTotal:" || $1 == "SwapTotal:" {n += $2} END {printf "%.0f\n", n}' /proc/meminfo)
  if [ "$all_mem" -lt "$min_mem" ]; then
    log_error "Combined RAM and swap is below $(kb_size_h "$min_mem")."
    return 1
  fi
  return 0
}

# serial_ok $serial $key
# Does the serial number and licnese key look correct?
serial_ok () {
  serial_num=$1
  license_key=$2
  i=0
  while [ $i -eq 0 ]; do
    if res=$(echo "$serial_num" |grep "[^a-z^A-Z^0-9]"); then
      printf "Serial number ${RED}$serial_num${NORMAL} contains invalid characters.\\n"
      get_serial
    elif [ -z "$serial_num" ]; then
      printf "${RED}Serial number cannot be blank.${NORMAL}\\n"
      get_serial
    elif res=$(echo "$license_key" |grep "[^a-z^A-Z^0-9]"); then
      printf "License key ${RED}$license_key${NORMAL} contains invalid characters.\\n"
      get_serial
    elif [ -z "$license_key" ]; then
      printf "${RED}License key cannot be blank.${NORMAL}\\n"
      get_serial
    else
      i=1
    fi
  done
  export SERIAL=$serial_num
  export KEY=$license_key
}

# Ask the user for a new serial number and license key
get_serial () {
  printf "${YELLOW}Please enter your serial number or 'GPL': ${NORMAL}"
  stty echo 1>/dev/null 2>&1
  read -r serial_num
  stty -echo 1>/dev/null 2>&1
  printf "${YELLOW}Please enter your license key or 'GPL': ${NORMAL}"
  stty echo 1>/dev/null 2>&1
  read -r license_key
  stty -echo 1>/dev/null 2>&1
}
