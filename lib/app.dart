import 'package:flutter/material.dart';

import 'features/adventure_map/adventure_map_screen.dart';
import 'identity/identity.dart';
import 'identity/register_screen.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';

class NuclearPokerApp extends StatelessWidget {
  const NuclearPokerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NuclearPoker',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const _Gate(),
    );
  }
}

/// Decides the entry screen: register first-run, otherwise the map for the
/// signed-in account. The chosen account is remembered across restarts.
class _Gate extends StatefulWidget {
  const _Gate();

  @override
  State<_Gate> createState() => _GateState();
}

class _GateState extends State<_Gate> {
  final AccountStore _accounts = LocalAccountStore();
  Identity? _identity;
  bool _loading = true;

  /// True only right after a fresh registration (not when auto-resuming a saved
  /// account), so the how-to-play intro pops once for new players.
  bool _justRegistered = false;

  @override
  void initState() {
    super.initState();
    _accounts.current().then((id) {
      if (!mounted) return;
      setState(() {
        _identity = id;
        _loading = false;
      });
    });
  }

  Future<void> _register(String username, String password) async {
    final id = await _accounts.register(username, password);
    if (mounted) {
      setState(() {
        _identity = id;
        _justRegistered = true;
      });
    }
  }

  Future<void> _logout() async {
    await _accounts.signOut();
    if (mounted) {
      setState(() {
        _identity = null;
        _justRegistered = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator(color: AppColors.gold)),
      );
    }
    final id = _identity;
    if (id == null) return RegisterScreen(onSubmit: _register);
    // Re-key the map per account so switching users loads the right data.
    return AdventureMapScreen(
      key: ValueKey(id.namespace),
      identity: id,
      showIntro: _justRegistered,
      onLogout: _logout,
    );
  }
}
