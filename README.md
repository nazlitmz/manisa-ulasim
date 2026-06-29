# manisa_ulasim

Manisa için toplu taşıma uygulaması — yakındaki durakları bulma, hat/sefer arama, adım adım otobüs navigasyonu, şoföre bildirim, engelli kartı doğrulama ve yapay zeka destekli asistan içerir.

> **Not:** Bu repo, Manisa Büyükşehir Belediyesi'ne ait canlı API anahtarları ve veri kaynaklarını içermez (bkz. [Setup](#setup)). Aşağıdaki ekran görüntüleri uygulamanın gerçek API'lere bağlı haliyle çalışırken alınmıştır; bu repoyu klonlayıp kendi `.env` ve GTFS verileriniz olmadan çalıştırırsanız harita/hat/canlı veri özellikleri çalışmaz.

## Ekran Görüntüleri

| | | |
|---|---|---|
| ![Ana Ekran](manisaulasımscreenshot/mainekran.jpeg) Ana ekran — durak/konum arama, hızlı erişim kısayolları ve popüler yerler | ![Konum İzni](manisaulasımscreenshot/konumkullanımizni.jpeg) Konum izni isteği | ![Yakındaki Duraklar](manisaulasımscreenshot/yakınduraklar.jpeg) Yakındaki duraklar — mesafe filtresiyle liste görünümü |
| ![Yakındaki Duraklar Harita](manisaulasımscreenshot/yakınduraklarmap.jpeg) Yakındaki duraklar — harita görünümü | ![Tüm Hatlar](manisaulasımscreenshot/tumhatlar.jpeg) Tüm hatlar listesi | ![Nereye Gitmek İstiyorsunuz](manisaulasımscreenshot/nereyegitmekistiyorsun.jpeg) Rota planlama — biniş/iniş durağı seçimi ve aktif seferler |
| ![Sefer Sona Erdi](manisaulasımscreenshot/bugunluksefersonaerdi.jpeg) Günün son seferi tamamlanmış uyarısı | ![Navigasyon - Yol Tarifi](manisaulasımscreenshot/navigasyon1.jpeg) Adım adım yol tarifi (yürü → bekle → otobüs → iniş) | ![Navigasyon - Yürüyüş](manisaulasımscreenshot/navigasyon2.jpeg) Canlı navigasyon — durağa yürüyüş aşaması |
| ![Navigasyon - Otobüs](manisaulasımscreenshot/navigasyon4.jpeg) Canlı navigasyon — otobüs yolculuğu aşaması | ![Otobüs Bekleme](manisaulasımscreenshot/otobusbekleyinnav.jpeg) Otobüs bekleme ekranı ve "Bindim!" onayı | ![Bildirim](manisaulasımscreenshot/bildirim.jpeg) Yolculuk başladı bildirimi |
| ![Şoföre Bildir](manisaulasımscreenshot/soforebildir.jpeg) Şoföre Bildir — biniş/iniş durağı ve hat seçimi | ![Engelliler için Şoföre Bildir](manisaulasımscreenshot/engellilericinsoforebildir.jpeg) Engelli kartı doğrulama (NFC veya manuel kart numarası) | ![Sesli Komut](manisaulasımscreenshot/engellilericinseslikomut.jpeg) Erişilebilirlik — sesli komutla arama |
| ![AI Asistan](manisaulasımscreenshot/aiasistan.jpeg) AI Asistan karşılama ekranı | ![AI Asistan Sohbet](manisaulasımscreenshot/aiassistant.jpeg) AI Asistan ile sohbet — hat ve sefer saati sorgulama | ![Günlük Soru Limiti](manisaulasımscreenshot/limit.jpeg) AI Asistan günlük soru limiti |
| ![Ayarlar](manisaulasımscreenshot/settings_screens.jpeg) Ayarlar — erişilebilirlik seçenekleri ve uygulama bilgisi | ![Uygulama İkonu](manisaulasımscreenshot/appicon.jpeg) Uygulama ikonu | |

## Setup

1. Copy `.env.example` to `.env` and fill in your own values:
   - `GROQ_API_KEY` — Groq API key for the AI chat assistant.
   - `MANISA_API_BASE_URL` / `MANISA_BEARER_TOKEN` — terminal messaging API credentials (not included in this repo).
   - `MANISA_VEHICLE_API_BASE_URL` — live vehicle tracking API endpoint (not included in this repo).
   - `GROQ_API_URL`, `OSM_TILE_URL`, `OSRM_BASE_URL`, `GOOGLE_MAPS_DIRECTIONS_URL`, `GOOGLE_MAPS_SEARCH_URL` — public third-party service endpoints (OpenStreetMap, OSRM, Google Maps, Groq); defaults are provided in `.env.example` and can be used as-is.
2. Place your own GTFS feed files under `assets/data/` (Manisa) and `assets/gtfs/cyprus/` — these directories are gitignored since the bundled data belongs to Manisa Büyükşehir Belediyesi and is not redistributed here.
