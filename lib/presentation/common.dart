import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../application/delivery_controller.dart';
import '../domain/models.dart';

Future<void> runAction(
  BuildContext context,
  Future<void> Function() action, {
  String? success,
}) async {
  try {
    await action();
    if (context.mounted && success != null) showMessage(context, success);
  } catch (error) {
    if (context.mounted) showMessage(context, errorText(error));
  }
}

void showMessage(BuildContext context, String message) => ScaffoldMessenger.of(
  context,
).showSnackBar(SnackBar(content: Text(message)));

Future<void> navigateTo(BuildContext context, Shop shop) =>
    runAction(context, () async {
      final launched = await launchUrl(
        navigationUri(shop),
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw StateError(
          'Could not open directions. Install Google Maps or a web browser.',
        );
      }
    });

Future<void> callShop(BuildContext context, Shop shop) => runAction(
  context,
  () async {
    final phone = shop.phone.replaceAll(RegExp(r'[^+0-9]'), '');
    if (phone.isEmpty) throw StateError('This shop has no phone number saved.');
    if (!await launchUrl(Uri(scheme: 'tel', path: phone))) {
      throw StateError('Could not open the phone dialler.');
    }
  },
);

class ShopPhoto extends StatelessWidget {
  const ShopPhoto({super.key, required this.shop, this.height = 170});
  final Shop shop;
  final double height;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(18),
    child: SizedBox(
      height: height,
      width: double.infinity,
      child: shop.localPhotoPath == null
          ? _placeholder()
          : Image.file(
              File(shop.localPhotoPath!),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _placeholder(),
            ),
    ),
  );
  Widget _placeholder() => const ColoredBox(
    color: Color(0xffe4ece6),
    child: Center(
      child: Icon(Icons.storefront_rounded, size: 48, color: Color(0xff527064)),
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });
  final IconData icon;
  final String title, message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(28),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 58, color: const Color(0xff709182)),
        const SizedBox(height: 18),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Text(message, textAlign: TextAlign.center),
        if (action != null)
          Padding(padding: const EdgeInsets.only(top: 20), child: action),
      ],
    ),
  );
}
