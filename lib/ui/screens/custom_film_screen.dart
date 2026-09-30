import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/models.dart';
import '../../l10n/labels.dart';
import '../../state/providers.dart';
import '../format.dart';
import '../icons.dart';
import '../theme.dart';
import '../widgets.dart';
import 'film_screen.dart';
import 'record_screen.dart';

const _langs = ['hi', 'ta', 'te', 'ml', 'kn', 'bn', 'mr', 'pa', 'gu', 'or', 'as', 'bho', 'en', 'ko', 'ja'];

/// For films and series the catalog does not have.
class CustomFilmScreen extends ConsumerStatefulWidget {
  const CustomFilmScreen({super.key, this.initialTitle = '', this.forRecord = false, this.recordDay});
  final String initialTitle;
  final bool forRecord;
  final DateTime? recordDay;

  @override
  ConsumerState<CustomFilmScreen> createState() => _CustomFilmScreenState();
}

class _CustomFilmScreenState extends ConsumerState<CustomFilmScreen> {
  late final _title = TextEditingController(text: widget.initialTitle);
  final _year = TextEditingController();
  final _form = GlobalKey<FormState>();
  String? _lang;
  var _series = false;
  String? _poster; // relative to the documents dir

  @override
  void dispose() {
    _title.dispose();
    _year.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    XFile? x;
    try {
      x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 900, imageQuality: 85);
    } on PlatformException {
      return; // Photo access denied: the film keeps its title card.
    }
    if (x == null) return;
    final dir = ref.read(docsDirProvider);
    final rel = 'posters/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await Directory('${dir.path}/posters').create(recursive: true);
    await File(x.path).copy('${dir.path}/$rel');
    if (mounted) setState(() => _poster = rel);
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final film = ref
        .read(diaryProvider.notifier)
        .addCustomFilm(
          title: _title.text,
          year: int.tryParse(_year.text.trim()),
          lang: _lang,
          series: _series,
          posterFile: _poster,
        );
    final nav = Navigator.of(context);
    if (widget.forRecord) {
      nav.pushReplacement(
        MaterialPageRoute(
          builder: (_) => RecordScreen(film: film, day: widget.recordDay),
        ),
      );
    } else {
      ref.read(diaryProvider.notifier).toggleWish(film);
      nav.pushReplacement(
        MaterialPageRoute(
          builder: (_) => FilmScreen(filmId: film.id, fallback: film),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final l = context.l;
    final maxYear = DateTime.now().year + 3;
    final preview = Film(
      id: 'my:preview',
      title: _title.text.isEmpty ? '?' : _title.text,
      year: int.tryParse(_year.text),
      poster: _poster == null ? null : 'file:$_poster',
    );
    return Scaffold(
      appBar: AppBar(
        leading: TkButton(Tk.back, tooltip: l.back, onPressed: () => Navigator.pop(context)),
        title: Text(l.customTitle.toUpperCase(), style: disp(22, p.ink)),
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Form(
          key: _form,
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Poster(preview, width: 96),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.customPoster, style: disp(16, p.ink)),
                        const SizedBox(height: 8),
                        InkButton(label: l.choosePhoto, icon: Tk.photo, outlined: true, onPressed: _pickPhoto),
                        if (_poster != null)
                          TextButton(
                            onPressed: () => setState(() => _poster = null),
                            child: Text(l.removePhoto, style: TextStyle(color: p.inkSoft)),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              TextFormField(
                key: const Key('custom-title'),
                controller: _title,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(labelText: l.customName),
                validator: (v) => (v ?? '').trim().isEmpty ? l.required : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _year,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(labelText: l.customYear),
                validator: (v) {
                  if ((v ?? '').trim().isEmpty) return null;
                  final y = int.tryParse(v!.trim());
                  return y == null || y < 1900 || y > maxYear ? l.yearInvalid(maxYear) : null;
                },
              ),
              const SizedBox(height: 20),
              Text(l.customLang, style: disp(16, p.ink)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final code in _langs)
                    OptionBox(
                      label: langName(context, code),
                      dense: true,
                      selected: _lang == code,
                      onTap: () => setState(() => _lang = _lang == code ? null : code),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l.customSeries),
                value: _series,
                onChanged: (v) => setState(() => _series = v),
              ),
              const SizedBox(height: 16),
              InkButton(
                key: const Key('custom-save'),
                label: widget.forRecord ? l.customSave : l.customSaveWish,
                onPressed: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
