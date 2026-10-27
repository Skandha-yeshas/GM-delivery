import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import '../application/delivery_controller.dart';
import '../domain/models.dart';
import '../domain/maps_location.dart';
import '../data/shop_location_service.dart';
import 'common.dart';
import 'workspace_design.dart';

class ShopForm extends StatefulWidget {
  const ShopForm({
    super.key,
    required this.controller,
    this.shop,
    this.initialName,
    this.onSaved,
    this.locationService,
    this.captureLocationOnOpen = false,
  });
  final DeliveryController controller;
  final Shop? shop;
  final String? initialName;
  final ValueChanged<String>? onSaved;
  final ShopLocationService? locationService;
  final bool captureLocationOnOpen;
  @override
  State<ShopForm> createState() => _ShopFormState();
}

class _ShopFormState extends State<ShopForm> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name,
      _area,
      _address,
      _landmark,
      _phone,
      _contactName,
      _postalCode,
      _notes,
      _mapsUrl;
  double? _latitude, _longitude;
  final _fieldKeys = <String, GlobalKey<FormFieldState<String>>>{};
  late final String _id;
  bool _verified = false, _locating = false, _saving = false;
  String? _pickedPhoto, _locationMessage;
  bool _settingsNeeded = false;
  bool _notListed = true, _addressAutofilled = false, _postalAutofilled = false;
  double? _accuracy;
  int _addressEditRevision = 0;
  ShopLocationService get _locationService =>
      widget.locationService ?? DeviceShopLocationService();

  @override
  void initState() {
    super.initState();
    final shop = widget.shop;
    _id = shop?.id ?? const Uuid().v4();
    _name = TextEditingController(text: shop?.name ?? widget.initialName);
    _area = TextEditingController(text: shop?.area);
    _address = TextEditingController(text: shop?.address);
    _landmark = TextEditingController(text: shop?.landmark);
    _phone = TextEditingController(text: _mobileDigits(shop?.phone ?? ''));
    _contactName = TextEditingController(text: shop?.contactName);
    _postalCode = TextEditingController(text: shop?.postalCode);
    _notes = TextEditingController(text: shop?.notes);
    _mapsUrl = TextEditingController(text: shop?.mapsUrl);
    _latitude = shop?.latitude;
    _longitude = shop?.longitude;
    _verified = shop?.verified ?? false;
    _notListed = shop == null || !shop.hasMapsLink;
    unawaited(_recoverPhoto());
    if (widget.captureLocationOnOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_captureLocation());
      });
    }
  }

  @override
  void dispose() {
    for (final field in [
      _name,
      _area,
      _address,
      _landmark,
      _phone,
      _contactName,
      _postalCode,
      _notes,
      _mapsUrl,
    ]) {
      field.dispose();
    }
    super.dispose();
  }

  bool get _hasCoordinates => validCoordinates(_latitude, _longitude);
  bool get _hasMapsLink => isGoogleMapsLink(_mapsUrl.text);

  Future<void> _recoverPhoto() async {
    try {
      if (await widget.controller.store.getSetting('bill_scan_state') ==
          'picking') {
        return;
      }
      final response = await ImagePicker().retrieveLostData();
      if (response.files?.isNotEmpty == true && mounted) {
        setState(() => _pickedPhoto = response.files!.first.path);
      }
    } catch (_) {
      // Some platforms do not implement lost-data recovery.
    }
  }

  Future<void> _photo(ImageSource source) async {
    await runAction(context, () async {
      final file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1280,
        imageQuality: 75,
      );
      if (file != null && mounted) setState(() => _pickedPhoto = file.path);
    });
  }

  Future<void> _captureLocation() async {
    setState(() {
      _locating = true;
      _locationMessage = null;
      _settingsNeeded = false;
    });
    final addressRevision = _addressEditRevision;
    try {
      final position = await _locationService.capture();
      if (!mounted) return;
      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
        _verified = false;
        _accuracy = position.accuracy;
        _mapsUrl.clear();
        _notListed = true;
        _addressAutofilled = false;
        _postalAutofilled = false;
        _locationMessage =
            'Captured location • accuracy about ${position.accuracy.round()} m. '
            '${position.accuracy > 50 ? 'The signal is weak. Move outdoors and try again. ' : ''}'
            'Preview the pin, then confirm it is the delivery entrance.';
      });
      try {
        final address = await _locationService
            .addressFor(position)
            .timeout(const Duration(seconds: 8));
        if (!mounted) return;
        setState(() {
          if (address != null && _addressEditRevision == addressRevision) {
            if (_address.text.trim().isEmpty && address.address.isNotEmpty) {
              _address.text = address.address;
              _addressAutofilled = true;
            }
            if (_area.text.trim().isEmpty) _area.text = address.area;
            if (_postalCode.text.trim().isEmpty) {
              _postalCode.text = address.postalCode;
              _postalAutofilled = address.postalCode.isNotEmpty;
            }
          }
          if (address == null ||
              (address.address.isEmpty && address.area.isEmpty)) {
            _locationMessage =
                '${_locationMessage!} Address not available; enter it manually.';
          }
        });
      } catch (_) {
        if (mounted) {
          setState(
            () => _locationMessage =
                '${_locationMessage!} Address lookup unavailable; your GPS pin is kept. Enter the address manually.',
          );
        }
      }
    } on ShopLocationException catch (error) {
      if (mounted) {
        setState(() {
          _locationMessage = error.message;
          _settingsNeeded = error.settingsNeeded;
        });
      }
    } on TimeoutException {
      if (mounted) {
        setState(
          () => _locationMessage =
              'Could not get a location in time. Move outdoors and try again.',
        );
      }
    } catch (error) {
      if (mounted) setState(() => _locationMessage = errorText(error));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _preview() => runAction(context, () async {
    final uri = Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': '$_latitude,$_longitude',
    });
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw StateError('Could not open the map preview.');
    }
  });

  Future<void> _openMap(Uri uri) => runAction(context, () async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw StateError('Could not open Google Maps.');
    }
  });

  Future<void> _save() async {
    if (!_form.currentState!.validate()) {
      final first = _fieldKeys.values
          .where((key) => key.currentState?.hasError ?? false)
          .firstOrNull;
      if (first?.currentContext != null) {
        await Scrollable.ensureVisible(
          first!.currentContext!,
          duration: const Duration(milliseconds: 200),
          alignment: .1,
        );
      }
      return;
    }
    setState(() => _saving = true);
    FocusScope.of(context).unfocus();
    try {
      await widget.controller.saveShop(
        Shop(
          id: _id,
          name: _name.text.trim(),
          area: _area.text.trim().isEmpty ? 'Area not set' : _area.text.trim(),
          address: _address.text.trim(),
          landmark: _landmark.text.trim(),
          phone: '+91${_mobileDigits(_phone.text)}',
          contactName: _contactName.text.trim(),
          postalCode: _postalCode.text.trim(),
          notes: _notes.text.trim(),
          mapsUrl: _mapsUrl.text.trim(),
          latitude: _latitude,
          longitude: _longitude,
          verified: _verified && _hasCoordinates,
          photoPath: widget.shop?.photoPath,
          localPhotoPath: widget.shop?.localPhotoPath,
          version: widget.shop?.version ?? 0,
        ),
        pickedPhoto: _pickedPhoto,
      );
      if (mounted) {
        widget.onSaved?.call(_id);
        Navigator.pop(context);
        showMessage(context, 'Shop saved.');
      }
    } catch (error) {
      if (mounted) showMessage(context, errorText(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static const _primary = Color(0xff1e3a8a);
  static const _surface = Color(0xfff7f9fb);
  static const _secondary = Color(0xff006a61);
  bool get _working => _saving || _locating;
  Uri get _coordinateLink =>
      Uri.https('maps.google.com', '/', {'q': '$_latitude,$_longitude'});
  Uri get _navigationLink =>
      _hasMapsLink ? googleMapsUri(_mapsUrl.text) : _coordinateLink;

  static String _mobileDigits(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    return digits.length == 12 && digits.startsWith('91')
        ? digits.substring(2)
        : digits;
  }

  String? _required(String? value, String label) =>
      value == null || value.trim().isEmpty ? 'Enter $label.' : null;
  void _addressEdited(String label) {
    _addressEditRevision++;
    setState(() {
      if (label == 'Address') _addressAutofilled = false;
      if (label == 'PIN code') _postalAutofilled = false;
    });
  }

  Widget _card(Widget child, {Color? border, Color color = Colors.white}) =>
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          border: border == null ? null : Border.all(color: border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0700236f),
              blurRadius: 5,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: child,
      );
  Widget _badge(String text, {IconData? icon, Color color = _secondary}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      );
  Widget _section(String title, IconData icon, {Widget? trailing}) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 14),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: _primary),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        ?trailing,
      ],
    ),
  );
  Widget _field(
    TextEditingController controller,
    String label, {
    String? caption,
    IconData? icon,
    String? hint,
    bool required = false,
    bool enabled = true,
    int lines = 1,
    int maxLength = 200,
    TextInputType? keyboard,
    Widget? badge,
    ValueChanged<String>? onChanged,
    String? Function(String?)? validator,
    bool mobile = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: KeyedSubtree(
      key: ValueKey('shop-field-$label'),
      child: _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              runSpacing: 6,
              children: [
                Text(
                  '${caption ?? label.toUpperCase()}${required ? ' *' : ''}',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Color(0xff444651),
                    letterSpacing: .5,
                  ),
                ),
                ?badge,
              ],
            ),
            const SizedBox(height: 5),
            Semantics(
              label: label,
              child: TextFormField(
                key: _fieldKeys.putIfAbsent(
                  label,
                  () => GlobalKey<FormFieldState<String>>(),
                ),
                controller: controller,
                enabled: enabled && !_saving,
                maxLines: lines,
                maxLength: maxLength,
                keyboardType: keyboard,
                textCapitalization: keyboard == null
                    ? TextCapitalization.sentences
                    : TextCapitalization.none,
                style: const TextStyle(fontSize: 14, height: 1.5),
                inputFormatters: mobile
                    ? [
                        TextInputFormatter.withFunction((oldValue, newValue) {
                          final digits = _mobileDigits(newValue.text);
                          return digits.length > 10
                              ? oldValue
                              : TextEditingValue(
                                  text: digits,
                                  selection: TextSelection.collapsed(
                                    offset: digits.length,
                                  ),
                                );
                        }),
                      ]
                    : null,
                decoration: InputDecoration(
                  hintText: hint,
                  counterText: '',
                  prefixIcon: mobile
                      ? const Padding(
                          padding: EdgeInsets.only(right: 10),
                          child: Text(
                            '+91',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        )
                      : icon == null
                      ? null
                      : Padding(
                          padding: const EdgeInsets.only(right: 9),
                          child: Icon(
                            icon,
                            size: 20,
                            color: const Color(0xff757682),
                          ),
                        ),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 0,
                    minHeight: 24,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 4),
                  isDense: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                ),
                onChanged: onChanged,
                validator:
                    validator ??
                    (value) => required ? _required(value, label) : null,
              ),
            ),
          ],
        ),
      ),
    ),
  );
  Widget _locationStatus() => _badge(
    _hasMapsLink
        ? 'Maps location saved'
        : _hasCoordinates && _verified
        ? 'Entrance verified'
        : _hasCoordinates
        ? 'Confirm entrance'
        : 'Add a location',
    icon: _hasMapsLink || (_hasCoordinates && _verified)
        ? Icons.check_circle_outline
        : Icons.location_on_outlined,
    color: _hasMapsLink || (_hasCoordinates && _verified)
        ? _secondary
        : WorkspaceColors.amber,
  );

  Widget _gpsCard() => _card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 3),
              child: Icon(
                Icons.wrong_location_outlined,
                size: 21,
                color: _secondary,
              ),
            ),
            const SizedBox(width: 7),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Shop not listed on Google Maps',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 5),
                  Text(
                    'No listing? Capture live GPS at the shop entrance to save the drop-off pin and look up its street address.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: Color(0xff444651),
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              key: const Key('shop-unlisted-switch'),
              value: _notListed,
              activeThumbColor: Colors.white,
              activeTrackColor: _secondary,
              onChanged: _working
                  ? null
                  : (value) => setState(() => _notListed = value),
            ),
          ],
        ),
        if (_notListed) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xfff2f4f6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_hasMapsLink)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      'A successful capture replaces the saved Maps link. Check the new entrance before saving.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const Key('shop-capture-gps'),
                    onPressed: _working ? null : _captureLocation,
                    icon: _locating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.radar, size: 19),
                    label: Text(
                      _locating
                          ? 'Finding GPS & address…'
                          : _hasCoordinates
                          ? 'Re-detect GPS & auto-fill address'
                          : 'Detect live GPS & auto-fill address',
                    ),
                  ),
                ),
                if (_accuracy != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 9),
                    child: _badge(
                      'Live GPS · accuracy about ${_accuracy!.round()} m',
                      icon: Icons.gps_fixed,
                      color: _accuracy! > 50
                          ? WorkspaceColors.amber
                          : _secondary,
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (_locationMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              _locationMessage!,
              style: const TextStyle(fontSize: 12, height: 1.5),
            ),
          ),
        if (_settingsNeeded)
          TextButton(
            onPressed: Geolocator.openAppSettings,
            child: const Text('Open app settings'),
          ),
      ],
    ),
    border: const Color(0xffc8e8e2),
  );

  Widget _mapsLinkField() => _field(
    _mapsUrl,
    'Google Maps link (optional)',
    enabled: !_locating,
    caption: 'GOOGLE MAPS LOCATION LINK',
    icon: Icons.link,
    hint: 'Paste a shop or dropped-pin share link',
    maxLength: 4096,
    keyboard: TextInputType.url,
    badge: _hasMapsLink
        ? _badge('Ready for delivery', icon: Icons.check_circle_outline)
        : null,
    onChanged: (_) => setState(() {
      _verified = false;
      _latitude = null;
      _longitude = null;
      _accuracy = null;
      _locationMessage = null;
    }),
    validator: (value) {
      if (value == null || value.trim().isEmpty) return null;
      try {
        googleMapsUri(value);
        return null;
      } on FormatException catch (error) {
        return error.message;
      }
    },
  );

  Widget _navigationCard() => _card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 8,
          runSpacing: 8,
          children: [
            const Text(
              'NAVIGATION LINK',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Color(0xff444651),
                letterSpacing: .5,
              ),
            ),
            _badge('Direct entrance route', color: _primary),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(Icons.near_me_outlined, color: _primary, size: 21),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _hasMapsLink
                    ? 'Saved Google Maps location'
                    : 'Shop entrance pin saved',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton.icon(
              key: const Key('shop-copy-location'),
              onPressed: _working
                  ? null
                  : () => runAction(context, () async {
                      await Clipboard.setData(
                        ClipboardData(text: _navigationLink.toString()),
                      );
                      if (mounted) {
                        showMessage(context, 'Navigation link copied.');
                      }
                    }),
              icon: const Icon(Icons.copy_outlined, size: 16),
              label: const Text('Copy'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Drivers can open this location in Google Maps, even when the shop has no business listing.',
          style: TextStyle(fontSize: 12, height: 1.5, color: Color(0xff444651)),
        ),
      ],
    ),
  );

  Widget _entranceCard() => _card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.pin_drop_outlined, color: _primary, size: 20),
                SizedBox(width: 7),
                Flexible(
                  child: Text(
                    'Delivery drop-off pin',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            if (_notListed)
              TextButton.icon(
                onPressed: _working ? null : _captureLocation,
                icon: const Icon(Icons.my_location, size: 16),
                label: const Text('Re-detect GPS'),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Material(
          color: const Color(0xffeef5f5),
          borderRadius: BorderRadius.circular(9),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _working
                ? null
                : () => _hasMapsLink
                      ? _openMap(googleMapsUri(_mapsUrl.text))
                      : _preview(),
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 126),
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.location_on, size: 35, color: _primary),
                  const SizedBox(height: 6),
                  _locationStatus(),
                  const SizedBox(height: 8),
                  const Text(
                    'Tap to open the actual location in Google Maps',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: Color(0xff444651)),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _working
                ? null
                : () => _hasMapsLink
                      ? _openMap(googleMapsUri(_mapsUrl.text))
                      : _preview(),
            icon: const Icon(Icons.map_outlined, size: 18),
            label: const Text('Preview location in Maps'),
          ),
        ),
        if (!_hasMapsLink)
          Material(
            type: MaterialType.transparency,
            child: CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _verified,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text(
                'I checked this is the correct delivery entrance',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'Confirm the actual pin in Maps before using it for delivery.',
                style: TextStyle(fontSize: 12),
              ),
              onChanged: _working
                  ? null
                  : (value) => setState(() => _verified = value ?? false),
            ),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final photo = _pickedPhoto ?? widget.shop?.localPhotoPath;
    final base = Theme.of(context);
    final theme = base.copyWith(
      scaffoldBackgroundColor: _surface,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _primary,
        primary: _primary,
        secondary: _secondary,
        surface: _surface,
      ),
      textTheme: base.textTheme.apply(
        fontFamily: 'PlusJakartaSans',
        bodyColor: const Color(0xff191c1e),
        displayColor: const Color(0xff191c1e),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: _surface,
        foregroundColor: Color(0xff191c1e),
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        hintStyle: TextStyle(fontSize: 14, color: Color(0xff757682)),
        errorStyle: TextStyle(fontSize: 11),
        border: InputBorder.none,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: _primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(
            fontFamily: 'PlusJakartaSans',
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _primary,
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
    return Theme(
      data: theme,
      child: PopScope(
        canPop: !_working,
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              tooltip: 'Back',
              onPressed: _working ? null : () => Navigator.maybePop(context),
              icon: const Icon(Icons.arrow_back),
            ),
            titleSpacing: 0,
            title: Row(
              children: [
                Container(
                  width: 27,
                  height: 27,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _primary,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: const Text(
                    'GM',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.shop == null ? 'Add new shop' : 'Edit shop',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: DecoratedBox(
            decoration: const BoxDecoration(
              color: _surface,
              boxShadow: [
                BoxShadow(
                  color: Color(0x101e3a8a),
                  blurRadius: 16,
                  offset: Offset(0, -4),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Center(
                heightFactor: 1,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 50,
                            child: TextButton(
                              style: TextButton.styleFrom(
                                backgroundColor: const Color(0xffe6e8ea),
                                foregroundColor: const Color(0xff191c1e),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              onPressed: _working
                                  ? null
                                  : () => Navigator.pop(context),
                              child: const Text(
                                'Cancel',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          flex: 2,
                          child: FilledButton.icon(
                            key: const Key('save-shop'),
                            onPressed: _working ? null : _save,
                            icon: const Icon(Icons.save_outlined, size: 19),
                            label: Text(
                              _saving
                                  ? 'Saving…'
                                  : widget.shop == null
                                  ? 'Save & Add to Directory'
                                  : 'Save changes',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          body: Form(
            key: _form,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 26),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _section('Store Identity & Owner', Icons.badge_outlined),
                      _field(
                        _name,
                        'Shop name',
                        caption: 'SHOP / OUTLET NAME',
                        required: true,
                        icon: Icons.storefront_outlined,
                        hint: 'e.g., National Pen Corner',
                        badge: _badge('Primary ID', color: _primary),
                      ),
                      _field(
                        _contactName,
                        'Proprietor / contact person',
                        caption: 'PROPRIETOR / CONTACT PERSON',
                        required: true,
                        icon: Icons.person_outline,
                        hint: 'e.g., Rajesh Sharma',
                      ),
                      _field(
                        _phone,
                        'Contact number',
                        caption: 'DIRECT MOBILE NUMBER',
                        required: true,
                        mobile: true,
                        maxLength: 10,
                        keyboard: TextInputType.phone,
                        hint: '98765 43210',
                        validator: (value) =>
                            RegExp(
                              r'^[0-9]{10}$',
                            ).hasMatch(_mobileDigits(value ?? ''))
                            ? null
                            : 'Enter a 10-digit mobile number.',
                      ),
                      _section(
                        'Store Location & Drop Point',
                        Icons.pin_drop_outlined,
                        trailing: _locationStatus(),
                      ),
                      _gpsCard(),
                      const SizedBox(height: 14),
                      _mapsLinkField(),
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton.icon(
                            onPressed: _working
                                ? null
                                : () => _openMap(
                                    shopSearchUri(
                                      _name.text,
                                      _address.text,
                                      _area.text,
                                    ),
                                  ),
                            icon: const Icon(Icons.search, size: 18),
                            label: const Text('Search Google Maps'),
                          ),
                          if (_hasMapsLink)
                            TextButton(
                              onPressed: _working
                                  ? null
                                  : () =>
                                        _openMap(googleMapsUri(_mapsUrl.text)),
                              child: const Text('Open pasted link'),
                            ),
                        ],
                      ),
                      if (_hasMapsLink)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: WorkspaceBadge(
                            'Maps location ready for delivery',
                            icon: Icons.check_circle_outline,
                          ),
                        ),
                      _field(
                        _address,
                        'Address',
                        caption: 'COMPLETE STREET ADDRESS',
                        required: true,
                        lines: 2,
                        maxLength: 1000,
                        icon: Icons.location_city_outlined,
                        hint:
                            'Shop No. 12, Main Market Road, Opp. Central Bank',
                        badge: _addressAutofilled
                            ? _badge(
                                'Auto-filled from GPS',
                                icon: Icons.auto_awesome_outlined,
                              )
                            : null,
                        onChanged: (_) => _addressEdited('Address'),
                      ),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final landmark = _field(
                            _landmark,
                            'Landmark',
                            maxLength: 500,
                            hint: 'Near a familiar place',
                            badge: _badge('Edit', icon: Icons.edit_outlined),
                          );
                          final pin = _field(
                            _postalCode,
                            'PIN code',
                            required: true,
                            maxLength: 6,
                            keyboard: TextInputType.number,
                            hint: '560001',
                            badge: _postalAutofilled
                                ? _badge('GPS', icon: Icons.check)
                                : null,
                            onChanged: (_) => _addressEdited('PIN code'),
                            validator: (value) =>
                                RegExp(
                                  r'^[1-9][0-9]{5}$',
                                ).hasMatch(value?.trim() ?? '')
                                ? null
                                : 'Enter a valid 6-digit PIN.',
                          );
                          if (constraints.maxWidth < 330 ||
                              MediaQuery.textScalerOf(context).scale(1) > 1.3) {
                            return Column(children: [landmark, pin]);
                          }
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: landmark),
                              const SizedBox(width: 8),
                              Expanded(child: pin),
                            ],
                          );
                        },
                      ),
                      if (_hasCoordinates || _hasMapsLink) ...[
                        _navigationCard(),
                        const SizedBox(height: 14),
                        _entranceCard(),
                        const SizedBox(height: 14),
                      ],
                      ExpansionTile(
                        key: const Key('shop-additional-details'),
                        tilePadding: EdgeInsets.zero,
                        title: const Text(
                          'Additional delivery details',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        children: [
                          _field(
                            _area,
                            'Area',
                            icon: Icons.map_outlined,
                            hint: 'Market / locality / delivery area',
                            onChanged: (_) => _addressEdited('Area'),
                          ),
                          _field(
                            _notes,
                            'Delivery instructions',
                            lines: 3,
                            maxLength: 1000,
                            hint:
                                'Entrance, opening hours or unloading instructions',
                          ),
                          if (photo != null)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.file(
                                File(photo),
                                height: 150,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => const SizedBox(
                                  height: 60,
                                  child: Center(
                                    child: Text('Photo unavailable'),
                                  ),
                                ),
                              ),
                            ),
                          Wrap(
                            spacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed: _working
                                    ? null
                                    : () => _photo(ImageSource.camera),
                                icon: const Icon(
                                  Icons.photo_camera_outlined,
                                  size: 18,
                                ),
                                label: const Text('Take photo'),
                              ),
                              TextButton.icon(
                                onPressed: _working
                                    ? null
                                    : () => _photo(ImageSource.gallery),
                                icon: const Icon(
                                  Icons.photo_library_outlined,
                                  size: 18,
                                ),
                                label: const Text('Choose photo'),
                              ),
                            ],
                          ),
                        ],
                      ),
                      if (widget.controller.shared)
                        const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: Text(
                            'An internet connection is needed to save shared shop changes.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xff444651),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
