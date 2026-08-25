// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'BeeAware';

  @override
  String get close => 'Close';

  @override
  String get cancel => 'Cancel';

  @override
  String get other => 'Other';

  @override
  String get buyMore => 'Buy more';

  @override
  String get filters => 'Filters';

  @override
  String get dataSources => 'Data sources';

  @override
  String get aboutBeeAware => 'About BeeAware';

  @override
  String get emergencyServices => 'Emergency services';

  @override
  String get noDescriptionProvided => 'No description provided.';

  @override
  String get continueButton => 'Continue';

  @override
  String get buyTokensButton => 'Buy Tokens';

  @override
  String get severityLow => 'Low';

  @override
  String get severityMedium => 'Medium';

  @override
  String get severityHigh => 'High';

  @override
  String severitySuffixed(String severity) {
    String _temp0 = intl.Intl.selectLogic(
      severity,
      {
        'low': 'Low severity',
        'medium': 'Medium severity',
        'high': 'High severity',
        'other': '',
      },
    );
    return '$_temp0';
  }

  @override
  String get relativeTimeJustNow => 'Just now';

  @override
  String relativeTimeMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count minutes ago',
      one: '$count minute ago',
    );
    return '$_temp0';
  }

  @override
  String relativeTimeHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hours ago',
      one: '$count hour ago',
    );
    return '$_temp0';
  }

  @override
  String relativeTimeDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days ago',
      one: '$count day ago',
    );
    return '$_temp0';
  }

  @override
  String get loginHeadline => 'Stay aware.\nStay safe.';

  @override
  String get loginSubtitle =>
      'Private by design. No personal data required.\nCommunity and official data to help you make safer decisions.';

  @override
  String get continueWithGoogle => 'Continue with Google';

  @override
  String get continueWithApple => 'Continue with Apple';

  @override
  String get appleSignInComingSoon => 'Apple sign-in coming soon';

  @override
  String get enterYourEmail => 'Enter your email';

  @override
  String get sendMagicLink => 'Send magic link';

  @override
  String get privacyProtectedNotice =>
      'Your privacy is protected. No personal data required.';

  @override
  String get checkEmailForLoginLink => 'Check your email for the login link';

  @override
  String get buyTokensSubtitle =>
      'Choose a plan and explore any area before you go.';

  @override
  String packageSearches(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count searches',
      one: '$count search',
    );
    return '$_temp0';
  }

  @override
  String get badgeMostPopular => 'Most popular';

  @override
  String get badgeBestValue => 'Best value';

  @override
  String pricePerSearch(String price) {
    return '$price per search';
  }

  @override
  String get bonusTokensNotice => 'Bonus tokens — payments are not live yet.';

  @override
  String get creditsAdded => 'Credits added';

  @override
  String get whatHappenedTitle => 'What happened?';

  @override
  String get categoryHarassment => 'Harassment';

  @override
  String get categorySuspiciousActivity => 'Suspicious activity';

  @override
  String get categoryTheft => 'Theft';

  @override
  String get categoryViolence => 'Violence';

  @override
  String get categoryDrugs => 'Drugs';

  @override
  String get tellUsMoreTitle => 'Tell us more';

  @override
  String get subHarassmentVerbal => 'Verbal';

  @override
  String get subHarassmentPhysical => 'Physical';

  @override
  String get subHarassmentOnline => 'Online';

  @override
  String get subHarassmentStalking => 'Stalking';

  @override
  String get subHarassmentSexual => 'Sexual';

  @override
  String get subSuspiciousLoitering => 'Loitering';

  @override
  String get subSuspiciousFollowing => 'Following someone';

  @override
  String get subSuspiciousCars => 'Looking into cars';

  @override
  String get subSuspiciousDoors => 'Checking doors';

  @override
  String get subTheftPickpocketing => 'Pickpocketing';

  @override
  String get subTheftBike => 'Bike theft';

  @override
  String get subTheftCarBreakIn => 'Car break-in';

  @override
  String get subTheftShoplifting => 'Shoplifting';

  @override
  String get subViolenceFight => 'Fight';

  @override
  String get subViolenceDomestic => 'Domestic';

  @override
  String get subViolenceWeapon => 'Weapon involved';

  @override
  String get subViolenceThreats => 'Threats';

  @override
  String get subDrugsUse => 'Use';

  @override
  String get subDrugsDealing => 'Dealing';

  @override
  String get subDrugsExchange => 'Suspicious exchange';

  @override
  String get subDrugsNeedles => 'Needles found';

  @override
  String get howSeriousWasItTitle => 'How serious was it?';

  @override
  String get severityLowDesc => 'Uncomfortable but no immediate danger';

  @override
  String get severityMediumDesc => 'Concerning and potentially unsafe';

  @override
  String get severityHighDesc => 'Serious risk or immediate danger';

  @override
  String get whenDidItHappenTitle => 'When did it happen?';

  @override
  String get adjustDateTimeHint =>
      'You can adjust the date and time if you are reporting after the event.';

  @override
  String get dateLabel => 'Date';

  @override
  String get timeLabel => 'Time';

  @override
  String reportVisibilityNotice(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes minutes',
      one: '1 minute',
    );
    return 'This report will appear on the map in about $_temp0.';
  }

  @override
  String get confirmReport => 'Confirm report';

  @override
  String get describeWhatHappenedTitle => 'Describe what happened';

  @override
  String get addShortDescription => 'Add a short description';

  @override
  String get descriptionHelperText =>
      'This helps others understand the situation better.';

  @override
  String get descriptionHint =>
      'Example: A group of people acting suspiciously near the station...';

  @override
  String get whereDidItHappenTitle => 'Where did it happen?';

  @override
  String get selectLocationOnMap => 'Select a location on map';

  @override
  String get reviewReportTitle => 'Review report';

  @override
  String get missingSubcategory => 'Missing subcategory. Please go back.';

  @override
  String get missingLocation => 'Missing location. Please go back.';

  @override
  String waitBeforeAnotherReport(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes minutes',
      one: '1 minute',
    );
    return 'Please wait $_temp0 before sending another report.';
  }

  @override
  String get reportSubmittedSuccess =>
      'Thank you! Your report was submitted successfully.';

  @override
  String submitFailed(String error) {
    return 'Submit failed: $error';
  }

  @override
  String get sectionCategory => 'Category';

  @override
  String get sectionSeverity => 'Severity';

  @override
  String get sectionDescription => 'Description';

  @override
  String get sectionWhen => 'When';

  @override
  String get mapVisibleNow => 'This report is now visible on the map.';

  @override
  String get mapVisibleShortly => 'This report will appear on the map shortly.';

  @override
  String get submitReportAnonymously => 'Submit report anonymously';

  @override
  String get typeAddressToSearch => 'Type an address to search.';

  @override
  String searchingNearMock(String query) {
    return 'Searching near: $query (mock)';
  }

  @override
  String get noTokensLeftTitle => 'No tokens left';

  @override
  String get noTokensLeftContent =>
      'You have no search tokens remaining.\n\nBuy more tokens to continue searching.';

  @override
  String get searchAddressTitle => 'Search Address';

  @override
  String tokensRemaining(int count) {
    return 'Tokens remaining: $count';
  }

  @override
  String get addressOrPostcodeHint => 'Address or postcode';

  @override
  String get searchButton => 'Search';

  @override
  String sourceLabel(String source) {
    return 'Source: $source';
  }

  @override
  String get incidentInfoDisclaimer =>
      'Information from publicly available sources and community reports. For awareness only.';

  @override
  String get noDataAvailable => 'No data available';

  @override
  String get accountLabel => 'Account';

  @override
  String tokensCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tokens',
      one: '$count token',
    );
    return '$_temp0';
  }

  @override
  String get reportingHintText => 'Spot something? Tap the Bee.';

  @override
  String get clusterNumbersExplained => 'Cluster numbers explained';

  @override
  String get coverageGlobalBaselineOnly =>
      'Only global baseline data is available here — that\'s not a guarantee of safety, just the best we have.';

  @override
  String get choroplethLegendTooltip => 'Map legend';

  @override
  String get choroplethLegendTitle => 'What the colors mean';

  @override
  String get choroplethNoDataDisclaimer =>
      'Areas with no color on the map have no public security data source. The absence of color doesn\'t mean the area is safe — only that police or local government haven\'t published that data yet.';

  @override
  String get loadingIncidents => 'Loading incidents…';

  @override
  String get noIncidentsForFilters => 'No incidents match these filters';

  @override
  String get searchAnAddressHint => 'Search an address';

  @override
  String tokensSearchBadge(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count search tokens',
      one: '$count search token',
    );
    return '$_temp0';
  }

  @override
  String get oneSearchRemaining => 'You have 1 search remaining';

  @override
  String get allSearchesUsed => 'You\'ve used all your searches';

  @override
  String officialRecordDate(int month, int year) {
    return 'Official Police Record · $month/$year';
  }

  @override
  String communityReportRelative(String relative) {
    return 'Community Report · $relative';
  }

  @override
  String get clusterCountTitle => 'Cluster count';

  @override
  String get clusterCountExplanation =>
      'The number shown inside each cluster represents the total number of reported incidents in that area.';

  @override
  String callEmergencyNumber(String number) {
    return 'Call emergency ($number)';
  }

  @override
  String callNonEmergencyNumber(String number) {
    return 'Call non-emergency ($number)';
  }

  @override
  String get emergencyDisclaimer =>
      'BeeAware is not an emergency service.\nIf you are in immediate danger, contact emergency services directly.';

  @override
  String sosBarLabel(String number) {
    return 'SOS $number';
  }

  @override
  String get reportBarLabel => 'Report';

  @override
  String get filterTimeSectionTitle => 'Time';

  @override
  String get timeFilterLastHour => 'Last hour';

  @override
  String get timeFilterLast6Hours => 'Last 6 hours';

  @override
  String get timeFilterLast24Hours => 'Last 24 hours';

  @override
  String get timeFilterAllTime => 'All time';

  @override
  String get distanceLabel => 'Distance';

  @override
  String get distanceFilter250m => 'Within 250 m';

  @override
  String get distanceFilter500m => 'Within 500 m';

  @override
  String get distanceFilter1km => 'Within 1 km';

  @override
  String get distanceFilterAny => 'Any distance';

  @override
  String get applyFilters => 'Apply';

  @override
  String get clearFilters => 'Clear';

  @override
  String filterResultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count incidents',
      one: '$count incident',
    );
    return '$_temp0';
  }

  @override
  String get aboutBodyText =>
      'BeeAware is a community safety awareness platform designed to help people stay informed about non-emergency incidents in their local area.\n\nThe app combines community reports and publicly available official data to improve situational awareness and support safer daily decisions.\n\nInformation shown may be delayed, incomplete, or unverified and should not be used as a substitute for emergency services.\n\nBeeAware does not provide real-time monitoring and is not an emergency response system.';

  @override
  String get aboutDataSourcesBody =>
      'BeeAware displays safety information from two main sources:\n\n• Anonymous community reports submitted by users\n• Official open public data — government sources across the UK and Brazil (police, traffic safety, and public safety agencies), plus a coarse global baseline where local data isn\'t available yet\n\nThese sources are used to improve situational awareness and do not represent real-time alerts.';

  @override
  String get privacyAnonymityTitle => 'Privacy & anonymity';

  @override
  String get privacyAnonymityBody =>
      'BeeAware is designed with privacy by default.\nNo personal identifying information is required.\nReports are anonymous and location data is limited to what is necessary to display incidents on the map.';

  @override
  String get privacyPolicyButton => 'Privacy Policy';

  @override
  String get termsOfServiceButton => 'Terms of Service';

  @override
  String get copyrightBeeAware => '© BeeAware';

  @override
  String get officialLegendBody =>
      'BeeAware shows two types of reports:\n\n• Community reports (anonymous user submissions)\n• Official open data — public safety records from government sources across the UK and Brazil (police, traffic safety, and public safety agencies), plus a coarse global baseline where local data isn\'t available yet\n\nOfficial items are displayed with a distinct pin. They are included for situational awareness and are not real-time emergency alerts.';

  @override
  String get signInToBeeAware => 'Sign in to BeeAware';

  @override
  String get signedIn => 'Signed in';

  @override
  String get secureLoginGoogleEmail => 'Secure login · Google or Email';

  @override
  String tokensAvailable(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tokens available',
      one: '$count token available',
    );
    return '$_temp0';
  }

  @override
  String get menuSectionAccount => 'Account';

  @override
  String get menuSectionSupport => 'Support';

  @override
  String get buyMoreCredits => 'Buy more credits';

  @override
  String get alertsMonitoring => 'Alerts & monitoring';

  @override
  String get privacyLabel => 'Privacy';

  @override
  String get languageLabel => 'Language';

  @override
  String get languagePortuguese => 'Português';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageAutomatic => 'Automatic (device)';

  @override
  String get signOut => 'Sign out';

  @override
  String get addressNotFound => 'Address not found';

  @override
  String get noSearchTokensRemaining => 'No search tokens remaining';

  @override
  String get unlockUnlimitedInsights =>
      'Unlock unlimited safety insights before you move or visit an area.';

  @override
  String trendSubtitleWithMonth(String month, int year) {
    return 'Police and community reports · up to $month $year';
  }

  @override
  String get trendSubtitleFallback =>
      'Police and community reports · last 12 months';

  @override
  String get safetyTrendTitle => 'Safety trend in this area';

  @override
  String get safetyTrendShort => 'Safety trend';

  @override
  String get incidentsWithin1Mile => 'Incidents within 1 mile';

  @override
  String get stayUpdatedInArea => 'Stay updated in this area';

  @override
  String get alertOfferBody =>
      'We noticed you are searching this area. Would you like to receive alerts about new incidents nearby?';

  @override
  String get yesNotifyMe => 'Yes, notify me';

  @override
  String get notNow => 'Not now';

  @override
  String get installAppTooltip => 'Install App';

  @override
  String get shareReportTooltip => 'Share a local safety report';

  @override
  String get policeReportCategory => 'Police report';

  @override
  String get roadAccidentCategory => 'Traffic accident';

  @override
  String officialEventDescription(String type, String city, String state) {
    return '$type in $city, $state.';
  }

  @override
  String officialDescriptionWithOutcome(
      String category, String street, String outcome, String month) {
    return 'Police recorded $category near $street. Outcome: $outcome. Reported in $month.';
  }

  @override
  String officialDescriptionNoOutcome(
      String category, String street, String month) {
    return 'Police recorded $category near $street. Reported in $month.';
  }

  @override
  String get locationNotSpecified => 'Location not specified';

  @override
  String get areaIntelligenceSafetyPulse => 'Safety Pulse';

  @override
  String get areaIntelligenceHistorical => 'Historical Safety';

  @override
  String areaIntelligenceHistoricalCaption(String state) {
    return '12-month baseline, ranked against other cities in $state';
  }

  @override
  String get areaIntelligenceRecent => 'Recent Activity';

  @override
  String get areaIntelligenceRecentCaption =>
      'Last 30 days vs. this city\'s own baseline';

  @override
  String get areaIntelligenceLive => 'Live Awareness';

  @override
  String areaIntelligenceLiveCaption(String radius) {
    return 'Signals in the last 24h within $radius';
  }

  @override
  String get areaIntelligenceNoData => 'Not enough recent data yet';

  @override
  String areaIntelligenceSignalCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count signals',
      one: '$count signal',
      zero: 'No signals',
    );
    return '$_temp0';
  }

  @override
  String get areaIntelligenceDisclaimer =>
      'An intelligence indicator built from official records — not a probability of personal safety. Coverage varies by source and is still being validated.';

  @override
  String get areaIntelligenceLoadError =>
      'Couldn\'t load this area\'s data right now.';

  @override
  String get locationPermissionDenied =>
      'Location access is off — allow it to centre the map on you.';

  @override
  String get locationPermissionBlocked =>
      'Location is blocked for this site. Enable it in your browser\'s site settings.';

  @override
  String get locationPermissionError =>
      'Couldn\'t get your location right now.';
}
