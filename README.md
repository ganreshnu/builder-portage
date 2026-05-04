# builder-portage

An operating system image builder using portage.

## Installation

```bash
volumes=(
  --volume="$HOME"/.var/db/repos:/var/db/repos
  --volume="$HOME"/.cache/binpkgs:/var/cache/binpkgs
  --volume="$HOME"/.cache/distfiles:/var/cache/distfiles
)
ttl=24h
podman build --cache-ttl="$ttl" "${volumes[@]}" --tag=builder-portage .
```

## Usage

```bash
volumes=(
  --volume="$HOME"/.var/db/repos:/var/db/repos
  --volume="$HOME"/.cache/binpkgs:/var/cache/binpkgs
  --volume="$HOME"/.cache/distfiles:/var/cache/distfiles
)
alias builder-portage="podman run --rm --interactive --tty --device=/dev/fuse ${volumes[*]} --volume="\$PWD":"\$PWD" --workdir="\$PWD" builder-portage"
```

## License

[MIT](https://choosealicense.com/licenses/mit/)
