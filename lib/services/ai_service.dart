import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:wallify/core/user_shared_prefs.dart';

class AiWallpaperService {
  static const _geminiBaseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models';

  static Future<File> generateCustomWallpaper(
    String imageUrl,
    String apiKey,
  ) async {
    final width = await UserSharedPrefs.getDeviceWidth();
    final height = await UserSharedPrefs.getDeviceHeight();

    final imageBytes = await _downloadImageBytes(imageUrl);
    final description = await _analyzeWithGemini(imageBytes, apiKey);
    final resultFile = await _generateWithPollinations(
      description,
      width,
      height,
    );
    return resultFile;
  }

  static Future<Uint8List> _downloadImageBytes(String url) async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception("Failed to download image: HTTP ${response.statusCode}");
    }
    return response.bodyBytes;
  }

  static Future<String> _analyzeWithGemini(
    Uint8List imageBytes,
    String apiKey,
  ) async {
    final base64Image = base64Encode(imageBytes);

    final body = jsonEncode({
      "contents": [
        {
          "parts": [
            {
              "text":
                  "Describe this wallpaper image in extreme detail including: "
                      "the main subjects, artistic style, color palette, "
                      "composition, lighting, mood, textures, patterns, "
                      "and any key visual elements. Be specific and thorough. "
                      "This description will be used as a prompt to recreate "
                      "the image as a mobile wallpaper.",
            },
            {
              "inline_data": {
                "mime_type": "image/jpeg",
                "data": base64Image,
              },
            },
          ],
        },
      ],
    });

    final response = await http.post(
      Uri.parse(
        '$_geminiBaseUrl/gemini-2.5-flash:generateContent?key=$apiKey',
      ),
      headers: {'Content-Type': 'application/json'},
      body: body,
    );

    if (response.statusCode != 200) {
      throw Exception(
        "Gemini Vision error (${response.statusCode}): ${response.body}",
      );
    }

    final data = jsonDecode(response.body);
    final text = data['candidates']?[0]?['content']?['parts']?[0]?['text']
        as String?;

    if (text == null || text.isEmpty) {
      throw Exception("Gemini returned empty description");
    }

    return text;
  }

  static Future<File> _generateWithPollinations(
    String description,
    int width,
    int height,
  ) async {
    final prompt =
        "Mobile wallpaper for ${width}x$height device. "
        "Based on this description, recreate the wallpaper keeping the "
        "same artistic style, color palette, and composition. "
        "Smart crop and fill to perfectly fit the ${width}x$height screen. "
        "Enhance quality. Description: $description";

    final encodedPrompt = Uri.encodeComponent(prompt);
    final url =
        'https://image.pollinations.ai/prompt/$encodedPrompt'
        '?width=$width&height=$height'
        '&model=flux&nologo=true&enhance=true';

    final response = await http.get(Uri.parse(url));

    if (response.statusCode != 200) {
      throw Exception(
        "Pollinations error (${response.statusCode}): ${response.body}",
      );
    }

    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/ai_magic_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    await file.writeAsBytes(response.bodyBytes);
    return file;
  }
}
