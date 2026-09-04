#!/usr/bin/env bash
set -euo pipefail

#
# builder-portage entrypoint script
#
Main() {
	Usage() {
		cat <<-EOD
			Usage: builder-portage [OPTIONS]

			Options:
			  --nproc INT             Number of cores to use in build tasks.
			  --arch STRING           Architecture of the kernel configuration.
			  --kconfig FILE          Apply the specified kernel configuration fragment.
			  --help                  Display this message and exit.

			Builds an optimized system image from source using portage.
		EOD
	}

	local nproc=${ nproc; }
	local arch=x86
	# local kernel='sys-kernel/vanilla-sources'
	local kconfigs=()

	local inMain=yes
	local argv=()
	while (( $# > 0 )); do
		local shiftnum=0
		case "$1" in
			--nproc* )
				ExpectVal nproc shiftnum "$@"; shift $shiftnum
				;;
			--arch* )
				ExpectVal arch shiftnum "$@"; shift $shiftnum
				;;
			# --kernel* )
			# 	ExpectVal kernel shiftnum "$@"; shift $shiftnum
			# 	;;
			--kconfig* )
				local value=''
				ExpectVal value shiftnum "$@"; shift $shiftnum
				kconfigs+=( "$value" )
				;;
			nconfig|emerge|linux|initramfs )
				inMain=no
				argv+=( "$1" )
				;;
			-- )
				shift; break
				;;
			--help )
				if [[ "$inMain" == yes ]]; then
					Usage
					return 0
				fi
				argv+=( "$1" )
				;;
			* )
				argv+=( "$1" )
				;;
		esac
		shift
	done
	argv+=( "$@" )
	set - "${argv[@]}" && unset -v argv inMain

	ApplyKConfigs "${kconfigs[@]}" &&
		unset -v kconfigs

	(( $# == 0 )) && exec bash --login ||
		if [[ "${ type -t "$1"; }" == function ]]; then
			"$@"
		else
			exec "$@"
		fi
}
LocaleGen() {
	locale-gen --prefix="$PWD"/"$*" --update
}
# join arguments with first
# Usage: Join , "${array[@]}"
Join() {
	IFS="$1"; shift
	echo "$*"
}
# apply kernel configuration fragments
# Usage: ApplyKConfigs "$@"
ApplyKConfigs() {
	for fragmentFile in "$@"; do
		[[ ! -f /usr/src/linux/arch/"$arch"/configs/"$fragmentFile" ]] &&
			cp "$fragmentFile" /usr/src/linux/arch/"$arch"/configs/
		echo "Merging $fragmentFile"
		make --directory=/usr/src/linux "${ basename "$fragmentFile"; }" --quiet
	done
}
# display a notice message
# Usage: Notice STRING
Notice() {
	printf "${ tput setaf 3; tput bold; }[!!]${ tput sgr0; } %s\n" "$*"
}
# display an argument error
# Usage: ArgError --reqarg 'is required'
ArgError() {
	local arg="$1"; shift
	>&2 printf "${ tput setaf 1; }${ tput sitm; }%s${ tput ritm; } %s${ tput sgr0; }\n" "$arg" "$*"
}
# simple argument value parser.
# Usage: ExpectVal value shiftnum "$@"
ExpectVal() {
	local -n v="$1"; shift
	local -n s="$1"; shift
	local name="${1%%=*}"
	s=0
	if [[ "$1" == "${name}" ]]; then
		(( $# < 2 )) && { >&2 printf "${ tput setaf 1; }%s:${ tput sgr0; } ${ tput bold; }${ tput sitm; }%s${ tput ritm; }${ tput sgr0; } expects a value.\n" "${BASH_SOURCE[1]}" "$1"; } && return 1
		v="$2"; s=1
		return 0
	fi
	v="${1#*=}"
}
# import other functions
. /usr/share/entrypoint/nconfig.bash
. /usr/share/entrypoint/emerge.bash
. /usr/share/entrypoint/linux.bash
. /usr/share/entrypoint/image.bash

Main "$@"
