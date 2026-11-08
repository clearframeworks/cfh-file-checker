"""Download a public HTTPS URL without allowing redirects to private networks."""
import http.client
import ipaddress
import os
import socket
import ssl
import sys
from urllib.parse import urljoin, urlsplit

LIMIT = min(int(os.environ.get('MAX_DOWNLOAD_BYTES', 100 * 1024 * 1024)), 100 * 1024 * 1024)
if LIMIT <= 0:
    raise ValueError('Invalid download limit')


class PinnedHTTPS(http.client.HTTPSConnection):
    def __init__(self, host, address):
        super().__init__(host, 443, timeout=30, context=ssl.create_default_context())
        self.address = address

    def connect(self):
        raw = socket.create_connection((self.address, 443), self.timeout)
        self.sock = self._context.wrap_socket(raw, server_hostname=self.host)


def download(url):
    for _ in range(6):
        p = urlsplit(url)
        if p.scheme != 'https' or not p.hostname or p.username or p.password or p.port not in (None, 443):
            raise ValueError('Only public HTTPS URLs on port 443 are supported')
        addresses = {entry[4][0] for entry in socket.getaddrinfo(p.hostname, 443, type=socket.SOCK_STREAM)}
        if not addresses or any(not ipaddress.ip_address(a).is_global for a in addresses):
            raise ValueError('The URL does not resolve exclusively to public addresses')
        path = p.path or '/'
        if p.query:
            path += '?' + p.query
        response = None
        last_error = None
        for address in sorted(addresses, key=lambda a: ipaddress.ip_address(a).version):
            connection = PinnedHTTPS(p.hostname, address)
            try:
                connection.request('GET', path, headers={'User-Agent': 'CFH-File-Checker/1', 'Accept-Encoding': 'identity'})
                response = connection.getresponse()
                break
            except OSError as exc:
                last_error = exc
                connection.close()
        if response is None:
            raise ValueError('Could not connect to the public server: %s' % last_error)
        if response.status in (301, 302, 303, 307, 308):
            location = response.getheader('Location')
            connection.close()
            if not location:
                raise ValueError('Redirect has no destination')
            url = urljoin(url, location)
            continue
        if response.status != 200:
            raise ValueError('Download returned HTTP %s' % response.status)
        size = 0
        with open('sample', 'wb') as f:
            while True:
                chunk = response.read(65536)
                if not chunk:
                    break
                size += len(chunk)
                if size > LIMIT:
                    raise ValueError('File exceeds the configured download limit')
                f.write(chunk)
        if not size:
            raise ValueError('Downloaded file is empty')
        return
    raise ValueError('Too many redirects')


try:
    download(os.environ['TARGET_URL'])
except Exception as exc:
    print('Download failed:', str(exc), file=sys.stderr)
    sys.exit(1)
