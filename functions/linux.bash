#
# build the linux kernel with an initramfs
#
linux() {
	Usage() {
		cat <<-EOD
			Usage: linux [OPTIONS] DIRECTORY... MAKEARGS...

			Options:
			  --kconfig FILE          Apply the kernel configuration fragment before
			                          the build.
			  --root DIRECTORY        The directory containing the installed kernel
				                        and modules.
				--workdir DIRECTORY     OverlayFS workdir which must be on the same
				                        partition as the layer directories.
			  --help                  Display this message and exit.

			Overlays all DIRECTORY arguments with --root as upper then builds and installs
			the kernel and modules in the overlay. Any additional arguments are passed to
			the make command.
		EOD
	}

	local workdir=''
	local root=''
	# local cpioRoot="${ mktemp -d; }"
	# local rootpw=''
	local lowers=()
	# local modules=()
	# local cmdline=(
	# 	# rdinit=/usr/bin/bash
	# 	rdinit=/usr/lib/systemd/systemd
	# 	# console=uart,io,0x3f8 console=ttyS0
	# )

	local argv=()
	while (( $# > 0 )); do
		local shiftnum=0
		case "$1" in
			--workdir* )
				ExpectVal workdir shiftnum "$@"; shift $shiftnum
				;;
			# --rootpw* )
			# 	ExpectVal rootpw shiftnum "$@"; shift $shiftnum
			# 	;;
			--root* )
				ExpectVal root shiftnum "$@"; shift $shiftnum
				;;
			# --cmdline* )
			# 	ExpectVal v shiftnum "$@"; shift $shiftnum
			# 	cmdline+=( "$v" )
			# 	unset -v v
			# 	;;
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

	#
	# overlay the kernel root with the initramfs root
	#
	if (( ${#lowers[@]} == 0 )); then
		local -r tree="${ realpath "$root"; }"
	else
		local -r tree="${ mktemp -d; }"
		fuse-overlayfs -o workdir="$workdir",upperdir="$root",lowerdir="${ Join : "${lowers[@]}"; }" "$tree" &&
			trap "fusermount3 -u $tree" EXIT
	fi

	#
	# build the kernel and modules
	#
	local -r kversion="${ KVersion; }"
	if [[ ! -d "$tree"/usr/lib/modules/"$kversion" ]]; then
		ApplyKConfigs
		printf "Building linux ${ tput bold; }%s${ tput sgr0; }.\n" "$kversion"

		# local -r realRoot="${ realpath "$root"; }"
		pushd /usr/src/linux >/dev/null
		make -j"$nproc" "$@" #--quiet
		make INSTALL_MOD_PATH="$tree"/usr INSTALL_MOD_STRIP=1 modules_install
		make INSTALL_PATH="$tree"/boot install
		popd >/dev/null #/usr/src/linux/
		# create the kconfig.zst
		zstd --quiet /usr/src/linux/.config -o "$tree"/boot/kconfig.zst
	fi

# 	mkdir -p "$tree"/efi && chmod 0700 "$tree"/efi
# 	#
# 	# create the bootloader
# 	#
# 	mount --bind "$tree"/efi "$tree"/efi
# 	SYSTEMD_RELAX_ESP_CHECKS=1 bootctl --variables=no --esp-path="$tree"/efi install
# 	umount "$tree"/efi
# 	#
# 	# create the uki
# 	#
# 	printf "Creating UKI with commandline ${ tput bold; }%s${ tput sgr0; }.\n" "${cmdline[*]}"
# 	ukify build --linux "$tree"/boot/vmlinuz --os-release "$tree"/usr/lib/os-release --initrd "$tree"/boot/initramfs.cpio.zst \
# 		--uname "$kversion" --cmdline "${cmdline[*]}" --output "$tree"/efi/EFI/Linux/linux-"$kversion".efi "$@"
#
# 	cat >"$tree"/efi/loader/loader.conf <<-EOF
# 		timeout 0
# 	EOF
# 	cat >"$tree"/efi/loader/entries/default.conf <<-EOF
# 		title Linux-$kversion
# 		version $kversion
# 		efi EFI/Linux/linux-${kversion}.efi
# 	EOF
}
