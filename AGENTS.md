# AGENTS.md

Builds an official-branded, patched Firefox on Linux x86_64 from mozilla-central sources, inside a Fedora 44 docker container. Everything builds inside the container; the host only mounts volumes and installs the result.

## Layout

| Path         | Role (container mount)                          |
| ------------ | ----------------------------------------------- |
| `firefox/`   | mozilla-central git clone, root-owned (`/src/firefox`) |
| `firefox/obj-firefox` | build dir (clobbered via `AUTOCLOBBER=1`) |
| `mozconfig`  | build config (`/src/mozconfig`, picked up via `MOZCONFIG` env) |
| `mozbuild/`  | toolchain/indices cache (`/root/.mozbuild`)     |
| `sccache/`   | rust sccache cache (`/root/.cache/sccache`)     |
| `patches/`   | custom `.patch` files + `config.yml` (saved yes/no answer per patch) |
| `src/`       | helper scripts, copied into the image at `/src/bin/` |
| `dist/`      | output tarballs + build logs                    |

Image: `firefox-build:fedora` (see `Dockerfile`). Rebuild the image only when `Dockerfile` changed.

First-time setup (image build, initial source clone via `bootstrap.py`, `sudo mkdir` of `dist/ firefox/ mozbuild/`) is documented in `README.md` — in practice `firefox/` is already cloned.

## Build flow

All container commands need `export PATH="$PATH:/root/.cargo/bin:/root/bin"` first — `docker exec` does not load the shell profile, and `rustup`/`sccache` live in `/root/.cargo/bin`.

1. **Start container** (detached, tmux session survives):

   ```sh
   ./run-container.sh
   ```

   Always start it via `run-container.sh`, never with a bare `docker run`. The script sets `--oom-score-adj 1000`, so when the host runs out of memory the build (the gkrust `rustc` alone can exceed 18 GB) is killed first instead of desktop apps.

   Attach to watch: `docker exec -it firefox-build tmux attach -t build`.

2. **Prepare + checkout** (runs `rustup update`, `dnf update`, `git reset --hard`, `git fetch --all`, tag checkout, `mach bootstrap`). It prompts `Select tag to checkout:` — pipe the tag in. **Must run from `/src/firefox`** (container default cwd is `/src`):

   ```sh
   docker exec -i firefox-build bash -c \
     'export PATH="$PATH:/root/.cargo/bin:/root/bin"; cd /src/firefox && printf "FIREFOX_156_0_RELEASE\n" | bash /src/bin/build-prepare.sh' > dist/build-156-prepare.log 2>&1
   ```

   Done when `browser/config/version.txt` inside the container shows the expected version. **`git reset --hard` wipes previously applied patches — always re-run step 3 after step 2.**

3. **Apply patches**: `docker exec firefox-build bash -c 'cd /src/firefox && python3 /src/bin/apply-patches.py'`. Non-interactive when every patch name has an answer in `patches/config.yml`. Done when `git status` in `/src/firefox` shows exactly the patched files, nothing else.

4. **Build** (hours; run detached, log to the mounted `dist/`):

   ```sh
   docker exec -d firefox-build bash -c \
     'export PATH="$PATH:/root/.cargo/bin:/root/bin"; cd /src/firefox && bash /src/bin/build.sh > /dist/build-156.log 2>&1'
   ```

   `build.sh` = `nice -n 15 ./mach build` → stamps `MOZ_SOURCE_STAMP` into `obj-firefox/source-repo.h` (run once per fresh objdir) → `./mach package` → rsyncs the tarball to `dist/`. Done when `dist/firefox-<ver>.en-US.linux-x86_64.tar.xz` exists and `dist/build-*.log` ends without errors.

5. **Verify** (in container): `/src/firefox/obj-firefox/dist/firefox/firefox --version`.

6. **Install** (host, **user-run — the agent's work ends at step 5**): the user runs `./install.sh`, which extracts into `~/bin/<version>/`, symlinks `~/bin/firefox`, and installs the desktop file.

## Finding the version to build

```sh
docker exec firefox-build bash -c 'cd /src/firefox && git fetch --all && git tag -l "FIREFOX_*_RELEASE" | grep -v BUILD | sort -V | tail -10'
```

Release tags may appear on the remote (github.com/mozilla-firefox/firefox mirror) only a little after the release ships — if the expected tag is missing, `git fetch --all` first before concluding it does not exist.

## Gotchas

- **Patch failures on new versions are normal** — upstream moves files between releases. `apply-patches.py` applies each patch with `git apply`, which is atomic per patch file: one hunk failing aborts the whole patch (even hunks that would have applied). To fix: edit the file(s) in the container, then regenerate with `git diff -- <files> > /src/patches/<name>.patch` and validate with `git apply --check -R /src/patches/<name>.patch`.
- **`firefox/` is root-owned** (created with `sudo` during initial setup). Host-side file writes fail with PermissionDenied; edit via `docker exec` (container runs as root) or `sudo`.
- Host-side git on `firefox/` reports `dubious ownership`; use the container for git, or `git config --global --add safe.directory <path>`.
- **rustup `Invalid cross-device link (os error 18)`** during `rustup update` is an overlayfs rename bug, often on a stale `etc/bash_completion.d` component. Fix: `rustup toolchain uninstall stable && rustup toolchain install stable` (run in container).
- **Build OOM-killed** (exit 137, `Out of memory: Killed process ... (rustc)` in `journalctl -k`): the host ran out of memory. Lower `JOBS` in `mozconfig`.
- `mozconfig` sets `AUTOCLOBBER=1`: a version checkout clobbers `obj-firefox` (full rebuild). `JOBS` is `nproc-4` when `nproc >= 8`. `RUSTC_WRAPPER`/`--with-ccache` point at sccache; an empty `sccache/` means a cold cache.
- Keep build logs in `dist/` (mounted, survives container removal), not in container-local paths.
- Patches in `patches/` are the CompileNix customizations (ui tour, urlbar select-all, ...). `config.yml` is the applied/not-applied state — keep it in sync when adding or dropping a patch.
