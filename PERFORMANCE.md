# Speech Cleaner performans auditi

Tarix: 10 iyul 2026

## Test cihazı

- MacBook Pro (Mac16,8)
- Apple M4 Pro, 12 CPU nüvəsi (8 performance + 4 efficiency)
- 24 GB unified memory
- macOS 26.3.1
- Whisper medium Q5 multilingual modeli (514 MB)
- FFmpeg 8.1.1 və whisper.cpp 1.9.1

## Tam real Azərbaycan nitqi testi

Mənbə istifadəçinin 372.123 saniyəlik Azərbaycan dili voiceover WAV faylıdır. Mənbə yalnız oxunub; dəyişdirilməyib. Testə denoise, pauza analizi, compression, loudness normalization, Azərbaycan dili transkripsiyası, söz xəritəsi və 1280×720 H.264/AAC MP4 renderi daxildir.

| Ölçü | Nəticə |
|---|---:|
| Mənbə müddəti | 372.123 san (06:12) |
| Ümumi wall time | 68.35 san |
| Real-time sürəti | 5.44× |
| CPU user time | 33.96 san |
| CPU system time | 3.66 san |
| Orta CPU ekvivalenti | bir nüvənin təxminən 55%-i |
| Maksimum resident memory | 1,275,854,848 bayt (1.19 GiB) |
| Swap | 0 |
| Aşkarlanan söz | 890 |
| MP4 ölçüsü | 34 MB |
| Təmiz WAV | 51 MB |
| Təmiz M4A | 8.0 MB |
| Tətbiqin nəticədən sonrakı idle RAM-ı | 133,872 KiB (130.7 MiB) |
| Tətbiqin idle CPU-su | 0.0% |

CPU rəqəmi `/usr/bin/time -l` tərəfindən bütün production proses ağacı üçün ölçülüb. Whisper Metal sürətləndirməsindən, MP4 isə macOS hardware H.264 encoder-dən istifadə etdiyinə görə wall time yalnız CPU vaxtından ibarət deyil.

## Audio keyfiyyət ölçüsü

Tam test nəticəsində FFmpeg EBU R128 analizi:

- Integrated loudness: **-15.6 LUFS**
- True peak: **-1.5 dBFS**
- Loudness range: **2.4 LU**

Bu səviyyə danışıq audiosu üçün sabit və clipping-dən qorunan nəticədir.

## Dəqiq pauza testi

Test audiosuna süni olaraq 2.0 və 1.2 saniyəlik iki sükut əlavə edilib. Standart profil hər ikisini 0.20 saniyə ətrafında saxlayıb:

- Mənbə: 18.200 san
- Nəticə: 15.398 san
- Birinci saxlanan pauza: 0.196 san
- İkinci saxlanan pauza: 0.194 san
- Emal vaxtı, MP4-süz: 2.08 san

Bu test pauza mühərrikinin sadəcə sükutu aşkar etmədiyini, seçilən saxlanma müddətini həqiqətən tətbiq etdiyini sübut edir.

## Qiymətləndirmə

24 GB M4 Pro üçün resurs istifadəsi təhlükəsizdir: ağır emal zamanı RAM cihaz yaddaşının təxminən 5%-idir, swap yaranmır və 6 dəqiqəlik layihə təxminən 68 saniyədə tam hazır olur. UI emaldan ayrı işlədiyi üçün proses zamanı cavabdeh qalır.
