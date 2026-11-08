# debian-packages

Builds Debian packages from upstream source in GitHub Actions and publishes them
as a signed apt repository on GitHub Pages. Your machines then get updates with
a normal `apt upgrade`.

```
daily cron ─► check: newest stable upstream tag vs. what's published
                │  (nothing new → stop)
                ▼
              build: one job per package/arch, in a clean debian:trixie container
                │    → .deb → apt-installed into a fresh container + smoke test
                ▼
              publish: add to pool, keep last 2 versions, regenerate indexes,
                       sign with your key, deploy to https://<you>.github.io/<repo>/
```

Each package is one small bash file, `packages/<name>/recipe.sh`, laid out a lot
like an Arch PKGBUILD: some variables, then `build()` and `package()`.

## One-time setup

You need `git`, `gpg` and the [`gh`](https://cli.github.com/) CLI on your laptop.

1. **Make the GitHub repo** (public is best: Actions minutes are free and
   unlimited, and Pages on a private repo needs a paid plan. The repo only
   holds build recipes and open-source binaries.)

   ```sh
   cd debian-packages
   git init -b main && git add -A && git commit -m "Initial scaffold"
   gh repo create debian-packages --public --source . --push
   ```

2. **Make the signing key** and give the private half to GitHub:

   ```sh
   scripts/make-signing-key.sh
   gh secret set APT_SIGNING_KEY < keys/signing-key.private.asc
   # keep an offline backup if you like, then:
   shred -u keys/signing-key.private.asc
   git add keys/ && git commit -m "Add repo signing key" && git push
   ```

   The public key is committed under `keys/`. The publish step checks that the
   secret matches it, so a wrong key fails loudly.

3. **Turn on Pages**: repo **Settings → Pages → Build and deployment →
   Source: GitHub Actions**.

4. **Run it once by hand**: **Actions → Build packages → Run workflow**, or
   `gh workflow run build.yml`. The first niri build takes about 10–15 minutes.
   After that the daily run takes seconds when there's nothing new.

## Using the repo on a machine

Install the key from your own checkout. Don't download it from the Pages site,
because then you'd be trusting whatever the site serves.

```sh
sudo install -m644 keys/archive-keyring.gpg /usr/share/keyrings/selfbuilt.gpg

sudo tee /etc/apt/sources.list.d/selfbuilt.sources <<'EOF'
Types: deb
URIs: https://<you>.github.io/debian-packages/
Suites: trixie
Components: main
Signed-By: /usr/share/keyrings/selfbuilt.gpg
EOF

# Recommended: your repo can add new packages but can never replace a Debian one.
sudo tee /etc/apt/preferences.d/selfbuilt <<'EOF'
Package: *
Pin: release o=selfbuilt
Pin-Priority: 100
EOF

sudo apt update && sudo apt install niri
```

With that pin, niri installs and upgrades from your repo as normal, because
Debian doesn't ship it. But if your repo ever served a `libc6` or `openssh-server`,
Debian's copy would still win.

**Automatic upgrades (optional).** If you use `unattended-upgrades`, add your
origin:

```sh
echo 'Unattended-Upgrade::Origins-Pattern { "origin=selfbuilt"; };' \
  | sudo tee /etc/apt/apt.conf.d/52selfbuilt
```

On a machine with snapper's apt hook, every upgrade gets a pre/post snapshot
anyway, so a bad build is one rollback away.

## Adding a package

Copy `packages/niri/recipe.sh` to `packages/<name>/recipe.sh` and edit it. The
fields:

| Variable / function | What it does |
| --- | --- |
| `pkgname` | Must match the directory name. |
| `upstream_git` | Git URL. Used to find new tags and to clone. |
| `track` | `tags` (default) builds the newest tag matching `tag_regex`. `branch` builds the head of `branch`. |
| `tag_regex` | Which tags count as stable. The default `^v?[0-9]+(\.[0-9]+)+$` skips `-rc`, `-beta`, `tip`, etc. |
| `require_green_ci` | Branch mode only: build the newest of the last 20 commits whose GitHub checks all passed. |
| `pkgrel` | Bump it after changing a recipe to force a rebuild of the same upstream version. |
| `arches` | `(amd64)` or `(amd64 arm64)`. arm64 runs on GitHub's free arm runners. |
| `build_depends` | apt packages installed before building. |
| `depends` / `recommends` / `suggests` / `provides` / `conflicts` / `replaces` | Go straight into the control file. Shared-library deps are worked out automatically by `dpkg-shlibdeps`, so `depends` only needs what that can't see (dlopen'd libraries, helper programs). |
| `version_from_tag()` | Turns a tag into a version. The default strips a leading `v`. |
| `fetch()` | Optional. The default clones the tag. Ghostty's recipe overrides it to download a minisign-verified release tarball instead. |
| `build()` | Runs in the source dir. |
| `package()` | Install files into `$pkgdir` (e.g. `$pkgdir/usr/bin/foo`). |
| `smoke_test()` | Runs after the .deb is apt-installed into a clean container. A good one is `foo --version`. |

Helpers you can call: `ensure_rust` uses Debian's rustc if it meets the crate's
`rust-version`, and installs the stable toolchain with rustup if not.
`ensure_zig <ver>` downloads that exact Zig release and verifies its signature.
`fetch_minisigned <url> <pubkey> <out>` downloads a file and checks its signature.

Files under `/etc` are marked as conffiles automatically. Put `postinst`,
`prerm`, etc. next to the recipe if a package needs them.

Commit and push. Changing anything under `packages/` starts a run right away.

**Version numbers** look like `26.04-0local1`. The `-0…` revision sorts below
Debian's own `-1`, so if Debian ever packages the same version, apt prefers
Debian's. Branch builds look like `26.04+git202611071830.da0ab81-0local1`, which
sorts after 26.04 and before 26.05.

## Building locally

Same container and scripts as CI, using podman (or docker):

```sh
scripts/local-build.sh niri            # newest stable tag
scripts/local-build.sh niri v25.11     # a specific tag
# → out/niri_26.04-0local1_amd64.deb, then installed into a fresh container and smoke-tested
```

`scripts/check-updates.sh` prints what CI would build next.

## The packages included

- **niri**: enabled. Builds with Debian trixie's own Rust (niri 26.04 needs
  1.85, which is what trixie ships), and installs the session files,
  systemd user units, portal config and shell completions as upstream's
  packaging guide lists them. The binary isn't stripped, because upstream asks
  packagers to keep line tables so panic backtraces are useful.
- **ghostty**: included but `enabled=false`. Ghostty's build needs a
  specific Zig release that I couldn't download where this was written, so it
  hasn't been test-built. To try it, set `enabled=true`, push, and watch the run.
  You can also run the workflow by hand with `package: ghostty` (that works
  even while it's disabled).

## Things to know

- **GitHub pauses cron in quiet public repos.** If a public repo has no activity
  for 60 days, GitHub disables its scheduled workflows. You get an email first,
  and re-enabling takes one click on the Actions tab. Any push resets the clock.
- **Size limits.** GitHub Pages sites are capped at 1 GB, and git rejects files
  over 100 MB. Keeping 2 versions of each package stays far under that. A very
  large package (OrcaSlicer's .deb can get near 100 MB) would need hosting
  somewhere else.
- **History stays small.** The `gh-pages` branch is rewritten as a single commit
  on each publish, so old .debs don't pile up in git.
- **What you're trusting:** upstream's git tags (or signed tarballs where a
  recipe uses them), GitHub's runners, Debian's archive for build deps, and
  whoever can get at your repo's secrets. Turn on 2FA, and don't add other
  people as collaborators unless you mean it.
- **Moving to Debian 14 (forky):** change `SUITE` in `config.sh` and the
  `container:` lines in the workflow, run with `force`, and update `Suites:`
  on your machines.
- **Build failures** don't block other packages. Whatever succeeded still gets
  published, and the failed one is retried on the next run.
