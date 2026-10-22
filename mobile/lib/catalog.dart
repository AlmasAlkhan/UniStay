import 'package:flutter/material.dart';
import 'data.dart';
import 'widgets.dart';
import 'account.dart';

class CatalogScreen extends StatefulWidget {
  final AppState state;
  final VoidCallback onAccount;
  const CatalogScreen({
    super.key,
    required this.state,
    required this.onAccount,
  });
  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  final search = TextEditingController();
  Map<String, String> filters = {};
  List<Json> items = [];
  bool loading = false, hasNext = false;
  int page = 0, count = 0, generation = 0, revision = 0;
  Object? error;
  @override
  void initState() {
    super.initState();
    revision = widget.state.revision;
    widget.state.addListener(changed);
    load();
  }

  void changed() {
    if (revision != widget.state.revision) {
      revision = widget.state.revision;
      load();
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(changed);
    search.dispose();
    super.dispose();
  }

  Future<void> load({bool more = false}) async {
    if (more && loading) return;
    final request = ++generation;
    final next = more ? page + 1 : 1;
    setState(() {
      loading = true;
      error = null;
      if (!more) {
        items = [];
        page = 0;
        hasNext = false;
      }
    });
    try {
      final data = PageData.fromJson(
        await widget.state.api.object(
          'GET',
          'listings/',
          query: {
            ...filters,
            if (search.text.trim().isNotEmpty) 'search': search.text.trim(),
            'page': '$next',
          },
        ),
      );
      if (!mounted || request != generation) return;
      setState(() {
        items = more ? [...items, ...data.items] : data.items;
        page = next;
        count = data.count;
        hasNext = data.hasNext;
      });
    } catch (e) {
      if (mounted && request == generation) setState(() => error = e);
    } finally {
      if (mounted && request == generation) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Content(
    child: RefreshIndicator(
      onRefresh: load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 8),
          const Text(
            'ВАШ НОВЫЙ АДРЕС',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 2,
              fontWeight: FontWeight.bold,
              color: accent,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Жильё найдётся.\nСоседи — тоже.',
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: ink,
              height: 1.12,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Найдите своё место и познакомьтесь с теми, с кем будете жить.',
          ),
          const SizedBox(height: 24),
          TextField(
            controller: search,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => load(),
            decoration: InputDecoration(
              hintText: 'Поиск по названию и описанию',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: 'Искать',
                onPressed: () => load(),
                icon: const Icon(Icons.arrow_forward),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  final result = await Navigator.push<Map<String, String>>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FilterScreen(initial: filters),
                    ),
                  );
                  if (result != null && mounted) {
                    filters = result;
                    load();
                  }
                },
                icon: const Icon(Icons.tune, size: 18),
                label: Text(
                  filters.isEmpty ? 'Фильтры' : 'Фильтры · ${filters.length}',
                ),
              ),
              const Spacer(),
              Text(listingCount(count), style: const TextStyle(color: accent)),
            ],
          ),
          if (filters.isNotEmpty)
            TextButton(
              onPressed: () {
                filters = {};
                search.clear();
                load();
              },
              child: const Text('Сбросить поиск и фильтры'),
            ),
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: LinearProgressIndicator(),
            ),
          if (error != null)
            ErrorBox(error!, retry: () => load(more: page > 0 && hasNext)),
          if (!loading && error == null && items.isEmpty)
            const EmptyView(
              icon: Icons.travel_explore,
              title: 'Пока ничего не найдено',
              message:
                  'Попробуйте изменить фильтры или вернитесь позже — здесь появятся опубликованные объявления.',
            ),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(top: 16),
              child: ListingCard(
                item: item,
                api: widget.state.api,
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ListingScreen(
                        state: widget.state,
                        id: item['id'],
                        onAccount: widget.onAccount,
                      ),
                    ),
                  );
                  if (mounted) load();
                },
              ),
            ),
          ),
          if (hasNext)
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: ActionButton(
                label: 'Показать ещё',
                busy: loading,
                onPressed: () => load(more: true),
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    ),
  );
}

class ListingCard extends StatelessWidget {
  final Json item;
  final ApiClient api;
  final VoidCallback onTap;
  const ListingCard({
    super.key,
    required this.item,
    required this.api,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final photos = item['photos'] as List;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListingImage(
              url: photos.isEmpty ? null : api.imageUrl(photos.first['image']),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Tag(
                        '${item['available']} из ${item['capacity']} мест свободно',
                      ),
                      if (item['utilities_included'] == true)
                        const Tag('Коммунальные включены'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    item['title'],
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text('${item['city']} · ${item['district']}'),
                  const SizedBox(height: 5),
                  Text(item['university']),
                  const SizedBox(height: 16),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: money(item['price']),
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: ink,
                          ),
                        ),
                        const TextSpan(text: ' / место в месяц'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FilterScreen extends StatefulWidget {
  final Map<String, String> initial;
  const FilterScreen({super.key, required this.initial});
  @override
  State<FilterScreen> createState() => _FilterScreenState();
}

class _FilterScreenState extends State<FilterScreen> {
  final form = GlobalKey<FormState>();
  late final fields = {
    for (final k in [
      'city',
      'district',
      'university',
      'min_price',
      'max_price',
    ])
      k: TextEditingController(text: widget.initial[k]),
  };
  late bool available = widget.initial['available'] == 'true';
  late String ordering = widget.initial['ordering'] ?? '-created_at';
  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Подберите своё место')),
    body: Content(
      child: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            ...{
              'city': 'Город',
              'district': 'Район',
              'university': 'Университет',
              'min_price': 'Цена от, ₸',
              'max_price': 'Цена до, ₸',
            }.entries.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: TextFormField(
                  controller: fields[e.key],
                  decoration: InputDecoration(labelText: e.value),
                  keyboardType: e.key.contains('price')
                      ? const TextInputType.numberWithOptions(decimal: true)
                      : TextInputType.text,
                  validator: (v) {
                    if (!e.key.contains('price') || v!.trim().isEmpty) {
                      return null;
                    }
                    final n = double.tryParse(v.replaceAll(',', '.'));
                    if (n == null || !n.isFinite || n < 0 || n > 99999999) {
                      return 'Введите цену от 0 до 99 999 999';
                    }
                    final min = double.tryParse(
                      fields['min_price']!.text.replaceAll(',', '.'),
                    );
                    if (e.key == 'max_price' && min != null && n < min) {
                      return 'Максимум должен быть не меньше минимума';
                    }
                    return null;
                  },
                ),
              ),
            ),
            DropdownButtonFormField<String>(
              initialValue: ordering,
              decoration: const InputDecoration(labelText: 'Сортировка'),
              items: const [
                DropdownMenuItem(
                  value: '-created_at',
                  child: Text('Сначала новые'),
                ),
                DropdownMenuItem(
                  value: 'price',
                  child: Text('Сначала дешевле'),
                ),
                DropdownMenuItem(
                  value: '-price',
                  child: Text('Сначала дороже'),
                ),
              ],
              onChanged: (v) => ordering = v!,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: available,
              onChanged: (v) => setState(() => available = v),
              title: const Text('Только со свободными местами'),
            ),
            const SizedBox(height: 20),
            ActionButton(
              label: 'Показать объявления',
              onPressed: () {
                if (!form.currentState!.validate()) return;
                Navigator.pop(context, {
                  for (final e in fields.entries)
                    if (e.value.text.trim().isNotEmpty)
                      e.key: e.key.contains('price')
                          ? e.value.text.trim().replaceAll(',', '.')
                          : e.value.text.trim(),
                  if (available) 'available': 'true',
                  'ordering': ordering,
                });
              },
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, <String, String>{}),
              child: const Text('Сбросить фильтры'),
            ),
          ],
        ),
      ),
    ),
  );
}

class ListingScreen extends StatefulWidget {
  final AppState state;
  final int id;
  final VoidCallback onAccount;
  const ListingScreen({
    super.key,
    required this.state,
    required this.id,
    required this.onAccount,
  });
  @override
  State<ListingScreen> createState() => _ListingScreenState();
}

class _ListingScreenState extends State<ListingScreen> {
  Json? listing;
  List<Json>? group;
  Object? error, groupError, actionError;
  bool loading = true, sending = false, applied = false;
  final message = TextEditingController();
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    message.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
      group = null;
      groupError = null;
    });
    try {
      final result = await widget.state.api.object(
        'GET',
        'listings/${widget.id}/',
      );
      if (mounted) setState(() => listing = result);
      if (widget.state.verified) {
        try {
          final members =
              await widget.state.api.request(
                    'GET',
                    'listings/${widget.id}/group/',
                  )
                  as List;
          if (mounted) {
            setState(
              () => group = members
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList(),
            );
          }
        } catch (e) {
          if (mounted) setState(() => groupError = e);
        }
      }
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void account() {
    Navigator.pop(context);
    widget.onAccount();
  }

  Future<void> apply() async {
    if (sending || applied) return;
    if (!await confirm(
      context,
      'Отправить заявку?',
      'Владелец рассмотрит вашу анкету и сообщение. Место будет занято только после принятия заявки.',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() {
      sending = true;
      actionError = null;
    });
    try {
      await widget.state.api.object(
        'POST',
        'applications/',
        body: {'listing_id': widget.id, 'message': message.text.trim()},
      );
      if (mounted) {
        setState(() => applied = true);
        toast(
          context,
          'Заявка отправлена. Следите за статусом во вкладке «Заявки».',
        );
      }
      widget.state.changed();
    } catch (e) {
      if (mounted) setState(() => actionError = e);
      if (e is ApiException && e.status == 409) await load();
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.state,
    builder: (context, _) {
      final s = widget.state;
      final l = listing;
      return Scaffold(
        appBar: AppBar(title: const Text('О квартире')),
        body: Content(
          child: RefreshIndicator(
            onRefresh: load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              children: [
                if (loading) const LinearProgressIndicator(),
                if (error != null) ErrorBox(error!, retry: load),
                if (l != null) ...[
                  if ((l['photos'] as List).isEmpty)
                    const ListingImage()
                  else ...[
                    SizedBox(
                      height: 260,
                      child: PageView(
                        children: (l['photos'] as List)
                            .map<Widget>(
                              (p) => ClipRRect(
                                borderRadius: BorderRadius.circular(20),
                                child: ListingImage(
                                  url: s.api.imageUrl(p['image']),
                                  height: 260,
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${(l['photos'] as List).length} фото · листайте влево',
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 20),
                  Text(
                    l['title'],
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('${l['city']} · ${l['district']}'),
                  const SizedBox(height: 16),
                  Text(
                    '${money(l['price'])} / место в месяц',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: ink,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Tag('${l['available']} свободно / ${l['capacity']} мест'),
                      Tag(
                        l['utilities_included']
                            ? 'Коммунальные включены'
                            : 'Коммунальные отдельно',
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(l['description']),
                  const SizedBox(height: 20),
                  Text('Университет: ${l['university']}'),
                  Text('Залог: ${money(l['deposit'])}'),
                  Text('Заселение: ${dateLabel(l['move_in_date'])}'),
                  Text('Владелец: ${l['owner_name']}'),
                  const SizedBox(height: 12),
                  Text(
                    (s.user != null ? l['address'] : null) ??
                        'Точный адрес станет доступен после принятия заявки.',
                  ),
                  const Divider(height: 40),
                  Text(
                    'Будущие соседи',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  if (!s.verified)
                    const Text(
                      'Войдите и подтвердите email, чтобы видеть открытые анкеты соседей.',
                    ),
                  if (groupError != null) ErrorBox(groupError!, retry: load),
                  if (group != null && group!.isEmpty)
                    const Text(
                      'Открытых анкет пока нет. Здесь видны только жильцы, разрешившие показ профиля.',
                    ),
                  ...?(s.verified ? group : null)?.map(
                    (m) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                m['name'],
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                              Text(m['university'] ?? ''),
                              if ((m['bio'] ?? '').isNotEmpty) Text(m['bio']),
                              const SizedBox(height: 8),
                              Text(
                                m['compatibility'] == null
                                    ? 'Недостаточно данных для сравнения'
                                    : 'Совпадение привычек: ${m['compatibility']}%',
                              ),
                              Text(
                                'Сравнено критериев: ${m['compared_preferences']}',
                              ),
                              if ((m['matching_preferences'] as List)
                                  .isNotEmpty)
                                Text(
                                  'Совпадают: ${(m['matching_preferences'] as List).map((k) => preferenceLabels[k] ?? k).join(', ')}',
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Сравнение отражает совпадение заполненных привычек и не гарантирует совместимость.',
                  ),
                  const Divider(height: 40),
                  if (s.user == null)
                    ActionButton(
                      label: 'Войти, чтобы подать заявку',
                      onPressed: account,
                    )
                  else if (!s.isStudent)
                    const Text('Заявки на место доступны аккаунтам студентов.')
                  else if (!s.verified)
                    ActionButton(
                      label: 'Подтвердить email',
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => VerificationScreen(state: s),
                          ),
                        );
                        if (mounted) load();
                      },
                    )
                  else if (!s.profileComplete)
                    ActionButton(label: 'Заполнить профиль', onPressed: account)
                  else if (applied)
                    const Tag('Заявка отправлена')
                  else if (l['available'] <= 0 || l['status'] != 'published')
                    const Tag('Сейчас нет доступных мест')
                  else ...[
                    TextField(
                      controller: message,
                      maxLength: 1000,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Сообщение владельцу',
                        hintText: 'Расскажите немного о себе (необязательно)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    ActionButton(
                      label: 'Подать заявку на место',
                      busy: sending,
                      onPressed: apply,
                    ),
                  ],
                  if (actionError != null) ErrorBox(actionError!),
                  const SizedBox(height: 24),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}
