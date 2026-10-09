# Cost and Limits

This is the part most guides skip. Here it is straight.

## Will it cost me anything to run?

**Software: $0.** Outline is open source (Apache 2.0). The client apps for
Android, iPhone, Windows, and Mac are free. `tier-manager.sh` is in this repo.
You are not paying for the VPN software itself.

**Server: $0 to a few dollars a month.** You need one small Linux VPS to be the
exit node. Two realistic paths:

- **$0/month: Oracle Cloud "Always Free."** You get real compute forever, no
  credit card charge if you stay inside the free limits. As of now that is up to
  2 AMD micro instances, or 1 Arm instance with up to 4 OCPU and 24 GB RAM, plus
  **10 TB/month of outbound data**. That is enough for personal use and a small
  group of users. This is the "costs nothing" answer, and it is real.
- **$4 to $12/month: a cheap paid VPS** (Hetzner, Vultr, DigitalOcean). Better
  reputation, no "out of capacity" surprises, and you can pick the region. This
  is what you upgrade to when you outgrow free.

**Domain: optional.** The VPN works on a raw IP. A domain ($10-15/year) is only
nicer for the client links, not required.

## Is it limited to just me, or can a few users use it?

**It supports many users, not just you.** That is the whole point of the design.
Outline gives every person their own access key (their own password and link),
and `tier-manager.sh` creates those keys with rules:

- **Free tier:** a key with a data cap (default 5 GB). Hit the cap, connection
  stops until the cap resets or you lift it.
- **Paid tier:** a key with no cap (unlimited).
- **You** keep the admin key through the Outline Manager, which controls
  everything.

So "just me" is one key. "Me plus friends" is a handful of keys. You can hand
out dozens of keys on one server before you feel any strain.

## What actually limits how many users?

Two things, in order:

1. **Bandwidth, not CPU.** Shadowsocks is light on CPU. The wall you hit first is
   data transfer. On Oracle's free 10 TB/month, if each user streams ~2 TB/month
   (like a heavy streamer), that is roughly 5 heavy users, or many more light
   users who just browse. One person: you will never notice the limit.
2. **One IP, one location.** All your users share one server in one country. That
   is fine for privacy from your ISP and for security on public Wi-Fi. It is not
   great if users need to appear in many countries or need the crowd-hiding that
   a big commercial provider offers.

## The honest ceiling

This build is strong on the things that matter most for personal and small-group
use:

- Same modern crypto the top providers use (Shadowsocks with chacha20 or AES).
- True no-logs, because you own the box. No company can be compelled to hand
  over data that never existed.
- Hardened, fail-closed firewall. Auto security updates. fail2ban on SSH.

The honest limits, so you are not surprised:

- **One server = one point of failure and one exit IP.** Easy to correlate, no
  redundancy. This is the real ceiling of a single-box build.
- **No third-party audit.** "Bulletproof" here means "well-configured and yours,"
  not "independently audited."
- **If you ever take paying strangers' money, the abuse and payment problems from
  the earlier cost breakdown apply.** For you and friends on the free tier, none
  of that bites.

## Bottom line

For you, and a small circle, on Oracle's free tier: **$0/month, real security,
multiple users supported, capped free keys, unlimited paid keys.** You outgrow it
only when your combined monthly traffic pushes past the free bandwidth, at which
point a $5-12/month VPS is the next step, not a rewrite.
