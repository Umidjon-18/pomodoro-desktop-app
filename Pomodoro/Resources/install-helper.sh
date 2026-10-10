#!/bin/sh
# Installs the Pomodoro hosts helper and a sudoers rule that lets <username> run
# exactly that helper as root without a password.
#
#   install-helper.sh <username> <path-to-bundled-pomodoro-hosts>
#
# Run by the app via `do shell script ... with administrator privileges`.

set -eu
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH
LC_ALL=C
export LC_ALL
umask 022

HELPER_DIR=/usr/local/libexec
HELPER=$HELPER_DIR/pomodoro-hosts
SUDOERS_DIR=/etc/sudoers.d
SUDOERS_FILE=$SUDOERS_DIR/pomodoro

die() {
    printf 'install-helper: %s\n' "$1" >&2
    exit 1
}

[ "$(id -u)" -eq 0 ] || die 'must be run as root'
[ $# -eq 2 ] || die 'usage: install-helper.sh <username> <path-to-pomodoro-hosts>'

user=$1
source=$2

case $user in
    '' | *[!a-z0-9_.-]* | [!a-z_]*) die "invalid username: $user" ;;
esac
id -u "$user" >/dev/null 2>&1 || die "no such user: $user"
[ "$(id -u "$user")" -ne 0 ] || die 'refusing to install for root'

[ -f "$source" ] && [ ! -L "$source" ] || die "helper source not found: $source"

# Without the includedir directive the rule would be silently ignored. Never
# edit /etc/sudoers itself; ask the user to restore the macOS default instead.
grep -Eq '^[#@]includedir[[:space:]]+(/private)?/etc/sudoers\.d/?[[:space:]]*$' /etc/sudoers \
    || die '/etc/sudoers has no "#includedir /private/etc/sudoers.d" line; restore the macOS default and try again'

# A root-run helper is only as safe as the directories leading to it: any of them
# being writable by a non-root user would allow swapping the helper.
secure_dir() {
    owner=$(stat -f '%u' "$1") || die "cannot stat $1"
    perms=$(stat -f '%Sp' "$1") || die "cannot stat $1"
    [ "$owner" -eq 0 ] || die "$1 is not owned by root; refusing to install a root helper there"
    # perms looks like "drwxr-xr-x"; the 6th and 9th characters are group/other write.
    case $perms in
        ?????w* | ????????w*) die "$1 is group/world-writable; refusing to install a root helper there" ;;
    esac
}
secure_dir /usr
secure_dir /usr/local

install -d -o root -g wheel -m 755 "$HELPER_DIR" || die "cannot create $HELPER_DIR"
chown root:wheel "$HELPER_DIR"
chmod 755 "$HELPER_DIR"
secure_dir "$HELPER_DIR"

install -o root -g wheel -m 755 "$source" "$HELPER" || die "cannot install $HELPER"

install -d -o root -g wheel -m 755 "$SUDOERS_DIR" || die "cannot create $SUDOERS_DIR"

# sudo ignores files in sudoers.d whose names contain a '.', so the temp file is
# inert until it has been validated and renamed into place.
tmp=$(mktemp "$SUDOERS_DIR/.pomodoro.XXXXXX") || die 'cannot create temporary sudoers file'
trap 'rm -f -- "$tmp"' EXIT HUP INT TERM

printf '%s ALL=(root) NOPASSWD: %s\n' "$user" "$HELPER" > "$tmp"
chown root:wheel "$tmp"
chmod 440 "$tmp"
visudo -cf "$tmp" >/dev/null || die 'generated sudoers rule failed validation'
mv -f -- "$tmp" "$SUDOERS_FILE" || die "cannot install $SUDOERS_FILE"
trap - EXIT HUP INT TERM

echo "Installed $HELPER and $SUDOERS_FILE for $user"
