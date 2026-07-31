#!/usr/bin/env bash
# Runs inside the build container as root: hand the working directories to the
# unprivileged build user, run mkarchiso as that user, then hand the results
# back so they are owned by the person who started the build.
set -uo pipefail

chown -R build:build /work /out

runuser -u build -- env HOME=/home/build mkarchiso -v -w /work -o /out /profile
rc=$?

# Files created inside the nested user namespace land on ids the host user
# cannot touch; container uid 0 maps to the host user, so hand them back.
chown -R 0:0 /out  2>/dev/null || true
chown -R 0:0 /work 2>/dev/null || true

exit $rc
