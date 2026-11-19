# 🚀 AAU Kurulum Asistanı

```{=html}
<p align="center">
```
`<strong>`{=html}Windows uygulama kurulumunu tek noktadan yönetmek için
geliştirilen yardımcı araç.`</strong>`{=html}
```{=html}
</p>
```
```{=html}
<p align="center">
```
`<a href="https://github.com/ardaustunel55/AAU_Kurulum_Asistani">`{=html}
`<img src="https://img.shields.io/badge/GitHub-Repository-181717?style=for-the-badge&logo=github&logoColor=white" alt="GitHub Repository">`{=html}
`</a>`{=html}
`<img src="https://img.shields.io/badge/Platform-Windows-0078D4?style=for-the-badge&logo=windows&logoColor=white" alt="Windows">`{=html}
`<img src="https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?style=for-the-badge&logo=powershell&logoColor=white" alt="PowerShell">`{=html}
`<img src="https://img.shields.io/badge/Package_Manager-WinGet-00A4EF?style=for-the-badge" alt="WinGet">`{=html}
`<img src="https://img.shields.io/badge/Language-Turkish-red?style=for-the-badge" alt="Turkish">`{=html}
```{=html}
</p>
```

------------------------------------------------------------------------

## İçindekiler

-   [Proje hakkında](#proje-hakkında)
-   [Amaç ve yaklaşım](#amaç-ve-yaklaşım)
-   [Özellikler](#özellikler)
-   [Uygulama kataloğu](#uygulama-kataloğu)
-   [Teknolojiler](#teknolojiler)
-   [Sistem gereksinimleri](#sistem-gereksinimleri)
-   [Hızlı kurulum](#hızlı-kurulum)
-   [Manuel kurulum](#manuel-kurulum)
-   [Proje yapısı](#proje-yapısı)
-   [Çalışma akışı](#çalışma-akışı)
-   [Güvenlik ve gizlilik](#güvenlik-ve-gizlilik)
-   [Güncelleme yaklaşımı](#güncelleme-yaklaşımı)
-   [Sorun giderme](#sorun-giderme)
-   [Geliştirme ve katkı](#geliştirme-ve-katkı)
-   [Kaynakça](#kaynakça)
-   [Lisans](#lisans)
-   [Geliştirici](#geliştirici)

------------------------------------------------------------------------

## Proje hakkında

**AAU Kurulum Asistanı**, Windows bilgisayarlarda sık kullanılan
masaüstü uygulamalarının bulunması ve kurulması sürecini kolaylaştırmak
amacıyla geliştirilen bir yazılım projesidir.

Proje; uygulama kataloğunu, kurulum işlemlerini ve başlangıç akışını
ayrı bileşenler üzerinden yönetmeyi hedefler. Uygulama kayıtları JSON
dosyasında tutulur; desteklenen paketlerin kurulumu için Windows Package
Manager (WinGet) ve Microsoft Store kaynaklarından yararlanılır.

AAU'nun amacı, kullanıcıların ihtiyaç duydukları programları tek tek
aramak yerine düzenli bir katalog üzerinden seçebilmesini ve kurulum
sürecini daha anlaşılır biçimde takip edebilmesini sağlamaktır.

> **Proje durumu:** AAU geliştirme aşamasındadır. Bu belgede
> tamamlandığı doğrulanmamış özellikler mevcut özellik gibi
> sunulmamıştır. Arayüz ve modül davranışları sürüme göre değişebilir.

## Amaç ve yaklaşım

Projenin temel hedefleri:

-   Yaygın masaüstü uygulamalarını merkezi bir katalogda toplamak.
-   Uygulamaları kategorilere ayırarak keşfetmeyi kolaylaştırmak.
-   Birden fazla uygulamanın kurulumunu tek bir akışta yönetebilmek.
-   Katalog verilerini uygulama kodundan ayrı tutmak.
-   Kurulum öncesinde gerekli araç ve bağlantı kontrollerini yapmak.
-   Hata ve işlem kayıtlarının incelenebilmesini sağlamak.
-   Yeni özelliklerin eklenmesini kolaylaştıran modüler bir yapı
    oluşturmak.

## Özellikler

### Merkezi uygulama kataloğu

Uygulama kayıtları `data/apps/apps.json` dosyasında tutulur. Katalog
yöneticisi bu kayıtları yükleyerek uygulama listesinin oluşturulmasına
yardımcı olur.

### WinGet ve Microsoft Store kaynakları

Katalog kayıtları, tanımlandıkları kaynağa göre WinGet veya Microsoft
Store üzerinden kurulum akışına yönlendirilebilir. Her uygulamanın
kullanılabilirliği, paket kimliğine ve ilgili kaynağın durumuna
bağlıdır.

### Toplu kurulum yaklaşımı

Kullanıcının birden fazla uygulama seçerek kurulum işlemlerini tek
yerden yönetebilmesi hedeflenir. Gerçek kurulum sonucu; ağ bağlantısına,
paket kaynağına, Windows izinlerine ve ilgili uygulamanın dağıtım
koşullarına bağlıdır.

### Sistem ve kaynak kontrolleri

Geliştirme testlerinde WinGet'in kullanılabilirliği, internet bağlantısı
ve paket kaynaklarının durumu kontrol edilmiştir.

### Modüler yapı

Katalog yönetimi, kurulum işlevleri ve ana uygulama girişi farklı dosya
ve modüllere ayrılmıştır. Bu sayede bakım ve geliştirme süreçlerinin
daha düzenli yürütülmesi amaçlanır.

## Uygulama kataloğu

Katalog dosyası:

``` text
data/apps/apps.json
```

Geliştirme sırasında yapılan bir katalog doğrulama testinde aşağıdaki
sonuçlar alınmıştır:

  Ölçüt                       Test sonucu
  ------------------------- -------------
  Toplam uygulama kaydı               128
  Etkin kayıt                         128
  Devre dışı kayıt                      0
  WinGet kaynağı                      123
  Microsoft Store kaynağı               5
  Kategori                              8
  Doğrulanmamış kayıt                   0

Bu değerler test anındaki katalog çıktısını gösterir; güncel sürümdeki
sayılar farklı olabilir. Bir kaydın katalogda bulunması, ilgili
uygulamanın her cihazda kurulabileceği veya her zaman erişilebilir
olduğu anlamına gelmez.

## Teknolojiler

  -----------------------------------------------------------------------
  Teknoloji                           Kullanım alanı
  ----------------------------------- -----------------------------------
  Windows PowerShell 5.1              Betikler, sistem kontrolleri ve
                                      uygulama mantığı

  Windows CMD                         Başlatıcı dosyaları

  WinGet                              Desteklenen paketlerin yönetimi ve
                                      kurulumu

  Microsoft Store                     Mağaza kaynaklı uygulama kayıtları

  JSON                                Uygulama kataloğu ve
                                      yapılandırılmış veriler

  Git                                 Kaynak kodu sürüm kontrolü

  GitHub                              Kaynak kodu deposu ve proje iş
                                      birliği
  -----------------------------------------------------------------------

## Sistem gereksinimleri

-   Windows 10 (sürüm 1809 veya üzeri) ya da Windows 11.
-   Windows PowerShell 5.1.
-   Desteklenen kurulumlar için WinGet / App Installer.
-   İlk indirme ve çevrimiçi paket işlemleri için internet bağlantısı.
-   Kurulacak uygulamaların gerektirdiği kadar boş disk alanı.
-   Bazı uygulamalar için Windows yönetici izni.

Sistem gereksinimleri, kullanılan paketlerin ve proje sürümünün
gereksinimlerine göre değişebilir.

## Hızlı kurulum

> **Güvenlik uyarısı:** Aşağıdaki komut GitHub'daki betiği indirip
> mevcut PowerShell oturumunda çalıştırır. Uzak betikleri çalıştırmadan
> önce içeriğini inceleyin ve yalnızca güvendiğiniz kaynaklardan
> çalıştırın.

PowerShell üzerinden:

``` powershell
irm https://raw.githubusercontent.com/ardaustunel55/AAU_Kurulum_Asistani/master/Start-AAU.ps1 | iex
```

Başlangıç betiğinin mevcut tasarımına göre izlediği akış:

1.  GitHub üzerindeki `Start-AAU.ps1` betiğini indirir.
2.  Proje arşivini GitHub deposundan alır.
3.  Arşivi geçici bir klasöre açar.
4.  `AAU.cmd` ve `src/main.ps1` gibi gerekli dosyaları kontrol eder.
5.  Projeyi kullanıcı profili altındaki yerel kurulum dizinine
    yerleştirir.
6.  Normal kullanıcı başlatıcısını çalıştırır.

Varsayılan kurulum dizini:

``` text
%LOCALAPPDATA%\AAU_Kurulum_Asistani
```

Başlatma betiği mevcut kurulum klasörünü bulduğunda onu yeniden
indirmeden başlatabilir. Mevcut kurulumun otomatik olarak en yeni sürüme
güncellendiği varsayılmamalıdır.

## Manuel kurulum

Depoyu yerel bilgisayara klonlamak için:

``` powershell
git clone https://github.com/ardaustunel55/AAU_Kurulum_Asistani.git
cd AAU_Kurulum_Asistani
```

WinGet'in kullanılabilirliğini kontrol edin:

``` powershell
winget --version
```

Ardından normal başlatıcıyı çalıştırın:

``` powershell
.\AAU.cmd
```

Başlatma sırasında Windows izin istemi görüntülenirse, isteğin kaynağını
ve yapılacak işlemi kontrol etmeden onay vermeyin.

## Proje yapısı

Depoda bulunan temel klasör ve dosyaların genel açıklaması:

``` text
AAU_Kurulum_Asistani/
│
├── assets/                 # Görsel ve arayüz kaynakları
├── config/                 # Yapılandırma dosyaları
├── data/
│   └── apps/
│       └── apps.json       # Uygulama kataloğu
├── docs/                   # Dokümantasyon
├── logs/                   # İşlem günlükleri
├── modules/                # Uygulama modülleri
├── reports/                # Rapor çıktıları
├── scratch/                # Geliştirme çalışma alanı
├── src/
│   └── main.ps1            # Ana uygulama giriş noktası
├── tests/                  # Test dosyaları
├── AAU.cmd                 # Normal kullanıcı başlatıcısı
├── Start-AAU.ps1           # İndirme ve başlatma betiği
└── README.md
```

Klasörlerin içeriği geliştirme sürecinde değişebilir. Bu ağaç, projenin
temel düzenini açıklamak amacıyla verilmiştir.

### Önemli dosyalar

  Dosya                   Açıklama
  ----------------------- ----------------------------------------------------
  `AAU.cmd`               Normal kullanıcı için başlatıcı
  `Start-AAU.ps1`         GitHub üzerinden projeyi indiren ve başlatan betik
  `src/main.ps1`          Ana uygulama giriş noktası
  `data/apps/apps.json`   Uygulama kataloğu
  `modules/`              Katalog ve kurulum gibi işlevsel modüller
  `tests/`                Test betikleri

## Çalışma akışı

### 1. Başlatma

Kullanıcı `AAU.cmd` dosyasını çalıştırır. Başlatıcı, gerekli dosyaların
varlığını kontrol eder ve ana PowerShell betiğini başlatır.

### 2. Ana uygulama

`src/main.ps1`, uygulamanın giriş noktasıdır ve gerekli modüllerin
yüklenmesini yönetir.

### 3. Katalog yükleme

Katalog yöneticisi `apps.json` dosyasını okur ve uygulama kayıtlarını
kullanılabilir hâle getirir.

### 4. Kurulum

Kurulum modülü, katalogdaki kaynak ve paket bilgilerini kullanarak
desteklenen paket yöneticisi işlemlerini yürütür.

### 5. Kontrol ve kayıt

Sistem kontrolleri ve günlükleme bileşenleri, hata ayıklama ve işlem
takibi için kullanılır.

## Güvenlik ve gizlilik

AAU, Windows'un izin ve güvenlik mekanizmalarıyla uyumlu çalışmayı
hedefler. Bununla birlikte, paket kurulumu yapan her araçta olduğu gibi
kullanıcıların kaynakları ve izin isteklerini kontrol etmesi önemlidir.

-   Uzak betikleri çalıştırmadan önce kaynak kodunu inceleyin.
-   Yalnızca güvendiğiniz uygulamaları kurun.
-   Uygulama adı, paket kimliği ve kaynak eşleşmesini kontrol edin.
-   Yönetici iznini yalnızca gerekli ve güvenilir işlemler için verin.
-   Parola, erişim anahtarı, API anahtarı veya kişisel veri gibi gizli
    bilgileri depoya eklemeyin.
-   Üçüncü taraf uygulamaların lisans ve gizlilik koşullarını ayrıca
    inceleyin.

### Yönetici araçları hakkında

Bu herkese açık depoda normal kullanıcı başlatıcısı `AAU.cmd`
belgelenmektedir. Geliştiriciye özel yönetim araçları genel kullanıcı
kurulumunun parçası olarak sunulmaz.

**Önemli teknik ayrım:** Bir yönetici başlatıcısını Git takibinden
çıkarmak, yönetici işlevlerini içeren diğer kaynak kodları otomatik
olarak gizlemez. Özel kalması gereken kodların ayrı ve erişimi
kısıtlanmış bir yerde tutulması gerekir. Ayrıca herkese açık uygulamanın
içinde yönetici işlevleri varsa, bunların erişim kontrolleri uygulama
düzeyinde tasarlanmalıdır.

## Güncelleme yaklaşımı

Kaynak kodu GitHub deposunda sürüm kontrolüyle yönetilir.
`Start-AAU.ps1` ilk kurulumda depo arşivini indirir. Bu davranış, kurulu
uygulamanın her çalıştırmada otomatik güncellendiği anlamına gelmez.

Gelecekteki güncelleme mekanizmasında aşağıdaki konuların ele alınması
önerilir:

-   Sürüm numarası ve değişiklik günlüğü.
-   İndirilen arşivin bütünlük kontrolü.
-   Güncelleme öncesi kullanıcı verilerinin korunması.
-   Başarısız güncellemede geri dönüş.
-   İmzalı dağıtım paketleri.

## Test ve doğrulama

Geliştirme sürecinde aşağıdaki kontroller gerçekleştirilmiştir:

-   Uygulama kataloğunun JSON olarak ayrıştırılması.
-   Katalog yöneticisiyle kayıtların yüklenmesi.
-   Katalog istatistiklerinin alınması.
-   Katalog ve kurulum modüllerinin içe aktarılması.
-   WinGet kullanılabilirliğinin kontrol edilmesi.
-   İnternet ve paket kaynağı kontrolleri.
-   Başlangıç betiğinin PowerShell sözdizimi kontrolü.

Test sonuçları belirli bir geliştirme ortamındaki kontrolleri ifade
eder. Farklı Windows sürümlerinde, ağlarda veya paket sürümlerinde
sonuçlar değişebilir.

## Sorun giderme

### WinGet komutu tanınmıyor

``` powershell
winget --version
```

Komut bulunamıyorsa Windows App Installer bileşeninin kurulu ve güncel
olduğunu kontrol edin.

### Katalog yüklenemiyor

`data/apps/apps.json` dosyasının bulunduğunu ve geçerli JSON içerdiğini
kontrol edin:

``` powershell
Get-Content .\data\apps\apps.json -Raw | ConvertFrom-Json
```

### Ana uygulama dosyası bulunamıyor

Aşağıdaki dosyanın mevcut olduğunu doğrulayın:

``` text
src\main.ps1
```

### GitHub arşivi indirilemiyor

İnternet bağlantınızı, depo adresini ve GitHub üzerindeki `master`
dalının erişilebilirliğini kontrol edin.

### Kurulum izni gerekiyor

Bazı uygulamalar yönetici izni isteyebilir. İzin isteminin hangi
uygulamadan geldiğini kontrol edin ve emin olmadığınız işlemleri
onaylamayın.

### Hata devam ediyor

Sorunu yeniden oluşturmak için izlenen adımları, PowerShell hata metnini
ve mümkünse ilgili günlük kaydını paylaşın. Gizli bilgi veya kişisel
veri içeren kayıtları paylaşmadan önce temizleyin.

## Geliştirme ve katkı

Katkıda bulunmak isteyenler aşağıdaki akışı izleyebilir:

1.  Depoyu GitHub üzerinden fork edin.
2.  Fork'unuzu yerel bilgisayarınıza klonlayın.
3.  Yeni bir özellik veya düzeltme dalı oluşturun.
4.  Değişikliklerinizi küçük ve açıklayıcı commit'lerle kaydedin.
5.  İlgili testleri çalıştırın.
6.  GitHub üzerinden Pull Request açın.

Örnek:

``` powershell
git checkout -b feature/yeni-ozellik
git add .
git commit -m "feat: add new feature"
git push origin feature/yeni-ozellik
```

Katkı gönderirken:

-   Mevcut proje düzenini koruyun.
-   Gereksiz dosya veya geçici çıktıları eklemeyin.
-   Gizli bilgileri commit etmeyin.
-   Katalog kayıtlarında doğru paket kimliği ve kaynak kullanın.
-   Test edilmemiş davranışları belgede kesin özellik gibi göstermeyin.
-   Özel yönetim dosyalarını herkese açık dağıtıma eklemeyin.

## Geliştirme yol haritası

Aşağıdaki maddeler olası geliştirme hedefleridir; tamamlanma durumları
sürüme göre ayrıca doğrulanmalıdır.

-   [x] JSON tabanlı merkezi uygulama kataloğu
-   [x] WinGet kaynaklı katalog kayıtları
-   [x] Microsoft Store kaynaklı katalog kayıtları
-   [x] Katalog istatistikleri
-   [x] GitHub üzerinden başlangıç betiği
-   [ ] Bütünlük doğrulamalı güncelleme mekanizması
-   [ ] Sürüm geçmişi ve değişiklik günlüğü
-   [ ] Daha kapsamlı otomatik testler
-   [ ] Gelişmiş kurulum geçmişi
-   [ ] İmzalı dağıtım paketi

## Kaynakça

Teknik bilgi ve başvuru için resmî kaynaklar:

1.  **Microsoft Learn -- Windows Package Manager (WinGet):**\
    https://learn.microsoft.com/windows/package-manager/winget/

2.  **Microsoft Learn -- WinGet install komutu:**\
    https://learn.microsoft.com/windows/package-manager/winget/install

3.  **Microsoft -- WinGet CLI GitHub deposu:**\
    https://github.com/microsoft/winget-cli

4.  **Microsoft Learn -- PowerShell belgeleri:**\
    https://learn.microsoft.com/powershell/

5.  **Git -- Resmî dokümantasyon:**\
    https://git-scm.com/doc

6.  **GitHub Docs:**\
    https://docs.github.com/

Bu bağlantılar kullanılan teknolojilerin resmî dokümantasyonuna
yönlendirir. Üçüncü taraf uygulamaların kendi resmî siteleri ve lisans
koşulları ayrıca geçerlidir.

## Lisans

Depoda geçerli bir `LICENSE` dosyası bulunup bulunmadığını kontrol edin.
Lisans dosyası eklenmeden projenin kullanım, değiştirme ve yeniden
dağıtım koşulları açıkça tanımlanmış sayılmaz.

Bağımlılıkların ve katalogda yer alan üçüncü taraf uygulamaların kendi
lisans koşulları vardır. AAU bu yazılımların lisanslarının yerine
geçmez.

## Geliştirici

**Ali Arda Üstünel**

-   GitHub profili: https://github.com/ardaustunel55
-   Proje deposu: https://github.com/ardaustunel55/AAU_Kurulum_Asistani

------------------------------------------------------------------------

```{=html}
<p align="center">
```
`<strong>`{=html}AAU Kurulum Asistanı`</strong>`{=html}`<br>`{=html}
Windows uygulama kurulum sürecini daha düzenli ve erişilebilir hâle
getirmek için. `<br>`{=html}`<br>`{=html} © 2026 Ali Arda Üstünel
```{=html}
</p>
```
