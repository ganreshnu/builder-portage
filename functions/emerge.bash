#
# install portage packages
#
emerge() {
	Usage() {
		cat <<-EOD
			Usage: emerge [OPTIONS] [DIRECTORY...] [EMERGE_ARGS...] EBUILD...

			Options:
			  --root DIRECTORY        The directory containing the root filesystem tree.
			  --workdir DIRECTORY     OverlayFS workdir which must be on the same
			                          partition as the layer directories.
			  --confdir DIRECTORY     A directory containing the portage configuration.
			  --help                  Display this message and exit.

			Builds and installs EBUILDs to the specified --root directory. The --root
			directory is overlayed on top of any specified DIRECTORY.
		EOD
	}

	local workdir=''
	local root=''
	local numJobs=4
	local confdirs=()
	local lowers=()

	local argv=()
	while (( $# > 0 )); do
		local shiftnum=0
		case "$1" in
			--workdir* )
				ExpectVal workdir shiftnum "$@"; shift $shiftnum
				;;
			--root* )
				ExpectVal root shiftnum "$@"; shift $shiftnum
				;;
			--jobs* )
				ExpectVal numJobs shiftnum "$@"; shift $shiftnum
				;;
			--confdir* )
				local value=''
				ExpectVal value shiftnum "$@"; shift $shiftnum
				confdirs+=( "$value" )
				;;
			-- )
				shift; break
				;;
			--help )
				Usage
				return 0
				;;
			* )
				if [[ -d "$1" ]]; then
					lowers=( "$1" "${lowers[@]}" )
				else
					argv+=( "$1" )
				fi
				;;
		esac
		shift
	done
	argv+=( "$@" )
	set - "${argv[@]}" && unset -v argv

	# validate arguments
	if [[ ! -d "$root" ]]; then
		ArgError --root 'is required and must be an existing writable directory.'
		return 1
	fi
	if [[ ! -d "$workdir" ]]; then
		ArgError --workdir 'is required and must be an existing writable directory.'
		return 1
	fi

	for confdir in "${confdirs[@]}"; do
		tar --directory="$confdir" --create --preserve-permissions . |
			tar --directory=/etc/portage --extract --keep-directory-symlink
	done

	ApplyKConfigs

	# mount the overlay
	if (( ${#lowers[@]} == 0 )); then
		local -r tree="${ realpath "$root"; }"
	else
		local -r tree="${ mktemp -d; }"
		fuse-overlayfs -o workdir="$workdir",upperdir="$root",lowerdir="${ Join : "${lowers[@]}"; }" "$tree" &&
			trap "fusermount3 -u $tree" EXIT
	fi

	ln -sf usr/bin "$tree"/bin
	ln -sf usr/bin "$tree"/sbin
	mkdir -p "$tree"/usr
	ln -sf bin "$tree"/usr/sbin
	# PrepareRoot "$tree"

	MAKEOPTS="-j$(( $nproc / "$numJobs" ))" KERNEL_DIR=/usr/src/linux \
		command emerge --root="$tree" --jobs="$numJobs" "$@"
}
