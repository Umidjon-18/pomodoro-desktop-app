#!/bin/sh
# Removes the Pomodoro hosts helper and its sudoers rule, clearing any active
# block from /etc/hosts first. Run via `do shell script ... with administrator privileges`.

set -eu
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH
umask 022

HELPER=/usr/local/libexec/pomodoro-hosts
SUDOERS_FILE=/etc/sudoers.d/pomodoro

if [ "$(id -u)" -ne 0 ]; then
    printf 'uninstall-helper: must be run as root\n' >&2
    exit 1
fi

if [ -x "$HELPER" ]; then
    "$HELPER" clear || printf 'uninstall-helper: warning: could not clear the hosts block\n' >&2
fi

rm -f -- "$SUDOERS_FILE"
rm -f -- "$HELPER"

echo 'Removed the Pomodoro helper and sudoers rule'
