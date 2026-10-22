import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'data.dart';
import 'widgets.dart';
import 'catalog.dart';
import 'account.dart';
import 'applications.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  const configured = String.fromEnvironment('API_BASE_URL');
  final fallback = !kIsWeb && defaultTargetPlatform == TargetPlatform.android
      ? 'http://10.0.2.2:8000'
      : 'http://127.0.0.1:8000';
  final base = configured.isNotEmpty
      ? configured
      : kReleaseMode
      ? 'https://api.example.com'
      : fallback;
  runApp(
    UniStayApp(
      state: AppState(
        api: ApiClient(baseUrl: base),
        store: SecureSessionStore(),
      ),
    ),
  );
}

class UniStayApp extends StatefulWidget {
  final AppState state;
  const UniStayApp({super.key, required this.state});
  @override
  State<UniStayApp> createState() => _UniStayAppState();
}

class _UniStayAppState extends State<UniStayApp> {
  @override
  void initState() {
    super.initState();
    widget.state.initialize();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'UniStay',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: accent),
      scaffoldBackgroundColor: const Color(0xFFF7F7F0),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFF7F7F0),
        foregroundColor: ink,
        centerTitle: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        contentPadding: const EdgeInsets.all(16),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFE3E6DC)),
        ),
      ),
    ),
    home: Home(state: widget.state),
  );
}

class Home extends StatefulWidget {
  final AppState state;
  const Home({super.key, required this.state});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int index = 0;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.state,
    builder: (context, _) {
      final state = widget.state;
      return Scaffold(
        appBar: AppBar(
          title: const Row(
            children: [
              Icon(Icons.roofing_rounded),
              SizedBox(width: 8),
              Text(
                'UniStay',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.8,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Настройки подключения',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ServerScreen(state: state)),
              ),
              icon: const Icon(Icons.tune),
            ),
          ],
        ),
        body: !state.ready
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  if (state.notice != null)
                    MaterialBanner(
                      content: Text(state.notice!),
                      actions: [
                        TextButton(
                          onPressed: () {
                            state.notice = null;
                            state.changed();
                            setState(() => index = 2);
                          },
                          child: const Text('Войти'),
                        ),
                      ],
                    ),
                  if (state.startupError != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: ErrorBox(
                        state.startupError!,
                        retry: () => state.initialize(),
                      ),
                    ),
                  Expanded(
                    child: IndexedStack(
                      index: index,
                      children: [
                        CatalogScreen(
                          key: ValueKey(
                            'catalog:${state.api.baseUrl}:${state.user?['id']}',
                          ),
                          state: state,
                          onAccount: () => setState(() => index = 2),
                        ),
                        ApplicationsScreen(
                          key: ValueKey(
                            'applications:${state.api.baseUrl}:${state.user?['id']}',
                          ),
                          state: state,
                          onAccount: () => setState(() => index = 2),
                        ),
                        AccountScreen(
                          key: ValueKey(
                            'account:${state.api.baseUrl}:${state.user?['id']}',
                          ),
                          state: state,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (value) => setState(() => index = value),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.search),
              label: 'Найти жильё',
            ),
            NavigationDestination(
              icon: Icon(Icons.inbox_outlined),
              label: 'Заявки',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              label: 'Профиль',
            ),
          ],
        ),
      );
    },
  );
}
