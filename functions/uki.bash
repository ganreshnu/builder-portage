#
# create a uki
#
uki() {
	Usage() {
		cat <<-EOD
		Usage: uki [OPTIONS] [DIRECTORY...] [EMERGE_ARGS...] EBUILD...

		Options:
		  --root DIRECTORY        The directory containing the root filesystem tree.
		  --workdir DIRECTORY     OverlayFS workdir which must be on the same
		                          partition as the layer directories.
		  --cmdline STRING        Add a commandline entry to the kernel.
		  --help                  Display this message and exit.

		Creates a uki.
		EOD
	}

	local workdir=''
	local root=''
	local variant=''
	local lowers=()
	local cmdline=(
		rdinit=/usr/lib/systemd/systemd
	)

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
			--cmdline* )
				ExpectVal v shiftnum "$@"; shift $shiftnum
				cmdline+=( "$v" )
				unset -v v
				;;
			--variant* )
				ExpectVal variant shiftnum "$@"; shift $shiftnum
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
					lowers+=( "$1" )
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

	# mount the overlay
	if (( ${#lowers[@]} == 0 )); then
		local -r tree="${ realpath "$root"; }"
	else
		local -r tree="${ mktemp -d; }"
		fuse-overlayfs -o workdir="$workdir",upperdir="$root",lowerdir="${ Join : "${lowers[@]}"; }" "$tree" &&
			trap "fusermount3 -u $tree" EXIT
	fi

	local -r kversion="${ KVersion; }"
	. "$tree"/usr/lib/os-release
	#
	# create the uki
	#
	printf "Creating UKI with commandline ${ tput bold; }%s${ tput sgr0; }.\n" "${cmdline[*]}"
	ukify build --linux "$tree"/boot/vmlinuz --os-release "$tree"/usr/lib/os-release --initrd "$tree"/boot/"$IMAGE_ID"-"$variant".cpio.zst \
		--uname "$kversion" --cmdline "${cmdline[*]}" --output "$tree"/efi/EFI/Linux/"$IMAGE_ID"-"$VARIANT_ID"-"$IMAGE_VERSION".efi "$@"

	cat >"$tree"/efi/loader/entries/"$IMAGE_ID-$VARIANT_ID".conf <<-EOF
		title $IMAGE_ID-$VARIANT_ID-$IMAGE_VERSION
		version $kversion
		efi EFI/Linux/$IMAGE_ID-$VARIANT_ID-$IMAGE_VERSION.efi
	EOF
}
