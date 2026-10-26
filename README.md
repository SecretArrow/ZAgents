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
  `prompt` — pesan aktivasi pertama, untuk konfigurasi ulang modul, dan
  `setup` — nilai formulir setup per chat) dan
  **`zagents.agent.compose` (v1.22.0, izin `agent`)** — modul meminta
  **agen chat sendiri** menyusun SATU kalimat sesuai kebutuhan dari konteks
  live yang modul suplai; tanpa template/kumpulan pesan siap pakai, semua
  keluaran lolos gerbang host (satu kalimat santai berbahasa Inggris,
  tanpa karakter `! : ; — – ?`, batas kata, anti-ulang, retry perbaikan +
  sanitize deterministik). **Formulir setup per chat (v1.24.0)**: modul
  yang mendeklarasikan blok `setup` di manifestnya otomatis memunculkan
  formulir di chat — input wajib dikumpulkan aplikasi SEBELUM run pertama
  (banner + bottom sheet, tombol "Simpan dan jalankan"); setelah dikirim,
  nilai tersimpan per chat (kunci kooperatif `zagentsSetup`), modul
  langsung dijalankan, dan chat lain bertanya lagi sesuai desain isolasi.
  **Module doctor (v1.26.0)**: chat agent bisa mendiagnosis modul
  (`module_list`, `module_read` — baca-saja), mengekspor modul terpasang
  ke ZIP (`module_export` atau tombol Ekspor ZIP di layar Modul), dan
  menyiapkan perbaikan (`module_stage_repair`) yang SELALU butuh
  konfirmasimu di kartu "Install/Buang" sebelum dipasang — agent tidak
  pernah bisa memasang modul diam-diam. **Module builder (v1.27.0)**:
  ketik **`/make_plugins <deskripsi>`** di chat yang sedang berjalan
  (alias `/make_plugin`, `/make_module`) untuk meminta agent MEMBUAT
  plugin baru dari dalam chat — dengan atau tanpa data sesi (file
  unggahan/konteks chat ikut disalin ke dalam modul bila kamu menyebutnya,
  jadi zip-nya self-contained); agent menyusun `module.json` + entry
  CommonJS, mengemas zip, memvalidasi, lalu memunculkan kartu Install
  yang tetap butuh konfirmasimu. Intersepsi gagal-setup (v1.25.0):
  modul yang error "setup required" memunculkan formulirnya otomatis
  atau panduan solusi (zip lama / perintah setup).
  Dokumentasi SDK resmi tersedia in-app (EN/ID)
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
- **v1.28.0 — fan of subagents, exit confirmation & keandalan total**:
  1. **Fan of subagents**: minta agent bekerja paralel — "buat 5 subagents,
  masing-masing riset satu pesaing" — dan agent memanggil `spawn_subagents`
  dengan 2–6 tugas mandiri yang dijalankan BERSAMAAN (LLM call paralel,
  3 pekerja konkuren). Setiap subagent punya loop sendiri dengan toolset
  ruang kerja (file/zip/node/web_fetch/git lokal — tanpa browser, tanpa
  rekursi, langkah dibatasi) di sandbox chat yang sama, dan hasilnya
  kembali berlabel per tugas untuk dirangkum agent. Tombol Stop langsung
  menghentikan seluruh fan.
  2. **Dialog konfirmasi keluar**: tombol back di layar utama kini
  menanyakan "Keluar dari ZAgents?" (Ya/Tidak) — tekanan back tidak
  lagi menghentikan tugas agent yang sedang berjalan tanpa sengaja.
  3. **Keandalan latar belakang**: tile baru di Setelan ("Keandalan
  latar belakang") meminta pengecualian optimisasi baterai Android
  (Doze/OEM) lewat dialog sistem; wake lock kini diperpanjang otomatis
  pada setiap langkah progres sehingga sesi "run until done" yang sangat
  panjang tidak pernah tertidur di tengah jalan.
  4. **Anti-ANR ("app not responding")**: encode/decode JSON percakapan
  (besar bisa >1 MB) dan kripto backup PBKDF2-150k kini berjalan di
  background isolate — daftar chat, simpan otomatis, pencarian global,
  dan backup tidak lagi membekukan UI; sinkronisasi streaming juga
  dikoalesksi (~20 fps) agar transkrip panjang tetap mulus.
- **v1.29.0 — chat menunggu input modul & folder chat di file manager**:
  1. **Gerbang input pengguna sebelum chat dikerjakan**: saat pesan
  dikirim dan modul terpilih (atau modul aktif di chat itu) masih
  membutuhkan isian setup per-chat, **pesan masuk antrean** — tampil di
  transkrip, tersimpan, dengan banner + formulir setup — dan **agent
  baru mengerjakannya tepat setelah formulir dikirim** (modul berjalan
  dengan isian barunya, lalu agent merespons pesan yang menunggu).
  Chat tidak pernah dikerjakan tanpa input yang diminta modul; mengirim
  pesan lagi selagi menunggu hanya menambah antrean, dan menonaktifkan
  modul penghambat langsung melepas pesan yang menunggu.
  2. **Folder chat di file manager perangkat**: File Manager kini punya
  tombol **ekspor folder chat** — seluruh ruang kerja chat (data.json,
  uploads, state modul, file buatan agent) tersalin ke
  **`Download/ZAgents/<judul-chat>/`** lewat MediaStore (Android 10+,
  tanpa izin apa pun; versi lama: di-zip lalu dibagikan). Ekspor ulang
  menggantikan salinan lama. Selain itu modul yang menulis file dengan
  path relatif (`zagents.fs.writeFile('data.json', …)`) kini benar-benar
  masuk ke folder `state/` milik chat masing-masing (sebelumnya ditolak
  sandbox), menghapus chat ikut menghapus folder kerjanya, dan File
  Manager tanpa chat aktif menampilkan panduan "buka chat dulu" — bukan
  lagi root bersama yang mencampur file antar chat.
- **v1.30.0 — auto retry, tugas tidak mati kena jaringan & tombol Stop merah**:
  1. **Auto retry dua lapis**: error jaringan, koneksi lemah, aliran
  streaming terputus, dan error sementara provider (HTTP 408/425/429/5xx)
  tidak lagi mematikan tugas agent. Lapis pertama mencoba ulang giliran
  LLM yang gagal langsung di tempat (catatan "reconnecting" tampil di
  gelembung, lalu tergantikan konten hidup); lapis kedua melanjutkan run
  yang mati di tengah jalan dari transkrip tersimpan dengan catatan
  "Auto retry n/N — resuming" di chat. Error permanen (401/400/404/422)
  tidak diboroskan percobaannya, dan **Stop selalu menang** — tidak ada
  retry setelah Anda menekannya.
  2. **Lanjut otomatis saat rencana belum selesai**: bila run berhenti
  (batas langkah habis / model menyimpulkan terlalu cepat) padahal todo
  plan masih ada yang belum selesai, tugas diangkat kembali otomatis
  sampai budget percobaan habis.
  3. **Opsi custom di Pengaturan → Auto retry**: saklar aktif/nonaktif
  (default aktif), slider **maks. percobaan** (1–10, default 3), dan
  slider **jeda antar percobaan** (0–60 detik, default 5 — jeda membesar
  tiap percobaan: jeda × percobaan).
  4. **Tombol Stop kini merah** (bukan abu-abu permukaan) — kontrol
  interupsi terlihat jelas, dan gagal-turn tidak lagi meninggalkan
  gelembung "thinking" abadi di transkrip.
- **v1.31.0 — perintah slash modul & kontrol mode pesawat (root)**:
  1. **Perintah slash untuk modul (`commands` di module.json)**: modul
  kini bisa mendeklarasikan kata kunci slash, mis. `"commands":
  ["airplane"]`. Ketik **`/airplane on`**, **`/airplane off`** atau
  **`/airplane status`** di chat — dari pesan pertama chat baru maupun di
  tengah chat — dan pesan itu **dijalankan modulnya langsung tanpa LLM**
  (pesan mentah tiba sebagai `zagents.info.prompt`). Bila modul belum
  aktif, perintah **mengaktifkannya otomatis** (persetujuan izin tetap
  berlaku); modul ter-stage yang mendeklarasikan kata kunci yang diketik
  mengonsumsi pesan pertama seperti biasa. Disanitasi ketat (huruf kecil
  `[a-z0-9_-]`, maks 4 kata kunci, `plugins`/`make_plugins`/`doctor`
  dicadangkan).
  2. **Izin `device` + `zagents.device.shell`**: modul dengan izin
  `device` (disetujui saat aktivasi) dapat menjalankan SATU perintah
  shell di perangkat — `su -c` di ponsel root, `sh -c` tanpa root —
  dengan hasil terstruktur (exitCode/stdout/stderr/timedOut/error),
  batas perintah 2000 karakter, timeout 1–120 dtk (bawaan 30 dtk), dan
  stdout/stderr dibatasi 32 KB. Digerbang tiga lapis: izin manifest →
  **sakelar "Perintah perangkat (root)" di Setelan → Modul (mati
  bawaan)** → bridge native (`zagents/device`).
  3. **Modul sampel Airplane Mode**: `samples/airplane-mode/` (plus ZIP
  siap pasang) — pengalih mode pesawat untuk ponsel root: cek su,
  `cmd connectivity airplane-mode` dengan fallback `settings put` +
  broadcast, dan **verifikasi baca-balik** `settings get global
  airplane_mode_on` sehingga laporannya selalu keadaan perangkat
  sebenarnya.
  4. Dokumentasi SDK (EN/ID, termasuk yang di dalam aplikasi), typings
  TypeScript, dan guard arsip sampel diperluas untuk `device` +
  `commands`.
- **v1.33.0 — agen melihat status setup modul: tidak lagi meminta kredensial dua kali**:
  1. **Status setup per-chat di prompt sistem**: setiap modul aktif kini
  melaporkan ke agen apakah form setup-nya sudah **COMPLETED** untuk
  chat ini (nilai non-rahasia ditampilkan, field password **selalu
  disamarkan `********`**) lengkap dengan instruksi tegas untuk tidak
  meminta kredensial yang sudah diisi — atau **NOT completed** sehingga
  agen tahu form app yang mengumpulkannya, bukan dia.
  2. **`module_list` lapangan**: hasil tool kini menyertakan
  `setup for this chat: COMPLETED (Email: …, Password: ********)` atau
  `NOT completed` per chat — agen tidak perlu menebak lagi saat
  mendiagnosis modul.
  3. **Prefill lintas chat**: form setup di chat baru otomatis terisi
  nilai terakhir yang pernah Anda kirim untuk modul yang sama di chat
  lain (nilai chat aktif tetap menang per field; Save & run tetap
  wajib — isolasi per-chat tidak berubah).
  4. `SessionSandbox.sessionsRoot()` + `ModuleRuntime.latestStoredSetup`
  (pemindai mtime terbaru, tahan file korup) + uji unit wire/module_list.
- **v1.41.6 — isolasi form modul per chat & Plan kembali di atas
  thinking**: (1) bug prefill lintas chat dihapus — form setup modul di
  sebuah chat kini **hanya** menampilkan nilai yang pernah diisi di chat
  itu sendiri (kosong bila belum pernah); pemindai `latestStoredSetup`
  yang menyalin isian dari chat lain sudah dihapus total, persistensi
  per-chat dan gerbang Save & run tidak berubah. (2) Rencana/todos live
  kini dirender **inline tepat di atas baris "thinking"** saat agent
  berjalan (penempatan v1.36 ke bawah, sesuai permintaan), sementara
  panel tersemat di atas daftar otomatis mundur selama run dan kembali
  sendiri saat run selesai — flag buka/tutup tetap global sehingga
  perpindahan langkah, akhir run, dan pindah chat tidak pernah
  menutupnya.
- **v1.45.0 — dua modul resmi baru: asisten Fanspage Facebook & asisten X/Twitter + SDK `agent.polish`**:
  (1) **SDK baru `zagents.agent.polish`** — menulis ulang template balasan menjadi SATU balasan
  sosial yang natural seperti manusia (1–3 kalimat, tanda baca normal, bahasa mengikuti
  pengirim, anti-repetisi, tanpa markdown/link rekaan/frasa asisten, anggaran karakter
  20–500) melalui LLM chat sendiri dengan pipeline validate → retry → sanitize →
  re-validate yang sama ketatnya dengan `compose`. (2) **Modul `facebook-page`** (`/fb`) —
  asisten fanspage: "auto-login" via Page Access Token (formulir setup per-chat, divalidasi
  ke Graph API `/me`, tidak pernah di-log), auto-reply pesan Messenger DAN komentar post
  dengan 8 keluarga template (greeting/question/price/shipping/thanks/complaint/generic/away)
  yang dipoles AI secara live, klasifikasi intent kata kunci ID+EN, delay human-like
  acak, dedupe seen-ID (tidak pernah balas dua kali), burst auto-watch `/fb auto`,
  editor template, toggle per kanal. (3) **Modul `twitter-x`** (`/tw`) — auto-reply mention:
  OAuth 1.0a murni-JS (penanda tangan diverifikasi terhadap worked example resmi docs X),
  template + AI polish, dedupe dengan backoff gagal, `/tw tweet` + `/tw reply` manual,
  penanganan tier jujur (Free = posting saja; baca butuh Basic). Kedua modul terdaftar
  di katalog in-app (15 modul resmi), dilengkapi README cara mendapat token/keys, dan
  zip siap instal di `samples/`.
- **v1.44.0 — keamanan, pembaruan, multimodal, suara, ekosistem modul, aksesibilitas, bahasa ke-3**:
  (1) **API key terenkripsi** — kunci provider LLM tidak lagi tersimpan plaintext di
  SharedPreferences: kini berada di `flutter_secure_storage` (Android Keystore), dipisah
  lewat abstraksi `SecretBox`, dengan migrasi sekali-jalan yang crash-safe (salinan aman
  ditulis DULU baru plaintext di-strip, idempoten, key lebih baru di secure storage selalu
  menang) dan degradasi jujur bila secure storage gagal. (2) **Pemeriksa pembaruan** —
  satu ping GitHub Releases saat startup (bisa dimatikan di Settings → Help & About) +
  banner "Pembaruan tersedia" di atas chat dengan tombol salin tautan rilis; tersedia
  juga tombol "Periksa sekarang" dengan status versi terkini. (3) **Build AAB** —
  release CI kini menghasilkan 5 artefak: 4 APK split + `ZAgents-<versi>.aab`
  (tanda tangan kunci sama, diverifikasi `jarsigner`, menolak sertifikat debug) — siap
  untuk Google Play Console. (4) **Optimasi lampiran gambar** — file chooser tetap satu,
  tapi gambar kini melewati pipeline validasi magic-byte, gate 20 MB, downscale sisi
  panjang 1600 px (JPEG q85, PNG tetap PNG, GIF diambil frame pertamanya), copy-through
  untuk file kecil, dan disimpan ke `attachments/` sandbox chat masing-masing (isolasi
  per chat penuh, agent membacanya lewat tool fs chat itu sendiri). (5) **Dikte suara** —
  tombol mikrofon di composer: tekan untuk mendikte (RECORD_AUDIO diminta saat pakai),
  pratinjau parsial live di atas field, hasil final menyatu ke draft chat yang terikat
  (pindah chat otomatis menghentikan sesi suara), locale mengikuti bahasa aplikasi
  (en_US/id_ID/es_ES), perangkat tanpa mesin STT menyembunyikan kegagalan dengan pesan
  jelas. (6) **Ekosistem modul** — install ulang zip versi baru kini melaporkan transisi
  versi ("Updated name vX → vY") dan Modules screen menghadirkan katalog "Modul contoh
  resmi" berisi 13 modul bawaan repo beserta slash command-nya. (7) **Aksesibilitas** —
  pass TalkBack pertama: tooltip/semanticLabel untuk kontrol ikon, MergeSemantics untuk
  kartu & baris status, spinner diberi label, ikon status todo berlabel. (8) **Bahasa
  Spanyol** — paket string `es` lengkap (paritas 406/406 member dengan EN), tersedia di
  pemilih bahasa dan mengikuti seluruh fitur baru.
- **v1.43.1 — hardening isolasi antar chat pada `zagents.fs` (module mode)**:
  audit isolasi penuh menutup celah teoretis terakhir. Selama ini semua
  state modul memang per chat (`zagents.storage` →
  `sessions/<chatId>/modules/<nama>/storage.json`, setup form per chat,
  identitas WebView di-swap total saat pindah chat), tetapi sandbox fs
  memasukkan juga direktori **program modul yang global** ke dalam akar
  yang boleh diakses — dua chat yang menjalankan modul yang sama secara
  teori dapat bertukar data lewat folder kode bersama itu. Sekarang
  setiap aksi tulis (`writeFile`/`appendFile`/`mkdir`/`unlink`) pada run
  modul **wajib** berada di bawah `state/` modul untuk chat itu
  (dieksekusi di sisi Dart, bukan hanya di SDK JS): folder program global
  dan root npm menjadi read-only bagi modul, pembacaan kode untuk
  `require` tetap berjalan. Bonus perbaikan: plain run (`node_run`) pada
  runtime JS bersama tidak lagi mewarisi flag module-mode dari run modul
  sebelumnya. Dokumen referensi SDK (EN+ID) diselaraskan; test regresi
  `zIsUnderRoot` menambatkan jaminan (prefix sibling seperti
  `state-old` tidak pernah dianggap di dalam, pelarian `..` hasil
  normalisasi selalu ditolak).
- **v1.43.0 — 6 sample module baru di `samples/` (masing-masing dengan zip siap-install)**: (1) **Web Browser** (`/web`) — browser mode-teks di dalam chat: buka URL apa pun dalam mode pembaca (skrip/style/nav/footer dibuang, `<article>/<main>` diprioritaskan, heading & bullet dipertahankan, entitas diterjemahkan), tabel link bernomor dengan `/web goto <n>`, paginasi `/web more`, riwayat navigasi, pratinjau JSON mentah, dan pencarian 5 mesin berlapis (DuckDuckGo Lite/HTML → Mojeek → Wikipedia → DuckDuckGo Instant Answers); pesan biasa saat module di-stage diperlakukan seperti address bar. Izin jaringan sengaja tanpa `allowedHosts` karena sebuah browser harus bisa menjangkau situs apa pun — sisanya tetap terisolasi per chat. (2) **RSS Reader** (`/rss`) — pembaca RSS 2.0 + Atom per chat: parser regex toleran (CDATA, namespace, `link@href` alternate, link relatif diabsolutkan), langganan dengan hitung belum-baca, digest gabungan terbaru-di-atas, `/rss refresh` hanya melaporkan item BARU terhadap peta `seen` per chat, berhenti berlangganan dua langkah. (3) **QR Code** (`/qr`) — QR asli yang bisa dipindai kamera, dirender sebagai seni blok Unicode di chat: **tanpa izin sama sekali**, encoder murni-JS lengkap (byte mode, versi 1-25, Reed-Solomon GF(256), interleaving blok, bit format/versi BCH, 8 mask dengan penilaian penalti spesifikasi) yang matriksnya terverifikasi **identik sel-per-sel** dengan pustaka referensi Nayuki dan 9/9 hasilnya didekode balik oleh OpenCV; `/qr wifi ssid | sandi` menghasilkan payload WIFI:. (4) **Authenticator TOTP** (`/otp`) — RFC 6238 per chat: SHA-1/SHA-256/SHA-512 + HMAC + Base32 murni-JS, **seluruh 18 vektor resmi RFC 6238 lolos**, ekspor `otpauth://` yang pas dengan `/qr`, hapus dua langkah; **tanpa izin jaringan** — rahasia mustahil keluar perangkat. (5) **Data Studio CSV** (`/csv`) — analisis data per chat: parser RFC 4180 (kutipan, koma/newline di dalam kutipan, deteksi otomatis `,`/`;`/tab), tipe kolom otomatis, statistik (min/max/mean/median/std/unik), sort/filter numerik, grafik batang ASCII + histogram; dataset ≤56 KB per chat. (6) **Currency & Units** (`/cur` + `/unit`) — kurs mid-market langsung dari open.er-api.com (tanpa kunci API) yang **dikunci allowlist manifest** dengan cache per chat 6 jam, alias ramah (rupiah, euro, yen…), plus mesin konversi satuan offline 8 kategori (panjang/massa/data/kecepatan/volume/luas/waktu/suhu) dengan alias jamak, simbol, dan singkatan. Semua zip berada di `samples/<nama>.zip` ter-guard test identitas isinya terhadap foldernya, dan salinannya tersedia untuk diunduh.
- **v1.42.1 — sample module baru: EVM Wallet per chat di `samples/`**:
  contoh modul lengkap siap-install (`samples/evm-wallet/` + zip) yang
  menghadirkan dompet EVM per chat via perintah slash `/wallet` —
  **GENERATE-ONLY** (akun baru acak per chat, tanpa import; seed phrase
  dan private key lama tidak pernah diminta, selaras dengan garis merah
  keamanan Web3 aplikasi), alamat EIP-55 checksum, saldo native + ERC-20,
  harga gas, 10 jaringan terverifikasi (Ethereum, Sepolia, BSC, Polygon,
  Arbitrum, Base, OP Mainnet + 3 testnet; default **Sepolia**), dan
  transfer bertanda tangan EIP-155 dengan kripto murni-JS tanpa
  dependensi npm (Keccak-256, secp256k1, nonce deterministik RFC 6979,
  RLP). Setiap transfer wajib konfirmasi dua langkah: `/wallet send`
  menampilkan ringkasan penuh (dari/ke/jumlah/biaya/nonce/chain id),
  `/wallet confirm` menandatangani + menyiarkan, `/wallet cancel`
  membatalkan; tawaran tertunda kedaluwarsa 10 menit dan tidak pernah
  lolos pergantian jaringan. RPC dibatasi `allowedHosts` manifest dan
  seluruh endpoint diverifikasi langsung sebelum dikirim; tanda tangan
  direproduksi byte-per-byte dengan vektor kanonik spesifikasi EIP-155
  dan dicek silang dengan OpenSSL.
- **v1.42.0 — notifikasi per chat aktif & tombol Stop/Force stop**:
  (1) **Notifikasi per chat aktif** — setiap chat yang sedang berjalan
  kini memasang notifikasinya sendiri (judul chat + langkah/tool yang
  sedang dieksekusi), selain notifikasi agregat foreground service;
  ketuk notifikasi untuk langsung membuka chat tersebut (deep link
  pending-session kini juga di-drain saat app resume, bukan hanya saat
  cold start), izin POST_NOTIFICATIONS diminta sekali secara runtime
  untuk Android 13+, dan notifikasi per chat otomatis dibersihkan saat
  run selesai/berhenti/service mati. (2) **Tombol Stop 1x klik + Force
  stop 3x klik** — ketukan pertama menghentikan proses secara
  kooperatif; ketukan kedua menampilkan petunjuk eskalasi; ketukan
  ketiga menampilkan dialog tawaran **Force stop** (wajib konfirmasi)
  yang langsung memutus transport HTTP run tersebut via registry
  per-run `LlmClient.forceCancel` — stream yang macet tanpa delta pun
  langsung mati, lalu jalur release standar (marker stopped, persist,
  rilis state/background) yang teruji mengambil alih. Klien HTTP kini
  per-request sehingga force-kill satu chat tidak pernah menyentuh
  chat lain yang masih streaming. Bantuan in-app bertambah topik 11
  (notifikasi per chat & Stop/Force stop, dua bahasa).
- **v1.41.5 — User-Agent 153+ & layar Help/About**: seluruh database
  User-Agent di-refresh ke generasi terkini — semua browser berbasis
  Chromium (Chrome, Edge, Opera, Samsung Internet, Vivaldi) kini memakai
  Chromium **153–157** saja (tidak ada lagi token ≤ 150), Firefox memakai
  rilis terbaru (150–158) plus ESR aktif (140.x/153.x), Safari 26.x/27.x,
  dan pool perangkat bertambah Galaxy S25, Pixel 10, dan Android 16/17
  (total 1000 identitas tervalidasi). Halaman Settings kini punya menu
  **Help & About**: Bantuan (panduan lengkap 11 topik dua bahasa) dan
  Tentang (layar about baru yang rapi: versi, pembuat, isi aplikasi,
  disclaimer) — masing-masing di Activity/screen tersendiri.
- **v1.41.4 — APK split per-ABI di release**: GitHub Actions kini
  membangun 4 APK bertanda tangan per rilis — universal (semua ABI,
  nama tidak berubah) + tiga split `arm64-v8a`, `armeabi-v7a`, `x86_64`
  (`--split-per-abi`, unduhan lebih kecil). Semua APK diverifikasi
  apksigner (universal + tiap split, anti debug-sign), dan step artefak
  gagal cepat bila jumlah APK kurang dari 4.
- **v1.41.3 — perbaikan test skill_update**: asersi status pasca-update
  kini membaca instance yang melakukan update + pembaca disk baru (cache
  registry bersifat per-instance sesuai pola ModuleRegistry; produksi
  memakai satu singleton sehingga tidak terdampak).
- **v1.41.2 — perbaikan version-peek skill_update**: _peekManifestVersion
  mengikuti pipeline install (strip prefix) sehingga perbandingan versi
  bekerja untuk arsip ber-folder; sumber tersimpan mempertahankan @branch;
  dua temuan analyzer (null-aware element, doc comment) ditutup.
- **v1.41.1 — perbaikan test deterministik**: `message_actions_test`
  (dua kali kirim di satu sesi) sempat menggantung karena release run
  menunggu persist final, sementara IO nyata tidak pernah selesai di zona
  FakeAsync pengujian widget — kiriman kedua terbuat tanpa jejak. Harness
  kini memakai store in-memory (pola yang sama dengan `chat_flow_test`);
  perilaku produksi tidak berubah.
- **v1.41.0 — perbaikan stabilitas storage isolate, sistem skill lebih lengkap (`skill_update`, config unset), dan perbaikan pipeline rilis**:
  1. **Storage chat anti-"unsendable"**: semua job JSON berat (save/load/
     list/bundle/search) kini dibuat lewat pabrik closure TOP-LEVEL — chain
     context yang dikirim ke `Isolate.run` tidak pernah lagi membawa `this`
     (beserta `_writeChains` berisi `_Future` yang tidak bisa dikirim).
     Dulu, dua operasi storage yang beririsan (mis. backup berjalan saat
     chat menyimpan, atau load saat save masih mengantre) melempar
     "object is unsendable" dan data tampak hilang; sekarang deterministik
     aman dan salinan yang dikirim jauh lebih kecil.
  2. **`skill_update` (tool baru)**: agen bisa menyegarkan skill dari
     sumber asalnya — unduh ulang, bandingkan versi SKILL.md, ganti atomik
     dengan config/secret tetap dipertahankan; laporan "already up to
     date" saat versi sama; skill `builtin:`/`file:` ditolak dengan
     penjelasan jujur (tidak ada update palsu).
  3. **`skill_config` lebih ketat**: kunci tidak dikenal DITOLAK beserta
     daftar field yang valid (dulu typo tersimpan diam-diam dan skill
     tetap "needs config" tanpa petunjuk); nilai `null` menghapus kunci
     tersimpan (unset), dan menghapus kunci terakhir membersihkan file
     config.
  4. **Instalasi skill lebih akurat**: URL `github.com/o/r/tree/<branch>`
     (root branch, tanpa subpath) kini terparse benar (dulu gagal dengan
     "Nothing to install"); error metadata GitHub menjelaskan 404/private/
     rate-limit; `installBundled` (skill bawaan app) kini mempertahankan
     config tersimpan saat reinstall dan menulis registry SETELAH file
     benar-benar pindah (rollback tidak lagi meninggalkan registry maya).
  5. **`skill_run` lebih transparan**: timeout yang dipaksa ke batas
     (mis. 999 → 300) atau tidak valid dilaporkan ke model; pemeriksaan
     path berbasis segmen (nama file bertitik ganda sah, tetap blokir
     `..`).
  6. **CI/CD**: workflow Release/Auto-Release/CI diperketat setelah
     v1.39–v1.40 gagal quality gate (compile error Riverpod + formatter) —
     semua permintaan fitur v1.38–v1.40 (isolasi chat, panel Plan tetap
     terbuka & real-time, performa streaming) tetap terjaga penuh oleh
     test.
- **v1.40.0 — keamanan unduhan (SSRF/zip-bomb), persistensi atomik, dan CI rilis bertanda tangan**:
  1. **`RemoteGuard`** (baru): SEMUA unduhan skill/npm lewat satu gerbang —
     hanya `https` ke host publik (loopback, LAN, link-local, CGNAT,
     multicast, dan IPv6 ULA ditolak), redirect diikuti manual per-hop
     dengan validasi ulang, dan body dibatasi sambil di-stream (endpoint
     yang berbohong soal `Content-Length` tidak bisa menghabiskan memori).
  2. **Anti zip/gzip bomb**: ukuran deklarasi central directory (zip) dan
     ISIZE (gzip) diperiksa SEBELUM dekompresi; batas total/entry/jumlah
     file tetap berlaku sesudahnya. Entry tarball npm divalidasi satu per
     satu (`..`, path absolut, drive/UNC) sebelum ada byte yang ditulis.
  3. **Persistensi chat tahan race**: tulis atomik (temp + rename) dan
     antrean per-chat — `rename`/`saveModules` yang menimpa `save` tidak
     lagi bisa mengembalikan transkrip ke versi lama. `loadTitle` membaca
     judul milik sesi itu sendiri (bukan judul chat yang kebetulan tampil).
  4. **Isolasi antar-chat**: pesan yang dikirim saat riwayat masih dimuat
     TIDAK dibuang ketika pengguna pindah chat (run lanjut di latar),
     `restoreLastChat` tidak mengganti draft yang sudah dimulai, lampiran
     composer hanya dibersihkan saat benar-benar pindah chat, dan
     `runToken` mencegah finalisasi run lama mematikan run baru.
  5. **Persetujuan instalasi skill**: `skill_install` kini memakai kartu
     konfirmasi (sumber terlihat, kode pihak ketiga tidak diunduh sebelum
     disetujui); penolakan dilaporkan sebagai tool gagal, bukan sukses.
     Reinstall mempertahankan secret `.zconfig.json` yang sudah tersimpan.
  6. **CI/CD**: rilis WAJIB bertanda tangan (gagal keras tanpa keystore),
     alias diverifikasi `keytool`, fingerprint sertifikat bisa dipin,
     APK diverifikasi `apksigner` (menolak debug signing), dan tag harus
     sama dengan versi `pubspec.yaml`.
- **v1.38.0 — Skills system nyata, isolasi antar-chat, panel Plan live, dan pass performa**:
  1. **Skills system (v1.38.0)**: 6 tool baru (`skill_install/list/info/
     config/remove/run`) — pasang skill eksternal (paket SKILL.md, mis.
     `binance/binance-skills-hub/.../binance-agentic-wallet`) langsung dari
     GitHub/URL/zip (validasi nyata: zip-slip guard, size cap, staging
     atomik), konfigurasi secret tersimpan di perangkat (tidak pernah
     di-echo ke chat), manual dibaca via `skill_info`, skrip berjalan di
     sandbox tersemat dengan env injeksi (`process.env`) — tersedia di
     semua chat (global `<docs>/skills`).
  2. **`request_confirmation`**: kartu persetujuan eksplisit untuk aksi
     tak-terbalikkan (transaksi Web3, approval token) — loop agen BERHENTI
     sampai pengguna menyetujui ringkasan lengkap; penolakan final, prompt
     di latar belakang gagal-tertutup, seed phrase/private key tidak pernah
     diminta.
  3. **Isolasi antar-chat**: `ModuleRuntime` kini memakai context map per
     token korelasi (dua chat yang menjalankan modul paralel tidak lagi
     salah routing chat.emit/storage/Stop), draft attachment dibersihkan
     saat pindah chat, plus
     uji regresi paralel penuh.
  4. **Panel Plan live**: dipasang di atas daftar pesan (bukan di footer
     yang sering di-unmount), status terbuka/tutup global milik pengguna —
     real-time, tidak tertutup oleh streaming/transisi langkah/pindah
     chat/run selesai.
  5. **Performa**: id pesan streaming stabil (tanpa teardown subtree per
     delta), style sheet markdown stabil (tanpa re-parse semua bubble tiap
     sync), `jsonEncode` request LLM di isolate, refresh daftar chat tidak
     lagi per-langkah (dulu baca ulang SEMUA file chat per tool batch),
     `MediaQuery.sizeOf`, decode thumbnail (`cacheWidth`), dan
     `fetch()` nyata untuk skrip embedded (git-over-HTTPS & Web3 kini
     berfungsi).
- **v1.37.0 — Browser Context paralel (fan of subagents tanpa antre) + drawer ikon**:
  1. **Browser Context per pekerja**: engine browser baru
     (`ContextualBrowserAutomation`) memberi SETIAP sesi chat dan SETIAP
     subagent paralel WebView headless + lock + state cookie/storage-nya
     sendiri — pekerjaan browser paralel berjalan berdampingan, tidak lagi
     antre di belakang satu mutex global.
  2. **Subagent boleh pakai browser**: `spawn_subagents` kini menyertakan
     tool browser (`browser_navigate` s.d. `run_js`) untuk setiap tugas,
     masing-masing ter-pin ke context id unik (`subagent-<stamp>-<i>`);
     state subagent bersifat ephemeral (tidak ditulis ke disk, cookie
     dilepas dari jar saat selesai).
  3. **Higiene cookie jar bersama**:Android CookieManager global ditangani
     dengan klaim origin bedah (hapus nama cookie context lain yang IDLE
     saat kunjungan pertama, jangan sentuh yang sedang mid-op), purge
     sekali di awal proses, dan pelepasan cookie saat slot diusir (LRU,
     cap 4 engine).
  4. **Drawer**: aksi "Ekspor chat (Markdown)" dan "Token stats" menjadi
     tombol ikon saja tanpa label, menyatu dengan ikon import/export
     (v1.34.0 style).
- **v1.36.0 — database User-Agent 500 → 1500 identitas valid**:
  1. **+1000 User-Agent baru** dibangkitkan & divalidasi dari perangkat dan
     browser yang SAMA dengan database lama (tanpa vendor palsu) — total
     **1500 identitas unik (500 desktop + 1000 Android)**, semua lolos
     validasi format otomatis (`scripts/gen_user_agents.py` + unit test).
  2. **Desktop (+250)**: Chrome/Edge 144-146 di Windows/macOS/Linux, Chrome
     32-bit asli di Windows 64-bit (token `WOW64`), Edge 120-131 di
     macOS/Linux, Firefox 150-155 + rilis titik .0.1/.0.2 + ESR 128.x/140.x
     (rv = major.minor, persis Firefox asli), Safari 26.5/27.0, Opera untuk
     Linux (Chromium 136-146), Vivaldi 7.7/7.8 + Vivaldi Linux.
  3. **Android (+750)**: semua 35 ponsel + 6 tablet bawaan × Android 13-16 ×
     Chrome 120-146 (Chrome ponsel +260, tablet +50), Samsung Internet 28
     (Chromium 130) + kombinasi 25/26/27 yang belum terpakai (+40), Firefox
     Android rv 130-155 (+130), Edge/Opera Mobile diperluas ke semua ponsel
     (+135 masing-masing).
  4. **ID 1..500 tidak berubah satu byte pun** — pilihan UA tersimpan
     pengguna lama tetap menunjuk identitas yang sama; tes stabilitas id
     legacy menjaga invarian ini di masa depan.
- **v1.34.0 — pass performa anti-lag/ANR + siklus mode pesawat rotasi IP + ikon impor/ekspor**:
  1. **Form setup tidak lagi macet**: sheet setup tertutup seketika setelah
  dikirim — eksekusi modul + resume agen jalan di latar belakang
  (`submitModuleSetup(awaitRun: false)`); rebuild per-delta streaming dan
  output modul (console/emit) di-coalesce 48ms.
  2. **Kerja CPU berat keluar dari UI thread** (audit penuh fan of
  subagents): zip (deflate) + unzip (inflate/AES) di `Isolate.run`,
  downscale/encode JPEG lampiran di isolate, encode JSON backup utuh di
  dalam worker isolate (mengikuti kripto yang sudah off-isolate), decode/
  encode transkrip penuh di `ChatStore` (openChat/rename/saveModules/
  loadWaitingForSetup) lewat seam `offloadIsolate`, ekspor/impor sesi
  (pretty-print + decode) off-isolate, IO storage modul & scan prefill
  kini async.
  3. **`zagents.device.airplaneCycle({holdMs?, settleMs?})`** (root):
  siklus terverifikasi ON→hold→OFF untuk **rotasi IP carrier** — selalu
  berakhir OFF (online, IP baru); verifikasi read-back + retry sekali +
  pemulihan OFF; bisa dibatalkan dengan aman; clamp holdMs 500–15000
  (default 2500), settleMs 0–30000 (default 8000). Perintah modul
  `/airplane cycle|ip|rotate` di sampel Airplane Mode v1.3 (manual guided
  tanpa root); SDK + typings + docs EN/ID diperbarui.
  4. **Ikon impor/ekspor sesi** di drawer: dua `IconButton` ringkas
  (tooltip EN/ID, target sentuh 48×48) menggantikan dua ListTile teks.
  5. `ValueKey` per pesan pada list chat + 12 test baru (siklus airplane,
  awaitRun, module_list status, prefill); **657/657 test hijau**.
- **v1.32.0 — mode pesawat tanpa root: mode manual terverifikasi + auto-retry sadar mode pesawat**:
  1. **Baca status TANPA root** (`zagents.device.airplane`): state mode
  pesawat kini terbaca dari setelan sistem yang world-readable — tanpa
  root, tanpa sakelar "Perintah perangkat", dan **tetap bekerja saat
  mode pesawat ON** (perintah slash dijalankan app-side, bukan lewat AI).
  2. **Modul Airplane Mode v1.2 — dua mode**: ponsel root tetap AUTO
  (toggle terverifikasi); ponsel **tanpa root kini MANUAL mode** — tidak
  lagi gagal mentah: `/airplane on|off` mencetak panduan langkah demi
  langkah, pengguna membalik radio dari Quick Settings, dan
  `/airplane status` memverifikasi keadaan ASLI (jawaban "yes" telanjang
  tidak pernah dipercaya).
  3. **Tool agent baru `device_status`** (ke-27): mode pesawat +
  ketersediaan root (hasil su di-cache) — agent kini bisa MEMERIKSA
  klaim pengguna ("sudah dinyalakan") lewat fakta perangkat, bukan
  percaya buta; system prompt agent diajari pola instruksi
  round-trip (nyalakan → uji offline → matikan → lanjut otomatis).
  4. **Auto-retry sadar mode pesawat**: saat kegagalan jaringan terjadi
  DAN mode pesawat sedang ON, loop retry MENAHAN tanpa membakar kuota
  percobaan (default 3 × ~30 dtk terlalu pendek untuk jendela offline
  manual) sampai radio kembali OFF — cap 10 menit, Stop selalu menang,
  dan platform yang tak bisa membaca state memakai akuntansi lama.
  Inilah yang membuat "jawab yes → auto lanjutkan" benar-benar bekerja:
  pesan yang mengantre selama offline terkirim seketika koneksi pulih.
- **Pencarian + paging universal (v1.6.0)** — SEMUA list di aplikasi memakai
  widget `PagedList` yang sama: **5 item per halaman** (termasuk dropdown model),
  kolom pencarian, pager first/prev/next/last, dan empty state "No results".
  Berlaku untuk: daftar model (picker + hasil fetch di editor provider), daftar
  provider, riwayat chat (drawer), File Manager, Context Manager, dan library
  npm — masing-masing dengan hint pencarian berbahasa.
- **Database 1500 User-Agent + Mode UA (v1.7.0, diperluas v1.36.0)** — database
  internal berisi **1500 User-Agent unik & realistis** (500 PC/desktop + 1000
  Android; Chrome,
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

Atau lebih cepat: **buatan agent langsung dari chat** — ketik
`/make_plugins counter plugin dengan tombol reset` di chat mana pun; agent
menyusun modulnya, memvalidasi, dan menampilkan kartu Install untuk kamu
konfirmasi (bisa memakai data sesi bila kamu menyebutnya).

Test penjaga (`test/unit/module_sdk_assets_test.dart`) memvalidasi
kelengkapan ketiga folder tersebut — sdk, samples, docs tidak bisa
hilang atau rusak tanpa membuat test gagal.

## 🚀 CI/CD (GitHub Actions)

Semua build dilakukan di CI — tidak perlu build lokal.

| Workflow | Trigger | Isi |
|---|---|---|
| **CI** (`ci.yml`) | push `main`, PR | `dart format` check, `flutter analyze`, unit + widget tests (2 shard paralel + artefak coverage), build APK debug di PR, **E2E di emulator Android** (push main), dan job **auto-fix** (`dart fix --apply` + `dart format`, commit otomatis `[skip ci]`) bila analyze gagal |
| **Release** (`release.yml`) | tag `v*` / manual | validasi tag = versi pubspec → restore keystore terenkripsi → `flutter build apk --release` bertanda tangan → verifikasi `apksigner` → **GitHub Release otomatis** dengan APK + release notes |

Optimasi kecepatan: cache pub + Flutter SDK (`flutter-action cache`), cache
Gradle, `concurrency` cancel-in-progress, unit test di-shard, e2e emulator
hanya di `main`, APK hanya di-build saat rilis/PR.

### Secrets untuk rilis bertanda tangan

| Secret | Wajib | Isi |
|---|---|---|
| `KEYSTORE_PASSWORD` | ya | password untuk membuka `key-sign-apk.zip` (sekaligus fallback password keystore/key) |
| `KEYSTORE_STORE_PASSWORD` | tidak | password keystore (default: `KEYSTORE_PASSWORD`) |
| `KEYSTORE_KEY_PASSWORD` | tidak | password key (default: store password) |
| `KEYSTORE_ALIAS` | tidak | alias key (default: dideteksi dari `keytool -list`) |
| `KEYSTORE_SHA256` | tidak | pin fingerprint sertifikat (SHA-256) |

Keystore terenkripsi `key-sign-apk.zip` di-unzip di runner, bukan di mesin
lokal. Tanpa password/keystore yang valid, job **gagal** — tidak ada
fallback debug signing.
Secret tidak pernah ditulis ke `$GITHUB_ENV`; hanya diteruskan sebagai env
langsung ke langkah build, dan keystore yang sudah di-unzip dihapus di akhir
job (`if: always()`).

### Membuat rilis baru

```bash
# bump version di pubspec.yaml (mis. 1.40.0+48), lalu:
git tag v1.40.0
git push origin v1.40.0
# → workflow Release terbitkan APK bertanda tangan ke GitHub Releases
```

Tag dengan sufiks (mis. `v1.41.0-beta.1`) diterbitkan sebagai prerelease.

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
- Rilis wajib memakai keystore dari secrets (lihat tabel di atas); build
  tanpa keystore **gagal** dan tidak pernah jatuh ke debug signing.
- Seed phrase / private key tidak pernah diminta atau disimpan: secret
  skill disimpan lokal di `.zconfig.json` dan tidak pernah di-echo ke chat
  atau log.

## 🗺️ Rencana lanjutan

- [x] Signing config rilis via GitHub Secrets
- [ ] Ekspor/impor riwayat chat
- [ ] Mode multi-image / attachment
- [ ] Preview "browser inspector" layar penuh secara real-time
