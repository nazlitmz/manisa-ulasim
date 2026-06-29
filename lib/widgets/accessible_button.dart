import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/accessibility_provider.dart';

/// Erişilebilirlik odaklı buton widget'ı
/// Büyük dokunma alanı ve sesli geri bildirim desteği
class AccessibleButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final bool isLoading;
  final bool isOutlined;
  
  const AccessibleButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.backgroundColor,
    this.foregroundColor,
    this.isLoading = false,
    this.isOutlined = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accessibility = context.watch<AccessibilityProvider>();
    
    final minHeight = accessibility.buttonHeight;
    
    if (isOutlined) {
      return SizedBox(
        height: minHeight,
        child: OutlinedButton.icon(
          onPressed: isLoading ? null : onPressed,
          icon: isLoading 
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: foregroundColor ?? theme.colorScheme.primary,
                ),
              )
            : Icon(icon, size: accessibility.iconSize),
          label: Text(
            label,
            style: TextStyle(fontSize: accessibility.largeTextMode ? 18 : 16),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: foregroundColor,
            side: BorderSide(
              color: foregroundColor ?? theme.colorScheme.primary,
              width: accessibility.highContrastMode ? 2 : 1,
            ),
          ),
        ),
      );
    }
    
    return SizedBox(
      height: minHeight,
      child: ElevatedButton.icon(
        onPressed: isLoading ? null : onPressed,
        icon: isLoading 
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Icon(icon, size: accessibility.iconSize),
        label: Text(
          label,
          style: TextStyle(fontSize: accessibility.largeTextMode ? 18 : 16),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
        ),
      ),
    );
  }
}

/// Erişilebilir icon butonu
class AccessibleIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;
  
  const AccessibleIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final accessibility = context.watch<AccessibilityProvider>();
    
    return Semantics(
      button: true,
      label: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(accessibility.buttonHeight / 2),
        child: Container(
          width: accessibility.buttonHeight,
          height: accessibility.buttonHeight,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color?.withOpacity(0.1),
          ),
          child: Icon(
            icon,
            size: accessibility.iconSize,
            color: color,
          ),
        ),
      ),
    );
  }
}
