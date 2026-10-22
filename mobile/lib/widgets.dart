import 'package:flutter/material.dart';

const ink = Color(0xFF173D36);
const accent = Color(0xFF2F6B55);

class Content extends StatelessWidget {
  final Widget child;
  const Content({super.key, required this.child});
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: child,
    ),
  );
}

class ErrorBox extends StatelessWidget {
  final Object error;
  final VoidCallback? retry;
  const ErrorBox(this.error, {super.key, this.retry});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          error.toString(),
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
        if (retry != null)
          TextButton.icon(
            onPressed: retry,
            icon: const Icon(Icons.refresh),
            label: const Text('Повторить'),
          ),
      ],
    ),
  );
}

class EmptyView extends StatelessWidget {
  final IconData icon;
  final String title, message;
  const EmptyView({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 20),
    child: Column(
      children: [
        Icon(icon, size: 52, color: accent),
        const SizedBox(height: 20),
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(message, textAlign: TextAlign.center),
      ],
    ),
  );
}

class ActionButton extends StatelessWidget {
  final String label;
  final bool busy;
  final VoidCallback? onPressed;
  const ActionButton({
    super.key,
    required this.label,
    this.busy = false,
    this.onPressed,
  });
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: FilledButton(
      onPressed: busy ? null : onPressed,
      child: busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(label),
    ),
  );
}

class ListingImage extends StatelessWidget {
  final String? url;
  final double height;
  const ListingImage({super.key, this.url, this.height = 210});
  @override
  Widget build(BuildContext context) {
    Widget placeholder() => Container(
      height: height,
      width: double.infinity,
      color: const Color(0xFFE5EBE1),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.home_work_outlined, size: 48, color: accent),
          SizedBox(height: 8),
          Text('Фото недоступно'),
        ],
      ),
    );
    return url == null
        ? placeholder()
        : Image.network(
            url!,
            width: double.infinity,
            height: height,
            fit: BoxFit.cover,
            errorBuilder: (_, error, stack) => placeholder(),
            loadingBuilder: (_, child, progress) => progress == null
                ? child
                : SizedBox(
                    height: height,
                    child: const Center(child: CircularProgressIndicator()),
                  ),
          );
  }
}

class Tag extends StatelessWidget {
  final String text;
  const Tag(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: const Color(0xFFE8EEE4),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: ink,
        fontWeight: FontWeight.w600,
        fontSize: 12,
      ),
    ),
  );
}

void toast(BuildContext context, String message) => ScaffoldMessenger.of(
  context,
).showSnackBar(SnackBar(content: Text(message)));
Future<bool> confirm(
  BuildContext context,
  String title,
  String message,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Назад'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Подтвердить'),
          ),
        ],
      ),
    ) ??
    false;
String? requiredText(String? value) =>
    value == null || value.trim().isEmpty ? 'Заполните поле' : null;
String? emailValidator(String? value) =>
    RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value?.trim() ?? '')
    ? null
    : 'Введите email';
