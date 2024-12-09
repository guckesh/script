#!/usr/bin/env bash
#
# Pull in linux-stable updates to a kernel tree
#
# Copyright (C) 2017-2018 Nathan Chancellor
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>

# Colors for script
BOLD="\033[1m"
GRN="\033[01;32m"
RED="\033[01;31m"
RST="\033[0m"
YLW="\033[01;33m"

# Alias for echo to handle escape codes like colors
function echo() {
    command echo -e "$@"
}

# Prints a formatted header to point out what is being done to the user
function header() {
    if [[ -n ${2} ]]; then
        COLOR=${2}
    else
        COLOR=${RED}
    fi
    echo "${COLOR}"
    echo "====$(for i in $(seq ${#1}); do echo "=\c"; done)===="
    echo "==  ${1}  =="
    echo "====$(for i in $(seq ${#1}); do echo "=\c"; done)===="
    echo "${RST}"
}

# Prints an error in bold red
function die() {
    echo
    echo "${RED}${1}${RST}"
    [[ ${2} = "-h" ]] && ${0} -h
    exit 1
}

# Prints a statement in bold green
function success() {
    echo
    echo "${GRN}${1}${RST}"
    [[ -z ${2} ]] && echo
}

# Prints a warning in bold yellow
function warn() {
    echo
    echo "${YLW}${1}${RST}"
    [[ -z ${2} ]] && echo
}

# Parse the provided parameters
function parse_parameters() {
    while [[ $# -ge 1 ]]; do
        case ${1} in
            "-c"|"--cherry-pick") UPDATE_METHOD=cherry-pick ;;
            "-f"|"--fetch-only") FETCH_REMOTE_ONLY=true ;;
            "-h"|"--help")
                echo
                echo "${BOLD}Command:${RST} ./$(basename "${0}") <options>"
                echo "${BOLD}Script description:${RST} Merges/cherry-picks Linux upstream into a kernel tree"
                echo "${BOLD}Required parameters:${RST}"
                echo "    -c | --cherry-pick"
                echo "    -m | --merge"
                echo "${BOLD}Optional parameters:${RST}"
                echo "    -f | --fetch-only"
                echo "    -k | --kernel-folder <path>"
                echo "    -l | --latest"
                echo "    -p | --print-latest"
                echo "    -v | --version <version>"
                exit 1 ;;
            "-k"|"--kernel-folder")
                shift
                [[ $# -lt 1 ]] && die "Please specify a kernel source location!"
                KERNEL_FOLDER=${1} ;;
            "-l"|"--latest") UPDATE_MODE=1 ;;
            "-m"|"--merge") UPDATE_METHOD=merge ;;
            "-p"|"--print-latest") PRINT_LATEST=true ;;
            "-v"|"--version")
                shift
                [[ $# -lt 1 ]] && die "Please specify a version to update!"
                TARGET_VERSION=${1} ;;
            *) die "Invalid parameter!" ;;
        esac
        shift
    done
    [[ -z ${KERNEL_FOLDER} ]] && KERNEL_FOLDER=$(pwd)
    [[ ! ${UPDATE_METHOD} ]] && die "Neither cherry-pick nor merge were specified!" -h
    [[ ! -d ${KERNEL_FOLDER} ]] && die "Invalid kernel source location! Folder does not exist" -h
    [[ ! -f ${KERNEL_FOLDER}/Makefile ]] && die "Invalid kernel source location! No Makefile present" -h
    [[ -z ${UPDATE_MODE} && -z ${TARGET_VERSION} ]] && UPDATE_MODE=0
}

# Update the linux-stable remote
function update_remote() {
    header "Updating linux-stable"
    cd "${KERNEL_FOLDER}" || die "Could not change into ${KERNEL_FOLDER}!"
    if git fetch --tags https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git/; then
        success "linux-stable updated successfully!"
    else
        die "linux-stable update failed!"
    fi
    [[ ${FETCH_REMOTE_ONLY} ]] && exit 0
}

# Generate versions
function generate_versions() {
    header "Calculating versions"
    CURRENT_VERSION=$(make -s CC=gcc CROSS_COMPILE="" kernelversion)
    CURRENT_MAJOR_VERSION=$(echo "${CURRENT_VERSION}" | cut -f 1,2 -d .)
    CURRENT_SUBLEVEL=$(echo "${CURRENT_VERSION}" | cut -d . -f 3)
    LATEST_VERSION=$(git tag --sort=-taggerdate -l "v${CURRENT_MAJOR_VERSION}"* | head -n 1 | sed s/v//)
    LATEST_SUBLEVEL=$(echo "${LATEST_VERSION}" | cut -d . -f 3)
    echo "${BOLD}Current kernel version:${RST} ${CURRENT_VERSION}"
    echo "${BOLD}Latest kernel version:${RST} ${LATEST_VERSION}"
    [[ ${PRINT_LATEST} ]] && exit 0
    case ${UPDATE_MODE} in
        0) TARGET_SUBLEVEL=$((CURRENT_SUBLEVEL + 1))
           TARGET_VERSION=${CURRENT_MAJOR_VERSION}.${TARGET_SUBLEVEL} ;;
        1) TARGET_VERSION=${LATEST_VERSION} ;;
    esac
    TARGET_SUBLEVEL=$(echo "${TARGET_VERSION}" | cut -d . -f 3)
    [[ ${TARGET_SUBLEVEL} -le ${CURRENT_SUBLEVEL} ]] && die "${TARGET_VERSION} is already present!"
    [[ ${TARGET_SUBLEVEL} -gt ${LATEST_SUBLEVEL} ]] && die "${CURRENT_VERSION} is the latest!"
    [[ ${CURRENT_SUBLEVEL} -eq 0 ]] && CURRENT_VERSION=${CURRENT_MAJOR_VERSION}
    RANGE=v${CURRENT_VERSION}..v${TARGET_VERSION}
    echo "${BOLD}Target kernel version:${RST} ${TARGET_VERSION}"
}

# Resolve conflicts automatically
function resolve_conflicts() {
    echo
    warn "Conflicts detected! Attempting to resolve automatically..."
    git merge --abort 2>/dev/null || true
    git cherry-pick --abort 2>/dev/null || true
    git checkout --theirs .
    git add .
    if git cherry-pick --continue 2>/dev/null || git commit -m "Resolve conflicts during merge"; then
        success "Conflicts resolved successfully!"
    else
        die "Automatic conflict resolution failed! Please resolve manually."
    fi
}

# Update to target version
function update_to_target_version() {
    case ${UPDATE_METHOD} in
        "cherry-pick")
            if ! git cherry-pick "${RANGE}"; then
                resolve_conflicts
            else
                header "${TARGET_VERSION} PICKED CLEANLY!" "${GRN}"
            fi ;;
        "merge")
            if ! GIT_MERGE_VERBOSITY=1 git merge --no-edit "v${TARGET_VERSION}"; then
                resolve_conflicts
            else
                header "${TARGET_VERSION} MERGED CLEANLY!" "${GRN}"
            fi ;;
    esac
}

parse_parameters "$@"
update_remote
generate_versions
update_to_target_version
