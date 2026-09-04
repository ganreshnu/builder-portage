#
# build an image
#
image() {
	Usage() {
		cat <<-EOD
			Usage: image [OPTIONS] DIRECTORY...

			Options:
			  --root DIRECTORY        The directory containing the root filesystem tree.
			  --workdir DIRECTORY     OverlayFS workdir which must be on the same
			                          partition as the layer directories.
			  --help                  Display this message and exit.

			Makes the image from the given directories.
		EOD
	}

	local workdir=''
	local root=''
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

	local -r tree="${ mktemp -d; }"
	(( ${#lowers[@]} == 0 )) && lowers+=( /var/empty )
	fuse-overlayfs -o lowerdir="${ Join : "${lowers[@]}"; }",workdir="$workdir" "$tree" &&
		trap "fusermount3 -u $tree" EXIT


}
