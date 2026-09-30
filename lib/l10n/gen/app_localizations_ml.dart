// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Malayalam (`ml`).
class AppLocalizationsMl extends AppLocalizations {
  AppLocalizationsMl([String locale = 'ml']) : super(locale);

  @override
  String get appName => 'ടാക്കീസ്';

  @override
  String get tabHome => 'ഹോം';

  @override
  String get tabStubs => 'ടിക്കറ്റുകൾ';

  @override
  String get tabCalendar => 'കലണ്ടർ';

  @override
  String get tabFilms => 'സിനിമകൾ';

  @override
  String get tabStats => 'കണക്കുകൾ';

  @override
  String get recordFilm => 'സിനിമ രേഖപ്പെടുത്തുക';

  @override
  String get search => 'തിരയുക';

  @override
  String get cancel => 'റദ്ദാക്കുക';

  @override
  String get save => 'സേവ് ചെയ്യുക';

  @override
  String get delete => 'ഇല്ലാതാക്കുക';

  @override
  String get edit => 'എഡിറ്റ് ചെയ്യുക';

  @override
  String get done => 'പൂർത്തിയായി';

  @override
  String get undo => 'പഴയപടിയാക്കുക';

  @override
  String get share => 'ഷെയർ ചെയ്യുക';

  @override
  String get back => 'തിരികെ';

  @override
  String get clear => 'മായ്ക്കുക';

  @override
  String get settings => 'ക്രമീകരണം';

  @override
  String get previous => 'മുമ്പത്തേത്';

  @override
  String get next => 'അടുത്തത്';

  @override
  String unitFilms(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: 'സിനിമകൾ', one: 'സിനിമ');
    return '$_temp0';
  }

  @override
  String get thisYear => 'ഈ വർഷം';

  @override
  String get recent => 'അടുത്തിടെ';

  @override
  String get allStubs => 'എല്ലാ ടിക്കറ്റുകളും';

  @override
  String get newReleases => 'പുതിയ റിലീസുകൾ';

  @override
  String get comingSoon => 'ഉടൻ വരുന്നു';

  @override
  String get seeAll => 'എല്ലാം കാണുക';

  @override
  String get emptyHome => 'നിങ്ങളുടെ ആദ്യ ടിക്കറ്റിന് ഒരു സിനിമ മതി. + അമർത്തി സിനിമയുടെ പേര് തിരയുക.';

  @override
  String get venueCinema => 'തിയേറ്റർ';

  @override
  String get venueOtt => 'സ്ട്രീമിംഗ്';

  @override
  String get venueHome => 'വീട്';

  @override
  String get venueTv => 'ടിവി';

  @override
  String get venueOther => 'മറ്റുള്ളവ';

  @override
  String get splitLegend => 'ഈ വർഷം നിങ്ങൾ എവിടെ കണ്ടു';

  @override
  String ticketsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ടിക്കറ്റുകൾ',
      one: '1 ടിക്കറ്റ്',
      zero: 'ടിക്കറ്റുകളില്ല',
    );
    return '$_temp0';
  }

  @override
  String get sortNewest => 'പുതിയത് ആദ്യം';

  @override
  String get sortOldest => 'പഴയത് ആദ്യം';

  @override
  String get sortRatingHigh => 'ഏറ്റവും ഉയർന്ന റേറ്റിംഗ്';

  @override
  String get sortRatingLow => 'ഏറ്റവും കുറഞ്ഞ റേറ്റിംഗ്';

  @override
  String get sort => 'അടുക്കുക';

  @override
  String get filter => 'ഫിൽട്ടർ';

  @override
  String get filterAll => 'എല്ലാം';

  @override
  String get filterPlace => 'സ്ഥലം';

  @override
  String get filterTag => 'ടാഗ്';

  @override
  String get filterYear => 'വർഷം';

  @override
  String get filterKind => 'തരം';

  @override
  String get filterRating => 'റേറ്റിംഗ്';

  @override
  String get kindFilm => 'സിനിമകൾ';

  @override
  String get kindSeries => 'സീരീസ്';

  @override
  String get gridView => 'ഗ്രിഡ് വ്യൂ';

  @override
  String get listView => 'ലിസ്റ്റ് വ്യൂ';

  @override
  String get searchStubs => 'നിങ്ങളുടെ ടിക്കറ്റുകൾ തിരയുക';

  @override
  String get noStubs => 'ഇതുവരെ ടിക്കറ്റുകളില്ല. നിങ്ങൾ രേഖപ്പെടുത്തുന്ന ഓരോ സിനിമയും ഇവിടെ ഒരു ടിക്കറ്റാകും.';

  @override
  String get noMatch => 'ഈ ഫിൽട്ടറുകൾക്ക് ഒന്നും കിട്ടിയില്ല.';

  @override
  String get resetFilters => 'ഫിൽട്ടറുകൾ നീക്കുക';

  @override
  String starsAtLeast(int stars) {
    return '$stars+ സ്റ്റാർ';
  }

  @override
  String calWatched(int count) {
    return '$count കണ്ടത്';
  }

  @override
  String calPlanned(int count) {
    return '$count പ്ലാൻ ചെയ്തത്';
  }

  @override
  String get showStubs => 'ടിക്കറ്റുകൾ';

  @override
  String get showWatchlist => 'കാണാനുള്ളവ';

  @override
  String get dayEmpty => 'ഈ ദിവസം ഒന്നുമില്ല.';

  @override
  String get recordForDay => 'ഈ ദിവസം കണ്ട സിനിമ രേഖപ്പെടുത്തുക';

  @override
  String get today => 'ഇന്ന്';

  @override
  String get filmsNew => 'പുതിയവ';

  @override
  String get filmsUpcoming => 'വരാനിരിക്കുന്നവ';

  @override
  String get filmsWant => 'കാണാനുള്ളവ';

  @override
  String get filmsRecorded => 'കണ്ടവ';

  @override
  String get filmsReleased => 'റിലീസായവ';

  @override
  String get allLanguages => 'എല്ലാം';

  @override
  String get wantEmpty => 'കാണാനുള്ള സിനിമകൾ ബുക്ക്‌മാർക്ക് ചെയ്യുക. അവ ഇവിടെയും നിങ്ങളുടെ കലണ്ടറിലും കാണാം.';

  @override
  String get recordedEmpty => 'നിങ്ങൾ രേഖപ്പെടുത്തുന്ന സിനിമകൾ ഇവിടെ കാണാം.';

  @override
  String get noReleases => 'ഓഫ്‌ലൈൻ ലിസ്റ്റിൽ ഈ ഭാഷയിൽ റിലീസുകളില്ല. ഓൺലൈനിൽ ആകുമ്പോൾ സിനിമ ലിസ്റ്റ് പുതുക്കുക.';

  @override
  String get refreshNow => 'സിനിമ ലിസ്റ്റ് പുതുക്കുക';

  @override
  String get addedToWatchlist => 'വാച്ച്‌ലിസ്റ്റിൽ ചേർത്തു';

  @override
  String get removedFromWatchlist => 'വാച്ച്‌ലിസ്റ്റിൽ നിന്ന് നീക്കി';

  @override
  String watchCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count തവണ കണ്ടു', one: 'ഒരു തവണ കണ്ടു');
    return '$_temp0';
  }

  @override
  String get searchHint => 'സിനിമ, സീരീസ്, നടൻ അല്ലെങ്കിൽ സംവിധായകൻ';

  @override
  String get searchAll => 'എല്ലാം';

  @override
  String get notFound => 'ലിസ്റ്റിൽ ഇല്ലേ?';

  @override
  String get addManually => 'സ്വയം ചേർക്കുക';

  @override
  String get loadingCatalog => 'സിനിമ ലിസ്റ്റ് തുറക്കുന്നു';

  @override
  String get catalogError => 'സിനിമ ലിസ്റ്റ് ലോഡ് ആയില്ല. ആപ്പ് വീണ്ടും തുറക്കുക.';

  @override
  String searchPrompt(String count) {
    return '$count ഇന്ത്യൻ, വിദേശ ടൈറ്റിലുകൾ തിരയുക. ഓഫ്‌ലൈനിലും പ്രവർത്തിക്കും.';
  }

  @override
  String noResults(String query) {
    return '“$query” എന്നതിന് ടൈറ്റിലുകളൊന്നും കിട്ടിയില്ല.';
  }

  @override
  String get director => 'സംവിധായകൻ';

  @override
  String get cast => 'അഭിനേതാക്കൾ';

  @override
  String get language => 'ഭാഷ';

  @override
  String get country => 'രാജ്യം';

  @override
  String seasons(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count സീസണുകൾ', one: '1 സീസൺ');
    return '$_temp0';
  }

  @override
  String get availableOn => 'ഇവിടെ കാണാം';

  @override
  String get streamingHint => 'വിക്കിപീഡിയയിൽ നിന്ന്. ലഭ്യത മാറാം.';

  @override
  String get synopsis => 'കഥ';

  @override
  String get synopsisOffline => 'കഥ വായിക്കാൻ ഇന്റർനെറ്റ് വേണം.';

  @override
  String get synopsisNone => 'കഥ കിട്ടിയില്ല.';

  @override
  String get iWatched => 'ഞാൻ കണ്ടു';

  @override
  String get watchedAgain => 'വീണ്ടും കണ്ടു';

  @override
  String get wantToWatch => 'കാണണം';

  @override
  String get inWatchlist => 'വാച്ച്‌ലിസ്റ്റിലുണ്ട്';

  @override
  String plannedFor(String date) {
    return '$date-ന് പ്ലാൻ ചെയ്തു';
  }

  @override
  String get setPlannedDate => 'തീയതി നിശ്ചയിക്കുക';

  @override
  String get clearDate => 'തീയതി നീക്കുക';

  @override
  String get yourStubs => 'നിങ്ങളുടെ ടിക്കറ്റുകൾ';

  @override
  String get openWikipedia => 'Wikipedia-യിൽ വായിക്കുക';

  @override
  String get fixOnWikidata => 'ഈ വിവരങ്ങൾ തിരുത്തുക';

  @override
  String get fixHint => 'സിനിമ വിവരങ്ങൾ Wikidata-യിൽ നിന്നാണ്. ആർക്കും അവിടെ തിരുത്താം.';

  @override
  String get yourOwnFilm => 'നിങ്ങൾ ചേർത്തത്';

  @override
  String watchNth(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n-ാം തവണ',
      two: 'രണ്ടാം തവണ',
      one: 'ആദ്യ തവണ',
    );
    return '$_temp0';
  }

  @override
  String hoursMinutes(int h, int m) {
    return '$h മ. $m മി.';
  }

  @override
  String minutesOnly(int m) {
    return '$m മിനിറ്റ്';
  }

  @override
  String ticketNo(String no) {
    return 'നമ്പർ $no';
  }

  @override
  String get ticket => 'ടിക്കറ്റ്';

  @override
  String get admitOne => 'ADMIT ONE';

  @override
  String get stampWatched => 'WATCHED';

  @override
  String get fdfs => 'FDFS';

  @override
  String get labelDate => 'തീയതി';

  @override
  String get labelPlace => 'സ്ഥലം';

  @override
  String get labelShow => 'ഷോ';

  @override
  String get labelClass => 'ക്ലാസ്';

  @override
  String get labelSeat => 'സീറ്റ്';

  @override
  String get labelPrice => 'നിരക്ക്';

  @override
  String get labelFormat => 'ഫോർമാറ്റ്';

  @override
  String get labelLang => 'കണ്ട ഭാഷ';

  @override
  String get labelWith => 'കൂടെ';

  @override
  String get labelRating => 'റേറ്റിംഗ്';

  @override
  String get labelTags => 'ടാഗുകൾ';

  @override
  String get labelMemo => 'കുറിപ്പ്';

  @override
  String get dateUnknown => 'തീയതി ഓർമയില്ല';

  @override
  String get noRating => 'റേറ്റിംഗ് ഇല്ല';

  @override
  String get tearUpQ => 'ഈ ടിക്കറ്റ് കീറിക്കളയണോ?';

  @override
  String get tearUpBody => 'ഈ തവണ കണ്ടതിന്റെ രേഖ ഇല്ലാതാകും.';

  @override
  String get tearUp => 'കീറിക്കളയുക';

  @override
  String get stubDeleted => 'ടിക്കറ്റ് കീറിക്കളഞ്ഞു';

  @override
  String get shareTicket => 'ടിക്കറ്റ് ഷെയർ ചെയ്യുക';

  @override
  String get recordTitle => 'പുതിയ ടിക്കറ്റ്';

  @override
  String get editTitle => 'ടിക്കറ്റ് എഡിറ്റ് ചെയ്യുക';

  @override
  String get whenWatched => 'എപ്പോഴാണ് കണ്ടത്?';

  @override
  String get precisionDay => 'ദിവസം';

  @override
  String get precisionMonth => 'മാസം';

  @override
  String get precisionYear => 'വർഷം';

  @override
  String get precisionNone => 'ഓർമയില്ല';

  @override
  String get yesterday => 'ഇന്നലെ';

  @override
  String get wherePlace => 'എവിടെ?';

  @override
  String get addPlace => 'പുതിയ സ്ഥലം';

  @override
  String get placeName => 'സ്ഥലത്തിന്റെ പേര്';

  @override
  String get placeNameHint => 'PVR Lulu, കൈരളി, Netflix';

  @override
  String get placeType => 'തരം';

  @override
  String get hallDetails => 'തിയേറ്റർ വിവരങ്ങൾ';

  @override
  String get show => 'ഷോ';

  @override
  String get format => 'ഫോർമാറ്റ്';

  @override
  String get seatClass => 'ക്ലാസ്';

  @override
  String get seat => 'സീറ്റ്';

  @override
  String get seatHint => 'H12';

  @override
  String get price => 'ടിക്കറ്റ് നിരക്ക് (₹)';

  @override
  String get priceHint => '250';

  @override
  String get fdfsToggle => 'ആദ്യ ദിവസം, ആദ്യ ഷോ';

  @override
  String get watchedIn => 'കണ്ട ഭാഷ';

  @override
  String get originalLang => 'ഒറിജിനൽ';

  @override
  String get withWhom => 'ആരുടെ കൂടെ കണ്ടു';

  @override
  String get withHint => 'കൂട്ടുകാർ, കുടുംബം, ഒറ്റയ്ക്ക്';

  @override
  String get rating => 'റേറ്റിംഗ്';

  @override
  String get tags => 'ടാഗുകൾ';

  @override
  String get addTag => 'പുതിയ ടാഗ്';

  @override
  String get tagHint => 'പ്രിയപ്പെട്ടത്';

  @override
  String get memo => 'കുറിപ്പ്';

  @override
  String get memoHint => 'എന്താണ് മനസ്സിൽ തങ്ങിയത്?';

  @override
  String get stampIt => 'സീൽ അടിക്കുക';

  @override
  String get saveChanges => 'മാറ്റങ്ങൾ സേവ് ചെയ്യുക';

  @override
  String get discardQ => 'ഈ ടിക്കറ്റ് ഉപേക്ഷിക്കണോ?';

  @override
  String get discard => 'ഉപേക്ഷിക്കുക';

  @override
  String get keepEditing => 'എഡിറ്റിംഗ് തുടരുക';

  @override
  String get customTitle => 'സിനിമ സ്വയം ചേർക്കുക';

  @override
  String get customName => 'പേര്';

  @override
  String get customYear => 'വർഷം';

  @override
  String get customLang => 'ഭാഷ';

  @override
  String get customSeries => 'ഇതൊരു സീരീസ് ആണ്';

  @override
  String get customPoster => 'പോസ്റ്റർ';

  @override
  String get choosePhoto => 'ഫോട്ടോ തിരഞ്ഞെടുക്കുക';

  @override
  String get removePhoto => 'ഫോട്ടോ നീക്കുക';

  @override
  String get customSave => 'ചേർത്ത് രേഖപ്പെടുത്തുക';

  @override
  String get customSaveWish => 'വാച്ച്‌ലിസ്റ്റിൽ ചേർക്കുക';

  @override
  String get required => 'നിർബന്ധം';

  @override
  String yearInvalid(int max) {
    return '1900 മുതൽ $max വരെയുള്ള ഒരു വർഷം നൽകുക';
  }

  @override
  String get statsTitle => 'കണക്കുകൾ';

  @override
  String get scopeMonth => 'മാസം';

  @override
  String get scopeYear => 'വർഷം';

  @override
  String get scopeAll => 'എല്ലാ കാലവും';

  @override
  String get totalStubs => 'ടിക്കറ്റുകൾ';

  @override
  String get totalTime => 'കണ്ട സമയം';

  @override
  String get spent => 'ടിക്കറ്റിന് ചെലവായത്';

  @override
  String avgTicket(String amount) {
    return 'ഒരു ടിക്കറ്റിന് ശരാശരി $amount';
  }

  @override
  String get fdfsCount => 'FDFS';

  @override
  String get rewatches => 'വീണ്ടും കണ്ടവ';

  @override
  String get avgRating => 'ശരാശരി റേറ്റിംഗ്';

  @override
  String get byDay => 'ദിവസം തിരിച്ച്';

  @override
  String get byMonth => 'മാസം തിരിച്ച്';

  @override
  String get byYear => 'വർഷം തിരിച്ച്';

  @override
  String get byStars => 'റേറ്റിംഗുകൾ';

  @override
  String get byPlace => 'സ്ഥലങ്ങൾ';

  @override
  String get byVenueType => 'നിങ്ങൾ എവിടെ കാണുന്നു';

  @override
  String get byGenre => 'ജോണറുകൾ';

  @override
  String get byLanguage => 'ഭാഷകൾ';

  @override
  String get byCountry => 'രാജ്യങ്ങൾ';

  @override
  String get byDecade => 'ദശകങ്ങൾ';

  @override
  String get byDirector => 'നിങ്ങൾ കൂടുതൽ കാണുന്ന സംവിധായകർ';

  @override
  String get byActor => 'നിങ്ങൾ കൂടുതൽ കാണുന്ന അഭിനേതാക്കൾ';

  @override
  String get byTag => 'ടാഗുകൾ';

  @override
  String get byFormat => 'ഫോർമാറ്റുകൾ';

  @override
  String get byShow => 'ഷോ സമയങ്ങൾ';

  @override
  String get statsEmpty => 'ഈ കാലയളവിൽ ടിക്കറ്റുകളില്ല.';

  @override
  String get tapForDetail => 'സിനിമകൾ കാണാൻ ഒരു ബാറിൽ ടാപ്പ് ചെയ്യുക.';

  @override
  String showMore(int count) {
    return 'എല്ലാ $count എണ്ണവും കാണിക്കുക';
  }

  @override
  String get showLess => 'കുറച്ച് കാണിക്കുക';

  @override
  String get unrated => 'റേറ്റിംഗ് ഇല്ല';

  @override
  String decadeLabel(String decade) {
    return '$decade-കൾ';
  }

  @override
  String get shareTitle => 'ഇമേജ് ഷെയർ ചെയ്യുക';

  @override
  String get background => 'പശ്ചാത്തലം';

  @override
  String get showTitles => 'പേരുകൾ';

  @override
  String get showDates => 'തീയതികൾ';

  @override
  String get showRatings => 'റേറ്റിംഗുകൾ';

  @override
  String get shareMonth => 'ഈ മാസം ഷെയർ ചെയ്യുക';

  @override
  String monthAtMovies(String month) {
    return '$month-ലെ സിനിമകൾ';
  }

  @override
  String get nothingToShare => 'ഈ മാസം ഇതുവരെ ടിക്കറ്റുകളില്ല.';

  @override
  String get settingsTitle => 'ക്രമീകരണം';

  @override
  String get appearance => 'രൂപം';

  @override
  String get theme => 'തീം';

  @override
  String get themeSystem => 'സിസ്റ്റം';

  @override
  String get themeLight => 'ലൈറ്റ്';

  @override
  String get themeDark => 'ഡാർക്ക്';

  @override
  String get accentColor => 'സീൽ മഷി';

  @override
  String get accent_sindoor => 'സിന്ദൂരം';

  @override
  String get accent_marigold => 'ചെണ്ടുമല്ലി';

  @override
  String get accent_peacock => 'മയിൽപ്പീലി';

  @override
  String get accent_mehendi => 'മൈലാഞ്ചി';

  @override
  String get accent_neel => 'നീലം';

  @override
  String get accent_jamun => 'ഞാവൽ';

  @override
  String get accent_gulabi => 'റോസ്';

  @override
  String get accent_kesar => 'കുങ്കുമപ്പൂവ്';

  @override
  String get accent_paan => 'വെറ്റില';

  @override
  String get accent_chai => 'ചായ';

  @override
  String get accent_kajal => 'കണ്മഷി';

  @override
  String get appIcon => 'ആപ്പ് ഐക്കൺ';

  @override
  String get icon_default => 'പിങ്ക് ടിക്കറ്റ്';

  @override
  String get icon_yellow => 'മഞ്ഞ ടിക്കറ്റ്';

  @override
  String get icon_green => 'പച്ച ടിക്കറ്റ്';

  @override
  String get icon_blue => 'നീല ടിക്കറ്റ്';

  @override
  String get icon_night => 'നൈറ്റ് ഷോ';

  @override
  String get iconChanged => 'ആപ്പ് ഐക്കൺ മാറ്റി';

  @override
  String get iconFailed => 'ഈ ഉപകരണത്തിൽ ഐക്കൺ മാറിയില്ല.';

  @override
  String get appLanguage => 'ആപ്പ് ഭാഷ';

  @override
  String get languageSystem => 'ഉപകരണത്തിന്റെ ഭാഷ';

  @override
  String get calendarSection => 'കലണ്ടർ';

  @override
  String get weekStart => 'ആഴ്ച തുടങ്ങുന്നത്';

  @override
  String get sunday => 'ഞായർ';

  @override
  String get monday => 'തിങ്കൾ';

  @override
  String get ratingsSection => 'റേറ്റിംഗ്';

  @override
  String get showRatingsToggle => 'സ്റ്റാർ റേറ്റിംഗ് കാണിക്കുക';

  @override
  String get releaseLists => 'പുതിയതും വരാനിരിക്കുന്നതുമായ ലിസ്റ്റുകൾ';

  @override
  String get releasesIndia => 'ഇന്ത്യൻ സിനിമകൾ';

  @override
  String get releasesWorld => 'എല്ലാ സിനിമകളും';

  @override
  String get manageTags => 'ടാഗുകൾ';

  @override
  String get manageVenues => 'സ്ഥലങ്ങൾ';

  @override
  String get dataSection => 'നിങ്ങളുടെ ഡാറ്റ';

  @override
  String get exportCsv => 'CSV എക്സ്പോർട്ട് ചെയ്യുക';

  @override
  String get importCsv => 'CSV ഇംപോർട്ട് ചെയ്യുക';

  @override
  String get importHint => 'Talkies അല്ലെങ്കിൽ Letterboxd CSV ഫയൽ';

  @override
  String get backup => 'എല്ലാം ബാക്കപ്പ് ചെയ്യുക';

  @override
  String get backupHint => 'ഒരൊറ്റ JSON ഫയൽ. അത് Drive-ൽ സൂക്ഷിക്കുക, അല്ലെങ്കിൽ നിങ്ങൾക്കുതന്നെ അയയ്ക്കുക.';

  @override
  String get restore => 'ബാക്കപ്പ് പുനഃസ്ഥാപിക്കുക';

  @override
  String get batchAdd => 'ഒന്നിച്ച് ചേർക്കുക';

  @override
  String get batchAddHint => 'പേരുകളുടെ ലിസ്റ്റ് പേസ്റ്റ് ചെയ്യുക';

  @override
  String get refreshCatalog => 'സിനിമ ലിസ്റ്റ് പുതുക്കുക';

  @override
  String refreshedOn(String date, String updated) {
    return '$date-ന് തയ്യാറാക്കിയത്. $updated-ന് പുതുക്കി.';
  }

  @override
  String builtOn(String date) {
    return '$date-ന് തയ്യാറാക്കിയത്. ഇതുവരെ പുതുക്കിയിട്ടില്ല.';
  }

  @override
  String refreshDone(int count) {
    return '$count പുതിയതും വരാനിരിക്കുന്നതുമായ സിനിമകൾ പുതുക്കി';
  }

  @override
  String get refreshFailed => 'പുതുക്കാനായില്ല. ഇന്റർനെറ്റ് പരിശോധിക്കുക.';

  @override
  String get about => 'ആപ്പിനെക്കുറിച്ച്';

  @override
  String get aboutBody =>
      'ഇന്ത്യൻ സിനിമാപ്രേമികൾക്കുള്ള ടിക്കറ്റ് ഡയറിയാണ് ടാക്കീസ്. നിങ്ങളുടെ ടിക്കറ്റുകൾ ഈ ഫോണിൽ മാത്രമേ ഉണ്ടാകൂ. സിനിമ വിവരങ്ങൾ Wikidata (CC0)-യിൽ നിന്നും പോസ്റ്ററുകൾ Wikipedia-യിൽ നിന്നുമാണ്.';

  @override
  String version(String v) {
    return 'പതിപ്പ് $v';
  }

  @override
  String get whatsNew => 'പുതിയതെന്ത്';

  @override
  String get privacyPolicy => 'സ്വകാര്യതാ നയം';

  @override
  String get replaceQ => 'എല്ലാം ഈ ബാക്കപ്പ് കൊണ്ട് മാറ്റണോ?';

  @override
  String replaceBody(int count) {
    return 'നിങ്ങളുടെ ഇപ്പോഴത്തെ $count ടിക്കറ്റുകൾക്ക് പകരം ബാക്കപ്പ് വരും.';
  }

  @override
  String get replace => 'മാറ്റുക';

  @override
  String get restoreDone => 'ബാക്കപ്പ് പുനഃസ്ഥാപിച്ചു';

  @override
  String get restoreFailed => 'ഇതൊരു ടാക്കീസ് ബാക്കപ്പ് അല്ല.';

  @override
  String imported(int count, int matched, int custom) {
    return '$count ടിക്കറ്റുകൾ ചേർത്തു. $matched എണ്ണം സിനിമ ലിസ്റ്റുമായി ഒത്തു, $custom എണ്ണം നിങ്ങളുടെ സ്വന്തം സിനിമകളായി ചേർത്തു.';
  }

  @override
  String get importNothing => 'ഈ ഫയലിൽ വരികളൊന്നും കിട്ടിയില്ല.';

  @override
  String get nothingToExport => 'എക്സ്പോർട്ട് ചെയ്യാൻ ഇതുവരെ ടിക്കറ്റുകളില്ല.';

  @override
  String get tagsEmpty => 'ഇതുവരെ ടാഗുകളില്ല. ഇവിടെയോ സിനിമ രേഖപ്പെടുത്തുമ്പോഴോ ചേർക്കുക.';

  @override
  String get renameTag => 'ടാഗിന്റെ പേര് മാറ്റുക';

  @override
  String deleteTagQ(String tag, int count) {
    return '#$tag ഇല്ലാതാക്കണോ? ഇത് $count ടിക്കറ്റുകളിൽ നിന്ന് നീക്കും.';
  }

  @override
  String get editVenue => 'സ്ഥലം എഡിറ്റ് ചെയ്യുക';

  @override
  String deleteVenueQ(String name) {
    return '$name ലിസ്റ്റിൽ നിന്ന് നീക്കണോ? ടിക്കറ്റുകളിൽ പേര് നിലനിൽക്കും.';
  }

  @override
  String get remove => 'നീക്കുക';

  @override
  String stubsUsing(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ടിക്കറ്റുകളിൽ ഉപയോഗിച്ചു',
      one: '1 ടിക്കറ്റിൽ ഉപയോഗിച്ചു',
      zero: 'ഉപയോഗിച്ചിട്ടില്ല',
    );
    return '$_temp0';
  }

  @override
  String get batchTitle => 'ഒന്നിച്ച് ചേർക്കുക';

  @override
  String get batchHint => 'ഓരോ വരിയിലും ഒരു പേര്. കൃത്യമാകാൻ വർഷവും ചേർക്കുക.';

  @override
  String get batchExample => 'Sholay 1975\nRRR (2022)\nPanchayat';

  @override
  String get batchMatch => 'പേരുകൾ ഒത്തുനോക്കുക';

  @override
  String batchAddAll(int count) {
    return '$count ടിക്കറ്റുകൾ ചേർക്കുക';
  }

  @override
  String get batchOwn => 'ഒത്തില്ല. നിങ്ങളുടെ സ്വന്തം സിനിമയായി ചേർക്കും.';

  @override
  String get batchDefaults => 'എല്ലാ സിനിമകൾക്കും';

  @override
  String batchDone(int count) {
    return '$count ടിക്കറ്റുകൾ ചേർത്തു';
  }

  @override
  String whatsNewTitle(String v) {
    return 'ടാക്കീസ് $v';
  }

  @override
  String get whatsNew1 =>
      'എല്ലാ പ്രീമിയം ഫീച്ചറുകളും സൗജന്യം: എല്ലാ കാലത്തെയും കണക്കുകൾ, പരിധിയില്ലാത്ത ടാഗുകൾ, 11 സീൽ മഷികൾ, ഡാർക്ക് മോഡ്, ആപ്പ് ഐക്കണുകൾ, ഷെയർ പശ്ചാത്തലങ്ങൾ, CSV എക്സ്പോർട്ട്.';

  @override
  String get whatsNew2 =>
      'തിയേറ്റർ വിവരങ്ങൾ രേഖപ്പെടുത്തുക: ഷോ, ക്ലാസ്, സീറ്റ്, ഫോർമാറ്റ്, ടിക്കറ്റ് നിരക്ക്, ആദ്യ ദിവസം ആദ്യ ഷോ.';

  @override
  String get whatsNew3 =>
      '34,000 ഇന്ത്യൻ, വിദേശ ടൈറ്റിലുകൾ ഓഫ്‌ലൈനിൽ പ്രവർത്തിക്കും. ഓൺലൈനിൽ ആകുമ്പോൾ പുതിയ റിലീസുകൾ പുതുക്കും.';

  @override
  String get gotIt => 'ശരി';
}
