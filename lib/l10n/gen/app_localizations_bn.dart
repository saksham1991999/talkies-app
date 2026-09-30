// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Bengali Bangla (`bn`).
class AppLocalizationsBn extends AppLocalizations {
  AppLocalizationsBn([String locale = 'bn']) : super(locale);

  @override
  String get appName => 'টকিজ';

  @override
  String get tabHome => 'হোম';

  @override
  String get tabStubs => 'টিকিট';

  @override
  String get tabCalendar => 'ক্যালেন্ডার';

  @override
  String get tabFilms => 'সিনেমা';

  @override
  String get tabStats => 'পরিসংখ্যান';

  @override
  String get recordFilm => 'সিনেমা যোগ করুন';

  @override
  String get search => 'খুঁজুন';

  @override
  String get cancel => 'বাতিল';

  @override
  String get save => 'সেভ করুন';

  @override
  String get delete => 'মুছুন';

  @override
  String get edit => 'এডিট করুন';

  @override
  String get done => 'হয়ে গেছে';

  @override
  String get undo => 'ফিরিয়ে আনুন';

  @override
  String get share => 'শেয়ার করুন';

  @override
  String get back => 'ফিরে যান';

  @override
  String get clear => 'মুছে দিন';

  @override
  String get settings => 'সেটিংস';

  @override
  String get previous => 'আগের';

  @override
  String get next => 'পরের';

  @override
  String unitFilms(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: 'সিনেমা', one: 'সিনেমা');
    return '$_temp0';
  }

  @override
  String get thisYear => 'এই বছর';

  @override
  String get recent => 'সাম্প্রতিক';

  @override
  String get allStubs => 'সব টিকিট';

  @override
  String get newReleases => 'নতুন রিলিজ';

  @override
  String get comingSoon => 'শীঘ্রই আসছে';

  @override
  String get forYou => 'আপনার জন্য';

  @override
  String becauseYouLiked(String title) {
    return 'আপনার $title ভালো লেগেছে বলে';
  }

  @override
  String get notInterested => 'আগ্রহ নেই';

  @override
  String get hiddenFromRecs => 'সুপারিশ থেকে লুকানো হয়েছে';

  @override
  String get seeAll => 'সব দেখুন';

  @override
  String get emptyHome => 'আপনার প্রথম টিকিট মাত্র একটা সিনেমা দূরে। + চাপুন আর সিনেমার নাম খুঁজুন।';

  @override
  String get venueCinema => 'সিনেমা হল';

  @override
  String get venueOtt => 'স্ট্রিমিং';

  @override
  String get venueHome => 'বাড়ি';

  @override
  String get venueTv => 'টিভি';

  @override
  String get venueOther => 'অন্যান্য';

  @override
  String get splitLegend => 'এই বছর কোথায় দেখেছেন';

  @override
  String ticketsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countটি টিকিট',
      one: '1টি টিকিট',
      zero: 'কোনো টিকিট নেই',
    );
    return '$_temp0';
  }

  @override
  String get sortNewest => 'নতুন আগে';

  @override
  String get sortOldest => 'পুরোনো আগে';

  @override
  String get sortRatingHigh => 'সবচেয়ে বেশি রেটিং';

  @override
  String get sortRatingLow => 'সবচেয়ে কম রেটিং';

  @override
  String get sort => 'সাজান';

  @override
  String get filter => 'ফিল্টার';

  @override
  String get filterAll => 'সব';

  @override
  String get filterPlace => 'জায়গা';

  @override
  String get filterTag => 'ট্যাগ';

  @override
  String get filterYear => 'বছর';

  @override
  String get filterKind => 'ধরন';

  @override
  String get filterRating => 'রেটিং';

  @override
  String get kindFilm => 'সিনেমা';

  @override
  String get kindSeries => 'সিরিজ';

  @override
  String get gridView => 'গ্রিড ভিউ';

  @override
  String get listView => 'লিস্ট ভিউ';

  @override
  String get searchStubs => 'আপনার টিকিট খুঁজুন';

  @override
  String get noStubs => 'এখনো কোনো টিকিট নেই। যে সিনেমাই যোগ করবেন, তা এখানে টিকিট হয়ে যাবে।';

  @override
  String get noMatch => 'এই ফিল্টারে কিছু পাওয়া যায়নি।';

  @override
  String get resetFilters => 'ফিল্টার সরান';

  @override
  String starsAtLeast(int stars) {
    return '$stars+ স্টার';
  }

  @override
  String calWatched(int count) {
    return '$countটি দেখা';
  }

  @override
  String calPlanned(int count) {
    return '$countটি ঠিক করা';
  }

  @override
  String get showStubs => 'টিকিট';

  @override
  String get showWatchlist => 'দেখার তালিকা';

  @override
  String get dayEmpty => 'এই দিনে কিছু নেই।';

  @override
  String get recordForDay => 'এই দিনের সিনেমা যোগ করুন';

  @override
  String get today => 'আজ';

  @override
  String get filmsNew => 'নতুন';

  @override
  String get filmsUpcoming => 'আসছে';

  @override
  String get filmsWant => 'দেখতে চাই';

  @override
  String get filmsRecorded => 'দেখা হয়েছে';

  @override
  String get filmsReleased => 'মুক্তি পেয়েছে';

  @override
  String get allLanguages => 'সব';

  @override
  String get wantEmpty => 'যে সিনেমা দেখতে চান, বুকমার্ক করুন। সেগুলো এখানে আর ক্যালেন্ডারে দেখা যাবে।';

  @override
  String get recordedEmpty => 'আপনার যোগ করা সিনেমা এখানে দেখা যাবে।';

  @override
  String get noReleases => 'অফলাইন তালিকায় এই ভাষার কোনো রিলিজ নেই। অনলাইন হলে সিনেমার তালিকা রিফ্রেশ করুন।';

  @override
  String get refreshNow => 'সিনেমার তালিকা রিফ্রেশ করুন';

  @override
  String get addedToWatchlist => 'দেখার তালিকায় যোগ হয়েছে';

  @override
  String get removedFromWatchlist => 'দেখার তালিকা থেকে সরানো হয়েছে';

  @override
  String watchCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count বার দেখেছেন', one: 'একবার দেখেছেন');
    return '$_temp0';
  }

  @override
  String get searchHint => 'সিনেমা, সিরিজ, অভিনেতা বা পরিচালক';

  @override
  String get searchAll => 'সব';

  @override
  String get notFound => 'তালিকায় নেই?';

  @override
  String get addManually => 'নিজেই যোগ করুন';

  @override
  String get loadingCatalog => 'সিনেমার তালিকা খুলছে';

  @override
  String get catalogError => 'সিনেমার তালিকা লোড হয়নি। অ্যাপটি আবার চালু করুন।';

  @override
  String searchPrompt(String count) {
    return '$countটি ভারতীয় ও বিদেশি টাইটেল খুঁজুন। অফলাইনেও চলে।';
  }

  @override
  String noResults(String query) {
    return '“$query” নামে কোনো টাইটেল পাওয়া যায়নি।';
  }

  @override
  String get director => 'পরিচালক';

  @override
  String get cast => 'অভিনয়ে';

  @override
  String get language => 'ভাষা';

  @override
  String get country => 'দেশ';

  @override
  String seasons(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$countটি সিজন', one: '1টি সিজন');
    return '$_temp0';
  }

  @override
  String get availableOn => 'যেখানে স্ট্রিম হচ্ছে';

  @override
  String get streamingHint => 'উইকিপিডিয়া থেকে। প্রাপ্যতা বদলাতে পারে।';

  @override
  String get synopsis => 'গল্প';

  @override
  String get synopsisOffline => 'গল্প দেখতে ইন্টারনেট লাগবে।';

  @override
  String get synopsisNone => 'গল্প পাওয়া যায়নি।';

  @override
  String get iWatched => 'আমি দেখেছি';

  @override
  String get watchedAgain => 'আবার দেখেছি';

  @override
  String get wantToWatch => 'দেখতে চাই';

  @override
  String get inWatchlist => 'তালিকায় আছে';

  @override
  String plannedFor(String date) {
    return '$date তারিখে ঠিক করা';
  }

  @override
  String get setPlannedDate => 'তারিখ ঠিক করুন';

  @override
  String get clearDate => 'তারিখ সরান';

  @override
  String get yourStubs => 'আপনার টিকিট';

  @override
  String get openWikipedia => 'Wikipedia-তে পড়ুন';

  @override
  String get fixOnWikidata => 'তথ্য ঠিক করুন';

  @override
  String get fixHint => 'সিনেমার তথ্য আসে Wikidata থেকে। সেখানে যে কেউ তা ঠিক করতে পারেন।';

  @override
  String get yourOwnFilm => 'আপনার যোগ করা';

  @override
  String watchNth(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n নম্বর বার',
      two: 'দ্বিতীয়বার',
      one: 'প্রথমবার',
    );
    return '$_temp0';
  }

  @override
  String hoursMinutes(int h, int m) {
    return '$h ঘ $m মি';
  }

  @override
  String minutesOnly(int m) {
    return '$m মিনিট';
  }

  @override
  String ticketNo(String no) {
    return 'নং $no';
  }

  @override
  String get ticket => 'টিকিট';

  @override
  String get admitOne => 'ADMIT ONE';

  @override
  String get stampWatched => 'WATCHED';

  @override
  String get fdfs => 'FDFS';

  @override
  String get labelDate => 'তারিখ';

  @override
  String get labelPlace => 'জায়গা';

  @override
  String get labelShow => 'শো';

  @override
  String get labelClass => 'ক্লাস';

  @override
  String get labelSeat => 'সিট';

  @override
  String get labelPrice => 'দাম';

  @override
  String get labelFormat => 'ফরম্যাট';

  @override
  String get labelLang => 'দেখার ভাষা';

  @override
  String get labelWith => 'কার সঙ্গে';

  @override
  String get labelRating => 'রেটিং';

  @override
  String get labelTags => 'ট্যাগ';

  @override
  String get labelMemo => 'নোট';

  @override
  String get dateUnknown => 'তারিখ মনে নেই';

  @override
  String get noRating => 'রেটিং নেই';

  @override
  String get tearUpQ => 'এই টিকিট ছিঁড়ে ফেলবেন?';

  @override
  String get tearUpBody => 'এতে এই বার দেখার রেকর্ড মুছে যাবে।';

  @override
  String get tearUp => 'ছিঁড়ে ফেলুন';

  @override
  String get stubDeleted => 'টিকিট ছেঁড়া হয়েছে';

  @override
  String get shareTicket => 'টিকিট শেয়ার করুন';

  @override
  String get recordTitle => 'নতুন টিকিট';

  @override
  String get editTitle => 'টিকিট এডিট করুন';

  @override
  String get whenWatched => 'কবে দেখেছেন?';

  @override
  String get precisionDay => 'দিন';

  @override
  String get precisionMonth => 'মাস';

  @override
  String get precisionYear => 'বছর';

  @override
  String get precisionNone => 'মনে নেই';

  @override
  String get yesterday => 'গতকাল';

  @override
  String get wherePlace => 'কোথায়?';

  @override
  String get addPlace => 'নতুন জায়গা';

  @override
  String get placeName => 'জায়গার নাম';

  @override
  String get placeNameHint => 'INOX, নন্দন, Netflix';

  @override
  String get placeType => 'ধরন';

  @override
  String get hallDetails => 'হলের তথ্য';

  @override
  String get show => 'শো';

  @override
  String get format => 'ফরম্যাট';

  @override
  String get seatClass => 'ক্লাস';

  @override
  String get seat => 'সিট';

  @override
  String get seatHint => 'H12';

  @override
  String get price => 'টিকিটের দাম (₹)';

  @override
  String get priceHint => '250';

  @override
  String get fdfsToggle => 'প্রথম দিন, প্রথম শো';

  @override
  String get watchedIn => 'কোন ভাষায় দেখেছেন';

  @override
  String get originalLang => 'মূল';

  @override
  String get withWhom => 'কার সঙ্গে দেখেছেন';

  @override
  String get withHint => 'বন্ধু, পরিবার, একা';

  @override
  String get rating => 'রেটিং';

  @override
  String get tags => 'ট্যাগ';

  @override
  String get addTag => 'নতুন ট্যাগ';

  @override
  String get tagHint => 'প্রিয়';

  @override
  String get memo => 'নোট';

  @override
  String get memoHint => 'কী মনে থেকে গেল?';

  @override
  String get stampIt => 'ছাপ মারুন';

  @override
  String get saveChanges => 'পরিবর্তন সেভ করুন';

  @override
  String get discardQ => 'এই টিকিট বাদ দেবেন?';

  @override
  String get discard => 'বাদ দিন';

  @override
  String get keepEditing => 'এডিট চালিয়ে যান';

  @override
  String get customTitle => 'নিজেই সিনেমা যোগ করুন';

  @override
  String get customName => 'নাম';

  @override
  String get customYear => 'বছর';

  @override
  String get customLang => 'ভাষা';

  @override
  String get customSeries => 'এটা একটা সিরিজ';

  @override
  String get customPoster => 'পোস্টার';

  @override
  String get choosePhoto => 'ছবি বেছে নিন';

  @override
  String get removePhoto => 'ছবি সরান';

  @override
  String get customSave => 'যোগ করে টিকিট বানান';

  @override
  String get customSaveWish => 'দেখার তালিকায় যোগ করুন';

  @override
  String get required => 'দরকারি';

  @override
  String yearInvalid(int max) {
    return '1900 থেকে $max-এর মধ্যে একটা বছর লিখুন';
  }

  @override
  String get statsTitle => 'পরিসংখ্যান';

  @override
  String get scopeMonth => 'মাস';

  @override
  String get scopeYear => 'বছর';

  @override
  String get scopeAll => 'সব সময়';

  @override
  String get totalStubs => 'টিকিট';

  @override
  String get totalTime => 'দেখার সময়';

  @override
  String get spent => 'টিকিটে খরচ';

  @override
  String avgTicket(String amount) {
    return 'গড়ে টিকিট প্রতি $amount';
  }

  @override
  String get fdfsCount => 'FDFS';

  @override
  String get rewatches => 'আবার দেখা';

  @override
  String get avgRating => 'গড় রেটিং';

  @override
  String get byDay => 'দিন অনুযায়ী';

  @override
  String get byMonth => 'মাস অনুযায়ী';

  @override
  String get byYear => 'বছর অনুযায়ী';

  @override
  String get byStars => 'রেটিং';

  @override
  String get byPlace => 'জায়গা';

  @override
  String get byVenueType => 'কোথায় দেখেন';

  @override
  String get byGenre => 'জনরা';

  @override
  String get byLanguage => 'ভাষা';

  @override
  String get byCountry => 'দেশ';

  @override
  String get byDecade => 'দশক';

  @override
  String get byDirector => 'সবচেয়ে বেশি দেখা পরিচালক';

  @override
  String get byActor => 'সবচেয়ে বেশি দেখা অভিনেতা';

  @override
  String get byTag => 'ট্যাগ';

  @override
  String get byFormat => 'ফরম্যাট';

  @override
  String get byShow => 'শো-এর সময়';

  @override
  String get statsEmpty => 'এই সময়ে কোনো টিকিট নেই।';

  @override
  String get tapForDetail => 'সিনেমাগুলো দেখতে কোনো বারে ট্যাপ করুন।';

  @override
  String showMore(int count) {
    return 'সব $countটি দেখান';
  }

  @override
  String get showLess => 'কম দেখান';

  @override
  String get unrated => 'রেটিং ছাড়া';

  @override
  String decadeLabel(String decade) {
    return '$decade-এর দশক';
  }

  @override
  String get shareTitle => 'ছবি শেয়ার করুন';

  @override
  String get background => 'ব্যাকগ্রাউন্ড';

  @override
  String get showTitles => 'নাম';

  @override
  String get showDates => 'তারিখ';

  @override
  String get showRatings => 'রেটিং';

  @override
  String get shareMonth => 'এই মাস শেয়ার করুন';

  @override
  String monthAtMovies(String month) {
    return '$month-এর সিনেমা';
  }

  @override
  String get nothingToShare => 'এই মাসে এখনো কোনো টিকিট নেই।';

  @override
  String get settingsTitle => 'সেটিংস';

  @override
  String get appearance => 'চেহারা';

  @override
  String get theme => 'থিম';

  @override
  String get themeSystem => 'সিস্টেম';

  @override
  String get themeLight => 'লাইট';

  @override
  String get themeDark => 'ডার্ক';

  @override
  String get accentColor => 'ছাপের কালি';

  @override
  String get accent_sindoor => 'সিঁদুর';

  @override
  String get accent_marigold => 'গাঁদা';

  @override
  String get accent_peacock => 'ময়ূরকণ্ঠী';

  @override
  String get accent_mehendi => 'মেহেন্দি';

  @override
  String get accent_neel => 'নীল';

  @override
  String get accent_jamun => 'জাম';

  @override
  String get accent_gulabi => 'গোলাপি';

  @override
  String get accent_kesar => 'জাফরান';

  @override
  String get accent_paan => 'পান';

  @override
  String get accent_chai => 'চা';

  @override
  String get accent_kajal => 'কাজল';

  @override
  String get appIcon => 'অ্যাপ আইকন';

  @override
  String get icon_default => 'গোলাপি টিকিট';

  @override
  String get icon_yellow => 'হলুদ টিকিট';

  @override
  String get icon_green => 'সবুজ টিকিট';

  @override
  String get icon_blue => 'নীল টিকিট';

  @override
  String get icon_night => 'নাইট শো';

  @override
  String get iconChanged => 'অ্যাপ আইকন বদলে গেছে';

  @override
  String get iconFailed => 'এই ডিভাইসে আইকন বদলানো যায়নি।';

  @override
  String get appLanguage => 'অ্যাপের ভাষা';

  @override
  String get languageSystem => 'ডিভাইসের ভাষা';

  @override
  String get calendarSection => 'ক্যালেন্ডার';

  @override
  String get weekStart => 'সপ্তাহ শুরু হয়';

  @override
  String get sunday => 'রবিবার';

  @override
  String get monday => 'সোমবার';

  @override
  String get ratingsSection => 'রেটিং';

  @override
  String get showRatingsToggle => 'স্টার রেটিং দেখান';

  @override
  String get releaseLists => 'নতুন ও আসন্ন তালিকা';

  @override
  String get releasesIndia => 'ভারতীয় সিনেমা';

  @override
  String get releasesWorld => 'সব সিনেমা';

  @override
  String get manageTags => 'ট্যাগ';

  @override
  String get manageVenues => 'জায়গা';

  @override
  String get dataSection => 'আপনার ডেটা';

  @override
  String get exportCsv => 'CSV এক্সপোর্ট করুন';

  @override
  String get importCsv => 'CSV ইমপোর্ট করুন';

  @override
  String get importHint => 'Talkies বা Letterboxd-এর CSV ফাইল';

  @override
  String get backup => 'সবকিছু ব্যাকআপ করুন';

  @override
  String get backupHint => 'একটা JSON ফাইল। Drive-এ রাখুন বা নিজেকে পাঠিয়ে দিন।';

  @override
  String get restore => 'ব্যাকআপ ফিরিয়ে আনুন';

  @override
  String get batchAdd => 'একসঙ্গে যোগ করুন';

  @override
  String get batchAddHint => 'নামের তালিকা পেস্ট করুন';

  @override
  String get refreshCatalog => 'সিনেমার তালিকা রিফ্রেশ করুন';

  @override
  String refreshedOn(String date, String updated) {
    return '$date-এ তৈরি। $updated-এ আপডেট হয়েছে।';
  }

  @override
  String builtOn(String date) {
    return '$date-এ তৈরি। এখনো রিফ্রেশ হয়নি।';
  }

  @override
  String refreshDone(int count) {
    return '$countটি নতুন ও আসন্ন সিনেমা আপডেট হয়েছে';
  }

  @override
  String get refreshFailed => 'রিফ্রেশ হয়নি। ইন্টারনেট সংযোগ দেখুন।';

  @override
  String get about => 'অ্যাপ সম্পর্কে';

  @override
  String get aboutBody =>
      'টকিজ ভারতীয় সিনেমাপ্রেমীদের টিকিট ডায়েরি। আপনার টিকিট এই ফোনেই থাকে। সিনেমার তথ্য আসে Wikidata (CC0) থেকে আর পোস্টার Wikipedia থেকে।';

  @override
  String version(String v) {
    return 'ভার্সন $v';
  }

  @override
  String get whatsNew => 'নতুন কী';

  @override
  String get privacyPolicy => 'গোপনীয়তা নীতি';

  @override
  String get replaceQ => 'সবকিছু এই ব্যাকআপ দিয়ে বদলে দেবেন?';

  @override
  String replaceBody(int count) {
    return 'আপনার এখনকার $countটি টিকিট ব্যাকআপ দিয়ে বদলে যাবে।';
  }

  @override
  String get replace => 'বদলে দিন';

  @override
  String get restoreDone => 'ব্যাকআপ ফিরে এসেছে';

  @override
  String get restoreFailed => 'এটা টকিজের ব্যাকআপ ফাইল নয়।';

  @override
  String imported(int count, int matched, int custom) {
    return '$countটি টিকিট যোগ হয়েছে। $matchedটি সিনেমার তালিকার সঙ্গে মিলেছে, $customটি আপনার নিজের সিনেমা হিসেবে যোগ হয়েছে।';
  }

  @override
  String get importNothing => 'এই ফাইলে কোনো সারি পাওয়া যায়নি।';

  @override
  String get nothingToExport => 'এক্সপোর্ট করার মতো এখনো কোনো টিকিট নেই।';

  @override
  String get tagsEmpty => 'এখনো কোনো ট্যাগ নেই। এখানে বা সিনেমা যোগ করার সময় একটা যোগ করুন।';

  @override
  String get renameTag => 'ট্যাগের নাম বদলান';

  @override
  String deleteTagQ(String tag, int count) {
    return '#$tag মুছবেন? এটা $countটি টিকিট থেকে সরে যাবে।';
  }

  @override
  String get editVenue => 'জায়গা এডিট করুন';

  @override
  String deleteVenueQ(String name) {
    return '$name তালিকা থেকে সরাবেন? টিকিটে নামটা থেকে যাবে।';
  }

  @override
  String get remove => 'সরান';

  @override
  String stubsUsing(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countটি টিকিটে আছে',
      one: '1টি টিকিটে আছে',
      zero: 'ব্যবহার হয়নি',
    );
    return '$_temp0';
  }

  @override
  String get batchTitle => 'একসঙ্গে যোগ করুন';

  @override
  String get batchHint => 'প্রতি লাইনে একটা নাম। ঠিকঠাক মেলাতে বছরও লিখুন।';

  @override
  String get batchExample => 'Sholay 1975\nRRR (2022)\nPanchayat';

  @override
  String get batchMatch => 'নাম মেলান';

  @override
  String batchAddAll(int count) {
    return '$countটি টিকিট যোগ করুন';
  }

  @override
  String get batchOwn => 'মেলেনি। আপনার নিজের সিনেমা হিসেবে যোগ হবে।';

  @override
  String get batchDefaults => 'প্রতিটা সিনেমার জন্য';

  @override
  String batchDone(int count) {
    return '$countটি টিকিট যোগ হয়েছে';
  }

  @override
  String whatsNewTitle(String v) {
    return 'টকিজ $v';
  }

  @override
  String get whatsNew1 =>
      'সব প্রিমিয়াম ফিচার এখন ফ্রি: সব সময়ের পরিসংখ্যান, যত খুশি ট্যাগ, 11টি ছাপের কালি, ডার্ক মোড, অ্যাপ আইকন, শেয়ারের ব্যাকগ্রাউন্ড আর CSV এক্সপোর্ট।';

  @override
  String get whatsNew2 => 'হলের তথ্য লিখে রাখুন: শো, ক্লাস, সিট, ফরম্যাট, টিকিটের দাম আর প্রথম দিন প্রথম শো।';

  @override
  String get whatsNew3 => '34,000 ভারতীয় ও বিদেশি টাইটেল অফলাইনে চলে। অনলাইন হলে নতুন রিলিজ রিফ্রেশ হয়।';

  @override
  String get gotIt => 'ঠিক আছে';
}
