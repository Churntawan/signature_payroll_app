import 'package:flutter/material.dart';
import '../services/localization_service.dart';

class LanguageToggle extends StatelessWidget {
  final ValueChanged<SubLanguage>? onChanged;
  final bool isCompact;

  const LanguageToggle({
    super.key,
    this.onChanged,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SubLanguage>(
      valueListenable: L10n.currentSubLang,
      builder: (context, currentSub, _) {
        return Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF334155), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: SubLanguage.values.map((lang) {
              final isSelected = lang == currentSub;
              return InkWell(
                onTap: () {
                  if (!isSelected) {
                    L10n.setSubLanguage(lang);
                    onChanged?.call(lang);
                  }
                },
                borderRadius: BorderRadius.circular(16),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  padding: EdgeInsets.symmetric(
                    horizontal: isCompact ? 8 : 12,
                    vertical: isCompact ? 4 : 6,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF0284C7) : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: const Color(0xFF0284C7).withOpacity(0.4),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            )
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(lang.flag, style: TextStyle(fontSize: isCompact ? 12 : 14)),
                      const SizedBox(width: 4),
                      Text(
                        lang.label,
                        style: TextStyle(
                          fontSize: isCompact ? 11 : 12.5,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}
