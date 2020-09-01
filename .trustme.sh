#!/bin/bash
# vim:tw=0:ts=2:sw=2:et:norl:spell

# WHAT: A Continuous Integration (CI) script that's async-safe.

# USAGE: If you have Vim, check out the Dubsacks Vim plugin:
#
#          https://github.com/landonb/dubs_edit_juice
#
#        which automatically looks for a .trustme.vim above
#        any file you load into a buffer.
#
#        You can install the plugin or just copy the BufEnter
#        autocmd that loads for the .trustme.vim file, from:
#
#          plugin/dubs_edit_juice.vim
#
#        To wire it yourself instead, check out inotifywait:
#
#          https://linux.die.net/man/1/inotifywait
#
#        Ubuntu users can install from Aptitude
#
#          apt-get install inotify-tools
#
#        and then watch files from a shell script, e.g.,
#
#          inotifywait \
#            -mr \
#            --timefmt '%d/%m/%y %H:%M' \
#            --format '%T %w %f %e' \
#            -e close_write /path/to/project \
#            | while read date time dir file events; do
#              /path/to/project/.trustme.sh
#          done
#
# NOTE:  On Vim, if you're using the project.vim plugin, you'll need
#        to add a reference to the script from the directory entry.
#        Otherwise, when you double-click files in the project window
#        to open them, the BufEnter event doesn't trigger properly.
#        E.g.,
#
#          MY_PROJ=/path/to/proj in=".trustme.vim" filter=".* *" {
#            # ...
#          }
#
# WATCH: All script output gets writ to a file. Use a terminal to tail it:
#
#          tail -F .trustme.log
#
# TEST:  From one terminal:
#
#          tail -F .trustme.log
#
#        From another terminal:
#
#          TRUSTME_VERBOSE=true DUBS_TRUST_ME_ON_SAVE=1 ./.trustme.sh

source_plugin() {
  # This script is run relative to Vim's working directory,
  # so be deliberate about paths.
  #   ${BASH_SOURCE[0]} should be the absolute path to this script.
  # If you add libraries to the trust_me source, source it:
  #   TRUSTME_DIR=$(dirname $(readlink -f "${BASH_SOURCE[0]}"))
  #   source "${TRUSTME_DIR}/file"
  PROJECT_DIR=$(dirname -- "${BASH_SOURCE[0]}")
  DOTFILENAME=${TRUSTME_BASENAME:-.trustme}

  source_home_fries_util 'color_util.sh'
  source_home_fries_util 'logger.sh'

  PROJ_PLUGIN="${PROJECT_DIR}/${DOTFILENAME}.plugin"
  if [[ ! -f "${PROJ_PLUGIN}" ]]; then
    say "No project plugin! Nothing to do. Hint: Create and edit: ${PROJ_PLUGIN}"
    exit 1
  fi
  source "${PROJ_PLUGIN}"
}

source_home_fries_util() {
  local home_fries_util="$1"
  local source_path="${home_fries_util}"
  local log_success=false
  # DEV: Uncomment to get help with source errors.
  #  log_success=true
  # If the /user/home/.fries/lib path is on $PATH, you can just source it.
  if ! source "${source_path}" &> /dev/null; then
    # But if it's not on $PATH, see if this script is a symlink, and if so,
    # see if the util file is part of this file's owning repo.
    if [[ -h "${BASH_SOURCE[0]}" ]]; then
      # If this script is symlinked, checked its real path for the source file.
      source_path="$(dirname $(readlink -f ${BASH_SOURCE[0]}))/${home_fries_util}"
      if ! source "${source_path}" &> /dev/null; then
        # 2018-05-16 11:30: Ug, this fcn. is a mess now! So nested!
        # Use commonly used Home Fries location if not found so far.
        # What's up? If you run Vim from terminal, it inherits your
        # $PATH (and home-fries/lib is on your PATH, right?); but if
        # you run Vim from Gnome Launcher, or from Keyboard Shortcut,
        # it's got a basic $PATH. Real solution is to fix PATH from
        # your .vimrc; but we can be nice and patch it here, too.
        source_path="${HOME}/.fries/lib/${home_fries_util}"
        if ! source "${source_path}" &> /dev/null; then
          >&2 echo "Unable to find and source ${home_fries_util}. You're missing out!"
          # Rather than not exiting now, we could keep running, if we chose
          # to not use the libraries being loaded (2018-05-16: which is
          # just the logger and the color library), we could write our code
          # to work without said libraries. But it's not wired that way.
          exit 1
        elif $log_success; then
          echo "Sourced: Found in home-fries: ${source_path}"
        fi
      elif $log_success; then
        echo "Sourced: Inferred path from symlink: ${source_path}"
      fi
    fi
  elif $log_success; then
    echo "Sourced: Already on \$PATH: ${source_path}"
  fi
}

# ***

assign_globals_() {
  OUT_FILE="${PROJECT_DIR}/${DOTFILENAME}.log"

  LOCK_DIR="${PROJECT_DIR}/${DOTFILENAME}.lock"
  KILL_DIR="${PROJECT_DIR}/${DOTFILENAME}.kill"
  PID_FILE="${PROJECT_DIR}/${DOTFILENAME}.pid"
  # Hrm. The bang might not work without
  KILL_BIN="${PROJECT_DIR}/${DOTFILENAME}.kill!"

  # DEVS: You may want to set this, e.g., to 1, or to 300, depending on
  # how heavy your CI is. If it's a lot of CPU, set a longer delay.
  BUILD_DELAY_SECS=${TRUSTME_DELAYSECS:-0}

  # FIXME: Add an --arg parser, and add a --verbose/-V flag.
  TRUSTME_VERBOSE=${TRUSTME_VERBOSE:-false}

  # From Vim:
  #   PARENT_COMMAND=systemd
  # From Bash (invoked by user):
  #   PARENT_COMMAND=bash
  PARENT_COMMAND="$(ps -o comm= $PPID)"
}

assign_globals() {
  assign_globals_
}

# ***

say() {
  FORCE_ECHO=${2:-false}
  # Restrict newlines to no more than 2 in a row.
  TRUSTME_SAID_NEWLINE=${TRUSTME_SAID_NEWLINE:-false}
  if [[ "${PARENT_COMMAND}" == 'bash' ]]; then
    echo -e "$1"
  elif ${FORCE_ECHO} || ! ${TRUSTME_SAID_NEWLINE} || [[ ("$1" != "") ]]; then
    # Use -e so colors are included.
    echo -e "$1" >> "${OUT_FILE}"
  fi
  if [[ "$1" != "" ]]; then
    TRUSTME_SAID_NEWLINE=false
  else
    TRUSTME_SAID_NEWLINE=true
  fi
}

verbose() {
  ${TRUSTME_VERBOSE} && say "$@"
}

announcement() {
  local slugline="$2"
  local bordelimiter="${3-#}"
  local hlit="${4-${FG_REG}${BG_MAROON}}"
  #local hlit="${4-${FG_REG}${BG_MAROON}${FONT_LINE}}"
  say
  local bord=$(repeat_char ${bordelimiter} 67)
  local norm="${FONT_NORM}"
  say "${hlit}${bord}${norm}"
  say "$1"
  say "${hlit}${bord}${norm}"
  [[ "${slugline}" != '' ]] && say "${slugline}"
  say
}

verbose_announcement() {
  ${TRUSTME_VERBOSE} && announcement "$@"
}

say_pass() {
  say "$(fg_mediumgrey)<pass>$(attr_reset)"
}

say_skip() {
  say "$(fg_mediumgrey)<skip>$(attr_reset)"
}

repeat_char() {
  [[ -z $1 ]] && >&2 echo 'repeat_char: expecting 1st arg: character to repeat' && return 1
  [[ -z $2 ]] && >&2 echo 'repeat_char: expecting 2nd arg: num. of repetitions' && return 1
  # Bash expands {1..n} so the command becomes:
  #   printf '=%.0s' 1 2 3 4 ... 100
  # Where printf's format is =%.0s which means that it will always
  # print a single '=' no matter what argument it is given.
  printf "$1"'%.s' $(eval "echo {1.."$(($2))"}")
}

# ***

home_fries_nanos_now () {
  if command -v gdate > /dev/null 2>&1; then
    # macOS (brew install coreutils).
    gdate +%s.%N
  elif date --version > /dev/null 2>&1; then
    # Linux/GNU.
    date +%s.%N
  else
    # macOS pre-coreutils.
    python -c 'import time; print("{:.9f}".format(time.time()))'
  fi
}
æl
# ***

death() {
  if [[ -n ${WAIT_PID} ]]; then
    say "Sub-killing ‘${WAIT_PID}’"
    kill -s 9 ${WAIT_PID}
  fi
  # The other script waits for us to cleanup the PID file.
  remove_pid_files
  # Note that output gets interleaved with the killing process,
  # so keep this to one line (don't use `announcement`).
  say "☠☠☠ DEATH! ☠☠☠ ‘$$’ is now dead"
  exit 1
}

lock_kill_die() {
  say "┏ Desperately Seeking Lock on $(date)..."
  local AFTER_WAIT
  [[ "$1" == true ]] && AFTER_WAIT=true || AFTER_WAIT=false
  local build_it=false
  # mkdir is atomic. Isn't that nice.
  if $(mkdir "${LOCK_DIR}" 2> /dev/null); then
    say "┣━ Scored the lock!"
    kill_other ${AFTER_WAIT} true
  elif [[ -d "${LOCK_DIR}" ]]; then
    if ! ${AFTER_WAIT}; then
      # There's another script waiting to build, or a build going on.
      # Kill it if you can.
      say "┣━ Could not lock, but can still kill!"
      kill_other ${AFTER_WAIT} false
    else
      # This script got the lock earlier, released it, and slept, and now
      # it cannot get the lock...
      say "┣━ i waited for you but you locked me out"
      say "┗"
      exit
    fi
  else
    announcement "WARNING: could not mkdir ‘${LOCK_DIR}’ and it does not exist, later!"
    exit
  fi
  say "┣━ made it out alive!"
}

kill_other() {
  [[ "$1" == true ]] && local AFTER_WAIT=true || local AFTER_WAIT=false
  [[ "$2" == true ]] && local OUR_LOCK=true || local OUR_LOCK=false

  must_mkdir_kill_dir

  if [[ -f "${PID_FILE}" ]]; then
    local build_pid=$(cat "${PID_FILE}")
    say "┣━ Found PID file ‘${PID_FILE}’ harboring ‘${build_pid}’."
    if ${AFTER_WAIT}; then
      if [[ "$$" != "${build_pid}" ]]; then
        say "┗━━ Panic, jerks! The build_pid is not our PID! ${build_pid} != $$"
        rmdir "${KILL_DIR}"
        exit
      fi
    elif [[ "${build_pid}" != '' ]]; then
      say "┣━━ Killing ‘${build_pid}’"
      say '' true
      # Process, your time has come.
      kill -s SIGUSR1 "${build_pid}" >> "${OUT_FILE}" 2>&1
      killed=$?
      say '' true
      if [[ ${killed} -ne 0 ]]; then
        say "┣━━━ Kill failed! On PID ‘${build_pid}’"
        # So, what happened? Did the build complete?
        # Should we just move along? Probably...
        # Get the name of the process. If it still exists, die.
        if [[ $(ps -p "${build_pid}" -o comm=) != '' ]]; then
          say "┗━━━  Said process still exists!"
          rmdir "${KILL_DIR}"
          exit
        fi
        # The process is a ghost.
        remove_pid_files
      else
        # Wait for the other trustme to clean up.
        local wait_patience=10
        sleep 0.1
        while [[ -f "${PID_FILE}" ]]; do
          say "┣━━━ Waiting on PID ${build_pid} to cleanup..."
          sleep 0.5
          if $(ps p 24397 &> /dev/null); then
            say "┗━━ Disappeared!"
            remove_pid_files
            break
          fi
          wait_patience=$((${wait_patience} - 1))
          if [[ ${wait_patience} -eq 0 ]]; then
            say "┗━━  Done waiting!"
            rmdir "${KILL_DIR}"
            exit
          fi
        done
      fi
    else
      say "WARNING: Empty PID file? Whatever, we'll take it!"
    fi
  elif ! ${OUR_LOCK}; then
    # This is after waiting, which seems weird, eh.
    say "Kill okay without build lock, but no PID file. Is someone tinkering?"
    exit
  else
    say "Got the build lock and kill lock, and there's no PID. Fresh powder!"
  fi
}

must_mkdir_kill_dir() {
  local wait_patience=10
  while true; do
    if $(mkdir "${KILL_DIR}" 2> /dev/null); then
      return  # Success!
    fi
    say "┣━━ Waiting on Kill Dir!..."
    sleep 0.5
    wait_patience=$((${wait_patience} - 1))
    if [[ ${wait_patience} -eq 0 ]]; then
      say "┣━ Done waiting! Dying instead!!"
      say "┗━━ A/k/a: Someone else has the kill lock. We're boned!"
      exit
    fi
  done
}

lock_or_die() {
  lock_kill_die false
}

lock_kill_or_die() {
  lock_kill_die true
}

# ***

wait_maybe_fail_pre_exit() {
  : # no-op
}

wait_maybe_fail_success() {
  : # no-op
}

wait_maybe_fail() {
  # Caller: $! gets PID of last &'ed or bg'ed process -- your responsibility to have done so.
  WAIT_PID=$!
  wait ${WAIT_PID}
  local wait_for_what=$?
  if [[ ${wait_for_what} -ne 0 ]]; then
    say "ERROR: See previous error: we sniffed a ${wait_for_what}!"
    wait_maybe_fail_pre_exit
    exit ${wait_for_what}
  fi
  wait_maybe_fail_success
  WAIT_PID=
}

# ***

alert_success_toast() {
  local message
  local title
  local timeout
  message="${1:-Yay!}"
  title="${2:-Build Success!}"
  timeout=${3:-2123}
  if ``command -v notify-send >/dev/null 2>&1``; then
    #notify-send -i face-wink -t 1234 \
    #  'Build Success!' 'Murano CLI says, "Woot woot!!"'
    # 2018-03-19: 1234 msec. is a tad too long. Something quicker,
    # so I can train myself to ignore if it's a blip in the corner of my eye.
    # Just make sure your mouse into over popup, or it won't go away!
    # Hahaha, at 333 msec. it's basically a flash on the screen...
    #   in that case, there's probably a better way to implement this!
    notify-send \
      -t ${timeout} \
      -u normal \
      -i '/home/landonb/.waffle/home/Pictures/Landonb-Bitmoji-Thumbs.Up.png' \
      "${title}" \
      "${message}"
  fi
}

alert_success_flash() {
  local duration
  #duration=${1:-0.075}
  # 2018-07-10 14:07: Sometimes the inversion sticks! Trying longer sleep...
  #duration=${1:-0.100}
  duration=${1:-0.150}
  # 2018-03-19 18:04: This just gets better!
  # sudo apt-get install xcalib
  ##xcalib -invert -alter
  #xcalib -alter -invert
  # xcalib, because of X, only works on the first monitor!
  # 2018-04-12: But I found a solution that works on all!!
  /srv/opt/bin/xrandr-invert-colors.bin
  sleep ${duration}
  ##xcalib -invert -alter
  #xcalib -alter -invert
  /srv/opt/bin/xrandr-invert-colors.bin
}

# ***

prepare_to_build() {
  rmdir "${KILL_DIR}"
  say
  say "See you on the other side!"
  say
  touch "${OUT_FILE}"
  truncate -s 0 "${OUT_FILE}"
  say '' true
}

# ***

init_it_() {
  announcement "INIT IT"
}

init_it() {
  init_it_
}

lock_it_() {
  announcement "LOCK IT"

  # Get the lock.
  lock_or_die

  say "┗━ PID ‘$$’ (us!) has the lock"
  echo "$$" > "${PID_FILE}"
  echo "kill -s SIGUSR1 $$" > "${KILL_BIN}"
  chmod 755 "${KILL_BIN}"
}

lock_it() {
  lock_it_
}

lang_it_() {
  announcement "LANG IT"
}

lang_it() {
 lang_it_
}

build_it_() {
  announcement "BUILD IT"
}

build_it() {
  build_it_
}

lint_it_() {
  announcement "LINT IT"
}

lint_it() {
  lint_it_
}

test_it_() {
  announcement "TEST IT"
}

test_it() {
  test_it_
}

ctags_it_() {
  announcement "CTAGS IT"
}

ctags_it() {
  ctags_it_
}

# ***

drop_locks() {
  # FIXME/2017-10-03: Riddle me this: is a two-fer rmdir atomic like a 1 dir?
  rmdir "${LOCK_DIR}" "${KILL_DIR}"
}

remove_pid_files() {
  /bin/rm "${PID_FILE}"
  /bin/rm "${KILL_BIN}"
}

# ***

main() {
  source_plugin

  assign_globals

  if [[ "${PARENT_COMMAND}" != 'bash' ]]; then
    # We're called on both save, and on simple buffer enter.
    if [[ ${DUBS_TRUST_ME_ON_SAVE} != 1 ]]; then
      # We've got nothing to do on simple buffer enter...
      verbose_announcement "DUBS_TRUST_ME_ON_FILE: ${DUBS_TRUST_ME_ON_FILE}"
      verbose "Nothing to do on open"
      exit 1
    fi
  # else, being invoked deliberately by user via Bash CLI, so run!
  fi

  trap death SIGUSR1

  say
  say "              󷎟  󲁹  󲁭  󲁨  🚷  🐧  🐨  🐫  🐬  🐰  🐳  🐎 "
  announcement "  ❎ ❎ ❎ ❎ ❎ ❎ ❎ ❎ ❎ ❎ ❎ ❎ ❎ ❎ ❎   ❎ ❎ ❎ ❎ ❎ ❎ ❎ ❎ ❎ ❎ ❎ ❎ ❎ ❎ ❎ ❎"

  init_it

  lock_it

  # Ctags builder. Before the build, if BUILD_DELAY_SECS is a while.
  if [[ ${BUILD_DELAY_SECS} -gt 0 ]]; then
    ctags_it
  fi

  announcement "WAITING ON BUILD" "Countdown: ${BUILD_DELAY_SECS} secs..."

  # Defer the build!
  drop_locks
  # The trap on SIGUSR1 only fires when this script is active and
  # not blocked on a subshell. And sleep is it's own command, so we
  # background it.
  sleep ${BUILD_DELAY_SECS} &
  # Fortunately, we can use the Bash wait command, which does not
  # block signals.
  # Get the process ID of the last command.
  #   LPID=$!
  #   wait ${LPID}
  # Or just wait.
  wait

  say "READY TO BUILD..."
  say

  # Get the lock.
  lock_kill_or_die

  say "┗━ BUILDING!"

  if ${TESTING:-false}; then
    drop_locks
    remove_pid_files
    say "DONE! (ONLY TESTING)"
    exit
  fi

  prepare_to_build

  time_0=$(home_fries_nanos_now)
  announcement "WARMING UP"
  say "Build started at $(date '+%Y-%m-%d_%H-%M-%S')"
  verbose
  verbose "- Cwd: $(pwd)"

  lang_it

  build_it
  function test_concurrency() {
    for i in $(seq 1 5); do build_it; done
  }
  # DEVs: Wanna test CTRL-C more easily by keeping the script alive longer?
  #       Then uncomment this.
  #test_concurrency
  # A fancy, colorful "Built!" message, meant to be easy to spot.
  say "${FG_LIME}$(repeat_char '>' 67)${FONT_NORM}"
  say "${FG_LIME}~ ¡BUILT! $(repeat_char '|' 47) ¡BUILT! ~${FONT_NORM}"
  say "${FG_LIME}$(repeat_char '<' 67) ${FONT_NORM}"

  # Ctags builder. After the build, if there is no BUILD_DELAY_SECS.
  if [[ ${BUILD_DELAY_SECS} -le 0 ]]; then
    ctags_it
  fi

  lint_it

  # Unit tests.
  test_it

  time_n=$(home_fries_nanos_now)
  time_elapsed=$(echo "$time_n - $time_0" | bc -l)
  announcement "DONE!"
  say "Build finished at $(date '+%H:%M:%S') on $(date '+%Y-%m-%d') in ${time_elapsed} secs."
  say
  say "$(bg_skyblue)$(fg_mediumgrey)> $(repeat_char '═' 63) <$(attr_reset)"
  say

  trap - SIGUSR1

  remove_pid_files
  rmdir "${LOCK_DIR}"
}

main "$@"

