#!/bin/bash
# Run one command on the tablet's USB-serial shell; see n9sh.py.
# usage: tools/n9sh.sh '<command>' [max-seconds]
exec python3 -I "$(dirname "$0")/n9sh.py" "$@"
