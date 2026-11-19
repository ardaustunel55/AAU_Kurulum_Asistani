# AAU KURULUM ASİSTANI

**Windows uygulama kurulum deneyimini daha kolay, düzenli ve
erişilebilir hâle getirmek için.**

[![GitHub](https://img.shields.io/badge/GitHub-Proje_Deposu-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/ardaustunel55/AAU_Kurulum_Asistani)
![Windows 10 ve
11](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D4?style=for-the-badge&logo=windows&logoColor=white)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?style=for-the-badge&logo=powershell&logoColor=white)
![WinGet](https://img.shields.io/badge/Package_Manager-WinGet-00A4EF?style=for-the-badge)

[Genel Bakış](#genel-bakış) · [Özellikler](#özellikler) ·
[Kurulum](#kurulum) · [Mimari](#mimari) · [Güvenlik](#güvenlik) ·
[Kaynakça](#kaynakça)

--- \## Genel Bakış AAU Kurulum Asistanı, Windows bilgisayarlarda
kullanılan masaüstü uygulamalarının katalog üzerinden keşfedilmesini ve
kurulum sürecinin tek bir noktadan yönetilmesini amaçlayan bir yazılım
projesidir. Uygulama kataloğu JSON tabanlıdır. Paket kurulumlarında
desteklenen kayıtlara göre Windows Package Manager (WinGet) ve Microsoft
Store kaynaklarından yararlanılır. Proje; başlatma, katalog yönetimi ve
kurulum işlevlerini ayrı dosya ve modüller üzerinden düzenlemeyi
hedefler. \> \*\*Geliştirme notu:\*\* AAU geliştirme aşamasındadır. Bu
README, mevcut dosya yapısı ve gerçekleştirilen kontrollerle desteklenen
bilgileri açıklar. Henüz tamamlanmamış hedefler ayrıca belirtilmiştir.
\## Projenin hedefleri

<table>
<colgroup>
<col style="width: 50%" />
<col style="width: 50%" />
</colgroup>
<tbody>
<tr class="odd">
<td width="50%"><h3 id="merkezi-katalog">Merkezi katalog</h3>
Uygulamaları kategoriler ve paket bilgileriyle tek bir veri kaynağında
toplamak.</td>
<td width="50%"><h3 id="kolay-kurulum">Kolay kurulum</h3>
Desteklenen uygulamaların kurulum sürecini tek bir arayüzden
yönetilebilir kılmak.</td>
</tr>
<tr class="even">
<td><h3 id="modüler-yapı">Modüler yapı</h3>
Katalog, kurulum ve başlangıç işlevlerini ayrı bileşenlerde
düzenlemek.</td>
<td><h3 id="kontrol-edilebilir-süreç">Kontrol edilebilir süreç</h3>
Gerekli araçların, bağlantının ve paket kaynaklarının durumunu kontrol
etmek.</td>
</tr>
</tbody>
</table>

\## Özellikler - \*\*Uygulama kataloğu:\*\* Uygulama kayıtları
\`data/apps/apps.json\` dosyasında tutulur. - \*\*WinGet kaynakları:\*\*
WinGet üzerinden sağlanan paket kayıtlarını destekler. - \*\*Microsoft
Store kayıtları:\*\* Katalogda mağaza kaynaklı uygulamalar da bulunur. -
\*\*Kategorilendirme:\*\* Uygulamaların katalog içinde
gruplandırılmasını sağlar. - \*\*Katalog istatistikleri:\*\* Toplam
kayıt, etkin kayıt, kaynak dağılımı ve kategori sayısı gibi bilgileri
sunar. - \*\*Sistem kontrolleri:\*\* WinGet, internet bağlantısı ve
paket kaynaklarının kullanılabilirliğini denetlemek için kontroller
içerir. - \*\*Normal başlatıcı:\*\* \`AAU.cmd\`, normal kullanıcı
başlatma akışını sağlar. - \*\*İlk kurulum betiği:\*\*
\`Start-AAU.ps1\`, GitHub arşivini indirip projeyi başlatmak üzere
hazırlanmıştır. \## Katalog bilgileri Geliştirme sırasında yapılan bir
katalog doğrulama testinde aşağıdaki sonuçlar alınmıştır: \| Ölçüt \|
Test sonucu \| \|---\|---:\| \| Toplam uygulama kaydı \| 128 \| \| Etkin
kayıt \| 128 \| \| Devre dışı kayıt \| 0 \| \| WinGet kaynağı \| 123 \|
\| Microsoft Store kaynağı \| 5 \| \| Kategori sayısı \| 8 \| \|
Doğrulanmamış kayıt \| 0 \| <sub>Bu tablo test anındaki katalog
çıktısını gösterir. Katalog güncellendikçe sayılar değişebilir;
kayıtların bulunması her uygulamanın her cihazda kurulabileceği anlamına
gelmez.</sub> \## Teknolojiler \| Teknoloji \| Projedeki rol \|
\|---\|---\| \| Windows PowerShell 5.1 \| Betikler, sistem kontrolleri
ve uygulama mantığı \| \| Windows CMD \| Normal başlatıcı \| \| WinGet
\| Desteklenen paketlerin yönetimi \| \| Microsoft Store \| Mağaza
kaynaklı uygulama kayıtları \| \| JSON \| Uygulama kataloğu ve
yapılandırılmış veri \| \| Git \| Sürüm kontrolü \| \| GitHub \| Kaynak
kodu barındırma \| \## Sistem gereksinimleri - Windows 10 (1809 veya
üzeri) ya da Windows 11. - Windows PowerShell 5.1. - WinGet / App
Installer (paket kaynağı gerektiren işlemler için). - İlk indirme ve
çevrimiçi kurulumlar için internet bağlantısı. - Kurulacak programlar
için yeterli disk alanı. - Bazı uygulamalarda yönetici izni. \## Kurulum
\### Hızlı kurulum PowerShell üzerinden aşağıdaki komut kullanılabilir:
\`\`\`powershell irm
https://raw.githubusercontent.com/ardaustunel55/AAU_Kurulum_Asistani/master/Start-AAU.ps1
\| iex \`\`\` \*\*Güvenlik uyarısı:\*\* Bu komut GitHub üzerindeki
betiği indirir ve mevcut PowerShell oturumunda çalıştırır. Uzak
betikleri çalıştırmadan önce kaynak kodunu inceleyin ve yalnızca
güvendiğiniz kaynaklardan çalıştırın. Başlangıç betiğinin tasarlanan
akışı: 1. GitHub'dan \`Start-AAU.ps1\` dosyasını alır. 2. Proje arşivini
indirir ve geçici dizine açar. 3. \`AAU.cmd\` ve \`src/main.ps1\`
dosyalarını kontrol eder. 4. Projeyi
\`%LOCALAPPDATA%\AAU_Kurulum_Asistani\` konumuna yerleştirir. 5. Normal
başlatıcıyı çalıştırır. Mevcut kurulumun otomatik güncellendiği
varsayılmamalıdır; başlangıç betiğinin mevcut davranışı ilk kurulum ve
başlatma akışıdır. \### Manuel kurulum \`\`\`powershell git clone
https://github.com/ardaustunel55/AAU_Kurulum_Asistani.git cd
AAU_Kurulum_Asistani winget --version .\AAU.cmd \`\`\` WinGet komutu
tanınmıyorsa Windows App Installer bileşenini kontrol edin. \## Mimari
ve klasör yapısı \`\`\`text AAU_Kurulum_Asistani/ ├── assets/ \# Görsel
ve arayüz kaynakları ├── config/ \# Yapılandırma dosyaları ├── data/ │
└── apps/ │ └── apps.json \# Uygulama kataloğu ├── docs/ \#
Dokümantasyon ├── logs/ \# Günlük kayıtları ├── modules/ \# İşlevsel
PowerShell modülleri ├── reports/ \# Rapor çıktıları ├── scratch/ \#
Geliştirme çalışma alanı ├── src/ │ └── main.ps1 \# Ana uygulama giriş
noktası ├── tests/ \# Test dosyaları ├── AAU.cmd \# Normal kullanıcı
başlatıcısı ├── Start-AAU.ps1 \# İndirme ve başlatma betiği └──
README.md \`\`\` \### Çalışma akışı 1. \*\*Başlatma:\*\* \`AAU.cmd\`,
gerekli dosyaları kontrol ederek ana PowerShell betiğini çalıştırır. 2.
\*\*Ana giriş:\*\* \`src/main.ps1\`, uygulamanın giriş noktasıdır. 3.
\*\*Katalog:\*\* Katalog modülü JSON kayıtlarını yükler. 4.
\*\*Kurulum:\*\* Kurulum modülü, katalogdaki kaynak ve paket bilgilerine
göre desteklenen paket yöneticisi işlemlerini yürütür. 5.
\*\*Kontroller:\*\* Sistem ve kaynak kontrolleri, işlem öncesi
kullanılabilirliği değerlendirmeye yardımcı olur. \## Güvenlik - Uzak
betikleri çalıştırmadan önce içeriğini inceleyin. - Paket kimliğini ve
kaynağını doğrulayın. - Yönetici iznini yalnızca gerekli ve güvenilir
işlemler için verin. - Parola, API anahtarı, erişim belirteci veya
kişisel verileri Git deposuna eklemeyin. - Üçüncü taraf yazılımların
lisans ve gizlilik koşullarını ayrıca inceleyin. \### Yönetici araçları
Bu herkese açık depoda normal kullanıcı başlatıcısı \`AAU.cmd\`
belgelenir. Geliştiriciye özel yönetim araçları genel kullanıcı
kurulumunun parçası değildir. Bir yönetici başlatıcısını Git takibinden
çıkarmak, onun çağırdığı yönetim kodlarını otomatik olarak gizlemez.
Özel kalması gereken kaynak kodlar ayrı ve erişimi kısıtlanmış bir yerde
tutulmalıdır. \## Güncelleme yaklaşımı Kaynak kodu GitHub üzerinde sürüm
kontrolüyle yönetilir. \`Start-AAU.ps1\` proje arşivini indirerek ilk
kurulum akışını yürütür. Bu, kurulu uygulamanın her başlatmada otomatik
olarak güncellendiği anlamına gelmez. Gelecekteki güncelleme mekanizması
için sürüm numarası, arşiv bütünlüğü kontrolü, kullanıcı verilerinin
korunması ve başarısız güncellemeden geri dönüş gibi konular önemlidir.
\## Test ve doğrulama Geliştirme sürecinde gerçekleştirilen
kontroller: - JSON kataloğunun ayrıştırılması. - Katalog kayıtlarının
yüklenmesi. - Katalog istatistiklerinin alınması. - Katalog ve kurulum
modüllerinin içe aktarılması. - WinGet kullanılabilirliği, internet ve
paket kaynaklarının kontrolü. - Başlangıç betiğinin PowerShell sözdizimi
kontrolü. Bu kontroller belirli bir geliştirme ortamındaki sonuçları
ifade eder; her cihaz ve paket için aynı sonucu garanti etmez. \## Sorun
giderme \*\*WinGet bulunamıyor\*\* \`\`\`powershell winget --version
\`\`\` Komut tanınmıyorsa App Installer bileşenini kontrol edin.
\*\*Katalog yüklenemiyor\*\* \`\`\`powershell Get-Content
.\data\apps\apps.json -Raw \| ConvertFrom-Json \`\`\` \*\*Ana dosya
eksik\*\* \`src\main.ps1\` dosyasının proje klasöründe bulunduğunu
doğrulayın. \*\*GitHub arşivi indirilemiyor\*\* İnternet bağlantısını,
depo adresini ve \`master\` dalının erişilebilirliğini kontrol edin.
Sorun devam ederse hata mesajını ve yeniden oluşturma adımlarını
paylaşın. Günlük kayıtlarında kişisel veya gizli bilgi bulunmadığından
emin olun. \## Geliştirme ve katkı Katkı sunmak isteyenler depoyu fork
edip kendi dallarında değişiklik yapabilir. \`\`\`powershell git
checkout -b feature/yeni-ozellik git add . git commit -m "feat: add new
feature" git push origin feature/yeni-ozellik \`\`\` Ardından GitHub
üzerinden Pull Request açılabilir. Katkılarda mevcut klasör düzenini
koruyun, geçici dosyaları eklemeyin, gizli bilgileri commit etmeyin ve
test edilmemiş özellikleri tamamlanmış gibi tanımlamayın. \## Yol
haritası Aşağıdaki maddeler geliştirme hedefleridir; tamamlanma
durumları her sürümde ayrıca doğrulanmalıdır. - \[x\] JSON tabanlı
merkezi uygulama kataloğu - \[x\] WinGet ve Microsoft Store kaynak
kayıtları - \[x\] Katalog istatistikleri - \[x\] GitHub üzerinden
başlangıç betiği - \[ \] Bütünlük doğrulamalı güncelleme mekanizması -
\[ \] Sürüm geçmişi ve değişiklik günlüğü - \[ \] Daha kapsamlı otomatik
testler - \[ \] Gelişmiş kurulum geçmişi - \[ \] İmzalı dağıtım paketi
\## Kaynakça - \[Microsoft Learn – Windows Package Manager
(WinGet)\](https://learn.microsoft.com/windows/package-manager/winget/) -
\[Microsoft Learn – WinGet install
komutu\](https://learn.microsoft.com/windows/package-manager/winget/install) -
\[Microsoft – WinGet CLI kaynak
kodu\](https://github.com/microsoft/winget-cli) - \[Microsoft Learn –
PowerShell\](https://learn.microsoft.com/powershell/) - \[Git – Resmî
dokümantasyon\](https://git-scm.com/doc) - \[GitHub
Docs\](https://docs.github.com/) Bu bağlantılar ilgili teknolojilerin
resmî belgelerine yönlendirir. Katalogdaki üçüncü taraf uygulamaların
lisansları kendi geliştiricilerine aittir. \## Lisans Depoda geçerli bir
\`LICENSE\` dosyası bulunup bulunmadığını kontrol edin. Lisans
eklenmeden kullanım, değiştirme ve yeniden dağıtım koşulları açıkça
tanımlanmış sayılmaz. Üçüncü taraf uygulamalar kendi lisans koşullarına
tabidir. \## Geliştirici \*\*Ali Arda Üstünel\*\* - GitHub:
\[@ardaustunel55\](https://github.com/ardaustunel55) - Proje: \[AAU
Kurulum
Asistanı\](https://github.com/ardaustunel55/AAU_Kurulum_Asistani)

**AAU Kurulum Asistanı**  
Windows uygulama kurulum sürecini daha düzenli ve erişilebilir hâle
getirmek için.  
  
© 2026 Ali Arda Üstünel
