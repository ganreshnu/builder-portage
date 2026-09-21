# FROM docker.io/gentoo/portage:latest AS portage
FROM docker.io/gentoo/stage3:nomultilib-systemd

ARG jobs=2

COPY portage /etc/portage
# sync repositories
RUN emerge --jobs=$jobs dev-vcs/git
RUN emerge --sync

# update @world --update --deep
RUN emerge --jobs=$jobs --newuse --deep @world
# install a kernel and set default config
RUN emerge --jobs=1 sys-kernel/vanilla-sources && {\
	cd /usr/src/linux; \
	make -C usr gen_init_cpio; \
	make alldefconfig; \
}
# install tools
RUN emerge --jobs=$jobs sys-fs/fuse-overlayfs sys-fs/dosfstools sys-fs/mtools

COPY verity-cert.config /usr/share/

COPY functions /usr/share/entrypoint
COPY entrypoint.bash /usr/sbin/entrypoint
RUN chmod a+x /usr/sbin/entrypoint
ENTRYPOINT [ "unshare", "--mount", "--map-users=all", "--map-groups=all", "entrypoint" ]
