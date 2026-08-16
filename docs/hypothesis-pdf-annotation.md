# Annotating PDFs with Hypothesis through via

The self-hosted via stack annotates PDFs with the Hypothesis client by serving them in via's own PDF.js viewer (`view_pdf`), which embeds the client. Public, anonymous PDFs work out of the box: via detects the `application/pdf` content type, serves the viewer, and the PDF is fetched by via's nginx proxy.

```text
http://<via>/route?url=<pdf-url>
# or the direct proxy path
http://<via>/http/<pdf-url>
```

The client, the PDF viewer and the PDF are all served from the via host (same site), so the sidebar shows, login works (the OAuth `web_message` fix) and highlights can be created.

## calibre-web PDFs

calibre-web requires a login for its download endpoints and serves an HTML reader for `/show/<id>/pdf` and `/read/<id>/pdf`, so via never detects a PDF. To annotate calibre-web PDFs:

1. Enable anonymous downloads so via's server-side fetch (which has no session) can read the raw PDF: `config_anonbrowse = 1` and give the built-in `Guest` user the download role (`ROLE_DOWNLOAD = 2`). `playbooks/roles/40-PKM/tasks/45-setup-calibre-annotation.archlinux.yml` applies this declaratively (tag `40-45`). This makes the whole library browsable/downloadable without a password on the LAN.
2. Use calibre-web's raw download URL: `http://calibre-web.local/download/<id>/pdf`. A local dnsmasq (`46-setup-lan-dns`, tag `40-46`) resolves `.local` aliases to the machine's current LAN address, and via's nginx uses that dnsmasq as its resolver, so the hostname stays stable even if the DHCP-assigned IP changes.

Then open it through via:

```text
# from this machine
http://localhost:9083/http://calibre-web.local/download/22/pdf
# from any LAN device (phone)
http://192.168.1.139:9083/http://calibre-web.local/download/22/pdf
```

calibre-web's reader URLs (`/show/<id>/pdf`, `/read/<id>/pdf`) are rewritten to `/download/<id>/pdf` by `hypothesis-via-calibre-reader-rewrite.patch` at via's content detection, so opening those also serves the Hypothesis viewer. via fetches the PDF server-side (via's nginx resolves `calibre-web.local` through the host dnsmasq), so devices only need to reach the via stack ports (9083/9085/5000/3001). To let other LAN devices resolve the `.local` aliases too, the router's DHCP should hand out this machine as the DNS server (the dnsmasq on port 53).

## Notes

- New annotations created this way are stored against the raw PDF URI (`http://calibre-web.local/download/<id>/pdf`), not the calibre reader page URI.
- Real-time updates from other devices still need the h websocket (`h.websocket_url` + streamer bind), which is a known follow-up.
