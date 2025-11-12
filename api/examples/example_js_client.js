async function fetchInfo(baseUrl) {
  const r = await fetch(baseUrl + '/api/info');
  const j = await r.json();
  console.log('REST /api/info', j);
}

function connectWs(baseUrl) {
  const ws = new WebSocket(baseUrl.replace('http', 'ws') + '/ws');
  ws.onopen = () => ws.send(JSON.stringify({ type: 'get_info' }));
  ws.onmessage = (e) => console.log('WS', e.data);
  ws.onerror = (e) => console.warn('WS error', e);
  ws.onclose = () => console.log('WS closed');
}

window.addEventListener('DOMContentLoaded', () => {
  const base = document.getElementById('base').value || 'http://127.0.0.1:8080';
  document.getElementById('btnRest').onclick = () => fetchInfo(base);
  document.getElementById('btnWs').onclick = () => connectWs(base);
});
