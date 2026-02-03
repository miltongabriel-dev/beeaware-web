import '../map/map_incident.dart';

IncidentSeverity mapSeverity(String policeCategory) {
  switch (policeCategory) {
    case 'violent-crime':
    case 'robbery':
    case 'sexual-offences':
    case 'possession-of-weapons':
      return IncidentSeverity.high;

    case 'burglary':
    case 'vehicle-crime':
    case 'drugs':
      return IncidentSeverity.medium;

    default:
      return IncidentSeverity.low;
  }
}
