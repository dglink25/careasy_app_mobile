// lib/screens/about_screen.dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../utils/constants.dart';

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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
            _buildSupportSection(isSmallScreen),
            const SizedBox(height: 16),
            _buildLegalSection(isSmallScreen),
            const SizedBox(height: 16),
            _buildSocialSection(isSmallScreen),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  Info app + logo
  // ─────────────────────────────────────────────
  Widget _buildAppInfoSection(bool isSmallScreen) {
    return _card(
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Image.asset(
              'assets/images/logo.png',
              height: 80,
              width: 80,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                height: 80,
                width: 80,
                decoration: BoxDecoration(
                  color: AppConstants.primaryRed,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.car_repair, color: Colors.white, size: 40),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'CarEasy',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Version $_appVersion ($_buildNumber)',
            style: TextStyle(fontSize: isSmallScreen ? 12 : 14, color: Colors.grey[600]),
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
          _buildInfoRow('Développé par', 'CarEasy Team', isSmallScreen),
          const SizedBox(height: 8),
          _buildInfoRow('Année', '2026', isSmallScreen),
          const SizedBox(height: 8),
          _buildInfoRow('Site web', 'www.careasy.com', isSmallScreen,
              isLink: true, onTap: () => _launchUrl('https://www.careasy.com')),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, bool isSmallScreen,
      {bool isLink = false, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('$label: ',
              style: TextStyle(
                  fontSize: isSmallScreen ? 12 : 14,
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w600)),
          Text(value,
              style: TextStyle(
                  fontSize: isSmallScreen ? 12 : 14,
                  color: isLink ? AppConstants.primaryRed : Colors.grey[600],
                  decoration: isLink ? TextDecoration.underline : null)),
        ],
      ),
    );
  }


  Widget _buildSupportSection(bool isSmallScreen) {
    const waMessage =
        'Bonjour CarEasy, je viens de l\'application CarEasy et j\'aimerais en savoir plus sur CarEasy.';

    final contacts = [
      {'label': 'Support 1', 'number': '22994119476', 'display': '+229 94 11 94 76'},
      {'label': 'Support 2', 'number': '22990078988', 'display': '+229 90 07 89 88'},
    ];

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.headset_mic_outlined,
                  color: AppConstants.primaryRed, size: 20),
              const SizedBox(width: 8),
              Text(
                'Contacter le support',
                style: TextStyle(
                    fontSize: isSmallScreen ? 15 : 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Notre équipe est disponible pour vous aider.',
            style: TextStyle(fontSize: isSmallScreen ? 11 : 12, color: Colors.grey[500]),
          ),
          const SizedBox(height: 16),
          Row(
            children: contacts.asMap().entries.map((entry) {
              final isLast = entry.key == contacts.length - 1;
              final c = entry.value;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: isLast ? 0 : 10),
                  child: _buildWhatsAppButton(
                    number: c['number']!,
                    display: c['display']!,
                    label: c['label']!,
                    message: waMessage,
                    isSmallScreen: isSmallScreen,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildWhatsAppButton({
    required String number,
    required String display,
    required String label,
    required String message,
    required bool isSmallScreen,
  }) {
    const waGreen = Color(0xFF25D366);
    return InkWell(
      onTap: () => _launchUrl(
          'https://wa.me/$number?text=${Uri.encodeComponent(message)}'),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.symmetric(
            vertical: isSmallScreen ? 12 : 14,
            horizontal: isSmallScreen ? 10 : 12),
        decoration: BoxDecoration(
          color: waGreen.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: waGreen.withOpacity(0.5), width: 1.5),
        ),
        child: Column(
          children: [
            const Icon(Icons.chat, color: waGreen, size: 28),
            const SizedBox(height: 6),
            Text(label,
                style: TextStyle(
                    fontSize: isSmallScreen ? 10 : 11, color: Colors.grey[500])),
            const SizedBox(height: 2),
            Text(display,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: isSmallScreen ? 11 : 12,
                    fontWeight: FontWeight.bold,
                    color: waGreen)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: waGreen, borderRadius: BorderRadius.circular(20)),
              child: Text('WhatsApp',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: isSmallScreen ? 9 : 10,
                      fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  Mentions légales
  // ─────────────────────────────────────────────
  Widget _buildLegalSection(bool isSmallScreen) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Mentions légales',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _buildLegalItem(
            icon: Icons.description_outlined,
            title: 'Conditions d\'utilisation',
            onTap: () => _showLegalDialog(
                'Conditions d\'utilisation', _conditionsUtilisation),
            isSmallScreen: isSmallScreen,
          ),
          const SizedBox(height: 8),
          _buildLegalItem(
            icon: Icons.privacy_tip_outlined,
            title: 'Politique de confidentialité',
            onTap: () => _showLegalDialog(
                'Politique de confidentialité', _politiqueConfidentialite),
            isSmallScreen: isSmallScreen,
          ),
          const SizedBox(height: 8),
          _buildLegalItem(
            icon: Icons.gavel_outlined,
            title: 'Mentions légales',
            onTap: () => _showLegalDialog('Mentions légales', _mentionsLegales),
            isSmallScreen: isSmallScreen,
          ),
          const SizedBox(height: 8),
          _buildLegalItem(
            icon: Icons.cookie_outlined,
            title: 'Politique des cookies',
            onTap: () =>
                _showLegalDialog('Politique des cookies', _politiqueCookies),
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
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).dividerColor!),
        ),
        child: Row(
          children: [
            Icon(icon, size: isSmallScreen ? 18 : 20, color: AppConstants.primaryRed),
            const SizedBox(width: 12),
            Expanded(
                child: Text(title,
                    style: TextStyle(
                        fontSize: isSmallScreen ? 14 : 16,
                        fontWeight: FontWeight.w500))),
            Icon(Icons.arrow_forward_ios,
                size: isSmallScreen ? 12 : 14, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  void _showLegalDialog(String title, String content) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, scrollController) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                height: 4,
                width: 40,
                decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(title,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                    IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context)),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  child: Text(content,
                      style: const TextStyle(fontSize: 14, height: 1.65)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  Réseaux sociaux
  // ─────────────────────────────────────────────
  Widget _buildSocialSection(bool isSmallScreen) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Suivez-nous',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildSocialButton(
                  icon: Icons.facebook,
                  label: 'Facebook',
                  color: const Color(0xFF1877F2),
                  onTap: () => _launchUrl('https://facebook.com/careasy'),
                  isSmallScreen: isSmallScreen),
              _buildSocialButton(
                  icon: Icons.camera_alt,
                  label: 'Instagram',
                  color: const Color(0xFFE4405F),
                  onTap: () => _launchUrl('https://instagram.com/careasy'),
                  isSmallScreen: isSmallScreen),
              _buildSocialButton(
                  icon: Icons.chat,
                  label: 'WhatsApp',
                  color: const Color(0xFF25D366),
                  onTap: () => _launchUrl('https://wa.me/22994119476'),
                  isSmallScreen: isSmallScreen),
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
            decoration:
                BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: isSmallScreen ? 18 : 24),
          ),
          const SizedBox(height: 8),
          Text(label,
              style: TextStyle(
                  fontSize: isSmallScreen ? 10 : 12, color: Colors.grey[600])),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  Helper carte
  // ─────────────────────────────────────────────
  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, 2)),
        ],
      ),
      child: child,
    );
  }

  Future<void> _launchUrl(String url) async {
    final Uri uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Impossible d\'ouvrir le lien'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }
}

// ═══════════════════════════════════════════════
//  Textes des mentions légales
// ═══════════════════════════════════════════════

const String _conditionsUtilisation = '''
CONDITIONS GÉNÉRALES D'UTILISATION
Dernière mise à jour : janvier 2025

1. OBJET
Les présentes Conditions Générales d'Utilisation (CGU) régissent l'utilisation de l'application mobile CarEasy, éditée par CarEasy Team. En téléchargeant et en utilisant l'application, vous acceptez sans réserve les présentes conditions.

2. ACCÈS AU SERVICE
L'application CarEasy est accessible gratuitement à tout utilisateur disposant d'un accès à Internet. CarEasy se réserve le droit de suspendre ou d'interrompre l'accès au service à tout moment, notamment pour des opérations de maintenance.

3. CRÉATION DE COMPTE
Pour accéder à l'ensemble des fonctionnalités, l'utilisateur doit créer un compte en fournissant des informations exactes et à jour. L'utilisateur est seul responsable de la confidentialité de ses identifiants de connexion.

4. UTILISATION DU SERVICE
L'utilisateur s'engage à utiliser CarEasy de manière conforme à la législation en vigueur. Il est notamment interdit de :
• Utiliser l'application à des fins frauduleuses ou illicites ;
• Porter atteinte aux droits de tiers ;
• Tenter de pirater ou de perturber le fonctionnement du service.

5. RESPONSABILITÉ
CarEasy s'efforce de fournir des informations exactes mais ne peut garantir l'exhaustivité des données affichées. L'application ne saurait être tenue responsable des dommages directs ou indirects résultant de son utilisation.

6. PROPRIÉTÉ INTELLECTUELLE
L'ensemble des contenus (textes, images, logos, icônes) sont protégés par le droit de la propriété intellectuelle et appartiennent exclusivement à CarEasy Team.

7. MODIFICATION DES CGU
CarEasy se réserve le droit de modifier les présentes CGU. L'utilisateur sera informé par notification dans l'application.

8. LOI APPLICABLE
Les présentes CGU sont régies par les lois en vigueur. En cas de litige, les parties rechercheront une solution amiable.

Contact : caeary26@gmail.com
''';

const String _politiqueConfidentialite = '''
POLITIQUE DE CONFIDENTIALITÉ
Dernière mise à jour : janvier 2025

1. RESPONSABLE DU TRAITEMENT
CarEasy Team est responsable du traitement de vos données personnelles.

2. DONNÉES COLLECTÉES
• Informations d'identité : nom, prénom, adresse e-mail ;
• Données de connexion : date et heure ;
• Données d'utilisation : fonctionnalités, préférences ;
• Données du véhicule : renseignées volontairement.

3. FINALITÉS
• Gérer votre compte et fournir nos services ;
• Améliorer l'expérience utilisateur ;
• Envoyer des notifications (avec votre consentement) ;
• Assurer la sécurité de l'application.

4. BASE LÉGALE
• Exécution du contrat ;
• Votre consentement ;
• Notre intérêt légitime.

5. CONSERVATION
Données conservées pendant toute la durée d'utilisation, puis 3 ans après suppression du compte.

6. PARTAGE
Nous ne vendons jamais vos données. Partage uniquement avec nos prestataires techniques ou en cas d'obligation légale.

7. VOS DROITS
Droits d'accès, rectification, effacement, portabilité et opposition.
Contact : careasy26@gmail.com

8. SÉCURITÉ
Mesures techniques et organisationnelles adaptées mises en œuvre.

Contact : careasy26@gmail.com
''';

const String _mentionsLegales = '''
MENTIONS LÉGALES

ÉDITEUR
Application : CarEasy
Éditeur : CarEasy Team
Email : careasy26@gmail.com
Site : www.careasy.com

DIRECTEUR DE LA PUBLICATION
CarEasy Team

HÉBERGEMENT
Données hébergées sur serveurs sécurisés.
Contact : careasy26@gmail.com

PROPRIÉTÉ INTELLECTUELLE
L'application CarEasy, son contenu et son code sont protégés par la propriété intellectuelle et appartiennent à CarEasy Team. Toute reproduction sans autorisation écrite est interdite.

RESPONSABILITÉ
CarEasy Team ne saurait être tenu responsable des dommages liés à l'utilisation de l'application. Les informations sont fournies à titre indicatif.

DROIT APPLICABLE
Lois en vigueur. Résolution amiable privilégiée en cas de litige.

VERSION
Version 1.0 — 2026
''';

const String _politiqueCookies = '''
POLITIQUE DES COOKIES ET TRACEURS
Dernière mise à jour : Avril 2026

1. QU'EST-CE QU'UN COOKIE ?
Petit fichier mémorisant des informations relatives à votre navigation sur l'application.

2. TRACEURS UTILISÉS

a) Traceurs strictement nécessaires (sans consentement requis)
• Gestion de session et authentification ;
• Mémorisation des préférences (thème, langue) ;
• Sécurité de la connexion.

b) Traceurs de performance (analytiques)
Mesurent l'audience et analysent les comportements. Données anonymisées.

c) Traceurs de personnalisation
Adaptent l'affichage selon vos préférences (thème clair/sombre).

3. GESTION DE VOS PRÉFÉRENCES
Paramètres disponibles dans la section « Apparence » de l'application.

4. DURÉE DE CONSERVATION
• Session : supprimés à la fermeture ;
• Préférences : jusqu'à modification ou suppression du compte ;
• Analytiques : données anonymisées, 13 mois maximum.

5. CONTACT
careasy26@gmail.com
''';