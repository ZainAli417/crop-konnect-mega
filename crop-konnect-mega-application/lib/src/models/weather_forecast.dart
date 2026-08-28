/// The visual families the WMO weather codes collapse into.
///
/// The forecast sheet draws one animated vector per family, so the codes are
/// grouped by what a farmer needs to see at a glance rather than by the full
/// WMO taxonomy.
enum WeatherKind {
  clear,
  partlyCloudy,
  cloudy,
  fog,
  drizzle,
  rain,
  showers,
  snow,
  thunderstorm,
}

extension WeatherKindLabel on WeatherKind {
  String get label {
    switch (this) {
      case WeatherKind.clear:
        return 'Clear';
      case WeatherKind.partlyCloudy:
        return 'Partly cloudy';
      case WeatherKind.cloudy:
        return 'Overcast';
      case WeatherKind.fog:
        return 'Fog';
      case WeatherKind.drizzle:
        return 'Drizzle';
      case WeatherKind.rain:
        return 'Rain';
      case WeatherKind.showers:
        return 'Showers';
      case WeatherKind.snow:
        return 'Snow';
      case WeatherKind.thunderstorm:
        return 'Thunderstorm';
    }
  }

  /// True when the day carries water — used to flag spray / harvest windows.
  bool get isWet =>
      this == WeatherKind.drizzle ||
      this == WeatherKind.rain ||
      this == WeatherKind.showers ||
      this == WeatherKind.thunderstorm ||
      this == WeatherKind.snow;
}

/// Map a WMO code to its visual family.
WeatherKind weatherKindFromCode(int? code) {
  switch (code) {
    case 0:
      return WeatherKind.clear;
    case 1:
    case 2:
      return WeatherKind.partlyCloudy;
    case 3:
      return WeatherKind.cloudy;
    case 45:
    case 48:
      return WeatherKind.fog;
    case 51:
    case 53:
    case 55:
    case 56:
    case 57:
      return WeatherKind.drizzle;
    case 61:
    case 63:
    case 65:
    case 66:
    case 67:
      return WeatherKind.rain;
    case 80:
    case 81:
    case 82:
      return WeatherKind.showers;
    case 71:
    case 73:
    case 75:
    case 77:
    case 85:
    case 86:
      return WeatherKind.snow;
    case 95:
    case 96:
    case 99:
      return WeatherKind.thunderstorm;
    default:
      return WeatherKind.cloudy;
  }
}

class ForecastDay {
  const ForecastDay({
    required this.date,
    required this.weatherCode,
    this.tempMaxC,
    this.tempMinC,
    this.precipitationMm,
    this.precipitationChance,
    this.windMaxMs,
    this.windDirectionDeg,
    this.uvIndexMax,
    this.sunrise,
    this.sunset,
  });

  final DateTime date;
  final int? weatherCode;
  final double? tempMaxC;
  final double? tempMinC;
  final double? precipitationMm;

  /// Peak chance of precipitation across the day, 0–100.
  final double? precipitationChance;
  final double? windMaxMs;
  final double? windDirectionDeg;
  final double? uvIndexMax;
  final DateTime? sunrise;
  final DateTime? sunset;

  WeatherKind get kind => weatherKindFromCode(weatherCode);

  bool get isToday {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }
}

/// A 14-day outlook for the field.
class WeatherForecast {
  const WeatherForecast({
    required this.fetchedAt,
    required this.latitude,
    required this.longitude,
    required this.days,
  });

  final DateTime fetchedAt;
  final double latitude;
  final double longitude;
  final List<ForecastDay> days;

  ForecastDay? get today => days.isEmpty ? null : days.first;

  /// Total rain expected across the whole outlook.
  double get totalRainMm => days.fold<double>(
        0,
        (sum, day) => sum + (day.precipitationMm ?? 0),
      );

  /// The next day carrying meaningful rain, or null when the outlook is dry.
  /// Used for the "next wet day" callout above the day list.
  ForecastDay? get nextWetDay {
    for (final day in days) {
      final mm = day.precipitationMm ?? 0;
      final chance = day.precipitationChance ?? 0;
      if (mm >= 1 || chance >= 50) return day;
    }
    return null;
  }

  double? get warmestC {
    final values =
        days.map((d) => d.tempMaxC).whereType<double>().toList(growable: false);
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a > b ? a : b);
  }

  double? get coolestC {
    final values =
        days.map((d) => d.tempMinC).whereType<double>().toList(growable: false);
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a < b ? a : b);
  }
}
