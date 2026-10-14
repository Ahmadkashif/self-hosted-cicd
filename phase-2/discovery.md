# Phase 2: Discovery (version and schema re-check, 2026-10-14)

Read-only web/API research. Raw artifacts: `phase-2/raw/` (`INDEX.txt`). Sources S200–S238 (appended to `../sources.md`).
Lab cross-checks done in Phase 3 are marked **[lab]**.

## 1. Forgejo
| Item | Pinned | Latest (date) | Action |
|---|---|---|---|
| v15 LTS | `15-rootless` | **v15.0.10** (2026-10-12); `15-rootless` = `15.0.10-rootless` (same digest) [S200][S203] | Keep; pin `15.0.10-rootless` for reproducibility |
| v16 | – | v16.0.6 (2026-10-12), non-LTS, **EOL 2026-10-29** [S200][S201] | Don't adopt |
| v17 | – | scheduled 2026-10-15, EOL 2027-01-28 [S202] | Ignore |
| v15 LTS end | 2027-07-15 | confirmed [S201][S202] | – |

Rootless image (v15.0.10 = v16.0.6) [S204]: `USER 1000:1000`, `EXPOSE 2222 3000`, curl installed (healthcheck OK),
`GITEA_WORK_DIR=/var/lib/gitea`, `GITEA_APP_INI=/var/lib/gitea/custom/conf/app.ini` (so the template's single
`/var/lib/gitea` volume does persist app.ini and its generated secrets).

Automatic token vs packages [S205][S206]: `services/packages/perm.go` has `// TODO: ActionUser permission check`;
the Actions user gets at most read. **`GITHUB_TOKEN`/`FORGEJO_TOKEN` cannot push packages** in v15/v16. Push needs a PAT
with `write:package`. v16 adds `ActionTaskToken` / "Authorized Integrations" as package auth (v16 only).

v16 changes [S207][S208]: image no longer defaults `REVERSE_PROXY_TRUSTED_PROXIES=*`; mirrors don't follow redirects;
centralised hooks; warnings for unsupported `permissions:`; server-side `if`; new run/log/artifact APIs.
`forgejo-cli actions register` unchanged: `--secret --scope --labels --keep-labels --name --version --ephemeral` [S209].
The cache is held by the runner, never by Forgejo [S212].

## 2. Forgejo Runner
| Item | Pinned | Latest | Action |
|---|---|---|---|
| Image | `data.forgejo.org/forgejo/runner:13` | **v13.2.0** (2026-09-18) [S210][S203] | Keep / pin 13.2.0 |
| UID | 1001 (template) | **1000:1000**, `HOME=/data` [S211]; confirmed **[lab]** `id` in image | Template forces 1001: works only with a chown; changed to 1000 |

v13.0.0 breaking (2026-08-03) [S213]: invalid syntax/expressions are hard errors; `set-output`/`set-env`/`add-path`
removed (use `$FORGEJO_OUTPUT`/`$FORGEJO_ENV`/`$FORGEJO_PATH`); `DOCKER_USERNAME/PASSWORD` secrets unused (use
`container.credentials`); **Docker ≥ 25**; `container.network_mode` removed; `GITEA_RUNNER_*` env ignored; `gitea.*` context gone.

Config schema (v13.2.0 `config.example.yaml`, and **[lab]** `forgejo-runner generate-config` from the image) [S214]:
`server.connections.<name>.{url, uuid, token | token_url, labels, fetch_interval}` is real; `token_url: file:` with
`$CREDENTIALS_DIRECTORY`; `cache.{enabled,dir,port,host,proxy_port,external_server,secret,secret_url,actions_cache_url_override}`;
`container.{network,enable_ipv6,privileged,options,workdir_parent,valid_volumes,docker_host,force_pull,force_rebuild}`.

Registration [S212][S215]: `forgejo forgejo-cli actions register --name N --scope S --secret <40 hex>` on the forge;
first 16 chars = runner id, last 24 = secret; prints a UUID. On the runner: `url`, `uuid`, `token`/`token_url` = full
40-char secret. `forgejo-runner register` / `create-runner-file` are deprecated.

JS actions: the runner executes `node <main>` **inside the job container** [S216] → job images need Node (24 for
checkout v7 / cache v6 ESM builds).

## 3. actions/checkout — SHAs identical on github.com, data.forgejo.org, code.forgejo.org [S217]
| Tag | SHA | Date | Node |
|---|---|---|---|
| v6.0.2 (pinned) | `de0fac2e4500dabe0009e67214ff5f5447ce83dd` | 2026-01-09 | node24 |
| v6.1.0 | `d23441a48e516b6c34aea4fa41551a30e30af803` | 2026-07-20 | node24 |
| v7.0.1 | `3d3c42e5aac5ba805825da76410c181273ba90b1` | 2026-07-20 | node24 |

v6.1.0 is [BREAKING]: backports `allow-unsafe-pr-checkout` (blocks fork-PR checkout under `pull_request_target`/`workflow_run`)
plus security fixes [S218][S219]. **Action: bump to v6.1.0.**

## 4. actions/cache — SHAs identical on all three hosts [S217]
| Tag | SHA | Date | Node |
|---|---|---|---|
| v4.3.0 (pinned) | `0057852bfaa89a56745cba8c7296529d2fc39830` | 2025-09-24 | **node20** |
| v5.1.0 | `caa296126883cff596d87d8935842f9db880ef25` | 2026-06-26 | node24 |
| v6.1.0 | `55cc8345863c7cc4c66a329aec7e433d2d1c52a9` | 2026-06-26 | node24, ESM |

All select protocol by `ACTIONS_CACHE_SERVICE_V2 ? v2 : v1` [S221]. Runner v13.2.0's cache server implements only the
legacy v1 REST API (`/_apis/artifactcache/...`) [S222] and sets `ACTIONS_CACHE_URL` (+ `ACTIONS_RESULTS_URL`), never
`ACTIONS_CACHE_SERVICE_V2` [S223]. So all three should work over v1 (lab test: Q6).

## 5. Kamal
Kamal **v2.12.0** (2026-06-18) still latest [S224]; kamal-proxy **v0.10.2** (tag 2026-10-06) [S225].
Schema unchanged for `proxy.healthcheck.{path,interval,timeout}`, `registry.*`, `builder.arch`, `ssh.user` [S226].
`kamal deploy --skip-push --version` valid; `kamal rollback VERSION` needs that version's container still on the host [S227].
No registry-CA/insecure option in Kamal: hosts and the builder's dockerd must trust the CA (`/etc/docker/certs.d`).

## 6. Hook tooling
| Tool | Pinned | Latest | Action |
|---|---|---|---|
| pre-commit-hooks | v6.0.0 | v6.0.0 | keep |
| gitleaks | v8.30.1 | v8.30.1 | keep |
| actionlint | v1.7.12 | v1.7.12 | keep |
| zizmor-pre-commit | v1.30.1 | v1.30.1 | keep |
| prek | – | v0.5.5 (2026-10-05) | pin 0.5.5 |
| go-task | 3.53.1 | v3.54.0 (2026-10-01) | bump (optional) |
[S228]. prek supports `install --hook-type` (repeatable) and `default_install_hook_types` [S229].

## 7. Images
| Image | Pinned | Latest | Action |
|---|---|---|---|
| caddy | 2 | 2.11.7 | keep |
| registry | 3 | 3.1.2 | keep |
| docker dind | 28-dind | `28-dind` frozen at 28.5.2 (2025-11-05); only 29.x maintained; 29.9.0 (2026-10-08) | **bump to 29-dind** |
| postgres | 17 | 17.11 | keep |
[S230]–[S233]

## 8. Claude Code hooks [S234]
- **`args` exists**: with `args`, `command` is exec'd without a shell (exec form); without it, `command` runs via `sh -c`.
  The template's `args: ["stop"]` form is therefore valid (lab test: Q10).
- Stop input: `session_id`, `stop_hook_active`, `last_assistant_message`, …; PreToolUse: `tool_name`, `tool_input.command`.
- Exit 2: PreToolUse blocks the call; Stop prevents stopping. Stop continuations are capped at 8 in a row.
- `CLAUDE_PROJECT_DIR` is exported to hooks.

## 9. Gitea (reference)
Gitea moved from 1.27.x to **v28** (v28.0.0 2026-09-29, v28.1.0 2026-10-06); last 1.x is 1.27.3. Runner moved to
`gitea.com/gitea/runner` v5.1.0 [S235][S236].

## 10. registry:3 pull-through
Docker Hub only, one upstream, must be a domain root [S237]; proxy mode is read-only (push unsupported) [S238].

## Corrections to Mac claims
1. Runner image UID is 1000, not 1001.
2. `server.connections` is the v13 schema; `.runner`-file registration is deprecated.
3. Offline registration: runner token = full 40-char secret; uuid = printed by `forgejo-cli actions register`.
4. Automatic token cannot push packages (v15/v16): confirmed from source (lab test Q7).
5. v16 is not a target (EOL 2026-10-29); stay on v15 LTS.
6. checkout v6.0.2 superseded by v6.1.0/v7.0.1 (security fixes).
7. cache v4.3.0 is node20; all versions use the v1 protocol against the runner cache.
8. `docker:28-dind` is unmaintained; use `29-dind`.
9. `::set-output` etc. break on runner v13.
10. Task latest 3.54.0; Kamal 2.12.0 still latest; kamal-proxy v0.10.2.
11. Gitea version scheme is now v28.x.
