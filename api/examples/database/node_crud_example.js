/**
 * PeopleChain Monitor • Node.js CRUD example (Node 18+)
 *
 * Prerequisites:
 *   Node.js 18+ (global fetch available). If you are on Node <18, install node-fetch.
 *
 * Usage:
 *   node node_crud_example.js
 */

const BASE = process.env.PC_BASE || 'http://127.0.0.1:8081';
const COLLECTION = 'notes';

async function http(method, path, body) {
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers: { 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (!res.ok) {
    const t = await res.text();
    throw new Error(`${method} ${path} -> ${res.status}: ${t}`);
  }
  return res.json();
}

const pretty = (o) => console.log(JSON.stringify(o, null, 2));

async function run() {
  console.log('1) Create two notes');
  const n1 = await http('POST', `/api/db/${COLLECTION}`, { data: { title: 'First', body: 'Hello from Node', tags: ['demo','node'] } });
  const n2 = await http('POST', `/api/db/${COLLECTION}`, { data: { title: 'Second', body: 'Filter me', tags: ['filter'] } });
  pretty(n1); pretty(n2);

  console.log('\n2) List (limit=10)');
  pretty(await (await fetch(`${BASE}/api/db/${COLLECTION}?limit=10`)).json());

  console.log('\n3) Filter q=filter');
  pretty(await (await fetch(`${BASE}/api/db/${COLLECTION}?q=filter`)).json());

  console.log('\n4) Read first by id');
  const id = n1.id;
  pretty(await http('GET', `/api/db/${COLLECTION}/${id}`));

  console.log('\n5) Replace with PUT');
  pretty(await http('PUT', `/api/db/${COLLECTION}/${id}`, { data: { title: 'Updated', body: 'Replaced body', tags: ['updated'] } }));

  console.log('\n6) Patch with PATCH');
  pretty(await http('PATCH', `/api/db/${COLLECTION}/${id}`, { data: { extra: 42, tags: ['updated','patched'] } }));

  console.log('\n7) Delete second');
  pretty(await http('DELETE', `/api/db/${COLLECTION}/${n2.id}`));

  console.log('\n8) List again');
  pretty(await (await fetch(`${BASE}/api/db/${COLLECTION}`)).json());
}

run().catch(err => { console.error(err); process.exit(1); });
