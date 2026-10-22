import 'package:flutter/material.dart';
import 'data.dart';
import 'widgets.dart';

class AccountScreen extends StatefulWidget {
  final AppState state;
  const AccountScreen({super.key, required this.state});
  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final form = GlobalKey<FormState>();
  final email = TextEditingController(),
      password = TextEditingController(),
      name = TextEditingController();
  final university = TextEditingController(), bio = TextEditingController();
  bool register = false, busy = false, obscure = true, share = false;
  String schedule = '', cleanliness = '';
  bool? smoking;
  Object? error;
  @override
  void initState() {
    super.initState();
    final p = widget.state.profile;
    university.text = p['university'] ?? '';
    bio.text = p['bio'] ?? '';
    schedule = p['schedule'] ?? '';
    cleanliness = p['cleanliness'] ?? '';
    smoking = p['smoking'];
    share = p['share_with_group'] ?? false;
  }

  @override
  void dispose() {
    for (final c in [email, password, name, university, bio]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> submitAuth() async {
    if (!form.currentState!.validate()) return;
    await run(() async {
      if (register) {
        await widget.state.api.object(
          'POST',
          'auth/register/',
          body: {
            'name': name.text.trim(),
            'email': email.text.trim(),
            'password': password.text,
            'role': 'student',
          },
          authenticated: false,
        );
        // Registration returns a user, not a session. Do not assume auto-login.
        if (!mounted) return;
        setState(() => register = false);
        toast(
          context,
          'Аккаунт создан. Войдите и подтвердите email по ссылке из письма.',
        );
      } else {
        await widget.state.login(email.text, password.text);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return Content(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: state.user == null
            ? [
                const SizedBox(height: 16),
                Text(
                  register ? 'Начните свою историю' : 'С возвращением',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: ink,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  register
                      ? 'Создайте аккаунт студента, чтобы найти жильё и соседей.'
                      : 'Войдите, чтобы управлять заявками и знакомиться с соседями.',
                ),
                const SizedBox(height: 28),
                Form(
                  key: form,
                  child: Column(
                    children: [
                      if (register) ...[
                        TextFormField(
                          controller: name,
                          decoration: const InputDecoration(labelText: 'Имя'),
                          maxLength: 120,
                          validator: requiredText,
                          autofillHints: const [AutofillHints.name],
                        ),
                        const SizedBox(height: 16),
                      ],
                      TextFormField(
                        controller: email,
                        decoration: const InputDecoration(labelText: 'Email'),
                        keyboardType: TextInputType.emailAddress,
                        validator: emailValidator,
                        autofillHints: const [AutofillHints.email],
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: password,
                        obscureText: obscure,
                        autofillHints: [
                          register
                              ? AutofillHints.newPassword
                              : AutofillHints.password,
                        ],
                        decoration: InputDecoration(
                          labelText: 'Пароль',
                          helperText: register
                              ? 'Не менее 10 символов, не только цифры'
                              : null,
                          suffixIcon: IconButton(
                            tooltip: obscure
                                ? 'Показать пароль'
                                : 'Скрыть пароль',
                            onPressed: () => setState(() => obscure = !obscure),
                            icon: Icon(
                              obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                        validator: (v) => register && (v?.length ?? 0) < 10
                            ? 'Не менее 10 символов'
                            : requiredText(v),
                        onFieldSubmitted: (_) => busy ? null : submitAuth(),
                      ),
                      if (error != null) ErrorBox(error!),
                      const SizedBox(height: 20),
                      ActionButton(
                        label: register ? 'Создать аккаунт' : 'Войти',
                        busy: busy,
                        onPressed: submitAuth,
                      ),
                      TextButton(
                        onPressed: busy
                            ? null
                            : () {
                                setState(() {
                                  register = !register;
                                  error = null;
                                });
                                form.currentState?.reset();
                              },
                        child: Text(
                          register
                              ? 'Уже есть аккаунт? Войти'
                              : 'Нет аккаунта? Зарегистрироваться',
                        ),
                      ),
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => RecoveryScreen(state: state),
                                ),
                              ),
                        child: const Text('Забыли пароль?'),
                      ),
                      if (state.startupError != null)
                        TextButton(
                          onPressed: () => run(state.forgetSession),
                          child: const Text(
                            'Удалить сохранённую сессию с устройства',
                          ),
                        ),
                    ],
                  ),
                ),
              ]
            : [
                Text(
                  state.user!['name'],
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: ink,
                  ),
                ),
                const SizedBox(height: 6),
                Text(state.user!['email']),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Tag(state.isStudent ? 'Студент' : 'Арендодатель'),
                    Tag(
                      state.verified
                          ? 'Email подтверждён'
                          : 'Email не подтверждён',
                    ),
                  ],
                ),
                if (!state.verified) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Для заявок и просмотра соседей подтвердите email. Откройте письмо и скопируйте ссылку в форму подтверждения.',
                  ),
                  OutlinedButton.icon(
                    onPressed: busy
                        ? null
                        : () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => VerificationScreen(state: state),
                            ),
                          ),
                    icon: const Icon(Icons.mark_email_read_outlined),
                    label: const Text('Подтвердить email'),
                  ),
                ],
                const SizedBox(height: 28),
                Text(
                  'О вас и вашем быте',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Заполните университет и привычки перед первой заявкой. Это поможет сравнить предпочтения с будущими соседями.',
                ),
                const SizedBox(height: 20),
                Form(
                  key: form,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: university,
                        maxLength: 160,
                        decoration: const InputDecoration(
                          labelText: 'Университет',
                        ),
                        validator: requiredText,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: bio,
                        maxLength: 1000,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(labelText: 'О себе'),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: schedule,
                        decoration: const InputDecoration(
                          labelText: 'Режим сна',
                        ),
                        items: const [
                          DropdownMenuItem(value: '', child: Text('Не указан')),
                          DropdownMenuItem(
                            value: 'early',
                            child: Text('Рано ложусь и рано встаю'),
                          ),
                          DropdownMenuItem(
                            value: 'late',
                            child: Text('Ложусь и встаю поздно'),
                          ),
                        ],
                        onChanged: (v) => schedule = v!,
                        validator: requiredText,
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: cleanliness,
                        decoration: const InputDecoration(
                          labelText: 'Порядок дома',
                        ),
                        items: const [
                          DropdownMenuItem(value: '', child: Text('Не указан')),
                          DropdownMenuItem(
                            value: 'tidy',
                            child: Text('Люблю чистоту и порядок'),
                          ),
                          DropdownMenuItem(
                            value: 'relaxed',
                            child: Text('Спокойно отношусь к беспорядку'),
                          ),
                        ],
                        onChanged: (v) => cleanliness = v!,
                        validator: requiredText,
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: smoking == null ? '' : smoking.toString(),
                        decoration: const InputDecoration(labelText: 'Курение'),
                        items: const [
                          DropdownMenuItem(
                            value: '',
                            child: Text('Не указано'),
                          ),
                          DropdownMenuItem(
                            value: 'false',
                            child: Text('Не курю'),
                          ),
                          DropdownMenuItem(value: 'true', child: Text('Курю')),
                        ],
                        onChanged: (v) =>
                            smoking = v == '' ? null : v == 'true',
                        validator: requiredText,
                      ),
                      const SizedBox(height: 16),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: share,
                        onChanged: (v) => setState(() => share = v),
                        title: const Text('Показывать анкету соседям'),
                        subtitle: const Text(
                          'Разрешить другим участникам видеть профиль и сравнение привычек.',
                        ),
                      ),
                      if (error != null) ErrorBox(error!),
                      const SizedBox(height: 16),
                      ActionButton(
                        label: 'Сохранить профиль',
                        busy: busy,
                        onPressed: () {
                          if (!form.currentState!.validate()) return;
                          run(() async {
                            final p = await state.api.object(
                              'PATCH',
                              'me/profile/',
                              body: {
                                'university': university.text.trim(),
                                'bio': bio.text.trim(),
                                'schedule': schedule,
                                'cleanliness': cleanliness,
                                'smoking': smoking,
                                'share_with_group': share,
                              },
                            );
                            if (state.user != null) {
                              state.user!['profile'] = p;
                              state.changed();
                            }
                            if (context.mounted) {
                              toast(context, 'Профиль сохранён');
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      TextButton.icon(
                        onPressed: busy ? null : () => run(state.logout),
                        icon: const Icon(Icons.logout),
                        label: const Text('Выйти из аккаунта'),
                      ),
                    ],
                  ),
                ),
              ],
      ),
    );
  }
}

class VerificationScreen extends StatefulWidget {
  final AppState state;
  const VerificationScreen({super.key, required this.state});
  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  final token = TextEditingController();
  bool busy = false;
  Object? error;
  Future<void> run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    token.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Подтверждение email')),
    body: Content(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Вставьте ссылку из письма или значение token. После подтверждения станут доступны заявки и анкеты соседей.',
          ),
          const SizedBox(height: 20),
          TextField(
            controller: token,
            decoration: const InputDecoration(labelText: 'Ссылка или token'),
            minLines: 2,
            maxLines: 4,
          ),
          if (error != null) ErrorBox(error!),
          const SizedBox(height: 20),
          ActionButton(
            label: 'Подтвердить',
            busy: busy,
            onPressed: () => run(() async {
              final value = token.text.trim();
              final parsed = Uri.tryParse(value);
              final actual = parsed?.queryParameters['token'] ?? value;
              if (actual.isEmpty) {
                throw const ApiException('Вставьте ссылку из письма.');
              }
              await widget.state.api.request(
                'POST',
                'auth/verify-email/',
                body: {'token': actual},
                authenticated: false,
              );
              await widget.state.refreshUser();
              if (context.mounted) {
                toast(context, 'Email подтверждён');
                Navigator.pop(context);
              }
            }),
          ),
          TextButton(
            onPressed: busy
                ? null
                : () => run(() async {
                    final result = await widget.state.api.object(
                      'POST',
                      'auth/resend-verification/',
                      body: {'email': widget.state.user!['email']},
                      authenticated: false,
                    );
                    if (context.mounted) toast(context, result['detail']);
                  }),
            child: const Text('Запросить письмо повторно'),
          ),
          TextButton(
            onPressed: busy
                ? null
                : () => run(() async {
                    await widget.state.refreshUser();
                    if (context.mounted) {
                      toast(
                        context,
                        widget.state.verified
                            ? 'Email подтверждён'
                            : 'Подтверждение ещё не выполнено',
                      );
                    }
                  }),
            child: const Text('Я уже подтвердил — проверить'),
          ),
        ],
      ),
    ),
  );
}

class RecoveryScreen extends StatefulWidget {
  final AppState state;
  const RecoveryScreen({super.key, required this.state});
  @override
  State<RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends State<RecoveryScreen> {
  final email = TextEditingController(),
      link = TextEditingController(),
      password = TextEditingController();
  Object? error;
  bool busy = false;
  Future<void> run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    email.dispose();
    link.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Восстановление доступа')),
    body: Content(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('1. Запросите письмо для вашего аккаунта.'),
          const SizedBox(height: 16),
          TextField(
            controller: email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          TextButton(
            onPressed: busy
                ? null
                : () => run(() async {
                    if (emailValidator(email.text) != null) {
                      throw const ApiException('Введите корректный email.');
                    }
                    final r = await widget.state.api.object(
                      'POST',
                      'auth/password-reset/',
                      body: {'email': email.text.trim()},
                      authenticated: false,
                    );
                    if (context.mounted) toast(context, r['detail']);
                  }),
            child: const Text('Запросить восстановление'),
          ),
          const SizedBox(height: 24),
          const Text('2. Вставьте ссылку из письма и задайте новый пароль.'),
          const SizedBox(height: 16),
          TextField(
            controller: link,
            decoration: const InputDecoration(
              labelText: 'Ссылка восстановления',
            ),
            minLines: 2,
            maxLines: 4,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: password,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Новый пароль',
              helperText: 'Не менее 10 символов',
            ),
          ),
          if (error != null) ErrorBox(error!),
          const SizedBox(height: 20),
          ActionButton(
            label: 'Изменить пароль',
            busy: busy,
            onPressed: () => run(() async {
              final uri = Uri.tryParse(link.text.trim());
              final uid = uri?.queryParameters['uid'];
              final token = uri?.queryParameters['token'];
              if (uid == null || token == null) {
                throw const ApiException('В ссылке должны быть uid и token.');
              }
              if (password.text.length < 10) {
                throw const ApiException(
                  'Пароль должен содержать не менее 10 символов.',
                );
              }
              await widget.state.api.request(
                'POST',
                'auth/password-reset/confirm/',
                body: {'uid': uid, 'token': token, 'password': password.text},
                authenticated: false,
              );
              await widget.state.forgetSession();
              if (context.mounted) {
                toast(context, 'Пароль изменён. Войдите с новым паролем.');
                Navigator.pop(context);
              }
            }),
          ),
        ],
      ),
    ),
  );
}

class ServerScreen extends StatefulWidget {
  final AppState state;
  const ServerScreen({super.key, required this.state});
  @override
  State<ServerScreen> createState() => _ServerScreenState();
}

class _ServerScreenState extends State<ServerScreen> {
  late final address = TextEditingController(text: widget.state.api.baseUrl);
  Object? error;
  bool busy = false;
  @override
  void dispose() {
    address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Подключение')),
    body: Content(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Icon(Icons.dns_outlined, size: 48, color: accent),
          const SizedBox(height: 20),
          const Text(
            'Адрес общего сервера UniStay',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          const Text(
            'Используйте адрес, предоставленный командой. При смене сервера потребуется войти заново.',
          ),
          const SizedBox(height: 24),
          TextField(
            controller: address,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Адрес API',
              hintText: 'https://api.example.com',
            ),
          ),
          if (error != null) ErrorBox(error!),
          const SizedBox(height: 20),
          ActionButton(
            label: 'Проверить и сохранить',
            busy: busy,
            onPressed: () async {
              setState(() {
                busy = true;
                error = null;
              });
              ApiClient? candidate;
              try {
                candidate = ApiClient(baseUrl: address.text);
                await candidate.object(
                  'GET',
                  'listings/',
                  query: {'page': '1'},
                  authenticated: false,
                );
                await widget.state.changeServer(address.text);
                if (context.mounted) {
                  toast(context, 'Подключение настроено');
                  Navigator.pop(context);
                }
              } catch (e) {
                if (mounted) setState(() => error = e);
              } finally {
                candidate?.close();
                if (mounted) setState(() => busy = false);
              }
            },
          ),
        ],
      ),
    ),
  );
}
