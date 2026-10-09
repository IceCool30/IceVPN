# IceVPN

Your own VPN, built on the same open source engine the strong providers use.
Outline is made by Jigsaw, it is Apache 2.0 licensed, and it ships official
client apps for Android, iPhone, Windows, and Mac. You run the server, you own
the data, and you can rebrand all of it and make it your own.

This repo is a complete, deployable kit. One script turns a fresh Ubuntu VPS into
a hardened VPN server with a free + paid tier.

## What's in here

| Path | What it is |
|------|------------|
| `scripts/bootstrap.sh` | Turns a fresh Ubuntu VPS into a hardened Outline server. Pins ports, installs it, opens a fail-closed firewall, prints your access JSON. |
| `scripts/tier-manager.sh` | Your paywall engine. Creates free keys with a data cap, unlimited paid keys, upgrades, revokes, reports usage. |
| `scripts/test-connection.sh` | Checks your IP, pings the API, points you at the leak tests. |
| `tests/test-tier-manager.sh` | Unit tests for the tier logic. Run with `bash tests/test-tier-manager.sh`. |
| `config/oci-firewall-guide.md` | The exact ports to open in Oracle Cloud. Read this or your build fails at Layer 2. |
| `docs/cost-and-limits.md` | What it costs to run, and how many users it supports. |
| `.env.example` | Copy to `.env` and fill in. Never commit the real one. |

## Prerequisites

- A fresh Ubuntu 22.04 or 24.04 VPS. Oracle Cloud Always Free works and costs $0.
- SSH access as root or a sudo user.
- 15 minutes.

## Deploy in three steps

### 1. Open the cloud firewall first

Before running anything, open the ports in your provider's cloud firewall.
Oracle uses two layers. Follow `config/oci-firewall-guide.md` now, not later.
Default ports: SSH 22, management 25565, keys 44444 (TCP and UDP).

### 2. Install the server

```bash
scp -r IceVPN user@YOUR_VPS_IP:~/
ssh user@YOUR_VPS_IP
cd IceVPN
sudo bash scripts/bootstrap.sh
```

It prints a green JSON block:

```json
{"apiUrl":"https://YOUR_IP:25565/S3cr3tPath","certSha256":"AB12..."}
```

Copy it. That is your admin key to the server. Treat it like a root password.

### 3. Run your tiers

```bash
export ICEVPN_API_URL='https://YOUR_IP:25565/S3cr3tPath'

# Free key with a 5 GB cap
./scripts/tier-manager.sh free "$ICEVPN_API_URL" alice-free

# Paid key, unlimited
./scripts/tier-manager.sh paid "$ICEVPN_API_URL" bob-paid

# Alice pays. Lift her cap (this is the upgrade trigger):
./scripts/tier-manager.sh uncap "$ICEVPN_API_URL" 0

# See who is using what
./scripts/tier-manager.sh usage "$ICEVPN_API_URL"

# Revoke a user
./scripts/tier-manager.sh delete "$ICEVPN_API_URL" 0
```

Each command prints an `ss://` link you hand to the user's client app.

## Client apps (all official, all free)

- **Android:** Google Play "Outline", or the APK on getoutline.org
- **iPhone/iPad:** App Store "Outline"
- **Windows/Mac/Linux:** getoutline.org download, or the Outline Manager app

Each user opens the app, pastes their `ss://` key, and connects.

## Verify it works

```bash
./scripts/test-connection.sh "$ICEVPN_API_URL"
```

Then connect a client on cellular data and confirm your IP changed at ipinfo.io
and DNS does not leak at dnsleaktest.com.

## Security notes, straight

- The `apiUrl` is a root-password-level secret. Anyone with it controls your
  server. It is in `.gitignore` for a reason. Do not commit it, do not paste it
  in public.
- The scripts use `--insecure` because the API cert is self-signed and the secret
  in the URL path is the real auth. To harden, pin `certSha256` or use `--cacert`
  instead of disabling verification.
- Lock SSH (22) and the management port (25565) to your own IP in the cloud
  firewall if you can. Leave only the keys port (44444) open to the world.
- One VPS is a single point of failure and a single exit IP. That is the honest
  ceiling of a one-box build. See `docs/cost-and-limits.md`.

## Wiring in real payments later

`tier-manager.sh` is built to be called by a payment webhook:

- New free signup -> `free`
- Payment confirmed -> `uncap <id>`
- Refund or ban -> `delete <id>`

Outline does not handle billing. That is intentional, it keeps the server clean
and lets you pick your processor. Remember the payment risk from the cost
breakdown: crypto via BTCPay is the path that will not freeze on a VPN business.

## License

The scripts in this repo are yours. Outline itself is Apache 2.0, so you can
rebrand the server and clients and sell access if you want. Check the Outline
license before you ship anything commercial.
