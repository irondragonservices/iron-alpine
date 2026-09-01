# irondragonservices/iron-alpine

Hardened Alpine Linux base image for Docker.

Forked from [ironpeakservices/iron-alpine](https://github.com/ironpeakservices/iron-alpine).
The hardening is theirs; what is added here is the automation that keeps a
published image current, and the fixes noted at the bottom.

If you build static binaries — Go, Rust — you want
[iron-scratch](https://github.com/irondragonservices/iron-scratch) instead.
For Java, Python, Node or .NET, a
[distroless image](https://github.com/GoogleContainerTools/distroless) is a
better fit than this.

```sh
# Pin as loosely or as tightly as you want.
docker pull ghcr.io/irondragonservices/iron-alpine:3        # any 3.x
docker pull ghcr.io/irondragonservices/iron-alpine:3.24     # any 3.24.x
docker pull ghcr.io/irondragonservices/iron-alpine:3.24.1   # exactly this
```

The tag tracks the Alpine release the image is built on, so `:3.24.1` is
iron-alpine built on `alpine:3.24.1`.

## How is this different from alpine

- ca-certificates included
- `/app` for everything app-related: `$CONF_DIR`, `$DATA_DIR`, `$TMP_DIR`
- runs as an unprivileged user, uid 1000
- no interactive shell for any account
- only `app`, `root` and `nobody` remain in `/etc/passwd`; password login is
  disabled for all of them
- crontabs, init scripts, kernel tunables, `/root` and `/etc/fstab` removed
- `hexdump`, `chgrp`, `ln`, `od`, `strings`, `su` and `sudo` removed
- every setuid and setgid bit removed
- world-writable permissions stripped from everything but `/tmp`
- system directories owned by root and not writable by anybody else

## Using it

```dockerfile
FROM ghcr.io/irondragonservices/iron-alpine:3

RUN apk add --no-cache your-package

COPY your.conf $CONF_DIR/

# Always last. See below for why.
RUN $APP_DIR/post-install.sh

USER $APP_USER
```

`post-install.sh` runs after everything you install, and does the work that
can only be done once nothing else will follow it:

- removes `apk` itself
- re-removes the dangerous applets, and any setuid or setgid bit a package set
- makes `$APP_DIR` read-only, leaving only `$DATA_DIR` and `$TMP_DIR` writable
- removes `chown`, then removes itself

Re-removing the applets matters more than it looks. Every `apk add` fires the
busybox trigger, which recreates the whole applet symlink farm — `su`,
`hexdump`, `od` and the rest come straight back, and the base image's
hardening is undone by the first package anyone installs. Nothing warns you.

See [the nginx example](example/) for a complete, runnable one.

## Environment

| Variable | Default | For |
|---|---|---|
| `APP_USER` | `app` | The unprivileged user, uid 1000 |
| `APP_DIR` | `/app` | Home. Read-only after `post-install.sh` |
| `CONF_DIR` | `/app/conf` | Configuration. Read-only at runtime |
| `DATA_DIR` | `/app/data` | Persistent data. Mount a volume here |
| `TMP_DIR` | `/app/tmp` | Scratch — pid files, sockets, upload buffers |

## Verifying what you pulled

Images are signed keylessly, so there is no key to leak or rotate: the
signature is bound to the workflow identity that built it.

```sh
cosign verify ghcr.io/irondragonservices/iron-alpine:3 \
  --certificate-identity-regexp '^https://github\.com/irondragonservices/\.github/\.github/workflows/image-(release|refresh)\.yml@refs/heads/main$' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-github-workflow-repository irondragonservices/iron-alpine
```

Be precise about the identity. The signature is produced by the shared
reusable workflow in
[irondragonservices/.github](https://github.com/irondragonservices/.github),
not by a workflow in this repository, so the certificate names *that* path.
A looser pattern such as `^https://github.com/irondragonservices/` would
accept a signature from any workflow in any repository in the organisation,
which is a much weaker claim than it looks. The
`--certificate-github-workflow-repository` flag is what ties the signature back
to this repository.

Both `image-release` and `image-refresh` sign: the nightly rebuild republishes
when the package set has actually changed, and it signs what it pushes.

An SBOM and a provenance attestation ride along with every image:

```sh
docker buildx imagetools inspect ghcr.io/irondragonservices/iron-alpine:3 \
  --format '{{ json .SBOM }}'
```

## Update policy

Four mechanisms, because no single one of them sees everything. The details
are in [irondragonservices/.github](https://github.com/irondragonservices/.github).

- **Renovate** digest-pins the base image and auto-merges a new digest once the
  gate is green. Catches Alpine moving.
- **The pull request gate** — hadolint, a build on every architecture, and a
  vulnerability scan — is what makes that auto-merge safe.
- **A nightly cache-free rebuild** catches package updates that never moved the
  base image tag. It republishes only when the package set actually changed,
  because a rebuild changes the digest whether or not anything inside did.
- **A nightly re-scan of the published image** catches vulnerabilities
  disclosed after the build, which change nothing in this repository and would
  otherwise never be looked at again.

## Changes from upstream

- **The base packages are now upgraded, not just added to.** The step commented
  *update base system* only installed `ca-certificates`, so the image shipped
  whatever the base image tag happened to contain. Distributions patch a
  package well before they rebuild and republish the base image, so a digest
  pin — which is what Renovate maintains — pins the *unpatched* set until
  upstream gets round to a rebuild. `alpine:3.24.1` was carrying openssl
  3.5.7-r0 with a fixed HIGH against it and 3.5.8-r0 already in the repository.
  This is also what makes the nightly cache-free rebuild worth running: without
  it, that job rebuilt the same packages every night and picked up nothing.
- `post-install.sh` was missing from this repository entirely, so the image
  could not build — `COPY post-install.sh` had nothing to copy.
- `post-install.sh` now re-removes the dangerous applets and setuid bits that
  a derived image's `apk add` silently restores.
- Added `$TMP_DIR`. The README advertised `/app/tmp` and the example wrote a
  pid file into it, but nothing created it.
- The example could not start: it listened on 8443 with every
  `ssl_certificate` line commented out, logged to a directory the image does
  not create, never set `daemon off`, and pinned TLSv1 and TLSv1.1. It is now
  a minimal HTTP example that runs.
- `ENV key value` replaced with `ENV key=value`.
- The release workflow was rebuilt: it ran on `master` in a repository whose
  default branch is `main`, used `::set-output` and `actions/create-release`,
  both long dead, and authenticated as an account in another organisation.
