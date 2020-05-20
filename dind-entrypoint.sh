#!/bin/bash
set -x
set -o errexit
set -o nounset
set -o pipefail

# This is copied from official dind script:
# https://raw.githubusercontent.com/docker/docker/master/hack/dind
if [ -d /sys/kernel/security ] && ! mountpoint -q /sys/kernel/security; then
	mount -t securityfs none /sys/kernel/security || {
		echo >&2 'Could not mount /sys/kernel/security.'
		echo >&2 'AppArmor detection and --privileged mode might break.'
	}
fi

# Mount /tmp (conditionally)
if ! mountpoint -q /tmp; then
	mount -t tmpfs none /tmp
fi

# Note that `release_agent` file is only created at the root of a
# cgroup hierarchy.
if [[ ! -f /sys/fs/cgroup/systemd/release_agent ]]; then
  echo >&2 'Unsupported configuration, please mount /sys/fs/cgroup'
  ls -al /sys/fs/cgroup
  cat /proc/self/mountinfo
  exit 1
fi

CGROUP_PARENT="$(grep systemd /proc/self/cgroup | cut -d: -f3)/docker"
nohup dockerd \
  --cgroup-parent="${CGROUP_PARENT}" \
  --bip="${DOCKER_RANGE:-172.17.1.1/24}" \
  --mtu="${DOCKER_MTU:-1400}" ${DOCKER_ARGS:-} &

# Wait until dockerd is ready.
for i in `seq ${START_TIMEOUT:-10}`; do
  if docker ps >/dev/null 2>&1; then
    break
  fi
  echo "Waiting for dockerd..."
  sleep 1
done

exec "$@"
