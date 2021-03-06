#!/usr/bin/env ruby

require_relative 'command'

class DashboardsUsingMetrics < Command
  def parse_args(options, parser)
    parser.banner = "Usage: #{$0} [options] <metric>\n"+
                    "Example: #{$0} 'system.load.1'"

    options[:is_regex] = false
    options[:file] = nil

    parser.on('-r', '--[no-]regex', 'Input is a regular expression (don\'t quote)') do |v|
      options[:is_regex] = v
    end

    parser.on('-fFILE', '--file=FILE', String, 'File to store queries') do |v|
      options[:file] = File.new(v, 'a')
    end
  end

  def metric_regex(metric)
    if @options[:is_regex]
      /#{metric}/
    else
      /#{Regexp.quote(metric)}/
    end
  end

  def find_dashboard_graphs(definition, regex)
    definition.fetch('dash', {}).fetch('graphs', []).reduce([]) do |acc, graph|
      queries = graph.fetch('definition', {}).fetch('requests', []).reduce([]) do |acc2, request|
        next acc2 unless request.key?('q') || !request['q'].respond_to?(:to_str)
        next acc2 unless request['q'] =~ regex

        acc2 + [request['q']]
      end

      next acc unless queries.length > 0

      acc + [{
        title: graph.fetch('title', 'Unknown'),
        queries: queries
      }]
    end
  end

  def find_screenboard_graphs(definition, regex)
    definition.fetch('widgets', []).reduce([]) do |acc, widget|
      queries = widget.fetch('tile_def', {}).fetch('requests', []).reduce([]) do |acc2, request|
        next acc2 unless request.key?('q') || !request['q'].respond_to?(:to_str)
        next acc2 unless request['q'] =~ regex

        acc2 + [request['q']]
      end

      next acc unless queries.length > 0

      acc + [{
        title: widget.fetch('title_text', 'Unknown'),
        queries: queries
      }]
    end
  end

  def print_dashboard_matches(metric)
    regex = metric_regex(metric)
    @logger.info("Looking for dashboards using metric: #{regex.inspect}")
    _, dashes = with_retries { @dog_client.get_dashboards() }
    each_with_status_and_delay(
      dashes['dashes'],
      template: '%{title} (#%{id})...',
    ) do |dash|
      status_code, definition = with_retries { @dog_client.get_dashboard(dash['id']) }

      if status_code != '200'
        @logger.warn("Got status code #{status_code} querying dashboard #{dash['id']}")
        next
      end

      found = find_dashboard_graphs(definition, regex)

      if found.length > 0
        url = template('dashboard', id: dash['id'])

        @logger.info "Found: #{dash['title']} - #{url}"
        found.each do |graph|
          @logger.debug "  #{graph[:title]}"
          graph[:queries].each do |query|
            @logger.debug "    #{query}"
            if @options[:file]
              @options[:file].puts(query)
              @options[:file].flush
            end
          end
        end

        @logger.debug ""
      end
    end
  end

  def print_screenboard_matches(metric)
    regex = metric_regex(metric)
    @logger.info("Looking for screenboards using metric: #{regex.inspect}")
    _, screens = with_retries { @dog_client.get_all_screenboards() }

    each_with_status_and_delay(
      screens['screenboards'],
      template: '%{title}: (#%{id})...'
    ) do |screen|
      status_code, definition = with_retries { @dog_client.get_screenboard(screen['id']) }

      if status_code != '200'
        @logger.warn("Got status code #{status_code} querying dashboard #{dash['id']}")
        next
      end

      found = find_screenboard_graphs(definition, regex)

      if found.length > 0
        url = template('screenboard', id: screen['id'])

        @logger.info "Found: #{screen['title']} - #{url}"
        found.each do |graph|
          @logger.debug "  #{graph[:title]}"
          graph[:queries].each do |query|
            @logger.debug "    #{query}"
            if @options[:file]
              @options[:file].puts(query)
              @options[:file].flush
            end
          end
        end

        @logger.debug ""
      end
    end
  end

  def run()
    super do
      raise ArgumentError.new("You must specify a metric name!") unless @args.length > 0
    end

    metric = @args[0]

    print_dashboard_matches(metric)
    print_screenboard_matches(metric)
  end
end

DashboardsUsingMetrics.new().run()
