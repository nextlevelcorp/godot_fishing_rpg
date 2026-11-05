# Yapay zekâ ile çizim brifi — Shore Fishing Türkiye

Bu belge, oyunun resimlerini (sprite) bir yapay zekâ resim aracıyla üretmeniz içindir. Açıklamalar
Türkçe, araçlara yapıştıracağınız komutlar (prompt) İngilizce: araçlar İngilizce komutla daha iyi
sonuç veriyor. Resimler gelince ben oyuna bağlarım. Bir resim eksikse oyun o nesneyi eskisi gibi
çizer, yani parça parça getirebilirsiniz.

---

## 1. Adım adım ne yapacaksınız

1. **Araç seçin.** Yeni başlayan için en kolayı **ChatGPT'nin resim üretme özelliği**: şeffaf arka
   planlı PNG verebiliyor ve sohbet içinde "aynı tarzda devam et" diyebiliyorsunuz. Alternatifler:
   Midjourney (stil referansı güçlü), Leonardo veya Scenario (oyun varlığı için).
2. **Önce tek bir "stil çapası" üretin.** Bölüm 3'teki *ilk komut* ile bir lüfer çizdirin. Beğendiğiniz
   sonucu kaydedin: bu, bütün diğer resimlerin örnek alacağı resim. Sonraki her komutta bu resmi
   yükleyip "bu resmin tarzında" deyin (ChatGPT'de aynı sohbette devam etmek de yeter).
3. **Her resmi kontrol edin** (Bölüm 8'deki kontrol listesi). Yüzgeç sayısı, renk deseni yanlışsa
   "fix: ..." diye düzelttirin.
4. **Arka plan şeffaf olsun.** Araç şeffaf veremiyorsa düz parlak pembe (#FF00FF) arka plan isteyin;
   ben onu silerim.
5. **Dosyayı adlandırın** (tablolardaki dosya adı) ve klasörüne koyun.
6. **Bana ulaştırın.** Klasörleri zip yapıp buraya yükleyin, ya da GitHub'da reponun
   `assets/art/` klasörüne "Add file → Upload files" ile yükleyin.

**Kullanım şartı notu:** Aracın kullanım şartlarının ticari kullanıma izin verdiğinden emin olun
(ücretli planlar genelde izin verir). Steam'de yayınlarsanız yapay zekâ kullanımını beyan etmeniz
gerekir. Hangi aracı kullandığınızı bana yazın, `assets/art/SOURCE.md`'ye kaydederim.

---

## 2. Ortak tarz (her komutun başına eklenecek)

Bu satırı **her komutun başına** yapıştırın:

```
Hand-painted 2D game art, soft painterly shading, warm natural sunlight from the top-left, clean shapes,
very thin dark-brown outline or no outline, realistic proportions, cozy Mediterranean seaside mood,
NOT pixel art, NOT 3D render, NOT photo. Single subject, centered, transparent background,
no text, no watermark, no frame.
```

Renk yönü: sıcak ve doygun ama gerçekçi. Deniz turkuaz ve lacivert, taşlar sıcak gri ve bej, çatılar
kiremit kırmızısı, duvarlar beyaz ve krem, yeşiller zeytin yeşili.

---

## 3. Balıklar (öncelik 1)

Hepsi **tam yandan, baş sağa dönük**, yüzgeçler açık, ağız kapalı. Tuval **1024 × 512 px**, balık
genişliğin yaklaşık %90'ını kaplasın. Yerde gölge yok. Klasör: `assets/art/fish/`.

Her balık için komut kalıbı:

```
[ortak tarz satırı] Scientific-illustration accurate side view of a [TÜR], facing right, fins spread,
mouth closed, wet glossy look, 1024x512 canvas, the fish fills 90% of the width. [TÜR TARİFİ]
```

**İlk komut (stil çapası):** lüfer satırını kullanın.

| Dosya adı | Tür (TR) | [TÜR] ve [TÜR TARİFİ] (İngilizce, olduğu gibi yapıştırın) |
|---|---|---|
| `bluefish.png` | Lüfer | bluefish (Pomatomus saltatrix). Elongated body, blue-green back fading to silver sides and white belly, large mouth with a jutting lower jaw and small sharp teeth, two dorsal fins (first short and spiny, second long), forked tail, dark blotch at the base of the pectoral fin. |
| `garfish.png` | Zargana | garfish (Belone belone). Very long slender body, long thin beak-like jaws, green-blue back, bright silver sides, dorsal and anal fins set far back near the small forked tail. |
| `european_seabass.png` | Levrek | European seabass (Dicentrarchus labrax). Streamlined silver-grey body, darker grey back, white belly, two separate dorsal fins (first spiny), dark spot on the edge of the gill cover, slightly forked tail. |
| `gilthead_seabream.png` | Çipura | gilthead seabream (Sparus aurata). Deep oval body, steep rounded forehead, silvery grey with thin grey lengthwise lines, golden band between the eyes, dark spot at the top of the gill cover, one long dorsal fin, forked tail. |
| `atlantic_bonito.png` | Palamut | Atlantic bonito (Sarda sarda). Torpedo body, steel-blue back with dark slanting stripes, silver belly, two dorsal fins close together, a row of small finlets before a sharply forked tail. |
| `atlantic_mackerel.png` | Uskumru | Atlantic mackerel (Scomber scombrus). Spindle body, green-blue back with wavy black bars, silver-white belly, two widely spaced dorsal fins, small finlets, forked tail. |
| `mediterranean_horse_mackerel.png` | İstavrit | Mediterranean horse mackerel (Trachurus mediterraneus). Slim body, big eyes, grey-green back, silver sides, bony scutes along a lateral line that bends down, two dorsal fins, deeply forked tail, small black spot on the gill cover. |
| `european_anchovy.png` | Hamsi | European anchovy (Engraulis encrasicolus). Small slender body, blue-green back, a silver stripe along the side, long mouth reaching behind the eye, one dorsal fin, forked tail. |
| `red_mullet.png` | Barbunya | red mullet (Mullus barbatus). Pinkish-red body, steep head profile, two long barbels under the chin, large scales, two dorsal fins, forked tail. |
| `flathead_grey_mullet.png` | Kefal | flathead grey mullet (Mugil cephalus). Rounded torpedo body, broad flat head, grey-blue back, silver sides with faint dark lengthwise stripes, two small separate dorsal fins, small mouth. |
| `common_dentex.png` | Sinağrit | common dentex (Dentex dentex). Deep body, steep head, pinkish silver-grey with small dark blue spots on the upper body, strong front teeth, one long dorsal fin, forked tail. |
| `greater_amberjack.png` | Akya / Sarıkuyruk | greater amberjack (Seriola dumerili). Long powerful body, blue-grey back, silver-white belly, an amber-yellow stripe along the side, dark band from the eye to the dorsal fin, deeply forked tail. |
| `leerfish.png` | Akya (Lichia) | leerfish (Lichia amia). Deep flattened silver body, wavy curved lateral line, dark fin tips, forked tail. |
| `dusky_grouper.png` | Orfoz | dusky grouper (Epinephelus marginatus). Heavy robust body, big mouth, dark reddish-brown with irregular pale yellow blotches, long spiny dorsal fin, rounded tail with a pale edge. |
| `black_scorpionfish.png` | İskorpit | black scorpionfish (Scorpaena porcus). Stocky body, big spiny head with small skin flaps above the eyes, mottled brown-red camouflage, spiny dorsal fin, rounded fins and tail. |
| `saddled_bream.png` | Melanurya | saddled bream (Oblada melanura). Oval silver-grey body, large eye, a black saddle spot with a white edge on the tail stalk, forked tail. |
| `white_seabream.png` | Sargoz | white seabream (Diplodus sargus). Oval flattened silver body, 8 to 9 thin dark vertical bars, black saddle on the tail stalk, forked tail. |
| `striped_sea_bream.png` | Mırmır | striped seabream (Lithognathus mormyrus). Oval body, pointed snout, silver with about 14 narrow dark vertical bars, forked tail. |
| `whiting.png` | Mezgit | whiting (Merlangius merlangus). Long body, sandy-olive back, silver-white sides, three dorsal fins and two anal fins, small dark spot at the pectoral fin base, square tail. |
| `turbot.png` | Kalkan | turbot (Scophthalmus maximus), seen FROM ABOVE (it is a flatfish): almost round body, both eyes on top, sandy brown with dark spots and small bony knobs, fringe fins all around. Canvas 1024x1024. |
| `greater_weever.png` | Trakonya | greater weever (Trachinus draco). Long body, eyes on top of the head, slanting mouth, yellowish-brown with blue-grey diagonal lines, short black first dorsal fin. |
| `ornate_wrasse.png` | Gün balığı | ornate wrasse (Thalassoma pavo). Slender body, green with blue lines on the head and a red and blue band behind the head, rounded tail. |
| `common_octopus.png` | Ahtapot | common octopus (Octopus vulgaris), side view, reddish-brown mottled skin, eight curling arms with suckers. |
| `common_cuttlefish.png` | Mürekkep balığı | common cuttlefish (Sepia officinalis), side view, broad oval body with a fin skirt, zebra-stripe pattern on the back, short arms. |
| `european_squid.png` | Kalamar | European squid (Loligo vulgaris), side view, long torpedo mantle with two triangular fins at the end, translucent pinkish with red dots, ten arms. |
| `blue_crab.png` | Mavi yengeç | Atlantic blue crab (Callinectes sapidus), seen FROM ABOVE, olive-green shell with spines on the sides, blue claws, paddle-shaped back legs. Canvas 1024x1024. |

---

## 4. Oltacı ve insanlar (öncelik 2)

Dünya görünüşü: **üstten ve hafif önden (3/4), Stardew Valley açısı, ama boyanmış, piksel değil.**
Her karede ayaklar aynı çizgide olsun. Klasör: `assets/art/characters/`.

Komut kalıbı:

```
[ortak tarz satırı] Three-quarter top-down game character (camera above and slightly in front, like
Stardew Valley but painted, not pixel art), full body, feet at the bottom of the frame, [KİŞİ], [POZ].
Frame 256x384 px.
```

**[KİŞİ] oltacı (siz):** `a Turkish shore angler in his 40s, olive-green fishing vest over a light shirt, dark trousers, red cap, short dark hair`

| Dosya adı | [POZ] |
|---|---|
| `angler_idle_down.png` | standing, facing the camera |
| `angler_idle_up.png` | standing, seen from behind, facing away |
| `angler_idle_side.png` | standing, side view facing right |
| `angler_walk_down.png` | walk cycle, 4 frames side by side in one horizontal sprite sheet 1024x384, facing the camera |
| `angler_walk_up.png` | walk cycle, 4 frames, seen from behind |
| `angler_walk_side.png` | walk cycle, 4 frames, side view facing right |
| `angler_hold_up.png` | seen from behind, holding a spinning rod forward with both hands, rod pointing up and away |
| `angler_cast_up.png` | seen from behind, rod raised over the right shoulder, about to cast |

Yapay zekâ hareket karelerini (walk cycle) bazen tutarsız çizer: kareler arasında yüz ya da renk
değişir. Öyle olursa sadece duran pozları (idle, hold, cast) getirin, yürümeyi ben hareket ettiririm.

**Kasabalılar** (her biri için `idle_down`, `idle_side`, `walk_side`; dosya adı `townsfolk_1_idle_down.png` gibi):

| No | [KİŞİ] |
|---|---|
| 1 | `an elderly Turkish man with a flat cap, grey jacket, prayer beads in hand` |
| 2 | `a young woman in a summer dress and a straw hat` |
| 3 | `a fisherman in yellow rubber overalls and boots` |
| 4 | `a boy in a striped T-shirt and shorts` |
| 5 | `a simit seller with a tray of sesame bread rings on his head` |

---

## 5. Kasaba ve kıyı (öncelik 3)

Aynı 3/4 açı. Yerde yumuşak gölge olabilir. Klasör: `assets/art/town/`.

```
[ortak tarz satırı] Three-quarter top-down game asset (camera above and slightly in front, like Stardew
Valley but painted, not pixel art), [NESNE]. [BOYUT].
```

| Dosya adı | [NESNE] | [BOYUT] |
|---|---|---|
| `house_1.png` … `house_4.png` | a two-storey Aegean town house, white-washed walls, terracotta tile roof, blue wooden shutters, a small balcony with flowers (her birinde farklı renk kepenk ve çiçek isteyin) | 512x512 |
| `house_stone.png` | a Black Sea stone and timber house with a dark wooden upper floor | 512x512 |
| `mosque.png` | a small Ottoman-style seaside mosque with one dome and one slender minaret | 768x1024 |
| `cafe.png` | a seaside tea house with a striped awning, small tables and stools outside | 512x512 |
| `tree_olive.png`, `tree_pine.png`, `tree_palm.png` | an olive tree / a Mediterranean stone pine / a palm tree | 384x512 |
| `bench.png` | a wooden park bench | 256x128 |
| `street_lamp.png` | an old cast-iron street lamp | 128x384 |
| `boat_fishing.png` | a small wooden Turkish fishing boat (kayık), blue and white, seen from above at an angle | 512x256 |
| `boat_ferry.png` | a white Istanbul passenger ferry (vapur) with a red-black funnel, seen from above at an angle | 768x384 |
| `cat_1.png`, `cat_2.png` | a ginger street cat sitting / a tabby cat walking, side view | 128x128 |
| `gull.png` | a yellow-legged gull flying, wings spread, seen from above | 256x128 |

**Zemin parçaları** (yan yana dizilince dikiş görünmemeli; `seamless tileable texture, top-down` ekleyin, 256x256):
`tile_sand.png` (kum), `tile_pebbles.png` (çakıl), `tile_rock.png` (kaya), `tile_cobble.png`
(Arnavut kaldırımı), `tile_pier_planks.png` (iskele tahtası), `tile_grass.png` (ot).

---

## 6. Birinci şahıs balık tutma ekranı (öncelik 4)

Klasör: `assets/art/pov/`.

| Dosya adı | Komut (ortak tarz satırından sonra) |
|---|---|
| `pov_rod_hands.png` | `First-person view from an angler's eyes: two hands holding a carbon spinning rod with a cork handle and a silver spinning reel, seen from slightly behind, placed in the bottom-right of a 1920x1080 frame, the rod reaching up toward the top-centre. Everything else transparent.` |
| `panorama_aegean.png` | `Wide panorama of the far shore of an Aegean bay seen across the sea: low olive hills, a white town with terracotta roofs, a small mosque, a few boats. Only the hills and town: sky and sea transparent. 4096x768.` |
| `panorama_istanbul.png` | aynı komut, ama `the Istanbul skyline across the Golden Horn: Galata Tower, domes and minarets of historic mosques, ferries` |
| `panorama_blacksea.png` | aynı komut, ama `green steep Black Sea hills with tea gardens and stone houses, misty` |
| `panorama_med.png` | aynı komut, ama `rocky Mediterranean coast with pine forests and the Taurus mountains behind` |

---

## 7. Teknik kurallar (özet)

- PNG, şeffaf arka plan. Şeffaf olmuyorsa düz #FF00FF pembe.
- Işık hep sol üstten, tarz hep aynı (stil çapasını referans verin).
- Balıklar tam yandan, baş sağa. Dünya nesneleri 3/4 üstten.
- Ölçekler tablodaki gibi. Ben oyunda küçültürüm, büyük çizilmesi iyidir.
- Dosya adları tablodaki gibi, küçük harf, Türkçe karakter yok.

---

## 8. Kontrol listesi (her resimde)

- Tür doğru mu? Yüzgeç sayısı ve yeri, desen, renk tarifteki gibi mi?
- Fazladan yüzgeç, göz, bacak, parmak var mı? (Yapay zekâda sık olur.)
- Yazı, imza, filigran var mı? Olmamalı.
- Arka plan şeffaf ya da düz pembe mi?
- Balık sağa mı bakıyor, yerde gölge yok mu?
- Diğer resimlerle aynı tarzda mı (renk sıcaklığı, çizgi kalınlığı, ışık yönü)?

Sorun varsa aynı sohbette düzeltme isteyin, örneğin: `Fix: it should have two separate dorsal fins and no
teeth showing, keep everything else the same.`

---

## 9. Öncelik ve teslim

1. **Önce 5 balık deneyin:** lüfer, çipura, levrek, istavrit, kefal. Bana gönderin. Oyuna bağlayıp
   nasıl göründüğünü birlikte değerlendirelim, sonra kalanları üretirsiniz.
2. Sonra oltacı (idle ve hold pozları yeter).
3. Sonra kasaba ve zemin, en son birinci şahıs ekranı ve panoramalar.

Klasör yapısı:

```
assets/art/fish/          balıklar
assets/art/characters/    oltacı ve kasabalılar
assets/art/town/          binalar, ağaçlar, nesneler, zemin parçaları
assets/art/pov/           eller ve olta, panoramalar
```
