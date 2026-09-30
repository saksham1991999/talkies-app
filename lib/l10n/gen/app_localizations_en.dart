// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Talkies';

  @override
  String get tabHome => 'Home';

  @override
  String get tabStubs => 'Stubs';

  @override
  String get tabCalendar => 'Calendar';

  @override
  String get tabFilms => 'Films';

  @override
  String get tabStats => 'Stats';

  @override
  String get recordFilm => 'Record a film';

  @override
  String get search => 'Search';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get delete => 'Delete';

  @override
  String get edit => 'Edit';

  @override
  String get done => 'Done';

  @override
  String get undo => 'Undo';

  @override
  String get share => 'Share';

  @override
  String get back => 'Back';

  @override
  String get clear => 'Clear';

  @override
  String get settings => 'Settings';

  @override
  String get previous => 'Previous';

  @override
  String get next => 'Next';

  @override
  String unitFilms(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: 'films', one: 'film');
    return '$_temp0';
  }

  @override
  String get thisYear => 'This year';

  @override
  String get recent => 'Recent';

  @override
  String get allStubs => 'All stubs';

  @override
  String get newReleases => 'New releases';

  @override
  String get comingSoon => 'Coming soon';

  @override
  String get forYou => 'For you';

  @override
  String becauseYouLiked(String title) {
    return 'Because you liked $title';
  }

  @override
  String get notInterested => 'Not interested';

  @override
  String get hiddenFromRecs => 'Hidden from recommendations';

  @override
  String get seeAll => 'See all';

  @override
  String get emptyHome => 'Your first ticket is one film away. Tap + and search for a title.';

  @override
  String get venueCinema => 'Cinema hall';

  @override
  String get venueOtt => 'Streaming';

  @override
  String get venueHome => 'Home';

  @override
  String get venueTv => 'TV';

  @override
  String get venueOther => 'Other';

  @override
  String get splitLegend => 'Where you watched this year';

  @override
  String ticketsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tickets',
      one: '1 ticket',
      zero: 'No tickets',
    );
    return '$_temp0';
  }

  @override
  String get sortNewest => 'Newest first';

  @override
  String get sortOldest => 'Oldest first';

  @override
  String get sortRatingHigh => 'Highest rated';

  @override
  String get sortRatingLow => 'Lowest rated';

  @override
  String get sort => 'Sort';

  @override
  String get filter => 'Filter';

  @override
  String get filterAll => 'All';

  @override
  String get filterPlace => 'Place';

  @override
  String get filterTag => 'Tag';

  @override
  String get filterYear => 'Year';

  @override
  String get filterKind => 'Type';

  @override
  String get filterRating => 'Rating';

  @override
  String get kindFilm => 'Films';

  @override
  String get kindSeries => 'Series';

  @override
  String get gridView => 'Grid view';

  @override
  String get listView => 'List view';

  @override
  String get searchStubs => 'Search your stubs';

  @override
  String get noStubs => 'No stubs yet. Every film you record becomes a ticket here.';

  @override
  String get noMatch => 'Nothing matches these filters.';

  @override
  String get resetFilters => 'Reset filters';

  @override
  String starsAtLeast(int stars) {
    return '$stars+ stars';
  }

  @override
  String calWatched(int count) {
    return '$count watched';
  }

  @override
  String calPlanned(int count) {
    return '$count planned';
  }

  @override
  String get showStubs => 'Stubs';

  @override
  String get showWatchlist => 'Watchlist';

  @override
  String get dayEmpty => 'Nothing on this day.';

  @override
  String get recordForDay => 'Record a film on this day';

  @override
  String get today => 'Today';

  @override
  String get filmsNew => 'New';

  @override
  String get filmsUpcoming => 'Upcoming';

  @override
  String get filmsWant => 'Want';

  @override
  String get filmsRecorded => 'Recorded';

  @override
  String get filmsReleased => 'Out now';

  @override
  String get allLanguages => 'All';

  @override
  String get wantEmpty => 'Bookmark films you want to watch. They show here and on your calendar.';

  @override
  String get recordedEmpty => 'Films you record show here.';

  @override
  String get noReleases =>
      'No releases in the offline list for this language. Refresh the film list when you are online.';

  @override
  String get refreshNow => 'Refresh film list';

  @override
  String get addedToWatchlist => 'Added to watchlist';

  @override
  String get removedFromWatchlist => 'Removed from watchlist';

  @override
  String watchCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Watched $count times',
      one: 'Watched once',
    );
    return '$_temp0';
  }

  @override
  String get searchHint => 'Film, series, actor or director';

  @override
  String get searchAll => 'All';

  @override
  String get notFound => 'Not in the list?';

  @override
  String get addManually => 'Add it yourself';

  @override
  String get loadingCatalog => 'Opening the film list';

  @override
  String get catalogError => 'The film list did not load. Restart the app.';

  @override
  String searchPrompt(String count) {
    return 'Search $count Indian and world titles. Works offline.';
  }

  @override
  String noResults(String query) {
    return 'No title matches “$query”.';
  }

  @override
  String get director => 'Director';

  @override
  String get cast => 'Cast';

  @override
  String get language => 'Language';

  @override
  String get country => 'Country';

  @override
  String seasons(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count seasons', one: '1 season');
    return '$_temp0';
  }

  @override
  String get availableOn => 'Streaming on';

  @override
  String get streamingHint => 'From Wikipedia. Availability can change.';

  @override
  String get synopsis => 'Synopsis';

  @override
  String get synopsisOffline => 'The synopsis needs an internet connection.';

  @override
  String get synopsisNone => 'No synopsis found.';

  @override
  String get iWatched => 'I watched it';

  @override
  String get watchedAgain => 'Watched again';

  @override
  String get wantToWatch => 'Want to watch';

  @override
  String get inWatchlist => 'In watchlist';

  @override
  String plannedFor(String date) {
    return 'Planned for $date';
  }

  @override
  String get setPlannedDate => 'Plan a date';

  @override
  String get clearDate => 'Clear date';

  @override
  String get yourStubs => 'Your stubs';

  @override
  String get openWikipedia => 'Read on Wikipedia';

  @override
  String get fixOnWikidata => 'Correct these details';

  @override
  String get fixHint => 'Film details come from Wikidata. Anyone can correct them there.';

  @override
  String get yourOwnFilm => 'Added by you';

  @override
  String watchNth(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: 'Watch no. $n',
      two: 'Second watch',
      one: 'First watch',
    );
    return '$_temp0';
  }

  @override
  String hoursMinutes(int h, int m) {
    return '${h}h ${m}m';
  }

  @override
  String minutesOnly(int m) {
    return '$m min';
  }

  @override
  String ticketNo(String no) {
    return 'No. $no';
  }

  @override
  String get ticket => 'Ticket';

  @override
  String get admitOne => 'ADMIT ONE';

  @override
  String get stampWatched => 'WATCHED';

  @override
  String get fdfs => 'FDFS';

  @override
  String get labelDate => 'Date';

  @override
  String get labelPlace => 'Place';

  @override
  String get labelShow => 'Show';

  @override
  String get labelClass => 'Class';

  @override
  String get labelSeat => 'Seat';

  @override
  String get labelPrice => 'Price';

  @override
  String get labelFormat => 'Format';

  @override
  String get labelLang => 'Watched in';

  @override
  String get labelWith => 'With';

  @override
  String get labelRating => 'Rating';

  @override
  String get labelTags => 'Tags';

  @override
  String get labelMemo => 'Notes';

  @override
  String get dateUnknown => 'Date not remembered';

  @override
  String get noRating => 'No rating';

  @override
  String get tearUpQ => 'Tear up this stub?';

  @override
  String get tearUpBody => 'This deletes the record of this viewing.';

  @override
  String get tearUp => 'Tear up';

  @override
  String get stubDeleted => 'Stub torn up';

  @override
  String get shareTicket => 'Share ticket';

  @override
  String get recordTitle => 'New stub';

  @override
  String get editTitle => 'Edit stub';

  @override
  String get whenWatched => 'When did you watch it?';

  @override
  String get precisionDay => 'Day';

  @override
  String get precisionMonth => 'Month';

  @override
  String get precisionYear => 'Year';

  @override
  String get precisionNone => 'Don\'t remember';

  @override
  String get yesterday => 'Yesterday';

  @override
  String get wherePlace => 'Where?';

  @override
  String get addPlace => 'New place';

  @override
  String get placeName => 'Place name';

  @override
  String get placeNameHint => 'PVR Phoenix, Maratha Mandir, Netflix';

  @override
  String get placeType => 'Type';

  @override
  String get hallDetails => 'Hall details';

  @override
  String get show => 'Show';

  @override
  String get format => 'Format';

  @override
  String get seatClass => 'Class';

  @override
  String get seat => 'Seat';

  @override
  String get seatHint => 'H12';

  @override
  String get price => 'Ticket price (₹)';

  @override
  String get priceHint => '250';

  @override
  String get fdfsToggle => 'First day, first show';

  @override
  String get watchedIn => 'Watched in';

  @override
  String get originalLang => 'Original';

  @override
  String get withWhom => 'Watched with';

  @override
  String get withHint => 'Friends, family, alone';

  @override
  String get rating => 'Rating';

  @override
  String get tags => 'Tags';

  @override
  String get addTag => 'New tag';

  @override
  String get tagHint => 'favourite';

  @override
  String get memo => 'Notes';

  @override
  String get memoHint => 'What stayed with you?';

  @override
  String get stampIt => 'Stamp it';

  @override
  String get saveChanges => 'Save changes';

  @override
  String get discardQ => 'Discard this stub?';

  @override
  String get discard => 'Discard';

  @override
  String get keepEditing => 'Keep editing';

  @override
  String get customTitle => 'Add a film yourself';

  @override
  String get customName => 'Title';

  @override
  String get customYear => 'Year';

  @override
  String get customLang => 'Language';

  @override
  String get customSeries => 'It is a series';

  @override
  String get customPoster => 'Poster';

  @override
  String get choosePhoto => 'Choose photo';

  @override
  String get removePhoto => 'Remove photo';

  @override
  String get customSave => 'Add and record';

  @override
  String get customSaveWish => 'Add to watchlist';

  @override
  String get required => 'Required';

  @override
  String yearInvalid(int max) {
    return 'Enter a year from 1900 to $max';
  }

  @override
  String get statsTitle => 'Stats';

  @override
  String get scopeMonth => 'Month';

  @override
  String get scopeYear => 'Year';

  @override
  String get scopeAll => 'All time';

  @override
  String get totalStubs => 'Stubs';

  @override
  String get totalTime => 'Watch time';

  @override
  String get spent => 'Spent on tickets';

  @override
  String avgTicket(String amount) {
    return '$amount per ticket on average';
  }

  @override
  String get fdfsCount => 'FDFS';

  @override
  String get rewatches => 'Rewatches';

  @override
  String get avgRating => 'Average rating';

  @override
  String get byDay => 'By day';

  @override
  String get byMonth => 'By month';

  @override
  String get byYear => 'By year';

  @override
  String get byStars => 'Ratings';

  @override
  String get byPlace => 'Places';

  @override
  String get byVenueType => 'Where you watch';

  @override
  String get byGenre => 'Genres';

  @override
  String get byLanguage => 'Languages';

  @override
  String get byCountry => 'Countries';

  @override
  String get byDecade => 'Decades';

  @override
  String get byDirector => 'Directors you watch most';

  @override
  String get byActor => 'Actors you watch most';

  @override
  String get byTag => 'Tags';

  @override
  String get byFormat => 'Formats';

  @override
  String get byShow => 'Show times';

  @override
  String get statsEmpty => 'No stubs in this period.';

  @override
  String get tapForDetail => 'Tap a bar to see its films.';

  @override
  String showMore(int count) {
    return 'Show all $count';
  }

  @override
  String get showLess => 'Show less';

  @override
  String get unrated => 'Unrated';

  @override
  String decadeLabel(String decade) {
    return '${decade}s';
  }

  @override
  String get shareTitle => 'Share image';

  @override
  String get background => 'Background';

  @override
  String get showTitles => 'Titles';

  @override
  String get showDates => 'Dates';

  @override
  String get showRatings => 'Ratings';

  @override
  String get shareMonth => 'Share this month';

  @override
  String monthAtMovies(String month) {
    return '$month at the movies';
  }

  @override
  String get nothingToShare => 'No stubs this month yet.';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get appearance => 'Appearance';

  @override
  String get theme => 'Theme';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get accentColor => 'Stamp ink';

  @override
  String get accent_sindoor => 'Sindoor';

  @override
  String get accent_marigold => 'Marigold';

  @override
  String get accent_peacock => 'Peacock';

  @override
  String get accent_mehendi => 'Mehendi';

  @override
  String get accent_neel => 'Neel';

  @override
  String get accent_jamun => 'Jamun';

  @override
  String get accent_gulabi => 'Gulabi';

  @override
  String get accent_kesar => 'Kesar';

  @override
  String get accent_paan => 'Paan';

  @override
  String get accent_chai => 'Chai';

  @override
  String get accent_kajal => 'Kajal';

  @override
  String get appIcon => 'App icon';

  @override
  String get icon_default => 'Pink ticket';

  @override
  String get icon_yellow => 'Yellow ticket';

  @override
  String get icon_green => 'Green ticket';

  @override
  String get icon_blue => 'Blue ticket';

  @override
  String get icon_night => 'Night show';

  @override
  String get iconChanged => 'App icon changed';

  @override
  String get iconFailed => 'This device did not change the icon.';

  @override
  String get appLanguage => 'App language';

  @override
  String get languageSystem => 'Device language';

  @override
  String get calendarSection => 'Calendar';

  @override
  String get weekStart => 'Week starts on';

  @override
  String get sunday => 'Sunday';

  @override
  String get monday => 'Monday';

  @override
  String get ratingsSection => 'Ratings';

  @override
  String get showRatingsToggle => 'Show star ratings';

  @override
  String get releaseLists => 'New and upcoming lists';

  @override
  String get releasesIndia => 'Indian films';

  @override
  String get releasesWorld => 'All films';

  @override
  String get manageTags => 'Tags';

  @override
  String get manageVenues => 'Places';

  @override
  String get dataSection => 'Your data';

  @override
  String get exportCsv => 'Export CSV';

  @override
  String get importCsv => 'Import CSV';

  @override
  String get importHint => 'A Talkies or Letterboxd CSV file';

  @override
  String get backup => 'Back up everything';

  @override
  String get backupHint => 'One JSON file. Keep it in Drive or send it to yourself.';

  @override
  String get restore => 'Restore a backup';

  @override
  String get batchAdd => 'Quick add';

  @override
  String get batchAddHint => 'Paste a list of titles';

  @override
  String get refreshCatalog => 'Refresh film list';

  @override
  String refreshedOn(String date, String updated) {
    return 'Built $date. Updated $updated.';
  }

  @override
  String builtOn(String date) {
    return 'Built $date. Not refreshed yet.';
  }

  @override
  String refreshDone(int count) {
    return '$count recent and upcoming films updated';
  }

  @override
  String get refreshFailed => 'Could not refresh. Check the connection.';

  @override
  String get about => 'About';

  @override
  String get aboutBody =>
      'Talkies is a ticket diary for Indian film lovers. Your stubs stay on this phone. Film details come from Wikidata (CC0) and posters from Wikipedia.';

  @override
  String version(String v) {
    return 'Version $v';
  }

  @override
  String get whatsNew => 'What\'s new';

  @override
  String get privacyPolicy => 'Privacy policy';

  @override
  String get replaceQ => 'Replace everything with this backup?';

  @override
  String replaceBody(int count) {
    return 'Your current $count stubs will be replaced by the backup.';
  }

  @override
  String get replace => 'Replace';

  @override
  String get restoreDone => 'Backup restored';

  @override
  String get restoreFailed => 'This file is not a Talkies backup.';

  @override
  String imported(int count, int matched, int custom) {
    return '$count stubs added. $matched matched the film list, $custom added as your own films.';
  }

  @override
  String get importNothing => 'No rows found in this file.';

  @override
  String get nothingToExport => 'No stubs to export yet.';

  @override
  String get tagsEmpty => 'No tags yet. Add one here or while you record a film.';

  @override
  String get renameTag => 'Rename tag';

  @override
  String deleteTagQ(String tag, int count) {
    return 'Delete #$tag? It is removed from $count stubs.';
  }

  @override
  String get editVenue => 'Edit place';

  @override
  String deleteVenueQ(String name) {
    return 'Remove $name from the list? Stubs keep the name.';
  }

  @override
  String get remove => 'Remove';

  @override
  String stubsUsing(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Used on $count stubs',
      one: 'Used on 1 stub',
      zero: 'Not used',
    );
    return '$_temp0';
  }

  @override
  String get batchTitle => 'Quick add';

  @override
  String get batchHint => 'One title per line. Add a year to be exact.';

  @override
  String get batchExample => 'Sholay 1975\nRRR (2022)\nPanchayat';

  @override
  String get batchMatch => 'Match titles';

  @override
  String batchAddAll(int count) {
    return 'Add $count stubs';
  }

  @override
  String get batchOwn => 'No match. Added as your own film.';

  @override
  String get batchDefaults => 'For every film';

  @override
  String batchDone(int count) {
    return '$count stubs added';
  }

  @override
  String whatsNewTitle(String v) {
    return 'Talkies $v';
  }

  @override
  String get whatsNew1 =>
      'Every premium feature is free: all-time stats, unlimited tags, 11 stamp inks, dark mode, app icons, share backgrounds and CSV export.';

  @override
  String get whatsNew2 => 'Record hall details: show, class, seat, format, ticket price and first day first show.';

  @override
  String get whatsNew3 => '34,000 Indian and world titles work offline. New releases refresh when you are online.';

  @override
  String get gotIt => 'Got it';
}
