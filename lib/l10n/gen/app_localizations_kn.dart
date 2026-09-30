// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Kannada (`kn`).
class AppLocalizationsKn extends AppLocalizations {
  AppLocalizationsKn([String locale = 'kn']) : super(locale);

  @override
  String get appName => 'ಟಾಕೀಸ್';

  @override
  String get tabHome => 'ಹೋಮ್';

  @override
  String get tabStubs => 'ಟಿಕೆಟ್‌ಗಳು';

  @override
  String get tabCalendar => 'ಕ್ಯಾಲೆಂಡರ್';

  @override
  String get tabFilms => 'ಸಿನಿಮಾಗಳು';

  @override
  String get tabStats => 'ಅಂಕಿಅಂಶ';

  @override
  String get recordFilm => 'ಸಿನಿಮಾ ದಾಖಲಿಸಿ';

  @override
  String get search => 'ಹುಡುಕಿ';

  @override
  String get cancel => 'ರದ್ದುಮಾಡಿ';

  @override
  String get save => 'ಉಳಿಸಿ';

  @override
  String get delete => 'ಅಳಿಸಿ';

  @override
  String get edit => 'ಬದಲಿಸಿ';

  @override
  String get done => 'ಆಯಿತು';

  @override
  String get undo => 'ಹಿಂಪಡೆಯಿರಿ';

  @override
  String get share => 'ಹಂಚಿಕೊಳ್ಳಿ';

  @override
  String get back => 'ಹಿಂದೆ';

  @override
  String get clear => 'ತೆರವುಗೊಳಿಸಿ';

  @override
  String get settings => 'ಸೆಟ್ಟಿಂಗ್‌ಗಳು';

  @override
  String get previous => 'ಹಿಂದಿನದು';

  @override
  String get next => 'ಮುಂದಿನದು';

  @override
  String unitFilms(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: 'ಸಿನಿಮಾಗಳು', one: 'ಸಿನಿಮಾ');
    return '$_temp0';
  }

  @override
  String get thisYear => 'ಈ ವರ್ಷ';

  @override
  String get recent => 'ಇತ್ತೀಚಿನವು';

  @override
  String get allStubs => 'ಎಲ್ಲಾ ಟಿಕೆಟ್‌ಗಳು';

  @override
  String get newReleases => 'ಹೊಸ ಬಿಡುಗಡೆಗಳು';

  @override
  String get comingSoon => 'ಶೀಘ್ರದಲ್ಲೇ ಬರಲಿವೆ';

  @override
  String get forYou => 'ನಿಮಗಾಗಿ';

  @override
  String becauseYouLiked(String title) {
    return 'ನಿಮಗೆ $title ಇಷ್ಟವಾದ ಕಾರಣ';
  }

  @override
  String get notInterested => 'ಆಸಕ್ತಿ ಇಲ್ಲ';

  @override
  String get hiddenFromRecs => 'ಶಿಫಾರಸುಗಳಿಂದ ಮರೆಮಾಡಲಾಗಿದೆ';

  @override
  String get seeAll => 'ಎಲ್ಲಾ ನೋಡಿ';

  @override
  String get emptyHome => 'ನಿಮ್ಮ ಮೊದಲ ಟಿಕೆಟ್‌ಗೆ ಒಂದೇ ಸಿನಿಮಾ ಸಾಕು. + ಒತ್ತಿ, ಸಿನಿಮಾದ ಹೆಸರು ಹುಡುಕಿ.';

  @override
  String get venueCinema => 'ಥಿಯೇಟರ್';

  @override
  String get venueOtt => 'ಸ್ಟ್ರೀಮಿಂಗ್';

  @override
  String get venueHome => 'ಮನೆ';

  @override
  String get venueTv => 'ಟಿವಿ';

  @override
  String get venueOther => 'ಇತರೆ';

  @override
  String get splitLegend => 'ಈ ವರ್ಷ ನೀವು ಎಲ್ಲಿ ನೋಡಿದಿರಿ';

  @override
  String ticketsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ಟಿಕೆಟ್‌ಗಳು',
      one: '1 ಟಿಕೆಟ್',
      zero: 'ಟಿಕೆಟ್ ಇಲ್ಲ',
    );
    return '$_temp0';
  }

  @override
  String get sortNewest => 'ಹೊಸದು ಮೊದಲು';

  @override
  String get sortOldest => 'ಹಳೆಯದು ಮೊದಲು';

  @override
  String get sortRatingHigh => 'ಅತಿ ಹೆಚ್ಚು ರೇಟಿಂಗ್';

  @override
  String get sortRatingLow => 'ಅತಿ ಕಡಿಮೆ ರೇಟಿಂಗ್';

  @override
  String get sort => 'ವಿಂಗಡಿಸಿ';

  @override
  String get filter => 'ಫಿಲ್ಟರ್';

  @override
  String get filterAll => 'ಎಲ್ಲಾ';

  @override
  String get filterPlace => 'ಸ್ಥಳ';

  @override
  String get filterTag => 'ಟ್ಯಾಗ್';

  @override
  String get filterYear => 'ವರ್ಷ';

  @override
  String get filterKind => 'ಪ್ರಕಾರ';

  @override
  String get filterRating => 'ರೇಟಿಂಗ್';

  @override
  String get kindFilm => 'ಸಿನಿಮಾಗಳು';

  @override
  String get kindSeries => 'ಸೀರೀಸ್';

  @override
  String get gridView => 'ಗ್ರಿಡ್ ವ್ಯೂ';

  @override
  String get listView => 'ಲಿಸ್ಟ್ ವ್ಯೂ';

  @override
  String get searchStubs => 'ನಿಮ್ಮ ಟಿಕೆಟ್‌ಗಳನ್ನು ಹುಡುಕಿ';

  @override
  String get noStubs => 'ಇನ್ನೂ ಟಿಕೆಟ್ ಇಲ್ಲ. ನೀವು ದಾಖಲಿಸುವ ಪ್ರತಿ ಸಿನಿಮಾ ಇಲ್ಲಿ ಒಂದು ಟಿಕೆಟ್ ಆಗುತ್ತದೆ.';

  @override
  String get noMatch => 'ಈ ಫಿಲ್ಟರ್‌ಗಳಿಗೆ ಏನೂ ಸಿಗಲಿಲ್ಲ.';

  @override
  String get resetFilters => 'ಫಿಲ್ಟರ್ ತೆಗೆಯಿರಿ';

  @override
  String starsAtLeast(int stars) {
    return '$stars+ ಸ್ಟಾರ್';
  }

  @override
  String calWatched(int count) {
    return '$count ನೋಡಿದ್ದು';
  }

  @override
  String calPlanned(int count) {
    return '$count ಯೋಜಿತ';
  }

  @override
  String get showStubs => 'ಟಿಕೆಟ್‌ಗಳು';

  @override
  String get showWatchlist => 'ನೋಡಬೇಕಾದವು';

  @override
  String get dayEmpty => 'ಈ ದಿನ ಏನೂ ಇಲ್ಲ.';

  @override
  String get recordForDay => 'ಈ ದಿನದ ಸಿನಿಮಾ ದಾಖಲಿಸಿ';

  @override
  String get today => 'ಇಂದು';

  @override
  String get filmsNew => 'ಹೊಸದು';

  @override
  String get filmsUpcoming => 'ಮುಂಬರುವ';

  @override
  String get filmsWant => 'ನೋಡಬೇಕು';

  @override
  String get filmsRecorded => 'ನೋಡಿದವು';

  @override
  String get filmsReleased => 'ಬಿಡುಗಡೆಯಾಗಿವೆ';

  @override
  String get allLanguages => 'ಎಲ್ಲಾ';

  @override
  String get wantEmpty => 'ನೋಡಬೇಕಾದ ಸಿನಿಮಾಗಳನ್ನು ಬುಕ್‌ಮಾರ್ಕ್ ಮಾಡಿ. ಅವು ಇಲ್ಲಿ ಮತ್ತು ನಿಮ್ಮ ಕ್ಯಾಲೆಂಡರ್‌ನಲ್ಲಿ ಕಾಣಿಸುತ್ತವೆ.';

  @override
  String get recordedEmpty => 'ನೀವು ದಾಖಲಿಸಿದ ಸಿನಿಮಾಗಳು ಇಲ್ಲಿ ಕಾಣಿಸುತ್ತವೆ.';

  @override
  String get noReleases =>
      'ಆಫ್‌ಲೈನ್ ಪಟ್ಟಿಯಲ್ಲಿ ಈ ಭಾಷೆಯ ಬಿಡುಗಡೆಗಳಿಲ್ಲ. ಆನ್‌ಲೈನ್ ಇರುವಾಗ ಸಿನಿಮಾ ಪಟ್ಟಿಯನ್ನು ರಿಫ್ರೆಶ್ ಮಾಡಿ.';

  @override
  String get refreshNow => 'ಸಿನಿಮಾ ಪಟ್ಟಿ ರಿಫ್ರೆಶ್ ಮಾಡಿ';

  @override
  String get addedToWatchlist => 'ವಾಚ್‌ಲಿಸ್ಟ್‌ಗೆ ಸೇರಿಸಲಾಗಿದೆ';

  @override
  String get removedFromWatchlist => 'ವಾಚ್‌ಲಿಸ್ಟ್‌ನಿಂದ ತೆಗೆಯಲಾಗಿದೆ';

  @override
  String watchCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ಬಾರಿ ನೋಡಿದ್ದು',
      one: 'ಒಮ್ಮೆ ನೋಡಿದ್ದು',
    );
    return '$_temp0';
  }

  @override
  String get searchHint => 'ಸಿನಿಮಾ, ಸೀರೀಸ್, ನಟ ಅಥವಾ ನಿರ್ದೇಶಕ';

  @override
  String get searchAll => 'ಎಲ್ಲಾ';

  @override
  String get notFound => 'ಪಟ್ಟಿಯಲ್ಲಿ ಇಲ್ಲವೇ?';

  @override
  String get addManually => 'ನೀವೇ ಸೇರಿಸಿ';

  @override
  String get loadingCatalog => 'ಸಿನಿಮಾ ಪಟ್ಟಿ ತೆರೆಯುತ್ತಿದೆ';

  @override
  String get catalogError => 'ಸಿನಿಮಾ ಪಟ್ಟಿ ಲೋಡ್ ಆಗಲಿಲ್ಲ. ಆ್ಯಪ್ ಅನ್ನು ಮತ್ತೆ ತೆರೆಯಿರಿ.';

  @override
  String searchPrompt(String count) {
    return '$count ಭಾರತೀಯ ಮತ್ತು ವಿದೇಶಿ ಟೈಟಲ್‌ಗಳನ್ನು ಹುಡುಕಿ. ಆಫ್‌ಲೈನ್‌ನಲ್ಲೂ ಕೆಲಸ ಮಾಡುತ್ತದೆ.';
  }

  @override
  String noResults(String query) {
    return '“$query” ಗೆ ಯಾವ ಟೈಟಲ್ ಕೂಡ ಸಿಗಲಿಲ್ಲ.';
  }

  @override
  String get director => 'ನಿರ್ದೇಶಕ';

  @override
  String get cast => 'ತಾರಾಗಣ';

  @override
  String get language => 'ಭಾಷೆ';

  @override
  String get country => 'ದೇಶ';

  @override
  String seasons(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count ಸೀಸನ್‌ಗಳು', one: '1 ಸೀಸನ್');
    return '$_temp0';
  }

  @override
  String get availableOn => 'ಇಲ್ಲಿ ಸ್ಟ್ರೀಮ್ ಆಗುತ್ತಿದೆ';

  @override
  String get streamingHint => 'ವಿಕಿಪೀಡಿಯದಿಂದ. ಲಭ್ಯತೆ ಬದಲಾಗಬಹುದು.';

  @override
  String get synopsis => 'ಕಥೆ';

  @override
  String get synopsisOffline => 'ಕಥೆ ನೋಡಲು ಇಂಟರ್ನೆಟ್ ಬೇಕು.';

  @override
  String get synopsisNone => 'ಕಥೆ ಸಿಗಲಿಲ್ಲ.';

  @override
  String get iWatched => 'ನಾನು ನೋಡಿದೆ';

  @override
  String get watchedAgain => 'ಮತ್ತೆ ನೋಡಿದೆ';

  @override
  String get wantToWatch => 'ನೋಡಬೇಕು';

  @override
  String get inWatchlist => 'ವಾಚ್‌ಲಿಸ್ಟ್‌ನಲ್ಲಿದೆ';

  @override
  String plannedFor(String date) {
    return '$date ರಂದು ಯೋಜಿಸಲಾಗಿದೆ';
  }

  @override
  String get setPlannedDate => 'ದಿನಾಂಕ ನಿಗದಿಪಡಿಸಿ';

  @override
  String get clearDate => 'ದಿನಾಂಕ ತೆಗೆಯಿರಿ';

  @override
  String get yourStubs => 'ನಿಮ್ಮ ಟಿಕೆಟ್‌ಗಳು';

  @override
  String get openWikipedia => 'Wikipedia ದಲ್ಲಿ ಓದಿ';

  @override
  String get fixOnWikidata => 'ಈ ವಿವರಗಳನ್ನು ಸರಿಪಡಿಸಿ';

  @override
  String get fixHint => 'ಸಿನಿಮಾ ವಿವರಗಳು Wikidata ದಿಂದ ಬರುತ್ತವೆ. ಯಾರು ಬೇಕಾದರೂ ಅಲ್ಲಿ ಸರಿಪಡಿಸಬಹುದು.';

  @override
  String get yourOwnFilm => 'ನೀವು ಸೇರಿಸಿದ್ದು';

  @override
  String watchNth(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$nನೇ ಬಾರಿ',
      two: 'ಎರಡನೇ ಬಾರಿ',
      one: 'ಮೊದಲ ಬಾರಿ',
    );
    return '$_temp0';
  }

  @override
  String hoursMinutes(int h, int m) {
    return '$h ಗಂ $m ನಿ';
  }

  @override
  String minutesOnly(int m) {
    return '$m ನಿಮಿಷ';
  }

  @override
  String ticketNo(String no) {
    return 'ನಂ. $no';
  }

  @override
  String get ticket => 'ಟಿಕೆಟ್';

  @override
  String get admitOne => 'ADMIT ONE';

  @override
  String get stampWatched => 'WATCHED';

  @override
  String get fdfs => 'FDFS';

  @override
  String get labelDate => 'ದಿನಾಂಕ';

  @override
  String get labelPlace => 'ಸ್ಥಳ';

  @override
  String get labelShow => 'ಶೋ';

  @override
  String get labelClass => 'ಕ್ಲಾಸ್';

  @override
  String get labelSeat => 'ಸೀಟ್';

  @override
  String get labelPrice => 'ಬೆಲೆ';

  @override
  String get labelFormat => 'ಫಾರ್ಮ್ಯಾಟ್';

  @override
  String get labelLang => 'ನೋಡಿದ ಭಾಷೆ';

  @override
  String get labelWith => 'ಯಾರ ಜೊತೆ';

  @override
  String get labelRating => 'ರೇಟಿಂಗ್';

  @override
  String get labelTags => 'ಟ್ಯಾಗ್‌ಗಳು';

  @override
  String get labelMemo => 'ಟಿಪ್ಪಣಿ';

  @override
  String get dateUnknown => 'ದಿನಾಂಕ ನೆನಪಿಲ್ಲ';

  @override
  String get noRating => 'ರೇಟಿಂಗ್ ಇಲ್ಲ';

  @override
  String get tearUpQ => 'ಈ ಟಿಕೆಟ್ ಹರಿದು ಹಾಕಬೇಕೇ?';

  @override
  String get tearUpBody => 'ಈ ಬಾರಿ ನೋಡಿದ ದಾಖಲೆ ಅಳಿಸಿಹೋಗುತ್ತದೆ.';

  @override
  String get tearUp => 'ಹರಿದು ಹಾಕಿ';

  @override
  String get stubDeleted => 'ಟಿಕೆಟ್ ಹರಿದು ಹಾಕಲಾಗಿದೆ';

  @override
  String get shareTicket => 'ಟಿಕೆಟ್ ಹಂಚಿಕೊಳ್ಳಿ';

  @override
  String get recordTitle => 'ಹೊಸ ಟಿಕೆಟ್';

  @override
  String get editTitle => 'ಟಿಕೆಟ್ ಬದಲಿಸಿ';

  @override
  String get whenWatched => 'ಯಾವಾಗ ನೋಡಿದಿರಿ?';

  @override
  String get precisionDay => 'ದಿನ';

  @override
  String get precisionMonth => 'ತಿಂಗಳು';

  @override
  String get precisionYear => 'ವರ್ಷ';

  @override
  String get precisionNone => 'ನೆನಪಿಲ್ಲ';

  @override
  String get yesterday => 'ನಿನ್ನೆ';

  @override
  String get wherePlace => 'ಎಲ್ಲಿ?';

  @override
  String get addPlace => 'ಹೊಸ ಸ್ಥಳ';

  @override
  String get placeName => 'ಸ್ಥಳದ ಹೆಸರು';

  @override
  String get placeNameHint => 'PVR Orion, ಸಂತೋಷ್, Netflix';

  @override
  String get placeType => 'ಪ್ರಕಾರ';

  @override
  String get hallDetails => 'ಹಾಲ್ ವಿವರಗಳು';

  @override
  String get show => 'ಶೋ';

  @override
  String get format => 'ಫಾರ್ಮ್ಯಾಟ್';

  @override
  String get seatClass => 'ಕ್ಲಾಸ್';

  @override
  String get seat => 'ಸೀಟ್';

  @override
  String get seatHint => 'H12';

  @override
  String get price => 'ಟಿಕೆಟ್ ಬೆಲೆ (₹)';

  @override
  String get priceHint => '250';

  @override
  String get fdfsToggle => 'ಮೊದಲ ದಿನ, ಮೊದಲ ಶೋ';

  @override
  String get watchedIn => 'ನೋಡಿದ ಭಾಷೆ';

  @override
  String get originalLang => 'ಮೂಲ';

  @override
  String get withWhom => 'ಯಾರ ಜೊತೆ ನೋಡಿದಿರಿ';

  @override
  String get withHint => 'ಸ್ನೇಹಿತರು, ಕುಟುಂಬ, ಒಬ್ಬರೇ';

  @override
  String get rating => 'ರೇಟಿಂಗ್';

  @override
  String get tags => 'ಟ್ಯಾಗ್‌ಗಳು';

  @override
  String get addTag => 'ಹೊಸ ಟ್ಯಾಗ್';

  @override
  String get tagHint => 'ಮೆಚ್ಚಿನದು';

  @override
  String get memo => 'ಟಿಪ್ಪಣಿ';

  @override
  String get memoHint => 'ಏನು ನೆನಪಿನಲ್ಲಿ ಉಳಿಯಿತು?';

  @override
  String get stampIt => 'ಮುದ್ರೆ ಒತ್ತಿ';

  @override
  String get saveChanges => 'ಬದಲಾವಣೆ ಉಳಿಸಿ';

  @override
  String get discardQ => 'ಈ ಟಿಕೆಟ್ ಕೈಬಿಡಬೇಕೇ?';

  @override
  String get discard => 'ಕೈಬಿಡಿ';

  @override
  String get keepEditing => 'ಬದಲಿಸುವುದನ್ನು ಮುಂದುವರಿಸಿ';

  @override
  String get customTitle => 'ಸಿನಿಮಾವನ್ನು ನೀವೇ ಸೇರಿಸಿ';

  @override
  String get customName => 'ಹೆಸರು';

  @override
  String get customYear => 'ವರ್ಷ';

  @override
  String get customLang => 'ಭಾಷೆ';

  @override
  String get customSeries => 'ಇದು ಸೀರೀಸ್';

  @override
  String get customPoster => 'ಪೋಸ್ಟರ್';

  @override
  String get choosePhoto => 'ಫೋಟೋ ಆಯ್ಕೆಮಾಡಿ';

  @override
  String get removePhoto => 'ಫೋಟೋ ತೆಗೆಯಿರಿ';

  @override
  String get customSave => 'ಸೇರಿಸಿ ಮತ್ತು ದಾಖಲಿಸಿ';

  @override
  String get customSaveWish => 'ವಾಚ್‌ಲಿಸ್ಟ್‌ಗೆ ಸೇರಿಸಿ';

  @override
  String get required => 'ಕಡ್ಡಾಯ';

  @override
  String yearInvalid(int max) {
    return '1900 ರಿಂದ $max ರವರೆಗಿನ ವರ್ಷ ನಮೂದಿಸಿ';
  }

  @override
  String get statsTitle => 'ಅಂಕಿಅಂಶ';

  @override
  String get scopeMonth => 'ತಿಂಗಳು';

  @override
  String get scopeYear => 'ವರ್ಷ';

  @override
  String get scopeAll => 'ಎಲ್ಲಾ ಸಮಯ';

  @override
  String get totalStubs => 'ಟಿಕೆಟ್‌ಗಳು';

  @override
  String get totalTime => 'ನೋಡಿದ ಸಮಯ';

  @override
  String get spent => 'ಟಿಕೆಟ್‌ಗಳಿಗೆ ಖರ್ಚು';

  @override
  String avgTicket(String amount) {
    return 'ಸರಾಸರಿ ಒಂದು ಟಿಕೆಟ್‌ಗೆ $amount';
  }

  @override
  String get fdfsCount => 'FDFS';

  @override
  String get rewatches => 'ಮತ್ತೆ ನೋಡಿದ್ದು';

  @override
  String get avgRating => 'ಸರಾಸರಿ ರೇಟಿಂಗ್';

  @override
  String get byDay => 'ದಿನದ ಪ್ರಕಾರ';

  @override
  String get byMonth => 'ತಿಂಗಳ ಪ್ರಕಾರ';

  @override
  String get byYear => 'ವರ್ಷದ ಪ್ರಕಾರ';

  @override
  String get byStars => 'ರೇಟಿಂಗ್‌ಗಳು';

  @override
  String get byPlace => 'ಸ್ಥಳಗಳು';

  @override
  String get byVenueType => 'ನೀವು ಎಲ್ಲಿ ನೋಡುತ್ತೀರಿ';

  @override
  String get byGenre => 'ಶೈಲಿಗಳು';

  @override
  String get byLanguage => 'ಭಾಷೆಗಳು';

  @override
  String get byCountry => 'ದೇಶಗಳು';

  @override
  String get byDecade => 'ದಶಕಗಳು';

  @override
  String get byDirector => 'ನೀವು ಹೆಚ್ಚು ನೋಡುವ ನಿರ್ದೇಶಕರು';

  @override
  String get byActor => 'ನೀವು ಹೆಚ್ಚು ನೋಡುವ ನಟರು';

  @override
  String get byTag => 'ಟ್ಯಾಗ್‌ಗಳು';

  @override
  String get byFormat => 'ಫಾರ್ಮ್ಯಾಟ್‌ಗಳು';

  @override
  String get byShow => 'ಶೋ ಸಮಯ';

  @override
  String get statsEmpty => 'ಈ ಅವಧಿಯಲ್ಲಿ ಟಿಕೆಟ್ ಇಲ್ಲ.';

  @override
  String get tapForDetail => 'ಸಿನಿಮಾಗಳನ್ನು ನೋಡಲು ಒಂದು ಬಾರ್ ಒತ್ತಿ.';

  @override
  String showMore(int count) {
    return 'ಎಲ್ಲಾ $count ತೋರಿಸಿ';
  }

  @override
  String get showLess => 'ಕಡಿಮೆ ತೋರಿಸಿ';

  @override
  String get unrated => 'ರೇಟಿಂಗ್ ಇಲ್ಲ';

  @override
  String decadeLabel(String decade) {
    return '$decadeರ ದಶಕ';
  }

  @override
  String get shareTitle => 'ಇಮೇಜ್ ಹಂಚಿಕೊಳ್ಳಿ';

  @override
  String get background => 'ಹಿನ್ನೆಲೆ';

  @override
  String get showTitles => 'ಹೆಸರುಗಳು';

  @override
  String get showDates => 'ದಿನಾಂಕಗಳು';

  @override
  String get showRatings => 'ರೇಟಿಂಗ್‌ಗಳು';

  @override
  String get shareMonth => 'ಈ ತಿಂಗಳನ್ನು ಹಂಚಿಕೊಳ್ಳಿ';

  @override
  String monthAtMovies(String month) {
    return '$month ರ ಸಿನಿಮಾಗಳು';
  }

  @override
  String get nothingToShare => 'ಈ ತಿಂಗಳು ಇನ್ನೂ ಟಿಕೆಟ್ ಇಲ್ಲ.';

  @override
  String get settingsTitle => 'ಸೆಟ್ಟಿಂಗ್‌ಗಳು';

  @override
  String get appearance => 'ನೋಟ';

  @override
  String get theme => 'ಥೀಮ್';

  @override
  String get themeSystem => 'ಸಿಸ್ಟಮ್';

  @override
  String get themeLight => 'ಲೈಟ್';

  @override
  String get themeDark => 'ಡಾರ್ಕ್';

  @override
  String get accentColor => 'ಮುದ್ರೆಯ ಶಾಯಿ';

  @override
  String get accent_sindoor => 'ಕುಂಕುಮ';

  @override
  String get accent_marigold => 'ಚೆಂಡು ಹೂ';

  @override
  String get accent_peacock => 'ನವಿಲು';

  @override
  String get accent_mehendi => 'ಗೋರಂಟಿ';

  @override
  String get accent_neel => 'ನೀಲಿ';

  @override
  String get accent_jamun => 'ನೇರಳೆ';

  @override
  String get accent_gulabi => 'ಗುಲಾಬಿ';

  @override
  String get accent_kesar => 'ಕೇಸರಿ';

  @override
  String get accent_paan => 'ವೀಳ್ಯದೆಲೆ';

  @override
  String get accent_chai => 'ಚಹಾ';

  @override
  String get accent_kajal => 'ಕಾಡಿಗೆ';

  @override
  String get appIcon => 'ಆ್ಯಪ್ ಐಕಾನ್';

  @override
  String get icon_default => 'ಗುಲಾಬಿ ಟಿಕೆಟ್';

  @override
  String get icon_yellow => 'ಹಳದಿ ಟಿಕೆಟ್';

  @override
  String get icon_green => 'ಹಸಿರು ಟಿಕೆಟ್';

  @override
  String get icon_blue => 'ನೀಲಿ ಟಿಕೆಟ್';

  @override
  String get icon_night => 'ನೈಟ್ ಶೋ';

  @override
  String get iconChanged => 'ಆ್ಯಪ್ ಐಕಾನ್ ಬದಲಾಗಿದೆ';

  @override
  String get iconFailed => 'ಈ ಸಾಧನದಲ್ಲಿ ಐಕಾನ್ ಬದಲಾಗಲಿಲ್ಲ.';

  @override
  String get appLanguage => 'ಆ್ಯಪ್ ಭಾಷೆ';

  @override
  String get languageSystem => 'ಸಾಧನದ ಭಾಷೆ';

  @override
  String get calendarSection => 'ಕ್ಯಾಲೆಂಡರ್';

  @override
  String get weekStart => 'ವಾರ ಆರಂಭವಾಗುವ ದಿನ';

  @override
  String get sunday => 'ಭಾನುವಾರ';

  @override
  String get monday => 'ಸೋಮವಾರ';

  @override
  String get ratingsSection => 'ರೇಟಿಂಗ್';

  @override
  String get showRatingsToggle => 'ಸ್ಟಾರ್ ರೇಟಿಂಗ್ ತೋರಿಸಿ';

  @override
  String get releaseLists => 'ಹೊಸ ಮತ್ತು ಮುಂಬರುವ ಪಟ್ಟಿಗಳು';

  @override
  String get releasesIndia => 'ಭಾರತೀಯ ಸಿನಿಮಾಗಳು';

  @override
  String get releasesWorld => 'ಎಲ್ಲಾ ಸಿನಿಮಾಗಳು';

  @override
  String get manageTags => 'ಟ್ಯಾಗ್‌ಗಳು';

  @override
  String get manageVenues => 'ಸ್ಥಳಗಳು';

  @override
  String get dataSection => 'ನಿಮ್ಮ ಡೇಟಾ';

  @override
  String get exportCsv => 'CSV ಎಕ್ಸ್‌ಪೋರ್ಟ್ ಮಾಡಿ';

  @override
  String get importCsv => 'CSV ಇಂಪೋರ್ಟ್ ಮಾಡಿ';

  @override
  String get importHint => 'Talkies ಅಥವಾ Letterboxd CSV ಫೈಲ್';

  @override
  String get backup => 'ಎಲ್ಲವನ್ನೂ ಬ್ಯಾಕಪ್ ಮಾಡಿ';

  @override
  String get backupHint => 'ಒಂದೇ JSON ಫೈಲ್. ಅದನ್ನು Drive ನಲ್ಲಿ ಇಡಿ ಅಥವಾ ನಿಮಗೇ ಕಳುಹಿಸಿಕೊಳ್ಳಿ.';

  @override
  String get restore => 'ಬ್ಯಾಕಪ್ ಮರುಸ್ಥಾಪಿಸಿ';

  @override
  String get batchAdd => 'ಒಟ್ಟಿಗೆ ಸೇರಿಸಿ';

  @override
  String get batchAddHint => 'ಹೆಸರುಗಳ ಪಟ್ಟಿಯನ್ನು ಪೇಸ್ಟ್ ಮಾಡಿ';

  @override
  String get refreshCatalog => 'ಸಿನಿಮಾ ಪಟ್ಟಿ ರಿಫ್ರೆಶ್ ಮಾಡಿ';

  @override
  String refreshedOn(String date, String updated) {
    return '$date ರಂದು ರಚಿಸಲಾಗಿದೆ. $updated ರಂದು ಅಪ್‌ಡೇಟ್ ಆಗಿದೆ.';
  }

  @override
  String builtOn(String date) {
    return '$date ರಂದು ರಚಿಸಲಾಗಿದೆ. ಇನ್ನೂ ರಿಫ್ರೆಶ್ ಆಗಿಲ್ಲ.';
  }

  @override
  String refreshDone(int count) {
    return '$count ಇತ್ತೀಚಿನ ಮತ್ತು ಮುಂಬರುವ ಸಿನಿಮಾಗಳು ಅಪ್‌ಡೇಟ್ ಆಗಿವೆ';
  }

  @override
  String get refreshFailed => 'ರಿಫ್ರೆಶ್ ಆಗಲಿಲ್ಲ. ಇಂಟರ್ನೆಟ್ ಪರಿಶೀಲಿಸಿ.';

  @override
  String get about => 'ಮಾಹಿತಿ';

  @override
  String get aboutBody =>
      'ಟಾಕೀಸ್ ಭಾರತೀಯ ಸಿನಿಮಾ ಪ್ರೇಮಿಗಳ ಟಿಕೆಟ್ ಡೈರಿ. ನಿಮ್ಮ ಟಿಕೆಟ್‌ಗಳು ಈ ಫೋನ್‌ನಲ್ಲೇ ಇರುತ್ತವೆ. ಸಿನಿಮಾ ವಿವರಗಳು Wikidata (CC0) ದಿಂದ ಮತ್ತು ಪೋಸ್ಟರ್‌ಗಳು Wikipedia ದಿಂದ ಬರುತ್ತವೆ.';

  @override
  String version(String v) {
    return 'ಆವೃತ್ತಿ $v';
  }

  @override
  String get whatsNew => 'ಹೊಸತೇನು';

  @override
  String get privacyPolicy => 'ಗೌಪ್ಯತಾ ನೀತಿ';

  @override
  String get replaceQ => 'ಎಲ್ಲವನ್ನೂ ಈ ಬ್ಯಾಕಪ್‌ನಿಂದ ಬದಲಿಸಬೇಕೇ?';

  @override
  String replaceBody(int count) {
    return 'ನಿಮ್ಮ ಈಗಿನ $count ಟಿಕೆಟ್‌ಗಳ ಬದಲಿಗೆ ಬ್ಯಾಕಪ್ ಬರುತ್ತದೆ.';
  }

  @override
  String get replace => 'ಬದಲಿಸಿ';

  @override
  String get restoreDone => 'ಬ್ಯಾಕಪ್ ಮರುಸ್ಥಾಪಿಸಲಾಗಿದೆ';

  @override
  String get restoreFailed => 'ಇದು ಟಾಕೀಸ್ ಬ್ಯಾಕಪ್ ಅಲ್ಲ.';

  @override
  String imported(int count, int matched, int custom) {
    return '$count ಟಿಕೆಟ್‌ಗಳು ಸೇರಿವೆ. $matched ಸಿನಿಮಾ ಪಟ್ಟಿಗೆ ಹೊಂದಿಕೆಯಾದವು, $custom ನಿಮ್ಮದೇ ಸಿನಿಮಾಗಳಾಗಿ ಸೇರಿವೆ.';
  }

  @override
  String get importNothing => 'ಈ ಫೈಲ್‌ನಲ್ಲಿ ಯಾವ ಸಾಲೂ ಸಿಗಲಿಲ್ಲ.';

  @override
  String get nothingToExport => 'ಎಕ್ಸ್‌ಪೋರ್ಟ್ ಮಾಡಲು ಇನ್ನೂ ಟಿಕೆಟ್ ಇಲ್ಲ.';

  @override
  String get tagsEmpty => 'ಇನ್ನೂ ಟ್ಯಾಗ್ ಇಲ್ಲ. ಇಲ್ಲಿ ಅಥವಾ ಸಿನಿಮಾ ದಾಖಲಿಸುವಾಗ ಸೇರಿಸಿ.';

  @override
  String get renameTag => 'ಟ್ಯಾಗ್ ಹೆಸರು ಬದಲಿಸಿ';

  @override
  String deleteTagQ(String tag, int count) {
    return '#$tag ಅಳಿಸಬೇಕೇ? ಇದು $count ಟಿಕೆಟ್‌ಗಳಿಂದ ತೆಗೆಯಲ್ಪಡುತ್ತದೆ.';
  }

  @override
  String get editVenue => 'ಸ್ಥಳ ಬದಲಿಸಿ';

  @override
  String deleteVenueQ(String name) {
    return '$name ಅನ್ನು ಪಟ್ಟಿಯಿಂದ ತೆಗೆಯಬೇಕೇ? ಟಿಕೆಟ್‌ಗಳಲ್ಲಿ ಹೆಸರು ಉಳಿಯುತ್ತದೆ.';
  }

  @override
  String get remove => 'ತೆಗೆಯಿರಿ';

  @override
  String stubsUsing(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ಟಿಕೆಟ್‌ಗಳಲ್ಲಿ ಬಳಸಲಾಗಿದೆ',
      one: '1 ಟಿಕೆಟ್‌ನಲ್ಲಿ ಬಳಸಲಾಗಿದೆ',
      zero: 'ಬಳಸಿಲ್ಲ',
    );
    return '$_temp0';
  }

  @override
  String get batchTitle => 'ಒಟ್ಟಿಗೆ ಸೇರಿಸಿ';

  @override
  String get batchHint => 'ಪ್ರತಿ ಸಾಲಿಗೆ ಒಂದು ಹೆಸರು. ಸರಿಯಾಗಿ ಹೊಂದಲು ವರ್ಷವನ್ನೂ ಬರೆಯಿರಿ.';

  @override
  String get batchExample => 'Sholay 1975\nRRR (2022)\nPanchayat';

  @override
  String get batchMatch => 'ಹೆಸರುಗಳನ್ನು ಹೊಂದಿಸಿ';

  @override
  String batchAddAll(int count) {
    return '$count ಟಿಕೆಟ್‌ಗಳನ್ನು ಸೇರಿಸಿ';
  }

  @override
  String get batchOwn => 'ಹೊಂದಿಕೆ ಸಿಗಲಿಲ್ಲ. ನಿಮ್ಮದೇ ಸಿನಿಮಾವಾಗಿ ಸೇರುತ್ತದೆ.';

  @override
  String get batchDefaults => 'ಪ್ರತಿ ಸಿನಿಮಾಗೆ';

  @override
  String batchDone(int count) {
    return '$count ಟಿಕೆಟ್‌ಗಳು ಸೇರಿವೆ';
  }

  @override
  String whatsNewTitle(String v) {
    return 'ಟಾಕೀಸ್ $v';
  }

  @override
  String get whatsNew1 =>
      'ಎಲ್ಲಾ ಪ್ರೀಮಿಯಂ ಫೀಚರ್‌ಗಳು ಉಚಿತ: ಎಲ್ಲಾ ಸಮಯದ ಅಂಕಿಅಂಶ, ಅನಿಯಮಿತ ಟ್ಯಾಗ್‌ಗಳು, 11 ಮುದ್ರೆ ಶಾಯಿಗಳು, ಡಾರ್ಕ್ ಮೋಡ್, ಆ್ಯಪ್ ಐಕಾನ್‌ಗಳು, ಶೇರ್ ಹಿನ್ನೆಲೆಗಳು ಮತ್ತು CSV ಎಕ್ಸ್‌ಪೋರ್ಟ್.';

  @override
  String get whatsNew2 => 'ಹಾಲ್ ವಿವರಗಳನ್ನು ದಾಖಲಿಸಿ: ಶೋ, ಕ್ಲಾಸ್, ಸೀಟ್, ಫಾರ್ಮ್ಯಾಟ್, ಟಿಕೆಟ್ ಬೆಲೆ ಮತ್ತು ಮೊದಲ ದಿನ ಮೊದಲ ಶೋ.';

  @override
  String get whatsNew3 =>
      '34,000 ಭಾರತೀಯ ಮತ್ತು ವಿದೇಶಿ ಟೈಟಲ್‌ಗಳು ಆಫ್‌ಲೈನ್‌ನಲ್ಲಿ ಕೆಲಸ ಮಾಡುತ್ತವೆ. ಆನ್‌ಲೈನ್ ಇರುವಾಗ ಹೊಸ ಬಿಡುಗಡೆಗಳು ರಿಫ್ರೆಶ್ ಆಗುತ್ತವೆ.';

  @override
  String get gotIt => 'ಸರಿ';
}
