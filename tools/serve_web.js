// Static server for build/web (Web export test): node tools/serve_web.js [port]  -> http://localhost:<port>/
const http = require('http'), fs = require('fs'), path = require('path');
const root = path.join(__dirname, '..', 'build', 'web');
const port = +process.argv[2] || 8060;
const types = { '.html': 'text/html', '.js': 'application/javascript', '.wasm': 'application/wasm', '.pck': 'application/octet-stream', '.png': 'image/png' };
http.createServer((req, res) => {
  const p = path.join(root, decodeURIComponent(req.url.split('?')[0]) === '/' ? 'index.html' : decodeURIComponent(req.url.split('?')[0]));
  if (!p.startsWith(root) || !fs.existsSync(p)) { res.writeHead(404); return res.end(); }
  res.writeHead(200, { 'Content-Type': types[path.extname(p)] || 'application/octet-stream', 'Cross-Origin-Opener-Policy': 'same-origin', 'Cross-Origin-Embedder-Policy': 'require-corp' });
  fs.createReadStream(p).pipe(res);
}).on('error', (e) => {
  if (e.code !== 'EADDRINUSE') throw e;
  console.log(`port ${port} is already in use (a server is probably still running): open http://localhost:${port}/ or pass another port`);
  process.exit(1);
}).listen(port, '127.0.0.1', () => console.log('http://localhost:' + port + '/'));
