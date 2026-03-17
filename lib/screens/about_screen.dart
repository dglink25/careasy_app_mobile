// lib/screens/about_screen.dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../utils/constants.dart';
import '../theme/app_theme.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String _appVersion = '1.0.0';
  String _buildNumber = '1';

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
  }

  Future<void> _loadPackageInfo() async {
    final packageInfo = await PackageInfo.fromPlatform();
    setState(() {
      _appVersion = packageInfo.version;
      _buildNumber = packageInfo.buildNumber;
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isSmallScreen = size.width < 360;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: AppConstants.primaryRed,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'À propos',
          style: TextStyle(
            fontSize: isSmallScreen ? 18 : 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
        child: Column(
          children: [
            _buildAppInfoSection(isSmallScreen),
            const SizedBox(height: 16),
            _buildLegalSection(isSmallScreen),
            const SizedBox(height: 16),
            _buildSocialSection(isSmallScreen),
          ],
        ),
      ),
    );
  }

  Widget _buildAppInfoSection(bool isSmallScreen) {
    return Container(
      padding: EdgeInsets.all(isSmallScreen ? 20 : 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            height: 80,
            width: 80,
            decoration: BoxDecoration(
              color: AppConstants.primaryRed,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.car_repair,
              color: Colors.white,
              size: 40,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'CarEasy',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Version $_appVersion ($_buildNumber)',
            style: TextStyle(
              fontSize: isSmallScreen ? 12 : 14,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Votre assistant automobile',
            style: TextStyle(
              fontSize: 14,
              color: AppConstants.primaryRed,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 16),
          
          _buildInfoRow(
            'Développé par',
            'CarEasy Team',
            isSmallScreen,
          ),
          const SizedBox(height: 8),
          _buildInfoRow(
            'Année',
            '2024',
            isSmallScreen,
          ),
          const SizedBox(height: 8),
          _buildInfoRow(
            'Site web',
            'www.careasy.com',
            isSmallScreen,
            isLink: true,
            onTap: () => _launchUrl('https://www.careasy.com'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, bool isSmallScreen, {bool isLink = false, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: isSmallScreen ? 12 : 14,
              color: Colors.grey[700],
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: isSmallScreen ? 12 : 14,
              color: isLink ? AppConstants.primaryRed : Colors.grey[600],
              decoration: isLink ? TextDecoration.underline : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegalSection(bool isSmallScreen) {
    return Container(
      padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Mentions légales',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          
          _buildLegalItem(
            icon: Icons.description_outlined,
            title: 'Conditions d\'utilisation',
            onTap: () => _showComingSoon('Conditions d\'utilisation'),
            isSmallScreen: isSmallScreen,
          ),
          const SizedBox(height: 8),
          
          _buildLegalItem(
            icon: Icons.privacy_tip_outlined,
            title: 'Politique de confidentialité',
            onTap: () => _showComingSoon('Politique de confidentialité'),
            isSmallScreen: isSmallScreen,
          ),
          const SizedBox(height: 8),
          
          _buildLegalItem(
            icon: Icons.gavel_outlined,
            title: 'Mentions légales',
            onTap: () => _showComingSoon('Mentions légales'),
            isSmallScreen: isSmallScreen,
          ),
          const SizedBox(height: 8),
          
          _buildLegalItem(
            icon: Icons.cookie_outlined,
            title: 'Politique des cookies',
            onTap: () => _showComingSoon('Politique des cookies'),
            isSmallScreen: isSmallScreen,
          ),
        ],
      ),
    );
  }

  Widget _buildLegalItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    required bool isSmallScreen,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.all(isSmallScreen ? 12 : 14),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: isSmallScreen ? 18 : 20,
              color: AppConstants.primaryRed,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: isSmallScreen ? 14 : 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: isSmallScreen ? 12 : 14,
              color: Colors.grey[400],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSocialSection(bool isSmallScreen) {
    return Container(
      padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Suivez-nous',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildSocialButton(
                icon: Icons.facebook,
                label: 'Facebook',
                color: const Color(0xFF1877F2),
                onTap: () => _launchUrl('https://facebook.com/careasy'),
                isSmallScreen: isSmallScreen,
              ),
              _buildSocialButton(
                icon: Icons.camera_alt,
                label: 'Instagram',
                color: const Color(0xFFE4405F),
                onTap: () => _launchUrl('https://instagram.com/careasy'),
                isSmallScreen: isSmallScreen,
              ),
              _buildSocialButton(
                icon: Icons.chat,
                label: 'WhatsApp',
                color: const Color(0xFF25D366),
                onTap: () => _launchUrl('https://wa.me/22901234567'),
                isSmallScreen: isSmallScreen,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSocialButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    required bool isSmallScreen,
  }) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: color,
              size: isSmallScreen ? 18 : 24,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: isSmallScreen ? 10 : 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    final Uri uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      _showError('Impossible d\'ouvrir le lien');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  void _showComingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature - Bientôt disponible'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }
}