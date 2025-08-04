import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import '../models/restaurant_model.dart';
import '../services/web_image_helper.dart';

class BadgePhotoSetupPage extends StatefulWidget {
  final Restaurant restaurant;
  
  const BadgePhotoSetupPage({
    super.key,
    required this.restaurant,
  });

  @override
  State<BadgePhotoSetupPage> createState() => _BadgePhotoSetupPageState();
}

class _BadgePhotoSetupPageState extends State<BadgePhotoSetupPage> {
  final List<File?> _selectedPhotos = List.filled(9, null);
  final List<String?> _photoUrls = List.filled(9, null);
  bool _isLoading = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadExistingPhotos();
  }

  Future<void> _loadExistingPhotos() async {
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('getUserBadgePhotos');
      final result = await callable.call({});
      
      final photos = List<Map<String, dynamic>>.from(result.data['photos'] ?? []);
      
      // 現在のレストランの写真のみを抽出
      for (final photo in photos) {
        if (photo['restaurant_id'] == widget.restaurant.id) {
          final order = photo['photo_order'] as int;
          if (order >= 1 && order <= 9) {
            setState(() {
              _photoUrls[order - 1] = photo['photo_url'];
            });
          }
        }
      }
    } catch (e) {
    }
  }

  Future<void> _pickImage(int index) async {
    try {
      final ImagePicker picker = ImagePicker();
      
      showModalBottomSheet(
        context: context,
        builder: (BuildContext context) {
          return SafeArea(
            child: Wrap(
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_library),
                  title: const Text('ギャラリーから選択'),
                  onTap: () async {
                    Navigator.pop(context);
                    await _selectImage(index, ImageSource.gallery);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_camera),
                  title: const Text('カメラで撮影'),
                  onTap: () async {
                    Navigator.pop(context);
                    await _selectImage(index, ImageSource.camera);
                  },
                ),
                if (_photoUrls[index] != null)
                  ListTile(
                    leading: const Icon(Icons.delete, color: Colors.red),
                    title: const Text('削除', style: TextStyle(color: Colors.red)),
                    onTap: () async {
                      Navigator.pop(context);
                      await _deletePhoto(index);
                    },
                  ),
              ],
            ),
          );
        },
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('画像の選択に失敗しました: $e')),
      );
    }
  }

  Future<void> _selectImage(int index, ImageSource source) async {
    try {
      setState(() {
        _isLoading = true;
      });

      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );

      if (image != null) {
        final File imageFile = File(image.path);
        final String photoUrl = await _uploadImage(imageFile, index);
        
        setState(() {
          _selectedPhotos[index] = imageFile;
          _photoUrls[index] = photoUrl;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('画像の選択に失敗しました: $e')),
      );
    }
  }

  Future<String> _uploadImage(File imageFile, int index) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('ユーザーが認証されていません');

      final fileName = 'badge_photo_${user.uid}_${widget.restaurant.id}_$index.jpg';
      final ref = FirebaseStorage.instance.ref().child('badge_photos/$fileName');
      
      final uploadTask = ref.putFile(imageFile);
      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();
      
      return downloadUrl;
    } catch (e) {
      throw Exception('画像のアップロードに失敗しました');
    }
  }

  Future<void> _deletePhoto(int index) async {
    try {
      if (_photoUrls[index] == null) return;

      setState(() {
        _isLoading = true;
      });

      // Cloud Functionsでバッジ写真を削除
      final callable = FirebaseFunctions.instance.httpsCallable('deleteBadgePhoto');
      await callable.call({'photoId': _photoUrls[index]});

      setState(() {
        _selectedPhotos[index] = null;
        _photoUrls[index] = null;
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('写真を削除しました')),
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('写真の削除に失敗しました: $e')),
      );
    }
  }

  Future<void> _saveBadgePhotos() async {
    try {
      setState(() {
        _isSaving = true;
      });

      final callable = FirebaseFunctions.instance.httpsCallable('setBadgePhoto');
      
      // 設定された写真を保存
      for (int i = 0; i < 9; i++) {
        if (_photoUrls[i] != null) {
          await callable.call({
            'restaurantId': widget.restaurant.id,
            'photoUrl': _photoUrls[i],
            'photoOrder': i + 1,
          });
        }
      }

      setState(() {
        _isSaving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('バッジ写真を保存しました'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _isSaving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('バッジ写真の保存に失敗しました: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildPhotoGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      itemCount: 9,
      itemBuilder: (context, index) {
        return _buildPhotoCell(index);
      },
    );
  }

  Widget _buildPhotoCell(int index) {
    final photoUrl = _photoUrls[index];
    final selectedPhoto = _selectedPhotos[index];

    return GestureDetector(
      onTap: () => _pickImage(index),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: photoUrl != null ? Colors.green : Colors.grey[300]!,
            width: photoUrl != null ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: Stack(
            children: [
              // 写真表示
              if (photoUrl != null)
                Positioned.fill(
                  child: kIsWeb
                      ? Image.network(
                          photoUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: Colors.grey[200],
                              child: const Icon(Icons.error, color: Colors.grey),
                            );
                          },
                        )
                      : Image.file(
                          selectedPhoto!,
                          fit: BoxFit.cover,
                        ),
                )
              else if (selectedPhoto != null)
                Positioned.fill(
                  child: Image.file(
                    selectedPhoto,
                    fit: BoxFit.cover,
                  ),
                )
              else
                Container(
                  color: Colors.grey[100],
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.add_a_photo,
                        color: Colors.grey[400],
                        size: 32,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${index + 1}',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              
              // 設定済みマーク
              if (photoUrl != null)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check,
                      color: Colors.white,
                      size: 12,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.restaurant.name}のバッジ写真'),
        backgroundColor: const Color(0xFFFFEFD5),
        foregroundColor: Colors.white,
        actions: [
          if (_photoUrls.any((url) => url != null))
            TextButton(
              onPressed: _isSaving ? null : _saveBadgePhotos,
              child: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      '保存',
                      style: TextStyle(color: Colors.white),
                    ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // レストラン情報
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          if (widget.restaurant.imageUrl != null)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: SizedBox(
                                width: 60,
                                height: 60,
                                child: Image.network(
                                  widget.restaurant.imageUrl!,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.restaurant.name,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (widget.restaurant.category != null)
                                  Text(
                                    widget.restaurant.category!,
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 14,
                                    ),
                                  ),
                                if (widget.restaurant.prefecture != null)
                                  Text(
                                    widget.restaurant.prefecture!,
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 14,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // 説明
                  const Text(
                    'バッジ写真について',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'このレストランで撮影した写真を9枚まで設定できます。\n'
                    '設定した写真は、このレストランの詳細画面で地元案内人として表示されます。',
                    style: TextStyle(fontSize: 14),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // 写真グリッド
                  _buildPhotoGrid(),
                  
                  const SizedBox(height: 24),
                  
                  // 注意事項
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.info, color: Colors.orange[700], size: 16),
                            const SizedBox(width: 8),
                            Text(
                              '注意事項',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.orange[700],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '• このレストランで実際に撮影した写真を設定してください\n'
                          '• 不適切な写真は削除される場合があります\n'
                          '• 写真は公開されますので、個人情報が含まれていないことを確認してください',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
} 