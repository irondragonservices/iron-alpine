#!/usr/bin/env sh

# fail if a command fails
set -e
set -o pipefail

# Re-remove the applets the base image already deleted. Every `apk add` in a
# derived image fires the busybox trigger, which recreates the full applet
# symlink farm — su, hexdump, od and the rest come back, and the hardening the
# base image did is silently undone by the first package anyone installs.
# This runs last, so it is the only place that can be sure nothing follows it.
find /bin /etc /lib /sbin /usr -xdev \( \
  -iname hexdump -o \
  -iname chgrp -o \
  -iname ln -o \
  -iname od -o \
  -iname strings -o \
  -iname su -o \
  -iname sudo \
  \) -delete

# Anything a package installed setuid or setgid is a privilege boundary the
# base image did not agree to.
find /bin /etc /lib /sbin /usr -xdev -type f -a \( -perm +4000 -o -perm +2000 \) -delete

# remove apk package manager
find / -type f -iname '*apk*' -xdev -delete
find / -type d -iname '*apk*' -print0 -xdev | xargs -0 rm -r --

# set rx to all directories, except data directory/
find "$APP_DIR" -type d -exec chmod 500 {} +

# set r to all files
find "$APP_DIR" -type f -exec chmod 400 {} +

# the two directories the app is allowed to write to
chmod -R u=rwx "$DATA_DIR/"
chmod -R u=rwx "$TMP_DIR/"

# chown all app files
chown $APP_USER:$APP_USER -R $APP_DIR $DATA_DIR $TMP_DIR

# remove chown after use (links & binaries)
find / \( -type f -o -type l \) -iname 'chown' -xdev -delete

# finally remove this file
rm "$0"
