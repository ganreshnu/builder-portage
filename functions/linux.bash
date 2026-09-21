#
# build the linux kernel with an initramfs
#
linux() {
	Usage() {
		cat <<-EOD
			Usage: linux [OPTIONS] DIRECTORY...

			Options:
			  --root DIRECTORY        The directory containing the installed kernel
				                        and modules.
				--cpio-root DIRECTORY   A directory containing the initramfs root
				                        before cpio creation.
			  --rootpw STRING         The initramfs root password.
				--workdir DIRECTORY     OverlayFS workdir which must be on the same
				                        partition as the layer directories.
			  --help                  Display this message and exit.

			Makes the kernel and modules and installs to DIRECTORY.
		EOD
	}

	local workdir=''
	local root=''
	local cpioRoot="${ mktemp -d; }"
	local rootpw=''
	local lowers=()
	local modules=()
	local cmdline=(
		consoleblank=60
		rw rdinit=/usr/lib/systemd/systemd
		# console=uart,io,0x3f8 console=tty0
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
			--cpio-root* )
				ExpectVal cpioRoot shiftnum "$@"; shift $shiftnum
				;;
			--rootpw* )
				ExpectVal rootpw shiftnum "$@"; shift $shiftnum
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
					modules+=( "$1" )
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
	if [[ ! -d "$cpioRoot" ]]; then
		ArgError --cpio-root 'must be an existing writable directory.'
		return 1
	fi

	#
	# build the kernel
	#
	local -r kversion="${ make --directory=/usr/src/linux --quiet kernelversion; }"
	if [[ ! -d "$root"/usr/lib/modules/"$kversion" ]]; then
		printf "Building linux ${ tput bold; }%s${ tput sgr0; }.\n" "$kversion"
		local -r realRoot="${ realpath "$root"; }"
		pushd /usr/src/linux >/dev/null
		make -j"$nproc" --quiet
		make INSTALL_MOD_PATH="$realRoot"/usr INSTALL_MOD_STRIP=1 modules_install
		make INSTALL_PATH="$realRoot"/boot install
		popd >/dev/null #/usr/src/linux/
		# create the kconfig.zst
		zstd --quiet /usr/src/linux/.config -o "$root"/boot/kconfig.zst
	fi

	#
	# overlay the kernel root with the initramfs root
	#
	local -r tree="${ mktemp -d; }"
	(( ${#lowers[@]} == 0 )) && lowers+=( /var/empty )
	fuse-overlayfs -o lowerdir="${ Join : "${lowers[@]}"; }",upperdir="$root",workdir="$workdir" "$tree" &&
		trap "fusermount3 -u $tree" EXIT

	#
	# build the initramfs
	#
	if [[ -f "$tree"/usr/lib/os-release && ! -f "$tree"/boot/initramfs.cpio.zst ]]; then
		local excludes=( --exclude=usr/lib/modules/"$kversion"/build )
		local includes=()
		# include specified modules
		if (( ${#modules[@]} > 0 )); then
			excludes+=( --exclude=usr/lib/modules/"$kversion"/kernel )
			for module in "${modules[@]}"; do [[ "$module" != '-' ]] && AddModule includes "$module"; done
		fi
		tar --directory="$tree" --create --preserve-permissions "${includes[@]}" "${excludes[@]}" usr |
			tar --directory="$cpioRoot" --extract --keep-directory-symlink

		depmod --basedir="$cpioRoot"/usr --outdir="$cpioRoot"/usr "$kversion"
		systemd-sysusers --root="$cpioRoot"
		# systemd-tmpfiles --root="$cpioRoot" --create --boot

		# set root password
		[[ -n "$rootpw" ]] && echo "root:$rootpw" |chpasswd --prefix /tmp/initramfs --encrypted

		printf "Generating initramfs from ${ tput bold; }%s${ tput sgr0; } source tree.\n" "${ du -sh "$cpioRoot" |cut -f1; }"
		cpioRoot="${ realpath "$cpioRoot"; }"
		pushd /usr/src/linux >/dev/null
		usr/gen_initramfs.sh -o /dev/stdout "$cpioRoot" \
			| zstd --compress --stdout > "$tree"/boot/initramfs.cpio.zst
		popd >/dev/null #/usr/src/linux/
	fi

	#
	# create the bootloader
	#
	mkdir -p "$tree"/efi && chmod 0700 "$tree"/efi
	mount --bind "$tree"/efi "$tree"/efi
	SYSTEMD_RELAX_ESP_CHECKS=1 bootctl --variables=no --esp-path="$tree"/efi install
	umount "$tree"/efi

	#
	# create the uki
	#
	printf "Creating UKI with commandline ${ tput bold; }%s${ tput sgr0; }.\n" "${cmdline[*]}"
	ukify build --linux "$tree"/boot/vmlinuz --os-release "$tree"/usr/lib/os-release --initrd "$tree"/boot/initramfs.cpio.zst \
		--uname "$kversion" --cmdline "${cmdline[*]}" --output "$tree"/efi/EFI/Linux/linux-"$kversion".efi
}
AddModule() {
	local -n out="$1"; shift
	{
		IFS=$'\n'
		for module in ${ modprobe --dirname="$root"/usr --set-version="$kversion" --show-depends "$*" |awk '{ print $2 }'; }; do
			out+=( "${module#$PWD/$root/}" )
			Notice "added ${out[-1]}"
		done
	}
}
