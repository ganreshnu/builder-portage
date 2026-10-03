#
# create a cpio archive
#
cpio() {
	Usage() {
		cat <<-EOD
		Usage: cpio [OPTIONS] DIRECTORY... [MODULE...]

		Options:
		  --root DIRECTORY        The directory containing the root filesystem tree.
		  --workdir DIRECTORY     OverlayFS workdir which must be on the same
		                          partition as the layer directories.
			--rootpw HASH           A password hash created by mkpasswd(1).
			--help                  Display this message and exit.

		Creates a cpio archive from the specified directory.
		EOD
	}

	local rootpw=''
	local workdir=''
	local root=''
	local lowers=()
	local modules=()

	local argv=()
	while (( $# > 0 )); do
		local shiftnum=0
		case "$1" in
			--workdir* )
				ExpectVal workdir shiftnum "$@"; shift $shiftnum
				;;
			--rootpw* )
				ExpectVal rootpw shiftnum "$@"; shift $shiftnum
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
					lowers+=( "$1" )
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
	if (( ${#lowers[@]} == 0 )); then
		ArgError DIRECTORY 'is required and must be an existing directory.'
		return 1
	fi

	# mount the overlay
	local -r tree="${ mktemp -d; }"
	fuse-overlayfs -o workdir="$workdir",upperdir="$root",lowerdir="${ Join : "${lowers[@]}"; }" "$tree" &&
		trap "fusermount3 -u $tree" EXIT

	. "$tree"/usr/lib/os-release
	[[ -f "$tree"/boot/"$IMAGE_ID-$VARIANT_ID.cpio.zst" ]] && return
	Notice "creating $IMAGE_ID-$VARIANT_ID.cpio.zst"

	local kversion="${ KVersion; }"
	local excludes=(
		--exclude=usr/lib/modules/"$kversion"/build
	)
	local includes=()
	# includes+=( etc/login.defs )
	[[ -f "$tree"/etc/initrd-release ]] && includes+=( etc/initrd-release )
	# include specified modules
	if (( ${#modules[@]} > 0 )); then
		excludes+=( --exclude=usr/lib/modules/"$kversion"/kernel )
		for module in "${modules[@]}"; do [[ "$module" != '-' ]] && AddModule includes "$module"; done
	fi

	local cpioRoot="${ mktemp -d; }"
	PrepareRoot "$cpioRoot"
	tar --directory="$tree" --create --preserve-permissions "${includes[@]}" "${excludes[@]}" usr |
		tar --directory="$cpioRoot" --extract --keep-directory-symlink

	depmod --basedir="$cpioRoot"/usr --outdir="$cpioRoot"/usr "$kversion"
	# create the system users
	systemd-sysusers --root="$cpioRoot"
	# systemd-tmpfiles --root="$root" --create --boot
	# generate the locales
	[[ -f "$tree"/etc/locale.gen ]] && locale-gen --prefix="$cpioRoot" --config="$tree"/etc/locale.gen
	# set root password
	[[ -n "$rootpw" ]] && printf 'root:%s' "$rootpw" |chpasswd --prefix "$cpioRoot" #--encrypted

	printf "Generating cpio from ${ tput bold; }%s${ tput sgr0; } source tree.\n" "${ du -sh "$cpioRoot" |cut -f1; }"
	mkdir -p "$tree"/boot
	{
		pushd /usr/src/linux >/dev/null
		usr/gen_initramfs.sh -o /dev/stdout "$cpioRoot" \
			| zstd --compress --stdout
		popd >/dev/null #/usr/src/linux/
	} > "$tree"/boot/"$IMAGE_ID-$VARIANT_ID.cpio.zst"
	rm -fr "$cpioRoot"
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
