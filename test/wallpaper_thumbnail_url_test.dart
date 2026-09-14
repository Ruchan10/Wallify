import 'package:flutter_test/flutter_test.dart';
import 'package:wallify/model/wallpaper_model.dart';

String thumb(String url) => Wallpaper(id: '1', url: url).thumbnailUrl;

void main() {
  const wallhaven = 'https://w.wallhaven.cc/full/w5/wallhaven-w5xdzx.png';

  test('landscape wallhaven image uses the large thumbnail', () {
    expect(
      Wallpaper(id: '1', url: wallhaven, width: 3840, height: 2160).thumbnailUrl,
      'https://th.wallhaven.cc/lg/w5/w5xdzx.jpg',
    );
  });

  test('portrait or unknown-size wallhaven image keeps its aspect ratio', () {
    expect(
      Wallpaper(id: '1', url: wallhaven, width: 1080, height: 2400).thumbnailUrl,
      'https://th.wallhaven.cc/orig/w5/w5xdzx.jpg',
    );
    expect(thumb(wallhaven), 'https://th.wallhaven.cc/orig/w5/w5xdzx.jpg');
  });

  test('pexels original gets resize parameters', () {
    expect(
      thumb('https://images.pexels.com/photos/2014422/pexels-photo-2014422.jpeg'),
      'https://images.pexels.com/photos/2014422/pexels-photo-2014422.jpeg?auto=compress&cs=tinysrgb&w=800',
    );
  });

  test('unsplash width is replaced and other parameters kept', () {
    final uri = Uri.parse(thumb(
      'https://images.unsplash.com/photo-123?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&q=80&w=1080',
    ));
    expect(uri.queryParameters['w'], '800');
    expect(uri.queryParameters['fit'], 'max');
  });

  test('picsum keeps the aspect ratio', () {
    expect(
      thumb('https://picsum.photos/id/10/2500/1667'),
      'https://picsum.photos/id/10/800/533',
    );
  });

  test('unknown hosts and local paths are unchanged', () {
    const pixabay = 'https://pixabay.com/get/abc_1280.jpg';
    const local = '/storage/emulated/0/Pictures/a.jpg';
    expect(thumb(pixabay), pixabay);
    expect(thumb(local), local);
  });
}
