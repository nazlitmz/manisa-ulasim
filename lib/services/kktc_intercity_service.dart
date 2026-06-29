/// KKTC Şehirlerarası Otobüs Servisi
/// Kaynak: İtimat, Kombos, KIBHAS (kibhas.org)
/// Saatler ve duraklar 2024-2025 resmi kaynaklardan doğrulanmıştır.

// ══════════════════════════════════════════════════════════════════
// KIBHAS Durak modeli
// ══════════════════════════════════════════════════════════════════
class KktcBusStop {
  final String stopId;
  final String stopName;
  final double lat;
  final double lon;

  const KktcBusStop({
    required this.stopId,
    required this.stopName,
    required this.lat,
    required this.lon,
  });
}

// ══════════════════════════════════════════════════════════════════
// KktcBusLine modeli
// ══════════════════════════════════════════════════════════════════
class KktcBusLine {
  final String id;
  final String company;
  final String from;
  final String to;
  final String fromCity;
  final String toCity;
  final double fromLat;
  final double fromLon;
  final double toLat;
  final double toLon;
  final List<String> departureTimes;
  final String frequency;
  final int durationMinutes;
  final String notes;
  final String phone;
  final List<KktcBusStop> stops;

  const KktcBusLine({
    required this.id,
    required this.company,
    required this.from,
    required this.to,
    required this.fromCity,
    required this.toCity,
    required this.fromLat,
    required this.fromLon,
    required this.toLat,
    required this.toLon,
    required this.departureTimes,
    required this.frequency,
    required this.durationMinutes,
    this.notes = '',
    this.phone = '',
    this.stops = const [],
  });

  bool get isIntercity => fromCity != toCity;
}

// ══════════════════════════════════════════════════════════════════
// 1. MAĞUSA / İSKELE ↔ ERCAN — Duraklar
// ══════════════════════════════════════════════════════════════════

const _magusaErcanStops = <KktcBusStop>[
  KktcBusStop(
      stopId: 'kibhas_stop_anit_cemberi',
      stopName: 'Anıt Çemberi (Mağusa Terminal)',
      lat: 35.1228,
      lon: 33.9408),
  KktcBusStop(
      stopId: 'kibhas_stop_kibhas_mag',
      stopName: 'Kıbhas Terminal (Mağusa)',
      lat: 35.1250,
      lon: 33.9380),
  KktcBusStop(
      stopId: 'kibhas_stop_ordu_evi',
      stopName: 'Ordu Evi',
      lat: 35.1270,
      lon: 33.9350),
  KktcBusStop(
      stopId: 'kibhas_stop_kaliland',
      stopName: 'Kaliland',
      lat: 35.1350,
      lon: 33.9200),
  KktcBusStop(
      stopId: 'kibhas_stop_dau_ofis',
      stopName: 'DAÜ Ofis (EMU)',
      lat: 35.1467,
      lon: 33.9008),
  KktcBusStop(
      stopId: 'kibhas_stop_dau_guney',
      stopName: 'DAÜ Güney Kampüs Üst Geçit',
      lat: 35.1480,
      lon: 33.8980),
  KktcBusStop(
      stopId: 'kibhas_stop_sabanci',
      stopName: 'Sabancı',
      lat: 35.1560,
      lon: 33.8850),
  KktcBusStop(
      stopId: 'kibhas_stop_arkin_iskele',
      stopName: 'Arkın Hotel İskele',
      lat: 35.2800,
      lon: 33.8900),
  KktcBusStop(
      stopId: 'kibhas_stop_begonvilla',
      stopName: 'Begonvilla Court İskele',
      lat: 35.2820,
      lon: 33.8920),
  KktcBusStop(
      stopId: 'kibhas_stop_royal_sun',
      stopName: 'Royal Sun Elite İskele',
      lat: 35.2850,
      lon: 33.8950),
  KktcBusStop(
      stopId: 'kibhas_stop_grand_sapphire',
      stopName: 'Grand Sapphire Resort İskele',
      lat: 35.2870,
      lon: 33.8970),
  KktcBusStop(
      stopId: 'kibhas_stop_caesar_resort',
      stopName: 'Caesar Resort B Kapısı İskele',
      lat: 35.2890,
      lon: 33.8990),
  KktcBusStop(
      stopId: 'kibhas_stop_zagidas',
      stopName: 'Zagidas Pembe Cafe İskele',
      lat: 35.2910,
      lon: 33.9010),
  KktcBusStop(
      stopId: 'kibhas_stop_doktorlar',
      stopName: 'Doktorlar Sitesi Süpermarket İskele',
      lat: 35.2930,
      lon: 33.9030),
  KktcBusStop(
      stopId: 'kibhas_stop_narin',
      stopName: 'Narin Pastanesi İskele',
      lat: 35.2950,
      lon: 33.9050),
  KktcBusStop(
      stopId: 'kibhas_stop_courtyard',
      stopName: 'Court Yard Long Beach İskele',
      lat: 35.2970,
      lon: 33.9070),
  KktcBusStop(
      stopId: 'kibhas_stop_unimar_iskele',
      stopName: 'Ünimar İskele',
      lat: 35.2990,
      lon: 33.9090),
  KktcBusStop(
      stopId: 'kibhas_stop_salamis',
      stopName: 'Salamis Hotel İskele',
      lat: 35.1600,
      lon: 33.9200),
  KktcBusStop(
      stopId: 'kibhas_stop_yeni_bogazici',
      stopName: 'Yeni Boğaziçi',
      lat: 35.3000,
      lon: 33.9100),
];

const _ercanMagusaStops = <KktcBusStop>[
  KktcBusStop(
      stopId: 'kibhas_stop_ercan',
      stopName: 'Ercan Havalimanı',
      lat: 35.1547,
      lon: 33.4961),
  KktcBusStop(
      stopId: 'kibhas_stop_arkin_iskele',
      stopName: 'Arkın Hotel İskele',
      lat: 35.2800,
      lon: 33.8900),
  KktcBusStop(
      stopId: 'kibhas_stop_begonvilla',
      stopName: 'Begonvilla Court İskele',
      lat: 35.2820,
      lon: 33.8920),
  KktcBusStop(
      stopId: 'kibhas_stop_caesar_resort',
      stopName: 'Caesar Resort B Kapısı İskele',
      lat: 35.2890,
      lon: 33.8990),
  KktcBusStop(
      stopId: 'kibhas_stop_courtyard',
      stopName: 'Court Yard Long Beach İskele',
      lat: 35.2970,
      lon: 33.9070),
  KktcBusStop(
      stopId: 'kibhas_stop_dau_guney',
      stopName: 'DAÜ Güney Kampüs Üst Geçit',
      lat: 35.1480,
      lon: 33.8980),
  KktcBusStop(
      stopId: 'kibhas_stop_dau_ofis',
      stopName: 'DAÜ Ofis (EMU)',
      lat: 35.1467,
      lon: 33.9008),
  KktcBusStop(
      stopId: 'kibhas_stop_doktorlar',
      stopName: 'Doktorlar Sitesi Süpermarket İskele',
      lat: 35.2930,
      lon: 33.9030),
  KktcBusStop(
      stopId: 'kibhas_stop_grand_sapphire',
      stopName: 'Grand Sapphire Resort İskele',
      lat: 35.2870,
      lon: 33.8970),
  KktcBusStop(
      stopId: 'kibhas_stop_kale_kapisi',
      stopName: 'Kale Kapısı Durağı',
      lat: 35.1230,
      lon: 33.9420),
  KktcBusStop(
      stopId: 'kibhas_stop_kaliland',
      stopName: 'Kaliland',
      lat: 35.1350,
      lon: 33.9200),
  KktcBusStop(
      stopId: 'kibhas_stop_long_beach',
      stopName: 'Long Beach İskele',
      lat: 35.2960,
      lon: 33.9060),
  KktcBusStop(
      stopId: 'kibhas_stop_anit_cemberi',
      stopName: 'Mağusa Terminal (Anıt Çemberi)',
      lat: 35.1228,
      lon: 33.9408),
  KktcBusStop(
      stopId: 'kibhas_stop_narin',
      stopName: 'Narin Pastanesi İskele',
      lat: 35.2950,
      lon: 33.9050),
  KktcBusStop(
      stopId: 'kibhas_stop_ordu_evi',
      stopName: 'Ordu Evi',
      lat: 35.1270,
      lon: 33.9350),
  KktcBusStop(
      stopId: 'kibhas_stop_royal_sun',
      stopName: 'Royal Sun Elite İskele',
      lat: 35.2850,
      lon: 33.8950),
  KktcBusStop(
      stopId: 'kibhas_stop_sabanci',
      stopName: 'Sabancı',
      lat: 35.1560,
      lon: 33.8850),
  KktcBusStop(
      stopId: 'kibhas_stop_salamis',
      stopName: 'Salamis Hotel İskele',
      lat: 35.1600,
      lon: 33.9200),
  KktcBusStop(
      stopId: 'kibhas_stop_unimar_iskele',
      stopName: 'Ünimar İskele',
      lat: 35.2990,
      lon: 33.9090),
  KktcBusStop(
      stopId: 'kibhas_stop_yeni_bogazici_dur',
      stopName: 'Yeni Boğaziçi Durağı',
      lat: 35.3000,
      lon: 33.9100),
  KktcBusStop(
      stopId: 'kibhas_stop_zagidas',
      stopName: 'Zagidas Pembe Cafe İskele',
      lat: 35.2910,
      lon: 33.9010),
];

// ══════════════════════════════════════════════════════════════════
// 2. LEFKOŞA ↔ ERCAN — Duraklar
// ══════════════════════════════════════════════════════════════════

const _lefkosaErcanStops = <KktcBusStop>[
  KktcBusStop(
      stopId: 'kibhas_stop_kizilbas',
      stopName: 'Kızılbaş Parkı',
      lat: 35.1731,
      lon: 33.3595),
  KktcBusStop(
      stopId: 'kibhas_stop_metropol',
      stopName: 'Metropol',
      lat: 35.1740,
      lon: 33.3610),
  KktcBusStop(
      stopId: 'kibhas_stop_campus_cyprus',
      stopName: 'Campus Cyprus',
      lat: 35.1750,
      lon: 33.3630),
  KktcBusStop(
      stopId: 'kibhas_stop_ydu',
      stopName: 'Yakın Doğu Üniversitesi',
      lat: 35.1760,
      lon: 33.3650),
  KktcBusStop(
      stopId: 'kibhas_stop_dormi',
      stopName: 'Dormi Öğrenci Yurdu',
      lat: 35.1765,
      lon: 33.3660),
  KktcBusStop(
      stopId: 'kibhas_stop_fuar',
      stopName: 'Fuar Durağı',
      lat: 35.1770,
      lon: 33.3670),
  KktcBusStop(
      stopId: 'kibhas_stop_devlet_hastanesi',
      stopName: 'Devlet Hastanesi',
      lat: 35.1690,
      lon: 33.3550),
  KktcBusStop(
      stopId: 'kibhas_stop_kiler3',
      stopName: 'Kiler 3 Gönyeli',
      lat: 35.1780,
      lon: 33.3580),
  KktcBusStop(
      stopId: 'kibhas_stop_irmar2',
      stopName: 'İrmar 2 Gönyeli Belediyesi Karşısı',
      lat: 35.1785,
      lon: 33.3575),
  KktcBusStop(
      stopId: 'kibhas_stop_tepehome',
      stopName: 'Tepehome',
      lat: 35.1790,
      lon: 33.3570),
  KktcBusStop(
      stopId: 'kibhas_stop_can_sigorta',
      stopName: 'Can Sigorta',
      lat: 35.1795,
      lon: 33.3565),
  KktcBusStop(
      stopId: 'kibhas_stop_ortakoy',
      stopName: 'Ortaköy China Bazaar',
      lat: 35.1800,
      lon: 33.3560),
  KktcBusStop(
      stopId: 'kibhas_stop_saglik_bak',
      stopName: 'Sağlık Bakanlığı',
      lat: 35.1748,
      lon: 33.3630),
  KktcBusStop(
      stopId: 'kibhas_stop_merit_lefkosa',
      stopName: 'Merit Lefkoşa',
      lat: 35.1752,
      lon: 33.3640),
  KktcBusStop(
      stopId: 'kibhas_stop_girne_kapisi',
      stopName: 'Girne Kapısı',
      lat: 35.1775,
      lon: 33.3633),
  KktcBusStop(
      stopId: 'kibhas_stop_kibhas_lef',
      stopName: 'Kıbhas Terminal (Lefkoşa)',
      lat: 35.1748,
      lon: 33.3650),
  KktcBusStop(
      stopId: 'kibhas_stop_eski_kaymakli',
      stopName: 'Eski Kaymaklı Mezarlığı (Macro)',
      lat: 35.1810,
      lon: 33.3540),
  KktcBusStop(
      stopId: 'kibhas_stop_cangar',
      stopName: 'Çangar',
      lat: 35.1815,
      lon: 33.3530),
  KktcBusStop(
      stopId: 'kibhas_stop_creditwest',
      stopName: 'Creditwest (Honda)',
      lat: 35.1755,
      lon: 33.3820),
  KktcBusStop(
      stopId: 'kibhas_stop_cadde_mutfak',
      stopName: 'Cadde Mutfak',
      lat: 35.1758,
      lon: 33.3830),
  KktcBusStop(
      stopId: 'kibhas_stop_uku_molto',
      stopName: 'UKÜ Molto',
      lat: 35.1762,
      lon: 33.3840),
  KktcBusStop(
      stopId: 'kibhas_stop_degirmenlik',
      stopName: 'Değirmenlik',
      lat: 35.1820,
      lon: 33.4200),
  KktcBusStop(
      stopId: 'kibhas_stop_erulku',
      stopName: 'Erülkü Süpermarket',
      lat: 35.1825,
      lon: 33.4300),
  KktcBusStop(
      stopId: 'kibhas_stop_ercan',
      stopName: 'Ercan Havalimanı',
      lat: 35.1547,
      lon: 33.4961),
];

// Ercan→Lefkoşa: Değirmenlik ve Erülkü yok
const _ercanLefkosaStops = <KktcBusStop>[
  KktcBusStop(
      stopId: 'kibhas_stop_ercan',
      stopName: 'Ercan Havalimanı',
      lat: 35.1547,
      lon: 33.4961),
  KktcBusStop(
      stopId: 'kibhas_stop_kizilbas',
      stopName: 'Kızılbaş Parkı',
      lat: 35.1731,
      lon: 33.3595),
  KktcBusStop(
      stopId: 'kibhas_stop_metropol',
      stopName: 'Metropol',
      lat: 35.1740,
      lon: 33.3610),
  KktcBusStop(
      stopId: 'kibhas_stop_campus_cyprus',
      stopName: 'Campus Cyprus',
      lat: 35.1750,
      lon: 33.3630),
  KktcBusStop(
      stopId: 'kibhas_stop_ydu',
      stopName: 'Yakın Doğu Üniversitesi',
      lat: 35.1760,
      lon: 33.3650),
  KktcBusStop(
      stopId: 'kibhas_stop_dormi',
      stopName: 'Dormi Öğrenci Yurdu',
      lat: 35.1765,
      lon: 33.3660),
  KktcBusStop(
      stopId: 'kibhas_stop_fuar',
      stopName: 'Fuar Durağı',
      lat: 35.1770,
      lon: 33.3670),
  KktcBusStop(
      stopId: 'kibhas_stop_devlet_hastanesi',
      stopName: 'Devlet Hastanesi',
      lat: 35.1690,
      lon: 33.3550),
  KktcBusStop(
      stopId: 'kibhas_stop_kiler3',
      stopName: 'Kiler 3 Gönyeli',
      lat: 35.1780,
      lon: 33.3580),
  KktcBusStop(
      stopId: 'kibhas_stop_irmar2',
      stopName: 'İrmar 2 Gönyeli Belediyesi Karşısı',
      lat: 35.1785,
      lon: 33.3575),
  KktcBusStop(
      stopId: 'kibhas_stop_tepehome',
      stopName: 'Tepehome',
      lat: 35.1790,
      lon: 33.3570),
  KktcBusStop(
      stopId: 'kibhas_stop_can_sigorta',
      stopName: 'Can Sigorta',
      lat: 35.1795,
      lon: 33.3565),
  KktcBusStop(
      stopId: 'kibhas_stop_ortakoy',
      stopName: 'Ortaköy China Bazaar',
      lat: 35.1800,
      lon: 33.3560),
  KktcBusStop(
      stopId: 'kibhas_stop_saglik_bak',
      stopName: 'Sağlık Bakanlığı',
      lat: 35.1748,
      lon: 33.3630),
  KktcBusStop(
      stopId: 'kibhas_stop_merit_lefkosa',
      stopName: 'Merit Lefkoşa',
      lat: 35.1752,
      lon: 33.3640),
  KktcBusStop(
      stopId: 'kibhas_stop_girne_kapisi',
      stopName: 'Girne Kapısı',
      lat: 35.1775,
      lon: 33.3633),
  KktcBusStop(
      stopId: 'kibhas_stop_kibhas_lef',
      stopName: 'Kıbhas Terminal (Lefkoşa)',
      lat: 35.1748,
      lon: 33.3650),
  KktcBusStop(
      stopId: 'kibhas_stop_eski_kaymakli',
      stopName: 'Eski Kaymaklı Mezarlığı (Macro)',
      lat: 35.1810,
      lon: 33.3540),
  KktcBusStop(
      stopId: 'kibhas_stop_cangar',
      stopName: 'Çangar',
      lat: 35.1815,
      lon: 33.3530),
  KktcBusStop(
      stopId: 'kibhas_stop_creditwest',
      stopName: 'Creditwest (Honda)',
      lat: 35.1755,
      lon: 33.3820),
  KktcBusStop(
      stopId: 'kibhas_stop_cadde_mutfak',
      stopName: 'Cadde Mutfak',
      lat: 35.1758,
      lon: 33.3830),
  KktcBusStop(
      stopId: 'kibhas_stop_uku_molto',
      stopName: 'UKÜ Molto',
      lat: 35.1762,
      lon: 33.3840),
];

// ══════════════════════════════════════════════════════════════════
// 3. GİRNE ↔ ERCAN — Duraklar
// ══════════════════════════════════════════════════════════════════

const _girneErcanStops = <KktcBusStop>[
  KktcBusStop(
      stopId: 'kibhas_stop_colony',
      stopName: 'Kıbhas Merkez (Colony Hotel)',
      lat: 35.3414,
      lon: 33.3193),
  KktcBusStop(
      stopId: 'kibhas_stop_gau',
      stopName: 'Girne Amerikan Üniversitesi',
      lat: 35.3345,
      lon: 33.2960),
  KktcBusStop(
      stopId: 'kibhas_stop_karmi',
      stopName: 'Karmi Öğrenci Yurdu',
      lat: 35.3360,
      lon: 33.2980),
  KktcBusStop(
      stopId: 'kibhas_stop_hale_sultan',
      stopName: 'Hale Sultan Öğrenci Yurdu',
      lat: 35.3370,
      lon: 33.3000),
  KktcBusStop(
      stopId: 'kibhas_stop_ozerin',
      stopName: 'Özerin Öğrenci Yurdu',
      lat: 35.3380,
      lon: 33.3020),
  KktcBusStop(
      stopId: 'kibhas_stop_sokmar',
      stopName: 'Şokmar',
      lat: 35.3385,
      lon: 33.3050),
  KktcBusStop(
      stopId: 'kibhas_stop_baris_parki',
      stopName: 'Barış Parkı Durağı',
      lat: 35.3390,
      lon: 33.3070),
  KktcBusStop(
      stopId: 'kibhas_stop_bestmar',
      stopName: 'Bestmar Durağı',
      lat: 35.3395,
      lon: 33.3090),
  KktcBusStop(
      stopId: 'kibhas_stop_pascucci',
      stopName: 'Cafe Pascucci',
      lat: 35.3400,
      lon: 33.3110),
  KktcBusStop(
      stopId: 'kibhas_stop_barbaroslar',
      stopName: 'Barbaroslar Market',
      lat: 35.3402,
      lon: 33.3130),
  KktcBusStop(
      stopId: 'kibhas_stop_ogretmenevi',
      stopName: 'Girne Öğretmenevi',
      lat: 35.3405,
      lon: 33.3150),
  KktcBusStop(
      stopId: 'kibhas_stop_pia_bella',
      stopName: 'Pia Bella Hotel Karşısı',
      lat: 35.3408,
      lon: 33.3170),
  KktcBusStop(
      stopId: 'kibhas_stop_oscar_hotel',
      stopName: 'Oscar Hotel',
      lat: 35.3410,
      lon: 33.3175),
  KktcBusStop(
      stopId: 'kibhas_stop_lords_palace',
      stopName: 'Lords Palace Hotel',
      lat: 35.3412,
      lon: 33.3180),
  KktcBusStop(
      stopId: 'kibhas_stop_molto_karakum',
      stopName: 'Molto Market Karakum',
      lat: 35.3200,
      lon: 33.3300),
  KktcBusStop(
      stopId: 'kibhas_stop_buyuk_anadolu',
      stopName: 'Büyük Anadolu Hotel',
      lat: 35.3100,
      lon: 33.3350),
  KktcBusStop(
      stopId: 'kibhas_stop_lefkosa_cemberi',
      stopName: 'Lefkoşa Çemberi',
      lat: 35.2500,
      lon: 33.3500),
  KktcBusStop(
      stopId: 'kibhas_stop_bogaz',
      stopName: 'Boğaz Durağı',
      lat: 35.2200,
      lon: 33.3600),
  KktcBusStop(
      stopId: 'kibhas_stop_uku_yurtlar',
      stopName: 'UKÜ Yurtlar Kahraman Market',
      lat: 35.1762,
      lon: 33.3840),
  KktcBusStop(
      stopId: 'kibhas_stop_ercan',
      stopName: 'Ercan Havalimanı',
      lat: 35.1547,
      lon: 33.4961),
];

const _ercanGirneStops = <KktcBusStop>[
  KktcBusStop(
      stopId: 'kibhas_stop_ercan',
      stopName: 'Ercan Havalimanı',
      lat: 35.1547,
      lon: 33.4961),
  KktcBusStop(
      stopId: 'kibhas_stop_life_hotel',
      stopName: 'Life Hotel (Akpınar Çemberi)',
      lat: 35.1600,
      lon: 33.4800),
  KktcBusStop(
      stopId: 'kibhas_stop_nusmar',
      stopName: 'Nusmar',
      lat: 35.3400,
      lon: 33.3130),
  KktcBusStop(
      stopId: 'kibhas_stop_pia_bella',
      stopName: 'Pia Bella Hotel',
      lat: 35.3408,
      lon: 33.3170),
  KktcBusStop(
      stopId: 'kibhas_stop_colony',
      stopName: 'Kıbhas Merkez (Colony Hotel)',
      lat: 35.3414,
      lon: 33.3193),
  KktcBusStop(
      stopId: 'kibhas_stop_gau',
      stopName: 'Girne Amerikan Üniversitesi',
      lat: 35.3345,
      lon: 33.2960),
  KktcBusStop(
      stopId: 'kibhas_stop_karmi',
      stopName: 'Karmi Öğrenci Yurdu',
      lat: 35.3360,
      lon: 33.2980),
  KktcBusStop(
      stopId: 'kibhas_stop_hale_sultan',
      stopName: 'Hale Sultan Öğrenci Yurdu',
      lat: 35.3370,
      lon: 33.3000),
  KktcBusStop(
      stopId: 'kibhas_stop_ozerin',
      stopName: 'Özerin Öğrenci Yurdu',
      lat: 35.3380,
      lon: 33.3020),
  KktcBusStop(
      stopId: 'kibhas_stop_sokmar',
      stopName: 'Şokmar',
      lat: 35.3385,
      lon: 33.3050),
  KktcBusStop(
      stopId: 'kibhas_stop_baris_parki',
      stopName: 'Barış Parkı Durağı',
      lat: 35.3390,
      lon: 33.3070),
  KktcBusStop(
      stopId: 'kibhas_stop_bestmar',
      stopName: 'Bestmar Durağı',
      lat: 35.3395,
      lon: 33.3090),
  KktcBusStop(
      stopId: 'kibhas_stop_pascucci',
      stopName: 'Cafe Pascucci',
      lat: 35.3400,
      lon: 33.3110),
  KktcBusStop(
      stopId: 'kibhas_stop_barbaroslar',
      stopName: 'Barbaroslar Market',
      lat: 35.3402,
      lon: 33.3130),
  KktcBusStop(
      stopId: 'kibhas_stop_ogretmenevi',
      stopName: 'Girne Öğretmenevi',
      lat: 35.3405,
      lon: 33.3150),
  KktcBusStop(
      stopId: 'kibhas_stop_oscar_hotel',
      stopName: 'Oscar Hotel',
      lat: 35.3410,
      lon: 33.3175),
  KktcBusStop(
      stopId: 'kibhas_stop_lords_palace',
      stopName: 'Lords Palace Hotel',
      lat: 35.3412,
      lon: 33.3180),
  KktcBusStop(
      stopId: 'kibhas_stop_molto_karakum',
      stopName: 'Molto Market Karakum',
      lat: 35.3200,
      lon: 33.3300),
  KktcBusStop(
      stopId: 'kibhas_stop_buyuk_anadolu',
      stopName: 'Büyük Anadolu Hotel',
      lat: 35.3100,
      lon: 33.3350),
  KktcBusStop(
      stopId: 'kibhas_stop_lefkosa_cemberi',
      stopName: 'Lefkoşa Çemberi',
      lat: 35.2500,
      lon: 33.3500),
  KktcBusStop(
      stopId: 'kibhas_stop_bogaz',
      stopName: 'Boğaz Durağı',
      lat: 35.2200,
      lon: 33.3600),
  KktcBusStop(
      stopId: 'kibhas_stop_uku_yurtlar',
      stopName: 'UKÜ Yurtlar Kahraman Market',
      lat: 35.1762,
      lon: 33.3840),
];

// ══════════════════════════════════════════════════════════════════
// 4. GÜZELYURT / LEFKE ↔ ERCAN — Duraklar
// ══════════════════════════════════════════════════════════════════

const _lefkeGuzelyurtErcanStops = <KktcBusStop>[
  KktcBusStop(
      stopId: 'kibhas_stop_lefke_karadag',
      stopName: 'Lefke Karadağ',
      lat: 35.1167,
      lon: 32.8500),
  KktcBusStop(
      stopId: 'kibhas_stop_akva_polis',
      stopName: 'Akva Polis Karakolu',
      lat: 35.1170,
      lon: 32.8520),
  KktcBusStop(
      stopId: 'kibhas_stop_portakal',
      stopName: 'Lefke Portakal Çemberi',
      lat: 35.1175,
      lon: 32.8540),
  KktcBusStop(
      stopId: 'kibhas_stop_lefke_4tabur',
      stopName: 'Lefke 4. Tabur',
      lat: 35.1180,
      lon: 32.8560),
  KktcBusStop(
      stopId: 'kibhas_stop_tufekci',
      stopName: 'Tüfekçi Evleri',
      lat: 35.1185,
      lon: 32.8580),
  KktcBusStop(
      stopId: 'kibhas_stop_gemikonagi',
      stopName: 'Gemikonağı Sos. Konutları',
      lat: 35.1190,
      lon: 32.8600),
  KktcBusStop(
      stopId: 'kibhas_stop_lau_orta',
      stopName: 'LAÜ Orta Cafe',
      lat: 35.1195,
      lon: 32.8620),
  KktcBusStop(
      stopId: 'kibhas_stop_dk_corner',
      stopName: 'D.K. Corner Cafe',
      lat: 35.1200,
      lon: 32.8640),
  KktcBusStop(
      stopId: 'kibhas_stop_doyum_market',
      stopName: 'Doyum Market',
      lat: 35.1205,
      lon: 32.8660),
  KktcBusStop(
      stopId: 'kibhas_stop_arap_petrol',
      stopName: 'Arap Petrol',
      lat: 35.1210,
      lon: 32.8680),
  KktcBusStop(
      stopId: 'kibhas_stop_cengiz_topel',
      stopName: 'Cengiz Topel Hastanesi',
      lat: 35.1700,
      lon: 32.9950),
  KktcBusStop(
      stopId: 'kibhas_stop_yesilyurt_kantin',
      stopName: 'Yeşilyurt Askeri Kantin',
      lat: 35.1710,
      lon: 32.9960),
  KktcBusStop(
      stopId: 'kibhas_stop_yesilyurt_seker',
      stopName: 'Yeşilyurt Şeker Sok.',
      lat: 35.1715,
      lon: 32.9965),
  KktcBusStop(
      stopId: 'kibhas_stop_green_house',
      stopName: 'Green House',
      lat: 35.1720,
      lon: 32.9970),
  KktcBusStop(
      stopId: 'kibhas_stop_doganci',
      stopName: 'Doğancı Argonya',
      lat: 35.1900,
      lon: 33.0000),
  KktcBusStop(
      stopId: 'kibhas_stop_gaziveren',
      stopName: 'Gaziveren Okulu',
      lat: 35.1950,
      lon: 33.0100),
  KktcBusStop(
      stopId: 'kibhas_stop_aydinköy',
      stopName: 'Aydınköy',
      lat: 35.2000,
      lon: 32.9980),
  KktcBusStop(
      stopId: 'kibhas_stop_guzelyurt_term',
      stopName: 'Güzelyurt Terminal',
      lat: 35.2009,
      lon: 32.9970),
  KktcBusStop(
      stopId: 'kibhas_stop_gepaz',
      stopName: 'Gepaz Çemberi',
      lat: 35.2020,
      lon: 33.0050),
  KktcBusStop(
      stopId: 'kibhas_stop_odtu_2yurt',
      stopName: 'ODTÜ 2. Yurt',
      lat: 35.1820,
      lon: 33.3600),
  KktcBusStop(
      stopId: 'kibhas_stop_odtu_misafir',
      stopName: 'ODTÜ Misafirhane',
      lat: 35.1825,
      lon: 33.3620),
  KktcBusStop(
      stopId: 'kibhas_stop_kalkanlı',
      stopName: 'Kalkanlı Lavish',
      lat: 35.1830,
      lon: 33.3640),
  KktcBusStop(
      stopId: 'kibhas_stop_gonyeli_irmar',
      stopName: 'Gönyeli İrmar Karşısı',
      lat: 35.1835,
      lon: 33.3660),
  KktcBusStop(
      stopId: 'kibhas_stop_gonyeli_arda',
      stopName: 'Gönyeli Arda Karşısı',
      lat: 35.1838,
      lon: 33.3665),
  KktcBusStop(
      stopId: 'kibhas_stop_gonyeli_sismar',
      stopName: 'Gönyeli Sismar Karşısı',
      lat: 35.1840,
      lon: 33.3670),
  KktcBusStop(
      stopId: 'kibhas_stop_ercan',
      stopName: 'Ercan Havalimanı',
      lat: 35.1547,
      lon: 33.4961),
];

const _ercanLefkeGuzelyurtStops = <KktcBusStop>[
  KktcBusStop(
      stopId: 'kibhas_stop_ercan',
      stopName: 'Ercan Havalimanı',
      lat: 35.1547,
      lon: 33.4961),
  KktcBusStop(
      stopId: 'kibhas_stop_macro',
      stopName: 'Macro',
      lat: 35.1810,
      lon: 33.3540),
  KktcBusStop(
      stopId: 'kibhas_stop_odtu', stopName: 'ODTÜ', lat: 35.1820, lon: 33.3580),
  KktcBusStop(
      stopId: 'kibhas_stop_tufekci',
      stopName: 'Tüfekçi Evleri',
      lat: 35.1185,
      lon: 32.8580),
  KktcBusStop(
      stopId: 'kibhas_stop_yesilyurt_kantin',
      stopName: 'Yeşilyurt Askeri Kantin',
      lat: 35.1710,
      lon: 32.9960),
  KktcBusStop(
      stopId: 'kibhas_stop_yesilyurt_seker',
      stopName: 'Yeşilyurt Şeker Sok.',
      lat: 35.1715,
      lon: 32.9965),
];

// ══════════════════════════════════════════════════════════════════
// Yakınlık tespiti için kAllKibhasStops (sık kullanılan terminal/ara duraklar)
// getNearbyStops'ta sadece bunlar kullanılır — tam liste değil
// ══════════════════════════════════════════════════════════════════
const kAllKibhasStops = <KktcBusStop>[
  KktcBusStop(
      stopId: 'kibhas_stop_ercan',
      stopName: 'KIBHAS — Ercan Havalimanı',
      lat: 35.1547,
      lon: 33.4961),
  KktcBusStop(
      stopId: 'kibhas_stop_anit_cemberi',
      stopName: 'KIBHAS — Mağusa Terminal',
      lat: 35.1228,
      lon: 33.9408),
  KktcBusStop(
      stopId: 'kibhas_stop_colony',
      stopName: 'KIBHAS — Girne Colony Hotel',
      lat: 35.3414,
      lon: 33.3193),
  KktcBusStop(
      stopId: 'kibhas_stop_kizilbas',
      stopName: 'KIBHAS — Lefkoşa Terminal',
      lat: 35.1731,
      lon: 33.3595),
  KktcBusStop(
      stopId: 'kibhas_stop_guzelyurt_term',
      stopName: 'KIBHAS — Güzelyurt Terminal',
      lat: 35.2009,
      lon: 32.9970),
  KktcBusStop(
      stopId: 'kibhas_stop_lefke_karadag',
      stopName: 'KIBHAS — Lefke Terminal',
      lat: 35.1167,
      lon: 32.8500),
  // Sık kullanılan ara duraklar
  KktcBusStop(
      stopId: 'kibhas_stop_dau_ofis',
      stopName: 'KIBHAS — DAÜ Ofis (EMU)',
      lat: 35.1467,
      lon: 33.9008),
  KktcBusStop(
      stopId: 'kibhas_stop_sabanci',
      stopName: 'KIBHAS — Sabancı',
      lat: 35.1560,
      lon: 33.8850),
  KktcBusStop(
      stopId: 'kibhas_stop_dau_guney',
      stopName: 'KIBHAS — DAÜ Güney Kampüs',
      lat: 35.1480,
      lon: 33.8980),
  KktcBusStop(
      stopId: 'kibhas_stop_gau',
      stopName: 'KIBHAS — GAU',
      lat: 35.3345,
      lon: 33.2960),
  KktcBusStop(
      stopId: 'kibhas_stop_ydu',
      stopName: 'KIBHAS — YDÜ',
      lat: 35.1760,
      lon: 33.3650),
  KktcBusStop(
      stopId: 'kibhas_stop_devlet_hastanesi',
      stopName: 'KIBHAS — Devlet Hastanesi',
      lat: 35.1690,
      lon: 33.3550),
  KktcBusStop(
      stopId: 'kibhas_stop_girne_kapisi',
      stopName: 'KIBHAS — Girne Kapısı',
      lat: 35.1775,
      lon: 33.3633),
  KktcBusStop(
      stopId: 'kibhas_stop_uku_molto',
      stopName: 'KIBHAS — UKÜ',
      lat: 35.1762,
      lon: 33.3840),
];

// ══════════════════════════════════════════════════════════════════
// İTİMAT
// ══════════════════════════════════════════════════════════════════

const _itimatMagusaLefkosa = KktcBusLine(
  id: 'itimat_magusa_lefkosa',
  company: 'İtimat',
  from: 'Mağusa Terminali (Anıt Çemberi)',
  to: 'Lefkoşa Çağlayan Terminali',
  fromCity: 'Mağusa',
  toCity: 'Lefkoşa',
  fromLat: 35.1228,
  fromLon: 33.9408,
  toLat: 35.1680,
  toLon: 33.3680,
  departureTimes: [
    '07:00',
    '08:00',
    '09:00',
    '10:00',
    '11:00',
    '12:00',
    '13:00',
    '14:00',
    '15:00',
    '16:00',
    '17:00',
    '18:00',
    '19:00'
  ],
  frequency: '07:00–19:00, her saat başı',
  durationMinutes: 50,
  notes: 'Son durak Girne Kapısına 5 dk yürüme mesafesinde.',
  phone: '+90 392 227 16 17',
);

const _itimatLefkosaMagusa = KktcBusLine(
  id: 'itimat_lefkosa_magusa',
  company: 'İtimat',
  from: 'Lefkoşa Çağlayan Terminali',
  to: 'Mağusa Terminali (Anıt Çemberi)',
  fromCity: 'Lefkoşa',
  toCity: 'Mağusa',
  fromLat: 35.1680,
  fromLon: 33.3680,
  toLat: 35.1228,
  toLon: 33.9408,
  departureTimes: [
    '07:00',
    '08:00',
    '09:00',
    '10:00',
    '11:00',
    '12:00',
    '13:00',
    '14:00',
    '15:00',
    '16:00',
    '17:00',
    '18:00',
    '19:00'
  ],
  frequency: '07:00–19:00, her saat başı',
  durationMinutes: 50,
  phone: '+90 392 227 27 43',
);

// ══════════════════════════════════════════════════════════════════
// KOMBOS
// ══════════════════════════════════════════════════════════════════

const _kombosGirneMagusa = KktcBusLine(
  id: 'kombos_girne_magusa',
  company: 'Kombos',
  from: 'Girne Merkez',
  to: 'Mağusa Terminali',
  fromCity: 'Girne',
  toCity: 'Mağusa',
  fromLat: 35.3414,
  fromLon: 33.3193,
  toLat: 35.1228,
  toLon: 33.9408,
  departureTimes: [
    '07:00',
    '08:00',
    '09:00',
    '10:00',
    '11:00',
    '12:00',
    '13:00',
    '14:00',
    '15:00',
    '16:00',
    '17:00',
    '18:00'
  ],
  frequency: '07:00–18:00, her saat başı',
  durationMinutes: 75,
);

const _kombosMagusaGirne = KktcBusLine(
  id: 'kombos_magusa_girne',
  company: 'Kombos',
  from: 'Mağusa Terminali',
  to: 'Girne Merkez',
  fromCity: 'Mağusa',
  toCity: 'Girne',
  fromLat: 35.1228,
  fromLon: 33.9408,
  toLat: 35.3414,
  toLon: 33.3193,
  departureTimes: [
    '07:30',
    '08:30',
    '09:30',
    '10:30',
    '11:30',
    '12:30',
    '13:30',
    '14:30',
    '15:30',
    '16:30',
    '17:30',
    '18:30'
  ],
  frequency: '07:30–18:30, her buçuklu saatlerde',
  durationMinutes: 75,
);

const _kombosLefkosaGirne = KktcBusLine(
  id: 'kombos_lefkosa_girne',
  company: 'Kombos',
  from: 'Lefkoşa Terminali',
  to: 'Girne Merkez',
  fromCity: 'Lefkoşa',
  toCity: 'Girne',
  fromLat: 35.1731,
  fromLon: 33.3595,
  toLat: 35.3414,
  toLon: 33.3193,
  departureTimes: [
    '06:00',
    '07:00',
    '08:00',
    '09:00',
    '10:00',
    '11:00',
    '12:00',
    '13:00',
    '14:00',
    '15:00',
    '16:00',
    '17:00',
    '18:00',
    '19:00',
    '19:30'
  ],
  frequency: '06:00–19:30, sık aralıklarla',
  durationMinutes: 30,
  notes: 'Yoğun saatlerde 20–30 dk arayla sefer.',
);

const _kombosGirneLefkosa = KktcBusLine(
  id: 'kombos_girne_lefkosa',
  company: 'Kombos',
  from: 'Girne Merkez',
  to: 'Lefkoşa Terminali',
  fromCity: 'Girne',
  toCity: 'Lefkoşa',
  fromLat: 35.3414,
  fromLon: 33.3193,
  toLat: 35.1731,
  toLon: 33.3595,
  departureTimes: [
    '06:00',
    '07:00',
    '08:00',
    '09:00',
    '10:00',
    '11:00',
    '12:00',
    '13:00',
    '14:00',
    '15:00',
    '16:00',
    '17:00',
    '18:00',
    '19:00',
    '19:30'
  ],
  frequency: '06:00–19:30, sık aralıklarla',
  durationMinutes: 30,
);

// ══════════════════════════════════════════════════════════════════
// KIBHAS — Resmi saatler (kibhas.org 2024-2025)
// ══════════════════════════════════════════════════════════════════

const _kibhasErcanLefkosa = KktcBusLine(
  id: 'kibhas_ercan_lefkosa',
  company: 'KIBHAS',
  from: 'Ercan Havalimanı',
  to: 'Lefkoşa Otobüs Terminali',
  fromCity: 'Ercan',
  toCity: 'Lefkoşa',
  fromLat: 35.1547,
  fromLon: 33.4961,
  toLat: 35.1731,
  toLon: 33.3595,
  departureTimes: [
    '00:30',
    '02:45',
    '07:00',
    '08:00',
    '09:00',
    '10:00',
    '11:10',
    '12:30',
    '13:15',
    '14:45',
    '16:15',
    '17:15',
    '18:15',
    '19:30',
    '20:30',
    '21:30',
    '22:30'
  ],
  frequency: 'Uçuş tarifesine göre gün boyu',
  durationMinutes: 20,
  phone: '0533 870 78 48',
  stops: _ercanLefkosaStops,
);

const _kibhasLefkosaErcan = KktcBusLine(
  id: 'kibhas_lefkosa_ercan',
  company: 'KIBHAS',
  from: 'Lefkoşa Otobüs Terminali',
  to: 'Ercan Havalimanı',
  fromCity: 'Lefkoşa',
  toCity: 'Ercan',
  fromLat: 35.1731,
  fromLon: 33.3595,
  toLat: 35.1547,
  toLon: 33.4961,
  departureTimes: [
    '00:05',
    '02:30',
    '05:00',
    '06:00',
    '08:30',
    '09:30',
    '11:30',
    '13:00',
    '14:30',
    '16:30',
    '17:30',
    '19:15',
    '21:00',
    '23:00'
  ],
  frequency: 'Uçuş tarifesine göre gün boyu',
  durationMinutes: 20,
  phone: '0533 870 78 45',
  stops: _lefkosaErcanStops,
);

const _kibhasErcanGirne = KktcBusLine(
  id: 'kibhas_ercan_girne',
  company: 'KIBHAS',
  from: 'Ercan Havalimanı',
  to: 'Girne Colony Hotel Yanı',
  fromCity: 'Ercan',
  toCity: 'Girne',
  fromLat: 35.1547,
  fromLon: 33.4961,
  toLat: 35.3414,
  toLon: 33.3193,
  departureTimes: [
    '00:30',
    '02:45',
    '07:00',
    '08:00',
    '09:00',
    '10:00',
    '11:10',
    '12:30',
    '13:15',
    '14:45',
    '16:15',
    '17:15',
    '18:15',
    '19:30',
    '20:30',
    '21:30',
    '22:30'
  ],
  frequency: 'Uçuş tarifesine göre gün boyu',
  durationMinutes: 50,
  phone: '0533 870 78 46',
  stops: _ercanGirneStops,
);

const _kibhasGirneErcan = KktcBusLine(
  id: 'kibhas_girne_ercan',
  company: 'KIBHAS',
  from: 'Girne Colony Hotel Yanı',
  to: 'Ercan Havalimanı',
  fromCity: 'Girne',
  toCity: 'Ercan',
  fromLat: 35.3414,
  fromLon: 33.3193,
  toLat: 35.1547,
  toLon: 33.4961,
  departureTimes: [
    '00:05',
    '02:00',
    '04:00',
    '06:00',
    '08:30',
    '09:30',
    '11:30',
    '13:00',
    '14:30',
    '16:30',
    '17:30',
    '19:15',
    '21:00',
    '23:00'
  ],
  frequency: 'Uçuş tarifesine göre gün boyu',
  durationMinutes: 50,
  stops: _girneErcanStops,
);

const _kibhasErcanMagusa = KktcBusLine(
  id: 'kibhas_ercan_magusa',
  company: 'KIBHAS',
  from: 'Ercan Havalimanı',
  to: 'Mağusa Otobüs Terminali',
  fromCity: 'Ercan',
  toCity: 'Mağusa',
  fromLat: 35.1547,
  fromLon: 33.4961,
  toLat: 35.1228,
  toLon: 33.9408,
  departureTimes: [
    '00:30',
    '02:45',
    '07:00',
    '08:00',
    '09:00',
    '10:00',
    '11:10',
    '12:30',
    '13:15',
    '14:45',
    '16:15',
    '17:15',
    '18:15',
    '19:30',
    '20:30',
    '21:30',
    '22:30'
  ],
  frequency: 'Uçuş tarifesine göre gün boyu',
  durationMinutes: 60,
  phone: '0533 870 78 47',
  stops: _ercanMagusaStops,
);

const _kibhasMagusaErcan = KktcBusLine(
  id: 'kibhas_magusa_ercan',
  company: 'KIBHAS',
  from: 'Mağusa Otobüs Terminali',
  to: 'Ercan Havalimanı',
  fromCity: 'Mağusa',
  toCity: 'Ercan',
  fromLat: 35.1228,
  fromLon: 33.9408,
  toLat: 35.1547,
  toLon: 33.4961,
  departureTimes: [
    '00:05',
    '02:00',
    '04:00',
    '06:00',
    '08:30',
    '09:30',
    '11:30',
    '13:00',
    '14:30',
    '16:30',
    '17:30',
    '19:15',
    '21:00',
    '23:00'
  ],
  frequency: 'Uçuş tarifesine göre gün boyu',
  durationMinutes: 60,
  stops: _magusaErcanStops,
);

const _kibhasErcanGuzelyurt = KktcBusLine(
  id: 'kibhas_ercan_guzelyurt',
  company: 'KIBHAS',
  from: 'Ercan Havalimanı',
  to: 'Güzelyurt Otobüs Terminali',
  fromCity: 'Ercan',
  toCity: 'Güzelyurt',
  fromLat: 35.1547,
  fromLon: 33.4961,
  toLat: 35.2009,
  toLon: 32.9970,
  departureTimes: [
    '00:30',
    '02:45',
    '09:00',
    '12:00',
    '14:30',
    '17:00',
    '19:30',
    '22:00'
  ],
  frequency: 'Uçuş tarifesine göre gün boyu',
  durationMinutes: 50,
  stops: _ercanLefkeGuzelyurtStops,
);

const _kibhasGuzelyurtErcan = KktcBusLine(
  id: 'kibhas_guzelyurt_ercan',
  company: 'KIBHAS',
  from: 'Güzelyurt Otobüs Terminali',
  to: 'Ercan Havalimanı',
  fromCity: 'Güzelyurt',
  toCity: 'Ercan',
  fromLat: 35.2009,
  fromLon: 32.9970,
  toLat: 35.1547,
  toLon: 33.4961,
  departureTimes: [
    '00:30',
    '03:00',
    '06:30',
    '11:30',
    '14:00',
    '16:00',
    '19:30',
    '22:00'
  ],
  frequency: 'Uçuş tarifesine göre gün boyu',
  durationMinutes: 50,
  stops: _lefkeGuzelyurtErcanStops,
);

const _kibhasErcanLefke = KktcBusLine(
  id: 'kibhas_ercan_lefke',
  company: 'KIBHAS',
  from: 'Ercan Havalimanı',
  to: 'Lefke Terminali',
  fromCity: 'Ercan',
  toCity: 'Lefke',
  fromLat: 35.1547,
  fromLon: 33.4961,
  toLat: 35.1167,
  toLon: 32.8500,
  departureTimes: [
    '00:30',
    '02:45',
    '09:00',
    '12:00',
    '14:30',
    '17:00',
    '19:30',
    '22:00'
  ],
  frequency: 'Uçuş tarifesine göre gün boyu',
  durationMinutes: 65,
  stops: _ercanLefkeGuzelyurtStops,
);

const _kibhasLefkeErcan = KktcBusLine(
  id: 'kibhas_lefke_ercan',
  company: 'KIBHAS',
  from: 'Lefke Terminali',
  to: 'Ercan Havalimanı',
  fromCity: 'Lefke',
  toCity: 'Ercan',
  fromLat: 35.1167,
  fromLon: 32.8500,
  toLat: 35.1547,
  toLon: 33.4961,
  departureTimes: [
    '00:30',
    '03:00',
    '06:30',
    '11:30',
    '14:00',
    '16:00',
    '19:30',
    '22:00'
  ],
  frequency: 'Uçuş tarifesine göre gün boyu',
  durationMinutes: 65,
  stops: _lefkeGuzelyurtErcanStops,
);

// ══════════════════════════════════════════════════════════════════
// Tüm KKTC hatları
// ══════════════════════════════════════════════════════════════════
const kKktcBusLines = <KktcBusLine>[
  _itimatMagusaLefkosa,
  _itimatLefkosaMagusa,
  _kombosGirneMagusa,
  _kombosMagusaGirne,
  _kombosLefkosaGirne,
  _kombosGirneLefkosa,
  _kibhasErcanLefkosa,
  _kibhasLefkosaErcan,
  _kibhasErcanGirne,
  _kibhasGirneErcan,
  _kibhasErcanMagusa,
  _kibhasMagusaErcan,
  _kibhasErcanGuzelyurt,
  _kibhasGuzelyurtErcan,
  _kibhasErcanLefke,
  _kibhasLefkeErcan,
];

// ══════════════════════════════════════════════════════════════════
// KktcBusService
// ══════════════════════════════════════════════════════════════════
class KktcBusService {
  static const KktcBusService instance = KktcBusService._();
  const KktcBusService._();

  bool isKibhasStop(String stopId) => stopId.startsWith('kibhas_stop_');

  List<KktcBusLine> linesForStop(String stopId) => kKktcBusLines
      .where((l) => l.stops.any((s) => s.stopId == stopId))
      .toList();

  List<KktcBusLine> linesFromTo(String fromCity, String toCity) {
    final fn = _n(fromCity);
    final tn = _n(toCity);
    return kKktcBusLines
        .where((l) => _n(l.fromCity).contains(fn) && _n(l.toCity).contains(tn))
        .toList();
  }

  List<KktcBusLine> linesFrom(String city) {
    final cn = _n(city);
    return kKktcBusLines.where((l) => _n(l.fromCity).contains(cn)).toList();
  }

  List<KktcBusLine> linesByCompany(String company) {
    final cn = _n(company);
    return kKktcBusLines.where((l) => _n(l.company).contains(cn)).toList();
  }

  List<_UpcomingDeparture> nextDepartures(KktcBusLine line, {int max = 5}) {
    final nowMin = DateTime.now().hour * 60 + DateTime.now().minute;
    final result = <_UpcomingDeparture>[];
    for (final t in line.departureTimes) {
      final parts = t.split(':');
      if (parts.length < 2) continue;
      int diff =
          (int.tryParse(parts[0])! * 60 + int.tryParse(parts[1])!) - nowMin;
      if (diff < 0) diff += 1440;
      if (diff <= 720)
        result.add(_UpcomingDeparture(time: t, minutesFromNow: diff));
    }
    result.sort((a, b) => a.minutesFromNow.compareTo(b.minutesFromNow));
    return result.take(max).toList();
  }

  String _n(String s) => s
      .toLowerCase()
      .replaceAll('ı', 'i')
      .replaceAll('ğ', 'g')
      .replaceAll('ü', 'u')
      .replaceAll('ş', 's')
      .replaceAll('ö', 'o')
      .replaceAll('ç', 'c');

  List<KktcBusLine> searchByMessage(String message) {
    final n = _n(message);
    final cities = <String, String>{
      'lefkosa': 'Lefkoşa',
      'nicosia': 'Lefkoşa',
      'girne': 'Girne',
      'kyrenia': 'Girne',
      'magusa': 'Mağusa',
      'gazimagusa': 'Mağusa',
      'famagusta': 'Mağusa',
      'ercan': 'Ercan',
      'havalimani': 'Ercan',
      'guzelyurt': 'Güzelyurt',
      'morfou': 'Güzelyurt',
      'lefke': 'Lefke',
    };
    final companies = {
      'itimat': 'İtimat',
      'kombos': 'Kombos',
      'kibhas': 'KIBHAS'
    };
    for (final e in companies.entries) {
      if (n.contains(e.key)) {
        final r = linesByCompany(e.value);
        if (r.isNotEmpty) return r;
      }
    }
    String? from, to;
    for (final e in cities.entries) {
      if (n.contains(e.key)) {
        if (from == null)
          from = e.value;
        else if (to == null && e.value != from) to = e.value;
      }
    }
    if (from != null && to != null) {
      final d = linesFromTo(from, to);
      return d.isNotEmpty ? d : linesFromTo(to, from);
    }
    if (from != null) return linesFrom(from);
    return [];
  }

  String formatForAI(List<KktcBusLine> lines) {
    if (lines.isEmpty) return '';
    final sb = StringBuffer();
    final now = DateTime.now();
    sb.writeln(
        '🕐 Şu an: ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}');
    for (final line in lines) {
      sb.writeln('\n🚌 ${line.company} — ${line.from} → ${line.to}');
      sb.writeln(
          '   Sıklık: ${line.frequency}  |  Süre: ~${line.durationMinutes} dk');
      if (line.phone.isNotEmpty) sb.writeln('   📞 ${line.phone}');
      final upcoming = nextDepartures(line, max: 4);
      if (upcoming.isNotEmpty) {
        sb.writeln('   Sonraki seferler:');
        for (final d in upcoming) {
          final h = d.minutesFromNow ~/ 60;
          final m = d.minutesFromNow % 60;
          sb.writeln(
              '   • ${d.time} — ${d.minutesFromNow < 60 ? '${d.minutesFromNow} dk' : '${h}s ${m}dk'} sonra');
        }
      }
      if (line.notes.isNotEmpty) sb.writeln('   ℹ️ ${line.notes}');
    }
    return sb.toString().trim();
  }
}

class _UpcomingDeparture {
  final String time;
  final int minutesFromNow;
  const _UpcomingDeparture({required this.time, required this.minutesFromNow});
}
