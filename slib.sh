#!/bin/sh
#--------------------------------------------------------------------------------------------------
# slib - Utility function library for Virtualmin installation scripts
# Copyright Joe Cooper
# slog logging library Copyright Fred Palmer and Joe Cooper
# Licensed under the BSD 3 clause license
# http://github.com/virtualmin/slib
#--------------------------------------------------------------------------------------------------
set -e  # Fail on first error

# scolors - Color constants
# canonical source http://github.com/swelljoe/scolors

# do we have tput?
if type 'tput' > /dev/null; then
  # do we have a terminal?
  if [ -t 1 ]; then
    # does the terminal have colors?
    ncolors=$(tput colors)
    if [ $ncolors -ge 8 ]; then	
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
    
      BOLD=$(tput bold)
      UNDERLINE=$(tput smul) # Many terminals don't support this
      NORMAL=$(tput sgr0)
    fi
  fi
else
  echo "tput not found, colorized output disabled."
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
SCRIPT_ARGS="$@"
SCRIPT_NAME="$0"
SCRIPT_NAME="${SCRIPT_NAME#\./}"
SCRIPT_NAME="${SCRIPT_NAME##/*/}"
SCRIPT_BASE_DIR="$(cd "$( dirname "$0")" && pwd )"

# Determines if we print colors or not
if [ $(tty -s) ]; then
    readonly INTERACTIVE_MODE="off"
else
    readonly INTERACTIVE_MODE="on"
fi

#--------------------------------------------------------------------------------------------------
# Begin Logging Section
if [ "${INTERACTIVE_MODE}" = "off" ]
then
    # Then we don't care about log colors
    readonly LOG_DEFAULT_COLOR=""
    readonly LOG_ERROR_COLOR=""
    readonly LOG_INFO_COLOR=""
    readonly LOG_SUCCESS_COLOR=""
    readonly LOG_WARN_COLOR=""
    readonly LOG_DEBUG_COLOR=""
else
    readonly LOG_DEFAULT_COLOR=$(tput sgr0)
    readonly LOG_ERROR_COLOR=$(tput setaf 1)
    readonly LOG_INFO_COLOR=$(tput sgr 0)
    readonly LOG_SUCCESS_COLOR=$(tput setaf 2)
    readonly LOG_WARN_COLOR=$(tput setaf 3)
    readonly LOG_DEBUG_COLOR=$(tput setaf 4)
fi

# Levels for comparing against LOG_LEVEL_STDOUT and LOG_LEVEL_LOG
readonly LOG_LEVEL_DEBUG=0
readonly LOG_LEVEL_INFO=1
readonly LOG_LEVEL_SUCCESS=2
readonly LOG_LEVEL_WARNING=3
readonly LOG_LEVEL_ERROR=4

# This function scrubs the output of any control characters used in colorized output
# It's designed to be piped through with text that needs scrubbing.  The scrubbed
# text will come out the other side!
prepare_log_for_nonterminal() {
    # Essentially this strips all the control characters for log colors
    sed "s/[[:cntrl:]]\[[0-9;]*m//g"
}

log() {
    local log_text="$1"
    local log_level="$2"
    local log_color="$3"

    # Default level to "info"
    [ -z ${log_level} ] && log_level="INFO";
    [ -z ${log_color} ] && log_color="${LOG_INFO_COLOR}";

    # Validate LOG_LEVEL_STDOUT and LOG_LEVEL_LOG since they'll be eval-ed.
    case $LOG_LEVEL_STDOUT in
        DEBUG|INFO|SUCCESS|WARNING|ERROR)
            break
            ;;
        *)
            LOG_LEVEL_STDOUT=INFO
            break
            ;;
    esac
    case $LOG_LEVEL_LOG in
        DEBUG|INFO|SUCCESS|WARNING|ERROR)
            break
            ;;
        *)
            LOG_LEVEL_LOG=INFO
            break
            ;;
    esac

    # Check LOG_LEVEL_STDOUT to see if this level of entry goes to STDOUT.
    # XXX This is the horror that happens when your language doesn't have a hash data struct.
    eval log_level_int="\$LOG_LEVEL_${log_level}";
    eval log_level_stdout="\$LOG_LEVEL_${LOG_LEVEL_STDOUT}"
    if [ $log_level_stdout -le $log_level_int ]; then
        # STDOUT
        printf "${log_color}[$(date +"%Y-%m-%d %H:%M:%S %Z")] [${log_level}] ${log_text} ${LOG_DEFAULT_COLOR}\n";
    fi
    eval log_level_log="\$LOG_LEVEL_${LOG_LEVEL_LOG}"
    # Check LOG_LEVEL_LOG to see if this level of entry goes to LOG_PATH
    if [ $log_level_log -le $log_level_int ]; then
        # LOG_PATH minus fancypants colors
        if [ ! -z $LOG_PATH ]; then
            printf "[$(date +"%Y-%m-%d %H:%M:%S %Z")] [${log_level}] ${log_text}\n" >> $LOG_PATH;
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
SPINNER_SYMBOLS="UNI_DOTS2" # Name of the variable containing the symbols.
SPINNER_CLEAR=1 # Blank the line when done.

spinner () {
  # Safest option are one of these. Doesn't need Unicode, at all.
  local ASCII_PROPELLER="/ - \\ |"
  local ASCII_PLUS="x +"
  local ASCII_BLINK="o -"
  local ASCII_V="v < ^ >"
  local ASCII_INFLATE=". o O o"

  # Needs Unicode support in shell and terminal.
  # These are ordered most to least likely to be available, in my limited experience.
  local UNI_DOTS="⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏"
  local UNI_DOTS2="⣾ ⣽ ⣻ ⢿ ⡿ ⣟ ⣯ ⣷"
  local UNI_DOTS3="⣷ ⣯ ⣟ ⡿ ⢿ ⣻ ⣽ ⣾"
  local UNI_DOTS4="⠋ ⠙ ⠚ ⠞ ⠖ ⠦ ⠴ ⠲ ⠳ ⠓"
  local UNI_DOTS5="⠄ ⠆ ⠇ ⠋ ⠙ ⠸ ⠰ ⠠ ⠰ ⠸ ⠙ ⠋ ⠇ ⠆"
  local UNI_DOTS6="⠋ ⠙ ⠚ ⠒ ⠂ ⠂ ⠒ ⠲ ⠴ ⠦ ⠖ ⠒ ⠐ ⠐ ⠒ ⠓ ⠋"
  local UNI_DOTS7="⠁ ⠉ ⠙ ⠚ ⠒ ⠂ ⠂ ⠒ ⠲ ⠴ ⠤ ⠄ ⠄ ⠤ ⠴ ⠲ ⠒ ⠂ ⠂ ⠒ ⠚ ⠙ ⠉ ⠁"
  local UNI_DOTS8="⠈ ⠉ ⠋ ⠓ ⠒ ⠐ ⠐ ⠒ ⠖ ⠦ ⠤ ⠠ ⠠ ⠤ ⠦ ⠖ ⠒ ⠐ ⠐ ⠒ ⠓ ⠋ ⠉ ⠈"
  local UNI_DOTS9="⠁ ⠁ ⠉ ⠙ ⠚ ⠒ ⠂ ⠂ ⠒ ⠲ ⠴ ⠤ ⠄ ⠄ ⠤ ⠠ ⠠ ⠤ ⠦ ⠖ ⠒ ⠐ ⠐ ⠒ ⠓ ⠋ ⠉ ⠈ ⠈"
  local UNI_DOTS10="⢹ ⢺ ⢼ ⣸ ⣇ ⡧ ⡗ ⡏"
  local UNI_DOTS11="⢄ ⢂ ⢁ ⡁ ⡈ ⡐ ⡠"
  local UNI_DOTS12="⠁ ⠂ ⠄ ⡀ ⢀ ⠠ ⠐ ⠈"
  local UNI_BOUNCE="⠁ ⠂ ⠄ ⠂"
  local UNI_PIPES="┤ ┘ ┴ └ ├ ┌ ┬ ┐"
  local UNI_HIPPIE="☮ ✌ ☺ ♥"
  local UNI_HANDS="☜ ☝ ☞ ☟"
  local UNI_ARROW_ROT="➫ ➭ ➬ ➭"
  local UNI_CARDS="♣ ♤ ♥ ♦"
  local UNI_TRIANGLE="◢ ◣ ◤ ◥"
  local UNI_SQUARE="◰ ◳ ◲ ◱"
  local UNI_BOX_BOUNCE="▖ ▘ ▝ ▗"
  local UNI_PIE="◴ ◷ ◶ ◵"
  local UNI_CIRCLE="◐ ◓ ◑ ◒"
  local UNI_QTR_CIRCLE="◜ ◝ ◞ ◟" 

  # Bigger spinners and progress type bars; takes more space.
  local WIDE_ASCII_PROG="[>----] [=>---] [==>--] [===>-] [====>] [----<] [---<=] [--<==] [-<===] [<====]"
  local WIDE_ASCII_PROPELLER="[|####] [#/###] [##-##] [###\\#] [####|] [###\\#] [##-##] [#/###]"
  local WIDE_ASCII_SNEK="[>----] [~>---] [~~>--] [~~~>-] [~~~~>] [----<] [---<~] [--<~~] [-<~~~] [<~~~~]"
  local WIDE_UNI_GREYSCALE="░░░░░░░ ▒░░░░░░ ▒▒░░░░░ ▒▒▒░░░░ ▒▒▒▒░░░ ▒▒▒▒▒░░ ▒▒▒▒▒▒░ ▒▒▒▒▒▒▒ ▒▒▒▒▒▒░ ▒▒▒▒▒░░ ▒▒▒▒░░░ ▒▒▒░░░░ ▒▒░░░░░ ▒░░░░░░ ░░░░░░░"

  local SPINNER_NORMAL=$(tput sgr0)

  eval SYMBOLS=\$${SPINNER_SYMBOLS}

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
      local COLOR=$(tput setaf ${SPINNER_COLORNUM})
      tput sc
      env printf "${COLOR}${c}${SPINNER_NORMAL}"
      tput rc
      if [ -f "${SPINNER_DONEFILE}" ]; then
        if [ ${SPINNER_CLEAR} -eq 1 ]; then
          tput el
        fi
	rm ${SPINNER_DONEFILE}
	break 2
      fi
      # This is questionable. sleep with fractional seconds is not
      # always available, but seems to not break things, when not.
      env sleep .2
    done
  done
  tput cnorm
  return 0
}

# run_ok - function to run a command or function, start a spinner and print a confirmation
# indicator when done.
# Canonical source - http://github.com/swelljoe/run_ok

log="run.log"

# Check for unicode support in the shell
# This is a weird function, but seems to work. Checks to see if a unicode char can be
# written to a file and can be read back.
shell_has_unicode () {
  # Write a unicode character to a file...read it back and see if it's handled right.
  env printf "\u2714"> unitest.txt

  read unitest < unitest.txt
  rm unitest.txt
  if [ ${#unitest} -le 3 ]; then
    return 0
  else
    return 1
  fi
}

# Setup spinner with our prefs.
SPINNER_COLORCYCLE=0
SPINNER_COLORNUM=5
if shell_has_unicode; ;then
  SPINNER_SYMBOLS="WIDE_UNI_GREYSCALE"
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
  local cmd="\${1}"
  local msg="${2}"
  local columns=$(tput cols)
  if [ $columns -ge 80 ]; then
    columns=80
  fi
  COL=$(( ${columns}-${#msg}+${#GREENBG}+${#NORMAL} ))

  printf "%s%${COL}s" "$2"
  # Make sure there some unicode action in the shell; there's no
  # way to check the terminal in a POSIX-compliant way, but terms
  # are mostly ahead of shells.
  # Unicode checkmark and x mark for run_ok function
  CHECK='\u2714'
  BALLOT_X='\u2718'
  (spinner &)
  eval ${cmd} >> ${log}
  local res=$?
  touch stopspinning
  while [ -f stopspinning ]; do
    sleep .2 # It's possible to have a race for stdout and spinner clobbering the next bit
  done
  # Log what we were supposed to be running
  printf "$msg: " >> ${log}
  if shell_has_unicode; then
    if [ $res -eq 0 ]; then
      printf "Success.\n" >> ${log}
      env printf "${GREENBG}[  ${CHECK}  ]${NORMAL}\n"
      return 0
    else
      log_error "Failed with error: ${res}\n"
      env printf "${REDBG}[  ${BALLOT_X}  ]${NORMAL}\n"
      return $?
    fi
  else
    if [ $res -eq 0 ]; then
      printf "Success.\n" >> ${log}
      env printf "${GREENBG}[ OK! ]${NORMAL}\n"
      return 0
    else
      printf "Failed with error: ${res}\n" >> ${log}
      env printf "${REDBG}[ERROR]${NORMAL}\n"
      return $?
    fi
  fi
}

# Ask a yes or no question
# if $skipyesno is 1, always Y
# if NONINTERACTIVE environment variable is 1, always Y
yesno () {
  if [ "$skipyesno" = "1" ]; then
    return 0
  fi
  if [ "$NONINTERACTIVE" = "1" ]; then
    return 0
  fi
  if [ "$VIRTUALMIN_NONINTERACTIVE" = "1" ]; then
    return 0
  fi
  while read line; do
    case $line in
      y|Y|Yes|YES|yes|yES|yEs|YeS|yeS) return 0
      ;;
      n|N|No|NO|no|nO) return 1
      ;;
      *)
      printf "\nPlease enter y or n: "
      ;;
    esac
  done
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
  primaryaddr=$(/sbin/ip -f inet -o -d addr show dev \`/sbin/ip ro ls | grep default | awk '{print $5}'\` | head -1 | awk '{print $4}' | cut -d"/" -f1)
  if [ "$primaryaddr" ]; then
    log_info "Primary address detected as $primaryaddr"
    address=$primaryaddr
    return 0
  else
    log_info "Unable to determine IP address of primary interface."
    echo "Please enter the name of your primary network interface: "
    read primaryinterface
    #primaryaddr=`/sbin/ifconfig $primaryinterface|grep 'inet addr'|cut -d: -f2|cut -d" " -f1`
    primaryaddr=$(/sbin/ip -f inet -o -d addr show dev "$primaryinterface" | head -1 | awk '{print $4}' | cut -d"/" -f1)
    if [ "$primaryaddr" = "" ]; then
      # Try again with FreeBSD format
      primaryaddr=$(/sbin/ifconfig "$primaryinterface"|grep 'inet' | awk '{ print $2 }')
    fi
    if [ "$primaryaddr" ]; then
      log_info "Primary address detected as $primaryaddr"
      address=$primaryaddr
    else
      fatal "Unable to determine IP address of selected interface.  Cannot continue."
    fi
    return 0
  fi
}

# Set the hostname
set_hostname () {
  i=0
  while [ $i -eq 0 ]; do
    if [ "$forcehostname" = "" ]; then
      printf "${RED}Please enter a fully qualified hostname (for example, host.example.com): ${NORMAL}"
      read line
    else
      log_debug "Setting hostname to $forcehostname"
      line=$forcehostname
    fi
    if ! is_fully_qualified "$line"; then
      log_info "Hostname $line is not fully qualified."
    else
      hostname "$line"
      detect_ip
      if grep "$address" /etc/hosts; then
        log_debug "Entry for IP $address exists in /etc/hosts."
        log_debug "Updating with new hostname."
        shortname=$(echo "$line" | cut -d"." -f1)
        sed -i "s/^$address\([\s\t]+\).*$/$address\1$line\t$shortname/" /etc/hosts
      else
        log_debug "Adding new entry for hostname $line on $address to /etc/hosts."
        printf "%s\t%s\t%s\n" \
        "$address" "$line" "$shortname" >> /etc/hosts
      fi
      i=1
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
    *.*)
      log_success "Hostname OK: fully qualified as $1"
      return 0
      ;;
  esac
  log_warning "Hostname $name is not fully qualified."
  return 1
}
