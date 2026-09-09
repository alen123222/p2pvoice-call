const WebSocket = require('ws');
const { spawn } = require('child_process');

// Use a random high port so the test never collides with a running instance.
const PORT = 20000 + Math.floor(Math.random() * 20000);
const URL = `ws://localhost:${PORT}`;

const serverProc = spawn('node', ['signaling.js'], {
  cwd: __dirname,
  stdio: 'inherit',
  env: { ...process.env, PORT: String(PORT) },
});

let finished = false;

function cleanup(code) {
  if (finished) return;
  finished = true;
  serverProc.kill();
  process.exit(code);
}

const globalTimeout = setTimeout(() => {
  console.error('[Test] TIMEOUT: Test failed');
  cleanup(1);
}, 8000);

setTimeout(() => {
  const ws1 = new WebSocket(URL);
  const ws2 = new WebSocket(URL);

  let testPassed = false;

  ws1.on('open', () => {
    console.log('[Test] Client 1 connected, registering as user101');
    ws1.send(JSON.stringify({ type: 'register', userId: 'user101' }));
  });

  ws2.on('open', () => {
    console.log('[Test] Client 2 connected, registering as user202');
    ws2.send(JSON.stringify({ type: 'register', userId: 'user202' }));
  });

  ws2.on('message', (msg) => {
    const data = JSON.parse(msg.toString());
    console.log('[Test] Client 2 received message:', data.type);
    if (data.type === 'call_request' && data.from === 'user101') {
      console.log('[Test] SUCCESS: Call request forwarded correctly!');
      testPassed = true;
      ws1.close();
      ws2.close();
      clearTimeout(globalTimeout);
      cleanup(0);
    }
  });

  ws1.on('message', (msg) => {
    const data = JSON.parse(msg.toString());
    if (data.type === 'registered') {
      setTimeout(() => {
        console.log('[Test] Client 1 calling user202');
        ws1.send(JSON.stringify({
          type: 'call_request',
          from: 'user101',
          to: 'user202',
          payload: { sdp: 'dummy_offer_sdp' },
        }));
      }, 500);
    }
  });

  ws1.on('error', (err) => {
    console.error('[Test] Client 1 error:', err.message);
    clearTimeout(globalTimeout);
    cleanup(1);
  });

  ws2.on('error', (err) => {
    console.error('[Test] Client 2 error:', err.message);
    clearTimeout(globalTimeout);
    cleanup(1);
  });
}, 1000);
