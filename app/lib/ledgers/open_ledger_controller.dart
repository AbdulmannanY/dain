import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/errors.dart';
import '../core/phone_number.dart';
import '../data/ledger_repository.dart';

/// Where the new ledger goes: personal, one of my shops, or a shop created
/// on submit.
sealed class LedgerOwner {
  const LedgerOwner();
}

class PersonalOwner extends LedgerOwner {
  const PersonalOwner();
}

class ShopOwner extends LedgerOwner {
  const ShopOwner(this.businessId);
  final String businessId;
}

class NewShopOwner extends LedgerOwner {
  const NewShopOwner();
}

/// The "new ledger" form: my shops, the choice of owner, and the submit.
///
/// A new shop is created before the ledger in a separate request. Once it
/// exists it joins [businesses] and becomes the selection, so a retry after
/// the ledger insert failed reuses it instead of creating a second shop.
class OpenLedgerController extends ChangeNotifier {
  OpenLedgerController(this._repository);

  final LedgerRepository _repository;

  List<Business>? _businesses;

  /// Null until the first successful load.
  List<Business>? get businesses => _businesses;

  LedgerOwner _owner = const PersonalOwner();
  LedgerOwner get owner => _owner;

  bool _loading = false;
  bool get loading => _loading;

  bool _busy = false;
  bool get busy => _busy;

  String? _error;
  String? get error => _error;

  bool _disposed = false;

  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    _notify();
    try {
      _businesses = await _repository.fetchMyBusinesses();
    } catch (e) {
      _error = arabicMessageFor(e);
    } finally {
      _loading = false;
      _notify();
    }
  }

  void select(LedgerOwner owner) {
    if (_busy) return;
    _owner = owner;
    _error = null;
    _notify();
  }

  /// Returns the new ledger's id, or null with an Arabic [error].
  Future<String?> submit({
    required String name,
    required String phone,
    String newShopName = '',
  }) async {
    if (_busy) return null;
    final counterpartyName = name.trim();
    if (counterpartyName.isEmpty || counterpartyName.runes.length > 80) {
      return _fail('اكتب اسم الطرف الآخر (حتى 80 حرفاً).');
    }
    final normalized = normalizePhone(phone);
    if (normalized == null) {
      return _fail('أدخل رقم جوال صحيحاً، مثل 05XXXXXXXX.');
    }
    // The database accepts it, but link_my_ledgers() never links a ledger
    // to its own owner, so it would stay unjoined forever.
    if (normalized == _repository.myPhone) {
      return _fail('هذا رقمك أنت. أدخل رقم الطرف الآخر.');
    }
    final shopName = newShopName.trim();
    if (_owner is NewShopOwner &&
        (shopName.isEmpty || shopName.runes.length > 80)) {
      return _fail('اكتب اسم المحل (حتى 80 حرفاً).');
    }

    _busy = true;
    _error = null;
    _notify();
    try {
      if (_owner is NewShopOwner) {
        final shop = await _repository.createBusiness(shopName);
        _businesses = [...?_businesses, shop];
        _owner = ShopOwner(shop.id);
      }
      final owner = _owner;
      return await _repository.openLedger(
        counterpartyName: counterpartyName,
        phone: normalized,
        businessId: owner is ShopOwner ? owner.businessId : null,
      );
    } on PostgrestException catch (e) {
      _error = e.code == '23505'
          ? (_owner is ShopOwner
                ? 'لهذا الرقم دفتر في هذا المحل بالفعل.'
                : 'لديك دفتر شخصي لهذا الرقم بالفعل.')
          : arabicMessageFor(e);
      return null;
    } catch (e) {
      _error = arabicMessageFor(e);
      return null;
    } finally {
      _busy = false;
      _notify();
    }
  }

  String? _fail(String message) {
    _error = message;
    _notify();
    return null;
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
