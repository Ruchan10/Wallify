import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:wallify/core/user_shared_prefs.dart';
import 'package:wallify/screens/wallpaper_preview.dart';

class DiscoverPage extends StatefulWidget {
  const DiscoverPage({super.key});

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  final TextEditingController _searchController = TextEditingController();
  List<String> _images = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchImages(null); 
  }

  Future<void> _fetchImages(String? query) async {
    setState(() {
      _isLoading = true;
      _images.clear();
    });

    final List<String> results = [];

    try {
      /// 🔹 Wallhaven
      final wallRes = await http.get(Uri.parse(
        "https://wallhaven.cc/api/v1/search?page=1"
      ));
      final wallData = jsonDecode(wallRes.body);
      for (var item in wallData["data"]) {
        results.add(item["path"]);
precacheImage(CachedNetworkImageProvider(item["path"]), context);
      }
      /// 🔹 Unsplash
      final unsplashRes = await http.get(
        Uri.parse(
          "https://api.unsplash.com/photos/random"
          "?count=10",
        ),
        headers: {
          "Authorization":
              "Client-ID yTBcYNAtnRHbrYMn2p4DrBiqzOAfdH9nyexQQtJWO-E",
        },
      );
      final unsplashData = jsonDecode(unsplashRes.body);
      for (var item in unsplashData) {
        results.add(item["urls"]["regular"]);
precacheImage(CachedNetworkImageProvider(item["urls"]["regular"]), context);

      }
      /// 🔹 Pixabay
      final pixabayRes = await http.get(Uri.parse(
        "https://pixabay.com/api/"
        "?key=52028006-a7e910370a5d0158c371bb06a"
        "&image_type=photo"
        "&per_page=10",
      ));
      final pixabayData = jsonDecode(pixabayRes.body);
      for (var item in pixabayData["hits"]) {
        results.add(item["largeImageURL"]);
precacheImage(CachedNetworkImageProvider(item["largeImageURL"]), context);
      }
    } catch (e) {
      debugPrint("❌ Error fetching images: $e ====================");
    }
    setState(() {
      _images = results;
      _isLoading = false;
    });
  }
  final Set<String> favorites = {};


  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      
      appBar: AppBar(
        title: const Text("Discover"),
        elevation: 0,
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          
          spacing: 12,
          children: [
             TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: "Search...",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                ),
                onSubmitted: (value) {
                  if (value.isNotEmpty) {
                    _fetchImages(value);
                  }
                },
              ),
             _images.isEmpty ? const Center(child: Text("No wallpapers")) : Expanded(
                  child: MasonryGridView.count(
                    crossAxisCount: 2,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    itemCount: _images.length,
                    itemBuilder: (context, index) {
                      final img = _images[index];
                      final isFav = favorites.contains(img);
                              
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Stack(
                          children: [
                            GestureDetector(
                              onTap: () {
                                Navigator.push(context, MaterialPageRoute(builder: (context) => WallpaperPreviewPage(imageUrl: img, isFavorite: isFav)));
                              },
                              child: CachedNetworkImage(
                                imageUrl: img,
                                fit: BoxFit.cover,
                                placeholder: (context, url) => Container(
                                  height: 200,
                                  color: Colors.grey[300],
                                  child: const Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                ),
                                errorWidget: (context, url, error) => Container(
                                  height: 200,
                                  color: Colors.grey[200],
                                  child: const Icon(Icons.broken_image, color: Colors.grey),
                                ),
                              ),
                            ),

                              
                              
                      Positioned(
                        top: 8,
                        right: 8,
                        child: IconButton(
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.black45,
                            foregroundColor: isFav
                                ? colorScheme.secondary
                                : colorScheme.onPrimary,
                          ),
                          icon: Icon(
                              isFav ? Icons.favorite : Icons.favorite_border),
                          onPressed: () {
                            setState(() {
                              if (isFav) {
                                favorites.remove(img);
                                UserSharedPrefs.removeFavWallpaper(img);
                              } else {
                                favorites.add(img);
                                UserSharedPrefs.saveFavWallpaper(img);
                              }
                            });
                          },
                        ),
                      ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
