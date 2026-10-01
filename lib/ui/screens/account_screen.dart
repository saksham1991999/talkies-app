import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../data/social.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/online.dart';
import '../../state/social.dart';
import '../../state/sync.dart';
import '../avatar.dart';
import '../common.dart';
import '../format.dart';
import '../icons.dart';
import '../online_gate.dart';
import '../online_parts.dart';
import '../theme.dart';
import '../widgets.dart';
import 'profile_screen.dart';

final _handleRe = RegExp(r'^[a-z0-9_]{3,20}$');
final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// Sign in, and once signed in the account: name, handle, stamp ink, who can see the films, blocked people,
/// sign out and delete. With the server down a signed-in user sees one quiet panel and Sign out.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _name = TextEditingController();
  final _handle = TextEditingController();

  /// A code went to [_sentTo]; the form asks for it.
  var _sent = false;
  var _sentTo = '';
  var _busy = false;
  var _asking = false;
  AuthResult? _result;
  String? _handleError;

  /// The profile id the name and handle fields were filled from.
  String? _seededFor;

  @override
  void initState() {
    super.initState();
    _seed(ref.read(meProvider).value ?? ref.read(sessionProvider)?.me);
    // Riverpod forbids provider changes while the widget builds: start after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadAccount();
      if (ref.read(syncEngineProvider) == SyncState.needsAccountChoice) _askChoice();
    });
  }

  @override
  void dispose() {
    for (final c in [_email, _code, _name, _handle]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Fills the name and handle fields once per account.
  void _seed(Me? me) {
    if (me == null || _seededFor == me.id) return;
    _seededFor = me.id;
    _name.text = me.displayName ?? '';
    _handle.text = me.handle ?? '';
  }

  void _loadAccount() {
    if (!mounted || !ref.read(onlineProvider)) return;
    ref.read(meProvider.notifier).load();
    ref.read(blocksProvider.notifier).load();
  }

  Future<void> _retry() async {
    await ref.read(backendProvider.notifier).probe(force: true);
    _loadAccount();
  }

  // Sign in ------------------------------------------------------------------

  Future<void> _run(Future<AuthResult> Function() call, {void Function()? onOk}) async {
    setState(() {
      _busy = true;
      _result = null;
    });
    final r = await call();
    if (!mounted) return;
    setState(() {
      _busy = false;
      // Cancelling a native sheet is not an error. Success flips the screen to the account.
      _result = r == AuthResult.ok || r == AuthResult.cancelled ? null : r;
    });
    if (r == AuthResult.ok) onOk?.call();
  }

  Future<void> _sendCode([String? to]) async {
    final email = (to ?? _email.text).trim();
    if (!_emailRe.hasMatch(email)) {
      setState(() => _result = AuthResult.badRequest);
      return;
    }
    await _run(
      () => ref.read(sessionProvider.notifier).requestCode(email),
      onOk: () => setState(() {
        _sent = true;
        _sentTo = email;
        _code.clear();
      }),
    );
  }

  Future<void> _verify() => _run(() => ref.read(sessionProvider.notifier).verifyCode(_sentTo, _code.text));

  // Account ------------------------------------------------------------------

  Future<CallResult<Me>> _patch(MePatch p) => ref.read(meProvider.notifier).patch(p);

  void _tell(CallResult<void> r) {
    if (!r.ok && mounted) say(context, problemText(context.l, r.outcome));
  }

  Future<void> _save(Me me) async {
    final l = context.l;
    final name = _name.text.trim();
    final handle = _handle.text.trim().toLowerCase();
    final handleChanged = handle != (me.handle ?? '');
    // ponytail: a handle cannot be cleared once set; the server has no rule for that case yet
    if (handleChanged && !_handleRe.hasMatch(handle)) {
      setState(() => _handleError = l.acctHandleInvalid);
      return;
    }
    final patch = MePatch(
      handle: handleChanged ? handle : null,
      displayName: name.isNotEmpty && name != me.displayName ? name : null,
      clearDisplayName: name.isEmpty && me.displayName != null,
    );
    if (patch.toJson().isEmpty) return;
    setState(() {
      _busy = true;
      _handleError = null;
    });
    final r = await _patch(patch);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r.outcome == CallOutcome.conflict && r.code == 'handle_taken') _handleError = l.acctHandleTaken;
      if (r.outcome == CallOutcome.invalid) _handleError = l.acctHandleInvalid;
    });
    if (r.ok) {
      _name.text = r.value?.displayName ?? '';
      _handle.text = r.value?.handle ?? '';
      say(context, l.acctSaved);
    } else if (_handleError == null) {
      _tell(r);
    }
  }

  Future<void> _visibility(Me me, ProfileVisibility v) async {
    if (v == me.visibility) return;
    if (v == ProfileVisibility.friends) {
      final go = await showModalBottomSheet<bool>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (c) => const _FriendsSheet(),
      );
      if (go != true || !mounted) return;
    }
    _tell(await _patch(MePatch(visibility: v)));
  }

  Future<void> _signOut() async {
    final l = context.l;
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    await ref.read(sessionProvider.notifier).signOut();
    if (!mounted) return;
    nav.pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l.acctSignedOut)));
  }

  Future<void> _delete() async {
    final l = context.l;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l.acctDeleteQ),
        content: Text(l.acctDeleteBody),
        actions: [
          TextButton(style: linkStyle(context), onPressed: () => Navigator.pop(c, false), child: Text(l.cancel)),
          TextButton(
            style: linkStyle(context),
            key: const Key('confirm-delete'),
            onPressed: () => Navigator.pop(c, true),
            child: Text(l.delete),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    final r = await ref.read(sessionProvider.notifier).deleteAccount();
    if (!mounted) return;
    setState(() => _busy = false);
    messenger.hideCurrentSnackBar();
    if (r == AuthResult.ok) {
      nav.pop();
      messenger.showSnackBar(SnackBar(content: Text(l.acctDeleted)));
    } else {
      messenger.showSnackBar(SnackBar(content: Text(r == AuthResult.offline ? l.gateCantReach : l.acctDeleteFailed)));
    }
  }

  /// This phone holds a diary of another account: merge it in, or keep the accounts apart.
  Future<void> _askChoice() async {
    if (_asking || !mounted) return;
    _asking = true;
    final l = context.l;
    final choice = await showDialog<AccountChoice>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l.acctChoiceTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.acctChoiceBody),
              const SizedBox(height: 14),
              Text(l.acctChoiceMerge, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(l.acctChoiceMergeNote),
              const SizedBox(height: 12),
              Text(l.acctChoiceSeparate, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(l.acctChoiceSeparateNote),
            ],
          ),
        ),
        actions: [
          TextButton(
            style: linkStyle(context),
            key: const Key('choice-separate'),
            onPressed: () => Navigator.pop(c, AccountChoice.separate),
            child: Text(l.acctChoiceSeparate),
          ),
          TextButton(
            style: linkStyle(context),
            key: const Key('choice-merge'),
            onPressed: () => Navigator.pop(c, AccountChoice.merge),
            child: Text(l.acctChoiceMerge),
          ),
        ],
      ),
    );
    _asking = false;
    if (choice != null && mounted) await ref.read(syncEngineProvider.notifier).chooseAccount(choice);
  }

  // Build --------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final p = Palette.of(context);
    final signedIn = ref.watch(signedInProvider);
    final up = ref.watch(backendProvider) == Backend.up;
    ref.listen(syncEngineProvider, (was, now) {
      if (now == SyncState.needsAccountChoice && was != now) _askChoice();
    });
    ref.listen(onlineProvider, (was, now) {
      if (now && was != true) _loadAccount();
    });
    ref.listen(meProvider, (_, s) => _seed(s.value));

    final Widget body;
    if (signedIn) {
      body = up ? _account(context) : _down(context);
    } else if (ref.watch(signInVisibleProvider)) {
      body = _signIn(context);
    } else {
      body = ListView(children: [CantReach(onRetry: _retry)]);
    }
    return Scaffold(
      appBar: AppBar(
        leading: TkButton(Tk.back, tooltip: l.back, onPressed: () => Navigator.maybePop(context)),
        title: Text(l.acctTitle.toUpperCase(), style: disp(26, p.ink)),
      ),
      body: body,
    );
  }

  // Signed out ---------------------------------------------------------------

  String? _notice(AppLocalizations l) => switch (_result) {
    AuthResult.badCode => l.acctBadCode,
    AuthResult.badRequest => l.acctBadRequest,
    AuthResult.rateLimited => l.acctRateLimited,
    AuthResult.disabled => l.acctDisabled,
    AuthResult.offline => l.gateCantReach,
    AuthResult.failed => l.acctFailed,
    _ => null,
  };

  Widget _signIn(BuildContext context) {
    final l = context.l;
    final p = Palette.of(context);
    final email = ref.watch(emailVisibleProvider);
    final google = ref.watch(googleVisibleProvider);
    final apple = ref.watch(appleVisibleProvider);
    final notice = _notice(l);
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 48),
      children: [
        Text(l.acctIntro, style: TextStyle(color: p.inkSoft, height: 1.45)),
        const SizedBox(height: 20),
        if (notice != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Semantics(
              liveRegion: true,
              child: Text(
                notice,
                style: TextStyle(color: p.ink, fontWeight: FontWeight.w600, height: 1.4),
              ),
            ),
          ),
        if (email) ..._emailForm(context),
        if (email && (apple || google))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Text(
              l.acctOr,
              textAlign: TextAlign.center,
              style: TextStyle(color: p.inkSoft),
            ),
          ),
        if (apple) _appleButton(context),
        if (apple && google) const SizedBox(height: 12),
        if (google)
          InkButton(
            key: const Key('google-sign-in'),
            label: l.acctGoogle,
            outlined: true,
            onPressed: _busy ? null : () => _run(ref.read(sessionProvider.notifier).signInWithGoogle),
          ),
        if (!email && !apple && !google) EmptyNote(l.acctNoMethods),
      ],
    );
  }

  List<Widget> _emailForm(BuildContext context) {
    final l = context.l;
    final p = Palette.of(context);
    if (!_sent) {
      return [
        AutofillGroup(
          child: TextField(
            key: const Key('email'),
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.send,
            autofillHints: const [AutofillHints.email],
            autocorrect: false,
            enableSuggestions: false,
            onSubmitted: (_) => _busy ? null : _sendCode(),
            decoration: InputDecoration(labelText: l.acctEmail, hintText: l.acctEmailHint),
          ),
        ),
        const SizedBox(height: 14),
        InkButton(key: const Key('send-code'), label: l.acctSendCode, onPressed: _busy ? null : _sendCode),
      ];
    }
    return [
      Text(l.acctCodeSent(_sentTo), style: TextStyle(color: p.ink, height: 1.4)),
      const SizedBox(height: 12),
      TextField(
        key: const Key('code'),
        controller: _code,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.done,
        autofillHints: const [AutofillHints.oneTimeCode],
        maxLength: 6,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onChanged: (_) => setState(() => _result = null),
        onSubmitted: (_) => _busy || _code.text.length != 6 ? null : _verify(),
        decoration: InputDecoration(labelText: l.acctCode, counterText: ''),
      ),
      const SizedBox(height: 14),
      InkButton(
        key: const Key('verify'),
        label: l.acctSignIn,
        onPressed: _busy || _code.text.length != 6 ? null : _verify,
      ),
      const SizedBox(height: 6),
      Wrap(
        spacing: 8,
        children: [
          TextButton(
            style: linkStyle(context),
            key: const Key('resend'),
            onPressed: _busy ? null : () => _sendCode(_sentTo),
            child: Text(l.acctResend),
          ),
          TextButton(
            style: linkStyle(context),
            key: const Key('other-email'),
            onPressed: _busy
                ? null
                : () => setState(() {
                    _sent = false;
                    _result = null;
                  }),
            child: Text(l.acctOtherEmail),
          ),
        ],
      ),
    ];
  }

  /// Apple's own button, so it follows Apple's guidelines. It is as high as the other buttons (50) and takes its
  /// text size from its height, which grows with the system text size (Apple allows 30 to 64), so the text scale
  /// is not applied twice.
  Widget _appleButton(BuildContext context) {
    final p = Palette.of(context);
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: SignInWithAppleButton(
        key: const Key('apple-sign-in'),
        text: context.l.acctApple,
        height: (50 * scale).clamp(50.0, 64.0),
        style: p.dark ? SignInWithAppleButtonStyle.white : SignInWithAppleButtonStyle.whiteOutlined,
        borderRadius: BorderRadius.circular(4),
        onPressed: _busy ? null : () => _run(ref.read(sessionProvider.notifier).signInWithApple),
      ),
    );
  }

  // Signed in, server down ---------------------------------------------------

  Widget _down(BuildContext context) {
    final l = context.l;
    final p = Palette.of(context);
    return ListView(
      padding: const EdgeInsets.only(bottom: 48),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Text(l.acctDown, style: TextStyle(color: p.inkSoft, height: 1.45)),
        ),
        NavRow(l.gateRetry, onTap: _retry),
        NavRow(l.acctSignOut, onTap: _busy ? null : _signOut),
      ],
    );
  }

  // Signed in ----------------------------------------------------------------

  Widget _account(BuildContext context) {
    final l = context.l;
    final p = Palette.of(context);
    final remote = ref.watch(meProvider);
    final me = remote.value ?? ref.watch(sessionProvider.select((s) => s?.me));
    final sync = ref.watch(syncEngineProvider);
    if (me == null) {
      return ListView(
        children: [
          if (remote.status == Fetch.offline || remote.status == Fetch.failed)
            CantReach(onRetry: _retry)
          else
            const LoadingBlock(),
        ],
      );
    }
    final shown = me.displayName ?? me.handle ?? '';
    final name = shown.isEmpty ? l.acctYou : shown;
    final dirty = _name.text.trim() != (me.displayName ?? '') || _handle.text.trim().toLowerCase() != (me.handle ?? '');
    final syncText = switch (sync) {
      SyncState.idle => l.acctSyncIdle,
      SyncState.syncing => l.acctSyncBusy,
      SyncState.failed => l.acctSyncFailed,
      SyncState.needsAccountChoice => l.acctSyncChoose,
    };
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.only(bottom: 48),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Row(
            children: [
              Avatar(name: shown, ink: me.avatarColor, size: 64),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: disp(30, p.ink, spacing: 0.6)),
                    Text(
                      me.handle == null ? l.acctNoHandle : '@${me.handle}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.inkSoft, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Text(syncText, style: TextStyle(color: p.inkSoft, fontSize: 13.5, height: 1.4)),
                ),
              ),
              if (sync == SyncState.needsAccountChoice)
                TextButton(
                  style: linkStyle(context),
                  key: const Key('choose-account'),
                  onPressed: _askChoice,
                  child: Text(l.acctChoose),
                ),
            ],
          ),
        ),
        NavRow(l.acctProfile, onTap: () => push(context, const ProfileScreen())),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const Key('name'),
                controller: _name,
                maxLength: 40,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(labelText: l.acctName, counterText: ''),
              ),
              const SizedBox(height: 14),
              TextField(
                key: const Key('handle'),
                controller: _handle,
                maxLength: 20,
                autocorrect: false,
                enableSuggestions: false,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9_]')),
                  TextInputFormatter.withFunction((_, n) => n.copyWith(text: n.text.toLowerCase())),
                ],
                onChanged: (_) => setState(() => _handleError = null),
                decoration: InputDecoration(
                  labelText: l.acctHandle,
                  prefixText: '@',
                  helperText: l.acctHandleHelp,
                  helperMaxLines: 3,
                  errorText: _handleError,
                  errorMaxLines: 3,
                  counterText: '',
                ),
              ),
              const SizedBox(height: 14),
              InkButton(
                key: const Key('save-profile'),
                label: l.save,
                icon: Tk.check,
                onPressed: dirty && !_busy ? () => _save(me) : null,
              ),
            ],
          ),
        ),
        SectionTitle(l.acctInk),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < accents.length; i++)
                Semantics(
                  button: true,
                  selected: me.avatarColor == i,
                  label: accentName(context, i),
                  child: InkWell(
                    key: Key('ink-$i'),
                    borderRadius: BorderRadius.circular(3),
                    onTap: _busy || me.avatarColor == i
                        ? null
                        : () async => _tell(await _patch(MePatch(avatarColor: i))),
                    child: Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: me.avatarColor == i ? p.ink : Colors.transparent, width: 1.6),
                      ),
                      child: ExcludeSemantics(
                        child: Avatar(name: shown, ink: i, size: 40),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        SectionTitle(l.acctVisibility),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OptionBox(
                key: const Key('vis-private'),
                label: l.acctVisPrivate,
                minHeight: 44,
                selected: me.visibility == ProfileVisibility.private,
                onTap: () => _visibility(me, ProfileVisibility.private),
              ),
              OptionBox(
                key: const Key('vis-friends'),
                label: l.acctVisFriends,
                minHeight: 44,
                selected: me.visibility == ProfileVisibility.friends,
                onTap: () => _visibility(me, ProfileVisibility.friends),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
          child: Text(
            me.visibility == ProfileVisibility.friends ? l.acctVisFriendsNote : l.acctVisPrivateNote,
            style: TextStyle(color: p.inkSoft, fontSize: 13.5, height: 1.4),
          ),
        ),
        SwitchListTile(
          key: const Key('share-ratings'),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          title: Text(l.acctShareRatings),
          value: me.shareRatings,
          onChanged: _busy ? null : (v) async => _tell(await _patch(MePatch(shareRatings: v))),
        ),
        SectionTitle(l.acctBlocked),
        _blocked(context),
        const SizedBox(height: 18),
        NavRow(l.acctSignOut, onTap: _busy ? null : _signOut),
        NavRow(l.acctDelete, onTap: _busy ? null : _delete),
      ],
    );
  }

  Widget _blocked(BuildContext context) {
    final l = context.l;
    final p = Palette.of(context);
    final b = ref.watch(blocksProvider);
    final people = b.value;
    if (people == null) {
      return switch (b.status) {
        Fetch.offline => CantReach(onRetry: _retry),
        Fetch.failed => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(l.acctFailed, style: TextStyle(color: p.inkSoft)),
        ),
        _ => const LoadingBlock(),
      };
    }
    if (people.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Text(l.acctBlockedNone, style: TextStyle(color: p.inkSoft, height: 1.4)),
      );
    }
    return Column(
      children: [
        for (final c in people)
          PersonRow(
            key: ValueKey(c.id),
            card: c,
            subtitle: c.handle == null ? null : '@${c.handle}',
            trailing: TextButton(
              style: linkStyle(context),
              key: Key('unblock-${c.id}'),
              onPressed: () async => _tell(await ref.read(blocksProvider.notifier).unblock(c.id)),
              child: Text(l.acctUnblock),
            ),
          ),
      ],
    );
  }
}

/// What "Friends only" means, before it is switched on. Pops true to go ahead.
class _FriendsSheet extends StatelessWidget {
  const _FriendsSheet();

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final p = Palette.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.privacySheetTitle.toUpperCase(), style: disp(22, p.ink)),
            const SizedBox(height: 12),
            Text(l.privacySheetBody, style: const TextStyle(height: 1.5)),
            const SizedBox(height: 18),
            InkButton(
              key: const Key('confirm-friends-only'),
              label: l.acctVisFriends,
              onPressed: () => Navigator.pop(context, true),
            ),
            const SizedBox(height: 6),
            TextButton(
              style: linkStyle(context),
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.cancel),
            ),
          ],
        ),
      ),
    );
  }
}
