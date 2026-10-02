import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/models.dart';
import '../../l10n/labels.dart';
import '../../state/online.dart';
import '../../state/providers.dart';
import '../format.dart';
import '../icons.dart';
import '../theme.dart';
import '../widgets.dart';
import 'stub_screen.dart';

const _dubLangs = ['hi', 'ta', 'te', 'ml', 'kn', 'bn', 'mr', 'en'];

class RecordScreen extends ConsumerStatefulWidget {
  const RecordScreen({super.key, required this.film, this.day, this.editing});
  final Film film;
  final DateTime? day;
  final Stub? editing;

  @override
  ConsumerState<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends ConsumerState<RecordScreen> {
  late DateTime _date;
  late DatePrecision _prec;
  double? _rating;
  String? _place, _show, _format, _class, _lang;
  bool _fdfs = false;

  /// See [Stub.private]. The switch shows only for a signed-in user; a stub that is private stays private on edit.
  bool _private = false;
  late List<String> _tags;
  final _seat = TextEditingController();
  final _price = TextEditingController();
  final _with = TextEditingController();
  final _memo = TextEditingController();
  final _newTag = TextEditingController();
  var _dirty = false;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    final today = ref.read(todayProvider);
    if (e != null) {
      _date = e.date ?? today;
      _prec = e.date == null ? DatePrecision.none : e.precision;
      _rating = e.rating;
      _place = e.place;
      _show = e.show;
      _format = e.format;
      _class = e.seatClass;
      _lang = e.lang;
      _fdfs = e.fdfs;
      _private = e.private;
      _tags = [...e.tags];
      _seat.text = e.seat ?? '';
      _price.text = e.price == null ? '' : _num(e.price!);
      _with.text = e.company ?? '';
      _memo.text = e.memo;
    } else {
      _date = widget.day ?? today;
      _prec = DatePrecision.day;
      _tags = [];
      final stubs = [...ref.read(diaryProvider).stubs]..sort((a, b) => byWatchOrder(b, a));
      _place = stubs.isEmpty ? null : stubs.first.place;
    }
  }

  @override
  void dispose() {
    for (final c in [_seat, _price, _with, _memo, _newTag]) {
      c.dispose();
    }
    super.dispose();
  }

  String _num(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  /// Text edits: rebuild once so the back gesture asks before discarding.
  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  void _set(VoidCallback f) => setState(() {
    f();
    _dirty = true;
  });

  StubDraft get _draft => StubDraft(
    date: _prec == DatePrecision.none ? null : _date,
    precision: _prec,
    rating: _rating,
    place: _place,
    memo: _memo.text,
    tags: _tags,
    show: _cinema ? _show : null,
    format: _cinema ? _format : null,
    seatClass: _cinema ? _class : null,
    seat: _cinema ? _seat.text : null,
    price: _cinema ? double.tryParse(_price.text.trim().replaceAll(',', '')) : null,
    fdfs: _cinema && _fdfs,
    lang: _lang,
    company: _with.text,
    private: _private,
  );

  bool get _cinema => ref.read(diaryProvider).venueType(_place) == VenueType.cinema;

  void _save() {
    final n = ref.read(diaryProvider.notifier);
    final nav = Navigator.of(context);
    if (widget.editing != null) {
      n.updateStub(widget.editing!, _draft);
      nav.pop();
    } else {
      HapticFeedback.lightImpact();
      final stub = n.addStub(widget.film, _draft);
      nav.pushReplacement(MaterialPageRoute(builder: (_) => StubScreen(stubId: stub.id, justStamped: true)));
    }
  }

  Future<bool> _confirmDiscard() async {
    final l = context.l;
    final r = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l.discardQ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(l.keepEditing)),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text(l.discard)),
        ],
      ),
    );
    return r ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final diary = ref.watch(diaryProvider);
    final showRatings = ref.watch(settingsProvider.select((s) => s.showRatings));
    final p = Palette.of(context);
    final l = context.l;
    final f = widget.film;
    final cinema = diary.venueType(_place) == VenueType.cinema;

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _confirmDiscard()) nav.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: TkButton(Tk.back, tooltip: l.back, onPressed: () => Navigator.maybePop(context)),
          title: Text((widget.editing == null ? l.recordTitle : l.editTitle).toUpperCase(), style: disp(24, p.ink)),
        ),
        body: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                  children: [
                    _FilmHead(f),
                    _Label(l.whenWatched),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final (v, t) in [
                          (DatePrecision.day, l.precisionDay),
                          (DatePrecision.month, l.precisionMonth),
                          (DatePrecision.year, l.precisionYear),
                          (DatePrecision.none, l.precisionNone),
                        ])
                          OptionBox(label: t, dense: true, selected: _prec == v, onTap: () => _set(() => _prec = v)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _datePart(context, p),
                    _Label(l.wherePlace),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final v in diary.venues)
                          OptionBox(
                            label: placeName(context, v.name),
                            selected: _place == v.name,
                            onTap: () => _set(() => _place = _place == v.name ? null : v.name),
                          ),
                        if (_place != null && !diary.venues.any((v) => v.name == _place))
                          OptionBox(label: _place!, selected: true, onTap: () => _set(() => _place = null)),
                        _AddBox(label: l.addPlace, onTap: _newPlace),
                      ],
                    ),
                    if (cinema) ..._hall(context, p),
                    if (f.langs.isNotEmpty) ...[
                      _Label(l.watchedIn),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OptionBox(
                            label: '${langName(context, f.mainLang!)} · ${l.originalLang}',
                            dense: true,
                            selected: _lang == null,
                            onTap: () => _set(() => _lang = null),
                          ),
                          for (final code in _dubLangs.where((c) => c != f.mainLang))
                            OptionBox(
                              label: langName(context, code),
                              dense: true,
                              selected: _lang == code,
                              onTap: () => _set(() => _lang = code),
                            ),
                        ],
                      ),
                    ],
                    if (showRatings) ...[
                      _Label(l.rating),
                      Row(
                        children: [
                          StarInput(value: _rating, onChanged: (v) => _set(() => _rating = v)),
                          const SizedBox(width: 12),
                          Text(
                            _rating == null ? '-' : fmtRating(_rating!),
                            style: disp(26, _rating == null ? p.inkSoft : p.ink),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OptionBox(
                          label: l.noRating,
                          dense: true,
                          selected: _rating == null,
                          onTap: () => _set(() => _rating = null),
                        ),
                      ),
                    ],
                    _Label(l.tags),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final t in {...diary.tags, ..._tags})
                          OptionBox(
                            label: '#$t',
                            dense: true,
                            selected: _tags.contains(t),
                            onTap: () => _set(() => _tags.contains(t) ? _tags.remove(t) : _tags.add(t)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      key: const Key('new-tag'),
                      controller: _newTag,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _addTag(),
                      decoration: InputDecoration(
                        hintText: l.tagHint,
                        prefixText: '# ',
                        isDense: true,
                        suffixIcon: TkButton(Tk.plus, tooltip: l.addTag, size: 20, onPressed: _addTag),
                      ),
                    ),
                    _Label(l.withWhom),
                    TextField(
                      controller: _with,
                      onChanged: (_) => _markDirty(),
                      decoration: InputDecoration(hintText: l.withHint, isDense: true),
                    ),
                    _Label(l.memo),
                    TextField(
                      key: const Key('memo'),
                      controller: _memo,
                      onChanged: (_) => _markDirty(),
                      minLines: 3,
                      maxLines: 8,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(hintText: l.memoHint),
                    ),
                    // Local data, so it shows for a signed-in user whether or not the server answers.
                    if (ref.watch(signedInProvider)) ...[
                      _Label(l.privacyTitle),
                      SwitchListTile(
                        key: const Key('private-stub'),
                        contentPadding: EdgeInsets.zero,
                        title: Text(l.privacyStubToggle, style: const TextStyle(fontWeight: FontWeight.w600)),
                        secondary: TkIcon(Tk.lock, color: _private ? p.ink : p.inkSoft),
                        value: _private,
                        onChanged: (v) => _set(() => _private = v),
                      ),
                    ],
                  ],
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: p.wall,
                  border: Border(top: BorderSide(color: p.line)),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
                    child: SizedBox(
                      width: double.infinity,
                      child: InkButton(
                        key: const Key('stamp-it'),
                        label: widget.editing == null ? l.stampIt : l.saveChanges,
                        icon: widget.editing == null ? Tk.stubs : Tk.check,
                        onPressed: _save,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _datePart(BuildContext context, Palette p) {
    final l = context.l;
    final today = ref.read(todayProvider);
    switch (_prec) {
      case DatePrecision.none:
        return Text(l.dateUnknown, style: TextStyle(color: p.inkSoft));
      case DatePrecision.day:
        final yesterday = today.subtract(const Duration(days: 1));
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OptionBox(
              label: l.today,
              dense: true,
              selected: DateUtils.isSameDay(_date, today),
              onTap: () => _set(() => _date = today),
            ),
            OptionBox(
              label: l.yesterday,
              dense: true,
              selected: DateUtils.isSameDay(_date, yesterday),
              onTap: () => _set(() => _date = yesterday),
            ),
            TextButton.icon(
              key: const Key('pick-date'),
              onPressed: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _date.isAfter(today) ? today : _date,
                  firstDate: DateTime(1900),
                  lastDate: today,
                );
                if (d != null) _set(() => _date = d);
              },
              icon: TkIcon(Tk.calendar, size: 18, color: p.ink),
              label: Text(
                fmtDay(context, _date),
                style: TextStyle(color: p.ink, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        );
      case DatePrecision.month:
      case DatePrecision.year:
        final years = [for (var y = today.year; y >= 1900; y--) y];
        return Row(
          children: [
            if (_prec == DatePrecision.month) ...[
              DropdownButton<int>(
                value: _date.month,
                underline: const SizedBox(),
                items: [
                  for (var m = 1; m <= 12; m++)
                    DropdownMenuItem(
                      value: m,
                      child: Text(DateFormat.MMMM(context.fmtLocale).format(DateTime(2000, m))),
                    ),
                ],
                onChanged: (m) => _set(() => _date = DateTime(_date.year, m!)),
              ),
              const SizedBox(width: 16),
            ],
            DropdownButton<int>(
              value: years.contains(_date.year) ? _date.year : today.year,
              underline: const SizedBox(),
              items: [for (final y in years) DropdownMenuItem(value: y, child: Text('$y'))],
              onChanged: (y) => _set(() => _date = DateTime(y!, _prec == DatePrecision.month ? _date.month : 1)),
            ),
          ],
        );
    }
  }

  List<Widget> _hall(BuildContext context, Palette p) {
    final l = context.l;
    return [
      _Label(l.hallDetails),
      Text(
        l.show,
        style: TextStyle(fontSize: 13, color: p.inkSoft, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 6),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final k in showKeys)
            OptionBox(
              label: showName(context, k),
              dense: true,
              selected: _show == k,
              onTap: () => _set(() => _show = _show == k ? null : k),
            ),
        ],
      ),
      const SizedBox(height: 14),
      Text(
        l.format,
        style: TextStyle(fontSize: 13, color: p.inkSoft, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 6),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final k in formatKeys)
            OptionBox(
              label: formatName(k),
              dense: true,
              selected: _format == k,
              onTap: () => _set(() => _format = _format == k ? null : k),
            ),
        ],
      ),
      const SizedBox(height: 14),
      Text(
        l.seatClass,
        style: TextStyle(fontSize: 13, color: p.inkSoft, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 6),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final k in seatClasses)
            OptionBox(
              label: k,
              dense: true,
              selected: _class == k,
              onTap: () => _set(() => _class = _class == k ? null : k),
            ),
        ],
      ),
      const SizedBox(height: 14),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _seat,
              onChanged: (_) => _markDirty(),
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(labelText: l.seat, hintText: l.seatHint, isDense: true),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              key: const Key('price'),
              controller: _price,
              onChanged: (_) => _markDirty(),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))],
              decoration: InputDecoration(labelText: l.price, hintText: l.priceHint, isDense: true),
            ),
          ),
        ],
      ),
      const SizedBox(height: 4),
      SwitchListTile(
        key: const Key('fdfs'),
        contentPadding: EdgeInsets.zero,
        title: Text(l.fdfsToggle, style: const TextStyle(fontWeight: FontWeight.w600)),
        secondary: Text(l.fdfs, style: disp(18, _fdfs ? p.accent : p.inkSoft, spacing: 1)),
        value: _fdfs,
        onChanged: (v) => _set(() => _fdfs = v),
      ),
    ];
  }

  void _addTag() {
    final t = cleanTag(_newTag.text);
    if (t.isEmpty) return;
    ref.read(diaryProvider.notifier).addTag(t);
    _set(() {
      if (!_tags.contains(t)) _tags.add(t);
      _newTag.clear();
    });
  }

  Future<void> _newPlace() async {
    final v = await showDialog<Venue>(context: context, builder: (_) => const VenueDialog());
    if (v == null) return;
    ref.read(diaryProvider.notifier).addVenue(v);
    _set(() => _place = v.name.trim());
  }
}

class _FilmHead extends StatelessWidget {
  const _FilmHead(this.f);
  final Film f;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Row(
      children: [
        Poster(f, width: 58, radius: 3),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(f.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              if (f.original != null) Text(f.original!, style: TextStyle(color: p.inkSoft)),
              Text(
                [if (f.year != null) '${f.year}', ...f.directors.take(1)].join('  ·  '),
                style: TextStyle(color: p.inkSoft, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 26, bottom: 10),
    child: Text(text, style: disp(18, Palette.of(context).ink)),
  );
}

class _AddBox extends StatelessWidget {
  const _AddBox({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(3),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TkIcon(Tk.plus, size: 16, color: p.accent),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(color: p.accent, fontWeight: FontWeight.w700, fontSize: 13.5),
            ),
          ],
        ),
      ),
    );
  }
}

/// Name and type of a place. Returns a [Venue] or null.
class VenueDialog extends StatefulWidget {
  const VenueDialog({super.key, this.initial});
  final Venue? initial;

  @override
  State<VenueDialog> createState() => _VenueDialogState();
}

class _VenueDialogState extends State<VenueDialog> {
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late var _type = widget.initial?.type ?? VenueType.cinema;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return AlertDialog(
      title: Text(widget.initial == null ? l.addPlace : l.editVenue),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const Key('venue-name'),
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: l.placeName, hintText: l.placeNameHint),
          ),
          const SizedBox(height: 16),
          Text(l.placeType, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in VenueType.values)
                OptionBox(
                  label: venueTypeName(context, t),
                  dense: true,
                  selected: _type == t,
                  onTap: () => setState(() => _type = t),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
        ListenableBuilder(
          listenable: _name,
          builder: (context, _) => TextButton(
            key: const Key('venue-save'),
            onPressed: _name.text.trim().isEmpty ? null : () => Navigator.pop(context, Venue(_name.text.trim(), _type)),
            child: Text(l.save),
          ),
        ),
      ],
    );
  }
}
