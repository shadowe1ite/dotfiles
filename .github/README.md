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
