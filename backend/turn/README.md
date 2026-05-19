# Rain Self-Hosted TURN Broker

This folder contains the zero-cost relay path for Rain: Coturn plus a tiny credential broker on an Oracle Always Free VM.

## Runtime Shape

- Coturn listens on `3478/udp`, `3478/tcp`, and `5349/tcp`.
- Caddy terminates HTTPS for `https://rain-p2p-turn.duckdns.org/rainTurnCredentials`.
- The Node broker verifies Firebase Auth ID tokens and returns short-lived Coturn REST/HMAC credentials.
- The app receives STUN-first ICE servers plus authenticated TURN URLs. The Coturn shared secret never ships in APK/EXE artifacts.

## Oracle VM Checklist

Create an Ubuntu ARM VM and open these OCI ingress rules:

- `22/tcp` from your IP for SSH
- `80/tcp` and `443/tcp` for Caddy and Let's Encrypt
- `3478/udp` and `3478/tcp` for STUN/TURN
- `5349/tcp` for TURNS
- `49160-49300/udp` for TURN relay traffic

Also allow the same ports in the VM firewall:

```bash
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 3478/udp
sudo ufw allow 3478/tcp
sudo ufw allow 5349/tcp
sudo ufw allow 49160:49300/udp
sudo ufw enable
```

## Deploy

1. Point DuckDNS `rain-p2p-turn.duckdns.org` to the Oracle public IP.
2. Run `sudo bash backend/turn/scripts/install_ubuntu.sh` on the VM.
3. Copy this folder to `/opt/rain-turn-broker`.
4. Run `npm ci --omit=dev` in `/opt/rain-turn-broker`.
5. Copy `backend/turn/env.example` to `/etc/rain-turn-broker.env` and replace placeholders.
6. Copy `backend/turn/coturn/turnserver.conf.template` to `/etc/turnserver.conf` and replace placeholders. Use the VM private IP for `listening-ip` and `relay-ip`, and `public/private` format for `external-ip`.
7. Copy `backend/turn/caddy/Caddyfile` to `/etc/caddy/Caddyfile`.
8. Copy both systemd unit files to `/etc/systemd/system/`.
9. Install a Firebase service account JSON at `/opt/rain-turn-broker/firebase-service-account.json`.
10. Start services:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now caddy
sudo systemctl enable --now coturn-rain
sudo systemctl enable --now rain-turn-broker
```

## Smoke Checks

Unauthenticated broker calls must return `401`:

```bash
curl -i -X POST https://rain-p2p-turn.duckdns.org/rainTurnCredentials
```

Service health:

```bash
sudo systemctl status rain-turn-broker
sudo systemctl status coturn-rain
sudo journalctl -u rain-turn-broker -n 100 --no-pager
sudo journalctl -u coturn-rain -n 100 --no-pager
```

After the broker returns `401`, set GitHub `RAIN_RELEASE_DART_DEFINES_JSON` to use `RAIN_TURN_BROKER_URL=https://rain-p2p-turn.duckdns.org/rainTurnCredentials`, then rerun CI/CD.

## Cost and Capacity Ceiling

The template caps Coturn at `max-bps=512000` per session and limits relay ports to `49160-49300/udp`. That range is 140 ports, which is about 70 concurrent relayed sessions because TURN commonly needs two relay ports per peer pair. At 512 Kbps, one continuously relayed session uses roughly 230 MB/hour.

Oracle's Always Free outbound allowance is generous, but not infinite. Add an OCI budget alert around 7 TB/month and move to paid or managed TURN when relay usage approaches either the egress limit or the relay-port ceiling.

The template also blocks relaying to private RFC1918 peer ranges with `denied-peer-ip`, and keeps `no-loopback-peers` plus `no-multicast-peers` enabled to reduce abuse risk.
