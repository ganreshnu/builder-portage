#
# edit a kernel configuration fragment
#
linux() {
	Usage() {
		cat <<-EOD
			Usage: linux [OPTIONS] DIRECTORY...

			Options:
			  --root DIRECTORY        The directory containing the root filesystem tree.
			  --workdir DIRECTORY     OverlayFS workdir which must be on the same
			                          partition as the layer directories.
			  --help                  Display this message and exit.

			Makes the kernel.
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

	local -r buildDir=/"$root"; mkdir -p "$buildDir"
	(( ${#lowers[@]} == 0 )) && lowers+=( /var/empty )
	fuse-overlayfs -o lowerdir="${ Join : "${lowers[@]}"; }",upperdir="$root",workdir="$workdir" "$buildDir" &&
		trap "fusermount3 -u $buildDir" EXIT

	if [[ -f "$buildDir"/usr/lib/os-release && ! -f "$buildDir"/boot/initramfs.cpio.zst ]]; then
		local excludes=() includes=()
		local initramfsDir="${ mktemp -d; }"
		tar --directory="$buildDir" --create --preserve-permissions usr "${includes[@]}" "${excludes[@]}" |
			tar --directory="$initramfsDir" --extract --keep-directory-symlink
		mkdir -p "$buildDir"/boot

		printf "Generating initramfs from ${ tput bold; }%s${ tput sgr0; } source tree.\n" "${ du -sh "$initramfsDir" |cut -f1; }"
		pushd /usr/src/linux >/dev/null
		usr/gen_initramfs.sh -o /dev/stdout "$initramfsDir" \
			| zstd --compress --stdout > "$buildDir"/boot/initramfs.cpio.zst
		popd >/dev/null #/usr/src/linux/
		rm -fr "$initramfsDir"
	fi

	local -r kversion="${ make --directory=/usr/src/linux --quiet kernelversion; }"
	if [[ -d "$buildDir"/usr/lib/modules/"$kversion" ]]; then
		printf "Linux kernel ${ tput bold; }%s${ tput sgr0; } already built.\n" "$kversion"
		return 0
	fi

	printf "Building linux kernel ${ tput bold; }%s${ tput sgr0; }.\n" "$kversion"
	make --directory=/usr/src/linux -j"$nproc" --quiet
	make --directory=/usr/src/linux INSTALL_MOD_PATH="$buildDir"/usr INSTALL_MOD_STRIP=1 modules_install
	make --directory=/usr/src/linux INSTALL_PATH="$buildDir"/boot install
	# create the kconfig.zst
	zstd --quiet /usr/src/linux/.config -o "$buildDir"/boot/kconfig.zst
}
