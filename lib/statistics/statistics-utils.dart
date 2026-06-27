import 'dart:math';
import 'dart:ui';

import "package:collection/collection.dart";
import 'package:intl/intl.dart';
import 'package:piggybank/helpers/datetime-utility-functions.dart';
import 'package:piggybank/helpers/tartessos_calendar.dart';
import 'package:piggybank/models/category.dart';
import 'package:piggybank/models/record.dart';
import 'package:piggybank/statistics/statistics-models.dart';

/// Genera la etiqueta/clave tartésica para un punto de las gráficas de
/// estadísticas y balance.
///
/// CRÍTICO: el texto que devuelve esta función se usa A LA VEZ como:
///   (a) la CLAVE que identifica a qué barra/punto pertenece un importe
///       (ChartDateRangeConfig.getKey, bar-chart-card._generateDataKey,
///       balance-chart-models ComparisonDataAggregator), y
///   (b) el TEXTO visible bajo cada barra en el eje (ChartTickGenerator).
/// Ambos deben coincidir carácter a carácter o las barras dejan de
/// alinearse con sus etiquetas. Por eso está centralizada aquí en una
/// única función en vez de repetida en varios sitios (como estaba en el
/// código original gregoriano, con la lógica duplicada en 3 archivos).
///
/// Comprobado sin colisiones de clave en 131 años (1970-2100) para
/// agregación por mes y por semana — ver auditoría previa a este cambio.
/// Limitación cosmética conocida: ~2 semanas al año, justo en el cambio
/// de año tartésico (hacia el 20 de marzo), el rango de días de una
/// semana puede mostrarse como "26-2" en vez de un rango más intuitivo.
/// Es solo visual, no afecta a qué importes se suman en cada barra.
String tartessosChartLabel(DateTime date, AggregationMethod aggregationMethod) {
  switch (aggregationMethod) {
    case AggregationMethod.WEEK:
      final tdStart = TartessosDate(date);
      DateTime weekEnd = date.add(Duration(days: 6));
      if (weekEnd.month != date.month) {
        weekEnd = DateTime(date.year, date.month + 1, 0); // Last day of month
      }
      final tdEnd = TartessosDate(weekEnd);
      return '${tdStart.day}-${tdEnd.day}';
    case AggregationMethod.DAY:
      final t = TartessosDate(date);
      final bool isMonthStart = t.day == 1;
      return isMonthStart ? '${t.month}/${t.day}' : '${t.day}';
    case AggregationMethod.MONTH:
      return '${TartessosDate(date).month}';
    case AggregationMethod.YEAR:
      return '${TartessosDate(date).year}';
    default:
      return '${TartessosDate(date).day}';
  }
}

double computeNumberOfMonthsBetweenTwoDates(DateTime from, DateTime to) {
  var apprxSizeOfMonth = 30;
  var numberOfDaysInBetween = from.difference(to).abs().inDays;
  var numberOfMonths = numberOfDaysInBetween / apprxSizeOfMonth;
  return numberOfMonths;
}

double computeNumberOfYearsBetweenTwoDates(DateTime from, DateTime to) {
  var apprxSizeOfYear = 365;
  var numberOfDaysInBetween = from.difference(to).abs().inDays;
  return numberOfDaysInBetween / apprxSizeOfYear;
}

/// Calculates the number of days between two dates (inclusive).
int computeNumberOfDays(DateTime from, DateTime to) {
  if (from.isAfter(to)) return 0;
  return to.difference(from).inDays + 1;
}

int computeNumberOfIntervals(
    DateTime from, DateTime to, AggregationMethod method,
    {DateTime? now}) {
  DateTime effectiveNow = now ?? DateTime.now();

  // The range we are interested in is [from, to]
  // We cap it at the interval containing 'now' if 'to' is in the future.
  DateTime effectiveTo = to.isAfter(effectiveNow) ? effectiveNow : to;

  DateTime start = truncateDateTime(from, method);
  DateTime end = truncateDateTime(effectiveTo, method);

  if (start.isAfter(end)) {
    // If the entire range starts after today's interval
    return 0;
  }

  int count = 0;
  DateTime current = start;
  while (!current.isAfter(end)) {
    count++;
    switch (method) {
      case AggregationMethod.DAY:
        current = DateTime(current.year, current.month, current.day + 1);
        break;
      case AggregationMethod.WEEK:
        if (current.day == 1) {
          current = DateTime(current.year, current.month, 8);
        } else if (current.day == 8) {
          current = DateTime(current.year, current.month, 15);
        } else if (current.day == 15) {
          current = DateTime(current.year, current.month, 22);
        } else if (current.day == 22) {
          current = DateTime(current.year, current.month, 29);
        } else {
          current = DateTime(current.year, current.month + 1, 1);
        }
        break;
      case AggregationMethod.MONTH:
        current = DateTime(current.year, current.month + 1, 1);
        break;
      case AggregationMethod.YEAR:
        current = DateTime(current.year + 1, 1, 1);
        break;
      default:
        // For NOT_AGGREGATED, we might just return 1 or something consistent
        return 1;
    }
  }
  return count;
}

double? computeAverage(DateTime from, DateTime to,
    List<DateTimeSeriesRecord> records, AggregationMethod aggregationMethod) {
  var sumValues = records.fold(0, (dynamic acc, e) => acc + e.value).abs();
  int denominator = computeNumberOfIntervals(from, to, aggregationMethod);
  return sumValues / (denominator == 0 ? 1 : denominator);
}

DateTime truncateDateTime(
    DateTime dateTime, AggregationMethod? aggregationMethod) {
  DateTime newDateTime;
  switch (aggregationMethod!) {
    case AggregationMethod.DAY:
      newDateTime = DateTime(dateTime.year, dateTime.month, dateTime.day);
      break;
    case AggregationMethod.WEEK:
      // Truncate to the first day given the bin 1-7, 8-14, 15-21, 22-end of month
      int truncatedDay;
      if (dateTime.day <= 7) {
        truncatedDay = 1;
      } else if (dateTime.day <= 14) {
        truncatedDay = 8;
      } else if (dateTime.day <= 21) {
        truncatedDay = 15;
      } else if (dateTime.day <= 28) {
        truncatedDay = 22;
      } else {
        truncatedDay = 29;
      }
      newDateTime = DateTime(dateTime.year, dateTime.month, truncatedDay);
      break;
    case AggregationMethod.MONTH:
      newDateTime = DateTime(dateTime.year, dateTime.month);
      break;
    case AggregationMethod.YEAR:
      newDateTime = DateTime(dateTime.year);
      break;
    case AggregationMethod.NOT_AGGREGATED:
      newDateTime = dateTime;
      break;
  }
  return newDateTime;
}

List<DateTimeSeriesRecord> aggregateRecordsByDate(
    List<Record?> records, AggregationMethod? aggregationMethod,
    {bool useTagWeight = false}) {
  /// Record Day 1: 100 euro Food, 20 euro Food, 30 euro Transport
  /// Record Day 1: 150 euro,
  /// Available grouping: by day, month, year.
  Map<DateTime?, DateTimeSeriesRecord> aggregatedByDay = {};
  for (var record in records) {
    DateTime? dateTime = truncateDateTime(record!.dateTime, aggregationMethod);
    double valueToAdd = record.value!.abs();
    if (useTagWeight) {
      valueToAdd *= record.tags.length;
    }
    aggregatedByDay.update(dateTime,
        (tsr) => DateTimeSeriesRecord(dateTime, tsr.value + valueToAdd),
        ifAbsent: () => DateTimeSeriesRecord(dateTime, valueToAdd));
  }
  List<DateTimeSeriesRecord> data = aggregatedByDay.values.toList();
  data.sort((a, b) => a.value.compareTo(b.value));
  return data;
}

List<Record?> aggregateRecordsByDateAndCategory(
    List<Record?> records, AggregationMethod? aggregationMethod) {
  /// Record Day 1: 100 euro Food, 20 euro Food, 30 euro Transport
  /// Record Day 1: 120 euro food, 30 euro transports.
  /// Available grouping: by day, month, year.
  if (aggregationMethod == AggregationMethod.NOT_AGGREGATED)
    return records; // don't aggregate
  List<Record?> newAggregatedRecords = [];
  Map<DateTime?, List<Record?>> mapDateTimeRecords = groupBy(records,
      (Record? obj) => truncateDateTime(obj!.dateTime, aggregationMethod));
  for (var recordsByDatetime in mapDateTimeRecords.entries) {
    Map<String?, List<Record?>> mapRecordsCategory =
        groupBy(recordsByDatetime.value, (Record? obj) => obj!.category!.name);
    for (var recordsSameDateTimeSameCategory in mapRecordsCategory.entries) {
      Record? aggregatedRecord;
      if (recordsSameDateTimeSameCategory.value.length > 1) {
        Category category = recordsSameDateTimeSameCategory.value[0]!.category!;
        var value = recordsSameDateTimeSameCategory.value.fold(0,
            (dynamic previousValue, element) => previousValue + element!.value);
        aggregatedRecord = Record(value, category.name, category,
            truncateDateTime(recordsByDatetime.key!, aggregationMethod));
        aggregatedRecord.aggregatedValues =
            recordsSameDateTimeSameCategory.value.length;
      } else {
        aggregatedRecord = recordsSameDateTimeSameCategory.value[0];
      }
      newAggregatedRecords.add(aggregatedRecord);
    }
  }
  return newAggregatedRecords;
}

// Tag equivalent of aggregateRecordsByDateAndCategory
List<Record?> aggregateRecordsByDateAndTag(
    List<Record?> records, AggregationMethod? aggregationMethod, String tag) {
  /// Same pattern as aggregateRecordsByDateAndCategory but groups by tag instead of category
  if (aggregationMethod == AggregationMethod.NOT_AGGREGATED)
    return records; // don't aggregate

  List<Record?> newAggregatedRecords = [];
  Map<DateTime?, List<Record?>> mapDateTimeRecords = groupBy(records,
      (Record? obj) => truncateDateTime(obj!.dateTime, aggregationMethod));

  for (var recordsByDatetime in mapDateTimeRecords.entries) {
    Map<String?, List<Record?>> mapRecordsTag = groupBy(recordsByDatetime.value,
        (Record? obj) => obj!.tags.contains(tag) ? tag : null);

    for (var recordsSameDateTimeSameTag in mapRecordsTag.entries) {
      if (recordsSameDateTimeSameTag.key == null)
        continue; // Skip records without the tag

      Record? aggregatedRecord;
      if (recordsSameDateTimeSameTag.value.length > 1) {
        // Use the category from the first record for the aggregated record
        Category? category = recordsSameDateTimeSameTag.value[0]!.category;
        var value = recordsSameDateTimeSameTag.value.fold(0,
            (dynamic previousValue, element) => previousValue + element!.value);
        // Use category name as title instead of tag for better display
        String? title = category?.name ?? tag;
        aggregatedRecord = Record(value, title, category,
            truncateDateTime(recordsByDatetime.key!, aggregationMethod));
        aggregatedRecord.tags = {tag};
        aggregatedRecord.aggregatedValues =
            recordsSameDateTimeSameTag.value.length;
      } else {
        aggregatedRecord = recordsSameDateTimeSameTag.value[0];
      }
      newAggregatedRecords.add(aggregatedRecord);
    }
  }
  return newAggregatedRecords;
}

int getColorSortValue(Color color) {
  int red = (color.r * 255).toInt();
  int green = (color.g * 255).toInt();
  int blue = (color.b * 255).toInt();
  return (red << 16) | (green << 8) | blue;
}

DateTime getEndOfInterval(
    DateTime start, AggregationMethod? aggregationMethod) {
  switch (aggregationMethod!) {
    case AggregationMethod.DAY:
      return DateTime(start.year, start.month, start.day, 23, 59, 59);
    case AggregationMethod.WEEK:
      // Calculate the end of the week bin (1-7, 8-14, 15-21, 22-28, 29-end)
      // based on the start day, matching truncateDateTime bins
      int endDay;
      int startDay = start.day;
      if (startDay == 1) {
        endDay = 7;
      } else if (startDay == 8) {
        endDay = 14;
      } else if (startDay == 15) {
        endDay = 21;
      } else if (startDay == 22) {
        endDay = 28;
      } else {
        // Day 29+ — last partial bin to end of month
        endDay = DateTime(start.year, start.month + 1, 0).day;
      }
      return DateTime(start.year, start.month, endDay, 23, 59, 59);
    case AggregationMethod.MONTH:
      return getEndOfMonth(start.year, start.month);
    case AggregationMethod.YEAR:
      return DateTime(start.year, 12, 31, 23, 59, 59);
    case AggregationMethod.NOT_AGGREGATED:
      return start;
  }
}

AggregationMethod getAggregationMethodGivenTheTimeRange(
    DateTime from, DateTime to) {
  Duration difference = to.difference(from);
  if (difference.inDays <= 7) {
    return AggregationMethod.DAY;
  } else if (difference.inDays <= 35) {
    // Increased slightly to handle 5-week months
    return AggregationMethod.WEEK;
  } else if (from.year != to.year) {
    return AggregationMethod.YEAR;
  } else {
    return AggregationMethod.MONTH;
  }
}

/// Configuration for chart date ranges and formatting.
/// Shared between bar-chart and balance-chart to ensure consistent behavior.
class ChartDateRangeConfig {
  final DateTime start;
  final DateTime end;
  final DateFormat formatter;
  final String scopeLabel;
  final AggregationMethod aggregationMethod;

  ChartDateRangeConfig._({
    required this.start,
    required this.end,
    required this.formatter,
    required this.scopeLabel,
    required this.aggregationMethod,
  });

  factory ChartDateRangeConfig.create(
    AggregationMethod method,
    DateTime? from,
    DateTime? to,
  ) {
    switch (method) {
      case AggregationMethod.DAY:
        // Truncate dates to midnight to ensure full day ranges
        final startDate = DateTime(from!.year, from.month, from.day);
        final endDate = DateTime(to!.year, to.month, to.day);
        final ts = TartessosDate(startDate);
        final te = TartessosDate(endDate);
        return ChartDateRangeConfig._(
          formatter: DateFormat("dd"),
          start: startDate,
          end: endDate,
          scopeLabel: "${ts.month}/${ts.day}-${te.month}/${te.day}",
          aggregationMethod: method,
        );

      case AggregationMethod.WEEK:
        final startDate = DateTime(from!.year, from.month);
        final endDate = DateTime(
            from.year, from.month + 1, 0, 23, 59, 59); // Last day of month
        final t = TartessosDate(startDate);
        return ChartDateRangeConfig._(
          formatter: DateFormat("'W'w"),
          start: startDate,
          end: endDate,
          scopeLabel: "${t.year}/${t.month}",
          aggregationMethod: method,
        );

      case AggregationMethod.MONTH:
        final DateTime fromDate = from!;
        final DateTime toDate = to!;
        final endDate =
            DateTime(toDate.year, 12, 31, 23, 59, 59); // Last day of December
        return ChartDateRangeConfig._(
          formatter: DateFormat("MM"),
          start: DateTime(fromDate.year),
          end: endDate,
          scopeLabel: "${TartessosDate(fromDate).year}",
          aggregationMethod: method,
        );

      case AggregationMethod.YEAR:
        final DateTime fromDate2 = from!;
        final DateTime toDate2 = to!;
        final endDate2 = DateTime(
            toDate2.year, 12, 31, 23, 59, 59); // Last day of last year
        return ChartDateRangeConfig._(
          formatter: DateFormat("yyyy"),
          start: DateTime(fromDate2.year),
          end: endDate2,
          scopeLabel:
              "${TartessosDate(fromDate2).year} - ${TartessosDate(toDate2).year}",
          aggregationMethod: method,
        );

      default:
        throw ArgumentError('Unknown aggregation method: $method');
    }
  }

  /// Generates a key for a given date based on the aggregation method.
  /// Used for data aggregation and lookup AND para el texto del tick del
  /// eje — ver tartessosChartLabel() para por qué están unificados.
  String getKey(DateTime date) {
    return tartessosChartLabel(date, aggregationMethod);
  }

  /// Advances a date by one period based on the aggregation method.
  DateTime advance(DateTime current) {
    switch (aggregationMethod) {
      case AggregationMethod.DAY:
        return current.add(Duration(days: 1));
      case AggregationMethod.WEEK:
        return current.add(Duration(days: 7));
      case AggregationMethod.MONTH:
        return DateTime(current.year, current.month + 1);
      case AggregationMethod.YEAR:
        return DateTime(current.year + 1);
      default:
        return current.add(Duration(days: 1));
    }
  }

}

/// Generates tick labels for chart axes.
/// Shared between bar-chart and balance-chart to ensure consistent tick display.
class ChartTickGenerator {
  /// Generates X-axis tick labels for DAY aggregation with month boundaries.
  /// Shows month boundaries with M/D format (e.g., "2/20") and other days as just day numbers.
  static List<String> generateDayTicks(DateTime start, DateTime end) {
    final int days = end.difference(start).inDays + 1;
    final int jump = max(1, (days / 12).ceil());

    final List<String> ticks = [];
    DateTime current = start;

    while (!current.isAfter(end)) {
      ticks.add(tartessosChartLabel(current, AggregationMethod.DAY));
      current = current.add(Duration(days: jump));
    }

    // Ensure end date is always shown
    final String endLabel = tartessosChartLabel(end, AggregationMethod.DAY);
    if (ticks.last != endLabel) {
      ticks.add(endLabel);
    }

    return ticks;
  }

  /// Generic tick generator for all aggregation methods.
  static List<String> generateTicks(ChartDateRangeConfig config) {
    List<String> ticks;
    switch (config.aggregationMethod) {
      case AggregationMethod.DAY:
        ticks = generateDayTicks(config.start, config.end);
        break;

      case AggregationMethod.WEEK:
        ticks = _generateWeekTicks(config.start, config.end);
        break;

      case AggregationMethod.MONTH:
        ticks = _generateMonthTicks(config.start, config.end);
        break;

      case AggregationMethod.YEAR:
        ticks = _generateYearTicks(config.start, config.end);
        break;

      default:
        ticks = [];
    }
    return ticks;
  }

  static List<String> _generateWeekTicks(DateTime start, DateTime end) {
    final List<String> ticks = [];
    DateTime current = start;
    while (!current.isAfter(end)) {
      ticks.add(tartessosChartLabel(current, AggregationMethod.WEEK));
      current = current.add(Duration(days: 7));
    }
    return ticks;
  }

  static List<String> _generateMonthTicks(DateTime start, DateTime end) {
    final List<String> ticks = [];
    DateTime current = start;
    while (!current.isAfter(end)) {
      ticks.add(tartessosChartLabel(current, AggregationMethod.MONTH));
      current = DateTime(current.year, current.month + 1);
    }
    return ticks;
  }

  static List<String> _generateYearTicks(DateTime start, DateTime end) {
    final List<String> ticks = [];
    DateTime current = start;
    while (!current.isAfter(end)) {
      ticks.add(tartessosChartLabel(current, AggregationMethod.YEAR));
      current = DateTime(current.year + 1);
    }
    return ticks;
  }
}
