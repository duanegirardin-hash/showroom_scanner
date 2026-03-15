// Showroom Scanner - sound paths: use sounds/... with prefix assets/ to avoid double assets/ (2025-03-11)
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  runApp(const ShowroomScannerApp());
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
      composing: TextRange.empty,
    );
  }
}

class ShowroomScannerApp extends StatelessWidget {
  const ShowroomScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Showroom Scanner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
      ),
      home: const ScannerHomePage(),
    );
  }
}

class Product {
  final String itemNumber;
  final String description;
  final String upc;
  final double price;
  final String category;
  final String subCategory;
  final int minOrderQty;
  final int caseQty;

  Product({
    required this.itemNumber,
    required this.description,
    required this.upc,
    required this.price,
    required this.category,
    required this.subCategory,
    required this.minOrderQty,
    required this.caseQty,
  });
}

class OrderLine {
  final Product product;
  int quantity;
  int scans;

  OrderLine({
    required this.product,
    required this.quantity,
    required this.scans,
  });

  double get lineTotal => quantity * product.price;
}

enum ScanFeedbackType {
  none,
  successNewItem,
  successExistingItem,
  notFound,
}

/// Saved quote entry in the index (for Load Quote list).
class SavedQuoteInfo {
  final String id;
  final String name;
  final DateTime updatedAt;

  SavedQuoteInfo({
    required this.id,
    required this.name,
    required this.updatedAt,
  });

  factory SavedQuoteInfo.fromJson(Map<String, dynamic> json) {
    return SavedQuoteInfo(
      id: json['id'] as String,
      name: (json['name'] as String?)?.trim() ?? '',
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'updatedAt': updatedAt.toIso8601String(),
  };
}

/// Customer from customers.csv (headers: Id, CompanyName, Address, ...).
class Customer {
  final String id;
  final String companyName;
  final String address;
  final String address2;
  final String city;
  final String state;
  final String zip;
  final String phone;
  final String fax;
  final String email;
  final String contact;
  final String salesRepName;
  final String priceList;
  final String discount;
  final String paymentTerms;

  Customer({
    required this.id,
    required this.companyName,
    required this.address,
    required this.address2,
    required this.city,
    required this.state,
    required this.zip,
    required this.phone,
    required this.fax,
    required this.email,
    required this.contact,
    required this.salesRepName,
    required this.priceList,
    required this.discount,
    required this.paymentTerms,
  });

  String get displayName =>
      companyName.trim().isNotEmpty ? companyName : id;

  Map<String, dynamic> toJson() => {
        'id': id,
        'companyName': companyName,
        'address': address,
        'address2': address2,
        'city': city,
        'state': state,
        'zip': zip,
        'phone': phone,
        'fax': fax,
        'email': email,
        'contact': contact,
        'salesRepName': salesRepName,
        'priceList': priceList,
        'discount': discount,
        'paymentTerms': paymentTerms,
      };

  static Customer fromJson(Map<String, dynamic> json) {
    String s(String key) => (json[key] as String?)?.trim() ?? '';
    return Customer(
      id: s('id'),
      companyName: s('companyName'),
      address: s('address'),
      address2: s('address2'),
      city: s('city'),
      state: s('state'),
      zip: s('zip'),
      phone: s('phone'),
      fax: s('fax'),
      email: s('email'),
      contact: s('contact'),
      salesRepName: s('salesRepName'),
      priceList: s('priceList'),
      discount: s('discount'),
      paymentTerms: s('paymentTerms'),
    );
  }
}

class ScannerHomePage extends StatefulWidget {
  const ScannerHomePage({super.key});

  @override
  State<ScannerHomePage> createState() => _ScannerHomePageState();
}

/// Load Quote dialog content. Owns the search TextEditingController and disposes it
/// when the dialog is closed, avoiding "used after being disposed" when deleting the last quote.
class _LoadQuoteDialogContent extends StatefulWidget {
  const _LoadQuoteDialogContent({
    required this.allQuotes,
    required this.formatDate,
    required this.dialogContext,
    required this.onRemoveQuote,
    required this.onShareQuote,
  });

  final List<SavedQuoteInfo> allQuotes;
  final String Function(DateTime) formatDate;
  final BuildContext dialogContext;
  final Future<void> Function(String id) onRemoveQuote;
  final void Function(String id, String name) onShareQuote;

  @override
  State<_LoadQuoteDialogContent> createState() => _LoadQuoteDialogContentState();
}

class _LoadQuoteDialogContentState extends State<_LoadQuoteDialogContent> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _searchController.text.trim().toLowerCase();
    final filtered = widget.allQuotes
        .where((info) {
          final name = info.name.toLowerCase();
          final dateText = widget.formatDate(info.updatedAt).toLowerCase();
          return q.isEmpty ||
              name.contains(q) ||
              dateText.contains(q);
        })
        .toList();

    return SizedBox(
      width: double.maxFinite,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tap a quote to load it. Email to share; remove only after emailing or saving elsewhere.',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _searchController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Search quotes',
              hintText: 'Type quote name',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: Text(
                  'No matching quotes',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            SizedBox(
              height: filtered.length > 5 ? 280 : null,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: filtered.length,
                itemBuilder: (_, i) {
                  final info = filtered[i];
                  return ListTile(
                    title: Text(
                      info.name.isEmpty ? 'Unnamed quote' : info.name,
                    ),
                    subtitle: Text(widget.formatDate(info.updatedAt)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.email_outlined),
                          tooltip: 'Email / Share quote',
                          onPressed: () =>
                              widget.onShareQuote(info.id, info.name),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip:
                              'Remove from list (after emailing or saving)',
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (c) => AlertDialog(
                                title: const Text('Remove quote?'),
                                content: const Text(
                                  'Remove this quote from the list? The file will be deleted.\n\n'
                                  'Only do this after you have emailed or saved the quote elsewhere. This cannot be undone.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(c, false),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(c, true),
                                    child: const Text('Remove'),
                                  ),
                                ],
                              ),
                            );

                            if (confirm == true && mounted) {
                              await widget.onRemoveQuote(info.id);
                              widget.allQuotes.removeWhere(
                                  (e) => e.id == info.id);
                              if (mounted) {
                                Navigator.of(widget.dialogContext)
                                    .pop('removed:${info.id}');
                              }
                            }
                          },
                        ),
                      ],
                    ),
                    onTap: () =>
                        Navigator.of(widget.dialogContext).pop(info.id),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _ScannerHomePageState extends State<ScannerHomePage> {
  final FocusNode _scannerFocusNode = FocusNode();
  final TextEditingController _scannerController = TextEditingController();

  final FocusNode _quickEntryFocusNode = FocusNode();
  final TextEditingController _quickEntryController = TextEditingController();

  final FocusNode _quoteNameFocusNode = FocusNode();
  final TextEditingController _quoteNameController = TextEditingController(
    text: 'NEW QUOTE',
  );

  final ScrollController _scrollController = ScrollController();

  final Map<String, Product> _productsByUpc = {};
  final Map<String, Product> _productsByItemNumber = {};

  final List<OrderLine> _orderLines = [];
  final Map<String, OrderLine> _orderLineByUpc = {};

  Timer? _scanDebounceTimer;
  Timer? _refocusTimer;
  Timer? _scanFeedbackTimer;
  Timer? _quoteNameBarcodeDebounce;

  late final AudioPlayer _goodScanPlayer;
  late final AudioPlayer _goodScanPlayer2;
  late final AudioPlayer _errorScanPlayer;

  String _lastScan = '-';
  String _lastItem = '-';
  String _status = 'Loading products...';
  String _quickEntryStatus = '-';
  String _catalogSource = 'Built-in catalog';

  int _itemsScanned = 0;
  int _totalUnits = 0;
  double _orderTotal = 0.0;
  int _qtyAdded = 0;
  int _catalogCount = 0;
  String? _lastAddedUpc;

  bool _readyToScan = false;
  bool _loadingProducts = true;
  bool _editDialogOpen = false;

  /// Quote name to restore when a barcode was mistakenly entered in the quote name field
  String _savedQuoteNameBeforeEdit = 'NEW QUOTE';

  /// Incremented when loading a quote so the order list widget is recreated and items display
  int _orderListVersion = 0;

  OrderLine? _selectedLine;
  ScanFeedbackType _scanFeedbackType = ScanFeedbackType.none;

  /// Prevent double beep: ignore same barcode if processed within this window (ms).
  static const int _scanDedupeMs = 650;
  String? _lastProcessedScanUpc;
  DateTime? _lastProcessedScanTime;

  /// Success scan count: 1st valid scan = single beep, 2nd+ = double beep. Reset on fail or new quote.
  int _scanCount = 0;
  /// Last scanned UPC: reset _scanCount when barcode != _lastUPC so new item = single, same item repeat = double.
  String _lastUPC = '';
  /// UPCs that have already played double-beep at least once; future scans of that item stay double (no reset when switching items).
  final Set<String> _doubleBeepUPCs = {};

  List<Customer> _customers = [];
  Customer? _selectedCustomer;
  /// When non-null, Save Quote updates this quote instead of creating a new one.
  String? _currentQuoteId;

  @override
  void initState() {
    super.initState();

    _goodScanPlayer = AudioPlayer();
    _goodScanPlayer2 = AudioPlayer();
    _errorScanPlayer = AudioPlayer();

    _loadProductsFromAssets();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestScannerFocus();
    });

    Future.delayed(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      if (!_scannerFocusNode.hasFocus && !_editDialogOpen) {
        _requestScannerFocus();
      }
    });
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted || _editDialogOpen) return;
      if (!_scannerFocusNode.hasFocus) _requestScannerFocus();
    });
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted || _editDialogOpen) return;
      if (!_scannerFocusNode.hasFocus) _requestScannerFocus();
    });

    _scannerFocusNode.addListener(() {
      if (!_scannerFocusNode.hasFocus &&
          !_quickEntryFocusNode.hasFocus &&
          !_quoteNameFocusNode.hasFocus &&
          !_editDialogOpen) {
        _scheduleScannerRefocus();
      }
    });

    _quoteNameFocusNode.addListener(() {
      if (_quoteNameFocusNode.hasFocus) {
        _savedQuoteNameBeforeEdit = _quoteNameController.text.trim().isEmpty
            ? 'NEW QUOTE'
            : _quoteNameController.text.trim().toUpperCase();
      }
    });

    _quoteNameController.addListener(_onQuoteNameChanged);
  }

  void _onQuoteNameChanged() {
    if (!_quoteNameFocusNode.hasFocus) return;

    _quoteNameBarcodeDebounce?.cancel();

    final text = _quoteNameController.text.trim();
    final digits = digitsOnly(text);

    if (digits.length >= 8 && digits == text) {
      _quoteNameBarcodeDebounce = Timer(const Duration(milliseconds: 80), () {
        if (!mounted) return;

        final t = _quoteNameController.text.trim();
        final d = digitsOnly(t);

        if (d.length >= 8 && d == t) {
          _quoteNameController.text = _savedQuoteNameBeforeEdit;
          _quoteNameController.selection = TextSelection.collapsed(
            offset: _savedQuoteNameBeforeEdit.length,
          );
          _processScan(t);
          _requestScannerFocus();
        }

        _quoteNameBarcodeDebounce = null;
      });
    }
  }

  Future<void> _initAudio() async {
    try {
      final ctx = AudioContext(
        android: AudioContextAndroid(
          audioFocus: AndroidAudioFocus.gainTransientMayDuck,
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.assistanceSonification,
        ),
        iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
      );

      await AudioPlayer.global.setAudioContext(ctx);

      final scanAudioCache = AudioCache(prefix: '');
      _goodScanPlayer.audioCache = scanAudioCache;
      _goodScanPlayer2.audioCache = scanAudioCache;
      _errorScanPlayer.audioCache = scanAudioCache;

      await _goodScanPlayer.setReleaseMode(ReleaseMode.stop);
      await _goodScanPlayer2.setReleaseMode(ReleaseMode.stop);
      await _errorScanPlayer.setReleaseMode(ReleaseMode.stop);

      // Do not pre-load any players: on Android, prepared players get stop/pause in wrong state (-38)
      // and break first beep / double beep until 3rd–4th scan. Load on first play instead.

      debugPrint('[Audio] initialized OK');
    } catch (e) {
      debugPrint('[Audio] init error: $e');
    }
  }

  @override
  void dispose() {
    _scanCount = 0;
    _lastUPC = '';
    _doubleBeepUPCs.clear();
    _scanDebounceTimer?.cancel();
    _refocusTimer?.cancel();
    _scanFeedbackTimer?.cancel();
    _quoteNameBarcodeDebounce?.cancel();
    _quoteNameController.removeListener(_onQuoteNameChanged);

    _goodScanPlayer.dispose();
    _goodScanPlayer2.dispose();
    _errorScanPlayer.dispose();

    _scannerFocusNode.dispose();
    _scannerController.dispose();

    _quickEntryFocusNode.dispose();
    _quickEntryController.dispose();

    _quoteNameFocusNode.dispose();
    _quoteNameController.dispose();

    _scrollController.dispose();
    super.dispose();
  }

  void _scheduleScannerRefocus() {
    _refocusTimer?.cancel();
    _refocusTimer = Timer(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      if (_editDialogOpen) return;

      if (!_quickEntryFocusNode.hasFocus && !_quoteNameFocusNode.hasFocus) {
        _requestScannerFocus();
      }
    });
  }

  void _requestScannerFocus() {
    if (!mounted) return;
    if (_editDialogOpen) return;

    FocusScope.of(context).requestFocus(_scannerFocusNode);

    const delays = [30, 90, 180, 350, 550, 800, 1200];
    for (final ms in delays) {
      Future.delayed(Duration(milliseconds: ms), () {
        if (!mounted || _editDialogOpen) return;
        if (!_scannerFocusNode.hasFocus) {
          FocusScope.of(context).requestFocus(_scannerFocusNode);
        }
      });
    }

    Future.microtask(() {
      if (!_editDialogOpen) {
        SystemChannels.textInput.invokeMethod('TextInput.hide');
      }
    });
  }

  void _triggerScanFeedback(ScanFeedbackType type) {
    _scanFeedbackTimer?.cancel();

    setState(() {
      _scanFeedbackType = type;
    });

    if (type == ScanFeedbackType.successNewItem ||
        type == ScanFeedbackType.successExistingItem) {
      _scanCount++;
      _playGoodScanBeep();
      HapticFeedback.selectionClick();
    } else if (type == ScanFeedbackType.notFound) {
      _scanCount = 0;
      _playErrorBuzz();
      HapticFeedback.vibrate();
    }

    _scanFeedbackTimer = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      setState(() {
        _scanFeedbackType = ScanFeedbackType.none;
      });
    });
  }

  static const String _goodScanAsset = 'assets/sounds/good_scan.mp3';
  static const String _goodScan2Asset = 'assets/sounds/good_scan2.mp3';
  static const String _errorScanAsset = 'assets/sounds/error_scan.wav';

  Future<void> _playGoodScanBeep() async {
    try {
      // Once an item has been double-beeped, every future scan of that item stays double (no reset when switching items).
      final bool isSingle = !_doubleBeepUPCs.contains(_lastUPC) && _scanCount <= 1;
      if (!isSingle) _doubleBeepUPCs.add(_lastUPC);
      debugPrint(
        'Playing ${isSingle ? 'single' : 'double'} beep (scanCount=$_scanCount)',
      );

      // Stop both players so no overlap and so the one we use is in a clean state.
      await _goodScanPlayer.stop();
      await _goodScanPlayer2.stop();
      await Future.delayed(const Duration(milliseconds: 80));

      if (!mounted) return;

      // Use separate players so we never swap source on the same player (avoids second-play silent on Android).
      if (isSingle) {
        await _goodScanPlayer.setSource(AssetSource(_goodScanAsset));
        if (!mounted) return;
        await _goodScanPlayer.seek(Duration.zero);
        await _goodScanPlayer.resume();
      } else {
        await _goodScanPlayer2.setSource(AssetSource(_goodScan2Asset));
        if (!mounted) return;
        // Give Android time to load the asset so second beep actually plays.
        await Future.delayed(const Duration(milliseconds: 60));
        if (!mounted) return;
        await _goodScanPlayer2.seek(Duration.zero);
        await _goodScanPlayer2.resume();
      }
      debugPrint('Play attempt');
    } catch (e) {
      debugPrint('[Audio] good beep error: $e');
    }
  }

  Future<void> _playErrorBuzz() async {
    bool soundPlayed = false;
    try {
      // Avoid stop() before play: on some Android devices it puts MediaPlayer in error state (-38)
      await _errorScanPlayer.setVolume(1.0);
      await _errorScanPlayer.setPlaybackRate(1.0);
      await _errorScanPlayer.setSource(AssetSource(_errorScanAsset));
      await _errorScanPlayer.resume();
      soundPlayed = true;
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _errorScanPlayer.stop();
      });
    } catch (e) {
      debugPrint('[Audio] error buzz error: $e');
    }
    // If asset sound never played, use system alert so user always hears something on bad scan
    if (!soundPlayed && mounted) {
      SystemSound.play(SystemSoundType.alert);
    }
  }

  String digitsOnly(String value) {
    return value.replaceAll(RegExp(r'[^0-9]'), '').trim();
  }

  String normalizeItemNumber(String value) {
    return value.trim().toUpperCase();
  }

  double _parsePrice(String value) {
    final cleaned = value.replaceAll('\$', '').replaceAll(',', '').trim();
    return double.tryParse(cleaned) ?? 0.0;
  }

  int _parseInt(String value) {
    return int.tryParse(value.trim()) ?? 0;
  }

  void _parseAndStoreProducts(String rawCsv, {required String sourceLabel}) {
    final rows = const CsvToListConverter(
      shouldParseNumbers: false,
    ).convert(rawCsv);

    final Map<String, Product> newProductsByUpc = {};
    final Map<String, Product> newProductsByItemNumber = {};

    for (int i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.length < 8) continue;

      final itemNumber = normalizeItemNumber(row[0].toString());
      final description = row[1].toString().trim();
      final upc = digitsOnly(row[2].toString());
      final price = _parsePrice(row[3].toString());
      final category = row[4].toString().trim();
      final subCategory = row[5].toString().trim();
      final minOrderQty = _parseInt(row[6].toString());
      final caseQty = _parseInt(row[7].toString());

      if (itemNumber.isEmpty || upc.isEmpty) continue;

      final product = Product(
        itemNumber: itemNumber,
        description: description,
        upc: upc,
        price: price,
        category: category,
        subCategory: subCategory,
        minOrderQty: minOrderQty == 0 ? 1 : minOrderQty,
        caseQty: caseQty,
      );

      newProductsByUpc[upc] = product;
      newProductsByItemNumber[itemNumber] = product;
    }

    _productsByUpc
      ..clear()
      ..addAll(newProductsByUpc);

    _productsByItemNumber
      ..clear()
      ..addAll(newProductsByItemNumber);

    _catalogCount = _productsByUpc.length;
    _catalogSource = sourceLabel;
  }

  Future<void> _loadProductsFromAssets() async {
    try {
      await _initAudio();
      final rawCsv = await rootBundle.loadString('assets/data/products.csv');

      _parseAndStoreProducts(rawCsv, sourceLabel: 'Built-in catalog');
      await _loadCustomersFromAssets();

      setState(() {
        _loadingProducts = false;
        _readyToScan = true;
        _status = 'Ready to scan';
      });

      _requestScannerFocus();
    } catch (e) {
      setState(() {
        _loadingProducts = false;
        _readyToScan = false;
        _status = 'Error loading built-in catalog';
        _catalogCount = 0;
      });
    }
  }

  /// Load customers from assets/data/customers.csv if present (optional).
  Future<void> _loadCustomersFromAssets() async {
    try {
      final rawCsv =
          await rootBundle.loadString('assets/data/customers.csv');
      _parseAndStoreCustomers(rawCsv);
    } catch (_) {
      // Optional asset; leave _customers empty if missing
    }
  }

  Future<void> _loadCsvFromPhone() async {
    try {
      _editDialogOpen = true;

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true,
      );

      _editDialogOpen = false;

      if (result == null || result.files.isEmpty) {
        setState(() {
          _status = 'CSV load cancelled';
        });
        _requestScannerFocus();
        return;
      }

      final file = result.files.single;
      String? rawCsv;

      if (file.bytes != null) {
        rawCsv = utf8.decode(file.bytes!);
      } else if (file.path != null) {
        rawCsv = await File(file.path!).readAsString();
      }

      if (rawCsv == null || rawCsv.trim().isEmpty) {
        setState(() {
          _status = 'Selected CSV was empty';
        });
        _requestScannerFocus();
        return;
      }

      _parseAndStoreProducts(rawCsv, sourceLabel: file.name);

      setState(() {
        _readyToScan = true;
        _loadingProducts = false;
        _status = 'Loaded CSV: ${file.name}';
      });
    } catch (e) {
      _editDialogOpen = false;
      setState(() {
        _status = 'Error loading CSV from phone';
      });
    }

    _requestScannerFocus();
  }

  /// Customers.csv headers: Id, CompanyName, Address, Address2, City, State, Zip, Phone, Fax, Email, Contact, SalesRepName, PriceList, Discount, PaymentTerms.
  void _parseAndStoreCustomers(String rawCsv) {
    final firstLine = rawCsv.split('\n').first;
    final useTab =
        firstLine.split('\t').length > firstLine.split(',').length;
    final rows = CsvToListConverter(
      shouldParseNumbers: false,
      fieldDelimiter: useTab ? '\t' : ',',
    ).convert(rawCsv);
    if (rows.isEmpty) {
      setState(() => _customers = []);
      return;
    }
    final headerRow = rows[0].map((e) => e.toString().trim()).toList();
    int col(String name) {
      final i = headerRow.indexOf(name);
      return i >= 0 ? i : -1;
    }
    final idxId = col('Id');
    final idxCompanyName = col('CompanyName');
    final idxAddress = col('Address');
    final idxAddress2 = col('Address2');
    final idxCity = col('City');
    final idxState = col('State');
    final idxZip = col('Zip');
    final idxPhone = col('Phone');
    final idxFax = col('Fax');
    final idxEmail = col('Email');
    final idxContact = col('Contact');
    final idxSalesRepName = col('SalesRepName');
    final idxPriceList = col('PriceList');
    final idxDiscount = col('Discount');
    final idxPaymentTerms = col('PaymentTerms');
    if (idxId < 0 && idxCompanyName < 0) {
      setState(() {
        _customers = [];
        _status = 'Customers CSV must have Id or CompanyName column';
      });
      return;
    }
    final list = <Customer>[];
    for (int i = 1; i < rows.length; i++) {
      final row = rows[i];
      String get(int index) =>
          index >= 0 && index < row.length ? row[index].toString().trim() : '';
      final idVal = idxId >= 0 ? get(idxId) : get(idxCompanyName);
      list.add(Customer(
        id: idVal,
        companyName: get(idxCompanyName),
        address: get(idxAddress),
        address2: get(idxAddress2),
        city: get(idxCity),
        state: get(idxState),
        zip: get(idxZip),
        phone: get(idxPhone),
        fax: get(idxFax),
        email: get(idxEmail),
        contact: get(idxContact),
        salesRepName: get(idxSalesRepName),
        priceList: get(idxPriceList),
        discount: get(idxDiscount),
        paymentTerms: get(idxPaymentTerms),
      ));
    }
    setState(() {
      _customers = list;
      _selectedCustomer = null;
    });
  }

  Future<void> _loadCustomersCsvFromPhone() async {
    try {
      _editDialogOpen = true;
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true,
      );
      _editDialogOpen = false;
      if (result == null || result.files.isEmpty) {
        setState(() => _status = 'Customers CSV load cancelled');
        _requestScannerFocus();
        return;
      }
      final file = result.files.single;
      String? rawCsv;
      if (file.bytes != null) {
        rawCsv = utf8.decode(file.bytes!);
      } else if (file.path != null) {
        rawCsv = await File(file.path!).readAsString();
      }
      if (rawCsv == null || rawCsv.trim().isEmpty) {
        setState(() => _status = 'Selected customers CSV was empty');
        _requestScannerFocus();
        return;
      }
      _parseAndStoreCustomers(rawCsv);
      setState(() => _status = 'Loaded customers from ${file.name}');
    } catch (e) {
      _editDialogOpen = false;
      setState(() => _status = 'Error loading customers CSV');
    }
    _requestScannerFocus();
  }

  Future<void> _showSelectCustomerDialog() async {
    if (_customers.isEmpty) return;
    _editDialogOpen = true;
    final searchController = TextEditingController();
    final filtered = <Customer>[];
    filtered.addAll(_customers);
    final picked = await showDialog<Customer>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void applyCustomerFilter(String query) {
              final q = query.trim().toLowerCase();
              filtered
                ..clear()
                ..addAll(_customers.where((c) {
                  if (q.isEmpty) return true;
                  return c.displayName.toLowerCase().contains(q) ||
                      c.contact.toLowerCase().contains(q) ||
                      c.email.toLowerCase().contains(q) ||
                      c.companyName.toLowerCase().contains(q) ||
                      c.city.toLowerCase().contains(q) ||
                      c.state.toLowerCase().contains(q);
                }));
              setDialogState(() {});
            }
            return AlertDialog(
              title: const Text('Select Customer'),
              content: SizedBox(
                width: 400,
                height: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: searchController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Search customers',
                        hintText: 'Name, contact, email...',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: applyCustomerFilter,
                    ),
                    const SizedBox(height: 10),
                    Flexible(
                      child: filtered.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(18),
                                child: Text('No matching customers'),
                              ),
                            )
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (_, i) {
                                final c = filtered[i];
                                return ListTile(
                                  title: Text(c.displayName),
                                  subtitle: c.contact.isEmpty
                                      ? null
                                      : Text(c.contact),
                                  onTap: () => Navigator.pop(ctx, c),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: const Text('Clear selection'),
                ),
              ],
            );
          },
        );
      },
    );
    _editDialogOpen = false;
    if (!mounted) return;
    setState(() {
      _selectedCustomer = picked;
      _status = picked == null
          ? 'Customer cleared'
          : 'Customer: ${picked.displayName}';
    });
    _requestScannerFocus();
  }

  Product? _findProduct(String input) {
    final upc = digitsOnly(input);
    final item = normalizeItemNumber(input);

    Product? product = _productsByUpc[upc];
    product ??= _productsByItemNumber[item];

    if (product == null && upc.length == 12 && upc.startsWith('0')) {
      product = _productsByUpc[upc.substring(1)];
    }

    if (product == null && upc.length == 11) {
      product = _productsByUpc['0$upc'];
    }

    return product;
  }

  void _recalculateTotals() {
    int units = 0;
    double total = 0.0;

    for (final line in _orderLines) {
      units += line.quantity;
      total += line.lineTotal;
    }

    _totalUnits = units;
    _orderTotal = total;
  }

  /// Call when quote/list becomes empty so next scan or manual entry is "first time" (single beep).
  void _resetQuoteDisplayAndScanState() {
    _lastAddedUpc = null;
    _lastItem = '-';
    _lastScan = '-';
    _qtyAdded = 0;
    _itemsScanned = 0;
    _scanCount = 0;
    _lastUPC = '';
    _doubleBeepUPCs.clear();
    _lastProcessedScanUpc = null;
    _lastProcessedScanTime = null;
  }

  void _scrollToTopSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  void _addProduct(Product product, String source) {
    OrderLine line;
    final bool isExistingLine = _orderLineByUpc.containsKey(product.upc);

    if (isExistingLine) {
      line = _orderLineByUpc[product.upc]!;
      line.quantity += product.minOrderQty;
      line.scans += 1;

      _orderLines.remove(line);
      _orderLines.insert(0, line);
    } else {
      line = OrderLine(
        product: product,
        quantity: product.minOrderQty,
        scans: 1,
      );

      _orderLines.insert(0, line);
      _orderLineByUpc[product.upc] = line;
    }

    _itemsScanned += 1;
    _qtyAdded = product.minOrderQty;
    _lastAddedUpc = product.upc;
    _recalculateTotals();

    setState(() {
      _selectedLine = line;
      _lastScan = source;
      _lastItem = product.description;
      _status = 'Item added';
      _quickEntryStatus = 'Added ${product.itemNumber}';
    });

    _scrollToTopSoon();

    _triggerScanFeedback(
      isExistingLine
          ? ScanFeedbackType.successExistingItem
          : ScanFeedbackType.successNewItem,
    );
  }

  void _processScan(String value) {
    final raw = value.trim();
    final upc = digitsOnly(raw);

    if (raw.isEmpty || upc.isEmpty) {
      _scannerController.clear();
      _requestScannerFocus();
      return;
    }

    // Prevent double beep: scanner or focus can deliver same barcode twice in quick succession.
    final now = DateTime.now();
    if (_lastProcessedScanUpc == upc &&
        _lastProcessedScanTime != null &&
        now.difference(_lastProcessedScanTime!).inMilliseconds < _scanDedupeMs) {
      _scannerController.clear();
      _requestScannerFocus();
      return;
    }
    _lastProcessedScanUpc = upc;
    _lastProcessedScanTime = now;

    final product = _findProduct(raw);
    _scannerController.clear();
    if (_quickEntryController.text.trim() == raw) {
      _quickEntryController.clear();
    }

    if (product == null) {
      setState(() {
        _lastScan = raw;
        _lastItem = 'NOT FOUND';
        _status = 'UPC / ITEM NOT FOUND';
        _scanCount = 0;
        _lastUPC = '';
      });
      _triggerScanFeedback(ScanFeedbackType.notFound);
      _requestScannerFocus();
      return;
    }

    // New item (different UPC): reset so first scan = single beep; same item again = double.
    if (upc != _lastUPC) {
      _scanCount = 0;
      _lastUPC = upc;
    }
    _addProduct(product, raw);
    _requestScannerFocus();
  }

  void _onScannerChanged(String value) {
    _scanDebounceTimer?.cancel();
    _scanDebounceTimer = Timer(const Duration(milliseconds: 50), () {
      if (!mounted) return;
      final text = _scannerController.text.trim();
      _processScan(text);
    });
  }

  /// When user scans while focus is in quote name field, barcode gets typed there.
  /// Detect barcode-like input and process as scan, then restore quote name.
  void _onQuoteNameSubmitted(String value) {
    final trimmed = value.trim();
    final digits = digitsOnly(trimmed);

    if (digits.length >= 8 && digits == trimmed) {
      _quoteNameController.text = _savedQuoteNameBeforeEdit;
      _quoteNameController.selection = TextSelection.collapsed(
        offset: _savedQuoteNameBeforeEdit.length,
      );
      _processScan(trimmed);
      _requestScannerFocus();
      return;
    }

    _savedQuoteNameBeforeEdit = trimmed.isEmpty
        ? 'NEW QUOTE'
        : trimmed.toUpperCase();

    if (_quoteNameController.text.trim().isEmpty) {
      _quoteNameController.text = 'NEW QUOTE';
    }

    _requestScannerFocus();
  }

  void _addQuickEntry() {
    final input = _quickEntryController.text.trim();
    if (input.isEmpty) return;

    final product = _findProduct(input);

    if (product == null) {
      setState(() {
        _quickEntryStatus = 'Item not found';
        _status = 'Quick entry not found';
      });
      _quickEntryController.clear();
      _triggerScanFeedback(ScanFeedbackType.notFound);
      _requestScannerFocus();
      return;
    }

    // Use same beep logic as scanning: first entry of item = single, repeat = double.
    final upc = product.upc;
    if (upc != _lastUPC) {
      _scanCount = 0;
      _lastUPC = upc;
    }

    _quickEntryController.clear();
    _addProduct(product, input);

    setState(() {
      _quickEntryStatus = 'Added ${product.itemNumber}';
    });

    _requestScannerFocus();
  }

  Future<void> _showEditQuantityDialog(OrderLine line) async {
    final controller = TextEditingController(text: line.quantity.toString());

    _editDialogOpen = true;

    final result = await showDialog<int>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Edit Quantity'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: InputDecoration(labelText: line.product.description),
            onSubmitted: (_) {
              final qty = int.tryParse(controller.text.trim());
              Navigator.pop(dialogContext, qty);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final qty = int.tryParse(controller.text.trim());
                Navigator.pop(dialogContext, qty);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    _editDialogOpen = false;

    if (result == null) {
      _requestScannerFocus();
      return;
    }

    if (result <= 0) {
      setState(() {
        _status = 'Quantity must be greater than 0';
      });
      _requestScannerFocus();
      return;
    }

    setState(() {
      _selectedLine = line;
      line.quantity = result;
      _recalculateTotals();
      _status = 'Quantity updated';
    });

    _requestScannerFocus();
  }

  Future<void> _confirmDeleteLine(OrderLine line) async {
    _editDialogOpen = true;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete Item'),
          content: Text('Remove ${line.product.description} from this order?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    _editDialogOpen = false;

    if (confirm == true) {
      setState(() {
        final wasSelected = identical(_selectedLine, line);

        _orderLines.remove(line);
        _orderLineByUpc.remove(line.product.upc);
        _recalculateTotals();
        _status = 'Item deleted';

        if (_orderLines.isEmpty) {
          _resetQuoteDisplayAndScanState();
          _selectedLine = null;
        } else {
          if (_lastAddedUpc == line.product.upc) {
            final newLastLine = _orderLines.first;
            _lastAddedUpc = newLastLine.product.upc;
            _lastItem = newLastLine.product.description;
          }
          if (wasSelected) {
            _selectedLine = _orderLines.first;
          }
        }
      });
    }

    _requestScannerFocus();
  }

  Future<void> _confirmDeleteLastItem() async {
    if (_lastAddedUpc == null) return;

    final line = _orderLineByUpc[_lastAddedUpc!];
    if (line == null) return;

    _editDialogOpen = true;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete Item'),
          content: const Text('Remove this item from the order?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    _editDialogOpen = false;

    if (confirm == true) {
      setState(() {
        _orderLines.remove(line);
        _orderLineByUpc.remove(line.product.upc);
        _recalculateTotals();
        _status = 'Item deleted';

        if (_orderLines.isEmpty) {
          _resetQuoteDisplayAndScanState();
          _selectedLine = null;
        } else {
          final newLastLine = _orderLines.first;
          _lastAddedUpc = newLastLine.product.upc;
          _lastItem = newLastLine.product.description;
          _selectedLine = newLastLine;
        }
      });
    }

    _requestScannerFocus();
  }

  Future<void> _confirmNewQuote() async {
    if (!mounted) return;

    final hasItems = _orderLines.isNotEmpty;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('New Quote'),
          content: Text(
            hasItems
                ? 'Your current order (${_orderLines.length} item${_orderLines.length == 1 ? '' : 's'}) will be saved first, then you can start a new quote.'
                : 'Start a new quote?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(hasItems ? 'Save & New Quote' : 'New Quote'),
            ),
          ],
        );
      },
    );

    if (confirm != true || !mounted) return;

    if (hasItems) await _saveQuote();
    if (mounted) _startNewQuote();
  }

  void _startNewQuote() {
    setState(() {
      _orderLines.clear();
      _orderLineByUpc.clear();
      _orderTotal = 0.0;
      _resetQuoteDisplayAndScanState();
      _status = 'New quote started';
      _quickEntryStatus = '-';
      _quoteNameController.text = 'NEW QUOTE';
      _savedQuoteNameBeforeEdit = 'NEW QUOTE';
      _selectedLine = null;
      _selectedCustomer = null;
      _currentQuoteId = null;
    });

    _requestScannerFocus();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_quoteNameFocusNode.hasFocus && !_quickEntryFocusNode.hasFocus) {
        _requestScannerFocus();
      }
    });

    Future.delayed(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      if (!_scannerFocusNode.hasFocus && !_editDialogOpen) {
        _requestScannerFocus();
      }
    });
  }

  Future<Directory> _getQuotesDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final quotesDir = Directory('${appDir.path}/showroom_quotes');

    if (!await quotesDir.exists()) {
      await quotesDir.create(recursive: true);
    }

    return quotesDir;
  }

  Future<String> _getQuoteIndexPath() async {
    final dir = await _getQuotesDirectory();
    return '${dir.path}/quotes_index.json';
  }

  Future<void> _saveQuote() async {
    final name = _quoteNameController.text.trim().isEmpty
        ? 'NEW QUOTE'
        : _quoteNameController.text.trim().toUpperCase();

    final now = DateTime.now();
    final id = _currentQuoteId ?? now.millisecondsSinceEpoch.toString();

    final linesJson = _orderLines.map((line) {
      return {
        'upc': line.product.upc,
        'itemNumber': line.product.itemNumber,
        'description': line.product.description,
        'price': line.product.price,
        'quantity': line.quantity,
        'scans': line.scans,
      };
    }).toList();

    final quoteJson = {
      'id': id,
      'name': name,
      'createdAt': now.toIso8601String(),
      'updatedAt': now.toIso8601String(),
      'lines': linesJson,
      if (_selectedCustomer != null) 'customer': _selectedCustomer!.toJson(),
    };

    try {
      final dir = await _getQuotesDirectory();
      final file = File('${dir.path}/quote_$id.json');
      await file.writeAsString(jsonEncode(quoteJson), flush: true);

      final indexPath = await _getQuoteIndexPath();
      final indexFile = File(indexPath);
      List<Map<String, dynamic>> list = [];

      if (await indexFile.exists()) {
        final content = await indexFile.readAsString();
        final decoded = jsonDecode(content);
        if (decoded is List) {
          list = List<Map<String, dynamic>>.from(
            decoded.map((e) => Map<String, dynamic>.from(e as Map)),
          );
        }
      }

      list.removeWhere((e) => e['id'] == id);
      list.insert(0, {
        'id': id,
        'name': name,
        'updatedAt': now.toIso8601String(),
      });

      await indexFile.writeAsString(jsonEncode(list), flush: true);

      if (!mounted) return;
      setState(() {
        _currentQuoteId = id;
        _status = 'Quote saved: $name';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = 'Error saving quote: $e';
      });
    }

    _requestScannerFocus();
  }

  Future<List<SavedQuoteInfo>> _loadQuoteIndex() async {
    try {
      final path = await _getQuoteIndexPath();
      final file = File(path);
      if (!await file.exists()) return [];

      final content = await file.readAsString();
      final decoded = jsonDecode(content);
      if (decoded is! List) return [];

      final list = decoded
          .map(
            (e) => SavedQuoteInfo.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList();

      final dir = await _getQuotesDirectory();
      final valid = <SavedQuoteInfo>[];

      for (final info in list) {
        final quoteFile = File('${dir.path}/quote_${info.id}.json');
        if (await quoteFile.exists()) valid.add(info);
      }

      return valid;
    } catch (_) {
      return [];
    }
  }

  /// Remove quote from index and delete its file. Call after user confirms.
  Future<void> _removeQuoteFromIndex(String id) async {
    try {
      final dir = await _getQuotesDirectory();
      final quoteFile = File('${dir.path}/quote_$id.json');
      if (await quoteFile.exists()) await quoteFile.delete();

      final indexPath = await _getQuoteIndexPath();
      final indexFile = File(indexPath);
      if (!await indexFile.exists()) return;

      final content = await indexFile.readAsString();
      final decoded = jsonDecode(content);
      if (decoded is! List) return;

      final list = List<Map<String, dynamic>>.from(
        decoded.map((e) => Map<String, dynamic>.from(e as Map)),
      );

      list.removeWhere((e) => e['id'] == id);
      await indexFile.writeAsString(jsonEncode(list), flush: true);
    } catch (_) {}
  }

  /// Build CSV with Item Number and Quantity for website upload.
  String _formatQuoteAsCsv(Map<String, dynamic> data) {
    const header = 'Item,Quantity';
    final lines =
        data['lines'] as List<dynamic>? ?? data['items'] as List<dynamic>? ?? [];
    final rows = <String>[header];

    for (final lineJson in lines) {
      final map = Map<String, dynamic>.from(lineJson as Map);
      final itemNumber = (map['itemNumber'] as String?) ?? '';
      final qty = (map['quantity'] as int?) ?? 1;
      final itemEscaped = itemNumber.contains(',') ? '"$itemNumber"' : itemNumber;
      rows.add('$itemEscaped,$qty');
    }

    return rows.join('\n');
  }

  /// Build shareable text for a quote from its JSON data.
  String _formatQuoteAsText(Map<String, dynamic> data) {
    final name = data['name'] as String? ?? 'Quote';
    final lines =
        data['lines'] as List<dynamic>? ?? data['items'] as List<dynamic>? ?? [];
    final buffer = StringBuffer('Quote: $name\n');
    final customerMap = data['customer'];
    if (customerMap is Map<String, dynamic>) {
      final c = Customer.fromJson(Map<String, dynamic>.from(customerMap));
      buffer.writeln('Customer: ${c.displayName}');
      if (c.contact.isNotEmpty) buffer.writeln('Contact: ${c.contact}');
      if (c.email.isNotEmpty) buffer.writeln('Email: ${c.email}');
      if (c.phone.isNotEmpty) buffer.writeln('Phone: ${c.phone}');
      buffer.writeln('');
    }

    buffer.writeln('${'Item / Description'.padRight(40)} Qty    Price    Total');
    buffer.writeln('-' * 60);

    double total = 0;

    for (final lineJson in lines) {
      final map = Map<String, dynamic>.from(lineJson as Map);
      final desc = (map['description'] as String?) ?? '';
      final qty = (map['quantity'] as int?) ?? 1;
      final price = (map['price'] as num?)?.toDouble() ?? 0.0;
      final lineTotal = qty * price;
      total += lineTotal;

      final shortDesc = desc.length > 38 ? '${desc.substring(0, 38)}..' : desc;

      buffer.writeln(
        '${shortDesc.padRight(40)} ${qty.toString().padLeft(3)}  \$${price.toStringAsFixed(2)}  \$${lineTotal.toStringAsFixed(2)}',
      );
    }

    buffer.writeln('-' * 60);
    buffer.writeln('Total: \$${total.toStringAsFixed(2)}');
    return buffer.toString();
  }

  /// Share quote by id: attaches CSV (Item Number, Quantity) for website upload and optional text summary.
  Future<void> _shareQuoteById(String id, String name) async {
    try {
      final dir = await _getQuotesDirectory();
      final file = File('${dir.path}/quote_$id.json');
      if (!await file.exists()) return;

      final content = await file.readAsString();
      final data = Map<String, dynamic>.from(jsonDecode(content) as Map);
      final csv = _formatQuoteAsCsv(data);

      final tempDir = await getTemporaryDirectory();
      final safeName = name
          .replaceAll(RegExp(r'[^\w\s-]'), '_')
          .replaceAll(RegExp(r'\s+'), '_');

      final csvPath =
          '${tempDir.path}/quote_${safeName.isEmpty ? id : safeName}.csv';

      final csvFile = File(csvPath);
      await csvFile.writeAsString(csv, flush: true);

      final text = _formatQuoteAsText(data);

      await Share.shareXFiles(
        [XFile(csvPath, mimeType: 'text/csv')],
        text: text,
        subject: 'Quote: $name',
      );
    } catch (_) {}
  }

  Future<void> _loadQuoteById(String id) async {
    try {
      final dir = await _getQuotesDirectory();
      final file = File('${dir.path}/quote_$id.json');

      if (!await file.exists()) {
        await _removeQuoteFromIndex(id);
        if (!mounted) return;
        setState(() => _status = 'Quote file not found; removed from list');
        return;
      }

      final content = await file.readAsString();
      final data = Map<String, dynamic>.from(jsonDecode(content) as Map);

      final name = (data['name'] as String? ?? 'NEW QUOTE').toUpperCase();
      final linesList =
          data['lines'] as List<dynamic>? ?? data['items'] as List<dynamic>? ?? [];

      Customer? loadedCustomer;
      final customerMap = data['customer'];
      if (customerMap is Map<String, dynamic>) {
        final savedId = (customerMap['id'] as String?)?.trim() ?? '';
        try {
          loadedCustomer = _customers.firstWhere((c) => c.id == savedId);
        } catch (_) {
          loadedCustomer =
              Customer.fromJson(Map<String, dynamic>.from(customerMap));
        }
      }

      final newOrderLines = <OrderLine>[];
      final newOrderLineByUpc = <String, OrderLine>{};

      for (final lineJson in linesList) {
        final map = Map<String, dynamic>.from(lineJson as Map);
        final upc = (map['upc'] as String?) ?? '';
        final itemNumber = (map['itemNumber'] as String?) ?? '';
        final description = (map['description'] as String?) ?? '';
        final price = (map['price'] as num?)?.toDouble() ?? 0.0;
        final quantity = (map['quantity'] as int?) ?? 1;
        final scans = (map['scans'] as int?) ?? 1;

        Product? product = _productsByUpc[upc];
        product ??= _productsByItemNumber[itemNumber];

        if (product == null) {
          product = Product(
            itemNumber: itemNumber.isEmpty ? upc : itemNumber,
            description: description.isEmpty ? 'Unknown' : description,
            upc: upc,
            price: price,
            category: '',
            subCategory: '',
            minOrderQty: 1,
            caseQty: 1,
          );
        }

        final line = OrderLine(
          product: product,
          quantity: quantity,
          scans: scans,
        );

        newOrderLines.add(line);
        newOrderLineByUpc[product.upc] = line;
      }

      if (!mounted) return;

      setState(() {
        _currentQuoteId = id;
        _quoteNameController.text = name;
        _savedQuoteNameBeforeEdit = name;
        _orderLines.clear();
        _orderLines.addAll(newOrderLines);
        _orderLineByUpc.clear();
        _orderLineByUpc.addAll(newOrderLineByUpc);
        _orderListVersion += 1;
        _selectedCustomer = loadedCustomer;

        _itemsScanned = 0;
        for (final l in _orderLines) {
          _itemsScanned += l.scans;
        }

        _recalculateTotals();
        _selectedLine = _orderLines.isNotEmpty ? _orderLines.first : null;
        _lastAddedUpc = _orderLines.isNotEmpty
            ? _orderLines.first.product.upc
            : null;
        _lastItem = _orderLines.isNotEmpty
            ? _orderLines.first.product.description
            : '-';
        _lastScan = _orderLines.isNotEmpty
            ? _orderLines.first.product.upc
            : '-';
        _qtyAdded = _orderLines.isNotEmpty ? _orderLines.first.quantity : 0;
        _status = 'Quote loaded: $name (${_orderLines.length} items)';
        _quickEntryStatus = '-';
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Error loading quote: $e');
    }

    _requestScannerFocus();
  }

  String _formatSavedQuoteDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _showLoadQuoteDialog() async {
    _editDialogOpen = true;
    final list = await _loadQuoteIndex();

    if (!mounted) {
      _editDialogOpen = false;
      return;
    }

    _editDialogOpen = false;

    if (list.isEmpty) {
      setState(() => _status = 'No saved quotes');
      _requestScannerFocus();
      return;
    }

    final allQuotes = List<SavedQuoteInfo>.from(list);

    final selectedId = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Load Quote'),
          content: _LoadQuoteDialogContent(
            allQuotes: allQuotes,
            formatDate: _formatSavedQuoteDate,
            dialogContext: ctx,
            onRemoveQuote: _removeQuoteFromIndex,
            onShareQuote: _shareQuoteById,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );

    final id = selectedId;
    if (id != null && mounted) {
      if (id.startsWith('removed:')) {
        final removedId = id.substring(8);
        if (removedId == _currentQuoteId) {
          setState(() {
            _currentQuoteId = null;
            _orderLines.clear();
            _orderLineByUpc.clear();
            _orderListVersion += 1;
            _recalculateTotals();
            _quoteNameController.text = 'NEW QUOTE';
            _savedQuoteNameBeforeEdit = 'NEW QUOTE';
            _selectedLine = null;
            _selectedCustomer = null;
            _status = 'Quote removed';
            _quickEntryStatus = '-';
            _resetQuoteDisplayAndScanState();
          });
        }
      } else {
        await Future.delayed(const Duration(milliseconds: 150));
        if (mounted) await _loadQuoteById(id);
      }
    }

    // Refocus scanner so first scan after closing dialog registers (avoids
    // needing multiple scanner triggers).
    if (mounted) {
      _requestScannerFocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_editDialogOpen) _requestScannerFocus();
      });
      for (final ms in [400, 800, 1200]) {
        Future.delayed(Duration(milliseconds: ms), () {
          if (mounted && !_editDialogOpen && !_scannerFocusNode.hasFocus) {
            _requestScannerFocus();
          }
        });
      }
    }
  }

  void _increaseSelectedLineQty() {
    if (_selectedLine == null) return;

    setState(() {
      _selectedLine!.quantity += _selectedLine!.product.minOrderQty;
      _recalculateTotals();
      _status = 'Quantity increased';
    });

    _requestScannerFocus();
  }

  void _decreaseSelectedLineQty() {
    if (_selectedLine == null) return;

    final line = _selectedLine!;
    final step = line.product.minOrderQty;
    final newQty = line.quantity - step;

    if (newQty < 1) {
      setState(() {
        _orderLines.remove(line);
        _orderLineByUpc.remove(line.product.upc);
        _recalculateTotals();
        _selectedLine = _orderLines.isEmpty ? null : _orderLines.first;
        if (_orderLines.isEmpty) {
          _resetQuoteDisplayAndScanState();
        }
        _status = 'Item removed from order';
      });
      _requestScannerFocus();
      return;
    }

    setState(() {
      line.quantity = newQty;
      _recalculateTotals();
      _status = 'Quantity decreased';
    });

    _requestScannerFocus();
  }

  void _increaseLineQty(OrderLine line) {
    setState(() {
      line.quantity += line.product.minOrderQty;
      _recalculateTotals();
      _status = 'Quantity increased';
    });
    _requestScannerFocus();
  }

  void _decreaseLineQty(OrderLine line) {
    final step = line.product.minOrderQty;
    final newQty = line.quantity - step;

    if (newQty < 1) {
      setState(() {
        _orderLines.remove(line);
        _orderLineByUpc.remove(line.product.upc);
        _recalculateTotals();
        if (_selectedLine == line) {
          _selectedLine = _orderLines.isEmpty ? null : _orderLines.first;
        }
        if (_orderLines.isEmpty) {
          _resetQuoteDisplayAndScanState();
        }
        _status = 'Item removed from order';
      });
      _requestScannerFocus();
      return;
    }

    setState(() {
      line.quantity = newQty;
      _recalculateTotals();
      _status = 'Quantity decreased';
    });
    _requestScannerFocus();
  }

  Widget _buildStatusCard() {
    final lastLine = _lastAddedUpc == null ? null : _orderLineByUpc[_lastAddedUpc!];
    final totalQtyForLastItem = lastLine?.quantity ?? 0;

    Color? feedbackColor;
    if (_scanFeedbackType == ScanFeedbackType.successNewItem ||
        _scanFeedbackType == ScanFeedbackType.successExistingItem) {
      feedbackColor = Colors.green.withValues(alpha: 0.55);
    } else if (_scanFeedbackType == ScanFeedbackType.notFound) {
      feedbackColor = Colors.red.withValues(alpha: 0.55);
    }

    final displayQuoteName = _quoteNameController.text.trim().isEmpty
        ? 'NEW QUOTE'
        : _quoteNameController.text.trim().toUpperCase();

    return Card(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        color: feedbackColor ?? Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Quote: $displayQuoteName',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Text(
                    _readyToScan ? 'Scanner Ready' : 'Scanner Not Ready',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: _readyToScan ? Colors.green : Colors.red,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text('Status: $_status'),
              const SizedBox(height: 4),
              Text('Last Scan: $_lastScan'),
              const SizedBox(height: 4),
              Text('Catalog Source: $_catalogSource'),
              const SizedBox(height: 8),
              const Text(
                'Last Item Added',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(_lastItem),
              const SizedBox(height: 8),
              Text('Last Qty Added: $_qtyAdded'),
              Text('Total Qty: $totalQtyForLastItem'),
              const SizedBox(height: 8),
              if (lastLine != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                    ),
                    onPressed: _confirmDeleteLastItem,
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopControls() {
    return Column(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: TextField(
              controller: _quoteNameController,
              focusNode: _quoteNameFocusNode,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [UpperCaseTextFormatter()],
              style: const TextStyle(fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                labelText: 'Quote Name',
                border: OutlineInputBorder(),
              ),
              onSubmitted: _onQuoteNameSubmitted,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _quickEntryController,
                    focusNode: _quickEntryFocusNode,
                    decoration: const InputDecoration(
                      labelText: 'Item Number or UPC',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _addQuickEntry(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _addQuickEntry,
                  child: const Text('Add'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Customer',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(
                        _selectedCustomer == null
                            ? (_customers.isEmpty
                                ? 'Load customers CSV first'
                                : 'No customer selected')
                            : _selectedCustomer!.displayName,
                        style: TextStyle(
                          color: _selectedCustomer != null
                              ? Theme.of(context).colorScheme.onSurface
                              : Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.tonal(
                  onPressed:
                      _customers.isEmpty ? null : _showSelectCustomerDialog,
                  child: const Text('Select'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: _loadCsvFromPhone,
                child: const Text('LOAD PRODUCTS'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                onPressed: _loadCustomersCsvFromPhone,
                child: const Text('LOAD CUSTOMERS'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              onPressed: _saveQuote,
              child: const Text('Save Quote'),
            ),
            FilledButton(
              onPressed: _showLoadQuoteDialog,
              child: const Text('Load Quote'),
            ),
            FilledButton(
              onPressed: _confirmNewQuote,
              child: const Text('New Quote'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTotalsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Column(
          children: [
            Text(
              'Items in Order: ${_orderLines.length}',
              style: const TextStyle(fontSize: 18),
            ),
            Text(
              'Total Units: $_totalUnits',
              style: const TextStyle(fontSize: 18),
            ),
            Text(
              'Items in Catalog: $_catalogCount',
              style: const TextStyle(fontSize: 18),
            ),
            Text(
              'Order Total: \$${_orderTotal.toStringAsFixed(2)}',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedItemPanel() {
    if (_selectedLine == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Selected Item',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text('No item selected yet.'),
              const SizedBox(height: 8),
              Text(
                'Scan an item or tap a line in the order list to select it. The − and + buttons will appear here to adjust quantity.',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final line = _selectedLine!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Selected Item',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              'Use the − and + buttons below to change quantity by Min Order Qty.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              line.product.description,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text('Item: ${line.product.itemNumber}'),
            Text('UPC: ${line.product.upc}'),
            Text('Category: ${line.product.category}'),
            Text('Sub-Category: ${line.product.subCategory}'),
            Text('Min Order Qty: ${line.product.minOrderQty}'),
            Text('Case Qty: ${line.product.caseQty}'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Price: \$${line.product.price.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Line Total: \$${line.lineTotal.toStringAsFixed(2)}',
                    textAlign: TextAlign.end,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              'Adjust quantity:',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                SizedBox(
                  width: 64,
                  height: 52,
                  child: FilledButton(
                    onPressed: _decreaseSelectedLineQty,
                    style: FilledButton.styleFrom(
                      padding: EdgeInsets.zero,
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.errorContainer,
                      foregroundColor: Theme.of(
                        context,
                      ).colorScheme.onErrorContainer,
                    ),
                    child: const Icon(Icons.remove, size: 32),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Qty Ordered: ${line.quantity}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 64,
                  height: 52,
                  child: FilledButton(
                    onPressed: _increaseSelectedLineQty,
                    style: FilledButton.styleFrom(padding: EdgeInsets.zero),
                    child: const Icon(Icons.add, size: 32),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Scans: ${line.scans}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderCard(OrderLine line) {
    return Dismissible(
      key: ValueKey(line.product.upc),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        await _confirmDeleteLine(line);
        return false;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.red.shade400,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            setState(() {
              _selectedLine = line;
            });
            _showEditQuantityDialog(line);
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        line.product.description,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('Item: ${line.product.itemNumber}'),
                      Text('UPC: ${line.product.upc}'),
                      Text(
                        'Min Order Qty: ${line.product.minOrderQty}    Case Qty: ${line.product.caseQty}',
                      ),
                      Text(
                        'Price: \$${line.product.price.toStringAsFixed(2)}',
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 36,
                          height: 36,
                          child: IconButton(
                            onPressed: () => _decreaseLineQty(line),
                            icon: const Icon(Icons.remove),
                            style: IconButton.styleFrom(
                              padding: EdgeInsets.zero,
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .errorContainer
                                  .withValues(alpha: 0.5),
                              foregroundColor: Theme.of(
                                context,
                              ).colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${line.quantity}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 36,
                          height: 36,
                          child: IconButton(
                            onPressed: () => _increaseLineQty(line),
                            icon: const Icon(Icons.add),
                            style: IconButton.styleFrom(
                              padding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('Scans ${line.scans}'),
                    const SizedBox(height: 4),
                    Text(
                      '\$${line.lineTotal.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOrderList() {
    if (_orderLines.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: Text('No items added yet')),
      );
    }

    return ListView.builder(
      key: ValueKey('order_list_${_orderListVersion}_${_orderLines.length}'),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _orderLines.length,
      itemBuilder: (context, index) {
        final line = _orderLines[index];
        return _buildOrderCard(line);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (!_quickEntryFocusNode.hasFocus &&
            !_quoteNameFocusNode.hasFocus &&
            !_editDialogOpen) {
          _requestScannerFocus();
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Showroom Scanner')),
        body: SafeArea(
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                SizedBox(
                  height: 1,
                  width: 1,
                  child: TextField(
                    controller: _scannerController,
                    focusNode: _scannerFocusNode,
                    keyboardType: TextInputType.none,
                    textInputAction: TextInputAction.done,
                    showCursor: false,
                    enableInteractiveSelection: false,
                    autocorrect: false,
                    onChanged: _onScannerChanged,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isCollapsed: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                _buildTopControls(),
                const SizedBox(height: 8),
                _buildStatusCard(),
                const SizedBox(height: 8),
                _buildTotalsCard(),
                const SizedBox(height: 8),
                _buildSelectedItemPanel(),
                const SizedBox(height: 12),
                if (_loadingProducts)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  )
                else
                  _buildOrderList(),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}