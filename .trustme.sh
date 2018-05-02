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
  # If the /user/home/.fries/lib path is on $PATH, you can just source it.
  if ! source "${source_path}" &> /dev/null; then
    # But if it's not on $PATH, see if this script is a symlink, and if so,
    # see if the util file is part of this file's owning repo.
    if [[ -h "${BASH_SOURCE[0]}" ]]; then
      source_path="$(dirname $(readlink -f ${BASH_SOURCE[0]}))/${home_fries_util}"
    fi
    if ! source "${source_path}" &> /dev/null; then
      >&2 echo "Unable to find and source ${home_fries_util}. You're missing out!"
    fi
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
}

assign_globals() {
  assign_globals_
}

# ***

say() {
  FORCE_ECHO=${2:-false}
  # Restrict newlines to no more than 2 in a row.
  TRUSTME_SAID_NEWLINE=${TRUSTME_SAID_NEWLINE:-false}
  if ${FORCE_ECHO} || ! ${TRUSTME_SAID_NEWLINE} || [[ ("$1" != "") ]]; then
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
  say "Desperately Seeking Lock on $(date)..."
  [[ "$1" == true ]] && local AFTER_WAIT=true || local AFTER_WAIT=false
  local build_it=false
  # mkdir is atomic. Isn't that nice.
  if $(mkdir "${LOCK_DIR}" 2> /dev/null); then
    say "- Scored the lock!"
    say
    kill_other ${AFTER_WAIT} true
  elif [[ -d "${LOCK_DIR}" ]]; then
    if ! ${AFTER_WAIT}; then
      # There's another script waiting to build, or a build going on.
      # Kill it if you can.
      say "Could not lock, but can still kill!"
      kill_other ${AFTER_WAIT} false
    else
      # This script got the lock earlier, released it, and slept, and now
      # it cannot get the lock...
      say "i waited for you but you locked me out"
      exit
    fi
  else
    announcement "WARNING: could not mkdir ‘${LOCK_DIR}’ and it does not exist, later!"
    exit
  fi
}

kill_other() {
  [[ "$1" == true ]] && local AFTER_WAIT=true || local AFTER_WAIT=false
  [[ "$2" == true ]] && local OUR_LOCK=true || local OUR_LOCK=false
  if $(mkdir "${KILL_DIR}" 2> /dev/null); then
    if [[ -f "${PID_FILE}" ]]; then
      local build_pid=$(cat "${PID_FILE}")
      if ${AFTER_WAIT}; then
        if [[ "$$" != "${build_pid}" ]]; then
          echo "Panic, jerks! The build_pid is not our PID! ${build_pid} != $$"
          exit
        fi
      elif [[ "${build_pid}" != '' ]]; then
        #say "Locked the kill directory! time for mischiefs"
        say "Killing ‘${build_pid}’"
        # Process, your time has come.
        kill -s SIGUSR1 "${build_pid}" &>> "${OUT_FILE}"
        if [[ $? -ne 0 ]]; then
          say "Kill failed! On PID ‘${build_pid}’"
          # So, what happened? Did the build complete?
          # Should we just move along? Probably...
          # Get the name of the process. If it still exists, die.
          if [[ $(ps -p "${build_pid}" -o comm=) != '' ]]; then
            say "Said process still exists!"
            exit
          fi
          # The process is a ghost.
          remove_pid_files
        else
          # Wait for the other trustme to clean up.
          WAIT_PATIENCE=10
          sleep 0.1
          while [[ -f "${PID_FILE}" ]]; do
            say "Waiting on PID ${build_pid} to cleanup..."
            sleep 0.5
            WAIT_PATIENCE=$((WAIT_PATIENCE - 1))
            [[ ${WAIT_PATIENCE} -eq 0 ]] && echo "Done waiting!" && exit
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
  else
    say "Someone else has the kill lock. We're boned!"
    exit
  fi
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
  duration=${1:-0.075}
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

  # We're called on both save, and on simple buffer enter.
  if [[ ${DUBS_TRUST_ME_ON_SAVE} != 1 ]]; then
    # We've got nothing to do on simple buffer enter...
    verbose_announcement "DUBS_TRUST_ME_ON_FILE: ${DUBS_TRUST_ME_ON_FILE}"
    verbose "Nothing to do on open"
    exit 1
  fi

  trap death SIGUSR1

  say
  say "              󷎟  󲁹  󲁭  󲁨  🚷  🐧  🐨  🐫  🐬  🐰  🐳  🐎 "
  announcement "  ❎ ❎ ❎ ❎ ❎ ❎ ❎ ❎ ❎ ❎ ❎ ❎ ❎ ❎ ❎   ❎ ❎ ❎ ❎ ❎ ❎ ❎ ❎ ❎ ❎ ❎ ❎ ❎ ❎ ❎ ❎"

  init_it

  # Get the lock.
  lock_or_die

  say "- ‘$$’ has the lock"
  echo "$$" > "${PID_FILE}"
  echo "kill -s SIGUSR1 $$" > "${KILL_BIN}"
  chmod 755 "${KILL_BIN}"

  # Ctags builder. Before the build. In case BUILD_DELAY_SECS is a while.
  ctags_it

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

  say "BUILDING!"

  if ${TESTING:-false}; then
    drop_locks
    remove_pid_files
    say "DONE! (ONLY TESTING)"
    exit
  fi

  prepare_to_build

  time_0=$(date +%s.%N)
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
  say "${FG_LIME}$(repeat_char '|' 67) BUILT!${FONT_NORM}"
  say "${FG_LIME}$(repeat_char '<' 67) ${FONT_NORM}"

  lint_it

  # Unit tests.
  test_it

  time_n=$(date +%s.%N)
  time_elapsed=$(echo "$time_n - $time_0" | bc -l)
  announcement "DONE!"
  say "Build finished at $(date '+%H:%M:%S') on $(date '+%Y-%m-%d') in ${time_elapsed} secs."

  trap - SIGUSR1

  remove_pid_files
  rmdir "${LOCK_DIR}"
}

main "$@"

