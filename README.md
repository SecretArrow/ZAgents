# ZAgents

![CI](https://github.com/SecretArrow/ZAgents/actions/workflows/ci.yml/badge.svg)
![Release](https://github.com/SecretArrow/ZAgents/actions/workflows/release.yml/badge.svg)

**ZAgents** adalah aplikasi Android (Flutter) bergaya **agent mode chat.z.ai** —
chat AI dengan kemampuan **otomasi browser tersemat** (buka halaman, klik, ketik,
scroll, screenshot) dan **kelola file**, mendukung **custom provider**
OpenAI-compatible: **OpenRouter, InferHub, Z.AI, OpenAI, DeepSeek, Groq, dan lainnya**.

## ✨ Fitur

- **Chat streaming** — jawaban model ditampilkan token demi token (SSE).
- **Mode Agent** — model diberi 9 tools dan bekerja step-by-step:
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
- **Custom provider** — cukup ganti Base URL + API key + model (preset tersedia:
  OpenRouter, **InferHub** `sk-airo-…`, Z.AI, OpenAI, DeepSeek, Groq, atau Custom).
- **Katalog model live** — pemilih model mengambil daftar langsung dari
  `GET {baseUrl}/models` provider aktif, lengkap dengan:
  - 🔍 **kolom pencarian** (by id atau nama),
  - 🏷️ **filter chip** (Semua / Tools / Gratis — termasuk model `:free` OpenRouter),
  - 📄 **paging** (20 model per halaman) dengan navigasi first/prev/next/last,
  - badge info (konteks, tools, gratis) + tombol refresh + fallback saran offline.
- **Dwibahasa** — antarmuka **English (default)** dan **Bahasa Indonesia**;
  ganti lewat ikon 🌐 di app bar atau **Settings → Language** (pilihan tersimpan).
- **UI gelap ala Z.AI** — model chip, toggle Agent, kartu tool call dengan status
  live, preview screenshot (tap untuk zoom), drawer riwayat percakapan.
- **Edge-to-edge yang aman** — di Android 15/16 (targetSdk 35/36) konten tidak pernah
  tertutup status bar atas maupun navigation bar bawah: mode edge-to-edge dideklarasikan
  eksplisit, semua layar memakai `SafeArea`, sheet model menghitung inset keyboard,
  dan app bar adaptif di layar sempit.
- **Tahan crash** — semua operasi rentan (WebView, file IO, stream SSE, pembukaan
  riwayat yang korup) ditangani sebagai error terkontrol; tidak ada exception yang
  membuat aplikasi mati.
- **Riwayat lokal** — percakapan disimpan sebagai JSON di penyimpanan privat app.

## 📲 Cara pakai

1. Unduh APK terbaru dari halaman [**Releases**](https://github.com/SecretArrow/ZAgents/releases).
2. Instal (izinkan instal dari sumber tidak dikenal bila diminta).
3. Buka **Settings/Pengaturan** → pilih preset provider (mis. OpenRouter / **InferHub**) → isi **API key**
   → ketuk ikon pencarian di kolom Model untuk **membrowse katalog model live**
   (pilih yang mendukung tool calling: Claude, GPT, Gemini, DeepSeek, Qwen, GLM, dll).
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
│   ├── tool_executor.dart     # dispatch 9 tools
│   ├── browser_automation.dart# headless InAppWebView + JS bridge
│   ├── chat_store.dart        # persistensi riwayat (JSON)
│   └── settings_repository.dart
├── tools/tool_defs.dart       # skema tools + system prompt agent
└── ui/                        # theme, HomeShell, composer, bubbles, dsb.
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
