#!/bin/bash
#
# rotatesBackups - Parametric backup rotator
# 
# Part of 
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

# Set this to false for production use
TESTING=false

_echo() {
   if $TESTING; then
      for i in "$@"; do echo -n "$i" ; done
	  echo ""
   fi
}

# Parse command line
if [ $# -lt 2 ]; then
   exit -1
fi

# $1 = root folder
# $2 = period
# $3 = number of old backups to keep (optional, defaults to 5)
ROOT_FOLDER=${1}
PERIOD_FOLDER=${2}
if [ -z ${3} ]; then
   BACKLOG=5
else
   BACKLOG=${3}
fi

# Create the folder structure in case is not in place yet
BASE_FOLDER=${ROOT_FOLDER}/${PERIOD_FOLDER}
mkdir -p ${BASE_FOLDER}
_echo "BASE FOLDER: " ${BASE_FOLDER}

# Hard link files from the latest backup into a new 
# folder with the current timestamp as the name.
LATEST=${ROOT_FOLDER}/.latest
TSTAMP=`date +\%Y\%m\%d\%H\%M.\%S`
NEW_FOLDER=${BASE_FOLDER}/"${TSTAMP:0:4}-${TSTAMP:4:2}-${TSTAMP:6:2}-${TSTAMP:8:4}${TSTAMP:13:2}"
_echo "NEW_FOLDER: " ${NEW_FOLDER}
if [ -d `readlink -mn ${LATEST}` ]; then 
   _echo "cp -al `readlink -mn ${LATEST}` `readlink -mn ${NEW_FOLDER}`"
   cp -al `readlink -mn ${LATEST}` `readlink -mn ${NEW_FOLDER}`
else
   mkdir -p `readlink -mn ${NEW_FOLDER}`
fi

# Now purge the oldest backups to keep the desired history
while [ ${BACKLOG} -lt `ls -l ${BASE_FOLDER} | grep ^d | wc -l` ]
do
   # Find the oldest backup and remove it
   # Some directories might not be writeable so need to chmod them
   OLDEST=`ls ${BASE_FOLDER} -1t | tail -1`
   find ${BASE_FOLDER}/${OLDEST} -type d ! -perm -u+w -exec chmod u+w {} +
   if ! rm -Rf ${BASE_FOLDER}/${OLDEST} >& /dev/null
   then
      exit 1
   fi
done

# Relink the latest folder
rm -f ${LATEST}
ln -s `readlink -mn ${NEW_FOLDER}` ${LATEST}

# Touch symlink.
touch -t ${TSTAMP} ${LATEST}

echo `readlink -mn ${NEW_FOLDER}` ${TSTAMP}

