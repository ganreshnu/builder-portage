#
# create the bootloader folder
#
bootloader() {
	Usage() {
		cat <<-EOD
		Usage: bootloader [OPTIONS]

		Options:
		  --root DIRECTORY        The directory containing the root filesystem tree.
		  --help                  Display this message and exit.

		Installs the bootloader.
		EOD
	}

	local root=''

	local argv=()
	while (( $# > 0 )); do
		local shiftnum=0
		case "$1" in
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

	mkdir -p "$root"/efi
	chmod 0700 "$root"/efi

	root="${ realpath "$root"; }"
	#
	# create the bootloader
	#
	mount --bind "$root"/efi "$root"/efi
	SYSTEMD_RELAX_ESP_CHECKS=1 bootctl --variables=no --esp-path="$root"/efi install
	umount "$root"/efi

	cat >"$root"/efi/loader/loader.conf <<-EOF
		timeout 5
	EOF
}
