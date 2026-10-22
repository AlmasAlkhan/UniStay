import 'package:flutter/material.dart';
import 'data.dart';
import 'widgets.dart';
import 'catalog.dart';

class ApplicationsScreen extends StatefulWidget {
  final AppState state;
  final VoidCallback onAccount;
  const ApplicationsScreen({
    super.key,
    required this.state,
    required this.onAccount,
  });
  @override
  State<ApplicationsScreen> createState() => _ApplicationsScreenState();
}

class _ApplicationsScreenState extends State<ApplicationsScreen> {
  List<Json> items = [];
  Object? error;
  bool loading = false, hasNext = false;
  int page = 0, generation = 0, revision = 0;
  final Set<int> pending = {};
  @override
  void initState() {
    super.initState();
    revision = widget.state.revision;
    widget.state.addListener(changed);
    if (widget.state.user != null) load();
  }

  void changed() {
    if (revision != widget.state.revision) {
      revision = widget.state.revision;
      if (widget.state.user != null) load();
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(changed);
    super.dispose();
  }

  Future<void> load({bool more = false}) async {
    if (more && loading) return;
    final request = ++generation, next = more ? page + 1 : 1;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = PageData.fromJson(
        await widget.state.api.object(
          'GET',
          'applications/',
          query: {'page': '$next'},
        ),
      );
      if (!mounted || generation != request) return;
      setState(() {
        items = more ? [...items, ...result.items] : result.items;
        page = next;
        hasNext = result.hasNext;
      });
    } catch (e) {
      if (mounted && generation == request) setState(() => error = e);
    } finally {
      if (mounted && generation == request) setState(() => loading = false);
    }
  }

  Future<void> action(Json item, String action) async {
    final id = item['id'] as int;
    if (pending.contains(id)) return;
    final labels = {
      'cancel': 'Отменить заявку?',
      'accept': 'Принять заявку?',
      'reject': 'Отклонить заявку?',
    };
    if (!await confirm(
      context,
      labels[action]!,
      action == 'cancel'
          ? 'Если заявка принята, место освободится. История заявки сохранится.'
          : 'Решение будет сохранено и станет доступно студенту.',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() {
      pending.add(id);
      error = null;
    });
    try {
      final result = await widget.state.api.object(
        'POST',
        'applications/$id/$action/',
      );
      if (mounted) {
        setState(
          () => items = items.map((e) => e['id'] == id ? result : e).toList(),
        );
        toast(context, 'Статус обновлён');
      }
      widget.state.changed();
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => pending.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    if (s.user == null) {
      return Content(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const EmptyView(
              icon: Icons.inbox_outlined,
              title: 'Ваши заявки будут здесь',
              message:
                  'Войдите, чтобы отправлять заявки и следить за решениями владельцев.',
            ),
            ActionButton(label: 'Войти', onPressed: widget.onAccount),
          ],
        ),
      );
    }
    return Content(
      child: RefreshIndicator(
        onRefresh: load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              s.isStudent ? 'Мои заявки' : 'Заявки студентов',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: ink,
              ),
            ),
            const SizedBox(height: 8),
            const Text('От первого сообщения до вашего нового места.'),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: loading ? null : () => load(),
                icon: const Icon(Icons.refresh),
                label: const Text('Обновить статусы'),
              ),
            ),
            if (loading) const LinearProgressIndicator(),
            if (error != null) ErrorBox(error!, retry: () => load()),
            if (!loading && items.isEmpty && error == null)
              const EmptyView(
                icon: Icons.markunread_mailbox_outlined,
                title: 'Заявок пока нет',
                message:
                    'Выберите квартиру в каталоге и отправьте владельцу заявку на свободное место.',
              ),
            ...items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Tag(statusLabels[item['status']] ?? item['status']),
                        const SizedBox(height: 12),
                        Text(
                          item['listing_title'],
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        if (!s.isStudent)
                          Text('Студент: ${item['student']['name']}'),
                        const SizedBox(height: 8),
                        Text('Отправлена ${dateLabel(item['created_at'])}'),
                        if ((item['message'] ?? '').isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(item['message']),
                          ),
                        TextButton(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ListingScreen(
                                state: s,
                                id: item['listing_id'],
                                onAccount: widget.onAccount,
                              ),
                            ),
                          ),
                          child: const Text('Открыть объявление'),
                        ),
                        if ((item['events'] as List).isNotEmpty)
                          ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            title: const Text('История заявки'),
                            children: (item['events'] as List)
                                .map<Widget>(
                                  (event) => ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    dense: true,
                                    leading: const Icon(
                                      Icons.history,
                                      size: 20,
                                    ),
                                    title: Text(
                                      statusLabels[event['to_status']] ??
                                          event['to_status'],
                                    ),
                                    subtitle: Text(
                                      dateLabel(event['created_at']),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        if (s.isStudent &&
                            ['pending', 'accepted'].contains(item['status']))
                          OutlinedButton(
                            onPressed: pending.contains(item['id'])
                                ? null
                                : () => action(item, 'cancel'),
                            child: Text(
                              pending.contains(item['id'])
                                  ? 'Сохраняем…'
                                  : 'Отменить заявку',
                            ),
                          ),
                        if (!s.isStudent && item['status'] == 'pending')
                          Wrap(
                            spacing: 8,
                            children: [
                              FilledButton(
                                onPressed: pending.contains(item['id'])
                                    ? null
                                    : () => action(item, 'accept'),
                                child: const Text('Принять'),
                              ),
                              OutlinedButton(
                                onPressed: pending.contains(item['id'])
                                    ? null
                                    : () => action(item, 'reject'),
                                child: const Text('Отклонить'),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (hasNext)
              ActionButton(
                label: 'Показать ещё',
                busy: loading,
                onPressed: () => load(more: true),
              ),
          ],
        ),
      ),
    );
  }
}
