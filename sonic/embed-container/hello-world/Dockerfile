# Self-contained example image for embedding in the SONiC installer.
#
# Requirements for an embeddable image:
#   * Base it on a small image so the saved tarball stays small; the appliance
#     has no internet access at runtime, so every layer must be in the tarball.
#   * The entrypoint should be a long-running foreground process.
#
# Build/emb is driven by sonic/embed-container.sh (which uses the legacy builder
# so `docker save` produces a tarball SONiC's Docker Engine can `docker load`).
FROM busybox:1.36
LABEL org.onie-gns3.experiment="hello-sonic"
COPY app/hello.sh /usr/local/bin/hello.sh
RUN chmod +x /usr/local/bin/hello.sh
ENTRYPOINT ["/usr/local/bin/hello.sh"]
