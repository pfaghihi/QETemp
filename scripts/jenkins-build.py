"""Retrieve status and console logs for a Jenkins build using read-only APIs."""
import argparse
import base64
import json
import os
from pathlib import Path
import urllib.request


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('build_url', help='Full Jenkins build URL, including build number')
    parser.add_argument('--output', default='jenkins-build-output')
    args = parser.parse_args()
    user = os.environ.get('JENKINS_USER')
    token = os.environ.get('JENKINS_API_TOKEN')
    if not user or not token:
        parser.error('Set JENKINS_USER and JENKINS_API_TOKEN in your environment')
    auth = base64.b64encode(f'{user}:{token}'.encode()).decode()
    base = args.build_url.rstrip('/')
    if not base.startswith(('http://', 'https://')):
        parser.error('build_url must be an HTTP or HTTPS URL')
    # Do not forward credentials through redirects to another host.
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, req, fp, code, msg, headers, newurl):
            return None
    opener = urllib.request.build_opener(NoRedirect)

    def get(path):
        req = urllib.request.Request(base + path, headers={'Authorization': 'Basic ' + auth})
        with opener.open(req, timeout=30) as response:
            return response.read().decode('utf-8')

    status = json.loads(get('/api/json?tree=number,result,building,url,duration'))
    # Resolve aliases such as lastBuild to one build before retrieving its log.
    base = base.rsplit('/', 1)[0] + '/' + str(status['number'])
    logs = get('/consoleText')
    output = Path(args.output)
    output.mkdir(parents=True, exist_ok=True)
    (output / 'status.json').write_text(json.dumps(status, indent=2) + '\n', encoding='utf-8')
    (output / 'console.log').write_text(logs, encoding='utf-8')
    print(json.dumps(status, indent=2))
    print(f'Console log saved to {output / "console.log"}')


if __name__ == '__main__':
    main()
