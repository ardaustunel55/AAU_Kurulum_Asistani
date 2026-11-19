# 🚀 AAU Kurulum Asistanı

### Windows için modern, pratik ve merkezi uygulama kurulum asistanı

**AAU Kurulum Asistanı**, Windows kullanıcılarının ihtiyaç duydukları popüler masaüstü uygulamalarını tek bir merkezden keşfetmelerini, seçmelerini ve kurmalarını kolaylaştırmak amacıyla geliştirilen bir Windows yazılım yönetimi projesidir.

Uygulama, Windows Package Manager (WinGet) ve Microsoft Store kaynaklarından yararlanarak uygulama kurulum sürecini daha düzenli ve erişilebilir hâle getirmeyi hedefler.


<p align="center">
  <a href="https://github.com/ardaustunel55/AAU_Kurulum_Asistani">
    <img src="https://img.shields.io/badge/GitHub-Repository-181717?style=for-the-badge&logo=github" alt="GitHub Repository">
  </a>
  <img src="https://img.shields.io/badge/Platform-Windows-0078D4?style=for-the-badge&logo=windows" alt="Windows">
  <img src="https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?style=for-the-badge&logo=powershell" alt="PowerShell">
  <img src="https://img.shields.io/badge/Package_Manager-WinGet-00A4EF?style=for-the-badge" alt="WinGet">
  <img src="https://img.shields.io/badge/Language-T%C3%BCrk%C3%A7e-red?style=for-the-badge" alt="Türkçe">
</p>


---

## 📌 İçindekiler

- [Proje Hakkında](#-proje-hakkında)
- [Projenin Amacı](#-projenin-amacı)
- [Özellikler](#-özellikler)
- [Uygulama Kataloğu](#-uygulama-kataloğu)
- [Kullanılan Teknolojiler](#-kullanılan-teknolojiler)
- [Sistem Gereksinimleri](#-sistem-gereksinimleri)
- [Hızlı Kurulum](#-hızlı-kurulum)
- [Manuel Kurulum](#-manuel-kurulum)
- [Proje Yapısı](#-proje-yapısı)
- [Çalışma Mantığı](#-çalışma-mantığı)
- [Güvenlik ve İzinler](#-güvenlik-ve-izinler)
- [Güncelleme Sistemi](#-güncelleme-sistemi)
- [Sorun Giderme](#-sorun-giderme)
- [Geliştirme ve Katkıda Bulunma](#-geliştirme-ve-katkıda-bulunma)
- [Kaynakça](#-kaynakça)
- [Lisans](#-lisans)
- [Geliştirici](#-geliştirici)

---

## 📖 Proje Hakkında

Bilgisayara yeni bir Windows kurulumu yapıldığında veya yeni bir bilgisayar kullanılmaya başlandığında, gerekli uygulamaların tek tek bulunması, indirilmesi ve kurulması zaman alabilir.

AAU Kurulum Asistanı, bu süreci tek bir uygulama üzerinden yönetilebilir hâle getirmek için geliştirilmiştir.

Proje kapsamında uygulama kataloğu, kurulum yönetimi ve sistem kontrolleri birbirinden ayrılmış modüller aracılığıyla yönetilir. Böylece uygulama yapısının daha düzenli, sürdürülebilir ve geliştirilebilir olması amaçlanır.

AAU, uygulama kurulumlarını kolaylaştırırken Windows'un mevcut paket yönetimi altyapısından yararlanır.

### 🎯 Projenin temel hedefleri

- Uygulama kurulumlarını tek merkezde toplamak.
- Kullanıcıların ihtiyaç duyduğu programlara daha kolay ulaşmasını sağlamak.
- Birden fazla uygulamanın kurulumunu yönetilebilir hâle getirmek.
- Uygulama kataloğunu merkezi bir JSON yapısı üzerinden yönetmek.
- Kurulum sırasında oluşan durumları ve hataları takip edebilmek.
- Modüler ve geliştirilebilir bir yazılım mimarisi oluşturmak.
- Windows kullanıcıları için sade ve erişilebilir bir deneyim sunmak.

---

## ✨ Özellikler

### 📦 Merkezi Uygulama Kataloğu

Uygulamalar merkezi bir katalog üzerinden yönetilir.

Katalog yapısı sayesinde uygulama isimleri, paket bilgileri, kategoriler ve kaynak tanımları düzenli bir şekilde saklanabilir.

### ⚡ Toplu Kurulum Yaklaşımı

Kullanıcıların ihtiyaç duydukları birden fazla uygulamayı seçerek kurulum sürecini tek bir noktadan yönetebilmesi hedeflenir.

### 🗂️ Kategorilere Ayrılmış Uygulamalar

Programların kategorilere ayrılması, kullanıcıların ihtiyaç duydukları yazılımları daha kolay bulmasına yardımcı olur.

### 🌐 WinGet ve Microsoft Store Desteği

Uygulama kataloğunda WinGet ve Microsoft Store kaynakları kullanılmaktadır.

Kurulum işlemleri, ilgili paket yöneticisinin sunduğu imkânlar üzerinden gerçekleştirilir.

### 🔍 Sistem ve Kaynak Kontrolleri

Kurulum öncesinde WinGet kullanılabilirliği, internet bağlantısı ve paket kaynaklarının durumu kontrol edilebilir.

### 📊 Katalog İstatistikleri

Katalog yöneticisi aracılığıyla toplam uygulama sayısı, etkin kayıtlar, kaynak dağılımı ve kategori sayısı gibi bilgiler alınabilir.

### 🧩 Modüler Yazılım Mimarisi

Katalog yönetimi, kurulum işlemleri ve uygulama giriş noktası farklı dosya ve modüller üzerinden düzenlenmiştir.

Bu yaklaşım, yeni özelliklerin mevcut yapıyı mümkün olduğunca az etkilemesini amaçlar.

---

## 🗃️ Uygulama Kataloğu

AAU Kurulum Asistanı'nın uygulama kataloğu, `data/apps/apps.json` dosyası üzerinden yönetilir.

Bu yapı, uygulama kayıtlarının program kodundan ayrı tutulmasına yardımcı olur.

### Katalog yapısı

Son gerçekleştirilen katalog doğrulama testinde aşağıdaki sonuçlar alınmıştır:

| Katalog bilgisi | Test sonucu |
|---|---:|
| Toplam uygulama | 128 |
| Etkin uygulama | 128 |
| Devre dışı uygulama | 0 |
| WinGet kaynaklı kayıt | 123 |
| Microsoft Store kaynaklı kayıt | 5 |
| Kategori sayısı | 8 |
| Doğrulanmamış kayıt | 0 |

> **Not:** Bu değerler test sırasında alınmış katalog istatistikleridir. Uygulama kataloğu güncellendikçe sayılar değişebilir. Bu tablo her zaman canlı katalog verisi olarak değerlendirilmemelidir.

### Kategori sistemi

Uygulamalar, katalogda tanımlanan kategorilere göre sınıflandırılır.

Kategoriler ve uygulama kayıtları `apps.json` üzerinden yönetilebilir. Yeni uygulama eklemek için mevcut katalog şemasına uygun bir kayıt oluşturulması gerekir.

---

## 🛠️ Kullanılan Teknolojiler

| Teknoloji | Kullanım amacı |
|---|---|
| PowerShell 5.1 | Uygulama mantığı ve sistem işlemleri |
| Windows CMD | Başlatıcı ve komut dosyaları |
| WinGet | Paket arama ve uygulama kurulumu |
| Microsoft Store | Mağaza tabanlı uygulama kaynağı |
| JSON | Uygulama kataloğu ve yapılandırma verileri |
| Git | Kaynak kodu sürüm kontrolü |
| GitHub | Proje deposu ve kaynak kod barındırma |

### WinGet neden kullanılıyor?

WinGet, Windows için Microsoft tarafından sunulan paket yönetim aracıdır.

Uygulamaların aranması, kurulması, güncellenmesi ve kaldırılması gibi işlemlere komut satırı üzerinden erişim sağlar.

AAU, bu altyapıyı kullanarak desteklenen uygulamaların kurulum sürecini merkezi hâle getirmeyi amaçlar.

---

## 💻 Sistem Gereksinimleri

| Gereksinim | Açıklama |
|---|---|
| İşletim sistemi | Windows 10 (1809 veya üzeri) / Windows 11 |
| PowerShell | Windows PowerShell 5.1 |
| Paket yöneticisi | WinGet |
| İnternet bağlantısı | İlk indirme ve çevrimiçi kurulumlar için gerekli |
| Depolama | Uygulama ve kurulacak programlar için yeterli boş alan |
| Yetki | Bazı uygulamaların kurulumu için yönetici izni gerekebilir |

**Önemli:** WinGet, Windows üzerinde App Installer bileşeni aracılığıyla sağlanır. Sisteminde bulunmuyorsa öncelikle App Installer durumunu kontrol etmelisin.

---

## ⚡ Hızlı Kurulum

AAU Kurulum Asistanı'nı GitHub üzerinden indirmek ve başlatmak için Windows PowerShell'i aç.

Aşağıdaki komutu çalıştır:

```powershell
irm https://raw.githubusercontent.com/ardaustunel55/AAU_Kurulum_Asistani/master/Start-AAU.ps1 | iex
```

### Kurulum işlemi nasıl çalışır?

1. GitHub üzerindeki başlangıç betiği indirilir.
2. Kurulum için gerekli geçici klasör hazırlanır.
3. Proje arşivi GitHub üzerinden indirilir.
4. Arşiv açılır ve proje dosyaları kontrol edilir.
5. Gerekli dosyalar doğrulandıktan sonra kurulum klasörüne aktarılır.
6. `AAU.cmd` başlatıcısı üzerinden uygulama çalıştırılır.

### Kurulum konumu

Başlangıç betiğinin kullandığı varsayılan kurulum konumu:

```text
%LOCALAPPDATA%\AAU_Kurulum_Asistani
```

Bu konum, kullanıcının yerel Windows uygulama verileri dizini altındadır.

> **Güvenlik notu:** PowerShell üzerinden uzaktaki bir betiği çalıştırmadan önce kaynak kodunu incelemeni öneririz. Komut GitHub'daki `master` dalından betik indirip çalıştırır. Bu yöntem şu an için proje başlatma yöntemidir; imzalı veya checksum doğrulamalı bir dağıtım paketi olarak değerlendirilmemelidir.

---

## 🔧 Manuel Kurulum

Projeyi kaynak kod üzerinden incelemek veya geliştirmek isteyenler için:

### 1. Depoyu klonla

```powershell
git clone https://github.com/ardaustunel55/AAU_Kurulum_Asistani.git
```

### 2. Proje klasörüne gir

```powershell
cd AAU_Kurulum_Asistani
```

### 3. WinGet kontrolü

```powershell
winget --version
```

WinGet düzgün şekilde kuruluysa sürüm bilgisi görüntülenir.

### 4. Uygulamayı başlat

```powershell
.\AAU.cmd
```

Başlatıcı, uygulamanın giriş dosyasını kontrol ederek ana programı çalıştırır.

---

## 📁 Proje Yapısı

Projenin genel klasör düzeni:

```text
AAU_Kurulum_Asistani/
│
├── .git/
│
├── assets/
│   └── Görsel ve arayüz kaynakları
│
├── config/
│   └── Yapılandırma dosyaları
│
├── data/
│   └── apps/
│       └── apps.json
│
├── docs/
│   └── Proje dokümantasyonu
│
├── logs/
│   └── Günlük kayıtları
│
├── modules/
│   └── Uygulama modülleri
│
├── reports/
│   └── Rapor dosyaları
│
├── scratch/
│   └── Geliştirme ve geçici çalışma alanı
│
├── src/
│   └── main.ps1
│
├── tests/
│   └── Test dosyaları
│
├── AAU.cmd
├── Start-AAU.ps1
└── README.md
```

> Klasör açıklamaları genel görevlerini belirtir. Proje geliştikçe dosya ve klasör yapısı değişebilir.

### Önemli dosyalar

| Dosya | Görevi |
|---|---|
| `AAU.cmd` | Normal kullanıcı başlatıcısı |
| `Start-AAU.ps1` | GitHub üzerinden indirme ve başlatma betiği |
| `src/main.ps1` | Ana uygulama giriş noktası |
| `data/apps/apps.json` | Uygulama kataloğu |
| `modules/` | Uygulama işlevlerini içeren modüller |
| `tests/` | Test dosyaları |
| `docs/` | Dokümantasyon |

---

## ⚙️ Çalışma Mantığı

AAU Kurulum Asistanı'nın temel çalışma akışı aşağıdaki bileşenlerden oluşur.

### 1. Başlatma katmanı

`AAU.cmd`, uygulamanın normal kullanıcı tarafından başlatılmasını sağlar.

Başlatıcı, gerekli dosyaları kontrol eder ve ana PowerShell dosyasını çalıştırır.

### 2. Ana uygulama

`src/main.ps1`, uygulamanın giriş noktasıdır.

Uygulamanın başlatılması ve ilgili modüllerin kullanılması bu dosya üzerinden yönetilir.

### 3. Katalog yönetimi

Katalog yöneticisi, JSON dosyasındaki uygulama kayıtlarını yükler ve uygulama listelerinin oluşturulmasına yardımcı olur.

### 4. Kurulum yönetimi

Kurulum modülü, uygulama kayıtlarını kullanarak WinGet üzerinden ilgili paket kurulum işlemlerini yürütür.

### 5. Sistem kontrolleri

Kurulum işlemlerinden önce gerekli araçların ve bağlantı durumunun kontrol edilmesi amaçlanır.

---

## 🔐 Güvenlik ve İzinler

AAU Kurulum Asistanı, Windows'un mevcut güvenlik mekanizmalarıyla uyumlu çalışmayı hedefler.

### Yönetici izinleri

Bazı yazılımların kurulumu yönetici izni gerektirebilir.

Bu durumda Windows'un Kullanıcı Hesabı Denetimi (UAC) mekanizması devreye girebilir.

### Yönetici paneli

Yönetici paneli, geliştiricinin kişisel kullanımına yönelik ayrı bir başlatıcı olarak tutulmaktadır.

`AAU_Admin.cmd`, herkese açık normal kullanıcı kurulumunun parçası değildir.

**Önemli:** Bir başlatıcı dosyasının GitHub'dan kaldırılması, onun çağırdığı diğer kaynak kodların da gizlendiği anlamına gelmez. Yönetici işlevlerinin gerçekten özel kalması için ilgili kodların ve erişim kontrollerinin ayrıca değerlendirilmesi gerekir.

### Üçüncü taraf uygulamalar

AAU, üçüncü taraf yazılımların kurulumunu kolaylaştırır. Kurulan yazılımların lisansları, gizlilik politikaları ve kullanım koşulları ilgili geliştiricilere aittir.

Kullanıcılar kurulum öncesinde uygulama adını, paket kimliğini ve kaynağını kontrol etmelidir.

---

## 🔄 Güncelleme Sistemi

Proje, GitHub üzerinde sürüm kontrolü kullanılarak geliştirilmektedir.

Kaynak kodundaki değişiklikler `master` dalına gönderilir.

Başlangıç betiği, ilk kurulumda GitHub arşivini indirir. Mevcut kurulumun otomatik olarak güncel sürüme yükseltilmesi ise bu betiğin şu anki işlevi değildir.

Güncelleme mekanizması geliştirilirken mevcut kullanıcı verilerinin korunması, dosya bütünlüğünün kontrol edilmesi ve başarısız güncellemelerde geri dönüş imkânı sağlanması hedeflenmektedir.

---

## 🧪 Test ve Doğrulama

Proje geliştirme sürecinde aşağıdaki kontroller gerçekleştirilmiştir:

- JSON katalog dosyasının ayrıştırılması.
- Uygulama katalog kayıtlarının yüklenmesi.
- Katalog istatistiklerinin alınması.
- Katalog ve kurulum modüllerinin içe aktarılması.
- WinGet kullanılabilirliğinin kontrol edilmesi.
- İnternet bağlantısı kontrolü.
- Paket kaynaklarının durumunun kontrol edilmesi.
- Başlangıç betiğinin PowerShell sözdizimi kontrolü.

Test sonuçları, geliştirmenin ilgili aşamasındaki durumu gösterir. Her Windows sürümünde ve her uygulama paketinde aynı sonuçların alınacağı garanti edilmez.

---

## 🛠️ Sorun Giderme

### WinGet bulunamadı

PowerShell üzerinde:

```powershell
winget --version
```

komutunu çalıştır.

Komut tanınmıyorsa Windows App Installer bileşenini kontrol et.

### İnternet bağlantısı bulunamadı

İnternet bağlantını kontrol et ve PowerShell üzerinden tekrar dene.

### Uygulama kataloğu yüklenemedi

`data/apps/apps.json` dosyasının mevcut olduğunu ve geçerli JSON biçiminde kaydedildiğini kontrol et.

JSON kontrolü:

```powershell
Get-Content .\data\apps\apps.json -Raw | ConvertFrom-Json
```

### Ana uygulama dosyası bulunamadı

Aşağıdaki dosyanın mevcut olduğunu kontrol et:

```text
src/main.ps1
```

### Yönetici izni gerekli

Kurulmak istenen uygulamanın yönetici izni gerektirip gerektirmediğini kontrol et. Yalnızca güvendiğin uygulamalar için Windows'un izin istemini onayla.

### Kaynak indirme hatası

GitHub deposuna erişilebildiğini ve `master` dalındaki `Start-AAU.ps1` dosyasının mevcut olduğunu kontrol et.

---

## 🤝 Geliştirme ve Katkıda Bulunma

AAU Kurulum Asistanı geliştirilmeye devam eden bir projedir.

Projeye katkıda bulunmak isteyen geliştiriciler aşağıdaki akışı izleyebilir:

### 1. Depoyu forklayın

GitHub üzerinden projeyi kendi hesabınıza fork edin.

### 2. Yerel kopyayı oluşturun

```powershell
git clone https://github.com/ardaustunel55/AAU_Kurulum_Asistani.git
cd AAU_Kurulum_Asistani
```

### 3. Yeni bir dal oluşturun

```powershell
git checkout -b feature/yeni-ozellik
```

### 4. Değişikliklerinizi gerçekleştirin

Kod düzenlemelerini mevcut modüler yapıyı koruyarak gerçekleştirin.

### 5. Değişiklikleri test edin

Özellikle katalog, kurulum ve başlatma işlemlerinin etkilenmediğini kontrol edin.

### 6. Commit oluşturun

```powershell
git add .
git commit -m "feat: add new feature"
```

### 7. Değişiklikleri gönderin

```powershell
git push origin feature/yeni-ozellik
```

### 8. Pull Request açın

GitHub üzerinden ana depoya Pull Request göndererek değişikliklerin incelenmesini sağlayın.

### Katkı ilkeleri

- Mevcut dosya ve klasör düzenini koruyun.
- Kullanıcı verilerini izinsiz değiştirmeyin.
- Hassas bilgileri kaynak koduna eklemeyin.
- Test edilmemiş özellikleri tamamlanmış olarak tanımlamayın.
- Yeni uygulama kayıtlarında doğru paket kimliği ve kaynak bilgisi kullanın.
- Yöneticiye özel dosyaları herkese açık dağıtıma eklemeyin.

---

## 🗺️ Geliştirme Yol Haritası

Projenin geliştirme sürecinde değerlendirilebilecek hedefler:

- [x] Merkezi JSON uygulama kataloğu
- [x] WinGet kaynak entegrasyonu
- [x] Microsoft Store kaynak kayıtları
- [x] Katalog istatistikleri
- [x] PowerShell başlangıç betiği
- [x] Normal kullanıcı başlatıcısı
- [ ] Güvenli ve doğrulanabilir otomatik güncelleme
- [ ] Sürüm ve değişiklik geçmişi
- [ ] Daha kapsamlı otomatik testler
- [ ] Kurulum geçmişinin geliştirilmesi
- [ ] Hata raporlama ve tanılama sisteminin geliştirilmesi
- [ ] Dağıtım paketinin imzalanması ve bütünlük doğrulaması

> Yol haritası, geliştirme hedeflerini ifade eder. Tamamlanmamış maddeler mevcut sürümde kullanılabilir özellikler olarak değerlendirilmemelidir.

---

## 📚 Kaynakça

Bu proje geliştirilirken yararlanılan ve teknik dokümantasyon amacıyla başvurulabilecek resmî kaynaklar:

| Kaynak | Açıklama |
|---|---|
| [Microsoft WinGet Dokümantasyonu](https://learn.microsoft.com/windows/package-manager/winget/) | Windows paket yönetimi |
| [WinGet Install Komutu](https://learn.microsoft.com/windows/package-manager/winget/install) | Paket kurulum parametreleri |
| [WinGet GitHub Deposu](https://github.com/microsoft/winget-cli) | WinGet kaynak kodu |
| [PowerShell Dokümantasyonu](https://learn.microsoft.com/powershell/) | PowerShell komutları ve betik geliştirme |
| [Git Dokümantasyonu](https://git-scm.com/doc) | Sürüm kontrol sistemi |
| [GitHub Docs](https://docs.github.com/) | Depo yönetimi ve katkı süreçleri |

---

## 📄 Lisans

Bu deponun lisans koşulları, depoya bir `LICENSE` dosyası eklenerek açıkça belirtilmelidir.

Bir lisans seçilene kadar kaynak kodun herkese açık olması, otomatik olarak sınırsız değiştirme, yeniden dağıtma veya ticari kullanım izni verildiği anlamına gelmez.

Kullanılan üçüncü taraf yazılımlar ve paketler kendi lisans koşullarına tabidir.

---

## 👨‍💻 Geliştirici

**Ali Arda Üstünel**

AAU Kurulum Asistanı, Windows kullanıcılarının uygulama kurulum sürecini kolaylaştırmak amacıyla geliştirilen bağımsız bir yazılım projesidir.

Projenin geliştirme, bakım ve iyileştirme çalışmaları devam etmektedir.

- **GitHub:** [ardaustunel55](https://github.com/ardaustunel55)
- **Proje deposu:** [AAU Kurulum Asistanı](https://github.com/ardaustunel55/AAU_Kurulum_Asistani)

---

<p align="center">
  <strong>AAU Kurulum Asistanı</strong>
  <br>
  Windows kurulum deneyimini daha kolay hâle getirmek için.
  <br><br>
  © 2026 Ali Arda Üstünel
</p>