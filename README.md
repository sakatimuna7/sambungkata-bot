# SambungKata Bot V2

![SambungKata Logo](https://img.shields.io/badge/Roblox-SambungKata-brightgreen)
![Platform](https://img.shields.io/badge/Platform-macOS-blue)

Bot otomatis untuk game Sambung Kata (Roblox/TextEdit) dengan antarmuka overlay yang elegan dan logika pemilihan kata yang cerdas.

## 🚀 Fitur Utama

- **Roblox Automation**: Mengetik kata secara otomatis langsung ke dalam game Roblox dengan pengenalan "Remainder" (hanya mengetik sisa huruf dari apa yang sudah ada di kotak input game).
- **Ultra-Stable Typing**: Menggunakan Virtual Keycodes tingkat rendah (HID level) untuk akurasi 100% di dalam game, menghindari bug karakter ganda atau tertinggal.
- **Smart AI Suggestion**:
  - Melakukan validasi "Continuation" untuk memastikan kata yang dipilih masih bisa dilanjutkan oleh bot (Anti Dead-End).
  - Melewatkan kata yang persis sama dengan input pencarian.
- **Word Elimination**:
  - **Auto-Elimination**: Setiap kata yang sudah diketik atau dipilih akan otomatis disembunyikan agar tidak dipakai dua kali.
  - **Manual Elimination**: Tombol `×` untuk membuang kata yang tidak diinginkan dari daftar.
  - **Reset Logic**: Tombol reset untuk mengembalikan semua kata yang sudah dibuang.
- **Seamless UI**:
  - **Global Hotkey**: `Cmd + Shift + K` untuk memunculkan/menyembunyikan overlay kapan saja.
  - **Draggable Overlay**: Antarmuka transparan yang bisa digeser sesuai keinginan.
  - **Auto Focus**: Fokus otomatis ke kotak pencarian setelah ngetik, biar lu makin cepet.

## 🛠 Persyaratan

- **macOS** (Tested on Apple Silicon & Intel)
- **Xcode Command Line Tools** (untuk build)

## 📦 Cara Build & Jalankan

1. Clone repositori ini:

   ```bash
   git clone git@github.com:sakatimuna7/sambungkata-bot.git
   cd sambungkata-bot
   ```

2. Jalankan script build:

   ```bash
   ./build.sh
   ```

3. Buka aplikasinya:
   ```bash
   open SambungKata.app
   ```

> [!NOTE]
> Jika muncul peringatan "Unidentified Developer", silakan buka **System Settings** → **Privacy & Security** → klik **Open Anyway**.

## 🎮 Cara Penggunaan

1. Buka game **Roblox** (atau **TextEdit** untuk tes).
2. Tekan `⌘ + ⇧ + K` untuk memunculkan bot.
3. Ketik awal kata atau akhiran di kotak pencarian.
4. **Opsi Typing**:
   - Tekan **Enter**: Mengetik saran pertama secara otomatis.
   - **Klik Kata**: Mengetik kata yang lu pilih secara spesifik.
5. Aktifkan toggle **AUTO** jika ingin bot langsung ngetik pas lu tekan Enter.

---

_Dibuat dengan ❤️ untuk para pro player Sambung Kata._
