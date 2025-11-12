// Minimal Node.js client for PeopleChain monitor REST + WebSocket
// Requires Node 18+.
//
// Usage:
//   npm i ws
//   BASE_URL=http://192.168.1.50:8081 node peoplechain_api_example.mjs
// Defaults to http://127.0.0.1:8081 if BASE_URL is not provided.

import WebSocket from 'ws';

const BASE_URL = process.env.BASE_URL || 'http://127.0.0.1:8081';

async function rest(path, params = undefined) {
  let url = `${BASE_URL}${path}`;
  if (params) {
    const qs = new URLSearchParams(params).toString();
    url += `?${qs}`;
  }
  const res = await fetch(url);
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return await res.json();
}

async function restDemo() {
  console.log('== REST: /api/info');
  console.log(JSON.stringify(await rest('/api/info'), null, 2));

  console.log('\n== REST: /api/peers');
  console.log(JSON.stringify(await rest('/api/peers', { limit: 10 }), null, 2));

  console.log('\n== REST: /api/blocks');
  console.log(JSON.stringify(await rest('/api/blocks', { from: 'tip', count: 3 }), null, 2));
}

async function wsDemo() {
  const wsUrl = BASE_URL.replace('http://', 'ws://').replace('https://', 'wss://') + '/ws';
  console.log(`\n== WS: connecting to ${wsUrl}`);
  const ws = new WebSocket(wsUrl);
  await new Promise((resolve, reject) => {
    const to = setTimeout(() => reject(new Error('WS connect timeout')), 10000);
    ws.on('open', () => { clearTimeout(to); resolve(); });
    ws.on('error', reject);
  });
  ws.send(JSON.stringify({ type: 'get_info' }));
  let count = 0;
  ws.on('message', (data) => {
    console.log('WS:', data.toString());
    if (++count >= 5) ws.close();
  });
  await new Promise((resolve) => ws.on('close', resolve));
}

console.log(`Using BASE_URL=${BASE_URL}`);
await restDemo();
await wsDemo();
