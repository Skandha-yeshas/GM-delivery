import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import '../application/delivery_controller.dart';
import '../domain/models.dart';
import '../domain/maps_location.dart';
import '../data/maps_link_resolver.dart';
import 'common.dart';
import 'workspace_design.dart';

class ShopForm extends StatefulWidget {
  const ShopForm({
    super.key,
    required this.controller,
    this.shop,
    this.initialName,
    this.onSaved,
  });
  final DeliveryController controller;
  final Shop? shop;
  final String? initialName;
  final ValueChanged<String>? onSaved;
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
      _notes,
      _latitude,
      _longitude,
      _mapsUrl;
  late final String _id;
  bool _verified = false, _locating = false, _saving = false;
  String? _pickedPhoto, _locationMessage;
  bool _settingsNeeded = false;
  bool _resolving = false;

  @override
  void initState() {
    super.initState();
    final shop = widget.shop;
    _id = shop?.id ?? const Uuid().v4();
    _name = TextEditingController(text: shop?.name ?? widget.initialName);
    _area = TextEditingController(text: shop?.area);
    _address = TextEditingController(text: shop?.address);
    _landmark = TextEditingController(text: shop?.landmark);
    _phone = TextEditingController(text: shop?.phone);
    _notes = TextEditingController(text: shop?.notes);
    _mapsUrl = TextEditingController(text: shop?.mapsUrl);
    _latitude = TextEditingController(text: shop?.latitude?.toStringAsFixed(7));
    _longitude = TextEditingController(
      text: shop?.longitude?.toStringAsFixed(7),
    );
    _verified = shop?.verified ?? false;
    unawaited(_recoverPhoto());
  }

  @override
  void dispose() {
    for (final field in [
      _name,
      _area,
      _address,
      _landmark,
      _phone,
      _notes,
      _latitude,
      _longitude,
      _mapsUrl,
    ]) {
      field.dispose();
    }
    super.dispose();
  }

  bool get _hasCoordinates => validCoordinates(
    double.tryParse(_latitude.text.trim()),
    double.tryParse(_longitude.text.trim()),
  );
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
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw StateError('Turn on the phone’s location service and try again.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        if (mounted) setState(() => _settingsNeeded = true);
        throw StateError('Allow location access in the phone’s app settings.');
      }
      if (permission == LocationPermission.denied) {
        throw StateError(
          'Location permission is needed to capture the shop entrance.',
        );
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 25),
        ),
      );
      if (mounted) {
        setState(() {
          _latitude.text = position.latitude.toStringAsFixed(7);
          _longitude.text = position.longitude.toStringAsFixed(7);
          _verified = false;
          _locationMessage =
              'Captured location • accuracy about ${position.accuracy.round()} m. '
              '${position.accuracy > 50 ? 'The signal is weak. Move outdoors and try again. ' : ''}'
              'Preview the pin, then confirm it is the delivery entrance.';
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
      'query': '${_latitude.text.trim()},${_longitude.text.trim()}',
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

  Future<void> _readMapsLink() async {
    setState(() => _resolving = true);
    try {
      final pin = await MapsLinkResolver().resolve(_mapsUrl.text.trim());
      if (!mounted) return;
      setState(() {
        _verified = false;
        // Never retain a previous shop's coordinates after reading a new link.
        _latitude.text = pin?.latitude.toStringAsFixed(7) ?? '';
        _longitude.text = pin?.longitude.toStringAsFixed(7) ?? '';
        _locationMessage = pin == null
            ? 'Maps location saved. This shop can be added to a delivery list using the link; extracting GPS is optional.'
            : 'Pin read from the link. The saved Maps location is ready for delivery.';
      });
    } catch (error) {
      if (mounted) showMessage(context, errorText(error));
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final lat = _latitude.text.trim(), lng = _longitude.text.trim();
    if ((lat.isNotEmpty || lng.isNotEmpty) && !_hasCoordinates) {
      showMessage(
        context,
        'Enter valid latitude and longitude together, or leave both empty.',
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.controller.saveShop(
        Shop(
          id: _id,
          name: _name.text.trim(),
          area: _area.text.trim().isEmpty ? 'Area not set' : _area.text.trim(),
          address: _address.text.trim(),
          landmark: _landmark.text.trim(),
          phone: _phone.text.trim(),
          notes: _notes.text.trim(),
          mapsUrl: _mapsUrl.text.trim(),
          latitude: double.tryParse(lat),
          longitude: double.tryParse(lng),
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

  Widget _field(
    TextEditingController controller,
    String label, {
    bool required = false,
    int lines = 1,
    int maxLength = 200,
    TextInputType? keyboard,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: controller,
      enabled: !_saving,
      maxLines: lines,
      maxLength: maxLength,
      keyboardType: keyboard,
      textCapitalization: keyboard == null
          ? TextCapitalization.sentences
          : TextCapitalization.none,
      decoration: InputDecoration(labelText: label, counterText: ''),
      validator: (v) =>
          required && (v == null || v.trim().isEmpty) ? 'Enter $label.' : null,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final photo = _pickedPhoto ?? widget.shop?.localPhotoPath;
    return PopScope(
      canPop: !_saving && !_resolving,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.shop == null ? 'Add shop' : 'Edit shop'),
          actions: [
            TextButton(
              onPressed: _saving || _locating || _resolving ? null : _save,
              child: const Text('Save'),
            ),
          ],
        ),
        body: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const WorkspaceLabel('Shop profile'),
              const SizedBox(height: 10),
              Text(
                widget.shop == null
                    ? 'Add to your directory'
                    : 'Keep shop details up to date',
                style: const TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.w800,
                  color: WorkspaceColors.ink,
                  letterSpacing: -.6,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Start with the shop name. Paste its Google Maps location or capture the entrance location during a visit.',
              ),
              const SizedBox(height: 24),
              if (photo != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Image.file(
                      File(photo),
                      height: 180,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox(
                        height: 60,
                        child: Center(child: Text('Photo unavailable')),
                      ),
                    ),
                  ),
                ),
              Wrap(
                spacing: 10,
                children: [
                  OutlinedButton.icon(
                    onPressed: _saving
                        ? null
                        : () => _photo(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Take photo'),
                  ),
                  TextButton.icon(
                    onPressed: _saving
                        ? null
                        : () => _photo(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Choose photo'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _field(_name, 'Shop name', required: true),
              _field(_area, 'Area'),
              _field(
                _phone,
                'Contact number',
                maxLength: 30,
                keyboard: TextInputType.phone,
              ),
              _field(_address, 'Address', lines: 2, maxLength: 1000),
              _field(_landmark, 'Landmark', maxLength: 500),
              _field(
                _notes,
                'Delivery instructions',
                lines: 3,
                maxLength: 1000,
              ),
              const Text(
                'Delivery entrance',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                'Paste the shop’s Google Maps share link. No latitude or longitude is required. You can also capture your current location at the shop entrance.',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _mapsUrl,
                enabled: !_saving && !_resolving && !_locating,
                maxLength: 4096,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Google Maps link (optional)',
                  hintText: 'Paste the shop or dropped-pin share link',
                  counterText: '',
                ),
                onChanged: (_) => setState(() {
                  _verified = false;
                  _latitude.clear();
                  _longitude.clear();
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
              ),
              if (_hasMapsLink)
                const Padding(
                  padding: EdgeInsets.only(top: 8, bottom: 12),
                  child: WorkspaceBadge(
                    'Maps location ready for delivery',
                    icon: Icons.check_circle_outline,
                  ),
                ),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed:
                        _saving ||
                            _locating ||
                            _resolving ||
                            _mapsUrl.text.trim().isEmpty
                        ? null
                        : _readMapsLink,
                    icon: const Icon(Icons.link),
                    label: Text(
                      _resolving ? 'Reading link…' : 'Read pin from link',
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _saving || _resolving
                        ? null
                        : () => _openMap(
                            shopSearchUri(
                              _name.text,
                              _address.text,
                              _area.text,
                            ),
                          ),
                    icon: const Icon(Icons.search),
                    label: const Text('Search Google Maps'),
                  ),
                  if (_mapsUrl.text.trim().isNotEmpty)
                    TextButton(
                      onPressed: _saving || _resolving
                          ? null
                          : () => runAction(
                              context,
                              () => _openMap(googleMapsUri(_mapsUrl.text)),
                            ),
                      child: const Text('Open pasted link'),
                    ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Shop not listed on Google? Long-press its entrance on Maps to drop a pin, then paste the share link. You can also save its address and landmark and add a location during a visit.',
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: _locating || _saving || _resolving
                    ? null
                    : _captureLocation,
                icon: _locating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location),
                label: Text(
                  _locating ? 'Finding location…' : 'Capture current location',
                ),
              ),
              if (_locationMessage != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(_locationMessage!),
                ),
              if (_settingsNeeded)
                TextButton(
                  onPressed: Geolocator.openAppSettings,
                  child: const Text('Open app settings'),
                ),
              const SizedBox(height: 16),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Coordinates (optional)'),
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _latitude,
                          enabled: !_saving && !_locating && !_resolving,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Latitude',
                          ),
                          onChanged: (_) => setState(() => _verified = false),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _longitude,
                          enabled: !_saving && !_locating && !_resolving,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Longitude',
                          ),
                          onChanged: (_) => setState(() => _verified = false),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed:
                    (_hasCoordinates || _hasMapsLink) &&
                        !_saving &&
                        !_locating &&
                        !_resolving
                    ? () => _hasMapsLink
                          ? _openMap(googleMapsUri(_mapsUrl.text))
                          : _preview()
                    : null,
                icon: const Icon(Icons.map_outlined),
                label: const Text('Preview location in Maps'),
              ),
              if (!_hasMapsLink)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _verified,
                  title: const Text(
                    'I checked this is the correct delivery entrance',
                  ),
                  subtitle: const Text(
                    'Confirm captured or manually entered coordinates. A saved Google Maps link is ready without this step.',
                  ),
                  onChanged:
                      _hasCoordinates && !_saving && !_locating && !_resolving
                      ? (v) => setState(() => _verified = v ?? false)
                      : null,
                ),
              if (widget.controller.shared)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'An internet connection is needed to save shared shop changes.',
                  ),
                ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _saving || _locating || _resolving ? null : _save,
                child: Text(_saving ? 'Saving shop…' : 'Save shop'),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
