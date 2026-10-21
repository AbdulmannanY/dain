import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/errors.dart';
import '../data/ledger_repository.dart';

/// "My shops": the list, renaming one, and deleting one that has no ledgers.
class ShopsController extends ChangeNotifier {
  ShopsController(this._repository);

  final LedgerRepository _repository;

  List<Business>? _shops;

  /// Null until the first successful load.
  List<Business>? get shops => _shops;

  bool _loading = false;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;

  bool _saving = false;
  bool get saving => _saving;

  /// The open sheet's error, apart from [error].
  String? _formError;
  String? get formError => _formError;

  bool _disposed = false;

  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    _notify();
    try {
      _shops = await _repository.fetchMyBusinesses();
    } catch (e) {
      _error = arabicMessageFor(e);
    } finally {
      _loading = false;
      _notify();
    }
  }

  void clearFormError() {
    _formError = null;
    _notify();
  }

  Future<bool> rename(String id, String name) async {
    final text = name.trim();
    if (text.isEmpty || text.runes.length > 80) {
      _formError = 'اكتب اسم المحل (حتى 80 حرفاً).';
      _notify();
      return false;
    }
    return _write(() => _repository.renameBusiness(id, text));
  }

  Future<bool> delete(String id) =>
      _write(() => _repository.deleteBusiness(id));

  Future<bool> _write(Future<void> Function() action) async {
    if (_saving) return false;
    _saving = true;
    _formError = null;
    _notify();
    try {
      await action();
    } on PostgrestException catch (e) {
      _formError = e.code == '23503'
          ? 'لا يُحذف محل فيه دفاتر. الدفتر سجل مشترك مع الطرف الآخر ولا يُحذف.'
          : arabicMessageFor(e);
      return false;
    } on StateError {
      _formError = 'المحل غير موجود.';
      await load();
      return false;
    } catch (e) {
      _formError = arabicMessageFor(e);
      return false;
    } finally {
      _saving = false;
      _notify();
    }
    await load();
    return true;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
