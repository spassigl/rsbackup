#!/bin/bash
# -------------------------------------------------------
# rsbackup - a simple shell script to automate backups
#            with rsync
# v 1.0
#
# Developed and tested on Linux Fedora 24 and MacOSX 
# Copyright Stefano Passiglia, 2016
# stefano.passiglia@gmail.com
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# Basic usage:
#   rsbackup.sh -c computername -p period -k keep
#
# E.g.:
#   rsbackup.sh -c fedora-home -p daily -k 7
#
# Default keep is 5.
# It will backup the whole disk from "/"
# Files to be excluded can be added to /etc/opt/rsbackup/excludes file.
#
# Backups are rotated at the destination side when this script is launched, and the oldest one deleted.
# Deleted files from source directories are deleted at the destination directory too.
#
# Server Configuration:
# ------------------------
# The script uses ssh remote command to rotate backups at the server end.
# On the backup server, a user name "rsbackup" needs to be created.
# 
# You can change that in the configuration section below.
# 
# Release notes:
# v 1.0 - June 2016
#   initial release
#

# ------------- Configuration --------------------------

# Change this to the actual rsync backup server
BACKUP_SERVER=

# BACKUP USER ID
BACKUP_LOGIN_SSH=

# Set this to true if you allow users to specify their
# own exclude files, false otherwise
ALLOW_USER_EXCLUDE_FILE=true

# Set this to 1 once configured properly
CONFIGURED=0

# ------------- Configuration end ------------------------

# ========================================================
#     YOU SHOULD NOT CHANGE ANYTHING AFTER THIS POINT
# ========================================================

# ------------------------------------------------------
# System-dependent aliases

OSTYPE=`uname`

if [ "${OSTYPE}" != "Linux" ] && [ "${OSTYPE}" != "Darwin" ]; then
   echo "Only Linux or OSX are supported. Exiting."
   exit -1
fi

# Users home dir
if [ "${OSTYPE}" == "Linux" ]; then
   USERS_HOME=/home
else
   USERS_HOME=/Users
fi

# -------------------------------------------------------

# What to backup. DO NOT REMOVE the trailing slash!
BACKUP_ROOT=/

# This is a symlink to the o.s. specific exclude file
# i.e. either excludes-linux or excludes-osx
RSYNC_EXCLUDES=/etc/opt/rsbackup/excludes

# Users can specify their own excludes in ~/.rsbackup-excludes
RSYNC_USER_EXCLUDES=.rsbackup-excludes

# Setup directory
SETUP_DIR=/opt/rsbackup

# Backup rotation script
ROTATION_SCRIPT=rotateBackups.sh

# Log directoy
LOG_DIR=/var/log/rsbackup

# If this file exists, another backup is still running
BACKUP_FLAG=/tmp/rsbackup-running

# ------------- Safety checks ---------------------------

# Make sure script has been configured
if (( $CONFIGURED != 1 )); then
   echo "Script needs configuration. Aborting..."
   exit 1
fi;

# Exit if another backup is still running.
if [ -f ${BACKUP_FLAG} ]; then 
   echo "Another backup is still running. Exiting…" 
   exit 1 
fi;

# Make sure we are running as root
if (( `id -u` != 0 )); then 
   echo "Backup must be run as root. Exiting…"
   exit 1
fi;

#
# Little helper functions
#
echo_red() {
   printf "\e[31m%s\e[0m\n" "$1"
}

echo_green() {
   printf "\e[32m%s\e[0m\n" "$1"
}


# ------------- Usage and cleanup ..-------------------

usage() {
   echo "rsbackup.sh version 1.0 June 2016" >&2
   echo "Usage: rsbackup.sh [-c computername] -p period [-k keep] [-v verboselevel] [--setup|--test|--dry-run] [-h]" >&2
   echo "   -c computername Computer name to identify backups" >&2
   echo "                   If not given, /etc/hostname will be used." >&2
   echo "   -p period       Gives a recognizable prefix to the" >&2
   echo "                   backup - e.g. weekly, daily, etc" >&2
   echo "                   Do not use quotes." >&2
   echo "   -k keep         How many old backups to keep for the" >&2
   echo "                   specified period." >&2
   echo "   -v verboselevel Verbosity level, between 1 and 3 (highest)" >&2
   echo "                   Defaults to 1." >&2
   echo "   --setup         Used to set up the environment for the first use." >&2
   echo "                   Mutually exclusive with --test">&2
   echo "   --test-env      Used to test the enviromnent and if it's setup properly and ready to run backups.">&2
   echo "                   Mutually exclusive with --setup">&2
   echo "   -h              Shows this help." >&2
   echo "" >&2
   echo "rsbackup comes with ABSOLUTELY NO WARRANTY.  This is free software, and you \
are welcome to redistribute it under certain conditions.  See the GNU \
General Public Licence for details." >&2
}

cleanup() {

   rm -f ${BACKUP_FLAG}

}

#
# This function tests the configuration
#
test-config() {
   local _needsetup=false
   local _sshreturn

   echo "Testing configuration as `whoami`"

   echo "System: ${OSTYPE}"

   echo -n "Testing setup directory..."
   if [ -d  ${SETUP_DIR} ]; then echo "OK"; else echo "FAIL"; _needsetup=true; fi

   echo -n "Testing log directory..."
   if [ -d  ${LOG_DIR} ]; then echo "OK"; else echo "FAIL"; _needsetup=true; fi

   echo -n "Testing system exclude file..." 
   if [ -f ${RSYNC_EXCLUDES} ]; then echo "OK"; else echo "FAIL"; _needsetup=true; fi

   echo "Remote connection parameters:"
   echo "   User: ${BACKUP_LOGIN_SSH}"
   echo "   Server: ${BACKUP_SERVER}"
   echo -n "Testing if there's a working ssh configuration..."

   _sshreturn="`ssh -o BatchMode=yes ${BACKUP_LOGIN_SSH}@${BACKUP_SERVER} "echo test" 2>&1`"
   case $_sshreturn in
      "test")
      echo "OK" 
      ;;
      "Permission"*)
      echo "FAIL: you need to setup ssh keys or use a different account."
      _needsetup=true
      ;;
      *)
      echo "FAIL: Unknown response from the server ($_sshreturn). Please check ssh configuration."
      _needsetup=true
      ;;
   esac

   echo "Default configuration values:"
   echo "   backup root: ${BACKUP_ROOT}"
   echo "   backup history: ${KEEP} backups"
   echo "   computer name: ${COMPUTER_NAME}"
   echo "   allow user exclude file: ${ALLOW_USER_EXCLUDE_FILE}"
   echo "   rsync options: ${RSOPTS}"
   echo ""

   if $_needsetup; then echo "Configuration is not correct, please run the script with the --setup option"; fi
}


#
# Setup function
#
setup-env() {
   echo "------------------------------------------------------------------------"
   echo "Setting up the environment..."

# 1 -----------------------------------------------------
# Create the system exclude file if it's not there yet

   if [ ! -f ${RSYNC_EXCLUDES} ]; then
      echo "Creating the system exclude file: ${RSYNC_EXCLUDES}"
      mkdir -p ${RSYNC_EXCLUDES%/*}
      if [ "${OSTYPE}" == "Linux" ]; then
         cat <<EOF > ${RSYNC_EXCLUDES}-linux
/dev
/sys
/tmp/*
/proc
/run
/mnt/*
/media/*
/lost+found
/home/*/.cache/*
/home/*/.thumbnails/*
/home/*/.local/share/Trash/*
/var/log/journal/*
/var/log/rsbackup/*
/var/cache/PackageKit/*

EOF
         ln -s ${RSYNC_EXCLUDES}-linux ${RSYNC_EXCLUDES}
      elif [ "${OSTYPE}" == "Darwin" ]; then
         cat <<EOF > ${RSYNC_EXCLUDES}-darwin
/var/log/rsbackup.log
# From /System/Library/CoreServices/backupd.bundle/Contents/Resources/StdExclusions.plist
# as used by Time Machine
/Volumes/*
/Network/*
/automount/*
/.vol/*
/tmp/*
/cores/*
/private/tmp/*
/private/Network/*
/private/tftpboot/*
/private/var/automount/*
/private/var/run/*
/private/var/tmp/*
/private/var/vm/*
/private/var/db/dhcpclient/*
/private/var/db/fseventsd/*
/Library/Caches/*
/Library/Logs/*
/System/Library/Caches/*
/System/Library/Extensions/Caches/*
/.Spotlight-V100
/.Trashes
/.fseventsd
/.hotfiles.btree
/Backups.backupdb
"/Desktop DB"
"/Desktop DF"
/Network/Servers
"/Previous Systems"
/Users/Guest
/dev
/home
/net
/private/var/db/Spotlight
/private/var/db/Spotlight-V100
"/Users/*/Library/Application Support/MobileSync"
"/Users/*/Library/Application Support/SyncServices"
/Users/*/Library/Caches
/Users/*/Library/Logs
"/Users/*/Library/Mail/Envelope Index"
/Users/*/Library/Mail/AvailableFeeds
/Users/*/Library/Mirrors
/Users/*/Library/PubSub/Database
/Users/*/Library/PubSub/Downloads
/Users/*/Library/PubSub/Feeds
/Users/*/Library/Safari/Icons.db
/Users/*/Library/Safari/HistoryIndex.sk
# Others as documented here: 
# https://bombich.com/kb/ccc4/some-files-and-folders-are-automatically-excluded-from-backup-task
.DocumentRevisions-V100*
.Spotlight-V100
/.fseventsd
/.hotfiles.btree
/private/var/db/systemstats
/private/var/db/dyld/dyld_*
/System/Library/Caches/com.apple.bootstamps/*
/System/Library/Caches/com.apple.corestorage/*
/System/Library/Caches/com.apple.kext.caches/*
/.quota.user
/.quota.group
/private/var/folders/zz/*
/private/var/vm/*
/private/tmp/*
/cores
.Trash
.Trashes
/Backups.backupdb
/.MobileBackups
/.MobileBackups.trash
Library/Mobile Documents.*
.webtmp
/private/tmp/kacta.txt
/private/tmp/kactd.txt
/Library/Caches/CrashPlan
/PGPWDE01
/PGPWDE02
/.bzvol
/private/var/spool/qmaster
"Saved Application State"
Library/Preferences/ByHost/com.apple.loginwindow*
EOF
         ln -s ${RSYNC_EXCLUDES}-darwin ${RSYNC_EXCLUDES}
      fi
   fi

# 1 -----------------------------------------------------
# 2 -----------------------------------------------------
# Create log dir
  echo "Creating the log directory: ${LOG_DIR}"
  mkdir -p ${LOG_DIR}

# 2 -----------------------------------------------------
# 3 -----------------------------------------------------
# Copy this and the rotateBackup scripts in their directory
  echo "Installing the scripts into ${SETUP_DIR}"
  mkdir -p ${SETUP_DIR}
  cp ${0} ${SETUP_DIR}
  cp ${0%/*}/${ROTATION_SCRIPT} ${SETUP_DIR}

# 3 -----------------------------------------------------

   echo "...done"
   echo "------------------------------------------------------------------------"
}
# End of setup-env()


# Rsync command line parameters
RSOPTS="-a -v -P -S -z --hard-links --sparse --numeric-ids --perms --delete --stats -i --human-readable"
if [ "${OSTYPE}" == "Darwin" ]; then
#   RSOPTS="${RSOPTS} -E"
   RSOPTS="${RSOPTS}"
elif [ "${OSTYPE}" == "Linux" ]; then
   RSOPTS="${RSOPTS} -X"
fi

# ------------- Command line parsing -------------------

# Default values
if [ "${OSTYPE}" == "Darwin" ]; then
   COMPUTER_NAME=`/bin/hostname -s`
elif [ "${OSTYPE}" == "Linux" ]; then
   COMPUTER_NAME=`/usr/bin/hostname -s`
fi
KEEP=5
VERBOSITY=3
DOSETUP=false
DOTEST=false

# This script need be run as root
if (( $# == 0 )); then
  usage;
  exit 1; 
fi

# Parse parameters
while getopts "c:p:k:v:h-:" opt; do
  case $opt in
    c)
      COMPUTER_NAME=$OPTARG
      ;;
    p)
      PERIOD=$OPTARG
      ;;
    k)
      KEEP=$OPTARG
      ;;
    v)
      (( VERBOSITY = $OPTARG>0 ? $OPTARG : 1 ))
      ;;
    h)
      usage
      exit 1
      ;;
    -)
      case "${OPTARG}" in
         setup)
            DOSETUP=true 
            DOTEST=false
            OPTIND=$(( $OPTIND + 1 ))
            ;;
         test-env)
            DOTEST=true 
            DOSETUP=false
            OPTIND=$(( $OPTIND + 1 ))
            ;;
         *)
            if [ "$OPTERR" = 1 ] && [ "${optspec:0:1}" != ":" ]; then
              echo "Unknown option --${OPTARG}" >&2
            fi
            usage
            exit 1
            ;;
       esac
       ;;
    \?)
      usage
      exit 1
      ;;
    :)
      usage
      exit 1
      ;;
   esac
done

if ${DOTEST}; then
   test-config
   exit 1
fi

# Setup of the environment
if ${DOSETUP}; 
then
   setup-env
   exit
fi

if [[ ! ${DOSETUP} ]] && [[ -z $PERIOD ]];
then
   echo "Missing period specification."
   usage
   cleanup
   exit 1
fi

# -------------------------------------------------------

if [ ! -f ${RSYNC_EXCLUDES} ]; 
then
   echo "It appears some configuration files are missing. Did you run the script"
   echo "with the --setup option one first time?"
   echo "Run it again with the -h option to get help."
   echo "Exiting."
fi

if [ $VERBOSITY -gt 2 ]; 
then
   echo "------------------------------------------------------------------------"
   echo "`date +%H:%M:%S` Contents of the system exclude file:"
   cat ${RSYNC_EXCLUDES}
   echo "------------------------------------------------------------------------"
fi

echo "========================================================================"
echo "`date +"%Y.%m.%d - %H:%M:%S"`"
echo "Backup starting on" ${BACKUP_LOGIN_SSH}@${BACKUP_SERVER}
echo "   computer:" ${COMPUTER_NAME}
echo "   period:" ${PERIOD}
echo "   keeping:" ${KEEP} "backups"
echo "========================================================================"


# Create the flag file now that the backup is starting
touch ${BACKUP_FLAG}

# Time to rotate snapshots
echo "`date +%H:%M:%S` Rotating backups..."

# Run remote rotation command. This will return the link to the 
# folder where to store the latest rsync in and the timestamp in touch format
# _res = "folder timestamp" where timestamp is in YYYYMMDDHHMM.SS format
_res=`cat ${0%/*}/rotateBackups.sh | ssh ${BACKUP_LOGIN_SSH}@${BACKUP_SERVER} "bash -s" ${COMPUTER_NAME} ${PERIOD} ${KEEP}`
BACKUP_FOLDER=${_res:0:${#_res}-16}
TSTAMP=${_res: -15}
if [ -z ${BACKUP_FOLDER} ];
then
   echo "Something went wrong during backup rotation. Exiting" 
   cleanup 
   exit 1
fi
echo "`date +%H:%M:%S` ...done."

if [ $VERBOSITY -gt 1 ]; 
then
   echo "`date +%H:%M:%S` Will backup to ${BACKUP_LOGIN_SSH}@${BACKUP_SERVER}:${BACKUP_FOLDER}"
fi

# Prepare the rsync filter rule:
# - first one is a merge rule (.) to add the overall exclude patterns. It uses the /
#   modifier so that the rule is matched against the absolute pathname of the exclude file
# - second one is a dir-merge rule (:) to include a per-directory (user home) merge-file
#   with user patterns
# - both rules are at the sending side (s) and of an exclude type
FILTERS[0]=".s-/ ${RSYNC_EXCLUDES}"
if $ALLOW_USER_EXCLUDE_FILE; 
then
   FILTERS[1]=":s- ${RSYNC_USER_EXCLUDES}"
fi

if [ $VERBOSITY -gt 2 ]; 
then
   echo "`date +%H:%M:%S` Running rsync with options: ${RSOPTS}"
fi

# Time to rsync now.
echo "`date +%H:%M:%S` Initiating rsync..."

# ---------------------------------------------------------------------

   rsync	${RSOPTS}						\
                --filter="${FILTERS[0]}"				\
                --filter="${FILTERS[1]}"				\
                -e ssh							\
		${BACKUP_ROOT}						\
		${BACKUP_LOGIN_SSH}@${BACKUP_SERVER}:${BACKUP_FOLDER}

# ---------------------------------------------------------------------

echo "`date +%H:%M:%S` ...rsync finished."

# Touch the new backup folder
echo "`date +%H:%M:%S` Touching the new backup folder..."
ssh ${BACKUP_LOGIN_SSH}@${BACKUP_SERVER} "touch -t ${TSTAMP} ${BACKUP_FOLDER}"

echo "`date +%H:%M:%S` Final cleanup..."

# Remove the flag file and other things
cleanup

echo "`date +%H:%M:%S` ...done."

# That's it folks
echo "`date +%H:%M:%S` backup ended."
echo "========================================================================"

exit 0
