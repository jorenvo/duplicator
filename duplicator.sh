#!/usr/bin/env bash
# Copyright (c) 2017 Joren Van Onder
#
# Permission is hereby granted, free of charge, to any person
# obtaining a copy of this software and associated documentation files
# (the "Software"), to deal in the Software without restriction,
# including without limitation the rights to use, copy, modify, merge,
# publish, distribute, sublicense, and/or sell copies of the Software,
# and to permit persons to whom the Software is furnished to do so,
# subject to the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
# BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
# ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
# CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

set -eu

if [[ -z "$(tty | grep 'tty1')" ]]; then
    exit
fi

# edit these variables for new setups
DISK_TO_DUPLICATE="/dev/sda"
BACKUP_DIR="/backup"

echo '______             _ _           _             
|  _  \           | (_)         | |            
| | | |_   _ _ __ | |_  ___ __ _| |_ ___  _ __ 
| | | | | | | '"'"'_ \| | |/ __/ _` | __/ _ \| '"'"'__|
| |/ /| |_| | |_) | | | (_| (_| | || (_) | |   
|___/  \__,_| .__/|_|_|\___\__,_|\__\___/|_|   
            | |                                
            |_|                                
'

START_DELAY_S=5

if mount | grep "${DISK_TO_DUPLICATE}"; then
    echo 'Not overwriting self'
    exit
fi

countdown_prompt () {
    local REMAINING_S="${1}"
    local MESSAGE="${2}"
    for i in $(seq 1 "${REMAINING_S}"); do
        echo -ne "\r${MESSAGE} in ${REMAINING_S} seconds..."
        sleep 1
        let --REMAINING_S || true # let returns 1 when expr evaluates to 0
    done
    echo ''
}

start_prompt () {
    echo "Existing backups:"
    ls -lh "${BACKUP_DIR}" | tail -n +2 # skip 'Total...'
    countdown_prompt "${START_DELAY_S}" "Will duplicate ${DISK_TO_DUPLICATE}"
}

calculate_available_space () {
    AVAILABLE_BACKUP_SPACE_B=$(($(df --output='avail' "${BACKUP_DIR}" | tail -n 1 | sed 's/ //g')*1024))
    echo "Space available: ${AVAILABLE_BACKUP_SPACE_B}"
}

start_prompt

DISK_TO_DUPLICATE_SIZE_B=$(($(sfdisk -u M -s "${DISK_TO_DUPLICATE}")*1024))
echo "Space needed: ${DISK_TO_DUPLICATE_SIZE_B}"

calculate_available_space

while [[ ${AVAILABLE_BACKUP_SPACE_B} -lt ${DISK_TO_DUPLICATE_SIZE_B} ]]; do
    echo 'Not enough space available'
    # TODO: attempt to use null as delimiter, \x0 used by sed is not portable however
    OLDEST_FILE="$(find "${BACKUP_DIR}" -maxdepth 1 -type f -printf '%T@ %f\0' | sort -zn | sed 's/\x0.*//' | sed 's/.* //')"

    if [[ -z "${OLDEST_FILE}" ]]; then
        echo 'Not enough space on backup device but no files present?'
        exit
    fi

    OLDEST_FILE="${BACKUP_DIR}/${OLDEST_FILE}"

    countdown_prompt 4 "Will remove ${OLDEST_FILE}"
    rm "${OLDEST_FILE}"
    calculate_available_space
done

BACKUP_NAME="${BACKUP_DIR}/backup_$(date +'%Y%m%d_%H%M%S').img"
echo "Creating image ${BACKUP_NAME}"

dd if="${DISK_TO_DUPLICATE}" of="${BACKUP_NAME}" bs=4096 &
DD_PID=$!

# don't race dd
until [[ -f "${BACKUP_NAME}" ]]; do
    sleep 1
done

CURRENT_BACKUP_SIZE=0
while [[ -d "/proc/${DD_PID}" ]]; do
    CURRENT_BACKUP_SIZE=$(stat --printf='%s' "${BACKUP_NAME}")
    PERCENT_DONE=$(((${CURRENT_BACKUP_SIZE} * 100) / ${DISK_TO_DUPLICATE_SIZE_B}))
    echo -ne "\r${CURRENT_BACKUP_SIZE} bytes / ${DISK_TO_DUPLICATE_SIZE_B} bytes (${PERCENT_DONE}%)"
    sleep 1
done
echo ''

sync
