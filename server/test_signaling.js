const assert = require('node:assert/strict');
const { spawn } = require('node:child_process');
const { once } = require('node:events');
const { WebSocket } = require('ws');
const port = 20000 + Math.floor(Math.random() * 20000);
const child = spawn(process.execPath, ['signaling.js'], {
  cwd: __dirname, stdio: ['ignore', 'pipe', 'pipe'],
  env: { ...process.env, PORT: String(port), SIGNALING_TOKEN: 'test-token', TURN_SERVER: 'localhost:3478', TURN_SECRET: 'test-secret' },
});
const clients = [];
let output = '';
child.stdout.on('data', data => { output += data; });
child.stderr.on('data', data => { output += data; });
const deadline = setTimeout(() => { console.error(output); child.kill(); process.exit(1); }, 15000);
async function connect() {
  const ws = new WebSocket(`ws://127.0.0.1:${port}`);
  clients.push(ws);
  const messages = [];
  ws.on('message', raw => messages.push(JSON.parse(raw)));
  await once(ws, 'open');
  return {
    ws,
    send(data) { ws.send(JSON.stringify(data)); },
    async next(type) {
      const end = Date.now() + 2000;
      while (Date.now() < end) {
        const i = messages.findIndex(m => m.type === type);
        if (i >= 0) return messages.splice(i, 1)[0];
        await new Promise(r => setTimeout(r, 5));
      }
      throw Error(`Timed out waiting for ${type}: ${JSON.stringify(messages)}`);
    },
  };
}
async function register(client, id) {
  client.send({ type: 'register', userId: id, token: 'test-token' });
  assert.equal((await client.next('registered')).userId, id);
}
(async () => {
  while (!output.includes('running on port')) {
    if (child.exitCode !== null) throw Error(output);
    await new Promise(r => setTimeout(r, 10));
  }
  const a = await connect();
  for (const value of [null, [], 3, 'bad']) {
    a.send(value); assert.equal((await a.next('error')).message, 'Expected a message object');
  }
  a.send({ type: 'register', userId: 123 });
  assert.equal((await a.next('error')).message, 'Invalid user ID');
  for (const type of ['get_users', 'get_turn', 'call_request']) {
    a.send({ type, to: 'peer' });
    assert.equal((await a.next('error')).message, 'Not registered');
  }
  a.send({ type: 'register', userId: 'alice', token: 'wrong' });
  assert.match((await a.next('error')).message, /Unauthorized/);
  await register(a, 'alice');
  const b = await connect(); await register(b, 'bob');
  assert.equal((await a.next('user_joined')).userId, 'bob');
  a.send({ type: 'get_turn' });
  const turn = (await a.next('turn_config')).turn;
  assert.equal(turn.uris.length, 2); assert.ok(turn.username); assert.ok(turn.credential);
  for (const type of ['call_request', 'call_accepted', 'offer', 'answer', 'ice_candidate', 'hangup', 'call_rejected']) {
    a.send({ type, to: 'bob', from: 'spoofed', payload: { sdp: 'v=0', candidate: 'candidate:1' } });
    const received = await b.next(type);
    assert.equal(received.from, 'alice'); assert.equal(received.to, 'bob');
  }
  a.send({ type: 'offer', to: 'bob', payload: {} });
  assert.equal((await a.next('error')).message, 'Invalid SDP payload');
  a.send({ type: 'call_request', to: 'missing' });
  assert.equal((await a.next('user_offline')).target, 'missing');
  await register(a, 'renamed');
  assert.equal((await b.next('user_left')).userId, 'alice');
  const replacement = await connect(); await register(replacement, 'renamed');
  assert.equal((await a.next('conflict')).message, 'Logged in from another device');
  replacement.send({ type: 'ping' }); assert.equal((await replacement.next('pong')).type, 'pong');
  b.send({ type: 'get_users' });
  assert.deepEqual((await b.next('user_list')).users.map(u => u.userId), ['renamed']);
  replacement.send({ type: 'unregister' });
  const left = await b.next('user_left'); assert.equal(left.userId, 'renamed');
  console.log('PASS: malformed input, auth, TURN, full call routing, sender identity, offline, rename, conflict, heartbeat, unregister');
})().catch(error => { console.error(error); console.error(output); process.exitCode = 1; })
.finally(() => { clearTimeout(deadline); for (const ws of clients) ws.terminate(); child.kill(); });
