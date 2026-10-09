# Opening the right ports (the #1 reason these builds fail)

IceVPN needs ports open in **TWO separate places**. Miss either one and your
clients cannot connect. This trips up almost everyone on Oracle Cloud.

Default ports used by bootstrap.sh:
- SSH: `22/tcp`
- Management API: `25565/tcp`
- Access keys (Shadowsocks): `44444/tcp` and `44444/udp`

## Layer 1: The OS firewall (handled for you)

`bootstrap.sh` runs `ufw` and opens the four rules above. You do not touch this
layer. The script does it and it is fail-closed (deny all in, allow the four).

## Layer 2: The cloud provider firewall (you must do this by hand)

Oracle Cloud (and most providers) run a firewall OUTSIDE the VM. On OCI this is
the **Security List** on your VCN subnet, plus a **Network Security Group (NSG)**
on the VM. Both must allow the ports or traffic dies at the edge.

### Oracle Cloud Console

1. **Networking > Virtual Cloud Networks** > your VCN > **Subnets** > click your
   subnet > **Security Lists** > **Add Ingress Rules**.

2. Add these. Use `0.0.0.0/0` for the VPN ports so clients can connect from
   anywhere. Lock SSH and the management port to your own IP if you can.

| Source CIDR | Protocol | Dest Port | Purpose |
|-------------|----------|-----------|---------|
| your-ip/32 | TCP | 22 | SSH (lock this down) |
| your-ip/32 | TCP | 25565 | Management API (lock this down) |
| 0.0.0.0/0 | TCP | 44444 | Access keys TCP |
| 0.0.0.0/0 | UDP | 44444 | Access keys UDP |

3. If the VM is also in a **Network Security Group**, add the SAME rules there
   (Networking > Network Security Groups > your NSG > Add Ingress Rules).

### Other providers

- **Hetzner / Vultr / DigitalOcean / Linode**: they have a cloud firewall too.
  Open the same four rules there. On Hetzner this layer is the main one.
- **Oracle specifically**: always check BOTH the Security List and the NSG.

## Test before you trust it

From a device on **cellular data** (not your own Wi-Fi, or you test nothing):

1. Import the `ss://` link into the Outline client.
2. Turn it on, load a site.
3. Confirm your public IP changed at https://ipinfo.io.
4. Confirm no DNS leak at https://dnsleaktest.com.

Connect works but pages do not load -> almost always Layer 2 (cloud firewall).
Will not connect at all -> the IP or port in the `ss://` link does not match what
you opened.
