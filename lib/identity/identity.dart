import 'package:shared_preferences/shared_preferences.dart';

/// A registered account. We do no validation and impose no restrictions on the
/// username or password (it's a PoC). The reserved username **admin** unlocks
/// every level with auto-play available.
class Identity {
  const Identity(this.username, this.password);

  final String username;
  final String password;

  /// Admin requires the username **and** password to both be `admin`. Anyone
  /// else named "admin" with a different password is just a normal player.
  bool get isAdmin =>
      username.trim().toLowerCase() == 'admin' && password == 'admin';

  /// Storage-key prefix so each user's progress + ranges are kept separate.
  String get namespace => 'u:${username.trim().toLowerCase()}:';
}

/// Stores accounts and remembers who's signed in. A thin interface so the
/// backing store can swap from on-device to a real server later (the stack doc's
/// Firebase plan) without touching the UI.
///
/// NOTE: there is **no backend wired in this PoC** — [LocalAccountStore] keeps
/// everything on-device (`localStorage` on web, so it survives reloads + hot
/// restarts). Swap in a `RemoteAccountStore` for true server-side saving.
abstract class AccountStore {
  /// The signed-in account, or null on first run.
  Future<Identity?> current();

  /// Register (or re-enter) [username]/[password] and make it the current
  /// account. No restrictions, no password check.
  Future<Identity> register(String username, String password);

  Future<void> signOut();
}

class LocalAccountStore implements AccountStore {
  static const String _currentKey = 'current_username';
  static String _pwKey(String username) =>
      'acct:${username.trim().toLowerCase()}:password';

  @override
  Future<Identity?> current() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_currentKey);
    if (name == null || name.trim().isEmpty) return null;
    return Identity(name, prefs.getString(_pwKey(name)) ?? '');
  }

  @override
  Future<Identity> register(String username, String password) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pwKey(username), password);
    await prefs.setString(_currentKey, username.trim());
    return Identity(username.trim(), password);
  }

  @override
  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_currentKey);
  }
}
