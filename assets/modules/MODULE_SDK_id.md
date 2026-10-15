# ZAgents Module SDK (v1.21.0)

Panduan resmi untuk membuat **modul chat**: paket JavaScript yang berjalan
secara native di dalam sesi chat ZAgents, terisolasi per chat seperti
jendela privat browser.

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
| `permissions` | — | `storage`, `network`, `files`, `chat` — pengguna menyetujui setiap aktivasi. |
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

## 3. SDK `zagents`

Tersedia sebagai global — atau `const zagents = require('zagents-sdk')`.

### `zagents.info`
Metadata: `name`, `version`, `title`, `sessionId`, `entry`.

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
const daftar = await zagents.fs.readdir('.');
await zagents.fs.mkdir('sub');
await zagents.fs.unlink('catatan.txt');
const info = await zagents.fs.stat('sub'); // { isDirectory, size, modified }
```

Path di luar direktori state akan ditolak.

### `zagents.http` — izin `network`
HTTP melalui aplikasi (status + body), opsional dibatasi host.

```js
const res = await zagents.http.request('https://api.contoh.com/data', {
  method: 'POST',
  body: JSON.stringify({ q: 'hai' }),
});
if (res.ok) {
  const data = await res.json();
}
```

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
* **Sumber daya** — timeout, batas output, batas storage.
* **Penghentian** — menonaktifkan modul atau menghentikan chat membatalkan
  run yang berjalan dengan aman: pengiriman berhenti, state tersimpan.

## 5. Contoh minimal

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
