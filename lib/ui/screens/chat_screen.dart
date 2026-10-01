import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/crews.dart';
import '../../data/models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/crews.dart';
import '../../state/crews_remote.dart';
import '../../state/online.dart';
import '../../state/providers.dart';
import '../../state/social.dart';
import '../avatar.dart';
import '../common.dart';
import '../format.dart';
import '../icons.dart';
import '../online_gate.dart';
import '../online_parts.dart';
import '../theme.dart';
import '../widgets.dart';
import 'night_screen.dart';
import 'search_screen.dart';

/// Chat of a shared group. Flat paper slips: mine on the accent, the others on the surface tone with the
/// sender's stamp and name. System lines are quiet text in the language of the phone. A film or a night sent
/// with a message is a small ticket under it. There is no time on any message.
///
/// The chat asks for new messages only while this screen is open and the app is in front. Tap a sender to block
/// them, press and hold a message to report it.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.crewId});
  final String crewId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> with WidgetsBindingObserver {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  late final ChatController _chat;

  /// The film attached to the message being written.
  Film? _film;
  var _sending = false;
  var _loadingOlder = false;

  /// The first answer of the server came: an empty chat is empty, not still loading.
  var _loaded = false;
  String? _problem;

  /// People blocked from this screen. The server hides them on the next poll; this hides them now.
  final _blocked = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _chat = ref.read(chatProvider(widget.crewId).notifier);
    // Riverpod forbids provider changes while a widget starts: one microtask later.
    scheduleMicrotask(() {
      if (mounted) _chat.setActive(true);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Polling runs only while the chat is in front.
    switch (state) {
      case AppLifecycleState.resumed:
        _chat.setActive(true);
      case AppLifecycleState.paused || AppLifecycleState.hidden || AppLifecycleState.detached:
        _chat.setActive(false);
      case AppLifecycleState.inactive:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final chat = _chat;
    // Riverpod forbids provider changes while a widget is torn down: one microtask later. The provider drops
    // itself and its timer when nobody listens, so a call that comes after that does no harm.
    scheduleMicrotask(() {
      try {
        chat.setActive(false);
      } catch (_) {
        // The provider is gone already.
      }
    });
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _retry() async {
    await ref.read(backendProvider.notifier).probe(force: true);
    if (mounted) unawaited(_chat.poll());
  }

  Future<void> _loadOlder() async {
    if (_loadingOlder) return;
    _loadingOlder = true;
    await _chat.loadOlder();
    _loadingOlder = false;
  }

  Future<void> _attach() => push(
    context,
    SearchScreen(
      onPick: (f) {
        if (mounted) setState(() => _film = f);
      },
    ),
  );

  String _why(AppLocalizations l, Refusal? r) => switch (r) {
    Refusal.offline => l.gateCantReach,
    Refusal.rateLimited => l.sendTooFast,
    _ => l.sendFailed,
  };

  Future<void> _send() async {
    final l = context.l;
    final film = _film;
    final typed = _text.text.trim();
    // The server wants a text; a film alone is sent with its title.
    final body = typed.isEmpty ? film?.title ?? '' : typed;
    if (body.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _problem = null;
    });
    final r = await _chat.send(body, film: film);
    if (!mounted) return;
    setState(() {
      _sending = false;
      if (r.ok) {
        _text.clear();
        _film = null;
      } else {
        _problem = _why(l, r.refusal);
      }
    });
    if (r.ok && _scroll.hasClients) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _scroll.jumpTo(0);
      } else {
        unawaited(_scroll.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut));
      }
    }
  }

  Future<void> _report(Message m) async {
    final l = context.l;
    final reason = await pickReportReason(context, title: l.chatReportTitle);
    if (reason == null || !mounted) return;
    final r = await _chat.report(m, reason.name);
    if (!mounted) return;
    say(context, r.ok ? l.friendsReported : _why(l, r.refusal));
  }

  Future<void> _block(Sender s, String name) async {
    final l = context.l;
    if (!await confirmBlock(context, name) || !mounted) return;
    final r = await ref.read(blocksProvider.notifier).block(s.id);
    if (!mounted) return;
    if (r.ok) {
      setState(() => _blocked.add(s.id));
      say(context, l.friendsBlocked(name));
    } else {
      say(context, problemText(l, r.outcome));
    }
  }

  /// A system line in the language of the phone, from the code and the arguments the server sent. Null for a
  /// code this version does not know.
  String? _system(AppLocalizations l, Message m, Crew? crew, Film? Function(String id) film) {
    String arg(String key) => '${m.args?[key] ?? ''}';
    String who() => arg('name').isEmpty ? l.friendsUnnamed : arg('name');
    switch (m.code) {
      case 'joined':
        return l.chatJoined(who());
      case 'left':
        return l.chatLeft(who());
      case 'poll_open':
        return l.chatPollOpen;
      case 'night_set':
        final f = crew?.night(arg('night_id'))?.film ?? film(arg('film_id'));
        return f == null ? l.chatNightSetPlain : l.chatNightSet(f.title);
      case 'wrapped':
        return l.chatWrapped;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final p = Palette.of(context);
    final online = ref.watch(onlineProvider);
    final chat = ref.watch(chatProvider(widget.crewId));
    final crew = ref.watch(sharedCrewsProvider.select((s) => s.crew(widget.crewId)));
    final catalog = ref.watch(catalogProvider).value;
    final myId = ref.watch(sessionProvider.select((s) => s?.userId));
    ref.listen(chatProvider(widget.crewId), (prev, next) {
      // A poll replaces the list, whether or not it brought anything: the first one ends the loading.
      if (!_loaded && prev != null && !identical(prev.messages, next.messages)) setState(() => _loaded = true);
    });

    Film? filmOf(String id) => catalog?.byId[id];
    final shown = [
      for (final m in chat.messages)
        if (m.kind == MessageKind.text ? !_blocked.contains(m.sender?.id) : _system(l, m, crew, filmOf) != null) m,
    ];
    final canSend = online && !_sending && (_text.text.trim().isNotEmpty || _film != null);

    final Widget body;
    if (!online || (chat.offline && shown.isEmpty)) {
      body = ListView(children: [CantReach(onRetry: _retry)]);
    } else {
      body = Column(
        children: [
          Expanded(child: _list(context, chat, shown, crew, myId, filmOf)),
          if (chat.offline)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(l.gateCantReach, style: TextStyle(color: p.inkSoft, fontSize: 13, height: 1.35)),
                  ),
                  TextButton(
                    style: linkStyle(context),
                    key: const Key('chat-retry'),
                    onPressed: _retry,
                    child: Text(l.gateRetry),
                  ),
                ],
              ),
            ),
          if (_problem != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _problem!,
                  style: TextStyle(color: p.ink, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          _composer(context, canSend),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: TkButton(Tk.back, tooltip: l.back, onPressed: () => Navigator.maybePop(context)),
        title: Text(
          (crew?.name ?? l.chatTitle).toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: disp(24, p.ink),
        ),
      ),
      body: body,
    );
  }

  Widget _list(
    BuildContext context,
    ChatState chat,
    List<Message> shown,
    Crew? crew,
    String? myId,
    Film? Function(String id) filmOf,
  ) {
    final l = context.l;
    if (shown.isEmpty) {
      return _loaded ? Center(child: EmptyNote(l.chatEmpty)) : const Center(child: LoadingBlock());
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        // The list runs from the bottom up: little room left "after" is the top, where the old messages are.
        if (n.metrics.extentAfter < 240 && chat.hasOlder) unawaited(_loadOlder());
        return false;
      },
      child: ListView.builder(
        reverse: true,
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        itemCount: shown.length + (chat.hasOlder ? 1 : 0),
        itemBuilder: (context, i) {
          if (i == shown.length) {
            return Center(
              child: TextButton(
                style: linkStyle(context),
                key: const Key('chat-older'),
                onPressed: _loadOlder,
                child: Text(l.chatOlder),
              ),
            );
          }
          final at = shown.length - 1 - i;
          final m = shown[at];
          final prev = at > 0 ? shown[at - 1] : null;
          if (m.kind == MessageKind.system) {
            return _SystemLine(key: ValueKey(m.id), text: _system(l, m, crew, filmOf) ?? '');
          }
          final s = m.sender;
          return _Slip(
            key: ValueKey(m.id),
            message: m,
            mine: s != null && s.id == myId,
            // A name and a stamp start a run of messages from one person.
            head: prev == null || prev.kind != MessageKind.text || prev.sender?.id != s?.id,
            crew: crew,
            crewId: widget.crewId,
            onBlock: s == null ? null : (name) => _block(s, name),
            onReport: () => _report(m),
          );
        },
      ),
    );
  }

  Widget _composer(BuildContext context, bool canSend) {
    final l = context.l;
    final p = Palette.of(context);
    final film = _film;
    return DecoratedBox(
      decoration: BoxDecoration(color: p.surface),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (film != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 320),
                      child: TicketRow(
                        film: film,
                        title: film.title,
                        sub: film.year == null ? null : '${film.year}',
                        end: TkButton(
                          Tk.close,
                          tooltip: l.chatRemoveFilm,
                          size: 18,
                          color: paperInkSoft,
                          onPressed: () => setState(() => _film = null),
                        ),
                      ),
                    ),
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  TkButton(Tk.films, key: const Key('chat-attach'), tooltip: l.chatAttach, onPressed: _attach),
                  Expanded(
                    child: TextField(
                      key: const Key('chat-text'),
                      controller: _text,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 1000,
                      keyboardType: TextInputType.multiline,
                      textCapitalization: TextCapitalization.sentences,
                      onChanged: (_) => setState(() => _problem = null),
                      decoration: InputDecoration(hintText: l.chatHint, counterText: '', isDense: true),
                    ),
                  ),
                  TkButton(
                    Tk.send,
                    key: const Key('chat-send'),
                    tooltip: l.chatSend,
                    color: canSend ? p.ink : p.inkSoft.withValues(alpha: 0.5),
                    onPressed: canSend ? _send : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The slip of somebody else: the surface tone. On the dark wall the surface is hardly lighter than the wall, so it
/// takes a little ink.
Color _paper(Palette p) => p.dark ? Color.lerp(p.surface, p.ink, 0.07)! : p.surface;

/// "Ravi joined": quiet, centered, no slip.
class _SystemLine extends StatelessWidget {
  const _SystemLine({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 24),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(color: Palette.of(context).inkSoft, fontSize: 13, height: 1.35),
    ),
  );
}

/// One message: a flat slip, with the sender's stamp and name on the first of a run, and the film or night it
/// came with as a ticket under it (not inside it).
class _Slip extends StatelessWidget {
  const _Slip({
    super.key,
    required this.message,
    required this.mine,
    required this.head,
    required this.crew,
    required this.crewId,
    required this.onBlock,
    required this.onReport,
  });
  final Message message;
  final bool mine, head;
  final Crew? crew;
  final String crewId;

  /// Null when the message names no sender. Gets the name to show in the question.
  final void Function(String name)? onBlock;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final p = Palette.of(context);
    final m = message;
    final s = m.sender;
    final name = s == null ? '' : (s.name ?? s.handle ?? l.friendsUnnamed);
    final film = m.film;
    final nightId = m.nightId;
    final night = nightId == null ? null : crew?.night(nightId);
    final nightFilm = night?.film;
    final body = (m.body ?? '').trim();

    final slip = body.isEmpty
        ? null
        : Semantics(
            onLongPressHint: mine ? null : l.chatReport,
            child: GestureDetector(
              onLongPress: mine ? null : onReport,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: mine ? p.accent : _paper(p), borderRadius: BorderRadius.circular(4)),
                child: Text(body, style: TextStyle(fontSize: 15, height: 1.35, color: mine ? onSlab(p) : p.ink)),
              ),
            ),
          );
    Widget ticket(Widget t) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 280), child: t),
    );
    final things = [
      ?slip,
      if (film != null)
        ticket(
          TicketRow(
            film: film,
            title: film.title,
            sub: film.year == null ? null : '${film.year}',
            onTap: () => openFilm(context, film),
          ),
        ),
      if (nightId != null)
        ticket(
          TicketRow(
            film: film == null ? nightFilm : null,
            title: nightFilm == null ? l.chatNight : l.chatNightFilm(nightFilm.title),
            end: const TkIcon(Tk.clock, size: 20, color: paperInkSoft),
            onTap: () => push(context, NightScreen(crewId: crewId, nightId: nightId)),
          ),
        ),
    ];

    if (mine) {
      return Padding(
        padding: const EdgeInsets.only(top: 3, bottom: 3, left: 56),
        child: Align(
          alignment: Alignment.centerRight,
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: things),
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.only(top: head ? 10 : 3, bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The stamp is the way to the block question, so it is a full 44 target.
          SizedBox(
            width: 44,
            height: head ? 44 : 0,
            child: head && s != null && onBlock != null
                ? Semantics(
                    button: true,
                    label: l.friendsBlockQ(name),
                    excludeSemantics: true,
                    child: GestureDetector(
                      key: Key('sender-${s.id}'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onBlock!(name),
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: Avatar(name: name, ink: s.ink, size: 36),
                      ),
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Padding(
              padding: const EdgeInsets.only(right: 36),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (head && name.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: p.inkSoft),
                      ),
                    ),
                  ...things,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
