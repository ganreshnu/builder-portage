#
# edit a kernel configuration fragment
#
nconfig() {
	Usage() {
		cat <<-EOD
			Usage: nconfig [OPTIONS] FILE

			Options:
			  --help                  Display this message and exit.

			Edits the kernel configuration fragment FILE.
		EOD
	}

	local argv=()
	while (( $# > 0 )); do
		case "$1" in
			-- )
				shift; break
				;;
			--help )
				Usage
				return 0
				;;
			* )
				argv+=( "$1" )
				;;
		esac
		shift
	done
	argv+=( "$@" )
	set - "${argv[@]}" && unset -v argv

	# validate input
	if (( $# != 1 )); then
		ArgError FILE 'is required.'
		return 1
	fi

	ApplyKConfigs

	local orig="${ mktemp; }"
	cp /usr/src/linux/.config "$orig"
	[[ -f "$*" ]] && ApplyKConfigs "$*"
	pushd /usr/src/linux >/dev/null
	make nconfig --quiet &&
		scripts/diffconfig -m "$orig" .config > diff.config
	local -r retcode=$?
	rm "$orig"
	popd >/dev/null #/usr/src/linux
	[[ -s /usr/src/linux/diff.config ]] && cp /usr/src/linux/diff.config "$*"
	return $retcode
}
