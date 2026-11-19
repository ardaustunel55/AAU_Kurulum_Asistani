# 🚀 AAU Kurulum Asistanı

**Windows ve PowerShell tabanlı, modüler uygulama kurulum ve sistem yönetim asistanı.**

Format sonrası veya yeni sistem kurulumlarında ihtiyaç duyulan yazılımları, sistem yapılandırmalarını ve otomasyon görevlerini tek merkezden, hızlı ve hatasız şekilde yönetmek için geliştirilmiştir.

---

## ✨ Öne Çıkan Özellikler

* ⚡ **Tek Tıkla Otomatik Kurulum:** Önceden tanımlanmış uygulama listelerini katılımsız ve sıralı şekilde kurar.
* 🛡️ **Yönetici Yetkisi Desteği:** Sistem düzeyindeki işlemler için doğrudan yükseltilmiş yetki (`AAU_Admin.cmd`) ile başlatma imkânı sunar.
* 🧩 **Modüler Mimari:** Kurulum ve sistem yönetim görevleri birbirinden bağımsız modüller halinde tasarlanmıştır; kolayca genişletilebilir.
* ⚙️ **Esnek Yapılandırma:** Kurulum paketleri ve tercihler `config` ve `data` dizinleri üzerinden kod değişikliği gerektirmeden düzenlenebilir.
* 🧪 **Entegre Test Altyapısı:** `test_runner.ps1` ile modüllerin ve betiklerin kararlılığı kolayca doğrulanabilir.

---

## 📁 Proje Klasör Yapısı

```text
AAU_Kurulum_Asistani/
├── assets/             # Arayüz görselleri, ikonlar ve statik kaynaklar
├── config/             # Uygulama ayarları ve yapılandırma dosyaları
├── data/               # Kurulum listeleri ve yerel veri dosyaları
├── modules/            # Bağımsız PowerShell / sistem yönetim modülleri
├── src/                # Ana uygulama kaynak kodları
├── AAU.cmd             # Standart kullanıcı başlatıcısı
├── AAU_Admin.cmd       # Yönetici (Administrator) yetkili başlatıcı
├── test_runner.ps1     # Otomatik test ve doğrulama betiği
└── README.md           # Proje dokümantasyonu