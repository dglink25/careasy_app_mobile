// lib/screens/help_screen.dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/constants.dart';
import '../theme/app_theme.dart';

class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  final List<Map<String, dynamic>> _faqs = [
    {
      'question': 'Comment créer une entreprise ?',
      'answer': 'Pour créer une entreprise, allez dans l\'onglet "Entreprise" depuis la page d\'accueil ou dans les paramètres. Suivez ensuite les étapes de création.',
      'expanded': false,
    },
    {
      'question': 'Comment contacter un service ?',
      'answer': 'Sur la page d\'accueil, sélectionnez un service puis cliquez sur "Contacter". Vous pourrez alors appeler, envoyer un message ou WhatsApp.',
      'expanded': false,
    },
    {
      'question': 'Comment prendre un rendez-vous ?',
      'answer': 'La fonctionnalité de rendez-vous sera bientôt disponible. Vous pourrez planifier des interventions directement depuis l\'application.',
      'expanded': false,
    },
    {
      'question': 'Comment changer mon mot de passe ?',
      'answer': 'Allez dans Paramètres > Confidentialité & sécurité, puis dans la section "Changer le mot de passe".',
      'expanded': false,
    },
    {
      'question': 'L\'application est-elle gratuite ?',
      'answer': 'L\'application est gratuite pour les clients. Pour les entreprises, des plans d\'abonnement sont disponibles.',
      'expanded': false,
    },
  ];

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
          'Aide & support',
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
            _buildContactSection(isSmallScreen),
            const SizedBox(height: 16),
            _buildFaqSection(isSmallScreen),
            const SizedBox(height: 16),
            _buildSupportSection(isSmallScreen),
          ],
        ),
      ),
    );
  }

  Widget _buildContactSection(bool isSmallScreen) {
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppConstants.primaryRed.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.support_agent,
                  color: AppConstants.primaryRed,
                  size: isSmallScreen ? 20 : 24,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Nous contacter',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          _buildContactButton(
            icon: Icons.email_outlined,
            title: 'Email',
            subtitle: 'careasy26@gmail.com',
            onTap: () => _launchEmail(),
            isSmallScreen: isSmallScreen,
          ),
          const SizedBox(height: 8),
          
          _buildContactButton(
            icon: Icons.phone_outlined,
            title: 'Téléphone',
            subtitle: '+229 01 90 07 89 88',
            onTap: () => _launchPhone('+22990078988'),
            isSmallScreen: isSmallScreen,
          ),
          const SizedBox(height: 8),
          
          _buildContactButton(
            icon: Icons.chat_outlined,
            title: 'WhatsApp',
            subtitle: 'Support WhatsApp',
            onTap: () => _launchWhatsApp('+22994119476'),
            isSmallScreen: isSmallScreen,
          ),
        ],
      ),
    );
  }

  Widget _buildContactButton({
    required IconData icon,
    required String title,
    required String subtitle,
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
              size: isSmallScreen ? 20 : 24,
              color: AppConstants.primaryRed,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: isSmallScreen ? 14 : 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: isSmallScreen ? 11 : 13,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
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

  Widget _buildFaqSection(bool isSmallScreen) {
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppConstants.primaryRed.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.help_outline,
                  color: AppConstants.primaryRed,
                  size: isSmallScreen ? 20 : 24,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Questions fréquentes',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          ..._faqs.map((faq) {
            return Column(
              children: [
                _buildFaqItem(faq, isSmallScreen),
                if (faq != _faqs.last)
                  Divider(height: 1, color: Colors.grey[200]),
              ],
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildFaqItem(Map<String, dynamic> faq, bool isSmallScreen) {
    return Container(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.only(bottom: 12, left: 36, right: 12),
          title: Text(
            faq['question'],
            style: TextStyle(
              fontSize: isSmallScreen ? 13 : 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          children: [
            Text(
              faq['answer'],
              style: TextStyle(
                fontSize: isSmallScreen ? 12 : 14,
                color: Colors.grey[700],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSupportSection(bool isSmallScreen) {
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppConstants.primaryRed.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.article_outlined,
                  color: AppConstants.primaryRed,
                  size: isSmallScreen ? 20 : 24,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Ressources',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          _buildResourceItem(
            icon: Icons.picture_as_pdf,
            title: 'Guide d\'utilisation',
            subtitle: 'Télécharger le guide PDF',
            onTap: () => _showComingSoon('Guide d\'utilisation'),
            isSmallScreen: isSmallScreen,
          ),
          const SizedBox(height: 8),
          
          _buildResourceItem(
            icon: Icons.video_library,
            title: 'Tutoriels vidéo',
            subtitle: 'Voir les tutoriels',
            onTap: () => _showComingSoon('Tutoriels vidéo'),
            isSmallScreen: isSmallScreen,
          ),
          const SizedBox(height: 8),
          
          _buildResourceItem(
            icon: Icons.update,
            title: 'Notes de version',
            subtitle: 'Découvrir les dernières mises à jour',
            onTap: () => _showComingSoon('Notes de version'),
            isSmallScreen: isSmallScreen,
          ),
        ],
      ),
    );
  }

  Widget _buildResourceItem({
    required IconData icon,
    required String title,
    required String subtitle,
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
              size: isSmallScreen ? 20 : 24,
              color: AppConstants.primaryRed,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: isSmallScreen ? 14 : 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: isSmallScreen ? 11 : 13,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
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

  Future<void> _launchEmail() async {
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: 'support@careasy.com',
      query: 'subject=Support CarEasy&body=Bonjour,',
    );
    
    try {
      await launchUrl(emailUri);
    } catch (e) {
      _showError('Impossible d\'ouvrir l\'application email');
    }
  }

  Future<void> _launchPhone(String phoneNumber) async {
    final Uri phoneUri = Uri(scheme: 'tel', path: phoneNumber);
    
    try {
      await launchUrl(phoneUri);
    } catch (e) {
      _showError('Impossible de lancer l\'appel');
    }
  }

  Future<void> _launchWhatsApp(String phoneNumber) async {
    final cleanNumber = phoneNumber.replaceAll('+', '');
    final Uri whatsappUri = Uri.parse('https://wa.me/$cleanNumber');
    
    try {
      await launchUrl(whatsappUri, mode: LaunchMode.externalApplication);
    } catch (e) {
      _showError('Impossible d\'ouvrir WhatsApp');
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