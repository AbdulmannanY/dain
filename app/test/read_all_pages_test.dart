import 'package:dain/data/ledger_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// A query of [total] rows that returns at most [maxRows] per request, as
/// PostgREST does; records the ranges asked for.
({Future<List<int>> Function(int, int) page, List<(int, int)> asked}) rows(
  int total, {
  int maxRows = pageSize,
}) {
  final asked = <(int, int)>[];
  Future<List<int>> page(int from, int to) async {
    asked.add((from, to));
    final end = [to + 1, total, from + maxRows].reduce((a, b) => a < b ? a : b);
    return [for (var i = from; i < end; i++) i];
  }

  return (page: page, asked: asked);
}

void main() {
  test(
    'reads past the rows one request returns, without gaps or repeats',
    () async {
      final q = rows(2500);
      final all = await readAllPages(q.page);
      expect(all, [for (var i = 0; i < 2500; i++) i]);
      expect(q.asked, [(0, 999), (1000, 1999), (2000, 2999)]);
    },
  );

  test('a full last page asks once more and stops on the empty one', () async {
    final q = rows(2000);
    expect(await readAllPages(q.page), hasLength(2000));
    expect(q.asked, [(0, 999), (1000, 1999), (2000, 2999)]);
  });

  test('fewer rows than a page: one request', () async {
    final q = rows(3);
    expect(await readAllPages(q.page), [0, 1, 2]);
    expect(q.asked, [(0, 999)]);
  });

  test('nothing at all: one request, an empty list', () async {
    final q = rows(0);
    expect(await readAllPages(q.page), isEmpty);
    expect(q.asked, hasLength(1));
  });

  test('the page size can be smaller', () async {
    final q = rows(5);
    expect(await readAllPages(q.page, size: 2), [0, 1, 2, 3, 4]);
    expect(q.asked, [(0, 1), (2, 3), (4, 5)]);
  });
}
