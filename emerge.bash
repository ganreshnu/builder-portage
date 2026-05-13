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

	# mount the overlay
	local -r buildDir=/"$root"; mkdir -p "$buildDir";
	(( ${#lowers[@]} == 0 )) && lowers+=( /var/empty )
	fuse-overlayfs -o lowerdir="${ Join : "${lowers[@]}"; }",upperdir="$root",workdir="$workdir" "$buildDir" &&
		trap "fusermount3 -u $buildDir" EXIT

	ln -s usr/bin "$buildDir"/bin
	ln -s usr/sbin "$buildDir"/sbin

	MAKEOPTS="-j$(( $nproc / "$numJobs" ))" KERNEL_DIR=/usr/src/linux \
		command emerge --root="$buildDir" --jobs="$numJobs" "$@"
}
