import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_bn.dart';
import 'app_localizations_en.dart';
import 'app_localizations_hi.dart';
import 'app_localizations_kn.dart';
import 'app_localizations_ml.dart';
import 'app_localizations_mr.dart';
import 'app_localizations_ta.dart';
import 'app_localizations_te.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('bn'),
    Locale('en'),
    Locale('hi'),
    Locale('kn'),
    Locale('ml'),
    Locale('mr'),
    Locale('ta'),
    Locale('te'),
  ];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'Talkies'**
  String get appName;

  /// No description provided for @tabHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get tabHome;

  /// No description provided for @tabStubs.
  ///
  /// In en, this message translates to:
  /// **'Stubs'**
  String get tabStubs;

  /// No description provided for @tabCalendar.
  ///
  /// In en, this message translates to:
  /// **'Calendar'**
  String get tabCalendar;

  /// No description provided for @tabFilms.
  ///
  /// In en, this message translates to:
  /// **'Films'**
  String get tabFilms;

  /// No description provided for @tabStats.
  ///
  /// In en, this message translates to:
  /// **'Stats'**
  String get tabStats;

  /// No description provided for @recordFilm.
  ///
  /// In en, this message translates to:
  /// **'Record a film'**
  String get recordFilm;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// No description provided for @share.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @previous.
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get previous;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @unitFilms.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{film} other{films}}'**
  String unitFilms(int count);

  /// No description provided for @thisYear.
  ///
  /// In en, this message translates to:
  /// **'This year'**
  String get thisYear;

  /// No description provided for @recent.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get recent;

  /// No description provided for @allStubs.
  ///
  /// In en, this message translates to:
  /// **'All stubs'**
  String get allStubs;

  /// No description provided for @newReleases.
  ///
  /// In en, this message translates to:
  /// **'New releases'**
  String get newReleases;

  /// No description provided for @comingSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get comingSoon;

  /// No description provided for @seeAll.
  ///
  /// In en, this message translates to:
  /// **'See all'**
  String get seeAll;

  /// No description provided for @emptyHome.
  ///
  /// In en, this message translates to:
  /// **'Your first ticket is one film away. Tap + and search for a title.'**
  String get emptyHome;

  /// No description provided for @venueCinema.
  ///
  /// In en, this message translates to:
  /// **'Cinema hall'**
  String get venueCinema;

  /// No description provided for @venueOtt.
  ///
  /// In en, this message translates to:
  /// **'Streaming'**
  String get venueOtt;

  /// No description provided for @venueHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get venueHome;

  /// No description provided for @venueTv.
  ///
  /// In en, this message translates to:
  /// **'TV'**
  String get venueTv;

  /// No description provided for @venueOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get venueOther;

  /// No description provided for @splitLegend.
  ///
  /// In en, this message translates to:
  /// **'Where you watched this year'**
  String get splitLegend;

  /// No description provided for @ticketsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No tickets} =1{1 ticket} other{{count} tickets}}'**
  String ticketsCount(int count);

  /// No description provided for @sortNewest.
  ///
  /// In en, this message translates to:
  /// **'Newest first'**
  String get sortNewest;

  /// No description provided for @sortOldest.
  ///
  /// In en, this message translates to:
  /// **'Oldest first'**
  String get sortOldest;

  /// No description provided for @sortRatingHigh.
  ///
  /// In en, this message translates to:
  /// **'Highest rated'**
  String get sortRatingHigh;

  /// No description provided for @sortRatingLow.
  ///
  /// In en, this message translates to:
  /// **'Lowest rated'**
  String get sortRatingLow;

  /// No description provided for @sort.
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get sort;

  /// No description provided for @filter.
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get filter;

  /// No description provided for @filterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get filterAll;

  /// No description provided for @filterPlace.
  ///
  /// In en, this message translates to:
  /// **'Place'**
  String get filterPlace;

  /// No description provided for @filterTag.
  ///
  /// In en, this message translates to:
  /// **'Tag'**
  String get filterTag;

  /// No description provided for @filterYear.
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get filterYear;

  /// No description provided for @filterKind.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get filterKind;

  /// No description provided for @filterRating.
  ///
  /// In en, this message translates to:
  /// **'Rating'**
  String get filterRating;

  /// No description provided for @kindFilm.
  ///
  /// In en, this message translates to:
  /// **'Films'**
  String get kindFilm;

  /// No description provided for @kindSeries.
  ///
  /// In en, this message translates to:
  /// **'Series'**
  String get kindSeries;

  /// No description provided for @gridView.
  ///
  /// In en, this message translates to:
  /// **'Grid view'**
  String get gridView;

  /// No description provided for @listView.
  ///
  /// In en, this message translates to:
  /// **'List view'**
  String get listView;

  /// No description provided for @searchStubs.
  ///
  /// In en, this message translates to:
  /// **'Search your stubs'**
  String get searchStubs;

  /// No description provided for @noStubs.
  ///
  /// In en, this message translates to:
  /// **'No stubs yet. Every film you record becomes a ticket here.'**
  String get noStubs;

  /// No description provided for @noMatch.
  ///
  /// In en, this message translates to:
  /// **'Nothing matches these filters.'**
  String get noMatch;

  /// No description provided for @resetFilters.
  ///
  /// In en, this message translates to:
  /// **'Reset filters'**
  String get resetFilters;

  /// No description provided for @starsAtLeast.
  ///
  /// In en, this message translates to:
  /// **'{stars}+ stars'**
  String starsAtLeast(int stars);

  /// No description provided for @calWatched.
  ///
  /// In en, this message translates to:
  /// **'{count} watched'**
  String calWatched(int count);

  /// No description provided for @calPlanned.
  ///
  /// In en, this message translates to:
  /// **'{count} planned'**
  String calPlanned(int count);

  /// No description provided for @showStubs.
  ///
  /// In en, this message translates to:
  /// **'Stubs'**
  String get showStubs;

  /// No description provided for @showWatchlist.
  ///
  /// In en, this message translates to:
  /// **'Watchlist'**
  String get showWatchlist;

  /// No description provided for @dayEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing on this day.'**
  String get dayEmpty;

  /// No description provided for @recordForDay.
  ///
  /// In en, this message translates to:
  /// **'Record a film on this day'**
  String get recordForDay;

  /// No description provided for @today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// No description provided for @filmsNew.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get filmsNew;

  /// No description provided for @filmsUpcoming.
  ///
  /// In en, this message translates to:
  /// **'Upcoming'**
  String get filmsUpcoming;

  /// No description provided for @filmsWant.
  ///
  /// In en, this message translates to:
  /// **'Want'**
  String get filmsWant;

  /// No description provided for @filmsRecorded.
  ///
  /// In en, this message translates to:
  /// **'Recorded'**
  String get filmsRecorded;

  /// No description provided for @filmsReleased.
  ///
  /// In en, this message translates to:
  /// **'Out now'**
  String get filmsReleased;

  /// No description provided for @allLanguages.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get allLanguages;

  /// No description provided for @wantEmpty.
  ///
  /// In en, this message translates to:
  /// **'Bookmark films you want to watch. They show here and on your calendar.'**
  String get wantEmpty;

  /// No description provided for @recordedEmpty.
  ///
  /// In en, this message translates to:
  /// **'Films you record show here.'**
  String get recordedEmpty;

  /// No description provided for @noReleases.
  ///
  /// In en, this message translates to:
  /// **'No releases in the offline list for this language. Refresh the film list when you are online.'**
  String get noReleases;

  /// No description provided for @refreshNow.
  ///
  /// In en, this message translates to:
  /// **'Refresh film list'**
  String get refreshNow;

  /// No description provided for @addedToWatchlist.
  ///
  /// In en, this message translates to:
  /// **'Added to watchlist'**
  String get addedToWatchlist;

  /// No description provided for @removedFromWatchlist.
  ///
  /// In en, this message translates to:
  /// **'Removed from watchlist'**
  String get removedFromWatchlist;

  /// No description provided for @watchCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Watched once} other{Watched {count} times}}'**
  String watchCount(int count);

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Film, series, actor or director'**
  String get searchHint;

  /// No description provided for @searchAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get searchAll;

  /// No description provided for @notFound.
  ///
  /// In en, this message translates to:
  /// **'Not in the list?'**
  String get notFound;

  /// No description provided for @addManually.
  ///
  /// In en, this message translates to:
  /// **'Add it yourself'**
  String get addManually;

  /// No description provided for @loadingCatalog.
  ///
  /// In en, this message translates to:
  /// **'Opening the film list'**
  String get loadingCatalog;

  /// No description provided for @catalogError.
  ///
  /// In en, this message translates to:
  /// **'The film list did not load. Restart the app.'**
  String get catalogError;

  /// No description provided for @searchPrompt.
  ///
  /// In en, this message translates to:
  /// **'Search {count} Indian and world titles. Works offline.'**
  String searchPrompt(String count);

  /// No description provided for @noResults.
  ///
  /// In en, this message translates to:
  /// **'No title matches “{query}”.'**
  String noResults(String query);

  /// No description provided for @director.
  ///
  /// In en, this message translates to:
  /// **'Director'**
  String get director;

  /// No description provided for @cast.
  ///
  /// In en, this message translates to:
  /// **'Cast'**
  String get cast;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @country.
  ///
  /// In en, this message translates to:
  /// **'Country'**
  String get country;

  /// No description provided for @seasons.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 season} other{{count} seasons}}'**
  String seasons(int count);

  /// No description provided for @availableOn.
  ///
  /// In en, this message translates to:
  /// **'Streaming on'**
  String get availableOn;

  /// No description provided for @streamingHint.
  ///
  /// In en, this message translates to:
  /// **'From Wikipedia. Availability can change.'**
  String get streamingHint;

  /// No description provided for @synopsis.
  ///
  /// In en, this message translates to:
  /// **'Synopsis'**
  String get synopsis;

  /// No description provided for @synopsisOffline.
  ///
  /// In en, this message translates to:
  /// **'The synopsis needs an internet connection.'**
  String get synopsisOffline;

  /// No description provided for @synopsisNone.
  ///
  /// In en, this message translates to:
  /// **'No synopsis found.'**
  String get synopsisNone;

  /// No description provided for @iWatched.
  ///
  /// In en, this message translates to:
  /// **'I watched it'**
  String get iWatched;

  /// No description provided for @watchedAgain.
  ///
  /// In en, this message translates to:
  /// **'Watched again'**
  String get watchedAgain;

  /// No description provided for @wantToWatch.
  ///
  /// In en, this message translates to:
  /// **'Want to watch'**
  String get wantToWatch;

  /// No description provided for @inWatchlist.
  ///
  /// In en, this message translates to:
  /// **'In watchlist'**
  String get inWatchlist;

  /// No description provided for @plannedFor.
  ///
  /// In en, this message translates to:
  /// **'Planned for {date}'**
  String plannedFor(String date);

  /// No description provided for @setPlannedDate.
  ///
  /// In en, this message translates to:
  /// **'Plan a date'**
  String get setPlannedDate;

  /// No description provided for @clearDate.
  ///
  /// In en, this message translates to:
  /// **'Clear date'**
  String get clearDate;

  /// No description provided for @yourStubs.
  ///
  /// In en, this message translates to:
  /// **'Your stubs'**
  String get yourStubs;

  /// No description provided for @openWikipedia.
  ///
  /// In en, this message translates to:
  /// **'Read on Wikipedia'**
  String get openWikipedia;

  /// No description provided for @fixOnWikidata.
  ///
  /// In en, this message translates to:
  /// **'Correct these details'**
  String get fixOnWikidata;

  /// No description provided for @fixHint.
  ///
  /// In en, this message translates to:
  /// **'Film details come from Wikidata. Anyone can correct them there.'**
  String get fixHint;

  /// No description provided for @yourOwnFilm.
  ///
  /// In en, this message translates to:
  /// **'Added by you'**
  String get yourOwnFilm;

  /// No description provided for @watchNth.
  ///
  /// In en, this message translates to:
  /// **'{n, plural, =1{First watch} =2{Second watch} other{Watch no. {n}}}'**
  String watchNth(int n);

  /// No description provided for @hoursMinutes.
  ///
  /// In en, this message translates to:
  /// **'{h}h {m}m'**
  String hoursMinutes(int h, int m);

  /// No description provided for @minutesOnly.
  ///
  /// In en, this message translates to:
  /// **'{m} min'**
  String minutesOnly(int m);

  /// No description provided for @ticketNo.
  ///
  /// In en, this message translates to:
  /// **'No. {no}'**
  String ticketNo(String no);

  /// No description provided for @ticket.
  ///
  /// In en, this message translates to:
  /// **'Ticket'**
  String get ticket;

  /// No description provided for @admitOne.
  ///
  /// In en, this message translates to:
  /// **'ADMIT ONE'**
  String get admitOne;

  /// No description provided for @stampWatched.
  ///
  /// In en, this message translates to:
  /// **'WATCHED'**
  String get stampWatched;

  /// No description provided for @fdfs.
  ///
  /// In en, this message translates to:
  /// **'FDFS'**
  String get fdfs;

  /// No description provided for @labelDate.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get labelDate;

  /// No description provided for @labelPlace.
  ///
  /// In en, this message translates to:
  /// **'Place'**
  String get labelPlace;

  /// No description provided for @labelShow.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get labelShow;

  /// No description provided for @labelClass.
  ///
  /// In en, this message translates to:
  /// **'Class'**
  String get labelClass;

  /// No description provided for @labelSeat.
  ///
  /// In en, this message translates to:
  /// **'Seat'**
  String get labelSeat;

  /// No description provided for @labelPrice.
  ///
  /// In en, this message translates to:
  /// **'Price'**
  String get labelPrice;

  /// No description provided for @labelFormat.
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get labelFormat;

  /// No description provided for @labelLang.
  ///
  /// In en, this message translates to:
  /// **'Watched in'**
  String get labelLang;

  /// No description provided for @labelWith.
  ///
  /// In en, this message translates to:
  /// **'With'**
  String get labelWith;

  /// No description provided for @labelRating.
  ///
  /// In en, this message translates to:
  /// **'Rating'**
  String get labelRating;

  /// No description provided for @labelTags.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get labelTags;

  /// No description provided for @labelMemo.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get labelMemo;

  /// No description provided for @dateUnknown.
  ///
  /// In en, this message translates to:
  /// **'Date not remembered'**
  String get dateUnknown;

  /// No description provided for @noRating.
  ///
  /// In en, this message translates to:
  /// **'No rating'**
  String get noRating;

  /// No description provided for @tearUpQ.
  ///
  /// In en, this message translates to:
  /// **'Tear up this stub?'**
  String get tearUpQ;

  /// No description provided for @tearUpBody.
  ///
  /// In en, this message translates to:
  /// **'This deletes the record of this viewing.'**
  String get tearUpBody;

  /// No description provided for @tearUp.
  ///
  /// In en, this message translates to:
  /// **'Tear up'**
  String get tearUp;

  /// No description provided for @stubDeleted.
  ///
  /// In en, this message translates to:
  /// **'Stub torn up'**
  String get stubDeleted;

  /// No description provided for @shareTicket.
  ///
  /// In en, this message translates to:
  /// **'Share ticket'**
  String get shareTicket;

  /// No description provided for @recordTitle.
  ///
  /// In en, this message translates to:
  /// **'New stub'**
  String get recordTitle;

  /// No description provided for @editTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit stub'**
  String get editTitle;

  /// No description provided for @whenWatched.
  ///
  /// In en, this message translates to:
  /// **'When did you watch it?'**
  String get whenWatched;

  /// No description provided for @precisionDay.
  ///
  /// In en, this message translates to:
  /// **'Day'**
  String get precisionDay;

  /// No description provided for @precisionMonth.
  ///
  /// In en, this message translates to:
  /// **'Month'**
  String get precisionMonth;

  /// No description provided for @precisionYear.
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get precisionYear;

  /// No description provided for @precisionNone.
  ///
  /// In en, this message translates to:
  /// **'Don\'t remember'**
  String get precisionNone;

  /// No description provided for @yesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get yesterday;

  /// No description provided for @wherePlace.
  ///
  /// In en, this message translates to:
  /// **'Where?'**
  String get wherePlace;

  /// No description provided for @addPlace.
  ///
  /// In en, this message translates to:
  /// **'New place'**
  String get addPlace;

  /// No description provided for @placeName.
  ///
  /// In en, this message translates to:
  /// **'Place name'**
  String get placeName;

  /// No description provided for @placeNameHint.
  ///
  /// In en, this message translates to:
  /// **'PVR Phoenix, Maratha Mandir, Netflix'**
  String get placeNameHint;

  /// No description provided for @placeType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get placeType;

  /// No description provided for @hallDetails.
  ///
  /// In en, this message translates to:
  /// **'Hall details'**
  String get hallDetails;

  /// No description provided for @show.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get show;

  /// No description provided for @format.
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get format;

  /// No description provided for @seatClass.
  ///
  /// In en, this message translates to:
  /// **'Class'**
  String get seatClass;

  /// No description provided for @seat.
  ///
  /// In en, this message translates to:
  /// **'Seat'**
  String get seat;

  /// No description provided for @seatHint.
  ///
  /// In en, this message translates to:
  /// **'H12'**
  String get seatHint;

  /// No description provided for @price.
  ///
  /// In en, this message translates to:
  /// **'Ticket price (₹)'**
  String get price;

  /// No description provided for @priceHint.
  ///
  /// In en, this message translates to:
  /// **'250'**
  String get priceHint;

  /// No description provided for @fdfsToggle.
  ///
  /// In en, this message translates to:
  /// **'First day, first show'**
  String get fdfsToggle;

  /// No description provided for @watchedIn.
  ///
  /// In en, this message translates to:
  /// **'Watched in'**
  String get watchedIn;

  /// No description provided for @originalLang.
  ///
  /// In en, this message translates to:
  /// **'Original'**
  String get originalLang;

  /// No description provided for @withWhom.
  ///
  /// In en, this message translates to:
  /// **'Watched with'**
  String get withWhom;

  /// No description provided for @withHint.
  ///
  /// In en, this message translates to:
  /// **'Friends, family, alone'**
  String get withHint;

  /// No description provided for @rating.
  ///
  /// In en, this message translates to:
  /// **'Rating'**
  String get rating;

  /// No description provided for @tags.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get tags;

  /// No description provided for @addTag.
  ///
  /// In en, this message translates to:
  /// **'New tag'**
  String get addTag;

  /// No description provided for @tagHint.
  ///
  /// In en, this message translates to:
  /// **'favourite'**
  String get tagHint;

  /// No description provided for @memo.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get memo;

  /// No description provided for @memoHint.
  ///
  /// In en, this message translates to:
  /// **'What stayed with you?'**
  String get memoHint;

  /// No description provided for @stampIt.
  ///
  /// In en, this message translates to:
  /// **'Stamp it'**
  String get stampIt;

  /// No description provided for @saveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get saveChanges;

  /// No description provided for @discardQ.
  ///
  /// In en, this message translates to:
  /// **'Discard this stub?'**
  String get discardQ;

  /// No description provided for @discard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discard;

  /// No description provided for @keepEditing.
  ///
  /// In en, this message translates to:
  /// **'Keep editing'**
  String get keepEditing;

  /// No description provided for @customTitle.
  ///
  /// In en, this message translates to:
  /// **'Add a film yourself'**
  String get customTitle;

  /// No description provided for @customName.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get customName;

  /// No description provided for @customYear.
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get customYear;

  /// No description provided for @customLang.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get customLang;

  /// No description provided for @customSeries.
  ///
  /// In en, this message translates to:
  /// **'It is a series'**
  String get customSeries;

  /// No description provided for @customPoster.
  ///
  /// In en, this message translates to:
  /// **'Poster'**
  String get customPoster;

  /// No description provided for @choosePhoto.
  ///
  /// In en, this message translates to:
  /// **'Choose photo'**
  String get choosePhoto;

  /// No description provided for @removePhoto.
  ///
  /// In en, this message translates to:
  /// **'Remove photo'**
  String get removePhoto;

  /// No description provided for @customSave.
  ///
  /// In en, this message translates to:
  /// **'Add and record'**
  String get customSave;

  /// No description provided for @customSaveWish.
  ///
  /// In en, this message translates to:
  /// **'Add to watchlist'**
  String get customSaveWish;

  /// No description provided for @required.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get required;

  /// No description provided for @yearInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a year from 1900 to {max}'**
  String yearInvalid(int max);

  /// No description provided for @statsTitle.
  ///
  /// In en, this message translates to:
  /// **'Stats'**
  String get statsTitle;

  /// No description provided for @scopeMonth.
  ///
  /// In en, this message translates to:
  /// **'Month'**
  String get scopeMonth;

  /// No description provided for @scopeYear.
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get scopeYear;

  /// No description provided for @scopeAll.
  ///
  /// In en, this message translates to:
  /// **'All time'**
  String get scopeAll;

  /// No description provided for @totalStubs.
  ///
  /// In en, this message translates to:
  /// **'Stubs'**
  String get totalStubs;

  /// No description provided for @totalTime.
  ///
  /// In en, this message translates to:
  /// **'Watch time'**
  String get totalTime;

  /// No description provided for @spent.
  ///
  /// In en, this message translates to:
  /// **'Spent on tickets'**
  String get spent;

  /// No description provided for @avgTicket.
  ///
  /// In en, this message translates to:
  /// **'{amount} per ticket on average'**
  String avgTicket(String amount);

  /// No description provided for @fdfsCount.
  ///
  /// In en, this message translates to:
  /// **'FDFS'**
  String get fdfsCount;

  /// No description provided for @rewatches.
  ///
  /// In en, this message translates to:
  /// **'Rewatches'**
  String get rewatches;

  /// No description provided for @avgRating.
  ///
  /// In en, this message translates to:
  /// **'Average rating'**
  String get avgRating;

  /// No description provided for @byDay.
  ///
  /// In en, this message translates to:
  /// **'By day'**
  String get byDay;

  /// No description provided for @byMonth.
  ///
  /// In en, this message translates to:
  /// **'By month'**
  String get byMonth;

  /// No description provided for @byYear.
  ///
  /// In en, this message translates to:
  /// **'By year'**
  String get byYear;

  /// No description provided for @byStars.
  ///
  /// In en, this message translates to:
  /// **'Ratings'**
  String get byStars;

  /// No description provided for @byPlace.
  ///
  /// In en, this message translates to:
  /// **'Places'**
  String get byPlace;

  /// No description provided for @byVenueType.
  ///
  /// In en, this message translates to:
  /// **'Where you watch'**
  String get byVenueType;

  /// No description provided for @byGenre.
  ///
  /// In en, this message translates to:
  /// **'Genres'**
  String get byGenre;

  /// No description provided for @byLanguage.
  ///
  /// In en, this message translates to:
  /// **'Languages'**
  String get byLanguage;

  /// No description provided for @byCountry.
  ///
  /// In en, this message translates to:
  /// **'Countries'**
  String get byCountry;

  /// No description provided for @byDecade.
  ///
  /// In en, this message translates to:
  /// **'Decades'**
  String get byDecade;

  /// No description provided for @byDirector.
  ///
  /// In en, this message translates to:
  /// **'Directors you watch most'**
  String get byDirector;

  /// No description provided for @byActor.
  ///
  /// In en, this message translates to:
  /// **'Actors you watch most'**
  String get byActor;

  /// No description provided for @byTag.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get byTag;

  /// No description provided for @byFormat.
  ///
  /// In en, this message translates to:
  /// **'Formats'**
  String get byFormat;

  /// No description provided for @byShow.
  ///
  /// In en, this message translates to:
  /// **'Show times'**
  String get byShow;

  /// No description provided for @statsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No stubs in this period.'**
  String get statsEmpty;

  /// No description provided for @tapForDetail.
  ///
  /// In en, this message translates to:
  /// **'Tap a bar to see its films.'**
  String get tapForDetail;

  /// No description provided for @showMore.
  ///
  /// In en, this message translates to:
  /// **'Show all {count}'**
  String showMore(int count);

  /// No description provided for @showLess.
  ///
  /// In en, this message translates to:
  /// **'Show less'**
  String get showLess;

  /// No description provided for @unrated.
  ///
  /// In en, this message translates to:
  /// **'Unrated'**
  String get unrated;

  /// No description provided for @decadeLabel.
  ///
  /// In en, this message translates to:
  /// **'{decade}s'**
  String decadeLabel(String decade);

  /// No description provided for @shareTitle.
  ///
  /// In en, this message translates to:
  /// **'Share image'**
  String get shareTitle;

  /// No description provided for @background.
  ///
  /// In en, this message translates to:
  /// **'Background'**
  String get background;

  /// No description provided for @showTitles.
  ///
  /// In en, this message translates to:
  /// **'Titles'**
  String get showTitles;

  /// No description provided for @showDates.
  ///
  /// In en, this message translates to:
  /// **'Dates'**
  String get showDates;

  /// No description provided for @showRatings.
  ///
  /// In en, this message translates to:
  /// **'Ratings'**
  String get showRatings;

  /// No description provided for @shareMonth.
  ///
  /// In en, this message translates to:
  /// **'Share this month'**
  String get shareMonth;

  /// No description provided for @monthAtMovies.
  ///
  /// In en, this message translates to:
  /// **'{month} at the movies'**
  String monthAtMovies(String month);

  /// No description provided for @nothingToShare.
  ///
  /// In en, this message translates to:
  /// **'No stubs this month yet.'**
  String get nothingToShare;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @accentColor.
  ///
  /// In en, this message translates to:
  /// **'Stamp ink'**
  String get accentColor;

  /// No description provided for @accent_sindoor.
  ///
  /// In en, this message translates to:
  /// **'Sindoor'**
  String get accent_sindoor;

  /// No description provided for @accent_marigold.
  ///
  /// In en, this message translates to:
  /// **'Marigold'**
  String get accent_marigold;

  /// No description provided for @accent_peacock.
  ///
  /// In en, this message translates to:
  /// **'Peacock'**
  String get accent_peacock;

  /// No description provided for @accent_mehendi.
  ///
  /// In en, this message translates to:
  /// **'Mehendi'**
  String get accent_mehendi;

  /// No description provided for @accent_neel.
  ///
  /// In en, this message translates to:
  /// **'Neel'**
  String get accent_neel;

  /// No description provided for @accent_jamun.
  ///
  /// In en, this message translates to:
  /// **'Jamun'**
  String get accent_jamun;

  /// No description provided for @accent_gulabi.
  ///
  /// In en, this message translates to:
  /// **'Gulabi'**
  String get accent_gulabi;

  /// No description provided for @accent_kesar.
  ///
  /// In en, this message translates to:
  /// **'Kesar'**
  String get accent_kesar;

  /// No description provided for @accent_paan.
  ///
  /// In en, this message translates to:
  /// **'Paan'**
  String get accent_paan;

  /// No description provided for @accent_chai.
  ///
  /// In en, this message translates to:
  /// **'Chai'**
  String get accent_chai;

  /// No description provided for @accent_kajal.
  ///
  /// In en, this message translates to:
  /// **'Kajal'**
  String get accent_kajal;

  /// No description provided for @appIcon.
  ///
  /// In en, this message translates to:
  /// **'App icon'**
  String get appIcon;

  /// No description provided for @icon_default.
  ///
  /// In en, this message translates to:
  /// **'Pink ticket'**
  String get icon_default;

  /// No description provided for @icon_yellow.
  ///
  /// In en, this message translates to:
  /// **'Yellow ticket'**
  String get icon_yellow;

  /// No description provided for @icon_green.
  ///
  /// In en, this message translates to:
  /// **'Green ticket'**
  String get icon_green;

  /// No description provided for @icon_blue.
  ///
  /// In en, this message translates to:
  /// **'Blue ticket'**
  String get icon_blue;

  /// No description provided for @icon_night.
  ///
  /// In en, this message translates to:
  /// **'Night show'**
  String get icon_night;

  /// No description provided for @iconChanged.
  ///
  /// In en, this message translates to:
  /// **'App icon changed'**
  String get iconChanged;

  /// No description provided for @iconFailed.
  ///
  /// In en, this message translates to:
  /// **'This device did not change the icon.'**
  String get iconFailed;

  /// No description provided for @appLanguage.
  ///
  /// In en, this message translates to:
  /// **'App language'**
  String get appLanguage;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'Device language'**
  String get languageSystem;

  /// No description provided for @calendarSection.
  ///
  /// In en, this message translates to:
  /// **'Calendar'**
  String get calendarSection;

  /// No description provided for @weekStart.
  ///
  /// In en, this message translates to:
  /// **'Week starts on'**
  String get weekStart;

  /// No description provided for @sunday.
  ///
  /// In en, this message translates to:
  /// **'Sunday'**
  String get sunday;

  /// No description provided for @monday.
  ///
  /// In en, this message translates to:
  /// **'Monday'**
  String get monday;

  /// No description provided for @ratingsSection.
  ///
  /// In en, this message translates to:
  /// **'Ratings'**
  String get ratingsSection;

  /// No description provided for @showRatingsToggle.
  ///
  /// In en, this message translates to:
  /// **'Show star ratings'**
  String get showRatingsToggle;

  /// No description provided for @releaseLists.
  ///
  /// In en, this message translates to:
  /// **'New and upcoming lists'**
  String get releaseLists;

  /// No description provided for @releasesIndia.
  ///
  /// In en, this message translates to:
  /// **'Indian films'**
  String get releasesIndia;

  /// No description provided for @releasesWorld.
  ///
  /// In en, this message translates to:
  /// **'All films'**
  String get releasesWorld;

  /// No description provided for @manageTags.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get manageTags;

  /// No description provided for @manageVenues.
  ///
  /// In en, this message translates to:
  /// **'Places'**
  String get manageVenues;

  /// No description provided for @dataSection.
  ///
  /// In en, this message translates to:
  /// **'Your data'**
  String get dataSection;

  /// No description provided for @exportCsv.
  ///
  /// In en, this message translates to:
  /// **'Export CSV'**
  String get exportCsv;

  /// No description provided for @importCsv.
  ///
  /// In en, this message translates to:
  /// **'Import CSV'**
  String get importCsv;

  /// No description provided for @importHint.
  ///
  /// In en, this message translates to:
  /// **'A Talkies or Letterboxd CSV file'**
  String get importHint;

  /// No description provided for @backup.
  ///
  /// In en, this message translates to:
  /// **'Back up everything'**
  String get backup;

  /// No description provided for @backupHint.
  ///
  /// In en, this message translates to:
  /// **'One JSON file. Keep it in Drive or send it to yourself.'**
  String get backupHint;

  /// No description provided for @restore.
  ///
  /// In en, this message translates to:
  /// **'Restore a backup'**
  String get restore;

  /// No description provided for @batchAdd.
  ///
  /// In en, this message translates to:
  /// **'Quick add'**
  String get batchAdd;

  /// No description provided for @batchAddHint.
  ///
  /// In en, this message translates to:
  /// **'Paste a list of titles'**
  String get batchAddHint;

  /// No description provided for @refreshCatalog.
  ///
  /// In en, this message translates to:
  /// **'Refresh film list'**
  String get refreshCatalog;

  /// No description provided for @refreshedOn.
  ///
  /// In en, this message translates to:
  /// **'Built {date}. Updated {updated}.'**
  String refreshedOn(String date, String updated);

  /// No description provided for @builtOn.
  ///
  /// In en, this message translates to:
  /// **'Built {date}. Not refreshed yet.'**
  String builtOn(String date);

  /// No description provided for @refreshDone.
  ///
  /// In en, this message translates to:
  /// **'{count} recent and upcoming films updated'**
  String refreshDone(int count);

  /// No description provided for @refreshFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not refresh. Check the connection.'**
  String get refreshFailed;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @aboutBody.
  ///
  /// In en, this message translates to:
  /// **'Talkies is a ticket diary for Indian film lovers. Your stubs stay on this phone. Film details come from Wikidata (CC0) and posters from Wikipedia.'**
  String get aboutBody;

  /// No description provided for @version.
  ///
  /// In en, this message translates to:
  /// **'Version {v}'**
  String version(String v);

  /// No description provided for @whatsNew.
  ///
  /// In en, this message translates to:
  /// **'What\'s new'**
  String get whatsNew;

  /// No description provided for @privacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy policy'**
  String get privacyPolicy;

  /// No description provided for @replaceQ.
  ///
  /// In en, this message translates to:
  /// **'Replace everything with this backup?'**
  String get replaceQ;

  /// No description provided for @replaceBody.
  ///
  /// In en, this message translates to:
  /// **'Your current {count} stubs will be replaced by the backup.'**
  String replaceBody(int count);

  /// No description provided for @replace.
  ///
  /// In en, this message translates to:
  /// **'Replace'**
  String get replace;

  /// No description provided for @restoreDone.
  ///
  /// In en, this message translates to:
  /// **'Backup restored'**
  String get restoreDone;

  /// No description provided for @restoreFailed.
  ///
  /// In en, this message translates to:
  /// **'This file is not a Talkies backup.'**
  String get restoreFailed;

  /// No description provided for @imported.
  ///
  /// In en, this message translates to:
  /// **'{count} stubs added. {matched} matched the film list, {custom} added as your own films.'**
  String imported(int count, int matched, int custom);

  /// No description provided for @importNothing.
  ///
  /// In en, this message translates to:
  /// **'No rows found in this file.'**
  String get importNothing;

  /// No description provided for @nothingToExport.
  ///
  /// In en, this message translates to:
  /// **'No stubs to export yet.'**
  String get nothingToExport;

  /// No description provided for @tagsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No tags yet. Add one here or while you record a film.'**
  String get tagsEmpty;

  /// No description provided for @renameTag.
  ///
  /// In en, this message translates to:
  /// **'Rename tag'**
  String get renameTag;

  /// No description provided for @deleteTagQ.
  ///
  /// In en, this message translates to:
  /// **'Delete #{tag}? It is removed from {count} stubs.'**
  String deleteTagQ(String tag, int count);

  /// No description provided for @editVenue.
  ///
  /// In en, this message translates to:
  /// **'Edit place'**
  String get editVenue;

  /// No description provided for @deleteVenueQ.
  ///
  /// In en, this message translates to:
  /// **'Remove {name} from the list? Stubs keep the name.'**
  String deleteVenueQ(String name);

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @stubsUsing.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Not used} =1{Used on 1 stub} other{Used on {count} stubs}}'**
  String stubsUsing(int count);

  /// No description provided for @batchTitle.
  ///
  /// In en, this message translates to:
  /// **'Quick add'**
  String get batchTitle;

  /// No description provided for @batchHint.
  ///
  /// In en, this message translates to:
  /// **'One title per line. Add a year to be exact.'**
  String get batchHint;

  /// No description provided for @batchExample.
  ///
  /// In en, this message translates to:
  /// **'Sholay 1975\nRRR (2022)\nPanchayat'**
  String get batchExample;

  /// No description provided for @batchMatch.
  ///
  /// In en, this message translates to:
  /// **'Match titles'**
  String get batchMatch;

  /// No description provided for @batchAddAll.
  ///
  /// In en, this message translates to:
  /// **'Add {count} stubs'**
  String batchAddAll(int count);

  /// No description provided for @batchOwn.
  ///
  /// In en, this message translates to:
  /// **'No match. Added as your own film.'**
  String get batchOwn;

  /// No description provided for @batchDefaults.
  ///
  /// In en, this message translates to:
  /// **'For every film'**
  String get batchDefaults;

  /// No description provided for @batchDone.
  ///
  /// In en, this message translates to:
  /// **'{count} stubs added'**
  String batchDone(int count);

  /// No description provided for @whatsNewTitle.
  ///
  /// In en, this message translates to:
  /// **'Talkies {v}'**
  String whatsNewTitle(String v);

  /// No description provided for @whatsNew1.
  ///
  /// In en, this message translates to:
  /// **'Every premium feature is free: all-time stats, unlimited tags, 11 stamp inks, dark mode, app icons, share backgrounds and CSV export.'**
  String get whatsNew1;

  /// No description provided for @whatsNew2.
  ///
  /// In en, this message translates to:
  /// **'Record hall details: show, class, seat, format, ticket price and first day first show.'**
  String get whatsNew2;

  /// No description provided for @whatsNew3.
  ///
  /// In en, this message translates to:
  /// **'34,000 Indian and world titles work offline. New releases refresh when you are online.'**
  String get whatsNew3;

  /// No description provided for @gotIt.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get gotIt;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['bn', 'en', 'hi', 'kn', 'ml', 'mr', 'ta', 'te'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'bn':
      return AppLocalizationsBn();
    case 'en':
      return AppLocalizationsEn();
    case 'hi':
      return AppLocalizationsHi();
    case 'kn':
      return AppLocalizationsKn();
    case 'ml':
      return AppLocalizationsMl();
    case 'mr':
      return AppLocalizationsMr();
    case 'ta':
      return AppLocalizationsTa();
    case 'te':
      return AppLocalizationsTe();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
