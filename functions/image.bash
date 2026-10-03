#
# build an image
#
image() {
	Usage() {
		cat <<-EOD
		Usage: image [OPTIONS] DIRECTORY...

		Options:
		  --outdir DIRECTORY      The directory containing the root filesystem tree.
		  --name STRING           The name of the image used in the filenames for the
		                          image and associated data.
		  --definitions           Definitions for systemd-repart.
		  --help                  Display this message and exit.

		Makes the image from the given directories and definitions.
		EOD
	}

	# local workdir=''
	local outdir=''
	local name='image'
	local definitions=''
	local veritykey=''
	local lowers=()

	local argv=()
	while (( $# > 0 )); do
		local shiftnum=0
		case "$1" in
			# --workdir* )
			# 	ExpectVal workdir shiftnum "$@"; shift $shiftnum
			# 	;;
			--outdir* )
				ExpectVal outdir shiftnum "$@"; shift $shiftnum
				;;
			--name* )
				ExpectVal name shiftnum "$@"; shift $shiftnum
				;;
			--definitions* )
				ExpectVal definitions shiftnum "$@"; shift $shiftnum
				;;
			--veritykey* )
				ExpectVal veritykey shiftnum "$@"; shift $shiftnum
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
	if [[ ! -d "$outdir" ]]; then
		ArgError --outdir 'is required and must be an existing writable directory.'
		return 1
	fi
	if [[ ! -d "$definitions" ]]; then
		ArgError --definitions 'is required and must be an existing directory.'
		return 1
	fi

	local -r tree="${ mktemp -d; }"
	fuse-overlayfs -o lowerdir="${ Join : "${lowers[@]}"; }" "$tree" &&
		trap "fusermount3 -u $tree" EXIT

	systemd-repart --root="$tree" --definitions="$definitions" \
		--empty=create --size=auto --json=short "$@" "$outdir"/"$name".raw > "$outdir"/"$name".json
}
