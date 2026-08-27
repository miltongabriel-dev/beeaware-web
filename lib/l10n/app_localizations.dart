import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_pt.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
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
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

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
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('pt')
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'BeeAware'**
  String get appTitle;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @other.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get other;

  /// No description provided for @buyMore.
  ///
  /// In en, this message translates to:
  /// **'Buy more'**
  String get buyMore;

  /// No description provided for @filters.
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get filters;

  /// No description provided for @dataSources.
  ///
  /// In en, this message translates to:
  /// **'Data sources'**
  String get dataSources;

  /// No description provided for @aboutBeeAware.
  ///
  /// In en, this message translates to:
  /// **'About BeeAware'**
  String get aboutBeeAware;

  /// No description provided for @emergencyServices.
  ///
  /// In en, this message translates to:
  /// **'Emergency services'**
  String get emergencyServices;

  /// No description provided for @noDescriptionProvided.
  ///
  /// In en, this message translates to:
  /// **'No description provided.'**
  String get noDescriptionProvided;

  /// No description provided for @continueButton.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueButton;

  /// No description provided for @buyTokensButton.
  ///
  /// In en, this message translates to:
  /// **'Buy Tokens'**
  String get buyTokensButton;

  /// No description provided for @severityLow.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get severityLow;

  /// No description provided for @severityMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get severityMedium;

  /// No description provided for @severityHigh.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get severityHigh;

  /// No description provided for @severitySuffixed.
  ///
  /// In en, this message translates to:
  /// **'{severity, select, low{Low severity} medium{Medium severity} high{High severity} other{}}'**
  String severitySuffixed(String severity);

  /// No description provided for @relativeTimeJustNow.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get relativeTimeJustNow;

  /// No description provided for @relativeTimeMinutes.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} minute ago} other{{count} minutes ago}}'**
  String relativeTimeMinutes(int count);

  /// No description provided for @relativeTimeHours.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} hour ago} other{{count} hours ago}}'**
  String relativeTimeHours(int count);

  /// No description provided for @relativeTimeDays.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} day ago} other{{count} days ago}}'**
  String relativeTimeDays(int count);

  /// No description provided for @loginHeadline.
  ///
  /// In en, this message translates to:
  /// **'Stay aware.\nStay safe.'**
  String get loginHeadline;

  /// No description provided for @loginSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Private by design. No personal data required.\nCommunity and official data to help you make safer decisions.'**
  String get loginSubtitle;

  /// No description provided for @continueWithGoogle.
  ///
  /// In en, this message translates to:
  /// **'Continue with Google'**
  String get continueWithGoogle;

  /// No description provided for @continueWithApple.
  ///
  /// In en, this message translates to:
  /// **'Continue with Apple'**
  String get continueWithApple;

  /// No description provided for @appleSignInComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Apple sign-in coming soon'**
  String get appleSignInComingSoon;

  /// No description provided for @enterYourEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter your email'**
  String get enterYourEmail;

  /// No description provided for @sendMagicLink.
  ///
  /// In en, this message translates to:
  /// **'Send magic link'**
  String get sendMagicLink;

  /// No description provided for @privacyProtectedNotice.
  ///
  /// In en, this message translates to:
  /// **'Your privacy is protected. No personal data required.'**
  String get privacyProtectedNotice;

  /// No description provided for @checkEmailForLoginLink.
  ///
  /// In en, this message translates to:
  /// **'Check your email for the login link'**
  String get checkEmailForLoginLink;

  /// No description provided for @buyTokensSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose a plan and explore any area before you go.'**
  String get buyTokensSubtitle;

  /// No description provided for @packageSearches.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} search} other{{count} searches}}'**
  String packageSearches(int count);

  /// No description provided for @badgeMostPopular.
  ///
  /// In en, this message translates to:
  /// **'Most popular'**
  String get badgeMostPopular;

  /// No description provided for @badgeBestValue.
  ///
  /// In en, this message translates to:
  /// **'Best value'**
  String get badgeBestValue;

  /// No description provided for @pricePerSearch.
  ///
  /// In en, this message translates to:
  /// **'{price} per search'**
  String pricePerSearch(String price);

  /// No description provided for @bonusTokensNotice.
  ///
  /// In en, this message translates to:
  /// **'Bonus tokens — payments are not live yet.'**
  String get bonusTokensNotice;

  /// No description provided for @creditsAdded.
  ///
  /// In en, this message translates to:
  /// **'Credits added'**
  String get creditsAdded;

  /// No description provided for @whatHappenedTitle.
  ///
  /// In en, this message translates to:
  /// **'What happened?'**
  String get whatHappenedTitle;

  /// No description provided for @categoryHarassment.
  ///
  /// In en, this message translates to:
  /// **'Harassment'**
  String get categoryHarassment;

  /// No description provided for @categorySuspiciousActivity.
  ///
  /// In en, this message translates to:
  /// **'Suspicious activity'**
  String get categorySuspiciousActivity;

  /// No description provided for @categoryTheft.
  ///
  /// In en, this message translates to:
  /// **'Theft'**
  String get categoryTheft;

  /// No description provided for @categoryViolence.
  ///
  /// In en, this message translates to:
  /// **'Violence'**
  String get categoryViolence;

  /// No description provided for @categoryDrugs.
  ///
  /// In en, this message translates to:
  /// **'Drugs'**
  String get categoryDrugs;

  /// No description provided for @tellUsMoreTitle.
  ///
  /// In en, this message translates to:
  /// **'Tell us more'**
  String get tellUsMoreTitle;

  /// No description provided for @subHarassmentVerbal.
  ///
  /// In en, this message translates to:
  /// **'Verbal'**
  String get subHarassmentVerbal;

  /// No description provided for @subHarassmentPhysical.
  ///
  /// In en, this message translates to:
  /// **'Physical'**
  String get subHarassmentPhysical;

  /// No description provided for @subHarassmentOnline.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get subHarassmentOnline;

  /// No description provided for @subHarassmentStalking.
  ///
  /// In en, this message translates to:
  /// **'Stalking'**
  String get subHarassmentStalking;

  /// No description provided for @subHarassmentSexual.
  ///
  /// In en, this message translates to:
  /// **'Sexual'**
  String get subHarassmentSexual;

  /// No description provided for @subSuspiciousLoitering.
  ///
  /// In en, this message translates to:
  /// **'Loitering'**
  String get subSuspiciousLoitering;

  /// No description provided for @subSuspiciousFollowing.
  ///
  /// In en, this message translates to:
  /// **'Following someone'**
  String get subSuspiciousFollowing;

  /// No description provided for @subSuspiciousCars.
  ///
  /// In en, this message translates to:
  /// **'Looking into cars'**
  String get subSuspiciousCars;

  /// No description provided for @subSuspiciousDoors.
  ///
  /// In en, this message translates to:
  /// **'Checking doors'**
  String get subSuspiciousDoors;

  /// No description provided for @subTheftPickpocketing.
  ///
  /// In en, this message translates to:
  /// **'Pickpocketing'**
  String get subTheftPickpocketing;

  /// No description provided for @subTheftBike.
  ///
  /// In en, this message translates to:
  /// **'Bike theft'**
  String get subTheftBike;

  /// No description provided for @subTheftCarBreakIn.
  ///
  /// In en, this message translates to:
  /// **'Car break-in'**
  String get subTheftCarBreakIn;

  /// No description provided for @subTheftShoplifting.
  ///
  /// In en, this message translates to:
  /// **'Shoplifting'**
  String get subTheftShoplifting;

  /// No description provided for @subViolenceFight.
  ///
  /// In en, this message translates to:
  /// **'Fight'**
  String get subViolenceFight;

  /// No description provided for @subViolenceDomestic.
  ///
  /// In en, this message translates to:
  /// **'Domestic'**
  String get subViolenceDomestic;

  /// No description provided for @subViolenceWeapon.
  ///
  /// In en, this message translates to:
  /// **'Weapon involved'**
  String get subViolenceWeapon;

  /// No description provided for @subViolenceThreats.
  ///
  /// In en, this message translates to:
  /// **'Threats'**
  String get subViolenceThreats;

  /// No description provided for @subDrugsUse.
  ///
  /// In en, this message translates to:
  /// **'Use'**
  String get subDrugsUse;

  /// No description provided for @subDrugsDealing.
  ///
  /// In en, this message translates to:
  /// **'Dealing'**
  String get subDrugsDealing;

  /// No description provided for @subDrugsExchange.
  ///
  /// In en, this message translates to:
  /// **'Suspicious exchange'**
  String get subDrugsExchange;

  /// No description provided for @subDrugsNeedles.
  ///
  /// In en, this message translates to:
  /// **'Needles found'**
  String get subDrugsNeedles;

  /// No description provided for @howSeriousWasItTitle.
  ///
  /// In en, this message translates to:
  /// **'How serious was it?'**
  String get howSeriousWasItTitle;

  /// No description provided for @severityLowDesc.
  ///
  /// In en, this message translates to:
  /// **'Uncomfortable but no immediate danger'**
  String get severityLowDesc;

  /// No description provided for @severityMediumDesc.
  ///
  /// In en, this message translates to:
  /// **'Concerning and potentially unsafe'**
  String get severityMediumDesc;

  /// No description provided for @severityHighDesc.
  ///
  /// In en, this message translates to:
  /// **'Serious risk or immediate danger'**
  String get severityHighDesc;

  /// No description provided for @whenDidItHappenTitle.
  ///
  /// In en, this message translates to:
  /// **'When did it happen?'**
  String get whenDidItHappenTitle;

  /// No description provided for @adjustDateTimeHint.
  ///
  /// In en, this message translates to:
  /// **'You can adjust the date and time if you are reporting after the event.'**
  String get adjustDateTimeHint;

  /// No description provided for @dateLabel.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get dateLabel;

  /// No description provided for @timeLabel.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get timeLabel;

  /// No description provided for @reportVisibilityNotice.
  ///
  /// In en, this message translates to:
  /// **'This report will appear on the map in about {minutes, plural, one{1 minute} other{{minutes} minutes}}.'**
  String reportVisibilityNotice(int minutes);

  /// No description provided for @confirmReport.
  ///
  /// In en, this message translates to:
  /// **'Confirm report'**
  String get confirmReport;

  /// No description provided for @describeWhatHappenedTitle.
  ///
  /// In en, this message translates to:
  /// **'Describe what happened'**
  String get describeWhatHappenedTitle;

  /// No description provided for @addShortDescription.
  ///
  /// In en, this message translates to:
  /// **'Add a short description'**
  String get addShortDescription;

  /// No description provided for @descriptionHelperText.
  ///
  /// In en, this message translates to:
  /// **'This helps others understand the situation better.'**
  String get descriptionHelperText;

  /// No description provided for @descriptionHint.
  ///
  /// In en, this message translates to:
  /// **'Example: A group of people acting suspiciously near the station...'**
  String get descriptionHint;

  /// No description provided for @whereDidItHappenTitle.
  ///
  /// In en, this message translates to:
  /// **'Where did it happen?'**
  String get whereDidItHappenTitle;

  /// No description provided for @selectLocationOnMap.
  ///
  /// In en, this message translates to:
  /// **'Select a location on map'**
  String get selectLocationOnMap;

  /// No description provided for @reviewReportTitle.
  ///
  /// In en, this message translates to:
  /// **'Review report'**
  String get reviewReportTitle;

  /// No description provided for @missingSubcategory.
  ///
  /// In en, this message translates to:
  /// **'Missing subcategory. Please go back.'**
  String get missingSubcategory;

  /// No description provided for @missingLocation.
  ///
  /// In en, this message translates to:
  /// **'Missing location. Please go back.'**
  String get missingLocation;

  /// No description provided for @waitBeforeAnotherReport.
  ///
  /// In en, this message translates to:
  /// **'Please wait {minutes, plural, one{1 minute} other{{minutes} minutes}} before sending another report.'**
  String waitBeforeAnotherReport(int minutes);

  /// No description provided for @reportSubmittedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Thank you! Your report was submitted successfully.'**
  String get reportSubmittedSuccess;

  /// No description provided for @submitFailed.
  ///
  /// In en, this message translates to:
  /// **'Submit failed: {error}'**
  String submitFailed(String error);

  /// No description provided for @sectionCategory.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get sectionCategory;

  /// No description provided for @sectionSeverity.
  ///
  /// In en, this message translates to:
  /// **'Severity'**
  String get sectionSeverity;

  /// No description provided for @sectionDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get sectionDescription;

  /// No description provided for @sectionWhen.
  ///
  /// In en, this message translates to:
  /// **'When'**
  String get sectionWhen;

  /// No description provided for @mapVisibleNow.
  ///
  /// In en, this message translates to:
  /// **'This report is now visible on the map.'**
  String get mapVisibleNow;

  /// No description provided for @mapVisibleShortly.
  ///
  /// In en, this message translates to:
  /// **'This report will appear on the map shortly.'**
  String get mapVisibleShortly;

  /// No description provided for @submitReportAnonymously.
  ///
  /// In en, this message translates to:
  /// **'Submit report anonymously'**
  String get submitReportAnonymously;

  /// No description provided for @typeAddressToSearch.
  ///
  /// In en, this message translates to:
  /// **'Type an address to search.'**
  String get typeAddressToSearch;

  /// No description provided for @searchingNearMock.
  ///
  /// In en, this message translates to:
  /// **'Searching near: {query} (mock)'**
  String searchingNearMock(String query);

  /// No description provided for @noTokensLeftTitle.
  ///
  /// In en, this message translates to:
  /// **'No tokens left'**
  String get noTokensLeftTitle;

  /// No description provided for @noTokensLeftContent.
  ///
  /// In en, this message translates to:
  /// **'You have no search tokens remaining.\n\nBuy more tokens to continue searching.'**
  String get noTokensLeftContent;

  /// No description provided for @searchAddressTitle.
  ///
  /// In en, this message translates to:
  /// **'Search Address'**
  String get searchAddressTitle;

  /// No description provided for @tokensRemaining.
  ///
  /// In en, this message translates to:
  /// **'Tokens remaining: {count}'**
  String tokensRemaining(int count);

  /// No description provided for @addressOrPostcodeHint.
  ///
  /// In en, this message translates to:
  /// **'Address or postcode'**
  String get addressOrPostcodeHint;

  /// No description provided for @searchButton.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get searchButton;

  /// No description provided for @sourceLabel.
  ///
  /// In en, this message translates to:
  /// **'Source: {source}'**
  String sourceLabel(String source);

  /// No description provided for @incidentInfoDisclaimer.
  ///
  /// In en, this message translates to:
  /// **'Information from publicly available sources and community reports. For awareness only.'**
  String get incidentInfoDisclaimer;

  /// No description provided for @noDataAvailable.
  ///
  /// In en, this message translates to:
  /// **'No data available'**
  String get noDataAvailable;

  /// No description provided for @accountLabel.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get accountLabel;

  /// No description provided for @tokensCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} token} other{{count} tokens}}'**
  String tokensCount(int count);

  /// No description provided for @clusterNumbersExplained.
  ///
  /// In en, this message translates to:
  /// **'Cluster numbers explained'**
  String get clusterNumbersExplained;

  /// No description provided for @coverageGlobalBaselineOnly.
  ///
  /// In en, this message translates to:
  /// **'Only global baseline data is available here — that\'s not a guarantee of safety, just the best we have.'**
  String get coverageGlobalBaselineOnly;

  /// No description provided for @choroplethLegendTooltip.
  ///
  /// In en, this message translates to:
  /// **'Map legend'**
  String get choroplethLegendTooltip;

  /// No description provided for @choroplethLegendTitle.
  ///
  /// In en, this message translates to:
  /// **'What the colors mean'**
  String get choroplethLegendTitle;

  /// No description provided for @choroplethNoDataDisclaimer.
  ///
  /// In en, this message translates to:
  /// **'Areas with no color on the map have no public security data source. The absence of color doesn\'t mean the area is safe — only that police or local government haven\'t published that data yet.'**
  String get choroplethNoDataDisclaimer;

  /// No description provided for @loadingIncidents.
  ///
  /// In en, this message translates to:
  /// **'Loading incidents…'**
  String get loadingIncidents;

  /// No description provided for @noIncidentsForFilters.
  ///
  /// In en, this message translates to:
  /// **'No incidents match these filters'**
  String get noIncidentsForFilters;

  /// No description provided for @searchAnAddressHint.
  ///
  /// In en, this message translates to:
  /// **'Search an address'**
  String get searchAnAddressHint;

  /// No description provided for @tokensSearchBadge.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} search token} other{{count} search tokens}}'**
  String tokensSearchBadge(int count);

  /// No description provided for @oneSearchRemaining.
  ///
  /// In en, this message translates to:
  /// **'You have 1 search remaining'**
  String get oneSearchRemaining;

  /// No description provided for @allSearchesUsed.
  ///
  /// In en, this message translates to:
  /// **'You\'ve used all your searches'**
  String get allSearchesUsed;

  /// No description provided for @officialRecordDate.
  ///
  /// In en, this message translates to:
  /// **'Official Police Record · {month}/{year}'**
  String officialRecordDate(int month, int year);

  /// No description provided for @communityReportRelative.
  ///
  /// In en, this message translates to:
  /// **'Community Report · {relative}'**
  String communityReportRelative(String relative);

  /// No description provided for @clusterCountTitle.
  ///
  /// In en, this message translates to:
  /// **'Cluster count'**
  String get clusterCountTitle;

  /// No description provided for @clusterCountExplanation.
  ///
  /// In en, this message translates to:
  /// **'The number shown inside each cluster represents the total number of reported incidents in that area.'**
  String get clusterCountExplanation;

  /// No description provided for @callEmergencyNumber.
  ///
  /// In en, this message translates to:
  /// **'Call emergency ({number})'**
  String callEmergencyNumber(String number);

  /// No description provided for @callNonEmergencyNumber.
  ///
  /// In en, this message translates to:
  /// **'Call non-emergency ({number})'**
  String callNonEmergencyNumber(String number);

  /// No description provided for @emergencyDisclaimer.
  ///
  /// In en, this message translates to:
  /// **'BeeAware is not an emergency service.\nIf you are in immediate danger, contact emergency services directly.'**
  String get emergencyDisclaimer;

  /// No description provided for @sosBarLabel.
  ///
  /// In en, this message translates to:
  /// **'SOS {number}'**
  String sosBarLabel(String number);

  /// No description provided for @reportBarLabel.
  ///
  /// In en, this message translates to:
  /// **'Report'**
  String get reportBarLabel;

  /// No description provided for @filterTimeSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get filterTimeSectionTitle;

  /// No description provided for @timeFilterLastHour.
  ///
  /// In en, this message translates to:
  /// **'Last hour'**
  String get timeFilterLastHour;

  /// No description provided for @timeFilterLast6Hours.
  ///
  /// In en, this message translates to:
  /// **'Last 6 hours'**
  String get timeFilterLast6Hours;

  /// No description provided for @timeFilterLast24Hours.
  ///
  /// In en, this message translates to:
  /// **'Last 24 hours'**
  String get timeFilterLast24Hours;

  /// No description provided for @timeFilterAllTime.
  ///
  /// In en, this message translates to:
  /// **'All time'**
  String get timeFilterAllTime;

  /// No description provided for @distanceLabel.
  ///
  /// In en, this message translates to:
  /// **'Distance'**
  String get distanceLabel;

  /// No description provided for @distanceFilter250m.
  ///
  /// In en, this message translates to:
  /// **'Within 250 m'**
  String get distanceFilter250m;

  /// No description provided for @distanceFilter500m.
  ///
  /// In en, this message translates to:
  /// **'Within 500 m'**
  String get distanceFilter500m;

  /// No description provided for @distanceFilter1km.
  ///
  /// In en, this message translates to:
  /// **'Within 1 km'**
  String get distanceFilter1km;

  /// No description provided for @distanceFilterAny.
  ///
  /// In en, this message translates to:
  /// **'Any distance'**
  String get distanceFilterAny;

  /// No description provided for @applyFilters.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get applyFilters;

  /// No description provided for @clearFilters.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clearFilters;

  /// No description provided for @filterResultCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} incident} other{{count} incidents}}'**
  String filterResultCount(int count);

  /// No description provided for @aboutBodyText.
  ///
  /// In en, this message translates to:
  /// **'BeeAware is a community safety awareness platform designed to help people stay informed about non-emergency incidents in their local area.\n\nThe app combines community reports and publicly available official data to improve situational awareness and support safer daily decisions.\n\nInformation shown may be delayed, incomplete, or unverified and should not be used as a substitute for emergency services.\n\nBeeAware does not provide real-time monitoring and is not an emergency response system.'**
  String get aboutBodyText;

  /// No description provided for @aboutDataSourcesBody.
  ///
  /// In en, this message translates to:
  /// **'BeeAware displays safety information from two main sources:\n\n• Anonymous community reports submitted by users\n• Official open public data — government sources across the UK and Brazil (police, traffic safety, and public safety agencies), plus a coarse global baseline where local data isn\'t available yet\n\nThese sources are used to improve situational awareness and do not represent real-time alerts.'**
  String get aboutDataSourcesBody;

  /// No description provided for @privacyAnonymityTitle.
  ///
  /// In en, this message translates to:
  /// **'Privacy & anonymity'**
  String get privacyAnonymityTitle;

  /// No description provided for @privacyAnonymityBody.
  ///
  /// In en, this message translates to:
  /// **'BeeAware is designed with privacy by default.\nNo personal identifying information is required.\nReports are anonymous and location data is limited to what is necessary to display incidents on the map.'**
  String get privacyAnonymityBody;

  /// No description provided for @privacyPolicyButton.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get privacyPolicyButton;

  /// No description provided for @termsOfServiceButton.
  ///
  /// In en, this message translates to:
  /// **'Terms of Service'**
  String get termsOfServiceButton;

  /// No description provided for @copyrightBeeAware.
  ///
  /// In en, this message translates to:
  /// **'© BeeAware'**
  String get copyrightBeeAware;

  /// No description provided for @officialLegendBody.
  ///
  /// In en, this message translates to:
  /// **'BeeAware shows two types of reports:\n\n• Community reports (anonymous user submissions)\n• Official open data — public safety records from government sources across the UK and Brazil (police, traffic safety, and public safety agencies), plus a coarse global baseline where local data isn\'t available yet\n\nOfficial items are displayed with a distinct pin. They are included for situational awareness and are not real-time emergency alerts.'**
  String get officialLegendBody;

  /// No description provided for @signInToBeeAware.
  ///
  /// In en, this message translates to:
  /// **'Sign in to BeeAware'**
  String get signInToBeeAware;

  /// No description provided for @signedIn.
  ///
  /// In en, this message translates to:
  /// **'Signed in'**
  String get signedIn;

  /// No description provided for @secureLoginGoogleEmail.
  ///
  /// In en, this message translates to:
  /// **'Secure login · Google or Email'**
  String get secureLoginGoogleEmail;

  /// No description provided for @tokensAvailable.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} token available} other{{count} tokens available}}'**
  String tokensAvailable(int count);

  /// No description provided for @menuSectionAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get menuSectionAccount;

  /// No description provided for @menuSectionSupport.
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get menuSectionSupport;

  /// No description provided for @buyMoreCredits.
  ///
  /// In en, this message translates to:
  /// **'Buy more credits'**
  String get buyMoreCredits;

  /// No description provided for @alertsMonitoring.
  ///
  /// In en, this message translates to:
  /// **'Alerts & monitoring'**
  String get alertsMonitoring;

  /// No description provided for @privacyLabel.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get privacyLabel;

  /// No description provided for @languageLabel.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageLabel;

  /// No description provided for @languagePortuguese.
  ///
  /// In en, this message translates to:
  /// **'Português'**
  String get languagePortuguese;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageAutomatic.
  ///
  /// In en, this message translates to:
  /// **'Automatic (device)'**
  String get languageAutomatic;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOut;

  /// No description provided for @addressNotFound.
  ///
  /// In en, this message translates to:
  /// **'Address not found'**
  String get addressNotFound;

  /// No description provided for @noSearchTokensRemaining.
  ///
  /// In en, this message translates to:
  /// **'No search tokens remaining'**
  String get noSearchTokensRemaining;

  /// No description provided for @unlockUnlimitedInsights.
  ///
  /// In en, this message translates to:
  /// **'Unlock unlimited safety insights before you move or visit an area.'**
  String get unlockUnlimitedInsights;

  /// No description provided for @trendSubtitleWithMonth.
  ///
  /// In en, this message translates to:
  /// **'Police and community reports · up to {month} {year}'**
  String trendSubtitleWithMonth(String month, int year);

  /// No description provided for @trendSubtitleFallback.
  ///
  /// In en, this message translates to:
  /// **'Police and community reports · last 12 months'**
  String get trendSubtitleFallback;

  /// No description provided for @safetyTrendTitle.
  ///
  /// In en, this message translates to:
  /// **'Safety trend in this area'**
  String get safetyTrendTitle;

  /// No description provided for @safetyTrendShort.
  ///
  /// In en, this message translates to:
  /// **'Safety trend'**
  String get safetyTrendShort;

  /// No description provided for @incidentsWithin1Mile.
  ///
  /// In en, this message translates to:
  /// **'Incidents within 1 mile'**
  String get incidentsWithin1Mile;

  /// No description provided for @stayUpdatedInArea.
  ///
  /// In en, this message translates to:
  /// **'Stay updated in this area'**
  String get stayUpdatedInArea;

  /// No description provided for @alertOfferBody.
  ///
  /// In en, this message translates to:
  /// **'We noticed you are searching this area. Would you like to receive alerts about new incidents nearby?'**
  String get alertOfferBody;

  /// No description provided for @yesNotifyMe.
  ///
  /// In en, this message translates to:
  /// **'Yes, notify me'**
  String get yesNotifyMe;

  /// No description provided for @notNow.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get notNow;

  /// No description provided for @installAppTooltip.
  ///
  /// In en, this message translates to:
  /// **'Install App'**
  String get installAppTooltip;

  /// No description provided for @shareReportTooltip.
  ///
  /// In en, this message translates to:
  /// **'Share a local safety report'**
  String get shareReportTooltip;

  /// No description provided for @policeReportCategory.
  ///
  /// In en, this message translates to:
  /// **'Police report'**
  String get policeReportCategory;

  /// No description provided for @roadAccidentCategory.
  ///
  /// In en, this message translates to:
  /// **'Traffic accident'**
  String get roadAccidentCategory;

  /// No description provided for @officialEventDescription.
  ///
  /// In en, this message translates to:
  /// **'{type} in {city}, {state}.'**
  String officialEventDescription(String type, String city, String state);

  /// No description provided for @officialDescriptionWithOutcome.
  ///
  /// In en, this message translates to:
  /// **'Police recorded {category} near {street}. Outcome: {outcome}. Reported in {month}.'**
  String officialDescriptionWithOutcome(
      String category, String street, String outcome, String month);

  /// No description provided for @officialDescriptionNoOutcome.
  ///
  /// In en, this message translates to:
  /// **'Police recorded {category} near {street}. Reported in {month}.'**
  String officialDescriptionNoOutcome(
      String category, String street, String month);

  /// No description provided for @locationNotSpecified.
  ///
  /// In en, this message translates to:
  /// **'Location not specified'**
  String get locationNotSpecified;

  /// No description provided for @areaIntelligenceSafetyPulse.
  ///
  /// In en, this message translates to:
  /// **'Safety Pulse'**
  String get areaIntelligenceSafetyPulse;

  /// No description provided for @areaIntelligenceHistorical.
  ///
  /// In en, this message translates to:
  /// **'Historical Safety'**
  String get areaIntelligenceHistorical;

  /// No description provided for @areaIntelligenceHistoricalCaption.
  ///
  /// In en, this message translates to:
  /// **'12-month baseline, ranked against other cities in {state}'**
  String areaIntelligenceHistoricalCaption(String state);

  /// No description provided for @areaIntelligenceRecent.
  ///
  /// In en, this message translates to:
  /// **'Recent Activity'**
  String get areaIntelligenceRecent;

  /// No description provided for @areaIntelligenceRecentCaption.
  ///
  /// In en, this message translates to:
  /// **'Last 30 days vs. this city\'s own baseline'**
  String get areaIntelligenceRecentCaption;

  /// No description provided for @areaIntelligenceLive.
  ///
  /// In en, this message translates to:
  /// **'Live Awareness'**
  String get areaIntelligenceLive;

  /// No description provided for @areaIntelligenceLiveCaption.
  ///
  /// In en, this message translates to:
  /// **'Signals in the last 24h within {radius}'**
  String areaIntelligenceLiveCaption(String radius);

  /// No description provided for @areaIntelligenceNoData.
  ///
  /// In en, this message translates to:
  /// **'Not enough recent data yet'**
  String get areaIntelligenceNoData;

  /// No description provided for @areaIntelligenceSignalCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No signals} one{{count} signal} other{{count} signals}}'**
  String areaIntelligenceSignalCount(int count);

  /// No description provided for @areaIntelligenceDisclaimer.
  ///
  /// In en, this message translates to:
  /// **'An intelligence indicator built from official records — not a probability of personal safety. Coverage varies by source and is still being validated.'**
  String get areaIntelligenceDisclaimer;

  /// No description provided for @areaIntelligenceLoadError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load this area\'s data right now.'**
  String get areaIntelligenceLoadError;

  /// No description provided for @areaIntelligenceDistrictBreakdown.
  ///
  /// In en, this message translates to:
  /// **'Police District Breakdown'**
  String get areaIntelligenceDistrictBreakdown;

  /// No description provided for @areaIntelligenceDistrictCaption.
  ///
  /// In en, this message translates to:
  /// **'{district} — last 3 months'**
  String areaIntelligenceDistrictCaption(String district);

  /// No description provided for @areaIntelligenceDistrictViolence.
  ///
  /// In en, this message translates to:
  /// **'Violence'**
  String get areaIntelligenceDistrictViolence;

  /// No description provided for @areaIntelligenceDistrictProperty.
  ///
  /// In en, this message translates to:
  /// **'Property'**
  String get areaIntelligenceDistrictProperty;

  /// No description provided for @areaIntelligenceDistrictPublicSafety.
  ///
  /// In en, this message translates to:
  /// **'Public safety'**
  String get areaIntelligenceDistrictPublicSafety;

  /// No description provided for @areaIntelligenceDistrictTotal.
  ///
  /// In en, this message translates to:
  /// **'Total reports'**
  String get areaIntelligenceDistrictTotal;

  /// No description provided for @locationPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Location access is off — allow it to centre the map on you.'**
  String get locationPermissionDenied;

  /// No description provided for @locationPermissionBlocked.
  ///
  /// In en, this message translates to:
  /// **'Location is blocked for this site. Enable it in your browser\'s site settings.'**
  String get locationPermissionBlocked;

  /// No description provided for @locationPermissionError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t get your location right now.'**
  String get locationPermissionError;

  /// No description provided for @routeAwarenessTitle.
  ///
  /// In en, this message translates to:
  /// **'Route Awareness'**
  String get routeAwarenessTitle;

  /// No description provided for @routeAwarenessFromLabel.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get routeAwarenessFromLabel;

  /// No description provided for @routeAwarenessToLabel.
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get routeAwarenessToLabel;

  /// No description provided for @routeAwarenessFromHint.
  ///
  /// In en, this message translates to:
  /// **'Starting point'**
  String get routeAwarenessFromHint;

  /// No description provided for @routeAwarenessToHint.
  ///
  /// In en, this message translates to:
  /// **'Destination'**
  String get routeAwarenessToHint;

  /// No description provided for @routeAwarenessUseMyLocation.
  ///
  /// In en, this message translates to:
  /// **'Use my location'**
  String get routeAwarenessUseMyLocation;

  /// No description provided for @routeAwarenessSearchButton.
  ///
  /// In en, this message translates to:
  /// **'Find routes'**
  String get routeAwarenessSearchButton;

  /// No description provided for @routeAwarenessRouteLabel.
  ///
  /// In en, this message translates to:
  /// **'Route {letter}'**
  String routeAwarenessRouteLabel(String letter);

  /// No description provided for @routeAwarenessFastest.
  ///
  /// In en, this message translates to:
  /// **'Faster: {route}'**
  String routeAwarenessFastest(String route);

  /// No description provided for @routeAwarenessFewerSignals.
  ///
  /// In en, this message translates to:
  /// **'Fewer recent safety signals: {route}'**
  String routeAwarenessFewerSignals(String route);

  /// No description provided for @routeAwarenessSimilarSignals.
  ///
  /// In en, this message translates to:
  /// **'Similar recent activity on both routes'**
  String get routeAwarenessSimilarSignals;

  /// No description provided for @routeAwarenessNoRoutes.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t find a route between these points.'**
  String get routeAwarenessNoRoutes;

  /// No description provided for @routeAwarenessDisclaimer.
  ///
  /// In en, this message translates to:
  /// **'Compares routes by recent safety signals — not a guarantee that either route is safe.'**
  String get routeAwarenessDisclaimer;

  /// No description provided for @routeAwarenessMenuLabel.
  ///
  /// In en, this message translates to:
  /// **'Route Awareness'**
  String get routeAwarenessMenuLabel;

  /// No description provided for @myLocation.
  ///
  /// In en, this message translates to:
  /// **'My location'**
  String get myLocation;

  /// No description provided for @routeAwarenessOpenInApp.
  ///
  /// In en, this message translates to:
  /// **'Open this route in'**
  String get routeAwarenessOpenInApp;

  /// No description provided for @routeAwarenessGoogleMaps.
  ///
  /// In en, this message translates to:
  /// **'Google Maps'**
  String get routeAwarenessGoogleMaps;

  /// No description provided for @routeAwarenessWaze.
  ///
  /// In en, this message translates to:
  /// **'Waze'**
  String get routeAwarenessWaze;

  /// No description provided for @routeAwarenessAppleMaps.
  ///
  /// In en, this message translates to:
  /// **'Apple Maps'**
  String get routeAwarenessAppleMaps;

  /// No description provided for @homeGreeting.
  ///
  /// In en, this message translates to:
  /// **'Hello, {name}!'**
  String homeGreeting(String name);

  /// No description provided for @homeGreetingGeneric.
  ///
  /// In en, this message translates to:
  /// **'Hello!'**
  String get homeGreetingGeneric;

  /// No description provided for @homeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Stay informed and help your community.'**
  String get homeSubtitle;

  /// No description provided for @homeReportCta.
  ///
  /// In en, this message translates to:
  /// **'Share something important with the community.'**
  String get homeReportCta;

  /// No description provided for @exploreSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Explore'**
  String get exploreSectionTitle;

  /// No description provided for @mapPreviewOpenHint.
  ///
  /// In en, this message translates to:
  /// **'Tap to open the map'**
  String get mapPreviewOpenHint;

  /// No description provided for @homeLocationLoading.
  ///
  /// In en, this message translates to:
  /// **'Finding your location…'**
  String get homeLocationLoading;

  /// No description provided for @homeLocationUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Location unavailable'**
  String get homeLocationUnavailable;

  /// No description provided for @recentActivityEmpty.
  ///
  /// In en, this message translates to:
  /// **'No recent activity near you yet.'**
  String get recentActivityEmpty;

  /// No description provided for @distanceAway.
  ///
  /// In en, this message translates to:
  /// **'{distance} away'**
  String distanceAway(String distance);

  /// No description provided for @bottomNavHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get bottomNavHome;

  /// No description provided for @bottomNavMap.
  ///
  /// In en, this message translates to:
  /// **'Map'**
  String get bottomNavMap;

  /// No description provided for @bottomNavAlerts.
  ///
  /// In en, this message translates to:
  /// **'Alerts'**
  String get bottomNavAlerts;

  /// No description provided for @bottomNavProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get bottomNavProfile;

  /// No description provided for @alertsComingSoonTitle.
  ///
  /// In en, this message translates to:
  /// **'Alerts are coming soon'**
  String get alertsComingSoonTitle;

  /// No description provided for @alertsComingSoonBody.
  ///
  /// In en, this message translates to:
  /// **'We\'re building notifications for new incidents near you. Check back soon.'**
  String get alertsComingSoonBody;

  /// No description provided for @profileTitle.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profileTitle;

  /// No description provided for @newsSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'In the news — {state}'**
  String newsSectionTitle(String state);

  /// No description provided for @newsSectionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Wide-area news coverage, not your exact location.'**
  String get newsSectionSubtitle;

  /// No description provided for @newsSectionEmpty.
  ///
  /// In en, this message translates to:
  /// **'No recent news for this area.'**
  String get newsSectionEmpty;

  /// No description provided for @newsReadArticle.
  ///
  /// In en, this message translates to:
  /// **'Read article'**
  String get newsReadArticle;

  /// No description provided for @unitedKingdomLabel.
  ///
  /// In en, this message translates to:
  /// **'United Kingdom'**
  String get unitedKingdomLabel;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'pt'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'pt':
      return AppLocalizationsPt();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
