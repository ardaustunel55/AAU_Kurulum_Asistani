# Değişiklik Günlüğü (CHANGELOG)

Bu projedeki tüm önemli değişiklikler bu dosyada belgelenmektedir.

---

## [2.0.0] - 2026-11-27

### ✨ Yeni Özellikler
- **Format Sonrası Sihirbazı (`[21]`):** 5 adımlı otomatik kurulum ve optimizasyon sihirbazı (geri yükleme noktası → debloat → arayüz konforu → güç planı → profil bazlı uygulama kurulumu).
- **Debloat & Gizlilik Merkezi (`[22]`):** Gereksiz yerleşik Windows uygulamalarını kaldırma, telemetri/reklamları kapatma, Copilot/Widgets/Edge arka plan süreçlerini devre dışı bırakma ve zorunlu güncelleme yeniden başlatmalarını engelleme.
- **Windows & Office Lisanslama (`[19]`):** MAS entegrasyonu ile lisanslama aracı.
- **Direct URL Kurulum Desteği:** WinGet ve Microsoft Store'a ek olarak doğrudan indirme (`direct_url`) kurulum türü ve Microsoft Office 365 ProPlus desteği.
- **Gerçek Sistem Otomasyonları:**
  - **Kişiselleştirme (`[16]`):** Açık/Koyu tema, dosya uzantıları, gizli dosyalar, Windows 11 görev çubuğu hizalama ve klasik sağ tık menüsü, masaüstü simgeleri.
  - **Ağ Araçları (`[8]`):** Winsock sıfırlama, IP yenileme, aktif TCP portları, Hosts dosyası görüntüleme/düzenleme.
  - **Sürücü Yönetimi (`[9]`):** Otomatik GPU algılama ve sürücü yardımcısı (`Invoke-GpuAutoDetectDriver`).
  - **Yedekleme & Kurtarma (`[10]`):** Wi-Fi profili yedekleme ve geri yükleme (`Invoke-WifiProfileBackupRestore`).
  - **Güvenlik Merkezi (`[11]`):** Windows Defender dışlama (exclusion) yöneticisi (`Invoke-DefenderExclusionManager`).
  - **Performans Optimizasyonu (`[12]`):** Hızlı Başlatma, Yüksek/Nihai Performans güç planları, WSearch/SysMain servis kontrolü, hazırda bekletme, oyun optimizasyonları (GameDVR/HAGS/fare ivmesi).
  - **Kullanıcı Yönetimi (`[13]`):** `New-LocalUser` / `Set-LocalUser` / `Remove-LocalUser` ile yerel hesap ve yönetici yetkisi yönetimi (Windows Home uyumlu).
  - **Tanı ve Onarım (`[14]`):** Windows Update indirme önbelleği sıfırlama.
- **Yönetici Paneli Geliştirmeleri:** Katalog sihirbazına `direct_url` desteği ve kullanıcı paneline geçiş (`[13]`) seçeneği eklendi.
- **Otomatik Kayıt Defteri Temizliği:** Program kaldırma sonrası kalan kayıt defteri anahtarlarının temizlenmesi (`Remove-ProgramLeftoverRegistryKeys`).

### 🐛 Hata Düzeltmeleri
- **WinGet İlerleme Çubuğu:** `winget` çıktısının fonksiyon tarafından yakalanıp ilerleme çubuğunun boş görünmesine neden olan sorun `Start-Process -NoNewWindow -Wait -PassThru` ile düzeltildi.
- **Program Yönetimi Arama Hatası:** Tek sonuç dönen aramalarda PowerShell dizi açılımı (array unwrap) kaynaklı çökme `@()` sarmalayıcısı ile giderildi; sekmeye girişte önbellek otomatik yenileniyor.
- **ASCII Kutu Hizalama & Menü Düzeni:** Açılış/kapanış animasyonlarındaki kutu taşmaları dinamik ortalama ile düzeltildi, ana menü sütun hizalaması (`PadRight(29)`) ve `[6]` ↔ `[16]` sıralaması düzenlendi.
- **Sessiz Çalışma:** Tüm `[Console]::Beep` ses çağrıları kaldırıldı.

### 🧹 Temizlik & Test
- Katalog **74 doğrulanmış uygulama** (sıralı `1..74` `InstallOrder`) ve **9 kurulum profili** olacak şekilde sadeleştirildi.
- 17 boş modül alt klasörü, kullanılmayan klasörler ve bozuk/artık yedek dosyalar temizlendi.
- 62 senaryolu otomatik test paketi (`test_runner.ps1`) ile tam doğrulama sağlandı.

---

## [1.0.0] - 2026-11-14

### 🎉 İlk Sürüm
- JSON tabanlı merkezi uygulama kataloğu ve profil sistemi.
- WinGet ve Microsoft Store kurulum motoru.
- Modüler PowerShell mimarisi (`admin`, `installer`, `system`).
- UAC yetki yükseltmeli `AAU.cmd` başlatıcısı ve `Start-AAU.ps1` tek komutlu kurulum betiği.
