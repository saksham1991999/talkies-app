import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/social.dart';
import '../../state/online.dart';
import '../../state/providers.dart';
import '../../state/social.dart';
import '../avatar.dart';
import '../common.dart';
import '../format.dart';
import '../icons.dart';
import '../online_parts.dart';
import '../profile_body.dart';
import '../share.dart';
import '../theme.dart';
import '../widgets.dart';
import 'account_screen.dart';

/// "Your profile": the stats ticket, top films and watchlist of your own diary, as a friend would see them
/// (no private stub, no date). It works with no account and no server. Signed in, it adds the name, the handle
/// and who can see it.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final p = Palette.of(context);
    final signedIn = ref.watch(signedInProvider);
    final me = signedIn ? ref.watch(meProvider).value ?? ref.watch(sessionProvider.select((s) => s?.me)) : null;
    final diary = ref.watch(diaryProvider);
    final catalog = ref.watch(catalogProvider).value;
    final showRatings = ref.watch(settingsProvider.select((s) => s.showRatings));
    // With an account, friends see ratings only when you allow it. Without one, the preview follows the app.
    final ratings = signedIn ? me?.shareRatings ?? false : showRatings;
    final view = catalog == null ? null : ProfileView.fromDiary(diary, catalog, card: me?.card, ratings: ratings);
    // Nothing a friend could see yet: no viewing (private and custom films do not count) and no watchlist.
    final blank = view != null && (view.stats?.viewings ?? 0) == 0 && view.watchlist.isEmpty;
    final shown = me?.displayName ?? me?.handle ?? '';

    return Scaffold(
      appBar: AppBar(
        leading: TkButton(Tk.back, tooltip: l.back, onPressed: () => Navigator.maybePop(context)),
        title: Text(l.profileTitle.toUpperCase(), style: disp(26, p.ink)),
        actions: [
          if (view != null && !blank)
            TkButton(
              Tk.share,
              tooltip: l.profileShare,
              onPressed: () => showShareSheet(
                context,
                ProfileShare(
                  view: view,
                  title: shown.isEmpty ? l.profileShareTitle : shown,
                  handle: me?.handle,
                  ratings: ratings,
                ),
              ),
            ),
          const SizedBox(width: 6),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 48),
        children: [
          if (signedIn) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Row(
                children: [
                  Avatar(name: shown, ink: me?.avatarColor ?? 0, size: 56),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          shown.isEmpty ? l.acctYou : shown,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: disp(30, p.ink, spacing: 0.6),
                        ),
                        if (me?.handle != null)
                          Text(
                            '@${me!.handle}',
                            style: TextStyle(color: p.inkSoft, fontWeight: FontWeight.w600),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            NavRow(
              l.profileVisibility(me?.visibility == ProfileVisibility.friends ? l.acctVisFriends : l.acctVisPrivate),
              onTap: () => push(context, const AccountScreen()),
            ),
            const SizedBox(height: 8),
          ],
          if (view == null)
            const LoadingBlock()
          else if (blank)
            EmptyNote(l.profileEmpty, action: l.recordFilm, onAction: () => startRecord(context))
          else
            ProfileBody(view: view, ratings: ratings),
          // The one way to an account from here: only while the server is up and nobody is signed in.
          if (ref.watch(signInVisibleProvider)) ...[
            const SizedBox(height: 18),
            NavRow(l.profileSignInFoot, onTap: () => push(context, const AccountScreen())),
          ],
        ],
      ),
    );
  }
}
