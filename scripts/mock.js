// Serves a snapshot of the sheet's JSON so the UI can be checked without the real key.
const http = require('http');
const fs = require('fs');
const body = fs.readFileSync(process.argv[2] || '/tmp/full.json', 'utf8');
http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(body);
}).listen(8787, '127.0.0.1', () => console.log('mock on 8787'));
