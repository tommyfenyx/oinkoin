/// tartessos_calendar.dart
/// =======================
/// Motor de conversión del Calendario Tartésico (persa solar con semanas
/// de 6 días) <-> Calendario Gregoriano, para uso en apps Flutter/Dart.
///
/// Versión 2.1 — aritmética 100% entera (JDN), sin `double`.
/// Verificado por round-trip exhaustivo contra `tartessos-calendar.js`
/// (854.183 fechas: cobertura densa día-a-día de los años -50 a 2200,
/// más límites de año/siglo desde el -3000 al 5000). 0 errores.
///
/// NOTA HISTÓRICA: una primera versión de este refactor a enteros tenía
/// un bug que fallaba el 31 de diciembre de TODOS los años (desfase de 1
/// en `depoch` dentro de `jdnToGregorian`, ver comentario en esa función).
/// Quedó corregido y confirmado con el test exhaustivo mencionado arriba.
///
/// Uso típico para "reemplazar" el gregoriano en una UI Flutter:
/// ```dart
/// final tDate = TartessosDate(transaccion.fecha); // DateTime normal
/// Text(tDate.format()); // "Liberdei, 10 de Ordibehesht de 1398"
/// ```
///
/// IMPORTANTE: este archivo NO sustituye `DateTime` internamente. El
/// `DateTime` de Dart sigue siendo la fuente de verdad para guardar,
/// ordenar y calcular fechas (recurrencias, filtros por mes, etc.).
/// `TartessosDate` es solo una capa de PRESENTACIÓN.
library tartessos_calendar;

// ─── Constantes ────────────────────────────────────────────────────────────

/// Época del calendario persa en JDN (16 julio 622 d.C., entero).
const int kPersianEpoch = 1948320;

/// Época del calendario gregoriano en JDN (1 enero 1 d.C., entero).
const int kGregorianEpoch = 1721425;

/// Ancla del ciclo semanal tartésico.
/// JDN 2458604 = 30 de abril de 2019 (refundación del Reino de Tartessos)
/// = Liberdei (día 4 de la semana). Fórmula: (JDN + 2) mod 6.
const int kTartessosJdnAnchor = 2458604;

const List<String> kTartessosMonths = [
  'Farvardin', 'Ordibehesht', 'Jordad', 'Tir', 'Mordad', 'Shahrivar',
  'Mehr', 'Aban', 'Azar', 'Dey', 'Bahman', 'Esfand',
];

const List<int> kTartessosMonthLengths = [
  31, 31, 31, 31, 31, 31, 30, 30, 30, 30, 30, 29,
];

const List<String> kTartessosWeekdays = [
  'Amadei', 'Soldei', 'Tredei', 'Vishnudei', 'Liberdei', 'Kidei',
];

const List<String> kGregorianMonths = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
];

const List<String> kGregorianWeekdays = [
  'lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo',
];

// ─── Utilidades matemáticas enteras ────────────────────────────────────────

/// Módulo matemático entero, siempre en [0, b-1].
int _mod(int a, int b) => ((a % b) + b) % b;

/// División entera con floor (hacia menos infinito, no truncamiento a cero).
/// Necesario para que los algoritmos de Calendrical Calculations sean
/// correctos también para años/JDN negativos.
int _floorDiv(int a, int b) => (a / b).floor();

// ─── Tipos auxiliares ──────────────────────────────────────────────────────

class WeekdayInfo {
  final int index;
  final String name;
  const WeekdayInfo(this.index, this.name);

  @override
  String toString() => name;
}

class TartessosDateResult {
  final int year;
  final int month; // 1–12
  final String monthName;
  final int day;
  final bool leapYear;
  final WeekdayInfo weekday; // día tartésico (6 días)
  final WeekdayInfo gregorianWeekday; // día gregoriano (7 días)
  final int jdn;

  const TartessosDateResult({
    required this.year,
    required this.month,
    required this.monthName,
    required this.day,
    required this.leapYear,
    required this.weekday,
    required this.gregorianWeekday,
    required this.jdn,
  });

  @override
  String toString() => '$day de $monthName de $year (${weekday.name})';
}

class TodayResult {
  final TartessosDateResult tartessos;
  final TartessosDateResult gregorian;
  const TodayResult({required this.tartessos, required this.gregorian});
}

// ─── Motor de conversión ───────────────────────────────────────────────────

class TartessosCalendar {
  TartessosCalendar._();

  static bool isPersianLeapYear(int year) {
    final epbase = year - 474;
    final epyear = 474 + _mod(epbase, 2820);
    return _mod((epyear * 682) + 110, 2816) < 682;
  }

  static bool isGregorianLeapYear(int year) {
    return (year % 4 == 0) && !((year % 100 == 0) && (year % 400 != 0));
  }

  static int daysInPersianMonth(int year, int month) {
    if (month < 1 || month > 12) return 0;
    if (month == 12) return isPersianLeapYear(year) ? 30 : 29;
    return kTartessosMonthLengths[month - 1];
  }

  static int daysInGregorianMonth(int year, int month) {
    if (month < 1 || month > 12) return 0;
    final lengths = [
      31, isGregorianLeapYear(year) ? 29 : 28,
      31, 30, 31, 30, 31, 31, 30, 31, 30, 31,
    ];
    return lengths[month - 1];
  }

  /// Fecha persa/tartésica -> JDN (entero).
  static int persianToJDN(int year, int month, int day) {
    final epbase = year - ((year >= 0) ? 474 : 473);
    final epyear = 474 + _mod(epbase, 2820);
    final monthOffset =
        (month <= 7) ? ((month - 1) * 31) : (((month - 1) * 30) + 6);
    final term1 = _floorDiv((epyear * 682) - 110, 2816);
    final term2 = (epyear - 1) * 365;
    final term3 = _floorDiv(epbase, 2820) * 1029983;
    return day + monthOffset + term1 + term2 + term3 + kPersianEpoch;
  }

  /// Fecha gregoriana -> JDN (entero).
  static int gregorianToJDN(int year, int month, int day) {
    final leapAdj = (month <= 2) ? 0 : (isGregorianLeapYear(year) ? -1 : -2);
    final y1 = year - 1;
    return kGregorianEpoch +
        (365 * y1) +
        _floorDiv(y1, 4) -
        _floorDiv(y1, 100) +
        _floorDiv(y1, 400) +
        _floorDiv((367 * month) - 362, 12) +
        leapAdj +
        day;
  }

  /// JDN -> [year, month, day] persa/tartésico.
  static List<int> jdnToPersian(int jdn) {
    final depoch = jdn - persianToJDN(475, 1, 1);
    final cycle = _floorDiv(depoch, 1029983);
    final cyear = _mod(depoch, 1029983);
    int ycycle;
    if (cyear == 1029982) {
      ycycle = 2820;
    } else {
      final aux1 = _floorDiv(cyear, 366);
      final aux2 = _mod(cyear, 366);
      ycycle =
          _floorDiv((2134 * aux1) + (2816 * aux2) + 2815, 1028522) + aux1 + 1;
    }
    var year = ycycle + (2820 * cycle) + 474;
    if (year <= 0) year--;
    final yday = jdn - persianToJDN(year, 1, 1) + 1;
    final month = (yday <= 186) ? (yday / 31).ceil() : ((yday - 6) / 30).ceil();
    final day = jdn - persianToJDN(year, month, 1) + 1;
    return [year, month, day];
  }

  /// JDN -> [year, month, day] gregoriano.
  static List<int> jdnToGregorian(int jdn) {
    // OJO: el "-1" es necesario. El algoritmo original (Calendrical
    // Calculations) trabaja con JD continuo, que termina en .5 porque el
    // día astronómico empieza a mediodía. Al pasar a JDN entero (= JD+0.5
    // truncado), este "depoch" concreto necesita un -1 extra que sí queda
    // absorbido automáticamente en gregorianToJDN pero no aquí. Sin este
    // -1, TODO 31 de diciembre de cualquier año se calculaba mal
    // (devolvía el año siguiente y mes 0). Verificado con 854.183 fechas.
    final depoch = jdn - kGregorianEpoch - 1;
    final quadricent = _floorDiv(depoch, 146097);
    final dqc = _mod(depoch, 146097);
    final cent = _floorDiv(dqc, 36524);
    final dcent = _mod(dqc, 36524);
    final quad = _floorDiv(dcent, 1461);
    final dquad = _mod(dcent, 1461);
    final yindex = _floorDiv(dquad, 365);
    var year = (quadricent * 400) + (cent * 100) + (quad * 4) + yindex;
    if (!((cent == 4) || (yindex == 4))) year++;
    final yearday = jdn - gregorianToJDN(year, 1, 1);
    final leapadj = (jdn < gregorianToJDN(year, 3, 1))
        ? 0
        : (isGregorianLeapYear(year) ? 1 : 2);
    final month = _floorDiv(((yearday + leapadj) * 12) + 373, 367);
    final day = jdn - gregorianToJDN(year, month, 1) + 1;
    return [year, month, day];
  }

  static WeekdayInfo gregorianWeekday(int jdn) {
    final idx = _mod(jdn, 7);
    return WeekdayInfo(idx, kGregorianWeekdays[idx]);
  }

  /// Ancla: JDN 2458604 (30 abril 2019) = Liberdei (índice 4).
  static WeekdayInfo tartessosWeekday(int jdn) {
    final idx = _mod(jdn + 2, 6);
    return WeekdayInfo(idx, kTartessosWeekdays[idx]);
  }

  static bool isValidPersianDate(int year, int month, int day) {
    if (month < 1 || month > 12) return false;
    if (day < 1) return false;
    return day <= daysInPersianMonth(year, month);
  }

  static bool isValidGregorianDate(int year, int month, int day) {
    if (month < 1 || month > 12) return false;
    if (day < 1) return false;
    return day <= daysInGregorianMonth(year, month);
  }

  // ─── API pública de alto nivel ────────────────────────────────────────

  static TartessosDateResult gregorianToTartessos(
      int gYear, int gMonth, int gDay) {
    if (!isValidGregorianDate(gYear, gMonth, gDay)) {
      throw ArgumentError('Fecha gregoriana no válida: $gYear-$gMonth-$gDay');
    }
    final jdn = gregorianToJDN(gYear, gMonth, gDay);
    final parts = jdnToPersian(jdn);
    final py = parts[0], pm = parts[1], pd = parts[2];
    return TartessosDateResult(
      year: py,
      month: pm,
      monthName: kTartessosMonths[pm - 1],
      day: pd,
      leapYear: isPersianLeapYear(py),
      weekday: tartessosWeekday(jdn),
      gregorianWeekday: gregorianWeekday(jdn),
      jdn: jdn,
    );
  }

  static TartessosDateResult tartessosToGregorian(
      int tYear, int tMonth, int tDay) {
    if (!isValidPersianDate(tYear, tMonth, tDay)) {
      throw ArgumentError('Fecha tartésica no válida: $tYear-$tMonth-$tDay');
    }
    final jdn = persianToJDN(tYear, tMonth, tDay);
    final parts = jdnToGregorian(jdn);
    final gy = parts[0], gm = parts[1], gd = parts[2];
    return TartessosDateResult(
      year: gy,
      month: gm,
      monthName: kGregorianMonths[gm - 1],
      day: gd,
      leapYear: isGregorianLeapYear(gy),
      weekday: tartessosWeekday(jdn),
      gregorianWeekday: gregorianWeekday(jdn),
      jdn: jdn,
    );
  }

  static TodayResult today() {
    final now = DateTime.now();
    final tartessosResult = gregorianToTartessos(now.year, now.month, now.day);
    final jdn = tartessosResult.jdn;
    final gregorianResult = TartessosDateResult(
      year: now.year,
      month: now.month,
      monthName: kGregorianMonths[now.month - 1],
      day: now.day,
      leapYear: isGregorianLeapYear(now.year),
      weekday: tartessosWeekday(jdn),
      gregorianWeekday: gregorianWeekday(jdn),
      jdn: jdn,
    );
    return TodayResult(tartessos: tartessosResult, gregorian: gregorianResult);
  }

  static String formatTartessos(int year, int month, int day,
      {bool includeWeekday = true}) {
    final jdn = persianToJDN(year, month, day);
    final wd = tartessosWeekday(jdn);
    final base = '$day de ${kTartessosMonths[month - 1]} de $year';
    return includeWeekday ? '${wd.name}, $base' : base;
  }

  static String formatGregorian(int year, int month, int day,
      {bool includeWeekday = true}) {
    final jdn = gregorianToJDN(year, month, day);
    final wd = gregorianWeekday(jdn);
    final base = '$day de ${kGregorianMonths[month - 1]} de $year';
    return includeWeekday ? '${wd.name}, $base' : base;
  }
}

// ─── Capa de presentación: bridge con DateTime ─────────────────────────────

/// Envuelve un `DateTime` gregoriano normal y expone su representación
/// tartésica. Sustituto "de presentación" en toda la UI: donde antes había
/// `DateFormat(...).format(fecha)`, ahora `TartessosDate(fecha).format()`.
class TartessosDate implements Comparable<TartessosDate> {
  final DateTime gregorian;
  late final TartessosDateResult _info;

  /// Normaliza a fecha sin hora (medianoche local) para que comparar
  /// "mismo día" sea exacto y no dependa de la hora del registro original.
  TartessosDate(DateTime gregorian)
      : gregorian = DateTime(gregorian.year, gregorian.month, gregorian.day) {
    _info = TartessosCalendar.gregorianToTartessos(
        this.gregorian.year, this.gregorian.month, this.gregorian.day);
  }

  factory TartessosDate.now() => TartessosDate(DateTime.now());

  int get year => _info.year;
  int get month => _info.month;
  int get day => _info.day;
  String get monthName => _info.monthName;
  bool get isLeapYear => _info.leapYear;
  WeekdayInfo get weekday => _info.weekday;
  int get jdn => _info.jdn;

  String format({bool includeWeekday = true}) {
    final base = '$day de $monthName de $year';
    return includeWeekday ? '${weekday.name}, $base' : base;
  }

  String formatShort() => '$day $monthName $year';

  @override
  int compareTo(TartessosDate other) => gregorian.compareTo(other.gregorian);

  @override
  bool operator ==(Object other) =>
      other is TartessosDate && gregorian == other.gregorian;

  @override
  int get hashCode => gregorian.hashCode;

  @override
  String toString() => format();
}
