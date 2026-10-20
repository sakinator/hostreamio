import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Universal TV remote D-Pad & pointer focusable button with high-contrast rings,
/// auto-scrolling on Android TV, subtle scaling animation, and responsive feedback.
class TvFocusableButton extends StatefulWidget {
  final FocusNode? focusNode;
  final VoidCallback onPressed;
  final Widget child;
  final bool isPrimary;
  final Color? primaryColor;
  final Color? focusColor;
  final bool autofocus;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;

  const TvFocusableButton({
    super.key,
    this.focusNode,
    required this.onPressed,
    required this.child,
    this.isPrimary = false,
    this.primaryColor,
    this.focusColor,
    this.autofocus = false,
    this.padding,
    this.borderRadius,
  });

  @override
  State<TvFocusableButton> createState() => _TvFocusableButtonState();
}

class _TvFocusableButtonState extends State<TvFocusableButton> {
  bool _isFocused = false;
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final hasHighlight = _isFocused || _isHovered;
    final bg = widget.isPrimary
        ? (widget.primaryColor ?? const Color(0xFF6366F1))
        : (hasHighlight ? const Color(0xFF21262D) : const Color(0xFF161B22));
    final highlightColor = widget.focusColor ?? const Color(0xFF38BDF8);

    return FocusableActionDetector(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: (focused) {
        setState(() => _isFocused = focused);
        if (focused) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
          );
        }
      },
      onShowHoverHighlight: (hovered) => setState(() => _isHovered = hovered),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) => widget.onPressed(),
        ),
      },
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          transform: hasHighlight ? Matrix4.diagonal3Values(1.04, 1.04, 1.0) : Matrix4.identity(),
          padding: widget.padding,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: widget.borderRadius ?? BorderRadius.circular(14),
            border: Border.all(
              color: hasHighlight ? highlightColor : const Color(0xFF30363D),
              width: hasHighlight ? 2.5 : 1.2,
            ),
            boxShadow: hasHighlight
                ? [
                    BoxShadow(
                      color: highlightColor.withOpacity(0.4),
                      blurRadius: 18,
                      spreadRadius: 2,
                    ),
                  ]
                : [],
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
