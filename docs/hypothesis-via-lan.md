# Self-hosted Via: LAN access for other devices

The self-hosted Via/Via HTML stack (bouncer, h, via, viahtml, client package) lets the browser annotate any third-party page or PDF. On this machine it used to work through loopback aliases (`via.local`, `viahtml.local`) added to `/etc/hosts`, but those aliases only resolve here: phones and other LAN devices fail with `viahtml.local server ip address could not be found` because the served page points at an unresolvable host.

## Root cause

Via's config baked service URLs into the served page, hardcoding the loopback aliases: via's `via_html_url: http://viahtml.local/proxy` (the proxied-content iframe URL), viahtml's `VIA_H_EMBED_URL=http://localhost:5000/embed.js` (the client embed), `VIA_ROUTING_HOST=http://via.local`, and via's `nginx_server`/`client_embed_url`. Off-host browsers cannot resolve those hosts.

A second, related failure: the embedded client authenticates with h through the OAuth `web_message` response mode, and h posts the authorization code back to the origin derived from the OAuth client's `redirect_uri` (`http://localhost:5000`). Once the client is served from another host (a LAN IP or a domain), the `postMessage` target origin no longer matches and the browser drops the code; the sidebar stays logged out and private annotations never load.

A third failure is the cross-site cookie issue: cookie-based logins (e.g. calibre-web) set a `SameSite=Lax` session cookie from the proxied iframe. If the top-level page and the iframe are on different hosts (`localhost` vs `192.168.1.139`), the browser rejects the cookie as cross-site, the login session is never established and the login POST returns 400. The top-level page and the proxied content must share the same host.

## Fix

Service URLs are no longer baked into config: `hypothesis-via-request-host.patch` and `hypothesis-viahtml-request-host.patch` (via marker `via-patches-v6`) make via and viahtml derive the viahtml URL, the h embed URL, the nginx signed-PDF URL and the routing host from each request's host. `hypothesis-bouncer-request-host.patch` (h marker `h-patches-v5`) makes bouncer redirect to via on the request's host too. Because every URL uses the same host the user is on, the top-level page and the proxied iframe are always same-site (localhost, a LAN IP or a domain all work) and cookie-based logins are accepted.

`hypothesis-viahtml.patch` makes viahtml's nginx-proxy bind `0.0.0.0` (the `127.0.0.1:9085/9086` ports) so LAN devices can reach the proxied content. The ufw LAN port rules already allow 8000/5000/9083/9085/3001.

`hypothesis_h.patch` (h marker `h-patches-v5`) fixes the OAuth `web_message` delivery origin in `h/views/api/auth.py` so the authorization code is posted to the client's actual origin.

Via/Via HTML also block proxying of local/private URLs: Checkmate's client-side cleaning rejects hosts like `calibre-web.local` as "not publicly accessible" (`BadURL`), so via refuses to proxy local services. `hypothesis-via-no-restrictions.patch` and `hypothesis-viahtml-no-restrictions.patch` make both never block, so any URL the instance can reach is proxied.

## Apply

```sh
cd ~/dotfiles/playbooks && ansible-playbook tools.yml --tags 40-PKM -l localhost 2>&1 | tee /tmp/ansible-hpi.log
```

The via marker bump (`via-patches-v6`) and h marker bump (`h-patches-v5`) re-clone via/viahtml and h/bouncer, re-apply the patches and restart the services.

## Known follow-ups

- h's client websocket URL (`h.websocket_url: ws://localhost:5001/ws` in `conf/development.ini`) is still loopback and the streamer binds `localhost:5001`, so real-time updates from other devices won't connect; REST annotation still works. Fixing it needs the same request-host derivation plus binding the streamer to `0.0.0.0`.
- A real PDF served from a `.local` host goes through via's nginx direct proxy (`/proxy/static`), and the nginx container resolves hostnames with DNS (`1.1.1.1`), which does not know `.local`. HTML content goes through viahtml (which resolves via the host's `/etc/hosts`) and works; only the direct-PDF path would need a local DNS resolver for the nginx container.
