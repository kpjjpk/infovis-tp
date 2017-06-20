#!/usr/bin/ruby

require "pry"
require "csv"
require "fileutils"
require "table_print"

require_relative "../src/script_params"
require_relative "../src/wind_reading"
require_relative "../src/chem_reading"
require_relative "../src/factory"
require_relative "../src/chem_monitor"
require_relative "../src/position"
require_relative "../src/dates"

def read_rows(klass)
  -> (file_name) do
    _headers, *rows = CSV.read(file_name)
    klass.all_from(rows)
  end
end

params = ScriptParams.read!(
  {
    name: "chem",
    attr: "chem_readings",
    cast: read_rows(ChemReading)
  },
  {
    name: "lookback-secs",
    attr: "lookback",
    cast: :to_i
  },
  {
    name: "winds",
    attr: "wind_readings",
    cast: read_rows(WindReading)
  },
  {
    name: "range",
    attr: "acceptable_range",
    cast: :to_f
  },
  {
    name: "factories",
    cast: read_rows(Factory)
  },
  {
    name: "monitors",
    attr: "chem_monitors",
    cast: read_rows(ChemMonitor)
  }
)

class ChemTracer
  MANDATORY_PARAMS = %i[
    chem_readings lookback wind_readings factories chem_monitors acceptable_range
  ].freeze

  attr_reader *MANDATORY_PARAMS

  def initialize(**kwargs)
    MANDATORY_PARAMS.each do |mandatory_param|
      instance_variable_set("@#{mandatory_param}", kwargs.fetch(mandatory_param))
    end
  end

  def trace
    factories_and_emission_counts = factories.map do |factory|
      FactoryAndEmissionsCount.new(factory, emission_counts(factory))
    end
    factories_and_emission_counts.sort_by(&:emissions_count).reverse
  end

  private

  def emission_counts(factory)
    factory_range = CircularRange.new(factory, acceptable_range)
    emission_origins.count { |emission_origin| factory_range.include? emission_origin }
  end

  def emission_origins
    @emission_origins ||= wind_periods.flat_map do |wind_period|
      wind_period.chem_readings.map do |chem_reading|
        if wind_period.duration < lookback
          raise "Unsupported lookback #{lookback} secs for a period of #{wind_period.duration} secs"
        end

        EmissionOrigin.from(
          chem_monitor: chem_monitors_by_id[chem_reading.monitor_id],
          chem_reading: chem_reading,
          wind_reading: wind_period.wind_reading,
          lookback:     lookback
        )
      end
    end
  end

  def chem_monitors_by_id
    @chem_monitors_by_id ||= chem_monitors.each_with_object({}) do |chem_monitor, result|
      result[chem_monitor.id] ||= chem_monitor
    end
  end

  def wind_periods
    @wind_periods ||= WindPeriod.all_from(wind_readings, chem_readings)
  end

  class WindPeriod < Struct.new(:wind_reading, :duration, :chem_readings)
    class << self
      def all_from(wind_readings, chem_readings)
        wind_readings      = wind_readings.sort
        wind_reading_pairs = wind_readings.each_slice(2)

        wind_reading_pairs.map do |wind_readings_pair|
          wind_reading_times  = wind_readings_pair.map(&:date_time)
          wind_readings_range = wind_reading_times.first...wind_reading_times.last

          new(
            wind_reading:  wind_readings_pair.first,
            duration:      Dates.seconds_between(*wind_reading_times),
            chem_readings: readings_within(wind_readings_range, chem_readings)
          )
        end
      end

      private

      def readings_within(time_range, readings)
        readings.select { |reading| time_range.include? reading.date_time }
      end
    end

    # TODO: move elsewhere!
    def initialize(*params, **kwargs)
      super(params)
      kwargs.each { |(k, value)| send("#{k}=", value) }
    end
  end

  class EmissionOrigin < Struct.new(:position, :date_time)
    extend Forwardable

    def_delegators :position, *%i[x y distance_to]

    def self.from(chem_monitor:, chem_reading:, wind_reading:, lookback:)
      new(
        position:  wind_reading.origin(chem_monitor.position, lookback),
        date_time: chem_reading.date_time - lookback
      )
    end

    # TODO: move elsewhere!
    def initialize(*params, **kwargs)
      super(params)
      kwargs.each { |(k, value)| send("#{k}=", value) }
    end
  end

  class CircularRange < Struct.new(:center, :radius)
    def include?(position)
      position.distance_to(center) <= radius
    end
  end

  FactoryAndEmissionsCount = Struct.new(:factory, :emissions_count)
end

chem_tracings = ChemTracer.new(**params).trace

tp(
  chem_tracings,
  { "factory"     => -> (chem_tracing) { chem_tracing.factory.name } },
  { "emissions #" => -> (chem_tracing) { chem_tracing.emissions_count } }
)
