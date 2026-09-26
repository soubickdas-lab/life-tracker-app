// Serves a snapshot of the API's JSON so the UI can be checked without the real key.
// A request for a photo gets a picture instead, so the strips and the gallery
// can be looked at too.
const http = require('http');
const fs = require('fs');

const body = fs.readFileSync(process.argv[2] || '/tmp/full.json', 'utf8');
const shots = process.argv[3] || '';          // a folder of .jpg files, optional

const pictures = shots && fs.existsSync(shots)
  ? fs.readdirSync(shots).filter((n) => /\.(jpe?g|png)$/i.test(n)).map((n) => `${shots}/${n}`)
  : [];

http.createServer((req, res) => {
  const url = new URL(req.url, 'http://localhost');

  if (url.searchParams.get('api') === 'photo' && req.method !== 'POST') {
    if (!pictures.length) { res.writeHead(404).end(); return; }
    /* a different picture per day, so sliding through looks like a run of them */
    const day = url.searchParams.get('day') || '';
    const pick = pictures[Math.abs(hash(day)) % pictures.length];
    res.writeHead(200, { 'Content-Type': 'image/jpeg' });
    res.end(fs.readFileSync(pick));
    return;
  }

  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(body);
}).listen(8787, '127.0.0.1', () => console.log('mock on 8787, pictures:', pictures.length));

function hash(text) {
  let n = 0;
  for (const ch of text) n = (n * 31 + ch.charCodeAt(0)) | 0;
  return n;
}
