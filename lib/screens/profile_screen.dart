import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb, mapEquals;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/user_service_e2ee.dart';
import '../services/theme_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final ImagePicker _picker = ImagePicker();

  bool _isLoading = false;
  bool _isUploading = false;
  bool _isFetchingProfile = false;
  Map<String, dynamic>? _userData;

  @override
  void initState() {
    super.initState();
    final user = _auth.currentUser;
    if (user != null) {
      _userData = {
        'displayName': user.displayName ?? '',
        'photoUrl': user.photoURL ?? '',
      };
    }
    final cached = UserService().cachedUserData;
    if (cached != null) {
      _userData = {
        ..._userData ?? {},
        ...cached,
      };
    }
    UserService().loadCachedProfile().then((cachedProfile) {
      if (!mounted || cachedProfile == null) return;
      setState(() {
        _userData = {
          ..._userData ?? {},
          ...cachedProfile,
        };
      });
    });
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final user = _auth.currentUser;
    if (user == null) return;
    if (_isFetchingProfile) return;
    _isFetchingProfile = true;

    try {
      final cachedDoc = await _firestore
          .collection('users')
          .doc(user.uid)
          .get(const GetOptions(source: Source.cache));
      final hasCache = cachedDoc.exists;
      if (hasCache) {
        _applyUserData(cachedDoc.data());
      }

      if (!Platform.isWindows || !hasCache) {
        final doc = await _firestore.collection('users').doc(user.uid).get();
        if (doc.exists) {
          _applyUserData(doc.data());
        }
      }
    } catch (e) {
      print('Error loading user data: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      _isFetchingProfile = false;
    }
  }

  void _applyUserData(Map<String, dynamic>? data) {
    if (data == null) return;
    final merged = {
      ..._userData ?? {},
      ...data,
    };

    if (!mapEquals(_userData, merged)) {
      if (mounted) {
        setState(() {
          _userData = merged;
        });
      } else {
        _userData = merged;
      }
    }
  }

  Future<void> _pickAndUploadImage(ImageSource source) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      await user.getIdToken(true);
      await user.reload();
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 75,
      );

      if (image == null) return;

      setState(() => _isUploading = true);

      // Upload to Firebase Storage
      final ref = _storage.ref().child('profile_pictures/${user.uid}');
      final uploadTask = await ref.putFile(
        File(image.path),
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final downloadUrl = await uploadTask.ref.getDownloadURL();

      // Update Firestore
      await _firestore.collection('users').doc(user.uid).update({
        'photoUrl': downloadUrl,
      });

      // Update Firebase Auth
      await user.updatePhotoURL(downloadUrl);
      await user.reload();

      // Reload user data
      await _loadUserData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile picture updated!')),
        );
      }
    } catch (e) {
      final message = e is FirebaseException && e.code == 'unauthorized'
          ? 'Not authorized to upload. Please re-login or verify your email.'
          : 'Error: ${e.toString()}';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } finally {
      setState(() => _isUploading = false);
    }
  }

  void _showImageSourceDialog() {
    // For desktop/web, use file picker directly
    if (kIsWeb || Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      showModalBottomSheet(
        context: context,
        builder: (context) => SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.folder_open),
                title: const Text('Choose from Files'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImageFromFiles();
                },
              ),
              if (_userData?['photoUrl'] != null)
                ListTile(
                  leading: const Icon(Icons.delete, color: Colors.red),
                  title: const Text('Remove Photo', style: TextStyle(color: Colors.red)),
                  onTap: () {
                    Navigator.pop(context);
                    _removeProfilePicture();
                  },
                ),
            ],
          ),
        ),
      );
    } else {
      // Mobile - show camera and gallery options
      showModalBottomSheet(
        context: context,
        builder: (context) => SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('Take Photo'),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndUploadImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose from Gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndUploadImage(ImageSource.gallery);
                },
              ),
              if (_userData?['photoUrl'] != null)
                ListTile(
                  leading: const Icon(Icons.delete, color: Colors.red),
                  title: const Text('Remove Photo', style: TextStyle(color: Colors.red)),
                  onTap: () {
                    Navigator.pop(context);
                    _removeProfilePicture();
                  },
                ),
            ],
          ),
        ),
      );
    }
  }

  // NEW: Pick image from files (for desktop)
  Future<void> _pickImageFromFiles() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      await user.getIdToken(true);
      await user.reload();
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      
      setState(() => _isUploading = true);

      // Upload to Firebase Storage
      final ref = _storage.ref().child('profile_pictures/${user.uid}');
      
      UploadTask uploadTask;
      if (file.path != null) {
        uploadTask = ref.putFile(
          File(file.path!),
          SettableMetadata(contentType: 'image/*'),
        );
      } else if (file.bytes != null) {
        uploadTask = ref.putData(
          file.bytes!,
          SettableMetadata(contentType: 'image/*'),
        );
      } else {
        throw Exception('Selected file has no data');
      }
      
      final uploadResult = await uploadTask;
      final downloadUrl = await uploadResult.ref.getDownloadURL();

      // Update Firestore
      await _firestore.collection('users').doc(user.uid).update({
        'photoUrl': downloadUrl,
      });

      // Update Firebase Auth
      await user.updatePhotoURL(downloadUrl);
      await user.reload();

      // Reload user data
      await _loadUserData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile picture updated!')),
        );
      }
    } catch (e) {
      final message = e is FirebaseException && e.code == 'unauthorized'
          ? 'Not authorized to upload. Please re-login or verify your email.'
          : 'Error: ${e.toString()}';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } finally {
      setState(() => _isUploading = false);
    }
  }

  Future<void> _removeProfilePicture() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      setState(() => _isUploading = true);

      // Delete from Storage
      try {
        final ref = _storage.ref().child('profile_pictures/${user.uid}');
        await ref.delete();
      } catch (e) {
        print('No profile picture to delete: $e');
      }

      // Update Firestore
      await _firestore.collection('users').doc(user.uid).update({
        'photoUrl': FieldValue.delete(),
      });

      // Update Firebase Auth
      await user.updatePhotoURL(null);
      await user.reload();

      await _loadUserData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile picture removed')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    } finally {
      setState(() => _isUploading = false);
    }
  }

  void _editDisplayName() {
    final controller = TextEditingController(
      text: _userData?['displayName'] ?? '',
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Name'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Display Name',
            hintText: 'Enter your name',
          ),
          textCapitalization: TextCapitalization.words,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Name cannot be empty')),
                );
                return;
              }

              Navigator.pop(context);
              await _updateDisplayName(newName);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _updateDisplayName(String newName) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      setState(() => _isLoading = true);

      await _firestore.collection('users').doc(user.uid).update({
        'displayName': newName,
      });

      await user.updateDisplayName(newName);
      await user.reload();

      await _loadUserData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Name updated!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _editBio() {
    final controller = TextEditingController(
      text: _getBio(),
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Bio'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Bio',
            hintText: 'Tell something about you',
          ),
          maxLength: 200,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final newBio = controller.text.trim();
              Navigator.pop(context);
              await _updateBio(newBio);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _updateBio(String newBio) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      setState(() => _isLoading = true);

      if (newBio.isEmpty) {
        await _firestore.collection('users').doc(user.uid).update({
          'bio': FieldValue.delete(),
        });
      } else {
        await _firestore.collection('users').doc(user.uid).update({
          'bio': newBio,
        });
      }

      await _loadUserData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(newBio.isEmpty ? 'Bio removed' : 'Bio updated!'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _editLocation() {
    final controller = TextEditingController(
      text: _userData?['location'] ?? '',
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Location'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Location',
            hintText: 'City, Country',
          ),
          textCapitalization: TextCapitalization.words,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final newLocation = controller.text.trim();
              Navigator.pop(context);
              await _updateLocation(newLocation);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _updateLocation(String newLocation) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      setState(() => _isLoading = true);

      if (newLocation.isEmpty) {
        await _firestore.collection('users').doc(user.uid).update({
          'location': FieldValue.delete(),
        });
      } else {
        await _firestore.collection('users').doc(user.uid).update({
          'location': newLocation,
        });
      }

      await _loadUserData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(newLocation.isEmpty ? 'Location removed' : 'Location updated!'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  List<Map<String, String>> _getSocialLinks() {
    final raw = _userData?['socialLinks'];
    if (raw is! List) return [];

    final result = <Map<String, String>>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item as Map);
      final platform = map['platform']?.toString() ?? '';
      final url = map['url']?.toString() ?? '';
      if (platform.trim().isEmpty && url.trim().isEmpty) continue;
      result.add({
        'platform': platform.trim(),
        'url': url.trim(),
      });
    }
    if (result.isEmpty) {
      final legacyWebsite = _userData?['website']?.toString() ?? '';
      if (legacyWebsite.trim().isNotEmpty) {
        result.add({
          'platform': 'Website',
          'url': legacyWebsite.trim(),
        });
      }
    }
    return result;
  }

  void _editSocialLinks() {
    final links = _getSocialLinks();
    if (links.isEmpty) {
      links.add({'platform': '', 'url': ''});
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Other Social Media'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (int i = 0; i < links.length; i++) ...[
                    TextFormField(
                      initialValue: links[i]['platform'],
                      decoration: const InputDecoration(
                        labelText: 'Platform',
                        hintText: 'YouTube, Steam, Facebook',
                      ),
                      onChanged: (value) {
                        links[i]['platform'] = value;
                      },
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      initialValue: links[i]['url'],
                      decoration: const InputDecoration(
                        labelText: 'Link or handle',
                        hintText: 'https://... or @username',
                      ),
                      keyboardType: TextInputType.url,
                      onChanged: (value) {
                        links[i]['url'] = value;
                      },
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () {
                          setDialogState(() {
                            if (links.length > 1) {
                              links.removeAt(i);
                            } else {
                              links[0] = {'platform': '', 'url': ''};
                            }
                          });
                        },
                      ),
                    ),
                    if (i != links.length - 1) const Divider(height: 24),
                  ],
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: links.length >= 5
                          ? null
                          : () {
                              setDialogState(() {
                                links.add({'platform': '', 'url': ''});
                              });
                            },
                      icon: const Icon(Icons.add),
                      label: const Text('Add social link'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final cleaned = links
                    .map((e) => {
                          'platform': (e['platform'] ?? '').trim(),
                          'url': (e['url'] ?? '').trim(),
                        })
                    .where((e) => e['platform']!.isNotEmpty || e['url']!.isNotEmpty)
                    .toList();

                Navigator.pop(context);
                await _updateSocialLinks(cleaned);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateSocialLinks(List<Map<String, String>> links) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      setState(() => _isLoading = true);

      if (links.isEmpty) {
        await _firestore.collection('users').doc(user.uid).update({
          'socialLinks': FieldValue.delete(),
        });
      } else {
        await _firestore.collection('users').doc(user.uid).update({
          'socialLinks': links,
        });
      }

      await _loadUserData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Social media updated')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  IconData _iconForPlatform(String platform) {
    final p = platform.toLowerCase();
    if (p.contains('youtube')) return Icons.play_circle_fill;
    if (p.contains('steam')) return Icons.sports_esports;
    if (p.contains('facebook')) return Icons.facebook;
    if (p.contains('instagram')) return Icons.camera_alt;
    if (p == 'x' || p.contains('twitter')) return Icons.alternate_email;
    if (p.contains('tiktok')) return Icons.music_note;
    if (p.contains('github')) return Icons.code;
    if (p.contains('twitch')) return Icons.videogame_asset;
    if (p.contains('discord')) return Icons.forum;
    if (p.contains('linkedin')) return Icons.business;
    return Icons.link;
  }

  String? _resolveSocialUrl(String platform, String input) {
    final raw = input.trim();
    if (raw.isEmpty) return null;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;

    final handle = raw.startsWith('@') ? raw.substring(1) : raw;
    final p = platform.toLowerCase();

    if (p.contains('youtube')) return 'https://www.youtube.com/@$handle';
    if (p.contains('steam')) return 'https://steamcommunity.com/id/$handle';
    if (p.contains('facebook')) return 'https://www.facebook.com/$handle';
    if (p.contains('instagram')) return 'https://www.instagram.com/$handle';
    if (p.contains('tiktok')) return 'https://www.tiktok.com/@$handle';
    if (p == 'x' || p.contains('twitter')) return 'https://x.com/$handle';
    if (p.contains('twitch')) return 'https://www.twitch.tv/$handle';
    if (p.contains('github')) return 'https://github.com/$handle';
    if (p.contains('linkedin')) return 'https://www.linkedin.com/in/$handle';

    if (raw.contains('.')) return 'https://$raw';
    return null;
  }

  String? _faviconUrlForLink(String platform, String input) {
    final resolved = _resolveSocialUrl(platform, input) ?? input;
    final uri = Uri.tryParse(resolved);
    var host = uri?.host ?? '';

    if (host.isEmpty) {
      final p = platform.toLowerCase();
      if (p.contains('youtube')) host = 'www.youtube.com';
      if (p.contains('steam')) host = 'steamcommunity.com';
      if (p.contains('facebook')) host = 'www.facebook.com';
      if (p.contains('instagram')) host = 'www.instagram.com';
      if (p.contains('tiktok')) host = 'www.tiktok.com';
      if (p == 'x' || p.contains('twitter')) host = 'x.com';
      if (p.contains('twitch')) host = 'www.twitch.tv';
      if (p.contains('github')) host = 'github.com';
      if (p.contains('linkedin')) host = 'www.linkedin.com';
    }

    if (host.isEmpty) return null;
    return 'https://www.google.com/s2/favicons?domain=$host&sz=64';
  }

  Widget _buildSocialIcon(Map<String, String> link) {
    final platform = link['platform']?.trim() ?? '';
    final url = link['url']?.trim() ?? '';
    final faviconUrl = _faviconUrlForLink(platform, url);

    if (faviconUrl == null) {
      return Icon(_iconForPlatform(platform));
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: CachedNetworkImage(
        imageUrl: faviconUrl,
        width: 24,
        height: 24,
        fit: BoxFit.cover,
        memCacheWidth: 48,
        memCacheHeight: 48,
        placeholder: (_, __) => Icon(_iconForPlatform(platform)),
        errorWidget: (_, __, ___) => Icon(_iconForPlatform(platform)),
        fadeInDuration: const Duration(milliseconds: 100),
        fadeOutDuration: const Duration(milliseconds: 100),
      ),
    );
  }

  Future<void> _openSocialLink(Map<String, String> link) async {
    final platform = link['platform'] ?? '';
    final url = link['url'] ?? '';
    final resolved = _resolveSocialUrl(platform, url) ?? url;
    if (resolved.trim().isEmpty) return;

    final uri = Uri.tryParse(resolved);
    if (uri == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid link')),
        );
      }
      return;
    }

    final launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );

    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open link')),
      );
    }
  }

  Widget _buildSocialLinkTile(Map<String, String> link) {
    final platform = link['platform']?.trim() ?? '';
    final url = link['url']?.trim() ?? '';
    final title = platform.isEmpty ? 'Link' : platform;

    return ListTile(
      leading: _buildSocialIcon(link),
      title: Text(title),
      subtitle: Text(url.isEmpty ? 'No link' : url),
      trailing: url.isEmpty ? null : const Icon(Icons.open_in_new, size: 16),
      onTap: url.isEmpty ? null : () => _openSocialLink(link),
    );
  }

  List<Widget> _buildSocialLinksSection(List<Map<String, String>> links) {
    final tiles = <Widget>[
      ListTile(
        leading: const Icon(Icons.link),
        title: const Text('Other Social Media'),
        subtitle: Text(
          links.isEmpty ? 'Not set' : 'Tap a link to open',
        ),
        trailing: IconButton(
          icon: const Icon(Icons.edit),
          onPressed: _isLoading ? null : _editSocialLinks,
        ),
      ),
    ];

    for (final link in links) {
      tiles.add(const Divider(height: 1));
      tiles.add(_buildSocialLinkTile(link));
    }

    return tiles;
  }

  Widget _buildAvatar(String? photoUrl, double radius) {
    final placeholder = Container(
      width: radius * 2,
      height: radius * 2,
      color: Colors.grey[300],
      child: Icon(
        Icons.person,
        size: radius,
        color: Colors.grey[600],
      ),
    );

    if (photoUrl == null || photoUrl.isEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: Colors.grey[300],
        child: Icon(
          Icons.person,
          size: radius,
          color: Colors.grey[600],
        ),
      );
    }
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final cacheSize = (radius * 2 * dpr).round().clamp(64, 512);
    // Windows-specific handling to prevent crashes
    if (Platform.isWindows) {
      return ClipOval(
        child: Image.network(
          photoUrl,
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded) return child;
            return AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: const Duration(milliseconds: 150),
              child: frame == null ? placeholder : child,
            );
          },
          errorBuilder: (_, __, ___) => placeholder,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return placeholder;
          },
        ),
      );
    }

    // Use CachedNetworkImage for mobile platforms
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: photoUrl,
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover,
        memCacheWidth: cacheSize,
        memCacheHeight: cacheSize,
        placeholder: (_, __) => placeholder,
        errorWidget: (_, __, ___) => placeholder,
        fadeInDuration: const Duration(milliseconds: 150),
        fadeOutDuration: const Duration(milliseconds: 150),
      ),
    );
  }

  String? _pickPhotoUrl() {
    final candidates = [
      _userData?['photoUrl'],
      _userData?['photoURL'],
      _auth.currentUser?.photoURL,
    ];

    for (final value in candidates) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  String _getBio() {
    final bio = _userData?['bio'] as String?;
    if (bio != null && bio.trim().isNotEmpty) return bio.trim();
    final legacy = _userData?['status'] as String?;
    if (legacy != null) {
      final trimmed = legacy.trim();
      if (trimmed.isNotEmpty && trimmed != 'online' && trimmed != 'offline') {
        return trimmed;
      }
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    final themeService = Provider.of<ThemeService>(context);
    
    final photoUrl = _pickPhotoUrl();
    final displayName = _userData?['displayName'] ?? user?.displayName ?? 'User';
    final email = user?.email ?? '';
    final bio = _getBio();
    final location = _userData?['location'] ?? '';
    final emailVerified = user?.emailVerified ?? false;
    final socialLinks = _getSocialLinks();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: Icon(
              themeService.isDarkMode ? Icons.light_mode : Icons.dark_mode,
            ),
            onPressed: () {
              themeService.toggleTheme();
            },
            tooltip: themeService.isDarkMode ? 'Light Mode' : 'Dark Mode',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
                // Profile Picture Section
                Center(
                  child: Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Theme.of(context).primaryColor,
                            width: 3,
                          ),
                        ),
                        child: _buildAvatar(photoUrl, 70),
                      ),
                      if (_isUploading)
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: const Center(
                              child: CircularProgressIndicator(
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Theme.of(context).primaryColor,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Theme.of(context).scaffoldBackgroundColor,
                              width: 3,
                            ),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.camera_alt, color: Colors.white),
                            onPressed: _isUploading ? null : _showImageSourceDialog,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Name
                Center(
                  child: Text(
                    displayName,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // Status
                Center(
                  child: Text(
                    bio.isEmpty ? 'No bio' : bio,
                    style: TextStyle(
                      fontSize: 16,
                      color: bio.isEmpty ? Colors.grey : null,
                      fontStyle: bio.isEmpty ? FontStyle.italic : null,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 32),

                // Profile Info Card
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.person_outline),
                        title: const Text('Name'),
                        subtitle: Text(displayName),
                        trailing: IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: _isLoading ? null : _editDisplayName,
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.email_outlined),
                        title: const Text('Email'),
                        subtitle: Text(email),
                        trailing: emailVerified
                            ? const Icon(Icons.verified, color: Colors.green)
                            : const Icon(Icons.warning, color: Colors.orange),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.info_outline),
                        title: const Text('Bio'),
                        subtitle: Text(bio.isEmpty ? 'No bio set' : bio),
                        trailing: IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: _isLoading ? null : _editBio,
                        ),
                      ),
                      const Divider(height: 1),
                      ..._buildSocialLinksSection(socialLinks),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.place_outlined),
                        title: const Text('Location'),
                        subtitle: Text(location.isEmpty ? 'Not set' : location),
                        trailing: IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: _isLoading ? null : _editLocation,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Account Section
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Text(
                    'Account',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                ),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.lock_outline),
                        title: const Text('Change Password'),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () {
                          _showChangePasswordDialog();
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.phone_outlined),
                        title: const Text('Phone Number'),
                        subtitle: const Text('Not set'),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Phone number feature coming soon')),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Privacy Section
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Text(
                    'Privacy',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                ),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.visibility_outlined),
                        title: const Text('Profile Visibility'),
                        subtitle: const Text('Everyone'),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Privacy settings coming soon')),
                          );
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.block_outlined),
                        title: const Text('Blocked Users'),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Blocked users list coming soon')),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Danger Zone
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Text(
                    'Danger Zone',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                ),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.delete_forever, color: Colors.red),
                    title: const Text(
                      'Delete Account',
                      style: TextStyle(color: Colors.red),
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.red),
                    onTap: () {
                      _showDeleteAccountDialog();
                    },
                  ),
                ),
        ],
      ),
    );
  }

  void _showChangePasswordDialog() {
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    bool obscureCurrent = true;
    bool obscureNew = true;
    bool obscureConfirm = true;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Change Password'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: currentPasswordController,
                  obscureText: obscureCurrent,
                  decoration: InputDecoration(
                    labelText: 'Current Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(obscureCurrent ? Icons.visibility_off : Icons.visibility),
                      onPressed: () {
                        setDialogState(() => obscureCurrent = !obscureCurrent);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: newPasswordController,
                  obscureText: obscureNew,
                  decoration: InputDecoration(
                    labelText: 'New Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(obscureNew ? Icons.visibility_off : Icons.visibility),
                      onPressed: () {
                        setDialogState(() => obscureNew = !obscureNew);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: confirmPasswordController,
                  obscureText: obscureConfirm,
                  decoration: InputDecoration(
                    labelText: 'Confirm New Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(obscureConfirm ? Icons.visibility_off : Icons.visibility),
                      onPressed: () {
                        setDialogState(() => obscureConfirm = !obscureConfirm);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final current = currentPasswordController.text;
                final newPass = newPasswordController.text;
                final confirm = confirmPasswordController.text;

                if (current.isEmpty || newPass.isEmpty || confirm.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please fill all fields')),
                  );
                  return;
                }

                if (newPass != confirm) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Passwords do not match')),
                  );
                  return;
                }

                if (newPass.length < 6) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Password must be at least 6 characters')),
                  );
                  return;
                }

                Navigator.pop(context);
                await _changePassword(current, newPass);
              },
              child: const Text('Change'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _changePassword(String currentPassword, String newPassword) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      // Re-authenticate user
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: currentPassword,
      );

      await user.reauthenticateWithCredential(credential);
      
      // Update password
      await user.updatePassword(newPassword);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password changed successfully!')),
        );
      }
    } on FirebaseAuthException catch (e) {
      String message = 'Failed to change password';
      if (e.code == 'wrong-password') {
        message = 'Current password is incorrect';
      } else if (e.code == 'weak-password') {
        message = 'New password is too weak';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    }
  }

  void _showDeleteAccountDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Text(
          'Are you sure you want to delete your account? This action cannot be undone and all your data will be permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Account deletion feature coming soon'),
                ),
              );
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
