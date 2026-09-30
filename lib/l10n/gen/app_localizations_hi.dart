// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hindi (`hi`).
class AppLocalizationsHi extends AppLocalizations {
  AppLocalizationsHi([String locale = 'hi']) : super(locale);

  @override
  String get appName => 'टॉकीज़';

  @override
  String get tabHome => 'होम';

  @override
  String get tabStubs => 'टिकट';

  @override
  String get tabCalendar => 'कैलेंडर';

  @override
  String get tabFilms => 'फ़िल्में';

  @override
  String get tabStats => 'आँकड़े';

  @override
  String get recordFilm => 'फ़िल्म दर्ज करें';

  @override
  String get search => 'खोजें';

  @override
  String get cancel => 'रद्द करें';

  @override
  String get save => 'सहेजें';

  @override
  String get delete => 'हटाएँ';

  @override
  String get edit => 'बदलें';

  @override
  String get done => 'हो गया';

  @override
  String get undo => 'वापस लें';

  @override
  String get share => 'शेयर करें';

  @override
  String get back => 'वापस';

  @override
  String get clear => 'साफ़ करें';

  @override
  String get settings => 'सेटिंग्स';

  @override
  String get previous => 'पिछला';

  @override
  String get next => 'अगला';

  @override
  String unitFilms(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: 'फ़िल्में', one: 'फ़िल्म');
    return '$_temp0';
  }

  @override
  String get thisYear => 'इस साल';

  @override
  String get recent => 'हाल ही में';

  @override
  String get allStubs => 'सभी टिकट';

  @override
  String get newReleases => 'नई रिलीज़';

  @override
  String get comingSoon => 'जल्द आ रही हैं';

  @override
  String get forYou => 'आपके लिए';

  @override
  String becauseYouLiked(String title) {
    return 'क्योंकि आपको $title पसंद आई';
  }

  @override
  String get notInterested => 'दिलचस्पी नहीं';

  @override
  String get hiddenFromRecs => 'सुझावों से हटाई गई';

  @override
  String get seeAll => 'सब देखें';

  @override
  String get emptyHome => 'आपका पहला टिकट बस एक फ़िल्म दूर है। + दबाएँ और फ़िल्म का नाम खोजें।';

  @override
  String get venueCinema => 'सिनेमा हॉल';

  @override
  String get venueOtt => 'स्ट्रीमिंग';

  @override
  String get venueHome => 'घर';

  @override
  String get venueTv => 'टीवी';

  @override
  String get venueOther => 'अन्य';

  @override
  String get splitLegend => 'इस साल आपने कहाँ देखा';

  @override
  String ticketsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count टिकट',
      one: '1 टिकट',
      zero: 'कोई टिकट नहीं',
    );
    return '$_temp0';
  }

  @override
  String get sortNewest => 'नए पहले';

  @override
  String get sortOldest => 'पुराने पहले';

  @override
  String get sortRatingHigh => 'सबसे ज़्यादा रेटिंग';

  @override
  String get sortRatingLow => 'सबसे कम रेटिंग';

  @override
  String get sort => 'क्रम';

  @override
  String get filter => 'फ़िल्टर';

  @override
  String get filterAll => 'सभी';

  @override
  String get filterPlace => 'जगह';

  @override
  String get filterTag => 'टैग';

  @override
  String get filterYear => 'साल';

  @override
  String get filterKind => 'प्रकार';

  @override
  String get filterRating => 'रेटिंग';

  @override
  String get kindFilm => 'फ़िल्में';

  @override
  String get kindSeries => 'सीरीज़';

  @override
  String get gridView => 'ग्रिड व्यू';

  @override
  String get listView => 'लिस्ट व्यू';

  @override
  String get searchStubs => 'अपने टिकट खोजें';

  @override
  String get noStubs => 'अभी कोई टिकट नहीं। हर दर्ज फ़िल्म यहाँ एक टिकट बनती है।';

  @override
  String get noMatch => 'इन फ़िल्टर से कुछ नहीं मिला।';

  @override
  String get resetFilters => 'फ़िल्टर हटाएँ';

  @override
  String starsAtLeast(int stars) {
    return '$stars+ स्टार';
  }

  @override
  String calWatched(int count) {
    return '$count देखीं';
  }

  @override
  String calPlanned(int count) {
    return '$count तय';
  }

  @override
  String get showStubs => 'टिकट';

  @override
  String get showWatchlist => 'देखनी हैं';

  @override
  String get dayEmpty => 'इस दिन कुछ नहीं।';

  @override
  String get recordForDay => 'इस दिन की फ़िल्म दर्ज करें';

  @override
  String get today => 'आज';

  @override
  String get filmsNew => 'नई';

  @override
  String get filmsUpcoming => 'आने वाली';

  @override
  String get filmsWant => 'देखनी हैं';

  @override
  String get filmsRecorded => 'देखी हुई';

  @override
  String get filmsReleased => 'रिलीज़ हो चुकी';

  @override
  String get allLanguages => 'सभी';

  @override
  String get wantEmpty => 'जो फ़िल्में देखनी हैं उन्हें बुकमार्क करें। वे यहाँ और कैलेंडर पर दिखेंगी।';

  @override
  String get recordedEmpty => 'आपकी दर्ज फ़िल्में यहाँ दिखेंगी।';

  @override
  String get noReleases => 'इस भाषा की कोई रिलीज़ ऑफ़लाइन सूची में नहीं है। ऑनलाइन होने पर फ़िल्म सूची रिफ़्रेश करें।';

  @override
  String get refreshNow => 'फ़िल्म सूची रिफ़्रेश करें';

  @override
  String get addedToWatchlist => 'देखने की सूची में जोड़ा गया';

  @override
  String get removedFromWatchlist => 'देखने की सूची से हटाया गया';

  @override
  String watchCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count बार देखी', one: 'एक बार देखी');
    return '$_temp0';
  }

  @override
  String get searchHint => 'फ़िल्म, सीरीज़, अभिनेता या निर्देशक';

  @override
  String get searchAll => 'सभी';

  @override
  String get notFound => 'सूची में नहीं है?';

  @override
  String get addManually => 'ख़ुद जोड़ें';

  @override
  String get loadingCatalog => 'फ़िल्म सूची खुल रही है';

  @override
  String get catalogError => 'फ़िल्म सूची नहीं खुली। ऐप फिर से खोलें।';

  @override
  String searchPrompt(String count) {
    return '$count भारतीय और विदेशी टाइटल खोजें। ऑफ़लाइन भी चलता है।';
  }

  @override
  String noResults(String query) {
    return '“$query” से कोई टाइटल नहीं मिला।';
  }

  @override
  String get director => 'निर्देशक';

  @override
  String get cast => 'कलाकार';

  @override
  String get language => 'भाषा';

  @override
  String get country => 'देश';

  @override
  String seasons(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count सीज़न', one: '1 सीज़न');
    return '$_temp0';
  }

  @override
  String get availableOn => 'यहाँ स्ट्रीम हो रही है';

  @override
  String get streamingHint => 'जानकारी विकिपीडिया से। उपलब्धता बदल सकती है।';

  @override
  String get synopsis => 'कहानी';

  @override
  String get synopsisOffline => 'कहानी के लिए इंटरनेट चाहिए।';

  @override
  String get synopsisNone => 'कहानी नहीं मिली।';

  @override
  String get iWatched => 'मैंने देखी';

  @override
  String get watchedAgain => 'फिर से देखी';

  @override
  String get wantToWatch => 'देखनी है';

  @override
  String get inWatchlist => 'सूची में है';

  @override
  String plannedFor(String date) {
    return '$date को तय';
  }

  @override
  String get setPlannedDate => 'तारीख़ तय करें';

  @override
  String get clearDate => 'तारीख़ हटाएँ';

  @override
  String get yourStubs => 'आपके टिकट';

  @override
  String get openWikipedia => 'विकिपीडिया पर पढ़ें';

  @override
  String get fixOnWikidata => 'जानकारी सुधारें';

  @override
  String get fixHint => 'फ़िल्म की जानकारी विकिडेटा से आती है। कोई भी उसे वहाँ सुधार सकता है।';

  @override
  String get yourOwnFilm => 'आपने जोड़ी';

  @override
  String watchNth(int n) {
    String _temp0 = intl.Intl.pluralLogic(n, locale: localeName, other: '$nवीं बार', two: 'दूसरी बार', one: 'पहली बार');
    return '$_temp0';
  }

  @override
  String hoursMinutes(int h, int m) {
    return '$h घं $m मि';
  }

  @override
  String minutesOnly(int m) {
    return '$m मिनट';
  }

  @override
  String ticketNo(String no) {
    return 'नं. $no';
  }

  @override
  String get ticket => 'टिकट';

  @override
  String get admitOne => 'ADMIT ONE';

  @override
  String get stampWatched => 'WATCHED';

  @override
  String get fdfs => 'FDFS';

  @override
  String get labelDate => 'तारीख़';

  @override
  String get labelPlace => 'जगह';

  @override
  String get labelShow => 'शो';

  @override
  String get labelClass => 'क्लास';

  @override
  String get labelSeat => 'सीट';

  @override
  String get labelPrice => 'दाम';

  @override
  String get labelFormat => 'फ़ॉर्मैट';

  @override
  String get labelLang => 'किस भाषा में';

  @override
  String get labelWith => 'किसके साथ';

  @override
  String get labelRating => 'रेटिंग';

  @override
  String get labelTags => 'टैग';

  @override
  String get labelMemo => 'नोट्स';

  @override
  String get dateUnknown => 'तारीख़ याद नहीं';

  @override
  String get noRating => 'कोई रेटिंग नहीं';

  @override
  String get tearUpQ => 'यह टिकट फाड़ दें?';

  @override
  String get tearUpBody => 'इससे इस बार देखने का रिकॉर्ड हट जाएगा।';

  @override
  String get tearUp => 'फाड़ दें';

  @override
  String get stubDeleted => 'टिकट फाड़ दिया';

  @override
  String get shareTicket => 'टिकट शेयर करें';

  @override
  String get recordTitle => 'नया टिकट';

  @override
  String get editTitle => 'टिकट बदलें';

  @override
  String get whenWatched => 'कब देखी?';

  @override
  String get precisionDay => 'दिन';

  @override
  String get precisionMonth => 'महीना';

  @override
  String get precisionYear => 'साल';

  @override
  String get precisionNone => 'याद नहीं';

  @override
  String get yesterday => 'कल';

  @override
  String get wherePlace => 'कहाँ?';

  @override
  String get addPlace => 'नई जगह';

  @override
  String get placeName => 'जगह का नाम';

  @override
  String get placeNameHint => 'PVR फ़ीनिक्स, मराठा मंदिर, Netflix';

  @override
  String get placeType => 'प्रकार';

  @override
  String get hallDetails => 'हॉल की जानकारी';

  @override
  String get show => 'शो';

  @override
  String get format => 'फ़ॉर्मैट';

  @override
  String get seatClass => 'क्लास';

  @override
  String get seat => 'सीट';

  @override
  String get seatHint => 'H12';

  @override
  String get price => 'टिकट का दाम (₹)';

  @override
  String get priceHint => '250';

  @override
  String get fdfsToggle => 'पहला दिन, पहला शो';

  @override
  String get watchedIn => 'किस भाषा में देखी';

  @override
  String get originalLang => 'मूल';

  @override
  String get withWhom => 'किसके साथ देखी';

  @override
  String get withHint => 'दोस्त, परिवार, अकेले';

  @override
  String get rating => 'रेटिंग';

  @override
  String get tags => 'टैग';

  @override
  String get addTag => 'नया टैग';

  @override
  String get tagHint => 'पसंदीदा';

  @override
  String get memo => 'नोट्स';

  @override
  String get memoHint => 'क्या याद रह गया?';

  @override
  String get stampIt => 'मुहर लगाएँ';

  @override
  String get saveChanges => 'बदलाव सहेजें';

  @override
  String get discardQ => 'यह टिकट छोड़ दें?';

  @override
  String get discard => 'छोड़ दें';

  @override
  String get keepEditing => 'बदलाव जारी रखें';

  @override
  String get customTitle => 'फ़िल्म ख़ुद जोड़ें';

  @override
  String get customName => 'नाम';

  @override
  String get customYear => 'साल';

  @override
  String get customLang => 'भाषा';

  @override
  String get customSeries => 'यह एक सीरीज़ है';

  @override
  String get customPoster => 'पोस्टर';

  @override
  String get choosePhoto => 'फ़ोटो चुनें';

  @override
  String get removePhoto => 'फ़ोटो हटाएँ';

  @override
  String get customSave => 'जोड़ें और दर्ज करें';

  @override
  String get customSaveWish => 'देखने की सूची में जोड़ें';

  @override
  String get required => 'ज़रूरी है';

  @override
  String yearInvalid(int max) {
    return '1900 से $max के बीच का साल लिखें';
  }

  @override
  String get statsTitle => 'आँकड़े';

  @override
  String get scopeMonth => 'महीना';

  @override
  String get scopeYear => 'साल';

  @override
  String get scopeAll => 'हमेशा से';

  @override
  String get totalStubs => 'टिकट';

  @override
  String get totalTime => 'देखने का समय';

  @override
  String get spent => 'टिकटों पर ख़र्च';

  @override
  String avgTicket(String amount) {
    return 'औसतन $amount प्रति टिकट';
  }

  @override
  String get fdfsCount => 'FDFS';

  @override
  String get rewatches => 'दोबारा देखीं';

  @override
  String get avgRating => 'औसत रेटिंग';

  @override
  String get byDay => 'दिन के हिसाब से';

  @override
  String get byMonth => 'महीने के हिसाब से';

  @override
  String get byYear => 'साल के हिसाब से';

  @override
  String get byStars => 'रेटिंग';

  @override
  String get byPlace => 'जगहें';

  @override
  String get byVenueType => 'आप कहाँ देखते हैं';

  @override
  String get byGenre => 'शैलियाँ';

  @override
  String get byLanguage => 'भाषाएँ';

  @override
  String get byCountry => 'देश';

  @override
  String get byDecade => 'दशक';

  @override
  String get byDirector => 'सबसे ज़्यादा देखे निर्देशक';

  @override
  String get byActor => 'सबसे ज़्यादा देखे कलाकार';

  @override
  String get byTag => 'टैग';

  @override
  String get byFormat => 'फ़ॉर्मैट';

  @override
  String get byShow => 'शो का समय';

  @override
  String get statsEmpty => 'इस अवधि में कोई टिकट नहीं।';

  @override
  String get tapForDetail => 'फ़िल्में देखने के लिए किसी बार को छुएँ।';

  @override
  String showMore(int count) {
    return 'सभी $count दिखाएँ';
  }

  @override
  String get showLess => 'कम दिखाएँ';

  @override
  String get unrated => 'बिना रेटिंग';

  @override
  String decadeLabel(String decade) {
    return '$decade का दशक';
  }

  @override
  String get shareTitle => 'इमेज शेयर करें';

  @override
  String get background => 'पृष्ठभूमि';

  @override
  String get showTitles => 'नाम';

  @override
  String get showDates => 'तारीख़ें';

  @override
  String get showRatings => 'रेटिंग';

  @override
  String get shareMonth => 'यह महीना शेयर करें';

  @override
  String monthAtMovies(String month) {
    return '$month सिनेमा में';
  }

  @override
  String get nothingToShare => 'इस महीने अभी कोई टिकट नहीं।';

  @override
  String get settingsTitle => 'सेटिंग्स';

  @override
  String get appearance => 'रूप-रंग';

  @override
  String get theme => 'थीम';

  @override
  String get themeSystem => 'सिस्टम';

  @override
  String get themeLight => 'लाइट';

  @override
  String get themeDark => 'डार्क';

  @override
  String get accentColor => 'मुहर की स्याही';

  @override
  String get accent_sindoor => 'सिंदूर';

  @override
  String get accent_marigold => 'गेंदा';

  @override
  String get accent_peacock => 'मोरपंखी';

  @override
  String get accent_mehendi => 'मेहंदी';

  @override
  String get accent_neel => 'नील';

  @override
  String get accent_jamun => 'जामुन';

  @override
  String get accent_gulabi => 'गुलाबी';

  @override
  String get accent_kesar => 'केसर';

  @override
  String get accent_paan => 'पान';

  @override
  String get accent_chai => 'चाय';

  @override
  String get accent_kajal => 'काजल';

  @override
  String get appIcon => 'ऐप आइकन';

  @override
  String get icon_default => 'गुलाबी टिकट';

  @override
  String get icon_yellow => 'पीला टिकट';

  @override
  String get icon_green => 'हरा टिकट';

  @override
  String get icon_blue => 'नीला टिकट';

  @override
  String get icon_night => 'नाइट शो';

  @override
  String get iconChanged => 'ऐप आइकन बदल गया';

  @override
  String get iconFailed => 'इस डिवाइस पर आइकन नहीं बदला।';

  @override
  String get appLanguage => 'ऐप की भाषा';

  @override
  String get languageSystem => 'डिवाइस की भाषा';

  @override
  String get calendarSection => 'कैलेंडर';

  @override
  String get weekStart => 'हफ़्ता शुरू होता है';

  @override
  String get sunday => 'रविवार';

  @override
  String get monday => 'सोमवार';

  @override
  String get ratingsSection => 'रेटिंग';

  @override
  String get showRatingsToggle => 'स्टार रेटिंग दिखाएँ';

  @override
  String get releaseLists => 'नई और आने वाली सूचियाँ';

  @override
  String get releasesIndia => 'भारतीय फ़िल्में';

  @override
  String get releasesWorld => 'सभी फ़िल्में';

  @override
  String get manageTags => 'टैग';

  @override
  String get manageVenues => 'जगहें';

  @override
  String get dataSection => 'आपका डेटा';

  @override
  String get exportCsv => 'CSV एक्सपोर्ट करें';

  @override
  String get importCsv => 'CSV इम्पोर्ट करें';

  @override
  String get importHint => 'Talkies या Letterboxd की CSV फ़ाइल';

  @override
  String get backup => 'सब कुछ बैकअप करें';

  @override
  String get backupHint => 'एक JSON फ़ाइल। इसे Drive में रखें या ख़ुद को भेजें।';

  @override
  String get restore => 'बैकअप वापस लाएँ';

  @override
  String get batchAdd => 'एक साथ जोड़ें';

  @override
  String get batchAddHint => 'नामों की सूची पेस्ट करें';

  @override
  String get refreshCatalog => 'फ़िल्म सूची रिफ़्रेश करें';

  @override
  String refreshedOn(String date, String updated) {
    return '$date को बनी। $updated को अपडेट हुई।';
  }

  @override
  String builtOn(String date) {
    return '$date को बनी। अभी रिफ़्रेश नहीं हुई।';
  }

  @override
  String refreshDone(int count) {
    return '$count नई और आने वाली फ़िल्में अपडेट हुईं';
  }

  @override
  String get refreshFailed => 'रिफ़्रेश नहीं हुआ। इंटरनेट जाँचें।';

  @override
  String get about => 'जानकारी';

  @override
  String get aboutBody =>
      'टॉकीज़ भारतीय फ़िल्म प्रेमियों की टिकट डायरी है। आपके टिकट इसी फ़ोन पर रहते हैं। फ़िल्म की जानकारी विकिडेटा (CC0) से और पोस्टर विकिपीडिया से आते हैं।';

  @override
  String version(String v) {
    return 'वर्ज़न $v';
  }

  @override
  String get whatsNew => 'नया क्या है';

  @override
  String get privacyPolicy => 'निजता नीति';

  @override
  String get replaceQ => 'सब कुछ इस बैकअप से बदल दें?';

  @override
  String replaceBody(int count) {
    return 'आपके अभी के $count टिकट बैकअप से बदल जाएँगे।';
  }

  @override
  String get replace => 'बदलें';

  @override
  String get restoreDone => 'बैकअप वापस आ गया';

  @override
  String get restoreFailed => 'यह टॉकीज़ का बैकअप नहीं है।';

  @override
  String imported(int count, int matched, int custom) {
    return '$count टिकट जुड़े। $matched फ़िल्म सूची से मिले, $custom आपकी अपनी फ़िल्मों के रूप में जुड़े।';
  }

  @override
  String get importNothing => 'इस फ़ाइल में कोई पंक्ति नहीं मिली।';

  @override
  String get nothingToExport => 'एक्सपोर्ट करने को अभी कोई टिकट नहीं।';

  @override
  String get tagsEmpty => 'अभी कोई टैग नहीं। यहाँ या फ़िल्म दर्ज करते समय जोड़ें।';

  @override
  String get renameTag => 'टैग का नाम बदलें';

  @override
  String deleteTagQ(String tag, int count) {
    return '#$tag हटाएँ? यह $count टिकटों से हट जाएगा।';
  }

  @override
  String get editVenue => 'जगह बदलें';

  @override
  String deleteVenueQ(String name) {
    return '$name को सूची से हटाएँ? टिकटों पर नाम बना रहेगा।';
  }

  @override
  String get remove => 'हटाएँ';

  @override
  String stubsUsing(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count टिकटों पर',
      one: '1 टिकट पर',
      zero: 'इस्तेमाल नहीं हुआ',
    );
    return '$_temp0';
  }

  @override
  String get batchTitle => 'एक साथ जोड़ें';

  @override
  String get batchHint => 'हर पंक्ति में एक नाम। सही मिलान के लिए साल भी लिखें।';

  @override
  String get batchExample => 'Sholay 1975\nRRR (2022)\nPanchayat';

  @override
  String get batchMatch => 'नाम मिलाएँ';

  @override
  String batchAddAll(int count) {
    return '$count टिकट जोड़ें';
  }

  @override
  String get batchOwn => 'मिलान नहीं हुआ। आपकी अपनी फ़िल्म के रूप में जुड़ेगी।';

  @override
  String get batchDefaults => 'हर फ़िल्म के लिए';

  @override
  String batchDone(int count) {
    return '$count टिकट जुड़े';
  }

  @override
  String whatsNewTitle(String v) {
    return 'टॉकीज़ $v';
  }

  @override
  String get whatsNew1 =>
      'हर प्रीमियम फ़ीचर मुफ़्त है: पूरे समय के आँकड़े, असीमित टैग, 11 स्याही रंग, डार्क मोड, ऐप आइकन, शेयर पृष्ठभूमि और CSV एक्सपोर्ट।';

  @override
  String get whatsNew2 => 'हॉल की जानकारी दर्ज करें: शो, क्लास, सीट, फ़ॉर्मैट, टिकट का दाम और पहला दिन पहला शो।';

  @override
  String get whatsNew3 => '34,000 भारतीय और विदेशी टाइटल ऑफ़लाइन चलते हैं। ऑनलाइन होने पर नई रिलीज़ अपडेट होती हैं।';

  @override
  String get gotIt => 'ठीक है';
}
