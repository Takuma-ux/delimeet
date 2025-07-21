import 'package:flutter/material.dart';
import 'search_page.dart';
import 'favorite_stores_page.dart';
import 'match_page.dart';
import 'likes_page.dart';
import 'account_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;

  // 各画面のWidget
  static const List<Widget> _pages = <Widget>[
    SearchPage(),
    FavoriteStoresPage(),
    MatchPage(),
    LikesPage(),
    AccountPage(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.search),
            label: '探す',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.store),
            label: 'お気に入りのお店',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.favorite),
            label: 'マッチ',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.favorite_border),
            label: 'いいね',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'アカウント',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.pink,
        unselectedItemColor: Colors.grey,
        onTap: _onItemTapped,
      ),
    );
  }
} 