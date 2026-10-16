# Panduan Proxmox Community (PXVIRT 8) pada Firmware DBAI Armbian

Dokumen ini untuk image **DBAI Armbian Proxmox Community** pada board `aml-s9xx-box`. Image memakai Debian Bookworm ARM64, paket userspace PXVIRT 8 dari repositori komunitas, dan kernel/DTB Armbian agar tetap sesuai dengan jalur boot STB Amlogic.

> **Batas dukungan:** ini image eksperimen untuk TV box Amlogic, bukan platform yang disertifikasi resmi Proxmox. Berhasil membuka dashboard tidak otomatis berarti KVM acceleration, bridge jaringan, LXC, storage backend, atau semua jenis guest sudah bekerja pada perangkat tertentu. Uji fitur satu per satu.

## 1. Cara masuk ke Web UI

Saat first boot, firmware meminta password root. Gunakan password root yang kamu buat pada prompt tersebut.

Dari browser komputer yang satu jaringan LAN dengan STB, buka:

```text
https://IP-STB:8006
```

Contoh jika IP STB adalah `192.168.2.129`:

```text
https://192.168.2.129:8006
```

Sertifikat awal mungkin ditandatangani sendiri (*self-signed*), sehingga browser menampilkan peringatan sertifikat. Pastikan alamat IP benar-benar milik STB milikmu sebelum melanjutkan.

Pada halaman login gunakan:

- **Username:** `root@pam`
- **Password:** password root yang dibuat saat first boot.
- **Realm:** `Linux PAM standard authentication` (atau opsi `Linux PAM` bila label UI berbeda).

### Jika `root@pam` menolak password

Prompt first-login Armbian lama menampilkan peringatan password lemah, tetapi tidak memeriksa hasil perintah `passwd root`. Jika PAM menolak password pendek, setup masih dapat berlanjut sehingga kamu merasa password sudah disimpan meskipun sebenarnya belum berubah.

Karena kamu masih memiliki shell root di console/SSH, atur ulang password sekarang:

```bash
passwd root
passwd -S root
```

Masukkan password baru yang panjang (disarankan 12–16 karakter atau lebih), unik, dan tidak berdasarkan kata kamus. `passwd -S root` seharusnya menunjukkan status password `P` (password tersedia), bukan `L` (locked). Lalu coba login lagi ke `https://IP-STB:8006` sebagai `root@pam`, Realm `Linux PAM`, menggunakan password baru.

Jika masih ditolak, jangan mengulang tebakan berkali-kali. Periksa layanan dan log autentikasi dari console:

```bash
systemctl --no-pager --full status pveproxy pvedaemon
journalctl -u pveproxy -u pvedaemon -n 100 --no-pager
```

Perbaikan source DBAI sekarang memeriksa exit status perintah pengaturan password root dan menampilkan kesalahan jika password ditolak; first-login tidak melanjutkan dengan diam-diam seolah password sudah berhasil ditetapkan.

Untuk administrasi Proxmox, akun root PAM digunakan; akun Linux biasa bukan pengganti realm tersebut. Jika halaman tidak terbuka, lanjutkan ke diagnostik pada bagian 4.

## 2. Kenapa first-login meminta akun bernama `ceph`?

Log seperti berikut tidak normal sebagai pengalaman onboarding:

```text
Detected existing user ceph from previous setup, reusing.
...
Dear Ceph storage service, your account ceph has been created and is sudo enabled.
```

Akar masalahnya ada pada deteksi pengguna di skrip first-login Armbian: skrip lama mengambil akun pertama dengan UID `>= 1000` tanpa memeriksa apakah akun itu merupakan user service. Paket di lingkungan Proxmox dapat menghadirkan akun sistem seperti `ceph`; akun tersebut lalu keliru terpilih sebagai pengguna harian, home dibuat ulang, password disetel, dan grup `sudo` diberikan.

Perbaikan telah dimasukkan ke source DBAI: skrip first-login sekarang hanya menggunakan akun dengan home langsung di `/home/<user>` dan shell interaktif (bukan `nologin`/`false`) untuk mekanisme pemulihan setelah first-login terputus. Dengan image baru, jika belum ada pengguna manusia yang valid, prompt seharusnya meminta nama user baru alih-alih memilih `ceph`.

### Amankan image yang sudah terlanjur boot

Jangan menghapus akun `ceph` secara langsung—paket layanan bisa membutuhkannya. Masuk lewat root/SSH atau console dan periksa akun tersebut:

```bash
getent passwd ceph
id ceph
```

Jika `ceph` tercantum sebagai anggota grup tambahan setelah prompt first-login, cabut grup yang salah ditambahkan dan kunci autentikasi password untuk akun service tersebut:

```bash
for group in sudo netdev audio video disk tty users games dialout plugdev input bluetooth systemd-journal ssh render docker; do
  getent group "$group" >/dev/null && sudo gpasswd -d ceph "$group" 2>/dev/null || true
done
sudo passwd -l ceph
id ceph
getent passwd ceph
```

Daftar tersebut adalah grup yang skrip first-login DBAI/Armbian berikan ke user harian. Menghapusnya dari `ceph` mencegah akun service menerima hak `sudo`, akses grup `disk`, atau akses grup `docker`. Perintah tidak menghapus akun atau data milik paket. Periksa `id ceph`: grup primary `ceph` boleh tetap ada, tetapi grup-grup tambahan onboarding tadi seharusnya tidak ada. Jika akun ini memang telah dikonfigurasi manual untuk peran lain, tinjau kebutuhannya sebelum mencabut grup.

Buat akun administrator Linux biasa untuk SSH/shell jika diperlukan:

```bash
sudo adduser dbaiadmin
sudo usermod -aG sudo dbaiadmin
```

Pilih password yang kuat. Gunakan `dbaiadmin` untuk administrasi shell sehari-hari; tetap gunakan `root@pam` saat login ke dashboard Proxmox jika ingin mengelola sebagai root. Jika akun `dbaiadmin` sudah ada, jangan jalankan `adduser` lagi.

## 3. Kenapa MOTD menampilkan “Debian rolling (bookworm)”?

Label itu berasal dari skrip tampilan MOTD Armbian yang mengklasifikasikan status codename melalui metadata `/etc/armbian-distribution-status`. Ketika status tidak dikenali sebagai `supported` atau `eos`, skrip lama jatuh ke label `rolling`. Karena itu label `rolling` saja **tidak membuktikan** bahwa APT memakai repositori Debian rolling/unstable.

Periksa codename OS dan suite APT yang sebenarnya:

```bash
grep -E '^(ID|VERSION_ID|VERSION_CODENAME|PRETTY_NAME)=' /etc/os-release
grep -RhsE '^[[:space:]]*(deb[[:space:]]|URIs:|Suites:)' \
  /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null
apt-cache policy
```

Output yang kamu kirim menunjukkan suite APT yang benar: Debian `bookworm`, `bookworm-updates`, `bookworm-backports`, `bookworm-security`, ditambah repository Armbian dan PXVIRT Bookworm. Ada satu suite `stable` dari `github.armbian.com/configng`; itu repository konfigurator Armbian, bukan pengganti suite Debian utama. Dari output tersebut tidak terlihat Debian `sid` atau `unstable`.

Pemetaan fallback MOTD DBAI (hanya jika metadata status Armbian kosong/tidak dikenal) mengikuti status release upstream:
- Debian Bullseye: `oldoldstable/LTS`.
- Debian Bookworm: `oldstable/LTS`.
- Debian Trixie: `stable`.
- Debian Forky: `testing` (bukan stable pada saat ini).
- Ubuntu Jammy, Noble, dan Resolute: `LTS`.
- Codename lain yang tidak dikenali tetap menggunakan label fallback `rolling`.

Dengan begitu label Bookworm lebih tepat: tidak disebut rolling, tetapi juga tidak salah disebut stable paling baru.

Jika metadata Armbian secara eksplisit menyatakan `supported` atau `eos`, nilai metadata itu tetap didahulukan. Rujukan: [status release Debian](https://www.debian.org/releases/index.en.html) dan [informasi Debian Forky/testing](https://www.debian.org/releases/testing/).

Perbaikan MOTD tidak mengubah repository, versi paket, kernel, atau siklus dukungan OS—hanya teks klasifikasi yang ditampilkan. Image yang sudah di-flash perlu mengganti skrip MOTD atau dipasang ulang dengan image build baru agar tampilan ikut berubah.

## 4. Pemeriksaan layanan Proxmox

Jalankan pada STB:

```bash
pveversion -v
systemctl --no-pager --full status pve-cluster pvedaemon pveproxy pvestatd
systemctl --no-pager --full status dbai-proxmox-hosts.service
sudo ss -lntp | grep ':8006'
hostname
hostname -f
cat /etc/hosts
```

Jika `pveproxy` aktif dan port TCP `8006` sedang listen, coba URL HTTPS pada bagian 1 dari komputer LAN.

Untuk log layanan:

```bash
sudo journalctl -u pveproxy -u pvedaemon -u pve-cluster -u pvestatd -n 150 --no-pager
sudo journalctl -u dbai-proxmox-hosts.service -n 100 --no-pager
```

Ekstensi DBAI menyediakan `dbai-proxmox-hosts.service` untuk memetakan hostname ke IP LAN yang terdeteksi. Periksa log bila nama host tidak terselesaikan atau layanan Proxmox gagal mulai.

## 5. Membuat VM/container: cek dukungan perangkat terlebih dahulu

Sebelum membuat guest, periksa kemampuan host:

```bash
uname -r
ls -l /dev/kvm
lsmod | grep -E '(^kvm|kvm_)' || true
free -h
df -h /
ip -br address
ip route
```

- Jika `/dev/kvm` tidak ada, jangan menganggap hardware virtualization tersedia. QEMU software emulation, bila didukung, jauh lebih lambat dan tidak sesuai untuk semua beban kerja.
- Konfigurasi bridge jaringan tidak dibuat otomatis oleh ekstensi DBAI ini. Jangan menekan **Apply Configuration** atau mengedit `/etc/network/interfaces` secara coba-coba melalui koneksi SSH yang sedang dipakai; perubahan jaringan salah dapat memutus akses.
- Sebelum mengubah jaringan, simpan cadangan konfigurasi dan pastikan ada akses serial/HDMI atau cara pemulihan lokal. Pastikan bridge yang dipilih cocok dengan interface fisik pada STB.
- Untuk LXC, verifikasi kemampuan kernel/cgroups dan kompatibilitas userspace. Jangan menganggap dukungan penuh hanya karena paket manajer Proxmox terpasang.

## 6. Mengapa kernel Proxmox tidak dipasang?

Ekstensi Proxmox Community sengaja memasang userspace PXVIRT tetapi mempertahankan kernel/DTB Armbian, sebab perangkat Amlogic ini boot melalui U-Boot vendor dan membutuhkan DTB/konfigurasi yang sesuai. Kernel Proxmox generik tidak seharusnya menggantikan kernel board ini secara otomatis.

Mulai dari perubahan source DBAI ini, workflow image baru memakai `BSPFREEZE=yes` agar paket kernel, DTB, U-Boot dan Armbian board-support terkait tidak berubah oleh upgrade APT tanpa sengaja. Pembaruan aplikasi/paket OS biasa tetap bisa dilakukan.

Pada image yang sedang digunakan sekarang, bekukan update kernel/firmware dengan:

```bash
sudo armbian-config --cmd UPD002
apt-mark showhold
```

Untuk mengaktifkannya kembali setelah siap menguji kernel baru:

```bash
sudo armbian-config --cmd UPD001
```

Perintah menu/non-interaktif di atas berasal dari fitur freeze firmware Armbian. Sesudahnya, cek `apt-mark showhold` untuk memastikan paket kernel memang di-hold. Jangan menjalankan `apt full-upgrade` atau memasang kernel Proxmox pada STB ini tanpa meninjau rencana pemulihan boot.

## 7. Troubleshooting cepat

**Tidak bisa membuka HTTPS port 8006:** cek IP STB, konektivitas dari komputer LAN, `ss -lntp | grep ':8006'`, dan status/log `pveproxy`.

**Menerima “hostname verification” atau error hostname:** cek `hostname -f`, `/etc/hosts`, dan log `dbai-proxmox-hosts.service`. Jangan mengganti mapping hostname ke IP yang salah.

**Dashboard bisa dibuka, tetapi VM tidak bisa start:** periksa `/dev/kvm`, log task di UI, `journalctl -u pvedaemon -u pve-cluster`, ruang penyimpanan, dan konfigurasi bridge. Ini dapat menjadi batas kompatibilitas kernel/hardware, bukan masalah login dashboard.

**Update menawarkan kernel baru:** gunakan `sudo armbian-config --cmd UPD002`; kemudian pastikan paket kernel tampil pada `apt-mark showhold`. Perubahan default di source hanya memengaruhi image baru.

## 8. Status implementasi dan referensi

- Source ekstensi: [`extensions/proxmox-community.sh`](../extensions/proxmox-community.sh)
- Workflow build: [`.github/workflows/armbian-build.yml`](../.github/workflows/armbian-build.yml)
- Dokumen implementasi build: [`DBAI-ARMBIAN-BUILD.md`](DBAI-ARMBIAN-BUILD.md)
- Referensi update/freeze Armbian: https://docs.armbian.com/config/updates/ dan https://docs.armbian.com/getting-started/updating/
- Referensi proyek PXVIRT komunitas: https://github.com/jiangcuo/pxvirt

Perubahan yang dijelaskan adalah perbaikan pada source/workflow. Untuk validasi firmware penuh, build ulang satu image Proxmox Community Bookworm (pilih satu filesystem), cek dashboard, uji reboot, dan uji satu guest sederhana. Hasil itu tetap eksperimen perangkat nyata dan bukan sertifikasi kompatibilitas resmi.
