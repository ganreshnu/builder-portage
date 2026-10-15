# FROM docker.io/gentoo/portage:latest AS portage
FROM docker.io/gentoo/stage3:nomultilib-systemd

ARG jobs=2

COPY portage-builder/make.conf /etc/portage/
COPY portage-builder/repos.conf /etc/portage/
COPY portage-builder/package.accept_keywords /etc/portage/

# sync repositories
RUN USE="-perl" emerge --jobs=$jobs dev-vcs/git
RUN emerge --sync

# install a kernel and set default config
RUN USE=symlink emerge --jobs=1 sys-kernel/vanilla-sources && {\
	cd /usr/src/linux; \
	make -C usr gen_init_cpio; \
	make alldefconfig; \
}

# copy over the builder portage config
COPY portage-builder/package.license /etc/portage/
COPY portage-builder/package.use /etc/portage/

# update @world --update --deep
RUN emerge --jobs=$jobs --newuse --update --deep @world # --pretend --verbose; exit 1

# install tools
RUN emerge --jobs=$jobs sys-fs/fuse-overlayfs sys-fs/dosfstools sys-fs/mtools net-misc/whois dev-util/bpftool sys-fs/erofs-utils sys-fs/btrfs-progs dev-libs/glib sys-kernel/linux-firmware net-wireless/wireless-regdb # --pretend --verbose; exit 1
RUN emerge --jobs=$jobs sys-devel/bpf-toolchain
RUN emerge --jobs=$jobs llvm-core/clang
RUN emerge --jobs=$jobs app-portage/gentoolkit app-portage/portage-utils

# COPY verity-cert.config /usr/share/
RUN rm /etc/portage/package.{accept_keywords,license,use}
COPY portage-system/ /etc/portage/

COPY functions /usr/share/entrypoint
COPY entrypoint.bash /usr/sbin/entrypoint
RUN chmod a+x /usr/sbin/entrypoint
ENTRYPOINT [ "unshare", "--mount", "--map-users=all", "--map-groups=all", "entrypoint" ]
