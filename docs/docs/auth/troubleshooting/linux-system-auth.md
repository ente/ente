---
title: Linux system authentication
description: Set up Linux system authentication for Ente Auth desktop
---

# Linux System Authentication

> [!NOTE]
>
> Linux system authentication was added after the public `auth-v4.4.22` release
> from May 6, 2026. Use a newer Ente Auth desktop release before following this
> guide.

Ente Auth uses Polkit to ask your Linux desktop to authenticate the current
user. Ente Auth does not choose whether the prompt asks for a password,
fingerprint, or another method. Polkit uses your host PAM configuration, so
fingerprint unlock is offered only when fingerprint authentication is configured
for Polkit on your system.

## Register the Polkit Policy

Deb, RPM, and pacman packages install the policy automatically. If Ente Auth
shows **Linux setup required**, install the policy manually.

The policy action is:

```text
com.ente.auth.unlock
```

### Manual Policy Setup

Flatpak apps cannot install host Polkit policies by themselves, and AppImage or
manual builds may also need manual setup. Download the policy from GitHub and
verify its SHA-256 checksum before installing it:

The script automatically selects the correct install path: `/usr/share/polkit-1/actions/`
on traditional distros, or `/etc/polkit-1/actions/` on immutable distros (such as
Fedora Atomic, Universal Blue, or similar) where `/usr/share` is read-only.

```sh
policy_url="https://raw.githubusercontent.com/ente/ente/main/mobile/apps/auth/assets/polkit/com.ente.auth.policy"
policy_sha256="efba0409db9a0a53196fa8a7c9f4d4e874234b48287eb5242cf399f466e4c695"
policy="$(mktemp)"

if curl -fsSL "$policy_url" -o "$policy" &&
  printf "%s  %s\n" "$policy_sha256" "$policy" | sha256sum -c -; then

  # Use /etc on immutable distros (read-only /usr), /usr/share on traditional ones
  if findmnt -n -o OPTIONS --target /usr/share/polkit-1/actions 2>/dev/null | grep -qw ro; then
     install_path="/etc/polkit-1/actions/com.ente.auth.policy"
  else
     install_path="/usr/share/polkit-1/actions/com.ente.auth.policy"
  fi

  sudo install -D -o root -g root -m 0644 "$policy" "$install_path"

  if command -v restorecon >/dev/null 2>&1; then
    sudo restorecon -v "$install_path" || true
  fi

  # Give polkit time to pick up the new action via inotify
  sleep 1

  pkaction --action-id com.ente.auth.unlock --verbose
else
  echo "Policy download or checksum verification failed. Not installing."
fi

rm -f "$policy"
```

### Remove the Policy

If you manually installed the Polkit policy and no longer want Ente Auth to use
Linux system authentication, remove it from whichever path was used during install:

```sh
sudo rm -f /usr/share/polkit-1/actions/com.ente.auth.policy
# or, on immutable distros:
sudo rm -f /etc/polkit-1/actions/com.ente.auth.policy

```

## Fingerprint Prompts

The Polkit policy only registers Ente Auth as an application that can request
system authentication. Password versus fingerprint is controlled by your Linux
PAM and fprintd setup.

If fingerprint authentication is configured for Polkit, Ente Auth should offer
it automatically, like other Polkit-based apps. Ente Auth does not install or
edit `/etc/pam.d/polkit-1`, because that file is system-wide and
distro-specific.

If password authentication works but fingerprint is not offered, configure
fingerprint authentication for Polkit using your distro's documentation. On
Ubuntu or Debian, this is usually handled through `fprintd`, `libpam-fprintd`,
and `pam-auth-update`.

Some distros route Polkit through `/etc/pam.d/polkit-1`; others include shared
PAM profiles such as `common-auth`. Check your distro's PAM documentation before
editing these files.
