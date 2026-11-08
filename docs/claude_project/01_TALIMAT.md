# Shore Fishing Türkiye: proje talimatı

Bu projede **Shore Fishing Türkiye** adlı oyunu geliştiriyoruz. Oyun gerçekçi, sakin bir kıyı
balıkçılığı oyunudur: Türkiye'nin gerçek kıyılarında (Çeşme, Dikili, Antalya, Fethiye, Kaş, Galata,
Çanakkale, Teos, Sinop, Trabzon) balık tutulur. Mevsim, ay evresi, rüzgâr ve Türk amatör balıkçılık
kuralları (yasal boy, günlük sınır) oyunun parçasıdır.

## Ne yapacaksın
- Kodu GitHub deposunda (nextlevelcorp/godot_fishing_rpg) geliştir. Oyun Godot 4.4 ve GDScript ile
  yazılıyor, web (GitHub Pages) için yayınlanıyor, hedef iPhone Safari.
- Önce her zaman `GAME_DESIGN.md` ve `MVP_ROADMAP.md` belgelerinin ilgili bölümlerini oku.
- Yeni özellik eklerken tasarım belgesine de bölüm ekle. Kararları ve sayıları oraya yaz.
- Sayılar ve etkiler "game-design fill" (oyun tasarımı tahmini) ise bunu belgede açıkça yaz.
  Gerçek bir yere ait bilgi kullanıyorsan kaynağını belirt.

## Kurallar (önemli)
1. **Doğrulama:** Godot bulut ortamında gerçek cihazda çalışmaz. Bir şeyin çalıştığını ancak CI
   (GitHub Actions) sonucu ya da telefon raporu gösterirse söyle. Ekran görüntüsüyle görsel kontrol
   yapılabilir (`tools/shots/shot.gd`, bkz. `game-art` skill'i).
2. **Yayın:** `main` dalına push etmek oyunu yayınlar. Her davranış değişikliğinde
   `game_session.gd` içindeki `BUILD` sabitini artır, oyuncu eski sürümü görmesin.
3. **Dokunmatik girdi:** Dokunma yalnızca GUI kontrolleriyle (`touch_controls.gd`) yapılır,
   ham `_input` kullanılmaz.
4. **Hareket:** Canlı şeyler `noc.gd` kurallarına göre hareket eder (kuvvet, yay, parçacık, sürü).
5. **GDScript tuzağı:** `var x := sözlük["anahtar"]` ya da `{...}.get(...)` ifadesinde tip
   çıkarılamaz, script yüklenmez. Tipi açıkça yaz.
6. **Gerçek yerler:** Gerçek bir yerle ilgili iddia `fishing_spots.gd` içinde kaynaklanmalı.
7. **Kapanış:** Her değişikliği commit'le ve push et. Commit mesajında ne ve neden yazılsın.
8. **Kaynak kodu koruma:** Eski ya da bağlantısız dosyaları silmeden önce ne olacağını anlat, onay al.

## Çalışma biçimi
- Kararları ve riskleri kısa, Türkçe anlat. Büyük değişikliklerden önce plan sun, onay bekle.
- Bir özellik bitince: ne değişti, CI sonucu, telefonda ne kontrol edilmeli (3 madde), başarısız olan ne.
- Belgeler: `GAME_DESIGN.md` (tasarım), `TECHNICAL_ARCHITECTURE.md` (yapı), `MVP_ROADMAP.md`
  (yol haritası), `CLAUDE.md` (depodaki kurallar), `docs/REVIEW_2026-11-08.md` (son inceleme).
