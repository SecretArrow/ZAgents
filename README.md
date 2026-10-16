# ZAgents

![CI](https://github.com/SecretArrow/ZAgents/actions/workflows/ci.yml/badge.svg)
![Release](https://github.com/SecretArrow/ZAgents/actions/workflows/release.yml/badge.svg)

**ZAgents** adalah aplikasi Android (Flutter) bergaya **agent mode chat.z.ai** —
chat AI dengan kemampuan **otomasi browser tersemat** (buka halaman, klik, ketik,
scroll, screenshot) dan **kelola file**, mendukung **custom provider**
OpenAI-compatible: **OpenRouter, InferHub, Z.AI, OpenAI, DeepSeek, Groq, dan lainnya**.

## ✨ Fitur

- **Chat streaming** — jawaban model ditampilkan token demi token (SSE).
- **Mode Agent** — model diberi 12 tools dan bekerja step-by-step:
  | Tool | Fungsi |
  |---|---|
  | `browser_navigate` | Buka URL di browser tersemat (headless WebView) |
  | `browser_click` | Klik elemen via CSS selector / teks |
  | `browser_type` | Ketik ke input/textarea/contenteditable |
  | `browser_scroll` | Scroll halaman atas/bawah |
  | `browser_screenshot` | Capture halaman → tampil sebagai gambar di chat |
  | `browser_extract_text` | Ambil teks halaman untuk dianalisis |
  | `run_js` | Eksekusi JavaScript di konteks halaman |
  | `read_file` / `write_file` | Baca/tulis file di folder dokumen aplikasi |
  | `node_run` | Jalankan JavaScript di runtime tersemat (require/fs/fetch) |
  | `node_install` / `node_remove` | Tambah/hapus package npm sesuai kebutuhan agent |
- **Custom provider** — kelola provider lewat layar **Providers** penuh
  (bukan modal): setiap provider menyimpan **base URL + API key + model sendiri**
  (preset tersedia: OpenRouter, **InferHub** `sk-airo-…`, Z.AI, OpenAI, DeepSeek,
  Groq, atau Custom), lengkap dengan:
  - 💾 **tombol Save API key per provider** (tersimpan seketi tanpa keluar layar),
  - ☁️ **tombol Fetch models** — ambil daftar model yang benar-benar tersedia
    di provider tersebut (`GET {baseUrl}/models`) langsung dari editor,
  - ✅ validasi (nama wajib, URL wajib, nama ganda ditolak) + hapus provider
    dengan konfirmasi, aktifkan provider satu ketukan (⚡),
  - migrasi otomatis dari key lama.
- **Katalog model live** — pemilih model selalu terikat ke **provider yang
  di-set default di Settings** (nama provider + host tampil di header) dan
  mengambil daftar langsung dari `GET {baseUrl}/models`, lengkap dengan:
  - 🔍 **kolom pencarian** yang bekerja di semua state (katalog live, cache,
    maupun saran offline) — filter by id atau nama,
  - 🏷️ **filter chip** (Semua / Tools / Gratis — termasuk model `:free` OpenRouter),
  - 📄 **paging 5 item per halaman** dengan navigasi first/prev/next/last,
  - 📴 **cache model per provider** — hasil fetch tersimpan di preset sehingga
    daftar model provider Anda tetap tampil saat offline / API error,
  - badge info (konteks, tools, gratis) + tombol refresh + fallback saran offline.
- **Lanjut percakapan, bukan chat baru (v1.8.0)** — mengirim pesan selalu
  **melanjutkan percakapan yang terbuka** (dibuka dari riwayat maupun yang
  baru selesai jalan) alih-alih mem-fork chat baru; percakapan terakhir
  otomatis dibuka kembali saat aplikasi dimulai, dan chat baru hanya dimulai
  lewat tombol **"New chat"** di menu.
- **Run until done (v1.8.0)** — agent bekerja **sampai tugas benar-benar
  selesai** tanpa berhenti di batas langkah (default aktif). Batas maks.
  langkah tetap tersedia (slider 1-100 + input kustom) dan bisa diterapkan
  lewat Settings → Agent; saat batas tercapai, aplikasi kini menjelaskan
  alasannya di chat alih-alih berhenti diam-diam.
- **Plan first + Todos (v1.9.0)** — mirip mode agent z.ai: agent **selalu
  memulai tugas dengan rencana todo** (`todo_write`) sebelum bekerja,
  memperbarui status tiap langkah (pending → in progress → selesai), dan
  **otomatis tahu kapan tugas selesai** — bila model mencoba berhenti saat
  masih ada todo yang belum selesai, loop mengingatkannya untuk melanjutkan
  hingga semua todo tuntas. Rencana tampil sebagai **kartu Rencana** dengan
  progress bar + ikon status per langkah di dalam chat. Bisa dimatikan lewat
  Settings → Agent → "Buat rencana dulu (Todos)".
- **Panel rencana live + toggle show/hide (v1.10.0)** — di kanan teks
  **"thinking…"** kini ada ikon show/hide (rata kanan); ketuk untuk
  menampilkan/menyembunyikan **rencana (Todos) langsung** — langkah yang
  sedang dikerjakan berputar (spinner), progress bar dan status tiap todo
  diperbarui real-time, jadi Anda bisa memantau sejauh mana agent bekerja
  kapan saja selama proses berjalan (termasuk saat tool dieksekusi).
- **Aktivasi provider via long-press (v1.10.0)** — selain tombol bolt,
  **tahan (long-press) kartu provider** di layar Providers untuk
  mengaktifkannya: muncul **dialog konfirmasi** sebelum koneksi berpindah
  (tekan lama pada provider yang sudah aktif tidak melakukan apa-apa).
- **Eksekusi JS dari arsip upload (v1.11.0)** — file binary yang diunggah
  (mis. **zip berisi proyek JavaScript**) kini benar-benar bisa dikerjakan
  agent: pesan lampiran otomatis menyertakan **path relatif** file di folder
  `uploads/` + instruksi pemakaian, dan agent mendapat **tool baru
  `unzip_file` / `zip_file`** — mengekstrak arsip, membaca daftar isinya,
  lalu menjalankan file `.js` dengan `node_run` (runtime bergaya Node.js
  tersemat dengan `require` lokal, fs bridge, dan npm).
- **Tawaran User-Agent acak saat chat baru (v1.11.0)** — setiap kali
  **"New chat"** ditekan, muncul dialog menanyakan apakah browser tersemat
  harus memakai **User-Agent lain yang dipilih acak** (Ya, acak /
  Pertahankan). Bisa dimatikan lewat Settings → User Agent → "Tawarkan
  User-Agent acak saat chat baru" (**default aktif**).
- **Kredit pembuat di About (v1.11.0)** — Settings → About kini menampilkan
  **"Dibuat oleh Maragung"**.
- **ZIP terproteksi kata sandi (v1.12.0)** — `unzip_file` dan File Manager
  kini bisa mengekstrak **arsip zip terenkripsi**, baik **ZipCrypto**
  (enkripsi klasik) maupun **WinZip AES-128/192/256**. Tool agent menerima
  argumen **`password`** opsional — bila arsip terkunci, agent otomatis
  diminta menanyakan kata sandi ke Anda lalu mencoba lagi; di File Manager
  muncul **dialog kata sandi** saat mengekstrak arsip terenkripsi (kata
  sandi salah menampilkan pesan khusus).
- **Tombol Stop kini instan (v1.12.1)** — menekan **Stop** langsung
  **memutus koneksi streaming** ke provider (sebelumnya tombol hanya
  menandai flag yang baru dicek setelah giliran/tool selesai, jadi terasa
  mati). Jawaban sebagian tetap tampil dengan penanda *stopped*, run latar
  belakang dirilis dengan benar, dan tombol kirim tidak muncul selama run
  masih dalam proses berhenti (pesan tidak lagi tertelan diam-diam).
- **Ikon salin di setiap pesan (v1.13.0)** — setiap gelembung chat
  (yang **Anda kirim** maupun **balasan AI**) kini punya **ikon salin** di
  bawahnya. Satu ketukan menyalin **teks asli** pesan (markdown utk balasan
  AI) ke clipboard; ikon berubah jadi **centang** sebentar sebagai
  konfirmasi. Ikon tidak muncul saat jawaban masih mengalir atau pada
  pesan tanpa teks.
- **Ruang kerja terisolasi per sesi (v1.14.0)** — seperti **jendela privat
  browser**: setiap sesi chat kini punya **sandbox file sendiri** di
  `sessions/<id>/`. Unggahan, file yang dibuat agent, arsip zip, dan
  screenshot **tidak tercampur antar chat** — File Manager hanya
  menampilkan ruang kerja chat yang sedang aktif, dan agent hanya bisa
  melihat file sesinya sendiri. File lama dari versi sebelumnya otomatis
  dipindahkan ke workspace chat terakhir Anda (sekali saja). **npm
  tetap global** (package dipakai bersama), begitu juga riwayat chat,
  Context Manager, dan User-Agent.
- **Edit & regenerate pesan (v1.15.0)** — koreksi pesan yang sudah
  dikirim: ketuk **ikon pensil** di bawah gelembung pesan Anda, ubah
  teksnya, dan percakapan dilanjutkan dari titik itu (pesan setelahnya
  dipangkas). **Ikon regenerate** di balasan AI terakhir mengulang
  jawaban tanpa harus mengetik ulang.
- **Pencarian global chat (v1.15.0)** — ikon **cari** di drawer membuka
  pencarian di **semua sesi** (judul + isi pesan), lengkap dengan
  potongan kalimat yang di-*highlight*. Ketuk hasil untuk langsung
  membuka percakapan tersebut.
- **Judul sesi otomatis (v1.15.0)** — setelah balasan pertama selesai,
  sesi baru otomatis diberi **judul ringkas** oleh model (bisa dimatikan
  di Pengaturan lewat saklar *Auto title*). Rename manual tetap dihormati.
- **Perpustakaan prompt (v1.15.0)** — simpan prompt favorit (judul +
  isi) di **Prompt library** (dari drawer), lalu sisipkan ke composer
  dengan satu ketukan lewat ikon bookmark di bar input.
- **Tool web_fetch (v1.16.0)** — agent kini bisa mengambil URL langsung
  (halaman HTML, API JSON, teks) tanpa membuka browser tersemat: script
  & tag dibuang otomatis, JSON di-*pretty-print*, batas 1 MB + timeout
  20 detik. User-Agent sama dengan browser tersemat.
- **Tool git (v1.16.0)** — `git_clone`, `git_status`, `git_commit`,
  `git_push`, `git_log` bekerja di **workspace sesi aktif** (terisolasi
  per chat) lewat isomorphic-git di runtime JS tersemat; package
  terpasang otomatis saat pertama dipakai. Token repo dilewatkan
  lewat argumen (tidak pernah ditulis ke disk).
- **Vision hemat payload (v1.16.0)** — gambar terlampir otomatis
  **diturunkan skalanya** (sisi panjang maks 1568px, rasio terjaga;
  PNG kecil tetap PNG) sebelum dikirim sebagai data URL, jadi foto
  resolusi tinggi tidak lagi menggembungkan setiap pesan.
- **Ekspor chat Markdown (v1.17.0)** — menu drawer **Ekspor chat
  (Markdown)** menulis percakapan aktif sebagai file `.md` yang rapi
  (peran, model, timestamp, daftar tool call, lampiran) di folder
  `exports/` — siap dibagikan atau diarsipkan.
- **Backup terenkripsi .zabak (v1.17.0)** — **Pengaturan → Backup &
  pulihkan**: satu file **AES-256 terenkripsi** (PBKDF2 150 ribu
  iterasi + HMAC-SHA256, encrypt-then-MAC) berisi SEMUA chat, seluruh
  pengaturan (termasuk API key) dan Manajer Konteks. Pulihkan =
  verifikasi passphrase dulu, baru mengganti isi aplikasi.
- **Statistik token (v1.17.0)** — menu drawer **Statistik token**:
  total token prompt/jawaban, jumlah giliran, dan rincian **per model**
  — dihitung dari pemakaian yang dilaporkan provider per permintaan
  (`stream_options.include_usage` + fallback retry otomatis untuk
  provider yang menolak parameter itu).
- **Kunci aplikasi (v1.18.0)** — **Pengaturan → Kunci aplikasi**:
  aktifkan lock screen dengan **sidik jari/biometrik** + **PIN
  cadangan** (hash SHA-256 bergaram, disimpan di luar backup).
  Terkunci saat aplikasi dibuka & kembali dari latar belakang.
- **Notifikasi tugas selesai (v1.18.0)** — saat proses agent selesai
  **di latar belakang**, muncul notifikasi lokal "Tugas agent
  selesai"; ketuk untuk langsung membuka percakapan terkait. Bisa
  dimatikan lewat saklar *Notify when a task finishes*.
- **Isolasi browser per chat (v1.19.0)** — jendela privat kini
  **benar-benar privat**: cookie, **login**, dan storage situs
  (localStorage/sessionStorage) yang ditangkap agent di satu chat
  disimpan di sandbox chat itu sendiri dan **tidak pernah terlihat
  chat lain**. Login akun A di chat 1 dan akun B di chat 2 tetap
  terpisah meski situsnya sama; state browser tiap chat juga bertahan
  setelah aplikasi ditutup. Browser antar chat paralel tetap aman
  (operasi browser diserialisasi otomatis di belakang layar).
- **Pengerasan jendela privat (v1.20.0)** — setiap pergantian sesi chat
  kini juga **membersihkan cache HTTP bersama, seluruh web storage
  (termasuk IndexedDB) dan mendaftarkan-ulang service worker**, sehingga
  token login yang disimpan situs di IndexedDB atau respons ter-cache
  tidak bisa mengalir antar chat; registrasi service worker baru diblokir
  di browser tersemat. Runtime Node (`node_run`) kini **konteks segar
  untuk setiap eksekusi** — variabel, modul ter-cache, dan skript
  sebelumnya (termasuk rahasianya) tidak pernah bertahan lintas run
  maupun lintas chat, dan eksekusi paralel dari beberapa chat otomatis
  diserialisasi.
- **Modul chat / plugin Node.js (v1.21.1)** — pasang modul langsung dari
  file ZIP (layar *Modul* di Pengaturan) dan jalankan di dalam sesi chat:
  pilih saat membuat chat baru (chip di layar kosong), lewat menu
  interaktif **`/plugins`**, atau **`/plugins nama_modul`** di chat yang
  sudah ada. Tiap modul punya entry point `main.js` + manifest
  `module.json` (nama, versi, deskripsi, izin, host yang diizinkan,
  timeout) dan berjalan di atas **SDK resmi `zagents`** (global atau
  `require('zagents-sdk')`): `zagents.storage` (key/value per chat),
  `zagents.fs` (file, terkurung di direktori state modul per chat),
  `zagents.http` (jaringan dengan izin + allowlist host, header khusus,
  `timeoutMs`, `headOnly` untuk SSE; identitas User-Agent SELALU dari
  Setelan → User Agent pengguna — `zagents.info.userAgent` terbaca dan
  tidak bisa digantikan modul),
  `zagents.chat.emit` (kirim output ke percakapan), `zagents.info` (termasuk
  `prompt` — pesan aktivasi pertama, untuk perintah setup modul) dan
  **`zagents.agent.compose` (v1.22.0, izin `agent`)** — modul meminta
  **agen chat sendiri** menyusun SATU kalimat sesuai kebutuhan dari konteks
  live yang modul suplai; tanpa template/kumpulan pesan siap pakai, semua
  keluaran lolos gerbang host (satu kalimat santai berbahasa Inggris,
  tanpa karakter `! : ; — – ?`, batas kata, anti-ulang, retry perbaikan +
  sanitize deterministik). Dokumentasi SDK resmi tersedia in-app (EN/ID)
  di layar Modul, dan lengkap di repo: **`sdk/`** (SDK + definisi
  TypeScript), **`samples/`** (5 modul contoh siap pasang, termasuk
  **onhomeroom-daily** — bot harian app.onhomeroom.com yang setiap
  kalimatnya disusun agen chat), **`docs/modules/`** (referensi resmi EN+ID).
  **Isolasi private window per chat**: proses/konteks JS segar setiap
  eksekusi, storage & state & konfigurasi terpisah per (chat, modul),
  izin diminta saat aktivasi dan ditegakkan dua lapis (SDK + bridge
  Dart), batas sumber daya (timeout, cap output & storage), dan
  penghentian modul yang aman (nonaktif/Stop membatalkan eksekusi tanpa
  kehilangan data yang sudah tersimpan). **Uninstall oleh pengguna**:
  modul dihapus langsung dari layar Modul atau menu /plugins (ikon
  tempat sampah + konfirmasi) — file program dihapus, chat yang memakai
  otomatis dinonaktifkan, data per-chat tetap aman di sandbox masing-masing.
- **Pencarian + paging universal (v1.6.0)** — SEMUA list di aplikasi memakai
  widget `PagedList` yang sama: **5 item per halaman** (termasuk dropdown model),
  kolom pencarian, pager first/prev/next/last, dan empty state "No results".
  Berlaku untuk: daftar model (picker + hasil fetch di editor provider), daftar
  provider, riwayat chat (drawer), File Manager, Context Manager, dan library
  npm — masing-masing dengan hint pencarian berbahasa.
- **Database 500 User-Agent + Mode UA (v1.7.0)** — database internal berisi
  **500 User-Agent unik & realistis** (250 PC/desktop + 250 Android; Chrome,
  Edge, Firefox, Safari, Opera, Samsung Internet, Vivaldi) yang dibangkitkan
  dan divalidasi otomatis (`scripts/gen_user_agents.py` + unit test):
  - format 100% mengikuti browser asli — versi Edge/EdgA selalu sama dengan
    Chromium-nya, Samsung Internet dipetakan ke Chromium bundel sebenarnya,
    UA ponsel membawa token `Mobile` sementara tablet tidak, dan versi Android
    selalu masuk akal untuk model perangkatnya (Samsung, Pixel, Xiaomi, OPPO,
    vivo, realme, OnePlus, Motorola, dll. — tanpa vendor palsu),
  - **Settings → User Agent**: dropdown **Auto / PC/Desktop / Android Mobile**.
    *Auto* memakai identitas Android yang sesuai perangkat (mesin browser-nya
    memang Android WebView — paling jujur & stabil); PC/Desktop membatasi ke
    kategori desktop dan sekaligus mengubah viewport ke rendering "desktop
    site" agar lingkungan browser konsisten dengan identitasnya,
  - **pilihan sticky per sesi**: UA aktif tersimpan dan tidak berubah sendiri;
    rotasi hanya lewat tombol eksplisit dan berputar tanpa duplikasi sampai
    satu siklus penuh (500 entri) — kestabilan sesi & kompatibilitas situs
    diutamakan, tanpa pengacakan identitas berlebihan,
  - diterapkan konsisten ke seluruh WebView agent (browser automation per
    navigasi + runtime JS/fetch), bukan sekadar ganti identitas.
- **Dwibahasa** — antarmuka **English (default)** dan **Bahasa Indonesia**;
  ganti lewat ikon 🌐 di app bar atau **Settings → Language** (pilihan tersimpan).
- **UI gelap ala Z.AI** — model chip, toggle Agent, kartu tool call dengan status
  live, preview screenshot (tap untuk zoom), drawer riwayat percakapan.
- **Edge-to-edge yang aman** — di Android 15/16 (targetSdk 35/36) konten tidak pernah
  tertutup status bar atas maupun navigation bar bawah: mode edge-to-edge dideklarasikan
  eksplisit, semua layar memakai `SafeArea`, sheet model menghitung inset keyboard,
  dan app bar adaptif di layar sempit.
- **Multi-session paralel** — buka sesi baru sementara agent lain masih bekerja;
  badge progres di riwayat, rename (long-press), dan background refcount.
- **Tema Light / Dark / System** — persisten, system bar ikut menyesuaikan.
- **API key per-preset** — setiap preset provider menyimpan base URL + key + model
  sendiri; migrasi otomatis dari key lama.
- **Max agent steps 1–100** — slider + input angka kustom tervalidasi.
- **Upload file untuk AI** — gambar → vision parts (base64), file teks → inline ke
  prompt, biner → metadata.
- **Context Manager** — blok prompt reusable (CRUD + toggle aktif) yang disuntikkan
  ke system prompt setiap permintaan.
- **File Manager** — jelajahi dokumen app: preview, share, rename, hapus,
  **copy/cut/paste**, **zip/unzip**.
- **Runtime Node.js-style + npm otomatis** — engine JS tersemat di headless WebView;
  agent mengelola package dari registry npm sendiri.
- **Import/export sesi** — backup seluruh percakapan ke JSON + share, impor aman
  dengan id baru.
- **Tahan crash** — semua operasi rentan (WebView, file IO, stream SSE, pembukaan
  riwayat yang korup) ditangani sebagai error terkontrol; tidak ada exception yang
  membuat aplikasi mati.
- **Riwayat lokal** — percakapan disimpan sebagai JSON di penyimpanan privat app.

## 📲 Cara pakai

1. Unduh APK terbaru dari halaman [**Releases**](https://github.com/SecretArrow/ZAgents/releases).
2. Instal (izinkan instal dari sumber tidak dikenal bila diminta).
3. Buka **Settings → AI provider** → layar **Providers** → ketuk provider
   (mis. OpenRouter / **InferHub**) → isi **API key** → ketuk **Save API key**
   → ketuk **Fetch models** untuk menarik daftar model yang tersedia di
   provider tersebut, pilih modelnya (atau lewat chip model di chat:
   pilih yang mendukung tool calling — Claude, GPT, Gemini, DeepSeek, Qwen,
   GLM, dll) → **Save**.
4. (Opsional) **Settings → Language**: default **English**, tersedia **Bahasa Indonesia**.
5. Kembali ke chat, aktifkan pill **Agent**, dan mulai bertanya.

> ⚠️ API key hanya disimpan di penyimpanan lokal perangkat (SharedPreferences)
> dan tidak pernah dikirim ke mana pun selain provider yang Anda pilih.

## 🏗️ Arsitektur

```
lib/
├── main.dart                  # entry point (override settings repo)
├── di.dart                    # riverpod providers (DI)
├── l10n/app_strings.dart      # string EN (default) + ID + delegate
├── models/models.dart         # ChatMessage, ToolCall, AppSettings, presets
├── services/
│   ├── llm_client.dart        # klien OpenAI-compatible (SSE + tool deltas)
│   ├── agent_controller.dart  # tool-loop: LLM → tools → hasil → jawaban
│   ├── tool_executor.dart     # dispatch 12 tools
│   ├── browser_automation.dart# headless InAppWebView + JS bridge
│   ├── chat_store.dart        # persistensi riwayat (JSON)
│   └── settings_repository.dart
├── tools/tool_defs.dart       # skema tools + system prompt agent
├── ui/
│   ├── screens/providers_screen.dart   # manajemen provider (list + aktivasi)
│   ├── screens/preset_editor_screen.dart # editor provider penuh (key, fetch models)
│   └── ...                    # theme, HomeShell, composer, bubbles, dsb.
```

Alur agent: **prompt → chat/completions (stream) → tool_calls → eksekusi →
`role:"tool"` → … → jawaban final**, dengan batas langkah (`maxSteps`) dan
tombol **stop**.

## 🧩 Mengembangkan modul (plugin) — SDK resmi

Sistem modul Node.js lengkap ada di repo, siap dipakai developer:

```
sdk/                    # SDK resmi "zagents" untuk modul chat
├── zagents-sdk.js      #   shim require('zagents-sdk') (juga di-bundle in-app)
├── index.d.ts          #   definisi TypeScript — autocomplete penuh di editor
├── package.json        #   metadata npm
└── README.md           #   quick start developer
samples/                # 4 modul contoh siap ZIP + install:
├── counter/            #   izin storage — penghitung per chat
├── network-fetcher/    #   izin network — zagents.http + allowedHosts
├── file-notes/         #   izin files — filesystem tersandbox di state/
├── chat-streamer/      #   izin chat — output bertahap chat.emit
└── README.md           #   cara paket ZIP + install + expected output
docs/modules/
├── sdk-reference-en.md # referensi resmi EN (manifest, API, isolasi)
├── sdk-reference-id.md # referensi resmi ID
└── README.md           # indeks + checklist manifest
```

Contoh cepat (`samples/counter/main.js`):

```js
async function main() {
  const previous = (await zagents.storage.get('count')) || 0;
  await zagents.storage.set('count', previous + 1);
  zagents.log('Activations in THIS chat:', previous + 1);
  return { activationsInThisChat: previous + 1 };
}
module.exports = main();
```

Paket & pasang:

```bash
cd samples/counter && zip -r ../../hello-counter.zip .
# aplikasi → Settings → Modules → Install module → pilih ZIP
# di chat: ketik /plugins (menu interaktif) atau /plugins hello-counter
```

Test penjaga (`test/unit/module_sdk_assets_test.dart`) memvalidasi
kelengkapan ketiga folder tersebut — sdk, samples, docs tidak bisa
hilang atau rusak tanpa membuat test gagal.

## 🚀 CI/CD (GitHub Actions)

Semua build dilakukan di CI — tidak perlu build lokal.

| Workflow | Trigger | Isi |
|---|---|---|
| **CI** (`ci.yml`) | push `main`, PR | `dart format` check, `flutter analyze`, unit + widget tests, **E2E di emulator Android** (push main), dan job **auto-fix** (`dart fix --apply` + `dart format`, commit otomatis) bila analyze gagal |
| **Release** (`release.yml`) | tag `v*` / manual | quality gate → `flutter build apk --release` → **GitHub Release otomatis** dengan APK + release notes |

Optimasi kecepatan: cache pub + Flutter SDK (`flutter-action cache`), cache
Gradle, `concurrency` cancel-in-progress, e2e emulator hanya di `main`,
APK hanya di-build saat rilis.

### Membuat rilis baru

```bash
# bump version di pubspec.yaml (mis. 1.0.0+2), lalu:
git tag v1.0.1
git push origin v1.0.1
# → workflow Release terbitkan APK ke GitHub Releases otomatis
```

### Menjalankan dari source

```bash
flutter pub get
flutter run            # perangkat/emulator terpasang
flutter test           # unit + widget
flutter test integration_test   # e2e (butuh emulator)
```

## 🔒 Catatan keamanan

- Jangan pernah commit API key atau token GitHub ke repo ini.
- Jika token GitHub pernah dibagikan di tempat publik, **rotasi/ revoke**
  token tersebut di *Settings → Developer settings*.
- Build release saat ini memakai debug signing; konfigurasi keystore rilis
  sendiri via secrets (`KEYSTORE_BASE64`, dll) sebelum distribusi publik.

## 🗺️ Rencana lanjutan

- [ ] Signing config rilis via GitHub Secrets
- [ ] Ekspor/impor riwayat chat
- [ ] Mode multi-image / attachment
- [ ] Preview "browser inspector" layar penuh secara real-time
