# Runs on the Hermes server, fed to `bash -l -s` by connect.sh. Turns on Hermes' API server
# bound to this machine's Tailscale address, with a fresh key unless one is set, restarts
# the gateway if anything changed, and prints the key after an ORBKEY= marker (the login
# shell may print other things; connect.sh only reads the marked line).

env_file="$HOME/.hermes/.env"
mkdir -p "$HOME/.hermes"
touch "$env_file"
chmod 600 "$env_file"

ip=
if ! grep -q '^API_SERVER_HOST=.' "$env_file"; then
  ip=$(tailscale ip -4 2>/dev/null | head -n 1)
  if [ -z "$ip" ]; then
    echo "ORBERR=no-tailscale-ip"
    exit 1
  fi
fi

changed=
if ! grep -q '^API_SERVER_ENABLED=true' "$env_file"; then
  echo 'API_SERVER_ENABLED=true' >> "$env_file"
  changed=1
fi
if [ -n "$ip" ]; then
  echo "API_SERVER_HOST=$ip" >> "$env_file"
  changed=1
fi
if ! grep -q '^API_SERVER_KEY=.' "$env_file"; then
  echo "API_SERVER_KEY=$(openssl rand -hex 32)" >> "$env_file"
  changed=1
fi

if [ -n "$changed" ]; then
  hermes gateway restart > /dev/null 2>&1 || echo "ORBERR=restart-failed"
fi
sed -n 's/^API_SERVER_KEY=/ORBKEY=/p' "$env_file" | tail -n 1
