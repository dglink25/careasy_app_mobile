
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/accessibility_provider.dart';
import '../utils/constants.dart';


class AccessibilityButton extends StatelessWidget {
  final Color? iconColor;
  const AccessibilityButton({super.key, this.iconColor});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(Icons.accessibility_new_rounded, color: iconColor ?? Colors.white),
      tooltip: 'Accessibilité',
      onPressed: () => AccessibilitySheet.show(context),
    );
  }
}


class AccessibilitySheet extends StatelessWidget {
  const AccessibilitySheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<AccessibilityProvider>(),
        child: const AccessibilitySheet(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Handle ───────────────────────────────────────────────────
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // ── En-tête ──────────────────────────────────────────────────
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppConstants.primaryRed.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.accessibility_new_rounded,
                      color: AppConstants.primaryRed, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Accessibilité',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold, fontSize: 18)),
                    Text('Personnalisez la taille du texte',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey[500])),
                  ]),
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded, color: Colors.grey[400]),
                  onPressed: () => Navigator.pop(context),
                ),
              ]),

              const SizedBox(height: 24),
              const Divider(height: 1),
              const SizedBox(height: 20),

              // ── Section Taille de texte ───────────────────────────────────
              Text('Taille du texte',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppConstants.primaryRed)),
              const SizedBox(height: 14),

              // ── Contrôles +/− et slider ──────────────────────────────────
              Consumer<AccessibilityProvider>(
                builder: (_, acc, __) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Boutons − / niveaux visuels / + ───────────────────
                    Row(children: [
                      // Bouton réduire
                      _CircleBtn(
                        icon: Icons.text_decrease_rounded,
                        enabled: acc.canDecrease,
                        onTap: () => acc.decrease(),
                      ),
                      const SizedBox(width: 10),

                      // Niveaux
                      Expanded(
                        child: Row(
                          children: List.generate(
                            AccessibilityProvider.scales.length,
                            (i) {
                              final active = i == acc.currentIndex;
                              final scale  = AccessibilityProvider.scales[i];
                              return Expanded(
                                child: GestureDetector(
                                  onTap: () => acc.setScale(scale),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    margin: const EdgeInsets.symmetric(horizontal: 3),
                                    height: active ? 36 : 28,
                                    decoration: BoxDecoration(
                                      color: active
                                          ? AppConstants.primaryRed
                                          : AppConstants.primaryRed.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Center(
                                      child: Text(
                                        'A',
                                        style: TextStyle(
                                          fontSize: 10 + i * 2.0,
                                          fontWeight: FontWeight.w800,
                                          color: active ? Colors.white : AppConstants.primaryRed,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),

                      const SizedBox(width: 10),
                      // Bouton agrandir
                      _CircleBtn(
                        icon: Icons.text_increase_rounded,
                        enabled: acc.canIncrease,
                        onTap: () => acc.increase(),
                      ),
                    ]),

                    const SizedBox(height: 12),

                    // ── Label courant ──────────────────────────────────────
                    Center(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: Text(
                          acc.currentLabel,
                          key: ValueKey(acc.currentLabel),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppConstants.primaryRed,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ── Aperçu live ────────────────────────────────────────
                    _PreviewBox(scaleFactor: acc.scaleFactor),

                    const SizedBox(height: 16),

                    // ── Bouton reset ───────────────────────────────────────
                    if (acc.scaleFactor != 1.0)
                      Center(
                        child: TextButton.icon(
                          onPressed: () => acc.reset(),
                          icon: const Icon(Icons.refresh_rounded, size: 15),
                          label: const Text('Rétablir la taille par défaut'),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.grey[600],
                            textStyle: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Bouton rond +/− ─────────────────────────────────────────────────────────
class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _CircleBtn({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 44, height: 44,
        decoration: BoxDecoration(
          color: enabled
              ? AppConstants.primaryRed
              : Colors.grey.withOpacity(0.15),
          shape: BoxShape.circle,
          boxShadow: enabled
              ? [BoxShadow(
                  color: AppConstants.primaryRed.withOpacity(0.28),
                  blurRadius: 10, offset: const Offset(0, 3))]
              : [],
        ),
        child: Icon(icon,
            size: 20,
            color: enabled ? Colors.white : Colors.grey[400]),
      ),
    );
  }
}

// ─── Aperçu live du texte ─────────────────────────────────────────────────────
class _PreviewBox extends StatelessWidget {
  final double scaleFactor;
  const _PreviewBox({required this.scaleFactor});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(scaleFactor),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xFF2A2A3E)
              : AppConstants.primaryRed.withOpacity(0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppConstants.primaryRed.withOpacity(0.15),
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.visibility_outlined,
                size: 13, color: AppConstants.primaryRed),
            const SizedBox(width: 5),
            Text('Aperçu',
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppConstants.primaryRed)),
          ]),
          const SizedBox(height: 10),
          Text(
            'Vidange moteur — 15 000 FCFA',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : const Color(0xFF1A1A1A)),
          ),
          const SizedBox(height: 4),
          Text(
            'Garage Bénin Auto Express • Cotonou',
            style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white70 : Colors.grey[600]),
          ),
          const SizedBox(height: 4),
          Text(
            'Rendez-vous disponibles du lundi au samedi',
            style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white54 : Colors.grey[500]),
          ),
        ]),
      ),
    );
  }
}