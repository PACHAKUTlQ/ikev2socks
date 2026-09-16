## ikev2socks

`ikev2socks` runs a strongSwan IKEv2/IPsec client and exposes a local SOCKS5 proxy through [gost](https://github.com/go-gost/gost).

The container establishes the configured IPsec connection, listens on `127.0.0.1:1082`, and routes SOCKS5 connections through the VPN. If the IPsec connection drops, it attempts to reconnect automatically.

The proxy is intentionally bound to loopback and has no SOCKS authentication. Do not publish it on a non-loopback address unless access control and SOCKS authentication are configured separately.

## Requirements

- Podman with Quadlet support
- A working IKEv2/IPsec configuration for strongSwan
- Host networking support for Podman's `pasta` network mode
- User systemd instance

The container needs `NET_ADMIN` to create and manage IPsec network state.

## Build

> [!note]
>
> Because the strongSwan package on alpine does not have eap-peap installed, the Containerfile builds strongSwan from source.

Build the image from the directory containing `Containerfile`, `build-strongswan.sh`, and `entrypoint.sh`:

```sh
podman build -t localhost/ikev2socks:latest .
```

The build downloads the current strongSwan release archive from <https://download.strongswan.org/strongswan.tar.bz2>

## IPsec configuration

Place the strongSwan configuration and secrets on the host:

```text
/etc/ipsec.conf
/etc/ipsec.secrets
```

> [!note]
>
> `ipsec.secrets` defaults to root:root,0600. You can copy it, make the copy readable, and use the copy in Quadlet.

The Quadlet mounts both files read-only into the container.

The connection name defined in `ipsec.conf` must match the `CONNECTION` environment variable in `ikev2socks.container`.

Example `/etc/ipsec.conf`:

```conf
config setup
    charondebug="ike 1, cfg 1, net 1"

conn example-ikev2
    keyexchange=ikev2
    auto=add

    leftauth=eap-mschapv2
    leftsourceip=%config
    eap_identity="user@example.com"

    right=vpn.example.com
    rightid=@vpn.example.com
    rightauth=pubkey
    rightsubnet=0.0.0.0/0,::/0
```

Example `/etc/ipsec.secrets`:

```conf
user@example.com : EAP "password"
```

Provider-specific settings, certificate requirements, identities, cryptographic proposals, DNS configuration, and traffic selectors belong in the normal strongSwan configuration.

## Quadlet installation

Install `ikev2socks.container` as a user Quadlet:

```sh
mkdir -p ~/.config/containers/systemd
install -m 0644 ikev2socks.container ~/.config/containers/systemd/ikev2socks.container
```

Set the IPsec connection name in the Quadlet:

```ini
Environment=CONNECTION=example-ikev2
```

The image reference in the Quadlet must match the locally built image:

```ini
Image=localhost/ikev2socks:latest
```

Reload the user systemd manager and start the generated service:

```sh
systemctl --user daemon-reload
systemctl --user start ikev2socks.service
```

Check its status and logs:

```sh
systemctl --user status ikev2socks.service
journalctl --user -u ikev2socks.service -f
```

To keep the user systemd manager running after logout:

```sh
loginctl enable-linger "$USER"
```

## Using the SOCKS5 proxy

The service publishes an unauthenticated SOCKS5 listener at:

```text
127.0.0.1:1082
```

Example with curl:

```sh
curl --proxy socks5h://127.0.0.1:1082 https://ifconfig.me
```

The `socks5h` scheme sends DNS resolution through the SOCKS proxy.

Example with an environment variable:

```sh
export ALL_PROXY=socks5h://127.0.0.1:1082
```

## Configuration

The Quadlet exposes the following environment variables:

| Variable      | Required | Default | Description                                                                        |
| ------------- | -------- | ------- | ---------------------------------------------------------------------------------- |
| `CONNECTION`  | Yes      | None    | Name of the `conn` stanza in `/etc/ipsec.conf`.                                    |
| `TIMEOUT`     | No       | `120`   | Maximum number of seconds to wait for initial IPsec establishment or reconnection. |
| `START_DELAY` | No       | `1`     | Seconds to wait after starting strongSwan before checking that it remains running. |
| `SOCKS_PORT`  | No       | `1082`  | SOCKS5 listener port inside the container and on the loopback host binding.        |

For the default Quadlet port mapping, `SOCKS_PORT` must remain `1082`:

```ini
PublishPort=127.0.0.1:1082:1082
Environment=SOCKS_PORT=1082
```

Changing the proxy port requires updating both directives consistently.

## Lifecycle

Stop the service:

```sh
systemctl --user stop ikev2socks.service
```

Restart after changing the image, Quadlet, or IPsec configuration:

```sh
systemctl --user daemon-reload
systemctl --user restart ikev2socks.service
```

The container shuts down the configured IPsec connection and stops strongSwan when the service stops.
