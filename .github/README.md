# dotfiles

## mothership VM (NixOS)

Fresh VM:

```bash
nix run nixpkgs#chezmoi -- init --apply shadowe1ite
```

### Interceptor desktop

Installed by chezmoi. Start it in tmux, then open http://neo:6080/vnc.html

```bash
tmux new -s desk desk
```

### Hermes Agent

Install manually (chezmoi only provides `~/.hermes/config.yaml` for OmniRoute and the `hermes` alias):

```bash
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash -s -- --skip-browser --skip-computer-use
```

If the installer already created a config, set the model section to:

```yaml
model:
  provider: custom
  base_url: http://amd:20128/v1
  key_env: OMNIROUTE_API_KEY
  default: amd/DeepSeek-V4.1-Flash
```

### Reset to fresh

The system is rebuilt on every boot; only `/persist` survives. Back up anything you need first.
Never touch `/persist/tailscale` or `/persist/tailscale.authkey` (mesh identity, otherwise the VM re-joins as `alan-1`).

On the VM:

```bash
nix profile remove --all
sudo find /persist/home -mindepth 1 -delete
sudo reboot
```

After it's back, free the store overlay. Only delete paths that aren't in the host's read-only store;
don't use `nix-collect-garbage`, which can hide host paths in the persistent overlay.

```bash
nix-store --gc --print-dead 2>/dev/null | while read p; do
  [ -e "/nix/.ro-store/${p#/nix/store/}" ] || nix-store --delete "$p"
done
```

Elsewhere:

- client: `ssh-keygen -R neo`
- Tailscale admin console: Machines → `neo` → Remove

Then set it up again with the **Fresh VM** command above.
