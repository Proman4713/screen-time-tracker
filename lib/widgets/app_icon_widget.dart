import 'dart:io';
import 'package:fluent_ui/fluent_ui.dart';
import '../services/app_icon_service.dart';

/// A widget that displays an app's extracted icon with a fallback.
class AppIconWidget extends StatefulWidget {
  final String processName;
  final String? executablePath;
  final double size;
  final IconData fallbackIcon;

  const AppIconWidget({
    super.key,
    required this.processName,
    this.executablePath,
    this.size = 20,
    this.fallbackIcon = FluentIcons.app_icon_default,
  });

  @override
  State<AppIconWidget> createState() => _AppIconWidgetState();
}

class _AppIconWidgetState extends State<AppIconWidget> {
  String? _iconPath;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadIcon();
  }

  @override
  void didUpdateWidget(AppIconWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.processName != widget.processName ||
        oldWidget.executablePath != widget.executablePath) {
      _loaded = false;
      _loadIcon();
    }
  }

  Future<void> _loadIcon() async {
    final path = await AppIconService.instance.getIconPath(
      widget.processName,
      executablePath: widget.executablePath,
    );
    if (mounted) {
      setState(() {
        _iconPath = path;
        _loaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      // Show fallback while loading
      return Icon(widget.fallbackIcon, size: widget.size);
    }

    if (_iconPath != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.file(
          File(_iconPath!),
          width: widget.size,
          height: widget.size,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Icon(
            widget.fallbackIcon,
            size: widget.size,
          ),
        ),
      );
    }

    return Icon(widget.fallbackIcon, size: widget.size);
  }
}
