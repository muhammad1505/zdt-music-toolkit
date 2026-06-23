# Panduan Berkontribusi di ZDT Music Toolkit

Terima kasih atas minat Anda berkontribusi! 🚀

## Standar Kode
1. **Modular Bash**:
   - `zdt.sh` adalah **thin loader**. Jangan pernah menulis logika panjang di `zdt.sh`.
   - Gunakan folder `zdt-modules/` untuk menaruh fungsionalitas utama.
2. **Tidak Ada Fungsi Duplikat**:
   - Skrip `test_smoke.sh` akan mendeteksi jika ada dua fungsi bernama sama di file yang berbeda. Pastikan penamaan spesifik atau pindahkan fungsi yang dipakai bersama ke `helpers.sh`.
3. **Keamanan Bash**:
   - Selalu gunakan array Bash untuk argumen `find`. Hindari penggunaan `eval "find ..."`.
   - Gunakan *quote* pada variabel `$VAR` untuk mencegah eksploitasi *word-splitting*.
4. **Python**:
   - Tulis kode yang kompatibel dengan PEP-8.
   - Jangan menyematkan API Key langsung di dalam file. Ambil dari `~/.config/zdt/config.env` atau file `~/.config/zdt/*`.

## Pengujian (Testing)
Setiap Pull Request harus melewati ujian ini:
- **Smoke Test**: Jalankan `./test_smoke.sh` dan pastikan hasil `PASS` di seluruh pengecekan (Syntax, Integrity, Duplicate Function).
- **PyTest**: Jalankan tes unit Python yang ada di folder `tests/` jika memodifikasi *backend* Web atau Telegram.

## Commit Message
Gunakan standar *Conventional Commits*:
- `feat: ` untuk fitur baru.
- `fix: ` untuk perbaikan bug.
- `chore: ` untuk pekerjaan pemeliharaan (update dokumentasi, lisensi, alat bantu).
- `docs: ` untuk update README/CHANGELOG.
