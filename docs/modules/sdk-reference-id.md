# ZAgents Module SDK (v1.22.0)

Panduan resmi untuk membuat **modul chat**: paket JavaScript yang berjalan
secara native di dalam sesi chat ZAgents, terisolasi per chat seperti
jendela privat browser.

Lokasi berkas di repositori ini:

| Path | Isi |
|---|---|
| `sdk/` | SDK resmi — shim `zagents-sdk.js`, definisi TypeScript `index.d.ts`, `package.json` |
| `samples/` | Contoh modul siap pasang (counter, network-fetcher, file-notes, chat-streamer, onhomeroom-daily) |
| `docs/modules/` | Referensi ini (Inggris + Bahasa Indonesia) — juga dikirim in-app |

## 1. Struktur paket

Modul adalah arsip ZIP:

```
modul-saya.zip
├── module.json        (manifest — disarankan)
├── main.js            (entry point, bawaan)
├── lib/util.js        (file tambahan, di-require secara relatif)
└── node_modules/…     (opsional; atau gunakan paket dari alat npm)
```

### Manifest — `module.json`

```json
{
  "name": "modul-saya",
  "version": "1.0.0",
  "title": "Modul Saya",
  "description": "Apa yang dilakukan modul ini untuk pengguna.",
  "entry": "main.js",
  "permissions": ["storage", "network", "files", "chat"],
  "allowedHosts": ["api.contoh.com"],
  "timeoutSeconds": 30
}
```

| Kolom | Wajib | Keterangan |
|---|---|---|
| `name` | ya | Huruf kecil `[a-z0-9._-]`, maks 40 karakter. Sekaligus nama direktori instalasi. |
| `version` | — | Ditampilkan di layar Modules. |
| `title` | — | Nama tampilan (bawaan: `name`). |
| `description` | — | Ditampilkan ke pengguna dan disuntikkan ke konteks chat. |
| `entry` | — | Entry point, bawaan `main.js`. |
| `permissions` | — | `storage`, `network`, `files`, `chat`, `agent` — pengguna menyetujui setiap aktivasi. |
| `allowedHosts` | — | Membatasi `zagents.http` ke host tersebut (`*.contoh.com` mengizinkan subdomain). Kosongkan untuk semua host. |
| `timeoutSeconds` | — | Anggaran eksekusi per run (30 bawaan, maks 120). |

Tanpa `module.json`, `package.json` (`name`, `version`, `main`) tetap
dihormati; tanpa keduanya, nama file ZIP menjadi nama modul.

## 2. Memasang dan menjalankan

1. **Layar Modules** → *Pasang modul* → pilih file ZIP.
2. Jalankan di dalam chat:
   * Ketik **`/plugins`** → pilih modul dari menu interaktif, atau
   * Ketik **`/plugins modul-saya`**, atau
   * Pilih chip modul di layar chat baru, atau
   * Layar Modules → modul → *Mulai di chat baru*.
3. Entry point dieksekusi sekali per aktivasi. Output console dan nilai
   kembaliannya dikirim ke percakapan sebagai pesan modul; agen dapat
   membaca dan membahasnya.
   **Tips setup:** saat modul dipilih di chat BARU (staged), pesan pertama
   yang Anda kirim diekspos ke modul sebagai `zagents.info.prompt` —
   modul bisa menyediakan perintah seperti `setup <kredensial>`, `status`
   atau `reset` pada pesan itu.

## 3. SDK `zagents`

Tersedia sebagai global — atau `const zagents = require('zagents-sdk')`.

### `zagents.info`
Metadata: `name`, `version`, `title`, `sessionId`, `entry` — ditambah
`prompt` (pesan pengguna yang mengaktivasi) saat run dipicu pesan pertama
modul yang di-stage di draft baru, dan `userAgent` — identitas yang
dipilih pengguna di Setelan → User Agent.

**Kebijakan User-Agent:** modul selalu memakai identitas yang dikonfigurasi
di Setelan → User Agent. `zagents.http` mengirimkannya di setiap request,
dan header `User-Agent` dari modul dibuang oleh bridge — setelan SELALU
menang. Baca identitas aktif lewat `zagents.info.userAgent` (hanya untuk
tampilan atau debugging).

### `zagents.log(...)` — selalu tersedia
Output console, ditangkap ke dalam pesan modul.

### `zagents.storage` — izin `storage`
Penyimpanan kunci/nilai per chat. Chat berbeda TIDAK PERNAH berbagi.

```js
await zagents.storage.set('kunjungan', 1);
const kunjungan = await zagents.storage.get('kunjungan'); // 1
const kunci = await zagents.storage.keys();               // ['kunjungan']
await zagents.storage.remove('kunjungan');
```

Batas: 64 KB per nilai, 1 MB per (chat, modul).

### `zagents.fs` — izin `files`
Akses file terbatas pada direktori `state/` modul untuk chat ini.

```js
await zagents.fs.writeFile('catatan.txt', 'halo');
const teks = await zagents.fs.readFile('catatan.txt');
await zagents.fs.appendFile('catatan.txt', '\nlagi');
const daftar = await zagents.fs.readdir('.');
await zagents.fs.mkdir('sub');
await zagents.fs.unlink('catatan.txt');
const info = await zagents.fs.stat('sub'); // { isDirectory, size, modified }
```

Path di luar direktori state akan ditolak.

### `zagents.http` — izin `network`
HTTP melalui aplikasi (status + body + header respons), opsional dibatasi
host oleh `allowedHosts` di manifest.

```js
const res = await zagents.http.request('https://api.contoh.com/data', {
  method: 'POST',
  body: JSON.stringify({ q: 'hai' }),
  headers: { 'Content-Type': 'application/json' },
});
if (res.ok) {
  const data = await res.json();
  const cookie = res.headers['set-cookie']; // header respons (huruf kecil)
}
```

Opsi: `method`, `body`, `headers` (field hop-by-hop seperti `Host` dan
`Connection` dibuang; `User-Agent` juga dibuang — request selalu membawa
identitas Setelan → User Agent, lihat `zagents.info.userAgent`),
`timeoutMs` (batas seluruh request, maks 60000)
dan `headOnly: true` — kembali begitu status line + header tiba, tanpa
membaca body (memulai stream SSE tanpa menunggu stream itu selesai).

### `zagents.agent` — izin `agent`
Minta AGEN CHAT SENDIRI (provider/model yang dipakai chat ini) menyusun
SATU kalimat santai berbahasa Inggris dari konteks live yang modul
suplai. Tidak ada template: setiap kalimat digenerate saat dibutuhkan,
dan host menegakkan kontrak composer sebelum modul melihat teksnya:

* tepat satu kalimat, santai, terdengar seperti manusia, bahasa Inggris;
* tidak pernah memuat `!` `:` `;` `—` `–` `?` dan tanpa emoji;
* paling banyak `maxWords` kata (bawaan 24, rentang 1–40);
* tidak pernah mengulang teks yang diberikan lewat `avoid`;
* satu percobaan perbaikan otomatis, lalu satu pass sanitize
  deterministik — output yang masih melanggar melempar error sehingga
  modul bisa melewati aksi teks itu dengan anggun.

```js
const { text } = await zagents.agent.compose({
  task: 'chat-reply',
  context: barisChatTerakhir.join('\n'),
  instruction: 'reaksi atas pesan terakhir',
  maxWords: 16,
  avoid: teksTerakhirTerkirim,
});
```

Kegagalan (API key kosong, provider down, pelanggaran berulang) melempar
error — bungkus dengan try/catch dan lewati aksi teks tersebut bila
komposisi tidak memungkinkan.

### `zagents.chat` — izin `chat`
Kirim output bertahap ke percakapan selama modul berjalan:

```js
await zagents.chat.emit('Langkah 1 selesai…');
```

## 4. Model isolasi (jendela privat per chat)

* **Proses** — setiap eksekusi memulai konteks JS baru; tidak ada yang
  bertahan antar run.
* **State & storage** — `<sesi>/modules/<nama>/` dibuat per chat;
  `storage.json` dan `state/` tidak terlihat oleh chat lain maupun modul
  lain.
* **Izin** — dideklarasikan di manifest, disetujui pengguna saat
  aktivasi, ditegakkan dua lapis (SDK + bridge Dart).
* **Jaringan** — butuh `network`; `allowedHosts` mempersempit lagi.
* **Agen** — butuh `agent`; generasi lewat LLM chat sendiri plus gerbang
  composer di sisi host, sehingga output modul selalu di dalam kontrak
  yang diatur.
* **Sumber daya** — timeout, batas output, batas storage.
* **Penghentian** — menonaktifkan modul atau menghentikan chat membatalkan
  run yang berjalan dengan aman: pengiriman berhenti, state tersimpan.

## 5. Contoh minimal

Contoh yang sama, siap dipasang, ada di [`samples/counter/`](../../samples/counter/)
— bersama contoh lengkap lainnya yang mencakup semua izin:

| Contoh | Mendemonstrasikan |
|---|---|
| [`samples/counter/`](../../samples/counter/) | `storage` — penghitung aktivasi per chat |
| [`samples/network-fetcher/`](../../samples/network-fetcher/) | `network` — `zagents.http` + `allowedHosts` |
| [`samples/file-notes/`](../../samples/file-notes/) | `files` — catatan tersandbox di `state/` |
| [`samples/chat-streamer/`](../../samples/chat-streamer/) | `chat` — output bertahap `chat.emit` |
| [`samples/onhomeroom-daily/`](../../samples/onhomeroom-daily/) | `agent` — bot harian dunia nyata yang setiap kalimatnya disusun agen chat |

`module.json`

```json
{
  "name": "penghitung-halo",
  "version": "1.0.0",
  "title": "Penghitung Halo",
  "description": "Menghitung aktivasi per chat.",
  "permissions": ["storage"]
}
```

`main.js`

```js
async function main() {
  const sebelumnya = (await zagents.storage.get('jumlah')) || 0;
  await zagents.storage.set('jumlah', sebelumnya + 1);
  zagents.log('Halo dari modul! Jumlah di chat INI: ' + (sebelumnya + 1));
  return { jumlah: sebelumnya + 1 };
}
module.exports = main();
```
