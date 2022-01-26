require "time"
require "concurrent-ruby"

require_relative "../dto/target"
require_relative "../../sdk/version"
require_relative "../common/closeable"
require_relative "../api/summary_metrics"

class MetricsProcessor < Closeable

  def initialize(

    connector,
    config,
    callback
  )

    unless connector.kind_of?(Connector)

      raise "The 'connector' must be of '" + Connector.to_s + "' data type"
    end

    unless callback.kind_of?(MetricsCallback)

      raise "The 'callback' must be of '" + MetricsCallback.to_s + "' data type"
    end

    unless config.kind_of?(Config)

      raise "The 'config' must be of '" + Config.to_s + "' data type"
    end

    @config = config
    @callback = callback
    @connector = connector

    @sdk_type = "SDK_TYPE"
    @global_target_set = Set[]
    @staging_target_set = Set[]
    @target_attribute = "target"
    @global_target = "__global__cf_target" # <--- This target identifier is used to aggregate and send data for all
    #                                             targets as a summary

    @jar_version = ""
    @server = "server"
    @sdk_version = "SDK_VERSION"
    @sdk_language = "SDK_LANGUAGE"
    @global_target_name = "Global Target"
    @feature_name_attribute = "featureName"
    @variation_identifier_attribute = "variationIdentifier"

    @queue = SizedQueue.new(@config.buffer_size)
    @executor = Concurrent::FixedThreadPool.new(100)

    @callback.on_metrics_ready
  end

  def start

    puts "Starting MetricsProcessor with request interval: " + @config.frequency.to_s
    start_async
  end

  def stop

    puts "Stopping MetricsProcessor"
    stop_async
  end

  def close

    stop
    puts "Closing MetricsProcessor"
  end

  def push_to_queue(

    target,
    feature_config,
    variation
  )

    @executor.post do

      puts "Pushing to the metrics queue"

      event = MetricsEvent.new(feature_config, target, variation)
      @queue.push(event)
    end
  end

  def send_data_and_reset_cache(data)

    puts "Reading from queue and building cache"

    @jar_version = get_version

    unless data.empty?

      map = {}

      data.each do |event|

        new_value = 1
        current = map[event]

        if current != nil

          new_value = current + 1
        end

        map[event] = new_value
      end

      metrics = prepare_summary_metrics_body(map)

      if !metrics.metrics_data.empty? && !metrics.target_data.empty?

        start_time = (Time.now.to_f * 1000).to_i

        @connector.post_metrics(metrics)

        end_time = (Time.now.to_f * 1000).to_i

        if end_time - start_time > @config.metrics_service_acceptable_duration

          puts "Metrics service API duration=[" + (end_time - start_time).to_s + "]"
        end
      end

      @global_target_set.merge(@staging_target_set)
      @staging_target_set.clear
    end
  end

  protected

  def run_one_iteration

    puts "Async metrics iteration"

    data = []

    @queue.each do |item|

      data.push(item)
    end

    @queue.clear

    send_data_and_reset_cache(data)
  end

  def prepare_summary_metrics_body(data)

    summary_metrics_data = {}
    metrics = OpenapiClient::Metrics.new

    add_target_data(

      metrics,
      Target.new(

        name = @global_target_name,
        identifier = @global_target
      )
    )

    data.each do |key, value|

      target = key.target

      add_target_data(metrics, target)

      summary_metrics = prepare_summary_metrics_key(key)

      summary_metrics_data[summary_metrics] = value
    end

    summary_metrics_data.each do |key, value|

      metrics_data = OpenapiClient::MetricsData.new
      metrics_data.timestamp = (Time.now.to_f * 1000).to_i
      metrics_data.count = value
      metrics_data.metrics_type = "FFMETRICS"
      metrics_data.attributes.push(OpenapiClient::KeyValue.new({ @feature_name_attribute => key.feature_name }))
      metrics_data.attributes.push(OpenapiClient::KeyValue.new({ @variation_identifier_attribute => key.variation_identifier }))
      metrics_data.attributes.push(OpenapiClient::KeyValue.new({ @target_attribute => @global_target }))
      metrics_data.attributes.push(OpenapiClient::KeyValue.new({ @sdk_type => @server }))
      metrics_data.attributes.push(OpenapiClient::KeyValue.new({ @sdk_language => "ruby" }))
      metrics_data.attributes.push(OpenapiClient::KeyValue.new({ @sdk_version => @jar_version }))

      metrics.metrics_data.push(metrics_data)
    end

    metrics
  end

  private

  def start_async

    puts "Async starting: " + self.to_s

    @ready = true

    @thread = Thread.new do

      puts "Async started: " + self.to_s

      while @ready do

        unless @initialized

          @initialized = true
          puts "MetricsProcessor initialized"
        end

        sleep(@config.frequency)

        run_one_iteration
      end

      @thread.run
    end
  end

  def stop_async

    @ready = false
    @initialized = false
  end

  def prepare_summary_metrics_key(key)

    SummaryMetrics.new(

      feature_name = key.feature_config.feature,
      variation_identifier = key.variation.identifier,
      variation_value = key.variation.value
    )
  end

  def add_target_data(metrics, target)

    target_data = OpenapiClient::TargetData.new
    private_attributes = target.private_attributes

    if !@staging_target_set.include?(target) && !@global_target_set.include?(target) && !target.is_private

      @staging_target_set.add(target)

      attributes = target.attributes

      attributes.each do |k, v|

        key_value = OpenapiClient::KeyValue.new

        if !private_attributes.empty?

          unless private_attributes.include?(k)

            key_value = OpenapiClient::KeyValue.new({ k => v.to_s })
          end
        else

          key_value = OpenapiClient::KeyValue.new({ k => v.to_s })
        end

        target_data.attributes.push(key_value)
      end

      target_data.identifier = target.identifier

      if target.name == nil || target.name == ""

        target_data.name = target.identifier
      else

        target_data.name = target.name
      end

      metrics.target_data.push(target_data)
    end
  end

  def get_version

    Ff::Ruby::Server::Sdk::VERSION
  end
end
