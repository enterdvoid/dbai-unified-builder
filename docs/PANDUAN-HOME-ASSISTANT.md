# Panduan Arsitektur Home Assistant pada Firmware DBAI Armbian STB

Dokumen ini menjelaskan arsitektur, metode instalasi, serta perbedaan antara **Home Assistant OS (HAOS)**, **Home Assistant Supervised**, dan **Home Assistant Container** khususnya dalam konteks firmware STB TV Box (Amlogic `aml-s9xx-box`) dan repositori `dbai-unified-builder`.

---

## 1. Jawaban Langsung: Di Repositori Ini Sebenarnya Memakai Apa?

> **Repositori ini menggunakan: Home Assistant Supervised.**

Ketika Anda menjalankan perintah kompilasi:
```bash
./compile.sh build BOARD=aml-s9xx-box ... ENABLE_EXTENSIONS=applications-ha ... RELEASE=trixie
```
atau memilih profil `homeassistant` pada GitHub Actions workflow DBAI, sistem memanggil ekstensi resmi Armbian bernama **`applications-ha`**.

### "Tapi Dulu Saat Saya Tes, Kenapa Isinya Docker?"
**Karena Home Assistant Supervised MEMANG bekerja sepenuhnya di atas Docker Engine.**

Banyak pengguna mengira bahwa instalasi "Docker" dan "Supervised" adalah dua hal yang bertolak belakang. Faktanya:
1. **Home Assistant Supervised** membutuhkan Docker sebagai fondasi utamanya.
2. Saat sistem Supervised pertama kali menyala, ia menjalankan beberapa container Docker resmi:
   - `hassio_supervisor` : Container pengawas (*orchestrator*) yang mengatur sistem dan menyediakan menu **Add-on Store**.
   - `homeassistant` : Container aplikasi utama Home Assistant (dashboard web port 8123).
   - `hassio_dns` : Container CoreDNS untuk komunikasi jaringan antar-komponen.
   - `hassio_audio` : Container audio layer.
   - `hassio_cli` : Container antarmuka baris perintah (`ha`).
   - `addon_*` : Setiap kali Anda menginstal aplikasi dari Add-on Store (seperti Mosquitto MQTT, Zigbee2MQTT, atau Node-RED), Supervisor akan membuat container Docker baru secara otomatis di balik layar.

Jadi, ketika Anda mengecek STB dengan perintah `docker ps` dan melihat daftar container tersebut, itu **bukan** berarti Home Assistant Docker biasa, melainkan **Home Assistant Supervised yang sedang beroperasi normal**.

---

## 2. Perbandingan: HAOS vs Supervised vs Container Biasa

Home Assistant secara resmi memiliki 4 metode instalasi. Berikut perbandingan 3 metode yang relevan untuk perangkat mini PC / STB:

| Fitur / Karakteristik | **HAOS (Home Assistant OS)** | **Home Assistant Supervised**<br>*(Dipakai di Repo Ini)* | **Home Assistant Container**<br>*(Docker Standalone)* |
| :--- | :--- | :--- | :--- |
| **Sistem Operasi Dasar** | Minimalist appliance OS (berbasis Buildroot/Alpine) khusus Home Assistant. | **Debian / Armbian Linux lengkap** dengan kernel & DTB khusus STB. | **Distro Linux apa saja** (Armbian, Ubuntu, Debian, Alpine). |
| **Akses Root & Terminal Linux** | Terkunci & terbatas. Tidak ada APT package manager. | **Leluasa 100%**. Tersedia APT, compiler, systemd, btop, dll. | **Leluasa 100%**. |
| **Menu "Add-on Store" 1-Klik** | **ADA** | **ADA** | ❌ **TIDAK ADA** |
| **Backup / Snapshot 1-Klik** | **ADA** (Full & Partial backup dari web) | **ADA** (Full & Partial backup dari web) | ❌ **TIDAK ADA** (harus backup volume manual) |
| **Multi-fungsi (Aplikasi Lain)** | ❌ Tidak bisa. STB 100% hanya untuk Home Assistant. | **Bisa**. Bisa bareng CasaOS, Pi-hole, Cloudflare, dll. | **Bisa**. |
| **Kompatibilitas di STB Amlogic** | ⚠️ Sangat sulit / Tidak praktis (butuh bootloader & DTB terpisah). | **Sangat Bagus** (menggunakan kernel/bootloader DBAI Armbian). | **Sangat Bagus & Sangat Ringan**. |

---

## 3. Jadi, Apakah Supervised Sama Saja dengan HAOS?

### Persamaannya (Dari Sisi Pengguna):
- **Tampilan Dashboard Identik**: Tampilan web di port `8123` sama persis.
- **Dukungan Add-on**: Keduanya sama-sama memiliki menu **Settings -> Add-ons (Add-on Store)** untuk memasang plugin/service tambahan secara instan.
- **Dukungan Backup Snapshot**: Keduanya bisa membuat dan me-restore file backup `.tar` lengkap dengan satu klik.

### Perbedaannya (Dari Sisi Sistem):
- **HAOS** adalah sistem tertutup. Anda tidak bisa menginstall program Linux sembarangan karena sistem partisinya read-only dan diperbarui sebagai satu bundle image.
- **Supervised** adalah sistem terbuka. Anda memiliki sistem Debian/Armbian seutuhnya di balik layar. Jika Anda ingin menginstall paket Linux via `apt install`, menjalankan script Python, memasang VPN, atau memantau performa CPU dengan `btop`, semuanya tetap berfungsi normal tanpa hambatan.

---

## 4. Bagaimana Ekstensi `applications-ha` Bekerja saat Kompilasi?

Ketika parameter `ENABLE_EXTENSIONS=applications-ha` aktif saat build:
1. **Pemasangan Docker Engine**: Ekstensi memasang paket `docker-ce`, `docker-ce-cli`, dan `containerd.io`.
2. **Pemasangan Komponen Supervised**:
   - Memasang `os-agent` (daemon perantara antara Home Assistant Supervisor dan D-Bus Linux host).
   - Memasang paket `homeassistant-supervised.deb`.
   - Memasang dependensi sistem: `apparmor`, `network-manager`, `cifs-utils`, `nfs-common`, `systemd-journal-remote`.
3. **Konfigurasi Boot & Kernel**:
   - Menambahkan parameter keamanan AppArmor ke dalam baris perintah kernel (`bootargs`/`cmdline`):
     ```text
     apparmor=1 security=apparmor
     ```
4. **Inisialisasi Boot Pertama (*First-Boot*)**:
   - Saat STB pertama kali menyala dan terhubung ke internet, service `hassio-supervisor.service` akan menarik (*pull*) image Docker terbaru dari registry resmi Home Assistant dan menyusun seluruh stack container secara otomatis.

---

## 5. Batasan & Kompatibilitas Sistem Operasi

Sesuai standar resmi tim pengembang Home Assistant:
- **Distribusi yang Didukung Penuh**: Hanya keluarga **Debian** (Bullseye, Bookworm, Trixie).
- **Ubuntu**: Tim Home Assistant secara resmi menandai instalasi Supervised pada Ubuntu sebagai *Unsupported/Unhealthy*. 
- Oleh karena itu, di `dbai-apps`, opsi instalasi Proxmox dan Home Assistant Supervised secara otomatis diproteksi untuk berjalan optimal pada image berbasis Debian.

---

## 6. Ringkasan Praktis Penggunaan di STB

1. **Akses Dashboard**:
   Buka browser di jaringan lokal:
   ```text
   http://192.168.2.207:8123
   ```
2. **Memeriksa Status via CLI**:
   - Cek via DBAI Apps: `dbai-apps homeassistant`
   - Cek container Docker: `docker ps`
   - Cek service host: `systemctl status hassio-supervisor`
   - CLI Home Assistant bawaan: `ha core info` atau `ha supervisor info`
