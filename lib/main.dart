import 'dart:async';
import 'dart:typed_data'; 
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

// GÖRSEL İŞLEME KÜTÜPHANESİ
import 'package:image/image.dart' as img; 

// WEB İNDİRME İŞLEMİ
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:html' as html; 

List<CameraDescription>? cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    cameras = await availableCameras();
  } catch (e) {
    print("Kamera hatası: $e");
  }
  runApp(const FotoKabinApp());
}

class FotoKabinApp extends StatelessWidget {
  const FotoKabinApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Retro Foto Kabin',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF1A1A1A),
        colorScheme: const ColorScheme.dark(primary: Colors.redAccent),
      ),
      home: const KabinEkrani(),
    );
  }
}

class KabinEkrani extends StatefulWidget {
  const KabinEkrani({super.key});

  @override
  State<KabinEkrani> createState() => _KabinEkraniState();
}

class _KabinEkraniState extends State<KabinEkrani> {
  CameraController? controller;
  bool isCameraReady = false;
  
  List<XFile> capturedImages = []; 
  bool isShooting = false; 
  String? countdownText;
  
  // YENİ: Flaş Efekti için değişken
  bool showFlash = false;

  // YENİ: Seçilen şerit rengi (Varsayılan Beyaz)
  Color selectedStripColor = Colors.white;
  
  Uint8List? finalStripData; 
  bool isProcessing = false;

  @override
  void initState() {
    super.initState();
    initCamera();
  }

  void initCamera() {
    if (cameras == null || cameras!.isEmpty) return;
    controller = CameraController(cameras![0], ResolutionPreset.high);
    controller!.initialize().then((_) {
      if (!mounted) return;
      setState(() {
        isCameraReady = true;
      });
    });
  }

  Future<void> startPhotobooth() async {
    setState(() {
      isShooting = true;
      capturedImages.clear();
      finalStripData = null;
    });

    // 3 Kere Fotoğraf Çekme Döngüsü
    for (int i = 0; i < 3; i++) {
      // Geri Sayım
      for (int c = 3; c > 0; c--) {
        setState(() => countdownText = "$c");
        await Future.delayed(const Duration(seconds: 1));
      }
      
      // EMOJİ YERİNE FLAŞ EFEKTİ ⚡
      setState(() {
        countdownText = null; // Yazıyı kaldır
        showFlash = true;     // Beyaz ekranı aç
      });
      
      // 150 milisaniye bekle (Flaş süresi)
      await Future.delayed(const Duration(milliseconds: 150));

      try {
        final image = await controller!.takePicture();
        capturedImages.add(image);
        
        // Flaşı kapat ve önizlemeyi güncelle
        setState(() {
          showFlash = false; 
        });
        
      } catch (e) {
        print("Hata: $e");
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }

    setState(() {
      isShooting = false;
      isProcessing = true; 
    });

    await createAndShowStrip();
    
    setState(() {
      isProcessing = false;
    });
  }

  Future<void> createAndShowStrip() async {
    if (capturedImages.isEmpty) return;

    List<img.Image> loadedImages = [];
    for (var xfile in capturedImages) {
      final bytes = await xfile.readAsBytes();
      final decodedImg = img.decodeImage(bytes);
      if (decodedImg != null) {
        loadedImages.add(decodedImg); 
      }
    }
    if (loadedImages.isEmpty) return;

    int singleWidth = loadedImages[0].width;
    int singleHeight = loadedImages[0].height;
    int border = 50; 
    int gap = 20; 
    int footerHeight = 80; 

    int totalWidth = singleWidth + (border * 2);
    int totalHeight = (singleHeight * 3) + (gap * 2) + (border * 2) + footerHeight;

    img.Image stripCanvas = img.Image(width: totalWidth, height: totalHeight);
    
    // YENİ: Kullanıcının seçtiği rengi burada kullanıyoruz
    img.fill(stripCanvas, color: img.ColorRgb8(
      selectedStripColor.red, 
      selectedStripColor.green, 
      selectedStripColor.blue
    ));

    // Film Delikleri
    int holeWidth = 25;
    int holeHeight = 18;
    int holeMargin = 12; 
    int holeSpacing = 35; 
    
    // Delik rengi (Eğer arka plan siyahsa delikler beyaz olsun, yoksa siyah)
    final holeColor = selectedStripColor == Colors.black 
        ? img.ColorRgb8(255, 255, 255) 
        : img.ColorRgb8(0, 0, 0);

    for (int y = holeSpacing; y < totalHeight - holeSpacing; y += holeSpacing + holeHeight) {
       img.fillRect(stripCanvas, 
          x1: holeMargin, y1: y, 
          x2: holeMargin + holeWidth, y2: y + holeHeight, 
          color: holeColor);
       
       img.fillRect(stripCanvas, 
          x1: totalWidth - holeMargin - holeWidth, y1: y, 
          x2: totalWidth - holeMargin, y2: y + holeHeight, 
          color: holeColor);
    }

    // Fotoları yapıştır
    int currentY = border;
    for (var imgToDraw in loadedImages) {
      img.compositeImage(stripCanvas, imgToDraw, dstX: border, dstY: currentY);
      currentY += singleHeight + gap;
    }

    // Tarih Damgası
    String dateText = "${DateTime.now().toString().substring(0, 10)}";
    img.BitmapFont font = img.arial24; 
    
    img.drawString(stripCanvas, dateText, 
        font: font, 
        x: border, 
        y: totalHeight - 60, 
        color: holeColor); // Yazı rengi de delik rengiyle aynı olsun

    setState(() {
      finalStripData = img.encodeJpg(stripCanvas, quality: 95);
    });
  }

  void downloadStripWeb() {
    if (finalStripData == null || !kIsWeb) return;
    final blob = html.Blob([finalStripData!], 'image/jpeg');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute("download", "fotokabin_hatirasi.jpg")
      ..click(); 
    html.Url.revokeObjectUrl(url); 
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("🎞️ Retro Start-Up Kabini")),
      body: Row(
        children: [
          // SOL TARAF (KAMERA ve KONTROLLER)
          Expanded(
            flex: 2,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // KAMERA ALANI
                Container(
                  width: 500,
                  height: 375,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white, width: 5),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: isCameraReady
                      ? Stack(
                          alignment: Alignment.center,
                          children: [
                            CameraPreview(controller!),
                            
                            // FLAŞ KATMANI (Görünürse ekranı beyaz yapar)
                            if (showFlash)
                              Container(color: Colors.white),

                            // GERİ SAYIM YAZISI
                            if (countdownText != null)
                              Text(
                                countdownText!,
                                style: const TextStyle(
                                  fontSize: 80, 
                                  fontWeight: FontWeight.bold, 
                                  color: Colors.white,
                                  shadows: [Shadow(blurRadius: 10, color: Colors.black)]
                                ),
                              )
                          ],
                        )
                      : const Center(child: CircularProgressIndicator()),
                ),
                
                const SizedBox(height: 20),

                // RENK SEÇİCİ (Sadece çekim yapılmıyorken göster)
                if (!isShooting && !isProcessing) ...[
                  const Text("Şerit Rengini Seç:", style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _colorOption(Colors.white),
                      _colorOption(Colors.black),
                      _colorOption(Colors.pinkAccent),
                      _colorOption(Colors.blueAccent),
                      _colorOption(const Color(0xFFFFF59D)), // Krem/Sarı
                    ],
                  ),
                  const SizedBox(height: 20),
                ],

                // BAŞLAT BUTONU
                if (!isShooting && !isProcessing)
                  ElevatedButton.icon(
                    onPressed: startPhotobooth,
                    icon: const Icon(Icons.camera_alt, size: 28),
                    label: const Text("FOTOĞRAF ÇEKMEYE BAŞLA", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 22),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                      elevation: 10,
                    ),
                  ),
                  
                  if (isProcessing)
                    const Text("Film banyo ediliyor... 🎞️", style: TextStyle(color: Colors.white, fontSize: 18)),
              ],
            ),
          ),

          // SAĞ TARAF (SONUÇ)
          Expanded(
            flex: 1,
            child: Container(
              color: Colors.grey[900],
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("ÖNİZLEME", style: TextStyle(color: Colors.white54, letterSpacing: 2)),
                  const SizedBox(height: 20),
                  
                  Expanded(
                    child: Center(
                      child: finalStripData != null
                          ? Image.memory(finalStripData!) 
                          : Container(
                              width: 200,
                              height: 400,
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade800),
                                borderRadius: BorderRadius.circular(10),
                                color: Colors.white10
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Icon(Icons.photo_library_outlined, size: 50, color: Colors.white24),
                                  SizedBox(height: 10),
                                  Text("Henüz çekim yapılmadı", style: TextStyle(color: Colors.white24)),
                                ],
                              ),
                            ),
                    ),
                  ),
                  
                  const SizedBox(height: 20),
                  
                  if (finalStripData != null)
                    ElevatedButton.icon(
                      onPressed: downloadStripWeb,
                      icon: const Icon(Icons.download_rounded),
                      label: const Text("KAYDET VE İNDİR"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.greenAccent[700],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 18),
                      ),
                    ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Renk seçimi için yuvarlak buton widget'ı
  Widget _colorOption(Color color) {
    bool isSelected = selectedStripColor == color;
    return GestureDetector(
      onTap: () {
        setState(() {
          selectedStripColor = color;
        });
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: isSelected ? Border.all(color: Colors.redAccent, width: 4) : Border.all(color: Colors.grey, width: 1),
          boxShadow: [if(isSelected) BoxShadow(color: Colors.redAccent.withOpacity(0.5), blurRadius: 10)],
        ),
      ),
    );
  }
}