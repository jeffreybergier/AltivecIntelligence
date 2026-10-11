# altivec-release

A dependency-free Node >=22 CLI. Prepare versions and build artifacts in Docker
without a Git identity, credentials, remote, or even a `.git` directory. Commit
and publish separately on your host.

From the AltivecIntelligence checkout, install the package locally:

```sh
npm pack ./packages/altivec-release
npm install -g ./altivec-release-1.0.0.tgz
```

The image installs this same pinned package during its build. No command downloads
a helper. The npm package is ready for distribution; installing the local tarball
does not require an npm registry publication.

Copy `example.json` to `.altivec-release.json` at the project root and edit the
paths and targets. Add `build/` to `.gitignore`. Paths resolve from the config;
keep it at the Git checkout root if you will use commit/push.

```sh
# Docker, with the project mounted from the host:
altivec-release doctor
altivec-release current --json
altivec-release prepare patch --dry-run
altivec-release prepare patch
altivec-release build --target iOS
altivec-release stage

# Host, after reviewing git diff and build/release/plan.json:
altivec-release commit
# Only when you want to publish:
altivec-release push
```

`prepare`/`set`/`current`/`check`/`ci-env`/`build`/`stage` never invoke Git.
Build actions are project-defined; a configured action that invokes Git or the
network still needs its own prerequisites. `doctor` uses only local Git commands
unless you pass `--check-remote`. Missing identity or credentials are normal in
Docker. All commands support `--help`, `--version`, and `--dry-run`;
`doctor`, `current`, `check`, and `ci-env` support `--json`. Dry runs never write
release files or invoke builds, commits, or network operations.

## Configuration and migration

Use `schema_version: 1`. The included example documents the basic shape.
`version.source` defaults to a UTF-8 XML plist. `version.source_key` selects its
version key; `version.keys` defaults to `CFBundleShortVersionString` and
`CFBundleVersion`. `version.plists` accepts paths or `{ "path": "...", "keys":
["CFBundleVersion"] }` entries. The source/key must be included in that list.
The updater validates the whole supported XML structure before editing top-level
string values, preserving unrelated formatting. Binary plists, custom entities,
CDATA, duplicate keys, symlink paths and unsupported XML forms are rejected
before version files change. Convert binary plists to XML once with your host's
plist tooling.

For CLI, library, or website projects, use a plain version file:

```json
{
  "schema_version": 1,
  "version": { "source": "VERSION", "format": "text", "plists": [] }
}
```

`VERSION` contains a numeric version such as `1.2.3`. Text sources may also
update configured XML plists. Supported versions have one to three numeric
components; `major`, `minor`, and `patch` produce three components.

Targets retain `name`, `workdir`, `artifact`/`asset_name` or multiple `artifacts`.
Use build actions such as `{ "exec": "make", "args": ["release"] }`. Shell
pipelines must be explicit `{ "shell": "make clean && make release" }` actions.
Asset names support `{app_name}`, `{version}`, `{tag}`, and `{target}`.
`versioned_files` explicitly includes additional reviewed files in the release
commit; the helper does not rewrite their content.

Migrate existing YAML once, preferably inside the image's Python/PyYAML environment:

```sh
altivec-release migrate --config .altivec-release.yml --dry-run
altivec-release migrate --config .altivec-release.yml
```

Review the new JSON, update references and remove the old YAML. Migration keeps
build commands as explicit shell actions and sets `stage_dir: "dist"` to preserve
CI upload globs. Normal operation needs only Node, never Python/PyYAML. The old
`bump` command is a deprecated preparation alias; even without `--no-push` it
never commits, tags or pushes. Replace old callers with `prepare`, followed by
explicit host `commit` and `push` where appropriate.

New configs stage in `build/release/artifacts`. `--dist dist` preserves older
workflows. Staging creates `build/release/artifact-manifest.json` with versions,
targets, SHA-256 checksums and CI provenance when available. It validates every
source and destination before copying. Stage archive files (ZIP/IPA/DEB) for
bundles containing symlinks. Directory artifacts must contain regular files and
directories. Staging overwrites matching asset names but leaves other existing
assets alone; CI should start with a fresh staging directory.

## Review, identity and recovery

The plan contains the exact file list, before/after contents and checksums. Keep
it in the mounted checkout so the host can verify what the container prepared.
`commit` refuses changed version files/configuration, detached HEAD, conflicting
local tags and unrelated staged files. Unrelated unstaged edits remain untouched.
Once a commit attempt begins, its branch and base commit are recorded and checked
on retries. Local commit/tag never contacts the remote.

Host commits read your existing Git identity, or accept a one-command override:

```sh
altivec-release commit --name 'Your Name' --email 'you@example.com'
```

This sets both author and committer for that invocation and never changes global
Git settings. SSH keys/tokens authenticate publication; they do not provide an
author name/email. `doctor --check-remote` explicitly checks tag presence and
reports authentication/network errors separately from an absent tag. A readable
remote does not establish permission to push.

Retry the same failed command. A repeated `prepare` finishes interrupted writes
or reports the existing plan instead of bumping again. A repeated `commit`
resumes commit/tag creation; a repeated `push` resumes branch/tag publication.
Push uses non-forced refspecs to `origin` and never overwrites a conflicting tag.
After a completed local commit/tag, use `prepare patch --new-plan` to start the
next release and archive the previous plan. Commit or back up other work first;
a source-only preparation cannot record which Git branch you intended until the
first host commit attempt.

Commands that change release state use `build/release/.lock`. After a killed
process, confirm no release command is running, remove this empty lock directory,
and retry. Do not run simultaneous external Git/index edits during commit.
If an interrupted preparation finds a file changed beyond the plan's before/after
checksums, review and restore its intended contents from the plan before retrying.

## Optional container authentication

The preferred workflow requires no container Git setup. If you explicitly want
to commit/push there, supply identity with the flags above and credentials only
at runtime. Forward an SSH agent socket with `SSH_AUTH_SOCK` (Docker Desktop uses
its host-services agent socket; Linux can bind the host's socket), plus a reviewed
`known_hosts` file. Never copy a private-key directory into the image.

For an HTTPS GitHub remote, inject a token from the host environment with Docker's
`-e GH_TOKEN`, and configure an ephemeral container Git credential helper using
`gh auth git-credential`. For example, pass `GIT_CONFIG_COUNT=1`,
`GIT_CONFIG_KEY_0=credential.helper`, and
`GIT_CONFIG_VALUE_0='!gh auth git-credential'` to that container. This does not
configure SSH or commit identity, and no token belongs in a Dockerfile or config.
