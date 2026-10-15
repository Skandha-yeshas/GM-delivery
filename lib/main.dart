import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'application/delivery_controller.dart';
import 'data/cloud_service.dart';
import 'data/local_store.dart';
import 'presentation/home_screen.dart';
import 'presentation/workspace_design.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const url = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: String.fromEnvironment('SUPABASE_ANON_KEY'),
  );
  SupabaseClient? client;
  String? startupError;
  try {
    if (url.isNotEmpty != key.isNotEmpty) {
      throw StateError(
        'Both cloud configuration values must be provided when building this APK.',
      );
    }
    if (url.isNotEmpty) {
      await Supabase.initialize(url: url, publishableKey: key);
      client = Supabase.instance.client;
    }
  } catch (_) {
    startupError =
        'The app could not start its shared connection. Ask the person who built the APK to check its configuration.';
  }
  runApp(GmApp(client: client, startupError: startupError));
}

class GmApp extends StatelessWidget {
  const GmApp({super.key, this.client, this.startupError});
  final SupabaseClient? client;
  final String? startupError;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'G.M. Delivery',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      fontFamily: 'Roboto',
      colorScheme: ColorScheme.fromSeed(
        seedColor: WorkspaceColors.teal,
        primary: WorkspaceColors.teal,
        surface: WorkspaceColors.canvas,
        onSurface: WorkspaceColors.ink,
      ),
      scaffoldBackgroundColor: WorkspaceColors.canvas,
      appBarTheme: const AppBarTheme(
        backgroundColor: WorkspaceColors.canvas,
        foregroundColor: WorkspaceColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 17,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: WorkspaceColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: WorkspaceColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: WorkspaceColors.teal, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xffdff2ed),
        labelTextStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: const TextStyle(
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ),
    home: startupError == null
        ? SessionGate(client: client)
        : Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(startupError!, textAlign: TextAlign.center),
              ),
            ),
          ),
  );
}

class SessionGate extends StatefulWidget {
  const SessionGate({super.key, this.client});
  final SupabaseClient? client;
  @override
  State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate> {
  StreamSubscription<AuthState>? _subscription;
  Future<DeliveryController>? _controller;
  DeliveryController? _active;
  String? _account;
  int _generation = 0;
  Future<void> _retirement = Future<void>.value();

  @override
  void initState() {
    super.initState();
    _setSession();
    _subscription = widget.client?.auth.onAuthStateChange.listen((_) {
      final account = widget.client?.auth.currentUser?.id;
      if (account != _account) {
        _setSession();
        if (mounted) setState(() {});
      }
    });
  }

  void _setSession() {
    final generation = ++_generation;
    _account = widget.client?.auth.currentUser?.id;
    final old = _active;
    _active = null;
    if (old != null) {
      _retirement = _retire(old);
    }
    if (widget.client != null && _account == null) {
      _controller = null;
      return;
    }
    final account = _account ?? 'local';
    _controller = _createController(account, generation);
  }

  Future<void> _retire(DeliveryController controller) async {
    await controller.whenIdle;
    controller.dispose();
    await controller.store.close();
  }

  Future<DeliveryController> _createController(
    String account,
    int generation,
  ) async {
    await _retirement;
    final store = await LocalStore.open(account);
    final directory = await getApplicationSupportDirectory();
    final controller = DeliveryController(
      store: store,
      photoDirectory: Directory(p.join(directory.path, 'photos', account)),
      cloud: widget.client == null ? null : CloudService(widget.client!),
      accountId: account,
    );
    try {
      await controller.initialize();
      if (!mounted || generation != _generation) {
        throw StateError('The signed-in account changed during loading.');
      }
      _active = controller;
      return controller;
    } catch (_) {
      controller.dispose();
      await store.close();
      rethrow;
    }
  }

  @override
  void dispose() {
    _generation++;
    _subscription?.cancel();
    if (_active != null) {
      unawaited(_retire(_active!));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null) return LoginScreen(client: widget.client!);
    return FutureBuilder<DeliveryController>(
      future: _controller,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('G.M. Enterprises')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_rounded, size: 48),
                    const SizedBox(height: 16),
                    const Text(
                      'Could not load your account',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.client == null
                          ? 'The phone could not open its saved records. Please retry.'
                          : 'Connect to the internet for your first sign-in. An owner must also set up your account role.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: () => setState(_setSession),
                      child: const Text('Retry'),
                    ),
                    if (widget.client != null)
                      TextButton(
                        onPressed: () => widget.client!.auth.signOut(
                          scope: SignOutScope.local,
                        ),
                        child: const Text('Back to sign-in'),
                      ),
                  ],
                ),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return HomeScreen(
          controller: snapshot.data!,
          onSignOut: widget.client == null
              ? null
              : () => widget.client!.auth.signOut(scope: SignOutScope.local),
        );
      },
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.client});
  final SupabaseClient client;
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.client.auth.signInWithPassword(
        email: _email.text.trim(),
        password: _password.text,
      );
    } catch (error) {
      if (mounted) setState(() => _error = errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.edit_location_alt_rounded,
                    size: 54,
                    color: Color(0xff09685d),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'G.M. Enterprises',
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Every shop. The right location.',
                    style: TextStyle(fontSize: 17),
                  ),
                  const SizedBox(height: 36),
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(labelText: 'Email'),
                    validator: (v) => v == null || !v.contains('@')
                        ? 'Enter your account email.'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _password,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    decoration: const InputDecoration(labelText: 'Password'),
                    validator: (v) =>
                        v == null || v.isEmpty ? 'Enter your password.' : null,
                    onFieldSubmitted: (_) {
                      if (!_busy) _signIn();
                    },
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _busy ? null : _signIn,
                      child: Text(_busy ? 'Signing in…' : 'Sign in'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Use the account prepared for you. Contact an owner if you need access.',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
