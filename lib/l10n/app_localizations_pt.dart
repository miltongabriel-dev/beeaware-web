// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get appTitle => 'BeeAware';

  @override
  String get close => 'Fechar';

  @override
  String get cancel => 'Cancelar';

  @override
  String get other => 'Outro';

  @override
  String get buyMore => 'Comprar mais';

  @override
  String get filters => 'Filtros';

  @override
  String get dataSources => 'Fontes de dados';

  @override
  String get aboutBeeAware => 'Sobre o BeeAware';

  @override
  String get emergencyServices => 'Serviços de emergência';

  @override
  String get noDescriptionProvided => 'Nenhuma descrição fornecida.';

  @override
  String get continueButton => 'Continuar';

  @override
  String get buyTokensButton => 'Comprar Tokens';

  @override
  String get severityLow => 'Baixa';

  @override
  String get severityMedium => 'Média';

  @override
  String get severityHigh => 'Alta';

  @override
  String severitySuffixed(String severity) {
    String _temp0 = intl.Intl.selectLogic(
      severity,
      {
        'low': 'Severidade baixa',
        'medium': 'Severidade média',
        'high': 'Severidade alta',
        'other': '',
      },
    );
    return '$_temp0';
  }

  @override
  String get relativeTimeJustNow => 'Agora mesmo';

  @override
  String relativeTimeMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'há $count minutos',
      one: 'há $count minuto',
    );
    return '$_temp0';
  }

  @override
  String relativeTimeHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'há $count horas',
      one: 'há $count hora',
    );
    return '$_temp0';
  }

  @override
  String relativeTimeDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'há $count dias',
      one: 'há $count dia',
    );
    return '$_temp0';
  }

  @override
  String get loginHeadline => 'Fique atento.\nFique seguro.';

  @override
  String get loginSubtitle =>
      'Privado por padrão. Nenhum dado pessoal é necessário.\nDados da comunidade e oficiais para ajudar você a tomar decisões mais seguras.';

  @override
  String get continueWithGoogle => 'Continuar com o Google';

  @override
  String get continueWithApple => 'Continuar com a Apple';

  @override
  String get appleSignInComingSoon => 'Login com Apple em breve';

  @override
  String get enterYourEmail => 'Digite seu e-mail';

  @override
  String get sendMagicLink => 'Enviar link mágico';

  @override
  String get privacyProtectedNotice =>
      'Sua privacidade está protegida. Nenhum dado pessoal é necessário.';

  @override
  String get checkEmailForLoginLink =>
      'Verifique seu e-mail para o link de login';

  @override
  String get buyTokensSubtitle =>
      'Escolha um plano e explore qualquer área antes de ir.';

  @override
  String packageSearches(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count buscas',
      one: '$count busca',
    );
    return '$_temp0';
  }

  @override
  String get badgeMostPopular => 'Mais popular';

  @override
  String get badgeBestValue => 'Melhor custo-benefício';

  @override
  String pricePerSearch(String price) {
    return '$price por busca';
  }

  @override
  String get bonusTokensNotice =>
      'Tokens de bônus — pagamentos ainda não estão ativos.';

  @override
  String get creditsAdded => 'Créditos adicionados';

  @override
  String get whatHappenedTitle => 'O que aconteceu?';

  @override
  String get categoryHarassment => 'Assédio';

  @override
  String get categorySuspiciousActivity => 'Atividade suspeita';

  @override
  String get categoryTheft => 'Furto';

  @override
  String get categoryViolence => 'Violência';

  @override
  String get categoryDrugs => 'Drogas';

  @override
  String get tellUsMoreTitle => 'Conte mais';

  @override
  String get subHarassmentVerbal => 'Verbal';

  @override
  String get subHarassmentPhysical => 'Física';

  @override
  String get subHarassmentOnline => 'Online';

  @override
  String get subHarassmentStalking => 'Perseguição';

  @override
  String get subHarassmentSexual => 'Sexual';

  @override
  String get subSuspiciousLoitering => 'Rondando o local';

  @override
  String get subSuspiciousFollowing => 'Seguindo alguém';

  @override
  String get subSuspiciousCars => 'Olhando dentro de carros';

  @override
  String get subSuspiciousDoors => 'Testando portas';

  @override
  String get subTheftPickpocketing => 'Furto de carteira';

  @override
  String get subTheftBike => 'Furto de bicicleta';

  @override
  String get subTheftCarBreakIn => 'Arrombamento de carro';

  @override
  String get subTheftShoplifting => 'Furto em loja';

  @override
  String get subViolenceFight => 'Briga';

  @override
  String get subViolenceDomestic => 'Violência doméstica';

  @override
  String get subViolenceWeapon => 'Uso de arma';

  @override
  String get subViolenceThreats => 'Ameaças';

  @override
  String get subDrugsUse => 'Uso';

  @override
  String get subDrugsDealing => 'Tráfico';

  @override
  String get subDrugsExchange => 'Troca suspeita';

  @override
  String get subDrugsNeedles => 'Agulhas encontradas';

  @override
  String get howSeriousWasItTitle => 'Quão sério foi?';

  @override
  String get severityLowDesc => 'Desconfortável, mas sem perigo imediato';

  @override
  String get severityMediumDesc => 'Preocupante e potencialmente inseguro';

  @override
  String get severityHighDesc => 'Risco sério ou perigo imediato';

  @override
  String get whenDidItHappenTitle => 'Quando aconteceu?';

  @override
  String get adjustDateTimeHint =>
      'Você pode ajustar a data e hora se estiver reportando depois do ocorrido.';

  @override
  String get dateLabel => 'Data';

  @override
  String get timeLabel => 'Hora';

  @override
  String reportVisibilityNotice(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes minutos',
      one: '1 minuto',
    );
    return 'Este relato vai aparecer no mapa em cerca de $_temp0.';
  }

  @override
  String get confirmReport => 'Confirmar relato';

  @override
  String get describeWhatHappenedTitle => 'Descreva o que aconteceu';

  @override
  String get addShortDescription => 'Adicione uma breve descrição';

  @override
  String get descriptionHelperText =>
      'Isso ajuda outras pessoas a entenderem melhor a situação.';

  @override
  String get descriptionHint =>
      'Exemplo: Um grupo de pessoas agindo de forma suspeita perto da estação...';

  @override
  String get whereDidItHappenTitle => 'Onde aconteceu?';

  @override
  String get selectLocationOnMap => 'Selecione um local no mapa';

  @override
  String get reviewReportTitle => 'Revisar relato';

  @override
  String get missingSubcategory =>
      'Subcategoria ausente. Volte e selecione uma.';

  @override
  String get missingLocation => 'Localização ausente. Volte e selecione uma.';

  @override
  String waitBeforeAnotherReport(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes minutos',
      one: '1 minuto',
    );
    return 'Aguarde $_temp0 antes de enviar outro relato.';
  }

  @override
  String get reportSubmittedSuccess =>
      'Obrigado! Seu relato foi enviado com sucesso.';

  @override
  String submitFailed(String error) {
    return 'Falha ao enviar: $error';
  }

  @override
  String get sectionCategory => 'Categoria';

  @override
  String get sectionSeverity => 'Severidade';

  @override
  String get sectionDescription => 'Descrição';

  @override
  String get sectionWhen => 'Quando';

  @override
  String get mapVisibleNow => 'Este relato já está visível no mapa.';

  @override
  String get mapVisibleShortly => 'Este relato vai aparecer no mapa em breve.';

  @override
  String get submitReportAnonymously => 'Enviar relato anonimamente';

  @override
  String get typeAddressToSearch => 'Digite um endereço para buscar.';

  @override
  String searchingNearMock(String query) {
    return 'Buscando perto de: $query (simulação)';
  }

  @override
  String get noTokensLeftTitle => 'Sem tokens restantes';

  @override
  String get noTokensLeftContent =>
      'Você não tem mais tokens de busca.\n\nCompre mais tokens para continuar buscando.';

  @override
  String get searchAddressTitle => 'Buscar Endereço';

  @override
  String tokensRemaining(int count) {
    return 'Tokens restantes: $count';
  }

  @override
  String get addressOrPostcodeHint => 'Endereço ou código postal';

  @override
  String get searchButton => 'Buscar';

  @override
  String sourceLabel(String source) {
    return 'Fonte: $source';
  }

  @override
  String get incidentInfoDisclaimer =>
      'Informações de fontes públicas e relatos da comunidade. Apenas para conscientização.';

  @override
  String get noDataAvailable => 'Nenhum dado disponível';

  @override
  String get accountLabel => 'Conta';

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
  String get reportingHintText => 'Viu algo? Toque na abelha.';

  @override
  String get clusterNumbersExplained =>
      'Como funcionam os números dos agrupamentos';

  @override
  String get coverageGlobalBaselineOnly =>
      'Só há dado global de base aqui — isso não é garantia de segurança, é só o que temos disponível.';

  @override
  String get choroplethLegendTooltip => 'Legenda do mapa';

  @override
  String get choroplethLegendTitle => 'O que as cores mostram';

  @override
  String get choroplethNoDataDisclaimer =>
      'Áreas sem cor no mapa não têm fonte pública de dados de segurança. A ausência de cor não significa que o local é seguro — só que a polícia ou o governo local ainda não divulgam esses dados.';

  @override
  String get loadingIncidents => 'Carregando incidentes…';

  @override
  String get noIncidentsForFilters =>
      'Nenhum incidente encontrado com esses filtros';

  @override
  String get searchAnAddressHint => 'Buscar um endereço';

  @override
  String tokensSearchBadge(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tokens de busca',
      one: '$count token de busca',
    );
    return '$_temp0';
  }

  @override
  String get oneSearchRemaining => 'Você tem 1 busca restante';

  @override
  String get allSearchesUsed => 'Você usou todas as suas buscas';

  @override
  String officialRecordDate(int month, int year) {
    return 'Registro Oficial da Polícia · $month/$year';
  }

  @override
  String communityReportRelative(String relative) {
    return 'Relato da Comunidade · $relative';
  }

  @override
  String get clusterCountTitle => 'Contagem do agrupamento';

  @override
  String get clusterCountExplanation =>
      'O número mostrado dentro de cada agrupamento representa o total de incidentes reportados naquela área.';

  @override
  String callEmergencyNumber(String number) {
    return 'Ligar para emergência ($number)';
  }

  @override
  String callNonEmergencyNumber(String number) {
    return 'Ligar para não-emergência ($number)';
  }

  @override
  String get emergencyDisclaimer =>
      'BeeAware não é um serviço de emergência.\nSe você estiver em perigo imediato, contate os serviços de emergência diretamente.';

  @override
  String sosBarLabel(String number) {
    return 'SOS $number';
  }

  @override
  String get reportBarLabel => 'Reportar';

  @override
  String get filterTimeSectionTitle => 'Período';

  @override
  String get timeFilterLastHour => 'Última hora';

  @override
  String get timeFilterLast6Hours => 'Últimas 6 horas';

  @override
  String get timeFilterLast24Hours => 'Últimas 24 horas';

  @override
  String get timeFilterAllTime => 'Todo o período';

  @override
  String get distanceLabel => 'Distância';

  @override
  String get distanceFilter250m => 'Até 250 m';

  @override
  String get distanceFilter500m => 'Até 500 m';

  @override
  String get distanceFilter1km => 'Até 1 km';

  @override
  String get distanceFilterAny => 'Qualquer distância';

  @override
  String get applyFilters => 'Aplicar';

  @override
  String get clearFilters => 'Limpar';

  @override
  String filterResultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count incidentes',
      one: '$count incidente',
    );
    return '$_temp0';
  }

  @override
  String get aboutBodyText =>
      'BeeAware é uma plataforma comunitária de conscientização sobre segurança, feita para ajudar pessoas a se manterem informadas sobre incidentes não emergenciais na sua região.\n\nO app combina relatos da comunidade e dados oficiais publicamente disponíveis para melhorar a percepção situacional e apoiar decisões mais seguras no dia a dia.\n\nAs informações exibidas podem estar atrasadas, incompletas ou não verificadas, e não devem ser usadas como substituto dos serviços de emergência.\n\nO BeeAware não oferece monitoramento em tempo real e não é um sistema de resposta a emergências.';

  @override
  String get aboutDataSourcesBody =>
      'O BeeAware exibe informações de segurança a partir de duas fontes principais:\n\n• Relatos anônimos enviados pela comunidade\n• Dados públicos abertos oficiais — fontes governamentais do Reino Unido e do Brasil (polícia, segurança viária e órgãos de segurança pública), além de uma base global mais genérica onde ainda não há dado local\n\nEssas fontes são usadas para melhorar a percepção situacional e não representam alertas em tempo real.';

  @override
  String get privacyAnonymityTitle => 'Privacidade e anonimato';

  @override
  String get privacyAnonymityBody =>
      'O BeeAware é projetado com privacidade por padrão.\nNenhuma informação de identificação pessoal é necessária.\nOs relatos são anônimos e os dados de localização se limitam ao necessário para exibir os incidentes no mapa.';

  @override
  String get privacyPolicyButton => 'Política de Privacidade';

  @override
  String get termsOfServiceButton => 'Termos de Serviço';

  @override
  String get copyrightBeeAware => '© BeeAware';

  @override
  String get officialLegendBody =>
      'O BeeAware mostra dois tipos de relato:\n\n• Relatos da comunidade (envios anônimos de usuários)\n• Dados abertos oficiais — registros de segurança pública de fontes governamentais do Reino Unido e do Brasil (polícia, segurança viária e órgãos de segurança pública), além de uma base global mais genérica onde ainda não há dado local\n\nItens oficiais são exibidos com um pino distinto. Eles são incluídos para percepção situacional e não são alertas de emergência em tempo real.';

  @override
  String get signInToBeeAware => 'Entrar no BeeAware';

  @override
  String get signedIn => 'Conectado';

  @override
  String get secureLoginGoogleEmail => 'Login seguro · Google ou E-mail';

  @override
  String tokensAvailable(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tokens disponíveis',
      one: '$count token disponível',
    );
    return '$_temp0';
  }

  @override
  String get menuSectionAccount => 'Conta';

  @override
  String get menuSectionSupport => 'Suporte';

  @override
  String get buyMoreCredits => 'Comprar mais créditos';

  @override
  String get alertsMonitoring => 'Alertas e monitoramento';

  @override
  String get privacyLabel => 'Privacidade';

  @override
  String get languageLabel => 'Idioma';

  @override
  String get languagePortuguese => 'Português';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageAutomatic => 'Automático (dispositivo)';

  @override
  String get signOut => 'Sair';

  @override
  String get addressNotFound => 'Endereço não encontrado';

  @override
  String get noSearchTokensRemaining => 'Sem tokens de busca restantes';

  @override
  String get unlockUnlimitedInsights =>
      'Desbloqueie informações de segurança ilimitadas antes de se mudar ou visitar uma área.';

  @override
  String trendSubtitleWithMonth(String month, int year) {
    return 'Relatos da polícia e da comunidade · até $month $year';
  }

  @override
  String get trendSubtitleFallback =>
      'Relatos da polícia e da comunidade · últimos 12 meses';

  @override
  String get safetyTrendTitle => 'Tendência de segurança nesta área';

  @override
  String get safetyTrendShort => 'Tendência de segurança';

  @override
  String get incidentsWithin1Mile => 'Incidentes num raio de 1 milha';

  @override
  String get stayUpdatedInArea => 'Fique atualizado nesta área';

  @override
  String get alertOfferBody =>
      'Notamos que você está pesquisando esta área. Gostaria de receber alertas sobre novos incidentes por perto?';

  @override
  String get yesNotifyMe => 'Sim, me notifique';

  @override
  String get notNow => 'Agora não';

  @override
  String get installAppTooltip => 'Instalar App';

  @override
  String get shareReportTooltip => 'Compartilhar um relato de segurança local';

  @override
  String get policeReportCategory => 'Relato da polícia';

  @override
  String get roadAccidentCategory => 'Acidente de trânsito';

  @override
  String officialEventDescription(String type, String city, String state) {
    return '$type em $city, $state.';
  }

  @override
  String officialDescriptionWithOutcome(
      String category, String street, String outcome, String month) {
    return 'A polícia registrou $category perto de $street. Resultado: $outcome. Reportado em $month.';
  }

  @override
  String officialDescriptionNoOutcome(
      String category, String street, String month) {
    return 'A polícia registrou $category perto de $street. Reportado em $month.';
  }

  @override
  String get locationNotSpecified => 'Localização não especificada';

  @override
  String get areaIntelligenceSafetyPulse => 'Pulso de Segurança';

  @override
  String get areaIntelligenceHistorical => 'Segurança Histórica';

  @override
  String areaIntelligenceHistoricalCaption(String state) {
    return 'Base de 12 meses, comparado a outras cidades de $state';
  }

  @override
  String get areaIntelligenceRecent => 'Atividade Recente';

  @override
  String get areaIntelligenceRecentCaption =>
      'Últimos 30 dias vs. a própria base histórica desta cidade';

  @override
  String get areaIntelligenceLive => 'Ao Vivo';

  @override
  String areaIntelligenceLiveCaption(String radius) {
    return 'Sinais nas últimas 24h dentro de $radius';
  }

  @override
  String get areaIntelligenceNoData => 'Ainda sem dados recentes suficientes';

  @override
  String areaIntelligenceSignalCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sinais',
      one: '$count sinal',
      zero: 'Nenhum sinal',
    );
    return '$_temp0';
  }

  @override
  String get areaIntelligenceDisclaimer =>
      'Um indicador de inteligência construído a partir de registros oficiais — não é uma probabilidade de segurança pessoal. A cobertura varia por fonte e ainda está sendo validada.';

  @override
  String get areaIntelligenceLoadError =>
      'Não foi possível carregar os dados desta área agora.';

  @override
  String get locationPermissionDenied =>
      'A localização está desativada — permita o acesso para centralizar o mapa em você.';

  @override
  String get locationPermissionBlocked =>
      'A localização está bloqueada para este site. Ative nas configurações do seu navegador.';

  @override
  String get locationPermissionError =>
      'Não foi possível obter sua localização agora.';
}
