#!/bin/sh
# shellcheck disable=SC3043 disable=SC2086 disable=SC2059 disable=SC2039 disable=SC2034 disable=SC2317
#------------------------------------------------------------------------------
# Utility function library for Virtualmin installation scripts
# slib v1.0.8 (https://github.com/virtualmin/slib)
# Copyright 2017-2024 Joe Cooper
# slog logging library Copyright Fred Palmer and Joe Cooper
# Licensed under the BSD 3 clause license
#------------------------------------------------------------------------------
cleanup () {
  exit_code=$1
  stty echo
  # Make super duper sure we reap all the spinners
  # This is ridiculous, and I still don't know why spinners stick around.
  if [ -n "$allpids" ]; then
    for pid in $allpids; do
      kill "$pid" 1>/dev/null 2>&1
    done
    tput sgr0
  fi
  tput cnorm
  if [ -n "$VIRTUALMIN_INSTALL_TEMPDIR" ]; then
    if echo "$VIRTUALMIN_INSTALL_TEMPDIR" | grep -q "virtualmin-"; then
      rm -rf $VIRTUALMIN_INSTALL_TEMPDIR
    fi
  fi

  if [ "$exit_code" -ne 0 ]; then
    echo
  fi

  exit $exit_code
}

# This tries to catch any exit, whether normal or forced (e.g. Ctrl-C)
if [ "${INTERACTIVE_MODE}" != "off" ]; then
  trap 'cleanup 2' INT
  trap 'cleanup 3' QUIT
  trap 'cleanup 15' TERM
  trap 'cleanup 0' EXIT
fi

# scolors - Color constants
# canonical source http://github.com/swelljoe/scolors

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
      BLUE=$(tput setaf 4)
      MAGENTA=$(tput setaf 5)
      CYAN=$(tput setaf 6)
      WHITE=$(tput setaf 7)
      REDBG=$(tput setab 1)
      GREENBG=$(tput setab 2)
      YELLOWBG=$(tput setab 3)
      BLUEBG=$(tput setab 4)
      MAGENTABG=$(tput setab 5)
      CYANBG=$(tput setab 6)
      WHITEBG=$(tput setab 7)

      # Do we have support
      # for bright colors?
      if [ "$ncolors" -ge 16 ]; then
        BLACK="$(tput setaf 16)"
        WHITE=$(tput setaf 15)
        WHITEBG=$(tput setab 15)
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
  BLUE=''
  MAGENTA=''
  CYAN=''
  WHITE=''
  REDBG=''
  GREENBG=''
  YELLOWBG=''
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
if [ "${INTERACTIVE_MODE}" = "off" ]
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
      tput sc
      env printf "${SPINNER_COLOR}${c}${SPINNER_NORMAL}"
      tput rc
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
  tput rc
  tput cnorm
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
  local columns
  if [ "${INTERACTIVE_MODE}" != "off" ];then
    columns=$(tput cols)
    if [ "$columns" -ge 80 ]; then
      columns=79
    fi
  else
      columns=79
  fi
  # shellcheck disable=SC2004
  COL=$((${columns}-${#msg}-3 ))

  printf "%s%${COL}s" "$2"
  # Make sure there some unicode action in the shell; there's no
  # way to check the terminal in a POSIX-compliant way, but terms
  # are mostly ahead of shells.
  # Unicode checkmark and x mark for run_ok function
  CHECK='\u2714'
  BALLOT_X='\u2718'
  if [ "${INTERACTIVE_MODE}" != "off" ];then
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
  if [ "${INTERACTIVE_MODE}" != "off" ];then
    pidcheck=$(ps --no-headers ${spinpid})
    if [ -n "$pidcheck" ]; then
      echo "$log_pref Made it here...why?" >> ${RUN_LOG}
      kill $spinpid 2>/dev/null
      rm -rf ${SPINNER_DONEFILE} 2>/dev/null 2>&1
      tput rc
      tput cnorm
    fi
  fi
  # Log what we were supposed to be running
  msg_safe=$(echo "$msg" | prepare_log_for_nonterminal)
  printf "$log_pref ${msg_safe}: " >> ${RUN_LOG}
  if shell_has_unicode; then
    if [ $res -eq 0 ]; then
      printf "$log_pref Success.\\n" >> ${RUN_LOG}
      env printf "${GREENBG} ${CHECK} ${NORMAL}\\n"
      return 0
    else
      printf "$log_pref Failed with error: ${res}\\n" >> ${RUN_LOG}
      env printf "${REDBG} ${BALLOT_X} ${NORMAL}\\n"
      if [ "$RUN_ERRORS_FATAL" ]; then
        echo
        log_fatal "Something went wrong. Exiting."
        log_fatal "The last few log entries were:"
        tail -15 ${RUN_LOG}
        exit 1
      fi
      return ${res}
    fi
  else
    if [ $res -eq 0 ]; then
      printf "$log_pref Success.\\n" >> ${RUN_LOG}
      env printf "${GREENBG} OK ${NORMAL}\\n"
      return 0
    else
      printf "$log_pref Failed with error: ${res}\\n" >> ${RUN_LOG}
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
  if [ "$VIRTUALMIN_NONINTERACTIVE" = "1" ]; then
    return 0
  fi
  if [ "$NONINTERACTIVE" = "1" ]; then
    echo "Non-interactive shell detected. Cannot continue, as the script may need to ask questions."
    echo "If you're running this from a script and want to install with default options, use '--force'."
    echo "Never run this script on a system already running Virtualmin."
    return 1
  fi
  stty echo
  while read -r line; do
    stty -echo
    case $line in
      y|Y|Yes|YES|yes|yES|yEs|YeS|yeS) return 0
      ;;
      n|N|No|NO|no|nO) return 1
      ;;
      *)
      stty echo
      printf "\\n${YELLOW}Please enter ${CYAN}[y]${YELLOW} or ${CYAN}[n]${YELLOW}:${NORMAL} "
      ;;
    esac
  done
  stty -echo
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
  defaultdev=$(ip ro ls|grep default|head -1|sed -e 's/.*\sdev\s//g'|awk '{print $1}')
  primaryaddr=$(ip -f inet addr show dev "$defaultdev" | grep 'inet ' | awk '{print $2}' | head -1 | cut -d"/" -f1 | cut -f1)
  if [ "$primaryaddr" ]; then
    log_debug "Primary address detected as $primaryaddr"
    address=$primaryaddr
    return 0
  else
    log_warning "Unable to determine IP address of primary interface."
    echo "Please enter the name of your primary network interface: "
    stty echo
    read -r primaryinterface
    stty -echo
    #primaryaddr=`/sbin/ifconfig $primaryinterface|grep 'inet addr'|cut -d: -f2|cut -d" " -f1`
    primaryaddr=$(/sbin/ip -f inet -o -d addr show dev "$primaryinterface" | head -1 | awk '{print $4}' | head -1 | cut -d"/" -f1)
    if [ "$primaryaddr" = "" ]; then
      # Try again with FreeBSD format
      primaryaddr=$(/sbin/ifconfig "$primaryinterface"|grep 'inet' | awk '{ print $2 }')
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
  # If cloud-init is installed, preserve the hostname Virtualmin sets
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
      stty echo
      read -r line
      stty -echo
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

# memory_ok - Function to check for enough memory. Will fix it, if not, by
# adding a swap file.
memory_ok () {
  min_mem=$1
  disk_space_required=$2
  # If Virtualmin swap hasn't been setup yet, try doing it
  is_swap=$(swapon -s|grep /swap.vm)
  if [ -n "$is_swap" ]; then
    if [ -z "$min_mem" ]; then
      min_mem=1048576
    fi
    # Check the available RAM and swap
    mem_total=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
    swap_total=$(awk '/SwapTotal/ {print $2}' /proc/meminfo)
    all_mem=$((mem_total + swap_total))
    swap_min=$(( 1286144 - all_mem ))

    if [ "$swap_min" -lt '262144' ]; then
      swap_min=262144
    fi

    min_mem_h=$((min_mem / 1024))
    if [ "$all_mem" -gt "$min_mem" ]; then
      log_debug "Memory is greater than ${min_mem_h} MB, which should be sufficient."
      return 0
    else
      log_error "Memory is below ${min_mem_h} MB. A full installation may not be possible."
    fi

    # We'll need swap, so ask and turn some on.
    swap_min_h=$((swap_min / 1024))
    echo
    echo "  Your system has less than ${min_mem_h} MB of available memory and swap."
    echo "  Installation is likely to fail, especially on Debian/Ubuntu systems (apt-get"
    echo "  grows very large when installing large lists of packages). You could exit"
    echo "  and re-install with the --minimal flag to install a more compact selection"
    echo "  of packages, or we can try to create a swap file for you. To create a swap"
    echo "  file, you'll need ${swap_min_h} MB free disk space, in addition to $disk_space_required GB of free space"
    echo "  for packages installation."
    echo
    echo "  Would you like to continue? If you continue, you will be given the option to" 
    printf "  create a swap file. (y/n) "
    if ! yesno; then
      return 1 # Should exit when this function returns 1
    fi
    echo
    echo "  Would you like for me to try to create a swap file? This will require" 
    echo "   at least ${swap_min_h} MB of free space, in addition to $disk_space_required GB for the"

    printf "  installation. (y/n) "
    if ! yesno; then
      log_warning "Proceeding without creating a swap file. Installation may fail."
      return 0
    fi

    # Check for btrfs, because it can't host a swap file safely.
    root_fs_type=$(grep -v "^$\\|^\\s*#" /etc/fstab | awk '{print $2 " " $3}' | grep "/ " | cut -d' ' -f2)
    if [ "$root_fs_type" = "btrfs" ]; then
      log_fatal "Your root filesystem appears to be running btrfs. It is unsafe to create"
      log_fatal "a swap file on a btrfs filesystem. You'll either need to use the --minimal"
      log_fatal "installation or create a swap file manually (on some other filesystem)."
      return 2
    fi

    # Check for enough space.
    root_fs_avail=$(df /|grep -v Filesystem|awk '{print $4}')
    if [ "$root_fs_avail" -lt $((swap_min + 358400)) ]; then
      root_fs_avail_h=$((root_fs_avail / 1024))
      log_fatal "Root filesystem only has $root_fs_avail_h MB available, which is too small."
      log_fatal "You'll either need to use the --minimal installation of add more space to '/'."
      return 3
    fi

    # Create a new file
    if ! dd if=/dev/zero of=/swap.vm bs=1024 count=$swap_min 1>>${RUN_LOG} 2>&1; then
      log_fatal "Creating swap file /swap.vm failed."
      return 4
    fi
    chmod 0600 /swap.vm 1>>${RUN_LOG} 2>&1
    mkswap /swap.vm 1>>${RUN_LOG} 2>&1
    if ! swapon /swap.vm 1>>${RUN_LOG} 2>&1; then
      log_fatal "Enabling swap file failed. If this is a VM, it may be prohibited by your provider."
      return 5
    fi
    echo "/swap.vm          swap            swap    defaults        0 0" >> /etc/fstab
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
  stty echo
  read -r serial_num
  stty -echo
  printf "${YELLOW}Please enter your license key or 'GPL': ${NORMAL}"
  stty echo
  read -r license_key
  stty -echo
}
