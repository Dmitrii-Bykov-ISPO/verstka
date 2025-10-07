import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}
class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}
class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  int _currentIndex = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  void _goHome(BuildContext context) { //Дмой
    Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
  }
  void _onBottomTap(int idx) {
    setState(() {
      _currentIndex = idx;
    });
  }
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      routes: {//пути для перехода
        '/': (context) => HomeScreen(
          onHomePressed: () => _goHome(context),
        ),
        '/photo': (context) => const PhotoViewScreen(),
      },
      initialRoute: '/',
    );
  }
}
class HomeScreen extends StatefulWidget {
  final VoidCallback onHomePressed;
  const HomeScreen({super.key, required this.onHomePressed});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}
class _HomeScreenState extends State<HomeScreen> {
  final List<PostData> posts = [
    PostData(
      profileAsset: 'assets/profile2.jpg',
      name: 'Казенов Эдуард',
      time: '2 часа назад',
      caption: 'Красота то какая! Ляпота!🌅 -  © Казенов Эдуард ',
      photos: ['assets/photo3.jpg'],
    ),
    PostData(
      profileAsset: 'assets/profile1.jpg',
      name: 'Мельник Сергий',
      time: '3 часа назад',
      caption: 'Поход в лес! 🌳🏔️🌲',
      photos: ['assets/photo1.jpg', 'assets/photo2.jpg'],
    ),
    PostData(
      profileAsset: 'assets/profile2.jpg',
      name: 'Казенов Эдуард',
      time: '5 часов назад',
      caption: 'Мой отдых 🌊🌊🌊',
      photos: ['assets/photo4.jpg', 'assets/photo5.jpg', 'assets/photo21.jpg'],
    ),
    PostData(
      profileAsset: 'assets/profile1.jpg',
      name: 'Мельник Сергий',
      time: '12 часов назад',
      caption: 'Красиво, однако!',
      photos: ['assets/photo6.jpg', 'assets/photo7.jpg', 'assets/photo8.jpg', 'assets/photo9.jpg', 'assets/photo24.jpg', 'assets/photo25.jpg'],
    ),
  ];
  Widget buildBottomBar(BuildContext context) {
    return BottomAppBar(
      shape: const CircularNotchedRectangle(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.home),
                  onPressed: () => Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false),
                ),
                IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Поиск (заглушка)')));
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.person),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Профиль (заглушка)')));
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5EEDC),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppHeader(),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: InfoCard(
                          icon: Icons.notifications,
                          iconColor: Colors.yellow,
                          title: '10 новостей',
                        ),
                      ),
                      Expanded(
                        child: InfoCard(
                          icon: Icons.event,
                          iconColor: Colors.green,
                          title: '15 событий',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  for (var p in posts) ...[
                    PostCard.buildFromData(
                      context: context,
                      profileAsset: p.profileAsset,
                      name: p.name,
                      time: p.time,
                      caption: p.caption,
                      photos: p.photos,
                    ),
                    const SizedBox(height: 16),
                  ],
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: buildBottomBar(context),
    );
  }
}
class AppHeader extends StatelessWidget {
  const AppHeader({super.key});
  @override
  Widget build(BuildContext context) {
    final int hour = DateTime.now().hour;
    String greeting;
    if (hour >= 4 && hour < 12) {
      greeting = 'Доброе утро! ';
    } else if (hour >= 12 && hour < 17) {
      greeting = 'Добрый день! ';
    } else if (hour >= 17 && hour < 22) {
      greeting = 'Добрый вечер! ';
    } else {
      greeting = 'Доброй ночи! ';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '$greeting Дмитрий!',
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          GestureDetector(
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Открыть профиль (заглушка)')),
              );
            },
            child: const CircleAvatar(
              radius: 50,
              backgroundImage: AssetImage('assets/profile0.jpg'),
            ),
          ),
        ],
      ),
    );
  }
}
class InfoCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  const InfoCard({super.key, required this.icon, required this.iconColor, required this.title});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor),
          const SizedBox(height: 8),
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
class PostData {// PostData — структура данных для поста
  final String profileAsset;
  final String name;
  final String time;
  final String caption;
  final List<String> photos;
  PostData({required this.profileAsset, required this.name, required this.time, required this.caption, required this.photos});
}
class PostCard extends StatelessWidget {// PostCard — вынесенная функция/виджет с параметрами (конструктор-подход)
// Пост создается через PostCard.buildFromData
  final String profileAsset;
  final String name;
  final String time;
  final String caption;
  final List<String> photos;
  const PostCard({
    super.key,
    required this.profileAsset,
    required this.name,
    required this.time,
    required this.caption,
    required this.photos,
  });
  static Widget buildFromData({
    required BuildContext context,
    required String profileAsset,
    required String name,
    required String time,
    required String caption,
    required List<String> photos,
  }) {
    return PostCard(
      profileAsset: profileAsset,
      name: name,
      time: time,
      caption: caption,
      photos: photos,
    );
  }
  void _openPhoto(BuildContext context, String photoAsset) {  // Вспомогательная функция для обработки нажатия на фото - переходит на экран с полноэкранной фотографией
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => PhotoViewScreen(imageAsset: photoAsset)));
  }
  Widget _buildPhotosLayout(BuildContext context) {  // расположение фото в зависимости от их количества
    if (photos.isEmpty) {
      return const SizedBox.shrink();
    }
    if (photos.length == 1) {
      return GestureDetector(
        onTap: () => _openPhoto(context, photos[0]),
        child: Container(
          height: 500,
          decoration: BoxDecoration(
            color: Colors.grey[300],
            borderRadius: BorderRadius.circular(15),
            image: DecorationImage(image: AssetImage(photos[0]), fit: BoxFit.cover),
          ),
        ),
      );
    }
    if (photos.length == 2) {
      return Row(
        children: photos.map((p) {
          return Expanded(
            child: GestureDetector(
              onTap: () => _openPhoto(context, p),
              child: Container(
                height: 500,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(15),
                  image: DecorationImage(image: AssetImage(p), fit: BoxFit.cover),
                ),
              ),
            ),
          );
        }).toList(),
      );
    }
    if (photos.length == 3) {// Три фотографии — большой слева и две справа
      return Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => _openPhoto(context, photos[0]),
              child: Container(
                height: 500,
                margin: const EdgeInsets.only(right: 4),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(15),
                  image: DecorationImage(image: AssetImage(photos[0]), fit: BoxFit.cover),
                ),
              ),
            ),
          ),
          Expanded(
            child: Column(
              children: [
                GestureDetector(
                  onTap: () => _openPhoto(context, photos[1]),
                  child: Container(
                    height: 240,
                    margin: const EdgeInsets.only(bottom: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(15),
                      image: DecorationImage(image: AssetImage(photos[1]), fit: BoxFit.cover),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => _openPhoto(context, photos[2]),
                  child: Container(
                    height: 240,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(15),
                      image: DecorationImage(image: AssetImage(photos[2]), fit: BoxFit.cover),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }
    return GridView.builder(    // Больше 3 — показываем Grid
    physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, crossAxisSpacing: 4, mainAxisSpacing: 4),
      itemCount: photos.length,
      itemBuilder: (context, index) {
        final p = photos[index];
        return GestureDetector(
          onTap: () => _openPhoto(context, p),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(8),
              image: DecorationImage(image: AssetImage(p), fit: BoxFit.cover),
            ),
          ),
        );
      },
    );
  }
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(radius: 24, backgroundImage: AssetImage(profileAsset)),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(time, style: const TextStyle(color: Colors.grey)),
          ]),
          const Spacer(),
          const Icon(Icons.more_vert),
        ]),
        const SizedBox(height: 12),
        Text(caption, style: const TextStyle(fontSize: 16)),
        const SizedBox(height: 12),
        _buildPhotosLayout(context),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: const [
          Icon(Icons.favorite_border),
          Icon(Icons.chat_bubble_outline),
          Icon(Icons.share),
        ])
      ]),
    );
  }
}
// PhotoViewScreen — экран для показа фото на весь экран
class PhotoViewScreen extends StatelessWidget {
  final String? imageAsset;
  const PhotoViewScreen({super.key, this.imageAsset});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Если imageAsset == null — пустой экран
            if (imageAsset != null)
              Center(
                child: InteractiveViewer(
                  child: Image.asset(imageAsset!, fit: BoxFit.contain),
                ),
              )
            else
              const Center(child: Text('Нет изображения', style: TextStyle(color: Colors.white))),
            // Нижняя панель — две кнопки: Домой и Назад
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                color: Colors.black54,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.home, color: Colors.white),
                      onPressed: () => Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false),
                    ),
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () {
                        if (Navigator.of(context).canPop()) {
                          Navigator.of(context).pop();
                        }
                      },
                    ),
                  ],
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}