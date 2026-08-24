import sqlite3, os, hmac, hashlib, base64, time, requests
from datetime import datetime

db_path = os.path.expandvars(r'%APPDATA%\com.yordany\cryptoview\CryptoView\cryptoview.db')
conn = sqlite3.connect(db_path)
c = conn.cursor()
c.execute('SELECT api_key, api_secret, api_passphrase FROM api_keys WHERE LOWER(exchange) = ?', ('kucoin',))
row = c.fetchone()
if not row:
    print('No KuCoin key')
    exit()

api_key, api_secret, passphrase = row

def get_kc(endpoint, params=None):
    now_ms = str(int(time.time() * 1000))
    query_str = ''
    if params:
        query_str = '?' + '&'.join([f'{k}={v}' for k, v in sorted(params.items())])
    msg = f'{now_ms}GET{endpoint}{query_str}'
    sig = base64.b64encode(hmac.new(api_secret.encode('utf-8'), msg.encode('utf-8'), hashlib.sha256).digest()).decode('utf-8')
    pass_sig = base64.b64encode(hmac.new(api_secret.encode('utf-8'), passphrase.encode('utf-8'), hashlib.sha256).digest()).decode('utf-8')
    headers = {
        'KC-API-KEY': api_key,
        'KC-API-SIGN': sig,
        'KC-API-TIMESTAMP': now_ms,
        'KC-API-PASSPHRASE': pass_sig,
        'KC-API-KEY-VERSION': '2',
    }
    r = requests.get('https://api.kucoin.com' + endpoint + query_str, headers=headers)
    return r.json()

# Query in chunks of 7 days backwards up to 730 days
now_ms = int(time.time() * 1000)
all_fills = []

for day_offset in range(0, 730, 7):
    end_at = now_ms - (day_offset * 24 * 3600 * 1000)
    start_at = end_at - (7 * 24 * 3600 * 1000)
    res = get_kc('/api/v1/fills', {'symbol': 'SOL-USDT', 'pageSize': 100, 'startAt': start_at, 'endAt': end_at})
    items = res.get('data', {}).get('items', [])
    if items:
        all_fills.extend(items)
    time.sleep(0.05)

print(f'Total KuCoin SOL-USDT fills found: {len(all_fills)}')
for o in sorted(all_fills, key=lambda x: x.get('createdAt')):
    dt = datetime.fromtimestamp(o.get('createdAt') / 1000).strftime('%Y-%m-%d %H:%M')
    print(f"{dt}: {o.get('side')} {o.get('size')} SOL @ ${o.get('price')} = ${o.get('funds')} USDT (fee: {o.get('fee')})")
