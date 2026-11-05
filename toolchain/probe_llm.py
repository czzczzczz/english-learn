import io, json, subprocess, sys

cfg = json.load(io.open(r'D:/vibe_coding/STranslate-dev/PortableConfig/Settings/Settings.json', encoding='utf-8-sig'))
base = cfg.get('LlmBaseUrl', '').rstrip('/')
key = cfg.get('LlmApiKey', '')
model = cfg.get('LlmModel', '')

print('base =', base)
print('key len =', len(key), 'prefix ok =', key.startswith('sk-'))
print('model =', model)

for proxy in (None, 'http://127.0.0.1:10809'):
    cmd = ['curl', '-sS', '-m', '25', '-o', 'D:/dsh/cache/tmp/models.json',
           '-w', '%{http_code}', '-H', f'Authorization: Bearer {key}', f'{base}/models']
    if proxy:
        cmd = cmd[:1] + ['-x', proxy] + cmd[1:]
    label = proxy or 'direct'
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=40)
        print(f'[{label}] http={r.stdout.strip()} err={r.stderr.strip()[:120]}')
        if r.stdout.strip() == '200':
            data = json.load(io.open('D:/dsh/cache/tmp/models.json', encoding='utf-8'))
            items = data.get('data') or data.get('models') or []
            ids = [i.get('id') if isinstance(i, dict) else i for i in items]
            print('model count =', len(ids))
            print('first 8 =', ids[:8])
            break
    except Exception as ex:
        print(f'[{label}] failed: {ex}')
