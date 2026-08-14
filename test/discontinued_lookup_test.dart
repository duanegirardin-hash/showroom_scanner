import 'package:flutter_test/flutter_test.dart';
import 'package:showroom_scanner/discontinued_products.dart';

const _sampleCsv =
    '"Item Number","Description","UPC","EMUN Status","Sellable","Whse 1 QtyAvailable","Whse 2 QtyAvailable","Total QtyAvailable","New Release","Image Available","Category","Sub-Category","List Price","Price"\n'
    '"01028","Sample L item A","062823010281","Inactive","NO","0","0","0","","YES","Cat","Sub","1","1"\n'
    '"01151","Sample L item B","062823011510","Inactive","NO","0","0","0","","NO","Cat","Sub","1","1"\n'
    '"10686","Squeeze Avocado","062823106864","Inactive","NO","0","0","0","","YES","Cat","Sub","1","1"\n'
    '"36017","Dup A","062823360174","Inactive","NO","0","0","0","","NO","Cat","Sub","1","1"\n'
    '"36017-KV","Dup B","062823360174","Inactive","NO","0","0","0","","NO","Cat","Sub","1","1"\n'
    '"07147-SDR","Blank UPC item","","Inactive","NO","0","0","0","","NO","Cat","Sub","1","1"\n'
    '"GC476433","Inactive conflict","067103167191","Inactive","NO","0","0","0","","NO","Cat","Sub","1","1"\n'
    '"GC476433L","Should not be in discontinued file","067103167191","Active","YES","10","10","20","","YES","Cat","Sub","1","1"\n';

void main() {
  late DiscontinuedCatalog catalog;

  setUp(() {
    catalog = parseDiscontinuedCsv(_sampleCsv);
  });

  test('parses discontinued rows and preserves item/UPC text', () {
    expect(catalog.count, 8);
    expect(catalog.byItemNumber['01028']!.upc, '062823010281');
    expect(catalog.byItemNumber['03132DC-BW'], isNull);
  });

  test('blank UPC cannot enter UPC map', () {
    expect(catalog.byItemNumber.containsKey('07147-SDR'), isTrue);
    expect(
      catalog.byUpc.values.any((p) => p.itemNumber == '07147-SDR'),
      isFalse,
    );
  });

  test('duplicate inactive UPC last row wins deterministically', () {
    final hit = catalog.byUpc[discontinuedNormalizeUpcLookupKey('062823360174')];
    expect(hit, isNotNull);
    expect(hit!.itemNumber, '36017-KV');
  });

  test('active UPC match wins over discontinued UPC match', () {
    final activeByUpc = {
      discontinuedNormalizeUpcLookupKey('067103167191'): 'ACTIVE_GC476433L',
    };
    final result = findDiscontinuedProduct(
      input: '067103167191',
      activeByUpc: activeByUpc,
      activeByItemNumber: const {},
      discontinued: catalog,
    );
    expect(result, isNull);
  });

  test('discontinued UPC recognized when Active misses', () {
    final result = findDiscontinuedProduct(
      input: '062823106864',
      activeByUpc: const {},
      activeByItemNumber: const {},
      discontinued: catalog,
    );
    expect(result, isNotNull);
    expect(result!.itemNumber, '10686');
    expect(result.description, 'Squeeze Avocado');
    expect(result.upc, '062823106864');
  });

  test('item-number discontinued lookup works when Active misses', () {
    final result = findDiscontinuedProduct(
      input: '01028',
      activeByUpc: const {},
      activeByItemNumber: const {},
      discontinued: catalog,
    );
    expect(result!.itemNumber, '01028');
  });

  test('unknown remains null when neither Active nor discontinued match', () {
    final result = findDiscontinuedProduct(
      input: '999999999999',
      activeByUpc: const {},
      activeByItemNumber: const {},
      discontinued: catalog,
    );
    expect(result, isNull);
  });

  test('active item-number match also blocks discontinued', () {
    final result = findDiscontinuedProduct(
      input: '01028',
      activeByUpc: const {},
      activeByItemNumber: {'01028': 'ACTIVE'},
      discontinued: catalog,
    );
    expect(result, isNull);
  });
}
