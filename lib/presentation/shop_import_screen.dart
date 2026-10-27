import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../application/delivery_controller.dart';
import '../domain/shop_import.dart';
import 'common.dart';

class ShopImportScreen extends StatefulWidget {
  const ShopImportScreen({super.key, required this.controller});
  final DeliveryController controller;
  @override
  State<ShopImportScreen> createState() => _ShopImportScreenState();
}

class _ShopImportScreenState extends State<ShopImportScreen> {
  List<ShopImportSheet> _sheets = [];
  int _sheet = 0, _completed = 0, _total = 0;
  String? _fileName, _error;
  bool _working = false;
  ShopImportResult? _result;

  Future<void> _template() async {
    setState(() => _working = true);
    try {
      await FilePicker.saveFile(
        fileName: 'GM_Shops_Template.xlsx',
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        bytes: createShopImportTemplate(),
      );
    } catch (error) {
      if (mounted) showMessage(context, errorText(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _choose() async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );
      if (file == null) return;
      final size = await file.length();
      if (size != null && size > 5 * 1024 * 1024) {
        throw const FormatException('Choose an .xlsx file smaller than 5 MB.');
      }
      final sheets = await compute(parseShopWorkbook, await file.readAsBytes());
      if (!mounted) return;
      setState(() {
        _sheets = sheets;
        _sheet = 0;
        _fileName = file.name;
        _result = null;
        _completed = 0;
        _total = 0;
      });
    } catch (error) {
      if (mounted) setState(() => _error = errorText(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _import() async {
    setState(() {
      _working = true;
      _error = null;
      _result = null;
      _completed = 0;
      _total = _sheets[_sheet].rows.length;
    });
    try {
      final result = await widget.controller.importShops(
        _sheets[_sheet].rows,
        onProgress: (done, total) {
          if (mounted) {
            setState(() {
              _completed = done;
              _total = total;
            });
          }
        },
      );
      if (mounted) setState(() => _result = result);
    } catch (error) {
      if (mounted) setState(() => _error = errorText(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.controller.isOwner) {
      return Scaffold(
        appBar: AppBar(title: const Text('Import shops')),
        body: const Center(child: Text('Only owners can import shops.')),
      );
    }
    final selected = _sheets.isEmpty ? null : _sheets[_sheet];
    final seen = widget.controller.shops.map(shopImportKey).toSet();
    final duplicates = <int>{};
    var valid = 0, invalid = 0, unlocated = 0;
    for (final row in selected?.rows ?? <ShopImportRow>[]) {
      final shop = row.shop;
      if (shop == null) {
        invalid++;
        continue;
      }
      if (!seen.add(shopImportKey(shop))) {
        duplicates.add(row.number);
        continue;
      }
      valid++;
      if (!shop.hasLocation) unlocated++;
    }
    return PopScope(
      canPop: !_working,
      child: Scaffold(
        appBar: AppBar(title: const Text('Import shops from Excel')),
        body: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Bring your whole directory',
                      style: TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Use Name and Location columns. Location can be a Google Maps link, address or blank. Optional: Area, Phone, Landmark, Delivery instructions, Latitude, Longitude, Opening balance (in rupees). Shop details are preserved on retry; an existing opening balance is never overwritten.',
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: _working ? null : _choose,
                          icon: const Icon(Icons.upload_file),
                          label: const Text('Choose Excel file'),
                        ),
                        TextButton.icon(
                          onPressed: _working ? null : _template,
                          icon: const Icon(Icons.download_outlined),
                          label: const Text('Save template'),
                        ),
                      ],
                    ),
                    if (_fileName != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _fileName!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    if (_sheets.length > 1)
                      DropdownButton<int>(
                        isExpanded: true,
                        value: _sheet,
                        items: [
                          for (var i = 0; i < _sheets.length; i++)
                            DropdownMenuItem(
                              value: i,
                              child: Text(_sheets[i].name),
                            ),
                        ],
                        onChanged: _working
                            ? null
                            : (value) => setState(() {
                                _sheet = value!;
                                _result = null;
                                _error = null;
                              }),
                      ),
                    if (selected != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          '$valid new • ${duplicates.length} possible duplicates • $invalid invalid\n$unlocated new shops need a location. Maps links are ready for delivery; coordinate-only pins need verification.',
                        ),
                      ),
                    if (selected?.error != null)
                      Text(
                        selected!.error!,
                        style: const TextStyle(color: Colors.deepOrange),
                      ),
                    if (_error != null)
                      Text(
                        _error!,
                        style: const TextStyle(color: Colors.deepOrange),
                      ),
                    if (_working) ...[
                      const SizedBox(height: 10),
                      LinearProgressIndicator(
                        value: _total == 0 ? null : _completed / _total,
                      ),
                      if (_total > 0)
                        Text('Reviewed $_completed of $_total rows'),
                    ],
                    if (_result != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          '${_result!.saved} imported • ${_result!.skipped} skipped • ${_result!.failures.length} not imported\nYou can correct failed rows and retry the file. Existing shops are preserved.',
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (selected == null)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text('Choose an .xlsx file to preview its rows.'),
                ),
              )
            else
              SliverList.builder(
                itemCount: selected.rows.length,
                itemBuilder: (context, index) {
                  final row = selected.rows[index];
                  final issue = _result?.failures[row.number] ?? row.error;
                  final duplicate = duplicates.contains(row.number);
                  return ListTile(
                    leading: Icon(
                      issue != null
                          ? Icons.error_outline
                          : duplicate
                          ? Icons.copy_outlined
                          : Icons.storefront_outlined,
                      color: issue != null || duplicate
                          ? Colors.deepOrange
                          : null,
                    ),
                    title: Text(
                      'Row ${row.number}: ${row.name.isEmpty ? '(missing name)' : row.name}',
                    ),
                    subtitle: Text(
                      issue ??
                          (duplicate
                              ? (_result == null
                                    ? 'Possible duplicate — skipped; review same-name branches separately.'
                                    : 'In your directory; preserved on retry.')
                              : '${row.shop!.area} • ${row.shop!.locationStatus}'),
                    ),
                  );
                },
              ),
          ],
        ),
        bottomNavigationBar: selected == null
            ? null
            : SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed:
                          _working || valid == 0 || selected.error != null
                          ? null
                          : _import,
                      icon: const Icon(Icons.playlist_add_check),
                      label: Text(
                        _working
                            ? 'Please wait…'
                            : _result == null
                            ? 'Import $valid new shops'
                            : 'Retry remaining rows',
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
