import 'package:flutter/material.dart';
import 'package:careasy_app_mobile/utils/constants.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _storage = const FlutterSecureStorage();
  Map<String, dynamic>? _userData;
  bool _isLoading = true;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final userDataString = await _storage.read(key: 'user_data');
      if (userDataString != null) {
        setState(() {
          _userData = jsonDecode(userDataString);
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Erreur chargement user data: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _logout() async {
    await _storage.delete(key: 'auth_token');
    await _storage.delete(key: 'user_data');
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final userName = _userData?['name'] ?? 'Utilisateur';
    final size = MediaQuery.of(context).size;
    final bool isSmallScreen = size.width < 360;

    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                // App Bar personnalisée
                SliverAppBar(
                  expandedHeight: 120,
                  floating: false,
                  pinned: true,
                  backgroundColor: AppConstants.primaryRed,
                  flexibleSpace: FlexibleSpaceBar(
                    title: Text(
                      'Bonjour, $userName',
                      style: TextStyle(
                        fontSize: isSmallScreen ? 16 : 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    background: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppConstants.primaryRed,
                            AppConstants.primaryRed.withOpacity(0.8),
                          ],
                        ),
                      ),
                    ),
                  ),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.logout),
                      onPressed: _logout,
                    ),
                  ],
                ),
                
                // Contenu principal
                SliverPadding(
                  padding: EdgeInsets.all(size.width * 0.05),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      // Message de bienvenue
                      Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              CircleAvatar(
                                radius: 40,
                                backgroundColor: AppConstants.primaryRed.withOpacity(0.1),
                                child: Text(
                                  userName[0].toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                    color: AppConstants.primaryRed,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Bienvenue sur CarEasy',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: AppConstants.darkGrey,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Nous sommes ravis de vous revoir !',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // Section À découvrir
                      const Text(
                        'À découvrir',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Grille de fonctionnalités
                      GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: 2,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        childAspectRatio: 1.2,
                        children: [
                          _buildFeatureCard(
                            icon: Icons.search,
                            title: 'Services',
                            color: Colors.blue,
                            onTap: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Bientôt disponible')),
                              );
                            },
                          ),
                          _buildFeatureCard(
                            icon: Icons.business,
                            title: 'Entreprises',
                            color: Colors.green,
                            onTap: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Bientôt disponible')),
                              );
                            },
                          ),
                          _buildFeatureCard(
                            icon: Icons.message,
                            title: 'Messages',
                            color: Colors.orange,
                            onTap: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Bientôt disponible')),
                              );
                            },
                          ),
                          _buildFeatureCard(
                            icon: Icons.person,
                            title: 'Mon profil',
                            color: AppConstants.primaryRed,
                            onTap: () {
                              _showProfileDialog();
                            },
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 24),
                    ]),
                  ),
                ),
              ],
            ),
      
      // Bottom Navigation Bar simple
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppConstants.primaryRed,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Accueil',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.search),
            label: 'Recherche',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.favorite),
            label: 'Favoris',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profil',
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureCard({
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showProfileDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mon profil'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nom: ${_userData?['name'] ?? 'Non renseigné'}'),
            const SizedBox(height: 8),
            Text('Email: ${_userData?['email'] ?? 'Non renseigné'}'),
            const SizedBox(height: 8),
            Text('Téléphone: ${_userData?['phone'] ?? 'Non renseigné'}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }
}