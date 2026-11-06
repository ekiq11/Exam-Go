# Design System & UI Specifications (ExamGO)

Dokumen ini merangkum seluruh fondasi desain, visual tokens, pola komponen, dan implementasi kode UI dari aplikasi ExamGO agar dapat diterapkan secara langsung pada aplikasi lain (Flutter, React Native, maupun Web/Tailwind).

---

## 1. Visual Identity & Brand Philosophy

* **Karakter Desain:** Modern, Clean, Aman (Trust & Security), Fokus, dan Ramah Pengguna.
* **Gaya Visual:** *Card-based floating design* dengan aksen *forest & emerald green*, dipadukan dengan latar belakang *light off-white*, bayangan lembut (*diffused elevation*), serta dekorasi geometris subtle (lingkaran gradien dan pola grid titik).
* **Motion & Feel:** Menggunakan *bouncing physics* (konsisten di Android & iOS), tanpa *overscroll glow*, animasi *breathing/pulse* pada aksi utama (CTA), serta *slide & fade* berkecepatan mikro (300–400ms).

---

## 2. Design Tokens

### A. Palet Warna (Color Palette)

| Kategori | Nama Token | Hex Code | Deskripsi & Penggunaan |
| :--- | :--- | :--- | :--- |
| **Primary** | `primaryGreen` | `#2E7D32` | Aksen utama, tombol aktif, ikon primer, status fokus |
| | `primaryDark` | `#1B5E20` | Awal gradien AppBar, header modal, mode gelap |
| | `primaryLight` | `#388E3C` / `#81C784` | Aksen gradien akhir, highlight terang |
| | `paleGreen` | `#E8F5E9` | Background kontainer ikon, badge sekunder, pill tag |
| **Status** | `success` | `#4CAF50` | Status sukses, indikator online |
| | `successDot` | `#A5D6A7` | Titik hijau terang di dalam badge status |
| | `warning` | `#FFA726` | Peringatan, koneksi putus, riwayat info |
| | `warningDark` | `#E65100` / `#FF6F00`| Teks peringatan penting, background banner offline |
| | `error` | `#E53935` | Pelanggaran, tombol darurat/keluar, status blokir |
| | `info` | `#2196F3` / `#0288D1`| Informasi sistem, update aplikasi |
| **Text** | `textPrimary` | `#212121` | Judul utama, teks tajam kontras tinggi |
| | `textSecondary` | `#757575` | Deskripsi, subtitle, caption penjelasan |
| | `textDisabled` | `#BDBDBD` | Teks tombol non-aktif, placeholder teks |
| **Surface/BG**| `scaffoldBg` | `#F5F7F5` | Background halaman utama (abu kehijauan lembut) |
| | `surfaceWhite`| `#FFFFFF` | Background kartu, dialog, dan bottom navigation |
| | `grey100` | `#F5F5F5` | Fill input field, skeleton loading |
| | `grey300` | `#E0E0E0` | Border tipis kartu non-aktif |
| | `grey700` | `#616161` | Teks tombol sekunder / batal |

### B. Tipografi (Typography)

* **Font Family:** `Poppins` (Google Fonts atau aset lokal)
* **Atribut Angka/Waktu:** `fontFeatures: [FontFeature.tabularFigures()]` agar lebar angka monospaced dan tidak bergetar saat detik berubah.

| Tingkat (Role) | Ukuran (Size) | Weight | Line Height | Penggunaan |
| :--- | :--- | :--- | :--- | :--- |
| **Display / Hero** | 24–26 px | `FontWeight.w700` (Bold) | 1.1–1.2 | Judul besar hero, nama aplikasi di AppBar |
| **Heading 1** | 20 px | `FontWeight.w700` (Bold) | 1.25 | Judul modal dialog, kartu besar |
| **Heading 2** | 16–17 px | `FontWeight.w700` (Bold) | 1.2 | Judul kartu CTA, judul section list |
| **Subhead / Menu** | 14 px | `FontWeight.w600` / `w700` | 1.3 | Judul item kartu menu, tombol aksi |
| **Body Regular** | 13 px | `FontWeight.w400` (Regular)| 1.6–1.7 | Paragraf deskripsi onboarding, pesan peringatan |
| **Caption / Sub** | 11 px | `FontWeight.w400` / `w500`| 1.3 | Subtitle kartu menu, panduan langkah |
| **Badge / Chip** | 10–11 px | `FontWeight.w600` (SemiBold)| 1.0 | Label "Online", "Live", "v7.0", tag kategori |

### C. Radius & Border Shapes

* **Pill / Circular (Badge & Toggle):** `BorderRadius.circular(20)` – `30px`
* **Modal / Dialog / Bottom Sheet:** `BorderRadius.circular(28px)`
* **Hero / Action Card Utama:** `BorderRadius.circular(24px)`
* **Menu Card / Standard Card:** `BorderRadius.circular(18px – 20px)`
* **Icon Box / Inner Container:** `BorderRadius.circular(12px – 16px)`
* **Input Fields:** `BorderRadius.circular(16px)`

### D. Sistem Bayangan & Elevasi (Shadows)

* **Soft Ambient Card Shadow:**
  ```dart
  BoxShadow(
    color: Colors.black.withValues(alpha: 0.04),
    blurRadius: 10,
    offset: const Offset(0, 3),
  )
  ```
* **Hero Glowing Shadow (Primary Green):**
  ```dart
  BoxShadow(
    color: const Color(0xFF2E7D32).withValues(alpha: 0.38),
    blurRadius: 22,
    offset: const Offset(0, 8),
  )
  ```
* **Floating Header / Bottom Bar Shadow:**
  ```dart
  BoxShadow(
    color: Colors.black.withValues(alpha: 0.07),
    blurRadius: 12,
    offset: const Offset(0, -3), // negatif untuk bottom bar
  )
  ```

---

## 3. Sistem Responsif & Layout

* **Base Reference:** Layar *mobile* lebar 360dp.
* **Fungsi Skala:**
  $$\text{scale} = \left(\frac{\text{shortestSide}}{360.0}\right)\text{ diclamp antara } 0.85 \text{ s.d. } 1.40$$
* **Padding:**
  * Ponsel: `20dp` horizontal
  * Tablet: `40dp` horizontal
* **Kontrol Lebar Maksimum (`MaxWidthBox`):**
  * Di tablet / desktop, bungkus konten kartu dengan batas `maxWidth: 600px` dan posisi `Center` agar antarmuka tidak melebar secara berlebihan.
* **Scroll Physics:** `BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics())` dengan menghilangkan *overscroll glow*.

---

## 4. Pola Komponen Inti (Component Blueprints)

### 1. Collapsible Gradient App Bar (Sliver)
* **Tampilan:**
  * Background: Linear gradient dari kiri-atas `#1B5E20` ke kanan-bawah `#2E7D32` & `#81C784`.
  * Dekorasi: Dua lingkaran semitransparan di pojok (`alpha: 0.05 - 0.08`) dan pola *dot-grid* halus (`alpha: 0.25`).
  * Saat diperluas (*expanded*): Logo aplikasi di dalam kotak rounded (`alpha: 0.18`), judul tebal, subtitle, jam *real-time* kapsul, serta chip versi di pojok kanan.
  * Saat diciutkan (*collapsed*): Menjadi bar ramping standar (56dp) dengan logo mini, teks judul, dan badge status koneksi online/offline.

### 2. Status Banner (Online & Offline)
* **Online Banner:**
  * Background: `#E8F5E9` (Pale Green) dengan border `#2E7D32` (alpha 25%).
  * Ikon: Bulat hijau dengan ikon wifi.
  * Teks: "Internet Terhubung" + "Siap memulai ujian".
  * Trailing: Pill hijau berisi titik putih dan teks "Online".
* **Offline Banner:**
  * Background: `#FFF8E1` (Amber/Orange 50) dengan border orange transparan.
  * Trailing: `CircularProgressIndicator` kecil berwarna orange.

### 3. Hero Action Card (CTA Utama dengan Pulse Animasi)
* **Karakteristik:**
  * Animasi pernapasan lembut: `Tween<double>(begin: 1.0, end: 1.055)` berdurasi 1800ms.
  * Background: Gradien hijau tua ke hijau primer.
  * Ikon Utama: Ikon 30dp dalam kontainer rounded dengan warna putih (alpha 20%).
  * Trailing: Chevron panah maju dalam kontainer rounded.
  * Efek Disabled: Jika offline, berubah menjadi gradien abu-abu tanpa bayangan dan tanpa animasi.

### 4. Menu / Feature Card (Sub-menu / Opsi Alternatif)
* **Struktur Horizontal:**
  1. **Leading Icon:** Ukuran ~42x42dp, background `paleGreen` (`#E8F5E9`), ikon hijau 22dp, radius 12dp.
  2. **Middle Content:** Judul 14dp bold (`textPrimary`), deskripsi 11dp regular (`textSecondary`).
  3. **Trailing Badge:** Pill oval dengan background `paleGreen`, teks berwarna hijau primer bold 11dp (contoh: "Token", "Generator").

### 5. Section Header dengan Aksen Bar
* Setiap kelompok konten baru diawali dengan garis aksen vertikal:
  * Batang vertikal: Lebar 4dp, tinggi 18dp, warna hijau primer, radius 2dp.
  * Jarak 8dp ke teks judul kategori (15dp, bold).
  * Tombol aksi sekunder di sisi kanan (misalnya tombol "Hapus Semua" dengan chip merah pastel).

### 6. Modal Dialog & Input Token
* Latar belakang transparan dengan overlay `Colors.black.withValues(alpha: 0.75)`.
* Kontainer putih dengan radius **28dp** dan padding 24–28dp.
* Ikon bulat besar di bagian atas tengah.
* Dua tombol sejajar di bagian bawah:
  * Tombol Batal: `TextButton` abu-abu netral (`grey600`).
  * Tombol Aksi: `ElevatedButton` dengan gradien hijau primer berbayangan lembut.

### 7. Slide-to-Confirm / Slide-to-Unblock (Aksi Kritis)
* Alternatif tombol swipe agar tidak sengaja terpencet:
  * Tinggi 60dp, radius 30dp.
  * Background pastel (`paleGreen`), slider bulat hijau.
  * Teks ajakan di tengah dengan animasi *shimmer*.
  * Threshold aktivasi: Trigger aksi jika digeser > 70% dari lebar maksimum, auto-reset jika dilepas sebelum 70%.

---

## 5. Cuplikan Kode Siap Pakai (Flutter Ready-to-Copy)

### `app_colors.dart`
```dart
import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Primary
  static const Color primaryGreen = Color(0xFF2E7D32);
  static const Color primaryDark  = Color(0xFF1B5E20);
  static const Color paleGreen    = Color(0xFFE8F5E9);

  // Status
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFFA726);
  static const Color error   = Color(0xFFE53935);
  static const Color info    = Color(0xFF2196F3);

  // Text
  static const Color textPrimary   = Color(0xFF212121);
  static const Color textSecondary = Color(0xFF757575);
  static const Color textDisabled  = Color(0xFFBDBDBD);

  // Neutral & Surfaces
  static const Color scaffoldBg    = Color(0xFFF5F7F5);
  static const Color surfaceWhite   = Color(0xFFFFFFFF);
  static const Color grey100       = Color(0xFFF5F5F5);
  static const Color grey300       = Color(0xFFE0E0E0);
}
```

### `responsive_helper.dart`
```dart
import 'package:flutter/material.dart';

extension ResponsiveContext on BuildContext {
  double get _scale =>
      (MediaQuery.of(this).size.shortestSide / 360.0).clamp(0.85, 1.40);

  double rs(double base) => base * _scale;
  bool get isTablet => MediaQuery.of(this).size.shortestSide >= 600;
  double get horizontalPadding => isTablet ? rs(40) : rs(20);
}

class MaxWidthBox extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  const MaxWidthBox({super.key, required this.child, this.maxWidth = 600});

  @override
  Widget build(BuildContext context) {
    if (!context.isTablet) return child;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
```

### `theme_config.dart`
```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: false,
    scaffoldBackgroundColor: AppColors.scaffoldBg,
    primaryColor: AppColors.primaryGreen,
    textTheme: GoogleFonts.poppinsTextTheme(ThemeData.light().textTheme),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.primaryGreen,
      elevation: 0,
      centerTitle: true,
      iconTheme: const IconThemeData(color: Colors.white),
      titleTextStyle: GoogleFonts.poppins(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primaryGreen,
        foregroundColor: Colors.white,
        elevation: 2,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    ),
  );
}
```

---

## 6. Panduan Adaptasi ke Aplikasi Lain

1. **Mengubah Tema Warna (Branding Lain):**
   * Ganti `primaryGreen` (`#2E7D32`) dan `primaryDark` (`#1B5E20`) dengan warna brand target (misal: Deep Blue `#1565C0` & `#0D47A1` untuk aplikasi korporat/finansial, atau Deep Purple `#6A1B9A` untuk aplikasi kreatif).
   * Ganti `paleGreen` (`#E8F5E9`) dengan warna *tint* 50 dari brand baru (misal: `#E3F2FD` untuk biru).
2. **Jika diterapkan ke Web / Tailwind CSS:**
   * Konversikan token ke file `tailwind.config.js`:
     ```js
     theme: {
       extend: {
         colors: {
           brand: {
             DEFAULT: '#2E7D32',
             dark: '#1B5E20',
             pale: '#E8F5E9',
           }
         },
         borderRadius: {
           card: '20px',
           dialog: '28px',
         }
       }
     }
     ```
3. **Komponen Wajib Dipertahankan:**
   * Konsistensi radius kartu (20–24px) dengan bayangan lembut beropasitas rendah (4–7%).
   * Pola kartu leading-icon persegi rounded + label + trailing pill badge.
   * Pembatas lebar tablet (`MaxWidthBox` / `max-w-xl mx-auto`).

