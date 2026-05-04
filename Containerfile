# FROM docker.io/gentoo/portage:latest AS portage
FROM docker.io/gentoo/stage3:nomultilib-systemd

ARG jobs=2

COPY portage /etc/portage
# sync repositories
RUN emerge --jobs=$jobs dev-vcs/git && emerge --sync

# update @world
RUN emerge --jobs=$jobs --update --newuse --deep @world
# install a kernel and set default config
RUN emerge --jobs=1 sys-kernel/vanilla-sources && {\
	cd /usr/src/linux; \
	make alldefconfig; \
	make -C usr gen_init_cpio;\
}
# install tools
RUN emerge --jobs=$jobs sys-fs/fuse-overlayfs

COPY verity-cert.config /usr/share/

COPY emerge.bash /usr/share/entrypoint/
COPY nconfig.bash /usr/share/entrypoint/
COPY linux.bash /usr/share/entrypoint/
COPY mkoci.bash /usr/share/entrypoint/

COPY entrypoint.bash /usr/sbin/entrypoint
RUN chmod a+x /usr/sbin/entrypoint
ENTRYPOINT [ "unshare", "--mount", "--map-users=all", "--map-groups=all", "entrypoint" ]
