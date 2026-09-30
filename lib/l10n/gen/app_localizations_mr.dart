// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Marathi (`mr`).
class AppLocalizationsMr extends AppLocalizations {
  AppLocalizationsMr([String locale = 'mr']) : super(locale);

  @override
  String get appName => 'टॉकीज';

  @override
  String get tabHome => 'होम';

  @override
  String get tabStubs => 'तिकिटे';

  @override
  String get tabCalendar => 'कॅलेंडर';

  @override
  String get tabFilms => 'चित्रपट';

  @override
  String get tabStats => 'आकडेवारी';

  @override
  String get recordFilm => 'चित्रपट नोंदवा';

  @override
  String get search => 'शोधा';

  @override
  String get cancel => 'रद्द करा';

  @override
  String get save => 'सेव्ह करा';

  @override
  String get delete => 'हटवा';

  @override
  String get edit => 'बदला';

  @override
  String get done => 'झाले';

  @override
  String get undo => 'पूर्ववत करा';

  @override
  String get share => 'शेअर करा';

  @override
  String get back => 'मागे';

  @override
  String get clear => 'साफ करा';

  @override
  String get settings => 'सेटिंग्ज';

  @override
  String get previous => 'मागील';

  @override
  String get next => 'पुढील';

  @override
  String unitFilms(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: 'चित्रपट', one: 'चित्रपट');
    return '$_temp0';
  }

  @override
  String get thisYear => 'या वर्षी';

  @override
  String get recent => 'अलीकडचे';

  @override
  String get allStubs => 'सर्व तिकिटे';

  @override
  String get newReleases => 'नवीन रिलीज';

  @override
  String get comingSoon => 'लवकरच येणार';

  @override
  String get seeAll => 'सर्व पाहा';

  @override
  String get emptyHome => 'तुमचे पहिले तिकीट फक्त एक चित्रपट दूर आहे. + दाबा आणि चित्रपटाचे नाव शोधा.';

  @override
  String get venueCinema => 'थिएटर';

  @override
  String get venueOtt => 'स्ट्रीमिंग';

  @override
  String get venueHome => 'घर';

  @override
  String get venueTv => 'टीव्ही';

  @override
  String get venueOther => 'इतर';

  @override
  String get splitLegend => 'या वर्षी तुम्ही कुठे पाहिले';

  @override
  String ticketsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count तिकिटे',
      one: '1 तिकीट',
      zero: 'एकही तिकीट नाही',
    );
    return '$_temp0';
  }

  @override
  String get sortNewest => 'नवीन आधी';

  @override
  String get sortOldest => 'जुने आधी';

  @override
  String get sortRatingHigh => 'सर्वाधिक रेटिंग';

  @override
  String get sortRatingLow => 'सर्वात कमी रेटिंग';

  @override
  String get sort => 'क्रमवारी';

  @override
  String get filter => 'फिल्टर';

  @override
  String get filterAll => 'सर्व';

  @override
  String get filterPlace => 'ठिकाण';

  @override
  String get filterTag => 'टॅग';

  @override
  String get filterYear => 'वर्ष';

  @override
  String get filterKind => 'प्रकार';

  @override
  String get filterRating => 'रेटिंग';

  @override
  String get kindFilm => 'चित्रपट';

  @override
  String get kindSeries => 'सिरीज';

  @override
  String get gridView => 'ग्रिड व्ह्यू';

  @override
  String get listView => 'लिस्ट व्ह्यू';

  @override
  String get searchStubs => 'तुमची तिकिटे शोधा';

  @override
  String get noStubs => 'अजून एकही तिकीट नाही. तुम्ही नोंदवलेला प्रत्येक चित्रपट इथे तिकीट बनतो.';

  @override
  String get noMatch => 'या फिल्टरनुसार काहीही सापडले नाही.';

  @override
  String get resetFilters => 'फिल्टर काढा';

  @override
  String starsAtLeast(int stars) {
    return '$stars+ स्टार';
  }

  @override
  String calWatched(int count) {
    return '$count पाहिले';
  }

  @override
  String calPlanned(int count) {
    return '$count ठरवले';
  }

  @override
  String get showStubs => 'तिकिटे';

  @override
  String get showWatchlist => 'पाहायची यादी';

  @override
  String get dayEmpty => 'या दिवशी काहीही नाही.';

  @override
  String get recordForDay => 'या दिवशीचा चित्रपट नोंदवा';

  @override
  String get today => 'आज';

  @override
  String get filmsNew => 'नवीन';

  @override
  String get filmsUpcoming => 'येणारे';

  @override
  String get filmsWant => 'पाहायचे';

  @override
  String get filmsRecorded => 'पाहिलेले';

  @override
  String get filmsReleased => 'प्रदर्शित';

  @override
  String get allLanguages => 'सर्व';

  @override
  String get wantEmpty => 'जे चित्रपट पाहायचे आहेत ते बुकमार्क करा. ते इथे आणि कॅलेंडरवर दिसतील.';

  @override
  String get recordedEmpty => 'तुम्ही नोंदवलेले चित्रपट इथे दिसतील.';

  @override
  String get noReleases => 'ऑफलाइन यादीत या भाषेतील एकही रिलीज नाही. ऑनलाइन असताना चित्रपट यादी रिफ्रेश करा.';

  @override
  String get refreshNow => 'चित्रपट यादी रिफ्रेश करा';

  @override
  String get addedToWatchlist => 'पाहायच्या यादीत जोडले';

  @override
  String get removedFromWatchlist => 'पाहायच्या यादीतून काढले';

  @override
  String watchCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count वेळा पाहिला', one: 'एकदा पाहिला');
    return '$_temp0';
  }

  @override
  String get searchHint => 'चित्रपट, सिरीज, अभिनेता किंवा दिग्दर्शक';

  @override
  String get searchAll => 'सर्व';

  @override
  String get notFound => 'यादीत नाही?';

  @override
  String get addManually => 'स्वतः जोडा';

  @override
  String get loadingCatalog => 'चित्रपट यादी उघडत आहे';

  @override
  String get catalogError => 'चित्रपट यादी लोड झाली नाही. ॲप पुन्हा सुरू करा.';

  @override
  String searchPrompt(String count) {
    return '$count भारतीय आणि जगभरातील टायटल शोधा. ऑफलाइनही चालते.';
  }

  @override
  String noResults(String query) {
    return '“$query” शी जुळणारे एकही टायटल नाही.';
  }

  @override
  String get director => 'दिग्दर्शक';

  @override
  String get cast => 'कलाकार';

  @override
  String get language => 'भाषा';

  @override
  String get country => 'देश';

  @override
  String seasons(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count सीझन', one: '1 सीझन');
    return '$_temp0';
  }

  @override
  String get availableOn => 'इथे स्ट्रीम होत आहे';

  @override
  String get streamingHint => 'माहिती विकिपीडियावरून. उपलब्धता बदलू शकते.';

  @override
  String get synopsis => 'कथा';

  @override
  String get synopsisOffline => 'कथा पाहण्यासाठी इंटरनेट हवे.';

  @override
  String get synopsisNone => 'कथा सापडली नाही.';

  @override
  String get iWatched => 'मी पाहिला';

  @override
  String get watchedAgain => 'पुन्हा पाहिला';

  @override
  String get wantToWatch => 'पाहायचा आहे';

  @override
  String get inWatchlist => 'यादीत आहे';

  @override
  String plannedFor(String date) {
    return '$date ला ठरवले';
  }

  @override
  String get setPlannedDate => 'तारीख ठरवा';

  @override
  String get clearDate => 'तारीख काढा';

  @override
  String get yourStubs => 'तुमची तिकिटे';

  @override
  String get openWikipedia => 'Wikipedia वर वाचा';

  @override
  String get fixOnWikidata => 'माहिती दुरुस्त करा';

  @override
  String get fixHint => 'चित्रपटाची माहिती Wikidata वरून येते. तिथे कोणीही ती दुरुस्त करू शकते.';

  @override
  String get yourOwnFilm => 'तुम्ही जोडलेला';

  @override
  String watchNth(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: 'पाहणे क्र. $n',
      two: 'दुसऱ्यांदा',
      one: 'पहिल्यांदा',
    );
    return '$_temp0';
  }

  @override
  String hoursMinutes(int h, int m) {
    return '$h ता $m मि';
  }

  @override
  String minutesOnly(int m) {
    return '$m मिनिटे';
  }

  @override
  String ticketNo(String no) {
    return 'क्र. $no';
  }

  @override
  String get ticket => 'तिकीट';

  @override
  String get admitOne => 'ADMIT ONE';

  @override
  String get stampWatched => 'WATCHED';

  @override
  String get fdfs => 'FDFS';

  @override
  String get labelDate => 'तारीख';

  @override
  String get labelPlace => 'ठिकाण';

  @override
  String get labelShow => 'शो';

  @override
  String get labelClass => 'क्लास';

  @override
  String get labelSeat => 'सीट';

  @override
  String get labelPrice => 'किंमत';

  @override
  String get labelFormat => 'फॉरमॅट';

  @override
  String get labelLang => 'पाहण्याची भाषा';

  @override
  String get labelWith => 'कोणासोबत';

  @override
  String get labelRating => 'रेटिंग';

  @override
  String get labelTags => 'टॅग';

  @override
  String get labelMemo => 'नोट्स';

  @override
  String get dateUnknown => 'तारीख आठवत नाही';

  @override
  String get noRating => 'रेटिंग नाही';

  @override
  String get tearUpQ => 'हे तिकीट फाडायचे?';

  @override
  String get tearUpBody => 'यामुळे या वेळी पाहिल्याची नोंद हटेल.';

  @override
  String get tearUp => 'फाडा';

  @override
  String get stubDeleted => 'तिकीट फाडले';

  @override
  String get shareTicket => 'तिकीट शेअर करा';

  @override
  String get recordTitle => 'नवीन तिकीट';

  @override
  String get editTitle => 'तिकीट बदला';

  @override
  String get whenWatched => 'कधी पाहिला?';

  @override
  String get precisionDay => 'दिवस';

  @override
  String get precisionMonth => 'महिना';

  @override
  String get precisionYear => 'वर्ष';

  @override
  String get precisionNone => 'आठवत नाही';

  @override
  String get yesterday => 'काल';

  @override
  String get wherePlace => 'कुठे?';

  @override
  String get addPlace => 'नवीन ठिकाण';

  @override
  String get placeName => 'ठिकाणाचे नाव';

  @override
  String get placeNameHint => 'PVR फिनिक्स, मराठा मंदिर, Netflix';

  @override
  String get placeType => 'प्रकार';

  @override
  String get hallDetails => 'थिएटरची माहिती';

  @override
  String get show => 'शो';

  @override
  String get format => 'फॉरमॅट';

  @override
  String get seatClass => 'क्लास';

  @override
  String get seat => 'सीट';

  @override
  String get seatHint => 'H12';

  @override
  String get price => 'तिकिटाची किंमत (₹)';

  @override
  String get priceHint => '250';

  @override
  String get fdfsToggle => 'पहिला दिवस, पहिला शो';

  @override
  String get watchedIn => 'कोणत्या भाषेत पाहिला';

  @override
  String get originalLang => 'मूळ';

  @override
  String get withWhom => 'कोणासोबत पाहिला';

  @override
  String get withHint => 'मित्र, कुटुंब, एकटे';

  @override
  String get rating => 'रेटिंग';

  @override
  String get tags => 'टॅग';

  @override
  String get addTag => 'नवीन टॅग';

  @override
  String get tagHint => 'आवडता';

  @override
  String get memo => 'नोट्स';

  @override
  String get memoHint => 'काय लक्षात राहिले?';

  @override
  String get stampIt => 'शिक्का मारा';

  @override
  String get saveChanges => 'बदल सेव्ह करा';

  @override
  String get discardQ => 'हे तिकीट टाकून द्यायचे?';

  @override
  String get discard => 'टाकून द्या';

  @override
  String get keepEditing => 'बदल सुरू ठेवा';

  @override
  String get customTitle => 'स्वतः चित्रपट जोडा';

  @override
  String get customName => 'नाव';

  @override
  String get customYear => 'वर्ष';

  @override
  String get customLang => 'भाषा';

  @override
  String get customSeries => 'ही सिरीज आहे';

  @override
  String get customPoster => 'पोस्टर';

  @override
  String get choosePhoto => 'फोटो निवडा';

  @override
  String get removePhoto => 'फोटो काढा';

  @override
  String get customSave => 'जोडा आणि नोंदवा';

  @override
  String get customSaveWish => 'पाहायच्या यादीत जोडा';

  @override
  String get required => 'आवश्यक';

  @override
  String yearInvalid(int max) {
    return '1900 ते $max मधील वर्ष लिहा';
  }

  @override
  String get statsTitle => 'आकडेवारी';

  @override
  String get scopeMonth => 'महिना';

  @override
  String get scopeYear => 'वर्ष';

  @override
  String get scopeAll => 'आतापर्यंत';

  @override
  String get totalStubs => 'तिकिटे';

  @override
  String get totalTime => 'पाहण्याचा वेळ';

  @override
  String get spent => 'तिकिटांवर खर्च';

  @override
  String avgTicket(String amount) {
    return 'सरासरी प्रति तिकीट $amount';
  }

  @override
  String get fdfsCount => 'FDFS';

  @override
  String get rewatches => 'पुन्हा पाहिलेले';

  @override
  String get avgRating => 'सरासरी रेटिंग';

  @override
  String get byDay => 'दिवसानुसार';

  @override
  String get byMonth => 'महिन्यानुसार';

  @override
  String get byYear => 'वर्षानुसार';

  @override
  String get byStars => 'रेटिंग';

  @override
  String get byPlace => 'ठिकाणे';

  @override
  String get byVenueType => 'तुम्ही कुठे पाहता';

  @override
  String get byGenre => 'शैली';

  @override
  String get byLanguage => 'भाषा';

  @override
  String get byCountry => 'देश';

  @override
  String get byDecade => 'दशके';

  @override
  String get byDirector => 'सर्वाधिक पाहिलेले दिग्दर्शक';

  @override
  String get byActor => 'सर्वाधिक पाहिलेले कलाकार';

  @override
  String get byTag => 'टॅग';

  @override
  String get byFormat => 'फॉरमॅट';

  @override
  String get byShow => 'शोची वेळ';

  @override
  String get statsEmpty => 'या कालावधीत एकही तिकीट नाही.';

  @override
  String get tapForDetail => 'चित्रपट पाहण्यासाठी एखाद्या बारवर टॅप करा.';

  @override
  String showMore(int count) {
    return 'सर्व $count दाखवा';
  }

  @override
  String get showLess => 'कमी दाखवा';

  @override
  String get unrated => 'रेटिंग नाही';

  @override
  String decadeLabel(String decade) {
    return '$decade चे दशक';
  }

  @override
  String get shareTitle => 'इमेज शेअर करा';

  @override
  String get background => 'पार्श्वभूमी';

  @override
  String get showTitles => 'नावे';

  @override
  String get showDates => 'तारखा';

  @override
  String get showRatings => 'रेटिंग';

  @override
  String get shareMonth => 'हा महिना शेअर करा';

  @override
  String monthAtMovies(String month) {
    return '$month मधील चित्रपट';
  }

  @override
  String get nothingToShare => 'या महिन्यात अजून एकही तिकीट नाही.';

  @override
  String get settingsTitle => 'सेटिंग्ज';

  @override
  String get appearance => 'स्वरूप';

  @override
  String get theme => 'थीम';

  @override
  String get themeSystem => 'सिस्टम';

  @override
  String get themeLight => 'लाइट';

  @override
  String get themeDark => 'डार्क';

  @override
  String get accentColor => 'शिक्क्याची शाई';

  @override
  String get accent_sindoor => 'कुंकू';

  @override
  String get accent_marigold => 'झेंडू';

  @override
  String get accent_peacock => 'मोरपंखी';

  @override
  String get accent_mehendi => 'मेंदी';

  @override
  String get accent_neel => 'नीळ';

  @override
  String get accent_jamun => 'जांभूळ';

  @override
  String get accent_gulabi => 'गुलाबी';

  @override
  String get accent_kesar => 'केशर';

  @override
  String get accent_paan => 'विडा';

  @override
  String get accent_chai => 'चहा';

  @override
  String get accent_kajal => 'काजळ';

  @override
  String get appIcon => 'ॲप आयकन';

  @override
  String get icon_default => 'गुलाबी तिकीट';

  @override
  String get icon_yellow => 'पिवळे तिकीट';

  @override
  String get icon_green => 'हिरवे तिकीट';

  @override
  String get icon_blue => 'निळे तिकीट';

  @override
  String get icon_night => 'नाईट शो';

  @override
  String get iconChanged => 'ॲप आयकन बदलला';

  @override
  String get iconFailed => 'या डिव्हाइसवर आयकन बदलला नाही.';

  @override
  String get appLanguage => 'ॲपची भाषा';

  @override
  String get languageSystem => 'डिव्हाइसची भाषा';

  @override
  String get calendarSection => 'कॅलेंडर';

  @override
  String get weekStart => 'आठवडा सुरू होतो';

  @override
  String get sunday => 'रविवार';

  @override
  String get monday => 'सोमवार';

  @override
  String get ratingsSection => 'रेटिंग';

  @override
  String get showRatingsToggle => 'स्टार रेटिंग दाखवा';

  @override
  String get releaseLists => 'नवीन आणि येणाऱ्या याद्या';

  @override
  String get releasesIndia => 'भारतीय चित्रपट';

  @override
  String get releasesWorld => 'सर्व चित्रपट';

  @override
  String get manageTags => 'टॅग';

  @override
  String get manageVenues => 'ठिकाणे';

  @override
  String get dataSection => 'तुमचा डेटा';

  @override
  String get exportCsv => 'CSV एक्सपोर्ट करा';

  @override
  String get importCsv => 'CSV इम्पोर्ट करा';

  @override
  String get importHint => 'Talkies किंवा Letterboxd ची CSV फाइल';

  @override
  String get backup => 'सर्व काही बॅकअप करा';

  @override
  String get backupHint => 'एक JSON फाइल. ती Drive मध्ये ठेवा किंवा स्वतःला पाठवा.';

  @override
  String get restore => 'बॅकअप परत आणा';

  @override
  String get batchAdd => 'एकदम जोडा';

  @override
  String get batchAddHint => 'नावांची यादी पेस्ट करा';

  @override
  String get refreshCatalog => 'चित्रपट यादी रिफ्रेश करा';

  @override
  String refreshedOn(String date, String updated) {
    return '$date ला तयार. $updated ला अपडेट झाली.';
  }

  @override
  String builtOn(String date) {
    return '$date ला तयार. अजून रिफ्रेश झाली नाही.';
  }

  @override
  String refreshDone(int count) {
    return '$count नवीन आणि येणारे चित्रपट अपडेट झाले';
  }

  @override
  String get refreshFailed => 'रिफ्रेश झाले नाही. इंटरनेट तपासा.';

  @override
  String get about => 'ॲपबद्दल';

  @override
  String get aboutBody =>
      'टॉकीज ही भारतीय चित्रपटप्रेमींची तिकीट डायरी आहे. तुमची तिकिटे याच फोनवर राहतात. चित्रपटाची माहिती Wikidata (CC0) वरून आणि पोस्टर Wikipedia वरून येतात.';

  @override
  String version(String v) {
    return 'आवृत्ती $v';
  }

  @override
  String get whatsNew => 'नवीन काय';

  @override
  String get privacyPolicy => 'गोपनीयता धोरण';

  @override
  String get replaceQ => 'सर्व काही या बॅकअपने बदलायचे?';

  @override
  String replaceBody(int count) {
    return 'तुमची सध्याची $count तिकिटे बॅकअपने बदलली जातील.';
  }

  @override
  String get replace => 'बदलून टाका';

  @override
  String get restoreDone => 'बॅकअप परत आला';

  @override
  String get restoreFailed => 'ही टॉकीजची बॅकअप फाइल नाही.';

  @override
  String imported(int count, int matched, int custom) {
    return '$count तिकिटे जोडली. $matched चित्रपट यादीशी जुळली, $custom तुमचे स्वतःचे चित्रपट म्हणून जोडली.';
  }

  @override
  String get importNothing => 'या फाइलमध्ये एकही ओळ सापडली नाही.';

  @override
  String get nothingToExport => 'एक्सपोर्ट करण्यासाठी अजून एकही तिकीट नाही.';

  @override
  String get tagsEmpty => 'अजून एकही टॅग नाही. इथे किंवा चित्रपट नोंदवताना जोडा.';

  @override
  String get renameTag => 'टॅगचे नाव बदला';

  @override
  String deleteTagQ(String tag, int count) {
    return '#$tag हटवायचा? तो $count तिकिटांवरून काढला जाईल.';
  }

  @override
  String get editVenue => 'ठिकाण बदला';

  @override
  String deleteVenueQ(String name) {
    return '$name यादीतून काढायचे? तिकिटांवर नाव तसेच राहील.';
  }

  @override
  String get remove => 'काढा';

  @override
  String stubsUsing(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count तिकिटांवर',
      one: '1 तिकिटावर',
      zero: 'वापरलेले नाही',
    );
    return '$_temp0';
  }

  @override
  String get batchTitle => 'एकदम जोडा';

  @override
  String get batchHint => 'प्रत्येक ओळीत एक नाव. अचूक जुळण्यासाठी वर्षही लिहा.';

  @override
  String get batchExample => 'Sholay 1975\nRRR (2022)\nPanchayat';

  @override
  String get batchMatch => 'नावे जुळवा';

  @override
  String batchAddAll(int count) {
    return '$count तिकिटे जोडा';
  }

  @override
  String get batchOwn => 'जुळले नाही. तुमचा स्वतःचा चित्रपट म्हणून जोडला जाईल.';

  @override
  String get batchDefaults => 'प्रत्येक चित्रपटासाठी';

  @override
  String batchDone(int count) {
    return '$count तिकिटे जोडली';
  }

  @override
  String whatsNewTitle(String v) {
    return 'टॉकीज $v';
  }

  @override
  String get whatsNew1 =>
      'प्रत्येक प्रीमियम फीचर मोफत आहे: आतापर्यंतची आकडेवारी, अमर्याद टॅग, 11 शिक्क्यांच्या शाई, डार्क मोड, ॲप आयकन, शेअरसाठी पार्श्वभूमी आणि CSV एक्सपोर्ट.';

  @override
  String get whatsNew2 => 'थिएटरची माहिती नोंदवा: शो, क्लास, सीट, फॉरमॅट, तिकिटाची किंमत आणि पहिला दिवस पहिला शो.';

  @override
  String get whatsNew3 => '34,000 भारतीय आणि जगभरातील टायटल ऑफलाइन चालतात. ऑनलाइन असताना नवीन रिलीज रिफ्रेश होतात.';

  @override
  String get gotIt => 'ठीक आहे';
}
