#!/usr/bin/ruby

require "pry"
require "csv"
require "fileutils"

require_relative "../src/script_params"
require_relative "../src/chem_reading"

params = ScriptParams.read!(
  {
    name:      "from",
    attr:      "input_file"
  },
  {
    name:      "runs",
    long_name: "Max refining runs",
    attr:      "max_refining_runs",
    default:   2,
    cast:      :to_i
  },
  {
    name:      "output-dir",
    default:   "data/processed/chems"
  },
  {
    name:      "atypical-stddevs",
    long_name: "StdDevs to be atypical",
    default:   1,
    cast:      :to_i
  }
)

INPUT_FILE             = params.fetch(:input_file)
OUTPUT_DIR             = params.fetch(:output_dir)
MAX_REFINING_RUNS      = params.fetch(:max_refining_runs)
STDDEVS_TO_BE_ATYPICAL = params.fetch(:atypical_stddevs)

class DataRefiner
  def refine(path)
    csv_headers, *csv_rows = CSV.read(path)
    readings               = ChemReading.all_from(row)
    readings_by_chemical   = readings.group_by(&:chemical)

    readings_by_chemical.each do |(_, readings_for_chemical)|
      refined_readings_for_chemical = refine_readings(readings_for_chemical)
      errored_readings_for_chemical = refine_readings(refined_readings_for_chemical.atypical).atypical
      refined_readings_for_chemical.atypical -= errored_readings_for_chemical

      store_readings_for_chemical(csv_headers, refined_readings_for_chemical, errored_readings_for_chemical)
      print "."
    end

    print "\n"
  end

  private

  def refine_readings(readings)
    prev_readings = readings = RefinedReadings.from(readings)
    return readings if readings.atypical.empty?

    (MAX_REFINING_RUNS - 1).times do
      prev_readings = readings
      readings      = RefinedReadings.from(readings)
      return readings if readings.atypical.count == prev_readings.atypical.count
    end
    readings
  end

  def store_readings_for_chemical(headers, valid_readings, errored_readings)
    %i[normal atypical errored].each do |reading_type|
      file_name = "#{OUTPUT_DIR}/#{valid_readings.chemical.downcase}-#{reading_type}.csv"

      CSV.open(file_name, "w") do |csv_file|
        csv_file << headers

        sorted_readings =
          if reading_type == :errored
            errored_readings
          else
            valid_readings.public_send(reading_type).sort
          end

        sorted_readings.each { |reading| csv_file << reading.to_a }
      end
    end
  end

  RefinedReadings = Struct.new(:normal, :atypical) do
    class << self
      def from(readings)
        case readings
        when Array
          from_array(readings)
        when RefinedReadings
          from_refined(readings)
        end
      end

      def from_array(readings)
        readings_stats        = Stats.from(readings, :value)
        readings_by_normality = readings.group_by { |reading| readings_stats.normal?(reading.value) }

        new(
          normal:   readings_by_normality.fetch(true, []),
          atypical: readings_by_normality.fetch(false, [])
        )
      end

      def from_refined(readings)
        refined_readings = from_array(readings.normal)

        new(
          normal:   refined_readings.normal,
          atypical: refined_readings.atypical + readings.atypical
        )
      end
    end

    def initialize(**kwargs)
      super(*members.map { |attr| kwargs.fetch(attr) })
    end

    def chemical
      return unless reading = (normal.first || atypical.first)
      reading.chemical
    end
  end

  Stats = Struct.new(:avg, :stddev) do
    class << self
      def from(values, attr = nil)
        values  = values.map(&attr) if attr
        average = avg(values)
        new(average, stddev(values, average))
      end

      def sum(values, &block)
        block ||= Proc.new { |value| value }
        values.inject(0) { |result, value| result + block[value] }
      end

      def avg(values)
        return 0.0 if values.empty?
        sum(values) / values.length.to_f
      end

      def stddev(values, average = nil)
        return 0.0 if values.length <= 1
        average ||= avg(values)

        values_sum = sum(values) { |value| (value - average)**2 }
        Math.sqrt(values_sum / values.length.to_f)
      end
    end

    def normal?(value)
      (value - avg).abs <= stddev * STDDEVS_TO_BE_ATYPICAL
    end
  end
end

FileUtils.mkdir_p OUTPUT_DIR
DataRefiner.new.refine(INPUT_FILE)