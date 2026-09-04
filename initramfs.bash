#
# build an initramfs
#
initramfs() {
	Usage() {
		cat <<-EOD
			Usage: initramfs [OPTIONS] DIRECTORY...

			Options:
			  --root DIRECTORY        The directory containing the root filesystem tree.
				--kernel-root DIRECTORY	A directory containing the built kernel and modules.
			  --workdir DIRECTORY     OverlayFS workdir which must be on the same
			                          partition as the layer directories.
			  --help                  Display this message and exit.

			Makes the initramfs from the given directories.
		EOD
	}

	local workdir=''
	local root=''
	local kernelRoot=''
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
			--kernel-root* )
				ExpectVal kernelRoot shiftnum "$@"; shift $shiftnum
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
	if [[ ! -d "$kernelRoot" ]]; then
		ArgError --kernel-root 'is required and must be an existing writable directory containing the installed kernel.'
		return 1
	fi


	# overlay the kernel root with the initramfs root
	local -r tree="${ mktemp -d; }"
	(( ${#lowers[@]} == 0 )) && lowers+=( /var/empty )
	fuse-overlayfs -o lowerdir="${ Join : "${lowers[@]}"; }",upperdir="$kernelRoot",workdir="$workdir" "$tree" &&
		trap "fusermount3 -u $tree" EXIT

	#
	# build the kernel
	#
	local -r kversion="${ make --directory=/usr/src/linux --quiet kernelversion; }"
	if [[ ! -d "$tree"/usr/lib/modules/"$kversion" ]]; then
		printf "Building linux ${ tput bold; }%s${ tput sgr0; }.\n" "$kversion"
		make --directory=/usr/src/linux -j"$nproc" --quiet
		make --directory=/usr/src/linux INSTALL_MOD_PATH="$tree"/usr INSTALL_MOD_STRIP=1 modules_install
		make --directory=/usr/src/linux INSTALL_PATH="$tree"/boot install
		# create the kconfig.zst
		zstd --quiet /usr/src/linux/.config -o "$tree"/boot/kconfig.zst
	else
		printf "Linux ${ tput bold; }%s${ tput sgr0; } already built.\n" "$kversion"
	fi

	#
	# build the initramfs
	#
	if [[ -f "$tree"/usr/lib/os-release && ! -f "$tree"/boot/initramfs.cpio.zst ]]; then
		local excludes=( --exclude=usr/lib/modules/"$kversion" )
		local includes=()
		tar --directory="$tree" --create --preserve-permissions "${excludes[@]}" usr "${includes[@]}" |
			tar --directory="$root" --extract --keep-directory-symlink

		printf "Generating initramfs from ${ tput bold; }%s${ tput sgr0; } source tree.\n" "${ du -sh "$root" |cut -f1; }"
		local -r realRoot="${ realpath $root; }"
		pushd /usr/src/linux >/dev/null
		usr/gen_initramfs.sh -o /dev/stdout "$realRoot" \
			| zstd --compress --stdout > "$tree"/boot/initramfs.cpio.zst
		popd >/dev/null #/usr/src/linux/
	else
		printf "Already generated a %s initramfs.\n" "${ du -sh "$tree"/boot/initramfs.cpio.zst |cut -f1; }"
	fi
}
