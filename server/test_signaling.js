const WebSocket = require('ws');

// Start server in background for testing if not already running
const { spawn } = require('child_process');
const serverProc = spawn('node', ['signaling.js'], { cwd: __dirname, stdio: 'inherit' });

setTimeout(() => {
  const ws1 = new WebSocket('ws://localhost:8080');
  const ws2 = new WebSocket('ws://localhost:8080');

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
      serverProc.kill();
      process.exit(0);
    }
  });

  ws1.on('message', (msg) => {
    const data = JSON.parse(msg.toString());
    if (data.type === 'registered') {
      // Once registered, wait a bit and call user202
      setTimeout(() => {
        console.log('[Test] Client 1 calling user202');
        ws1.send(JSON.stringify({
          type: 'call_request',
          from: 'user101',
          to: 'user202',
          payload: { sdp: 'dummy_offer_sdp' }
        }));
      }, 500);
    }
  });

  setTimeout(() => {
    if (!testPassed) {
      console.error('[Test] TIMEOUT: Test failed');
      serverProc.kill();
      process.exit(1);
    }
  }, 5000);
}, 1000);
