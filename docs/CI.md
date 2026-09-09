# CI setup and verification

[The manifest](../.mechatron-prime/targets) selects the x86_64 Linux package
and prototype checks. Both attributes currently resolve to the same tested
derivation. Verify them locally with:

```sh
nix build .#packages.x86_64-linux.default .#checks.x86_64-linux.prototype --no-link
```

Mechatron needs a signed GitHub push webhook before it can run the manifest.
On Thelio, run this in Bash as `pmarreck`. The secret travels directly through
the pipe; do not print it separately or paste it into chat.

```bash
sudo bash -c 'set -u; source /etc/mechatron-prime/github-webhook.env; printf "%s\n" "$MECHATRON_GITHUB_WEBHOOK_SECRET"' \
  | /home/pmarreck/Code/mechatron-prime/scripts/provision-mechatron-webhooks \
      --owner pmarreck \
      --allowlist <(printf 'pmarreck/nix_ex\n') \
      --endpoint https://thelio-nixos.tail66c90.ts.net/hooks/github
```

This scopes provisioning to this repository. Adding `--dry-run` reviews the
hook without changing GitHub. A subsequent push to `yolo` triggers a build;
provisioning alone does not build an earlier commit.

From a tailnet machine with `mechatron-ci` installed, substitute the pushed
commit prefix for `SHA_PREFIX`:

```sh
mechatron-ci queue --project nix_ex --commit SHA_PREFIX --json
mechatron-ci log --project nix_ex --commit SHA_PREFIX --json
```

The README badge reports the latest accepted build. An exact-commit `PASS`
in the log is the completion evidence; a local build or a queued job is not.
