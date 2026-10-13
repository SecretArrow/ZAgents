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
