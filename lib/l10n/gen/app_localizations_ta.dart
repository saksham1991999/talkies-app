// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Tamil (`ta`).
class AppLocalizationsTa extends AppLocalizations {
  AppLocalizationsTa([String locale = 'ta']) : super(locale);

  @override
  String get appName => 'டாக்கீஸ்';

  @override
  String get tabHome => 'முகப்பு';

  @override
  String get tabStubs => 'டிக்கெட்டுகள்';

  @override
  String get tabCalendar => 'காலண்டர்';

  @override
  String get tabFilms => 'படங்கள்';

  @override
  String get tabStats => 'புள்ளிவிவரம்';

  @override
  String get recordFilm => 'படத்தைப் பதிவு செய்';

  @override
  String get search => 'தேடு';

  @override
  String get cancel => 'ரத்துசெய்';

  @override
  String get save => 'சேமி';

  @override
  String get delete => 'நீக்கு';

  @override
  String get edit => 'திருத்து';

  @override
  String get done => 'முடிந்தது';

  @override
  String get undo => 'செயல்தவிர்';

  @override
  String get share => 'பகிர்';

  @override
  String get back => 'பின்செல்';

  @override
  String get clear => 'அழி';

  @override
  String get settings => 'அமைப்புகள்';

  @override
  String get previous => 'முந்தையது';

  @override
  String get next => 'அடுத்தது';

  @override
  String unitFilms(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: 'படங்கள்', one: 'படம்');
    return '$_temp0';
  }

  @override
  String get thisYear => 'இந்த ஆண்டு';

  @override
  String get recent => 'சமீபத்தியவை';

  @override
  String get allStubs => 'எல்லா டிக்கெட்டுகளும்';

  @override
  String get newReleases => 'புதிய ரிலீஸ்கள்';

  @override
  String get comingSoon => 'விரைவில் வருபவை';

  @override
  String get forYou => 'உங்களுக்காக';

  @override
  String becauseYouLiked(String title) {
    return '$title உங்களுக்குப் பிடித்ததால்';
  }

  @override
  String get notInterested => 'ஆர்வமில்லை';

  @override
  String get hiddenFromRecs => 'பரிந்துரைகளிலிருந்து மறைக்கப்பட்டது';

  @override
  String get seeAll => 'எல்லாம் பார்';

  @override
  String get emptyHome => 'உங்கள் முதல் டிக்கெட்டுக்கு ஒரு படம் போதும். + பட்டனைத் தட்டி, படத்தின் பெயரைத் தேடுங்கள்.';

  @override
  String get venueCinema => 'தியேட்டர்';

  @override
  String get venueOtt => 'ஸ்ட்ரீமிங்';

  @override
  String get venueHome => 'வீடு';

  @override
  String get venueTv => 'டிவி';

  @override
  String get venueOther => 'மற்றவை';

  @override
  String get splitLegend => 'இந்த ஆண்டு நீங்கள் எங்கே பார்த்தீர்கள்';

  @override
  String ticketsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count டிக்கெட்டுகள்',
      one: '1 டிக்கெட்',
      zero: 'டிக்கெட் இல்லை',
    );
    return '$_temp0';
  }

  @override
  String get sortNewest => 'புதியவை முதலில்';

  @override
  String get sortOldest => 'பழையவை முதலில்';

  @override
  String get sortRatingHigh => 'அதிக ரேட்டிங்';

  @override
  String get sortRatingLow => 'குறைந்த ரேட்டிங்';

  @override
  String get sort => 'வரிசை';

  @override
  String get filter => 'ஃபில்டர்';

  @override
  String get filterAll => 'எல்லாம்';

  @override
  String get filterPlace => 'இடம்';

  @override
  String get filterTag => 'டேக்';

  @override
  String get filterYear => 'ஆண்டு';

  @override
  String get filterKind => 'வகை';

  @override
  String get filterRating => 'ரேட்டிங்';

  @override
  String get kindFilm => 'படங்கள்';

  @override
  String get kindSeries => 'சீரிஸ்';

  @override
  String get gridView => 'கிரிட் வியூ';

  @override
  String get listView => 'லிஸ்ட் வியூ';

  @override
  String get searchStubs => 'உங்கள் டிக்கெட்டுகளில் தேடுங்கள்';

  @override
  String get noStubs => 'இன்னும் டிக்கெட் இல்லை. நீங்கள் பதிவு செய்யும் ஒவ்வொரு படமும் இங்கே ஒரு டிக்கெட் ஆகும்.';

  @override
  String get noMatch => 'இந்த ஃபில்டர்களுக்கு எதுவும் பொருந்தவில்லை.';

  @override
  String get resetFilters => 'ஃபில்டர்களை நீக்கு';

  @override
  String starsAtLeast(int stars) {
    return '$stars+ ஸ்டார்';
  }

  @override
  String calWatched(int count) {
    return '$count பார்த்தவை';
  }

  @override
  String calPlanned(int count) {
    return '$count திட்டமிட்டவை';
  }

  @override
  String get showStubs => 'டிக்கெட்டுகள்';

  @override
  String get showWatchlist => 'வாட்ச்லிஸ்ட்';

  @override
  String get dayEmpty => 'இந்த நாளில் எதுவும் இல்லை.';

  @override
  String get recordForDay => 'இந்த நாளில் பார்த்த படத்தைப் பதிவு செய்';

  @override
  String get today => 'இன்று';

  @override
  String get filmsNew => 'புதியவை';

  @override
  String get filmsUpcoming => 'வரவிருப்பவை';

  @override
  String get filmsWant => 'பார்க்க வேண்டியவை';

  @override
  String get filmsRecorded => 'பதிவு செய்தவை';

  @override
  String get filmsReleased => 'ரிலீஸ் ஆனவை';

  @override
  String get allLanguages => 'எல்லாம்';

  @override
  String get wantEmpty =>
      'பார்க்க விரும்பும் படங்களை புக்மார்க் செய்யுங்கள். அவை இங்கேயும் உங்கள் காலண்டரிலும் தெரியும்.';

  @override
  String get recordedEmpty => 'நீங்கள் பதிவு செய்யும் படங்கள் இங்கே தெரியும்.';

  @override
  String get noReleases =>
      'இந்த மொழிக்கு ஆஃப்லைன் பட்டியலில் ரிலீஸ் எதுவும் இல்லை. ஆன்லைனில் இருக்கும்போது படப் பட்டியலைப் புதுப்பியுங்கள்.';

  @override
  String get refreshNow => 'படப் பட்டியலைப் புதுப்பி';

  @override
  String get addedToWatchlist => 'வாட்ச்லிஸ்ட்டில் சேர்க்கப்பட்டது';

  @override
  String get removedFromWatchlist => 'வாட்ச்லிஸ்ட்டிலிருந்து நீக்கப்பட்டது';

  @override
  String watchCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count முறை பார்த்தது',
      one: 'ஒரு முறை பார்த்தது',
    );
    return '$_temp0';
  }

  @override
  String get searchHint => 'படம், சீரிஸ், நடிகர் அல்லது இயக்குநர்';

  @override
  String get searchAll => 'எல்லாம்';

  @override
  String get notFound => 'பட்டியலில் இல்லையா?';

  @override
  String get addManually => 'நீங்களே சேர்க்கவும்';

  @override
  String get loadingCatalog => 'படப் பட்டியல் திறக்கிறது';

  @override
  String get catalogError => 'படப் பட்டியல் திறக்கவில்லை. ஆப்பை மீண்டும் தொடங்குங்கள்.';

  @override
  String searchPrompt(String count) {
    return '$count இந்திய, உலகப் படங்கள், சீரிஸ்களில் தேடுங்கள். ஆஃப்லைனிலும் வேலை செய்யும்.';
  }

  @override
  String noResults(String query) {
    return '“$query” என்ற பெயரில் எதுவும் இல்லை.';
  }

  @override
  String get director => 'இயக்குநர்';

  @override
  String get cast => 'நடிகர்கள்';

  @override
  String get language => 'மொழி';

  @override
  String get country => 'நாடு';

  @override
  String seasons(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count சீசன்கள்', one: '1 சீசன்');
    return '$_temp0';
  }

  @override
  String get availableOn => 'ஸ்ட்ரீமிங் தளம்';

  @override
  String get streamingHint => 'விக்கிபீடியாவிலிருந்து. கிடைப்பது மாறலாம்.';

  @override
  String get synopsis => 'கதைச்சுருக்கம்';

  @override
  String get synopsisOffline => 'கதைச்சுருக்கம் பார்க்க இணைய இணைப்பு தேவை.';

  @override
  String get synopsisNone => 'கதைச்சுருக்கம் கிடைக்கவில்லை.';

  @override
  String get iWatched => 'நான் பார்த்தேன்';

  @override
  String get watchedAgain => 'மீண்டும் பார்த்தேன்';

  @override
  String get wantToWatch => 'பார்க்க வேண்டும்';

  @override
  String get inWatchlist => 'வாட்ச்லிஸ்ட்டில் உள்ளது';

  @override
  String plannedFor(String date) {
    return '$date அன்று பார்க்கத் திட்டம்';
  }

  @override
  String get setPlannedDate => 'தேதியைத் திட்டமிடு';

  @override
  String get clearDate => 'தேதியை நீக்கு';

  @override
  String get yourStubs => 'உங்கள் டிக்கெட்டுகள்';

  @override
  String get openWikipedia => 'Wikipedia-வில் படிக்கவும்';

  @override
  String get fixOnWikidata => 'இந்த விவரங்களைத் திருத்து';

  @override
  String get fixHint => 'பட விவரங்கள் Wikidata-விலிருந்து வருகின்றன. அங்கே யார் வேண்டுமானாலும் அவற்றைத் திருத்தலாம்.';

  @override
  String get yourOwnFilm => 'நீங்கள் சேர்த்தது';

  @override
  String watchNth(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$nவது முறை',
      two: 'இரண்டாவது முறை',
      one: 'முதல் முறை',
    );
    return '$_temp0';
  }

  @override
  String hoursMinutes(int h, int m) {
    return '$h மணி $m நிமி';
  }

  @override
  String minutesOnly(int m) {
    return '$m நிமிடம்';
  }

  @override
  String ticketNo(String no) {
    return 'எண் $no';
  }

  @override
  String get ticket => 'டிக்கெட்';

  @override
  String get admitOne => 'ADMIT ONE';

  @override
  String get stampWatched => 'WATCHED';

  @override
  String get fdfs => 'FDFS';

  @override
  String get labelDate => 'தேதி';

  @override
  String get labelPlace => 'இடம்';

  @override
  String get labelShow => 'ஷோ';

  @override
  String get labelClass => 'கிளாஸ்';

  @override
  String get labelSeat => 'சீட்';

  @override
  String get labelPrice => 'விலை';

  @override
  String get labelFormat => 'ஃபார்மேட்';

  @override
  String get labelLang => 'பார்த்த மொழி';

  @override
  String get labelWith => 'யாருடன்';

  @override
  String get labelRating => 'ரேட்டிங்';

  @override
  String get labelTags => 'டேக்குகள்';

  @override
  String get labelMemo => 'குறிப்புகள்';

  @override
  String get dateUnknown => 'தேதி நினைவில்லை';

  @override
  String get noRating => 'ரேட்டிங் இல்லை';

  @override
  String get tearUpQ => 'இந்த டிக்கெட்டைக் கிழிக்கவா?';

  @override
  String get tearUpBody => 'இந்த முறை பார்த்ததன் பதிவு நீக்கப்படும்.';

  @override
  String get tearUp => 'கிழி';

  @override
  String get stubDeleted => 'டிக்கெட் கிழிக்கப்பட்டது';

  @override
  String get shareTicket => 'டிக்கெட்டைப் பகிர்';

  @override
  String get recordTitle => 'புதிய டிக்கெட்';

  @override
  String get editTitle => 'டிக்கெட்டைத் திருத்து';

  @override
  String get whenWatched => 'எப்போது பார்த்தீர்கள்?';

  @override
  String get precisionDay => 'நாள்';

  @override
  String get precisionMonth => 'மாதம்';

  @override
  String get precisionYear => 'ஆண்டு';

  @override
  String get precisionNone => 'நினைவில்லை';

  @override
  String get yesterday => 'நேற்று';

  @override
  String get wherePlace => 'எங்கே?';

  @override
  String get addPlace => 'புதிய இடம்';

  @override
  String get placeName => 'இடத்தின் பெயர்';

  @override
  String get placeNameHint => 'PVR சத்யம், கமலா சினிமாஸ், Netflix';

  @override
  String get placeType => 'வகை';

  @override
  String get hallDetails => 'தியேட்டர் விவரங்கள்';

  @override
  String get show => 'ஷோ';

  @override
  String get format => 'ஃபார்மேட்';

  @override
  String get seatClass => 'கிளாஸ்';

  @override
  String get seat => 'சீட்';

  @override
  String get seatHint => 'H12';

  @override
  String get price => 'டிக்கெட் விலை (₹)';

  @override
  String get priceHint => '250';

  @override
  String get fdfsToggle => 'முதல் நாள், முதல் ஷோ';

  @override
  String get watchedIn => 'பார்த்த மொழி';

  @override
  String get originalLang => 'அசல்';

  @override
  String get withWhom => 'யாருடன் பார்த்தீர்கள்';

  @override
  String get withHint => 'நண்பர்கள், குடும்பம், தனியாக';

  @override
  String get rating => 'ரேட்டிங்';

  @override
  String get tags => 'டேக்குகள்';

  @override
  String get addTag => 'புதிய டேக்';

  @override
  String get tagHint => 'பிடித்தது';

  @override
  String get memo => 'குறிப்புகள்';

  @override
  String get memoHint => 'எது மனதில் நின்றது?';

  @override
  String get stampIt => 'முத்திரை இடு';

  @override
  String get saveChanges => 'மாற்றங்களைச் சேமி';

  @override
  String get discardQ => 'இந்த டிக்கெட்டைக் கைவிடவா?';

  @override
  String get discard => 'கைவிடு';

  @override
  String get keepEditing => 'தொடர்ந்து திருத்து';

  @override
  String get customTitle => 'படத்தை நீங்களே சேர்க்கவும்';

  @override
  String get customName => 'பெயர்';

  @override
  String get customYear => 'ஆண்டு';

  @override
  String get customLang => 'மொழி';

  @override
  String get customSeries => 'இது ஒரு சீரிஸ்';

  @override
  String get customPoster => 'போஸ்டர்';

  @override
  String get choosePhoto => 'போட்டோவைத் தேர்ந்தெடு';

  @override
  String get removePhoto => 'போட்டோவை நீக்கு';

  @override
  String get customSave => 'சேர்த்துப் பதிவு செய்';

  @override
  String get customSaveWish => 'வாட்ச்லிஸ்ட்டில் சேர்';

  @override
  String get required => 'அவசியம்';

  @override
  String yearInvalid(int max) {
    return '1900 முதல் $max வரையிலான ஆண்டை உள்ளிடுங்கள்';
  }

  @override
  String get statsTitle => 'புள்ளிவிவரம்';

  @override
  String get scopeMonth => 'மாதம்';

  @override
  String get scopeYear => 'ஆண்டு';

  @override
  String get scopeAll => 'மொத்தம்';

  @override
  String get totalStubs => 'டிக்கெட்டுகள்';

  @override
  String get totalTime => 'பார்த்த நேரம்';

  @override
  String get spent => 'டிக்கெட்டுகளுக்குச் செலவு';

  @override
  String avgTicket(String amount) {
    return 'சராசரியாக ஒரு டிக்கெட்டுக்கு $amount';
  }

  @override
  String get fdfsCount => 'FDFS';

  @override
  String get rewatches => 'மீண்டும் பார்த்தவை';

  @override
  String get avgRating => 'சராசரி ரேட்டிங்';

  @override
  String get byDay => 'நாள் வாரியாக';

  @override
  String get byMonth => 'மாதம் வாரியாக';

  @override
  String get byYear => 'ஆண்டு வாரியாக';

  @override
  String get byStars => 'ரேட்டிங்குகள்';

  @override
  String get byPlace => 'இடங்கள்';

  @override
  String get byVenueType => 'நீங்கள் எங்கே பார்க்கிறீர்கள்';

  @override
  String get byGenre => 'ஜானர்கள்';

  @override
  String get byLanguage => 'மொழிகள்';

  @override
  String get byCountry => 'நாடுகள்';

  @override
  String get byDecade => 'பத்தாண்டுகள்';

  @override
  String get byDirector => 'நீங்கள் அதிகம் பார்க்கும் இயக்குநர்கள்';

  @override
  String get byActor => 'நீங்கள் அதிகம் பார்க்கும் நடிகர்கள்';

  @override
  String get byTag => 'டேக்குகள்';

  @override
  String get byFormat => 'ஃபார்மேட்டுகள்';

  @override
  String get byShow => 'ஷோ நேரங்கள்';

  @override
  String get statsEmpty => 'இந்தக் காலத்தில் டிக்கெட் எதுவும் இல்லை.';

  @override
  String get tapForDetail => 'ஒரு பாரைத் தட்டி அதன் படங்களைப் பாருங்கள்.';

  @override
  String showMore(int count) {
    return '$count அனைத்தையும் காட்டு';
  }

  @override
  String get showLess => 'குறைவாகக் காட்டு';

  @override
  String get unrated => 'ரேட்டிங் இல்லை';

  @override
  String decadeLabel(String decade) {
    return '$decadeகள்';
  }

  @override
  String get shareTitle => 'இமேஜைப் பகிர்';

  @override
  String get background => 'பின்னணி';

  @override
  String get showTitles => 'பெயர்கள்';

  @override
  String get showDates => 'தேதிகள்';

  @override
  String get showRatings => 'ரேட்டிங்குகள்';

  @override
  String get shareMonth => 'இந்த மாதத்தைப் பகிர்';

  @override
  String monthAtMovies(String month) {
    return '$month-இல் பார்த்த படங்கள்';
  }

  @override
  String get nothingToShare => 'இந்த மாதம் இன்னும் டிக்கெட் இல்லை.';

  @override
  String get settingsTitle => 'அமைப்புகள்';

  @override
  String get appearance => 'தோற்றம்';

  @override
  String get theme => 'தீம்';

  @override
  String get themeSystem => 'சிஸ்டம்';

  @override
  String get themeLight => 'லைட்';

  @override
  String get themeDark => 'டார்க்';

  @override
  String get accentColor => 'முத்திரை மை';

  @override
  String get accent_sindoor => 'செந்தூரம்';

  @override
  String get accent_marigold => 'சாமந்தி';

  @override
  String get accent_peacock => 'மயில்';

  @override
  String get accent_mehendi => 'மருதாணி';

  @override
  String get accent_neel => 'நீலம்';

  @override
  String get accent_jamun => 'நாவல்';

  @override
  String get accent_gulabi => 'ரோஜா';

  @override
  String get accent_kesar => 'குங்குமப்பூ';

  @override
  String get accent_paan => 'வெற்றிலை';

  @override
  String get accent_chai => 'டீ';

  @override
  String get accent_kajal => 'கண்மை';

  @override
  String get appIcon => 'ஆப் ஐகான்';

  @override
  String get icon_default => 'இளஞ்சிவப்பு டிக்கெட்';

  @override
  String get icon_yellow => 'மஞ்சள் டிக்கெட்';

  @override
  String get icon_green => 'பச்சை டிக்கெட்';

  @override
  String get icon_blue => 'நீல டிக்கெட்';

  @override
  String get icon_night => 'நைட் ஷோ';

  @override
  String get iconChanged => 'ஆப் ஐகான் மாற்றப்பட்டது';

  @override
  String get iconFailed => 'இந்தச் சாதனத்தில் ஐகான் மாறவில்லை.';

  @override
  String get appLanguage => 'ஆப் மொழி';

  @override
  String get languageSystem => 'சாதன மொழி';

  @override
  String get calendarSection => 'காலண்டர்';

  @override
  String get weekStart => 'வாரம் தொடங்கும் நாள்';

  @override
  String get sunday => 'ஞாயிறு';

  @override
  String get monday => 'திங்கள்';

  @override
  String get ratingsSection => 'ரேட்டிங்குகள்';

  @override
  String get showRatingsToggle => 'ஸ்டார் ரேட்டிங்கைக் காட்டு';

  @override
  String get releaseLists => 'புதிய மற்றும் வரவிருக்கும் பட்டியல்கள்';

  @override
  String get releasesIndia => 'இந்தியப் படங்கள்';

  @override
  String get releasesWorld => 'எல்லாப் படங்களும்';

  @override
  String get manageTags => 'டேக்குகள்';

  @override
  String get manageVenues => 'இடங்கள்';

  @override
  String get dataSection => 'உங்கள் டேட்டா';

  @override
  String get exportCsv => 'CSV எக்ஸ்போர்ட் செய்';

  @override
  String get importCsv => 'CSV இம்போர்ட் செய்';

  @override
  String get importHint => 'Talkies அல்லது Letterboxd CSV ஃபைல்';

  @override
  String get backup => 'எல்லாவற்றையும் பேக்கப் எடு';

  @override
  String get backupHint => 'ஒரு JSON ஃபைல். அதை Drive-இல் வையுங்கள் அல்லது உங்களுக்கே அனுப்புங்கள்.';

  @override
  String get restore => 'பேக்கப்பிலிருந்து மீட்டெடு';

  @override
  String get batchAdd => 'விரைவாகச் சேர்';

  @override
  String get batchAddHint => 'படப் பெயர்களின் பட்டியலை பேஸ்ட் செய்யுங்கள்';

  @override
  String get refreshCatalog => 'படப் பட்டியலைப் புதுப்பி';

  @override
  String refreshedOn(String date, String updated) {
    return '$date அன்று உருவானது. $updated அன்று புதுப்பிக்கப்பட்டது.';
  }

  @override
  String builtOn(String date) {
    return '$date அன்று உருவானது. இன்னும் புதுப்பிக்கவில்லை.';
  }

  @override
  String refreshDone(int count) {
    return '$count சமீபத்திய, வரவிருக்கும் படங்கள் புதுப்பிக்கப்பட்டன';
  }

  @override
  String get refreshFailed => 'புதுப்பிக்க முடியவில்லை. இணைப்பைச் சரிபாருங்கள்.';

  @override
  String get about => 'ஆப் பற்றி';

  @override
  String get aboutBody =>
      'டாக்கீஸ் இந்திய சினிமா ரசிகர்களுக்கான டிக்கெட் டைரி. உங்கள் டிக்கெட்டுகள் இந்த போனிலேயே இருக்கும். பட விவரங்கள் Wikidata (CC0)-இலிருந்தும், போஸ்டர்கள் Wikipedia-விலிருந்தும் வருகின்றன.';

  @override
  String version(String v) {
    return 'பதிப்பு $v';
  }

  @override
  String get whatsNew => 'புதிதாக என்ன';

  @override
  String get privacyPolicy => 'தனியுரிமைக் கொள்கை';

  @override
  String get replaceQ => 'எல்லாவற்றையும் இந்த பேக்கப்பால் மாற்றவா?';

  @override
  String replaceBody(int count) {
    return 'உங்கள் தற்போதைய $count டிக்கெட்டுகளுக்குப் பதிலாக பேக்கப் வரும்.';
  }

  @override
  String get replace => 'மாற்று';

  @override
  String get restoreDone => 'பேக்கப் மீட்டெடுக்கப்பட்டது';

  @override
  String get restoreFailed => 'இது டாக்கீஸ் பேக்கப் இல்லை.';

  @override
  String imported(int count, int matched, int custom) {
    return '$count டிக்கெட்டுகள் சேர்க்கப்பட்டன. $matched படப் பட்டியலுடன் பொருந்தின, $custom உங்கள் சொந்தப் படங்களாகச் சேர்க்கப்பட்டன.';
  }

  @override
  String get importNothing => 'இந்த ஃபைலில் வரிகள் எதுவும் இல்லை.';

  @override
  String get nothingToExport => 'எக்ஸ்போர்ட் செய்ய இன்னும் டிக்கெட் இல்லை.';

  @override
  String get tagsEmpty => 'இன்னும் டேக் இல்லை. இங்கே அல்லது படத்தைப் பதிவு செய்யும்போது சேர்க்கலாம்.';

  @override
  String get renameTag => 'டேக்கின் பெயரை மாற்று';

  @override
  String deleteTagQ(String tag, int count) {
    return '#$tag டேக்கை நீக்கவா? இது $count டிக்கெட்டுகளிலிருந்து நீக்கப்படும்.';
  }

  @override
  String get editVenue => 'இடத்தைத் திருத்து';

  @override
  String deleteVenueQ(String name) {
    return '$name இடத்தைப் பட்டியலிலிருந்து நீக்கவா? டிக்கெட்டுகளில் பெயர் அப்படியே இருக்கும்.';
  }

  @override
  String get remove => 'நீக்கு';

  @override
  String stubsUsing(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count டிக்கெட்டுகளில் உள்ளது',
      one: '1 டிக்கெட்டில் உள்ளது',
      zero: 'பயன்பாட்டில் இல்லை',
    );
    return '$_temp0';
  }

  @override
  String get batchTitle => 'விரைவாகச் சேர்';

  @override
  String get batchHint => 'ஒரு வரியில் ஒரு பெயர். சரியாகப் பொருந்த ஆண்டையும் சேர்க்கவும்.';

  @override
  String get batchExample => 'Sholay 1975\nRRR (2022)\nPanchayat';

  @override
  String get batchMatch => 'பெயர்களைப் பொருத்து';

  @override
  String batchAddAll(int count) {
    return '$count டிக்கெட்டுகளைச் சேர்';
  }

  @override
  String get batchOwn => 'பொருந்தவில்லை. உங்கள் சொந்தப் படமாகச் சேர்க்கப்படும்.';

  @override
  String get batchDefaults => 'எல்லாப் படங்களுக்கும்';

  @override
  String batchDone(int count) {
    return '$count டிக்கெட்டுகள் சேர்க்கப்பட்டன';
  }

  @override
  String whatsNewTitle(String v) {
    return 'டாக்கீஸ் $v';
  }

  @override
  String get whatsNew1 =>
      'எல்லா பிரீமியம் வசதிகளும் இலவசம்: மொத்தப் புள்ளிவிவரம், வரம்பற்ற டேக்குகள், 11 முத்திரை மைகள், டார்க் மோட், ஆப் ஐகான்கள், பகிர்வு பின்னணிகள், CSV எக்ஸ்போர்ட்.';

  @override
  String get whatsNew2 =>
      'தியேட்டர் விவரங்களைப் பதிவு செய்யுங்கள்: ஷோ, கிளாஸ், சீட், ஃபார்மேட், டிக்கெட் விலை, முதல் நாள் முதல் ஷோ.';

  @override
  String get whatsNew3 =>
      '34,000 இந்திய, உலகப் படங்கள், சீரிஸ்கள் ஆஃப்லைனில் கிடைக்கும். ஆன்லைனில் இருக்கும்போது புதிய ரிலீஸ்கள் புதுப்பிக்கப்படும்.';

  @override
  String get gotIt => 'சரி';
}
