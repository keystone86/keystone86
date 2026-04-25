#!/usr/bin/env bash
set -euo pipefail

DEV_USER="dev"
DEV_GROUP="dev"
DEV_HOME="/home/dev"

HOST_UID="${HOST_UID:-1000}"
HOST_GID="${HOST_GID:-1000}"

# If the requested group id differs from the image default, adjust it when safe.
CURRENT_GID="$(getent group "${DEV_GROUP}" | cut -d: -f3 || true)"
if [[ -n "${CURRENT_GID}" && "${CURRENT_GID}" != "${HOST_GID}" ]]; then
    if getent group "${HOST_GID}" >/dev/null; then
        EXISTING_GROUP="$(getent group "${HOST_GID}" | cut -d: -f1)"
        DEV_GROUP="${EXISTING_GROUP}"
        usermod -g "${HOST_GID}" "${DEV_USER}"
    else
        groupmod -g "${HOST_GID}" "${DEV_GROUP}"
    fi
fi

# If the requested user id differs from the image default, adjust it.
CURRENT_UID="$(id -u "${DEV_USER}")"
if [[ "${CURRENT_UID}" != "${HOST_UID}" ]]; then
    if getent passwd "${HOST_UID}" >/dev/null; then
        echo "error: HOST_UID ${HOST_UID} already exists in the container." >&2
        echo "Refusing to continue because the dev user cannot safely take that UID." >&2
        exit 1
    fi
    usermod -u "${HOST_UID}" "${DEV_USER}"
fi

# Ensure the home/auth/cache directories exist and are writable by the dev user.
# Do not recursively chown all of /home/dev, because .ssh and .gitconfig may be
# read-only bind mounts from the host.
mkdir -p \
    "${DEV_HOME}" \
    "${DEV_HOME}/.claude" \
    "${DEV_HOME}/.codex" \
    "${DEV_HOME}/.cache" \
    "${DEV_HOME}/.npm"

chown "${HOST_UID}:${HOST_GID}" "${DEV_HOME}" || true
chown -R "${HOST_UID}:${HOST_GID}" "${DEV_HOME}/.claude" || true
chown -R "${HOST_UID}:${HOST_GID}" "${DEV_HOME}/.codex" || true
chown -R "${HOST_UID}:${HOST_GID}" "${DEV_HOME}/.cache" || true
chown -R "${HOST_UID}:${HOST_GID}" "${DEV_HOME}/.npm" || true

export HOME="${DEV_HOME}"
export USER="${DEV_USER}"
export LOGNAME="${DEV_USER}"

cd /work

exec gosu "${HOST_UID}:${HOST_GID}" "$@"