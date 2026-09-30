// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Telugu (`te`).
class AppLocalizationsTe extends AppLocalizations {
  AppLocalizationsTe([String locale = 'te']) : super(locale);

  @override
  String get appName => 'టాకీస్';

  @override
  String get tabHome => 'హోమ్';

  @override
  String get tabStubs => 'టికెట్లు';

  @override
  String get tabCalendar => 'క్యాలెండర్';

  @override
  String get tabFilms => 'సినిమాలు';

  @override
  String get tabStats => 'గణాంకాలు';

  @override
  String get recordFilm => 'సినిమా నమోదు చేయి';

  @override
  String get search => 'వెతుకు';

  @override
  String get cancel => 'రద్దు చేయి';

  @override
  String get save => 'సేవ్ చేయి';

  @override
  String get delete => 'తొలగించు';

  @override
  String get edit => 'సవరించు';

  @override
  String get done => 'పూర్తయింది';

  @override
  String get undo => 'చర్యరద్దు';

  @override
  String get share => 'షేర్ చేయి';

  @override
  String get back => 'వెనుకకు';

  @override
  String get clear => 'క్లియర్ చేయి';

  @override
  String get settings => 'సెట్టింగ్‌లు';

  @override
  String get previous => 'మునుపటి';

  @override
  String get next => 'తర్వాత';

  @override
  String unitFilms(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: 'సినిమాలు', one: 'సినిమా');
    return '$_temp0';
  }

  @override
  String get thisYear => 'ఈ సంవత్సరం';

  @override
  String get recent => 'ఇటీవలివి';

  @override
  String get allStubs => 'అన్ని టికెట్లు';

  @override
  String get newReleases => 'కొత్త రిలీజ్‌లు';

  @override
  String get comingSoon => 'త్వరలో వస్తున్నవి';

  @override
  String get seeAll => 'అన్నీ చూడండి';

  @override
  String get emptyHome => 'మీ మొదటి టికెట్‌కి ఒక్క సినిమా చాలు. + నొక్కి, సినిమా పేరు వెతకండి.';

  @override
  String get venueCinema => 'థియేటర్';

  @override
  String get venueOtt => 'స్ట్రీమింగ్';

  @override
  String get venueHome => 'ఇల్లు';

  @override
  String get venueTv => 'టీవీ';

  @override
  String get venueOther => 'ఇతర';

  @override
  String get splitLegend => 'ఈ సంవత్సరం మీరు ఎక్కడ చూశారు';

  @override
  String ticketsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count టికెట్లు',
      one: '1 టికెట్',
      zero: 'టికెట్లు లేవు',
    );
    return '$_temp0';
  }

  @override
  String get sortNewest => 'కొత్తవి ముందు';

  @override
  String get sortOldest => 'పాతవి ముందు';

  @override
  String get sortRatingHigh => 'ఎక్కువ రేటింగ్';

  @override
  String get sortRatingLow => 'తక్కువ రేటింగ్';

  @override
  String get sort => 'క్రమం';

  @override
  String get filter => 'ఫిల్టర్';

  @override
  String get filterAll => 'అన్నీ';

  @override
  String get filterPlace => 'ప్రదేశం';

  @override
  String get filterTag => 'ట్యాగ్';

  @override
  String get filterYear => 'సంవత్సరం';

  @override
  String get filterKind => 'రకం';

  @override
  String get filterRating => 'రేటింగ్';

  @override
  String get kindFilm => 'సినిమాలు';

  @override
  String get kindSeries => 'సిరీస్';

  @override
  String get gridView => 'గ్రిడ్ వ్యూ';

  @override
  String get listView => 'లిస్ట్ వ్యూ';

  @override
  String get searchStubs => 'మీ టికెట్లలో వెతకండి';

  @override
  String get noStubs => 'ఇంకా టికెట్లు లేవు. మీరు నమోదు చేసే ప్రతి సినిమా ఇక్కడ ఒక టికెట్ అవుతుంది.';

  @override
  String get noMatch => 'ఈ ఫిల్టర్లకు ఏదీ సరిపోలలేదు.';

  @override
  String get resetFilters => 'ఫిల్టర్లు తీసేయి';

  @override
  String starsAtLeast(int stars) {
    return '$stars+ స్టార్లు';
  }

  @override
  String calWatched(int count) {
    return '$count చూసినవి';
  }

  @override
  String calPlanned(int count) {
    return '$count ప్లాన్ చేసినవి';
  }

  @override
  String get showStubs => 'టికెట్లు';

  @override
  String get showWatchlist => 'వాచ్‌లిస్ట్';

  @override
  String get dayEmpty => 'ఈ రోజు ఏమీ లేదు.';

  @override
  String get recordForDay => 'ఈ రోజు చూసిన సినిమా నమోదు చేయి';

  @override
  String get today => 'ఈ రోజు';

  @override
  String get filmsNew => 'కొత్తవి';

  @override
  String get filmsUpcoming => 'రాబోయేవి';

  @override
  String get filmsWant => 'చూడాల్సినవి';

  @override
  String get filmsRecorded => 'నమోదు చేసినవి';

  @override
  String get filmsReleased => 'రిలీజ్ అయినవి';

  @override
  String get allLanguages => 'అన్నీ';

  @override
  String get wantEmpty => 'చూడాలనుకునే సినిమాలను బుక్‌మార్క్ చేయండి. అవి ఇక్కడ, మీ క్యాలెండర్‌లో కనిపిస్తాయి.';

  @override
  String get recordedEmpty => 'మీరు నమోదు చేసిన సినిమాలు ఇక్కడ కనిపిస్తాయి.';

  @override
  String get noReleases =>
      'ఈ భాషలో ఆఫ్‌లైన్ జాబితాలో రిలీజ్‌లు లేవు. ఆన్‌లైన్‌లో ఉన్నప్పుడు సినిమా జాబితాను రిఫ్రెష్ చేయండి.';

  @override
  String get refreshNow => 'సినిమా జాబితా రిఫ్రెష్ చేయి';

  @override
  String get addedToWatchlist => 'వాచ్‌లిస్ట్‌కు జోడించబడింది';

  @override
  String get removedFromWatchlist => 'వాచ్‌లిస్ట్ నుండి తీసివేయబడింది';

  @override
  String watchCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count సార్లు చూశారు',
      one: 'ఒకసారి చూశారు',
    );
    return '$_temp0';
  }

  @override
  String get searchHint => 'సినిమా, సిరీస్, నటుడు లేదా దర్శకుడు';

  @override
  String get searchAll => 'అన్నీ';

  @override
  String get notFound => 'జాబితాలో లేదా?';

  @override
  String get addManually => 'మీరే జోడించండి';

  @override
  String get loadingCatalog => 'సినిమా జాబితా తెరుచుకుంటోంది';

  @override
  String get catalogError => 'సినిమా జాబితా లోడ్ కాలేదు. యాప్‌ను రీస్టార్ట్ చేయండి.';

  @override
  String searchPrompt(String count) {
    return '$count భారతీయ, ప్రపంచ టైటిల్స్‌లో వెతకండి. ఆఫ్‌లైన్‌లోనూ పనిచేస్తుంది.';
  }

  @override
  String noResults(String query) {
    return '“$query” పేరుతో ఏదీ దొరకలేదు.';
  }

  @override
  String get director => 'దర్శకుడు';

  @override
  String get cast => 'నటీనటులు';

  @override
  String get language => 'భాష';

  @override
  String get country => 'దేశం';

  @override
  String seasons(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count సీజన్లు', one: '1 సీజన్');
    return '$_temp0';
  }

  @override
  String get availableOn => 'స్ట్రీమింగ్ ప్లాట్‌ఫామ్';

  @override
  String get streamingHint => 'వికీపీడియా నుండి. అందుబాటు మారవచ్చు.';

  @override
  String get synopsis => 'కథ సారాంశం';

  @override
  String get synopsisOffline => 'కథ సారాంశం చూడాలంటే ఇంటర్నెట్ కావాలి.';

  @override
  String get synopsisNone => 'కథ సారాంశం దొరకలేదు.';

  @override
  String get iWatched => 'నేను చూశాను';

  @override
  String get watchedAgain => 'మళ్లీ చూశాను';

  @override
  String get wantToWatch => 'చూడాలి';

  @override
  String get inWatchlist => 'వాచ్‌లిస్ట్‌లో ఉంది';

  @override
  String plannedFor(String date) {
    return '$dateన చూడాలని ప్లాన్';
  }

  @override
  String get setPlannedDate => 'తేదీ ప్లాన్ చేయి';

  @override
  String get clearDate => 'తేదీ తీసేయి';

  @override
  String get yourStubs => 'మీ టికెట్లు';

  @override
  String get openWikipedia => 'Wikipediaలో చదవండి';

  @override
  String get fixOnWikidata => 'ఈ వివరాలు సరిచేయండి';

  @override
  String get fixHint => 'సినిమా వివరాలు Wikidata నుండి వస్తాయి. అక్కడ ఎవరైనా వాటిని సరిచేయవచ్చు.';

  @override
  String get yourOwnFilm => 'మీరు జోడించినది';

  @override
  String watchNth(int n) {
    String _temp0 = intl.Intl.pluralLogic(n, locale: localeName, other: '$nవ సారి', two: 'రెండోసారి', one: 'మొదటిసారి');
    return '$_temp0';
  }

  @override
  String hoursMinutes(int h, int m) {
    return '$hగం $mని';
  }

  @override
  String minutesOnly(int m) {
    return '$m నిమి';
  }

  @override
  String ticketNo(String no) {
    return 'నం. $no';
  }

  @override
  String get ticket => 'టికెట్';

  @override
  String get admitOne => 'ADMIT ONE';

  @override
  String get stampWatched => 'WATCHED';

  @override
  String get fdfs => 'FDFS';

  @override
  String get labelDate => 'తేదీ';

  @override
  String get labelPlace => 'ప్రదేశం';

  @override
  String get labelShow => 'షో';

  @override
  String get labelClass => 'క్లాస్';

  @override
  String get labelSeat => 'సీట్';

  @override
  String get labelPrice => 'ధర';

  @override
  String get labelFormat => 'ఫార్మాట్';

  @override
  String get labelLang => 'చూసిన భాష';

  @override
  String get labelWith => 'ఎవరితో';

  @override
  String get labelRating => 'రేటింగ్';

  @override
  String get labelTags => 'ట్యాగ్‌లు';

  @override
  String get labelMemo => 'నోట్స్';

  @override
  String get dateUnknown => 'తేదీ గుర్తు లేదు';

  @override
  String get noRating => 'రేటింగ్ లేదు';

  @override
  String get tearUpQ => 'ఈ టికెట్ చింపేయాలా?';

  @override
  String get tearUpBody => 'ఈసారి చూసిన రికార్డ్ తొలగిపోతుంది.';

  @override
  String get tearUp => 'చింపేయి';

  @override
  String get stubDeleted => 'టికెట్ చింపేశారు';

  @override
  String get shareTicket => 'టికెట్ షేర్ చేయి';

  @override
  String get recordTitle => 'కొత్త టికెట్';

  @override
  String get editTitle => 'టికెట్ సవరించు';

  @override
  String get whenWatched => 'ఎప్పుడు చూశారు?';

  @override
  String get precisionDay => 'రోజు';

  @override
  String get precisionMonth => 'నెల';

  @override
  String get precisionYear => 'సంవత్సరం';

  @override
  String get precisionNone => 'గుర్తు లేదు';

  @override
  String get yesterday => 'నిన్న';

  @override
  String get wherePlace => 'ఎక్కడ?';

  @override
  String get addPlace => 'కొత్త ప్రదేశం';

  @override
  String get placeName => 'ప్రదేశం పేరు';

  @override
  String get placeNameHint => 'ప్రసాద్స్, సుదర్శన్ 35MM, Netflix';

  @override
  String get placeType => 'రకం';

  @override
  String get hallDetails => 'థియేటర్ వివరాలు';

  @override
  String get show => 'షో';

  @override
  String get format => 'ఫార్మాట్';

  @override
  String get seatClass => 'క్లాస్';

  @override
  String get seat => 'సీట్';

  @override
  String get seatHint => 'H12';

  @override
  String get price => 'టికెట్ ధర (₹)';

  @override
  String get priceHint => '250';

  @override
  String get fdfsToggle => 'మొదటి రోజు, మొదటి షో';

  @override
  String get watchedIn => 'చూసిన భాష';

  @override
  String get originalLang => 'ఒరిజినల్';

  @override
  String get withWhom => 'ఎవరితో చూశారు';

  @override
  String get withHint => 'స్నేహితులు, కుటుంబం, ఒంటరిగా';

  @override
  String get rating => 'రేటింగ్';

  @override
  String get tags => 'ట్యాగ్‌లు';

  @override
  String get addTag => 'కొత్త ట్యాగ్';

  @override
  String get tagHint => 'ఇష్టమైనది';

  @override
  String get memo => 'నోట్స్';

  @override
  String get memoHint => 'ఏది గుర్తుండిపోయింది?';

  @override
  String get stampIt => 'ముద్ర వేయి';

  @override
  String get saveChanges => 'మార్పులు సేవ్ చేయి';

  @override
  String get discardQ => 'ఈ టికెట్ వదిలేయాలా?';

  @override
  String get discard => 'వదిలేయి';

  @override
  String get keepEditing => 'సవరించడం కొనసాగించు';

  @override
  String get customTitle => 'సినిమాను మీరే జోడించండి';

  @override
  String get customName => 'పేరు';

  @override
  String get customYear => 'సంవత్సరం';

  @override
  String get customLang => 'భాష';

  @override
  String get customSeries => 'ఇది ఒక సిరీస్';

  @override
  String get customPoster => 'పోస్టర్';

  @override
  String get choosePhoto => 'ఫోటో ఎంచుకోండి';

  @override
  String get removePhoto => 'ఫోటో తీసేయి';

  @override
  String get customSave => 'జోడించి నమోదు చేయి';

  @override
  String get customSaveWish => 'వాచ్‌లిస్ట్‌కు జోడించు';

  @override
  String get required => 'తప్పనిసరి';

  @override
  String yearInvalid(int max) {
    return '1900 నుండి $max మధ్య సంవత్సరం ఇవ్వండి';
  }

  @override
  String get statsTitle => 'గణాంకాలు';

  @override
  String get scopeMonth => 'నెల';

  @override
  String get scopeYear => 'సంవత్సరం';

  @override
  String get scopeAll => 'మొత్తం';

  @override
  String get totalStubs => 'టికెట్లు';

  @override
  String get totalTime => 'చూసిన సమయం';

  @override
  String get spent => 'టికెట్లపై ఖర్చు';

  @override
  String avgTicket(String amount) {
    return 'సగటున ఒక్కో టికెట్‌కు $amount';
  }

  @override
  String get fdfsCount => 'FDFS';

  @override
  String get rewatches => 'మళ్లీ చూసినవి';

  @override
  String get avgRating => 'సగటు రేటింగ్';

  @override
  String get byDay => 'రోజు వారీగా';

  @override
  String get byMonth => 'నెల వారీగా';

  @override
  String get byYear => 'సంవత్సరం వారీగా';

  @override
  String get byStars => 'రేటింగ్‌లు';

  @override
  String get byPlace => 'ప్రదేశాలు';

  @override
  String get byVenueType => 'మీరు ఎక్కడ చూస్తారు';

  @override
  String get byGenre => 'జానర్లు';

  @override
  String get byLanguage => 'భాషలు';

  @override
  String get byCountry => 'దేశాలు';

  @override
  String get byDecade => 'దశాబ్దాలు';

  @override
  String get byDirector => 'మీరు ఎక్కువగా చూసే దర్శకులు';

  @override
  String get byActor => 'మీరు ఎక్కువగా చూసే నటులు';

  @override
  String get byTag => 'ట్యాగ్‌లు';

  @override
  String get byFormat => 'ఫార్మాట్లు';

  @override
  String get byShow => 'షో సమయాలు';

  @override
  String get statsEmpty => 'ఈ కాలంలో టికెట్లు లేవు.';

  @override
  String get tapForDetail => 'సినిమాలు చూడటానికి ఒక బార్‌ను నొక్కండి.';

  @override
  String showMore(int count) {
    return 'మొత్తం $count చూపించు';
  }

  @override
  String get showLess => 'తక్కువ చూపించు';

  @override
  String get unrated => 'రేటింగ్ లేదు';

  @override
  String decadeLabel(String decade) {
    return '$decadeలు';
  }

  @override
  String get shareTitle => 'ఇమేజ్ షేర్ చేయి';

  @override
  String get background => 'నేపథ్యం';

  @override
  String get showTitles => 'పేర్లు';

  @override
  String get showDates => 'తేదీలు';

  @override
  String get showRatings => 'రేటింగ్‌లు';

  @override
  String get shareMonth => 'ఈ నెలను షేర్ చేయి';

  @override
  String monthAtMovies(String month) {
    return '$monthలో చూసిన సినిమాలు';
  }

  @override
  String get nothingToShare => 'ఈ నెల ఇంకా టికెట్లు లేవు.';

  @override
  String get settingsTitle => 'సెట్టింగ్‌లు';

  @override
  String get appearance => 'రూపం';

  @override
  String get theme => 'థీమ్';

  @override
  String get themeSystem => 'సిస్టమ్';

  @override
  String get themeLight => 'లైట్';

  @override
  String get themeDark => 'డార్క్';

  @override
  String get accentColor => 'ముద్ర సిరా';

  @override
  String get accent_sindoor => 'సింధూరం';

  @override
  String get accent_marigold => 'బంతిపూవు';

  @override
  String get accent_peacock => 'నెమలి';

  @override
  String get accent_mehendi => 'గోరింటాకు';

  @override
  String get accent_neel => 'నీలం';

  @override
  String get accent_jamun => 'నేరేడు';

  @override
  String get accent_gulabi => 'గులాబీ';

  @override
  String get accent_kesar => 'కుంకుమపువ్వు';

  @override
  String get accent_paan => 'తమలపాకు';

  @override
  String get accent_chai => 'చాయ్';

  @override
  String get accent_kajal => 'కాటుక';

  @override
  String get appIcon => 'యాప్ ఐకాన్';

  @override
  String get icon_default => 'గులాబీ టికెట్';

  @override
  String get icon_yellow => 'పసుపు టికెట్';

  @override
  String get icon_green => 'ఆకుపచ్చ టికెట్';

  @override
  String get icon_blue => 'నీలి టికెట్';

  @override
  String get icon_night => 'నైట్ షో';

  @override
  String get iconChanged => 'యాప్ ఐకాన్ మారింది';

  @override
  String get iconFailed => 'ఈ డివైస్‌లో ఐకాన్ మారలేదు.';

  @override
  String get appLanguage => 'యాప్ భాష';

  @override
  String get languageSystem => 'డివైస్ భాష';

  @override
  String get calendarSection => 'క్యాలెండర్';

  @override
  String get weekStart => 'వారం మొదలయ్యే రోజు';

  @override
  String get sunday => 'ఆదివారం';

  @override
  String get monday => 'సోమవారం';

  @override
  String get ratingsSection => 'రేటింగ్‌లు';

  @override
  String get showRatingsToggle => 'స్టార్ రేటింగ్‌లు చూపించు';

  @override
  String get releaseLists => 'కొత్త, రాబోయే జాబితాలు';

  @override
  String get releasesIndia => 'భారతీయ సినిమాలు';

  @override
  String get releasesWorld => 'అన్ని సినిమాలు';

  @override
  String get manageTags => 'ట్యాగ్‌లు';

  @override
  String get manageVenues => 'ప్రదేశాలు';

  @override
  String get dataSection => 'మీ డేటా';

  @override
  String get exportCsv => 'CSV ఎక్స్‌పోర్ట్ చేయి';

  @override
  String get importCsv => 'CSV ఇంపోర్ట్ చేయి';

  @override
  String get importHint => 'Talkies లేదా Letterboxd CSV ఫైల్';

  @override
  String get backup => 'అన్నింటినీ బ్యాకప్ చేయి';

  @override
  String get backupHint => 'ఒక JSON ఫైల్. దాన్ని Driveలో ఉంచండి లేదా మీకే పంపుకోండి.';

  @override
  String get restore => 'బ్యాకప్ రీస్టోర్ చేయి';

  @override
  String get batchAdd => 'త్వరగా జోడించు';

  @override
  String get batchAddHint => 'పేర్ల జాబితాను పేస్ట్ చేయండి';

  @override
  String get refreshCatalog => 'సినిమా జాబితా రిఫ్రెష్ చేయి';

  @override
  String refreshedOn(String date, String updated) {
    return '$dateన తయారైంది. $updatedన అప్‌డేట్ అయింది.';
  }

  @override
  String builtOn(String date) {
    return '$dateన తయారైంది. ఇంకా రిఫ్రెష్ కాలేదు.';
  }

  @override
  String refreshDone(int count) {
    return '$count ఇటీవలి, రాబోయే సినిమాలు అప్‌డేట్ అయ్యాయి';
  }

  @override
  String get refreshFailed => 'రిఫ్రెష్ కాలేదు. కనెక్షన్ చెక్ చేయండి.';

  @override
  String get about => 'యాప్ గురించి';

  @override
  String get aboutBody =>
      'టాకీస్ భారతీయ సినిమా ప్రేమికుల టికెట్ డైరీ. మీ టికెట్లు ఈ ఫోన్‌లోనే ఉంటాయి. సినిమా వివరాలు Wikidata (CC0) నుండి, పోస్టర్లు Wikipedia నుండి వస్తాయి.';

  @override
  String version(String v) {
    return 'వెర్షన్ $v';
  }

  @override
  String get whatsNew => 'కొత్తగా ఏముంది';

  @override
  String get privacyPolicy => 'గోప్యతా విధానం';

  @override
  String get replaceQ => 'అన్నింటినీ ఈ బ్యాకప్‌తో మార్చాలా?';

  @override
  String replaceBody(int count) {
    return 'మీ ప్రస్తుత $count టికెట్ల స్థానంలో బ్యాకప్ వస్తుంది.';
  }

  @override
  String get replace => 'మార్చు';

  @override
  String get restoreDone => 'బ్యాకప్ రీస్టోర్ అయింది';

  @override
  String get restoreFailed => 'ఇది టాకీస్ బ్యాకప్ కాదు.';

  @override
  String imported(int count, int matched, int custom) {
    return '$count టికెట్లు జోడించబడ్డాయి. $matched సినిమా జాబితాతో సరిపోలాయి, $custom మీ సొంత సినిమాలుగా జోడించబడ్డాయి.';
  }

  @override
  String get importNothing => 'ఈ ఫైల్‌లో వరుసలు ఏవీ లేవు.';

  @override
  String get nothingToExport => 'ఎక్స్‌పోర్ట్ చేయడానికి ఇంకా టికెట్లు లేవు.';

  @override
  String get tagsEmpty => 'ఇంకా ట్యాగ్‌లు లేవు. ఇక్కడ గానీ, సినిమా నమోదు చేసేటప్పుడు గానీ జోడించండి.';

  @override
  String get renameTag => 'ట్యాగ్ పేరు మార్చు';

  @override
  String deleteTagQ(String tag, int count) {
    return '#$tag తొలగించాలా? ఇది $count టికెట్ల నుండి తీసివేయబడుతుంది.';
  }

  @override
  String get editVenue => 'ప్రదేశం సవరించు';

  @override
  String deleteVenueQ(String name) {
    return '$name ప్రదేశాన్ని జాబితా నుండి తీసేయాలా? టికెట్లపై పేరు అలాగే ఉంటుంది.';
  }

  @override
  String get remove => 'తీసేయి';

  @override
  String stubsUsing(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count టికెట్లలో ఉంది',
      one: '1 టికెట్‌లో ఉంది',
      zero: 'వాడలేదు',
    );
    return '$_temp0';
  }

  @override
  String get batchTitle => 'త్వరగా జోడించు';

  @override
  String get batchHint => 'ఒక్కో లైన్‌కు ఒక పేరు. సరిగ్గా సరిపోలడానికి సంవత్సరం కూడా ఇవ్వండి.';

  @override
  String get batchExample => 'Sholay 1975\nRRR (2022)\nPanchayat';

  @override
  String get batchMatch => 'పేర్లు సరిపోల్చు';

  @override
  String batchAddAll(int count) {
    return '$count టికెట్లు జోడించు';
  }

  @override
  String get batchOwn => 'సరిపోలలేదు. మీ సొంత సినిమాగా జోడించబడుతుంది.';

  @override
  String get batchDefaults => 'ప్రతి సినిమాకు';

  @override
  String batchDone(int count) {
    return '$count టికెట్లు జోడించబడ్డాయి';
  }

  @override
  String whatsNewTitle(String v) {
    return 'టాకీస్ $v';
  }

  @override
  String get whatsNew1 =>
      'ప్రతి ప్రీమియం ఫీచర్ ఉచితం: మొత్తం గణాంకాలు, అపరిమిత ట్యాగ్‌లు, 11 ముద్ర సిరాలు, డార్క్ మోడ్, యాప్ ఐకాన్‌లు, షేర్ నేపథ్యాలు, CSV ఎక్స్‌పోర్ట్.';

  @override
  String get whatsNew2 => 'థియేటర్ వివరాలు నమోదు చేయండి: షో, క్లాస్, సీట్, ఫార్మాట్, టికెట్ ధర, మొదటి రోజు మొదటి షో.';

  @override
  String get whatsNew3 =>
      '34,000 భారతీయ, ప్రపంచ టైటిల్స్ ఆఫ్‌లైన్‌లో పనిచేస్తాయి. ఆన్‌లైన్‌లో ఉన్నప్పుడు కొత్త రిలీజ్‌లు రిఫ్రెష్ అవుతాయి.';

  @override
  String get gotIt => 'సరే';
}
